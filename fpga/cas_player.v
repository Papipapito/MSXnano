// ============================================================================
// cas_player - Reproductor de cinta virtual MSX (modulador KCS) para FPGA.
//
// Genera la senal digital de ENTRADA de cassette (CMTIN) que en un MSX se lee
// por el bit 7 del port A del PSG (registro 14, I/O 0xA2). Alimentando esta
// senal, la BIOS REAL carga cualquier juego de cinta (CAS/TSX) sin hacks:
// RUN"CAS:", BLOAD"CAS:", cargadores de bloques crudos... todo funciona.
//
// Codificacion KCS del MSX (1200 baudios, valores en T-states del Z80):
//   pulso (medio ciclo) "one"=731  (~204us) ; "zero"=1463 (~408us) = 2x one
//   bit "1" = 4 pulsos "one"  ; bit "0" = 2 pulsos "zero" ; piloto = "one" continuos
//   byte    = start(0) + 8 datos (LSB primero) + 2 stop(1)
//
// RELOJ: clk = reloj global (clk_54m) ; ce = clock-enable a ritmo de T-state
//        del Z80 (clk_enable_3m6_54). El FSM avanza 1 paso por 'ce', asi que
//        los contadores de pulso estan en T-states (PULSE_ONE=731).
//
// Imagen de cinta (formato CVT1, la genera tape_image.py) en memoria por byte:
//   [0..3] "CVT1"  [4..5] num_blocks(LE)
//   [6..]  num_blocks x descriptor de 4B: len(2 LE) + pilot(1:1=largo) + pad
//   luego  payloads concatenados en orden de bloque.
// ============================================================================
module cas_player #(
    parameter ADDRW       = 20,
    parameter PULSE_ONE   = 16'd731,
    parameter PULSE_ZERO  = 16'd1463,
    parameter PILOT_LONG  = 16'd8000,
    parameter PILOT_SHORT = 16'd3000
)(
    input  wire             clk,        // reloj global (clk_54m)
    input  wire             ce,         // clock-enable = 1 T-state del Z80
    input  wire             rst,        // reset sincrono activo-alto (=~bus_reset_n)
    input  wire             motor,      // gate de reproduccion (ya en activo-alto)
    input  wire             load,       // arma/rebobina por FLANCO de subida
    output reg  [ADDRW-1:0] mem_addr,
    input  wire [7:0]       mem_data,
    output reg              casin,      // -> PSG port A bit 7
    output wire             playing
);
    localparam S_IDLE=0, S_RD=1, S_NB0=2, S_NB1=3,
               S_DL0=4, S_DL1=5, S_DPIL=6,
               S_PILOT=7, S_BYTE=8, S_BITSET=9, S_EMIT=10, S_DONE=11;

    reg [3:0]        st, rst_ret;
    reg [15:0]       nblk, blk;
    reg [ADDRW-1:0]  dptr, pptr;
    reg [15:0]       blen, bidx;
    reg [7:0]        cbyte;
    reg [3:0]        biti;
    reg [15:0]       pilcnt;
    reg              pillong;
    reg [15:0]       pulses;
    reg [15:0]       plen, ptmr;
    reg [3:0]        emit_ret;
    reg              load_prev;

    assign playing = (st != S_IDLE) && (st != S_DONE);
    wire load_edge = load & ~load_prev;

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; casin <= 1'b1; mem_addr <= 0; load_prev <= 1'b0;
        end else if (ce) begin
            load_prev <= load;
            if (load_edge) begin
                st <= S_RD; rst_ret <= S_NB0; mem_addr <= 4; casin <= 1'b1;
            end else case (st)
            S_IDLE:  casin <= 1'b1;
            S_RD:    st <= rst_ret;
            S_NB0: begin nblk[7:0] <= mem_data;
                         mem_addr <= 5; rst_ret <= S_NB1; st <= S_RD; end
            S_NB1: begin nblk[15:8] <= mem_data;
                         blk <= 0; dptr <= 6;
                         pptr <= 6 + ({mem_data, nblk[7:0]} << 2);
                         st <= S_DL0; end
            S_DL0: if (blk >= nblk) st <= S_DONE;
                   else begin mem_addr <= dptr; rst_ret <= S_DL1; st <= S_RD; end
            S_DL1: begin blen[7:0] <= mem_data;
                         mem_addr <= dptr+1; rst_ret <= S_DPIL; st <= S_RD; end
            S_DPIL:begin blen[15:8] <= mem_data;
                         mem_addr <= dptr+2; rst_ret <= S_PILOT; st <= S_RD; end
            S_PILOT: begin
                pillong <= mem_data[0];
                pulses  <= mem_data[0] ? PILOT_LONG : PILOT_SHORT;
                plen    <= PULSE_ONE; ptmr <= PULSE_ONE;
                dptr    <= dptr + 4; bidx <= 0;
                emit_ret<= S_BYTE; st <= S_EMIT;
            end
            S_BYTE: begin
                if (bidx >= blen) begin blk <= blk + 1; st <= S_DL0; end
                else begin
                    mem_addr <= pptr; rst_ret <= S_BITSET; st <= S_RD;
                    pptr <= pptr + 1; bidx <= bidx + 1; biti <= 0;
                end
            end
            S_BITSET: begin
                if (biti == 0) cbyte <= mem_data;
                begin : mkbit
                    reg b;
                    if (biti == 0)      b = 1'b0;
                    else if (biti <= 8) b = (biti==1 ? mem_data[0] : cbyte[biti-1]);
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
