// ============================================================================
// cas_stream - Reproductor de cinta virtual MSX en modo STREAM (companion WiFi).
//
// Hermano de cas_player.v (que queda INTACTO: BSRAM validado en HW). El emisor
// KCS (S_BITSET/S_EMIT, timings PULSE_*) es copia literal del validado; cambia
// la FUENTE: en vez de memoria direccionable (mem_addr), consume un flujo
// SECUENCIAL por un handshake pop (FIFO alimentado por UART desde el ESP32-C6,
// ver tape_uart.v). No hay punteros: los descriptores van INLINE en el stream.
//
// Formato de stream CVS1 (lo genera el companion en el ORDEN exacto de consumo;
// tools/tsx_stream_sim/mkstream.py lo deriva de un .cvt para probar):
//   [0..3]  "CVS1"                        (magia; si no cuadra -> S_IDLE)
//   [4..5]  num_blocks (LE)
//   por bloque: len(2 LE) + pilot(1: bit0=1 piloto largo) + pad(1)
//               + payload (len bytes)
//
// Handshake pop (mismo protocolo que mem_req/mem_ready de cas_player, sin addr):
//   pop_req sube (nivel) -> el backend presenta pop_data y sube pop_valid ->
//   este FSM latchea y baja pop_req -> el backend baja pop_valid y avanza.
//
// RELOJ: identico a cas_player (clk global + ce a ritmo de T-state del Z80).
// ============================================================================
module cas_stream #(
    parameter PULSE_ONE   = 16'd731,
    parameter PULSE_ZERO  = 16'd1463,
    parameter PILOT_LONG  = 16'd8000,
    parameter PILOT_SHORT = 16'd3000
)(
    input  wire       clk,        // reloj global (clk_54m)
    input  wire       ce,         // clock-enable = 1 T-state del Z80
    input  wire       rst,        // reset sincrono activo-alto (=~bus_reset_n)
    input  wire       motor,      // gate de reproduccion (ya en activo-alto)
    input  wire       load,       // arma/rebobina por FLANCO de subida
    output reg        pop_req,    // pide el siguiente byte del stream (nivel)
    input  wire       pop_valid,  // el backend tiene pop_data valido
    input  wire [7:0] pop_data,
    output wire       flush,      // pulso en el load-edge: vaciar el FIFO fuente
    output reg        casin,      // -> PSG port A bit 7
    output wire       playing,
    output wire [3:0] dbg_st
);
    localparam S_IDLE=0, S_RD=1, S_MAGIC=2, S_NB0=3, S_NB1=4,
               S_DL0=5, S_DL1=6, S_DPIL=7, S_DPAD=8,
               S_PILOT=9, S_BYTE=10, S_BITSET=11, S_EMIT=12, S_DONE=13;

    reg [3:0]  st, rst_ret;
    reg [15:0] nblk, blk;
    reg [15:0] blen, bidx;
    reg [7:0]  cbyte;
    reg [3:0]  biti;
    reg        pilbit;
    reg [15:0] pulses;
    reg [15:0] plen, ptmr;
    reg [3:0]  emit_ret;
    reg        load_prev;
    reg [1:0]  mgi;                       // indice de la magia "CVS1"

    assign playing = (st != S_IDLE) && (st != S_DONE);
    assign dbg_st  = st;
    wire load_edge = load & ~load_prev;
    assign flush   = load_edge & ce;      // 1 pulso de clk (gated ce, como el FSM)

    // "CVS1" = 43 56 53 31
    function [7:0] magic_byte;
        input [1:0] i;
        case (i)
            2'd0: magic_byte = 8'h43;
            2'd1: magic_byte = 8'h56;
            2'd2: magic_byte = 8'h53;
            default: magic_byte = 8'h31;
        endcase
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; casin <= 1'b1; load_prev <= 1'b0;
            pop_req <= 1'b0; mgi <= 2'd0;
        end else if (ce) begin
            load_prev <= load;
            if (load_edge) begin
                st <= S_RD; rst_ret <= S_MAGIC; mgi <= 2'd0; casin <= 1'b1;
            end else case (st)
            S_IDLE:  casin <= 1'b1;
            // S_RD: pide el byte (pop_req) y espera pop_valid (latencia variable:
            // el FIFO puede estar vacio hasta que el companion mande mas datos).
            // pop_data queda valido al pasar a rst_ret (el backend lo mantiene).
            S_RD:    begin
                         pop_req <= 1'b1;
                         if (pop_valid) begin pop_req <= 1'b0; st <= rst_ret; end
                     end
            S_MAGIC: begin                 // 4 bytes "CVS1"; basura -> S_IDLE
                         if (pop_data != magic_byte(mgi)) st <= S_IDLE;
                         else if (mgi == 2'd3) begin rst_ret <= S_NB0; st <= S_RD; end
                         else begin mgi <= mgi + 2'd1; rst_ret <= S_MAGIC; st <= S_RD; end
                     end
            S_NB0: begin nblk[7:0] <= pop_data;
                         rst_ret <= S_NB1; st <= S_RD; end
            S_NB1: begin nblk[15:8] <= pop_data;
                         blk <= 0; st <= S_DL0; end
            S_DL0: if (blk >= nblk) st <= S_DONE;
                   else begin rst_ret <= S_DL1; st <= S_RD; end
            S_DL1: begin blen[7:0] <= pop_data;
                         rst_ret <= S_DPIL; st <= S_RD; end
            S_DPIL:begin blen[15:8] <= pop_data;
                         rst_ret <= S_DPAD; st <= S_RD; end
            S_DPAD:begin pilbit <= pop_data[0];      // byte pilot; el pad se lee y
                         rst_ret <= S_PILOT; st <= S_RD; end  // descarta en S_PILOT
            S_PILOT: begin                 // pop_data = pad (descartado)
                pulses  <= pilbit ? PILOT_LONG : PILOT_SHORT;
                plen    <= PULSE_ONE; ptmr <= PULSE_ONE;
                bidx    <= 0;
                emit_ret<= S_BYTE; st <= S_EMIT;
            end
            S_BYTE: begin
                if (bidx >= blen) begin blk <= blk + 1; st <= S_DL0; end
                else begin
                    rst_ret <= S_BITSET; st <= S_RD;
                    bidx <= bidx + 1; biti <= 0;
                end
            end
            // ---- emisor KCS: COPIA LITERAL de cas_player.v (validado en HW) ----
            S_BITSET: begin
                if (biti == 0) cbyte <= pop_data;
                begin : mkbit
                    reg b;
                    if (biti == 0)      b = 1'b0;
                    else if (biti <= 8) b = (biti==1 ? pop_data[0] : cbyte[biti-1]);
                    else                b = 1'b1;
                    if (b) begin plen <= PULSE_ONE;  ptmr <= PULSE_ONE;  pulses <= 4; end
                    else   begin plen <= PULSE_ZERO; ptmr <= PULSE_ZERO; pulses <= 2; end
                end
                emit_ret <= (biti >= 10) ? S_BYTE : S_BITSET;
                biti     <= biti + 1; st <= S_EMIT;
            end
            S_EMIT: begin
                if (motor) begin
                    if (ptmr <= 1) begin
                        casin <= ~casin; ptmr <= plen;
                        if (pulses <= 1) st <= emit_ret;
                        else pulses <= pulses - 1;
                    end else ptmr <= ptmr - 1;
                end
            end
            S_DONE: casin <= 1'b1;
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
