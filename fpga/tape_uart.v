// ============================================================================
// tape_uart - Fuente de stream para cas_stream: UART RX -> FIFO 2KB -> pop.
//
// El companion (ESP32-C6, UART1) manda el stream CVS1 a 115200 8N1 por un pin
// del FPGA. Este modulo lo recibe (sincronizador de 2 flops + FSM 8N1, patron
// kbd_uart_rx.v), lo guarda en un FIFO de 2KB (1 BSRAM) y lo sirve a
// cas_stream por el handshake pop_req/pop_valid/pop_data.
//
// FLOW CONTROL por NIVEL (pin RTR, activo-alto = "sigue mandando"):
//   - RTR baja cuando el FIFO pasa de FILL_STOP (3/4) y sube al bajar de
//     FILL_GO (1/4): histeresis para no aletear. El C6 lee RTR como GPIO y
//     gatea su TX por chunks. El consumo es ~110-120 B/s (ritmo cinta) y la
//     UART llena a ~11KB/s -> el FIFO se mantiene lleno y el motor parado
//     (pausas entre bloques) se maneja SOLO por el backpressure.
//   - Un byte que llegue con el FIFO lleno se DESCARTA (el C6 respeta RTR;
//     margen: tras bajar RTR caben 512 bytes mas).
//
// pop: mismo contrato que mem_req/mem_ready de cas_player: pop_req (nivel) ->
// cuando hay dato, pop_data valido + pop_valid=1 (se MANTIENEN hasta que
// pop_req baje); un solo pop por cada flanco de pop_req.
//
// Dominio UNICO clk (54MHz): el consumidor va gated por ce pero es el mismo
// reloj -> sin CDC. El unico asincrono es rx (2 flops).
// ============================================================================
module tape_uart #(
    parameter CLK_FREQ  = 54_000_000,
    parameter BAUD      = 115_200,
    parameter FILL_STOP = 11'd1536,     // RTR baja aqui (3/4 de 2KB)
    parameter FILL_GO   = 11'd512      // RTR sube al bajar de aqui (1/4)
)(
    input  wire       clk,
    input  wire       rst,             // reset sincrono activo-alto
    input  wire       rx,              // pin UART desde el C6 (asincrono)
    input  wire       flush,           // pulso: vaciar el FIFO (re-arme de cinta)
    input  wire       pop_req,         // desde cas_stream
    output reg        pop_valid,
    output reg  [7:0] pop_data,
    output wire       rtr,             // -> pin al C6: 1 = listo para recibir
    output wire [10:0] fill_dbg
);
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD;   // 54e6/115200 = 468
    localparam integer CNT_W = 16;

    // ---- sincronizador RX (2 flops, como kbd_uart_rx) ----
    (* syn_preserve = 1 *) reg rx_s1 = 1'b1;
    (* syn_preserve = 1 *) reg rx_s2 = 1'b1;
    always @(posedge clk) begin
        rx_s1 <= rx;
        rx_s2 <= rx_s1;
    end

    // ---- UART RX 8N1 (start re-muestreado a mitad de bit; LSB primero) ----
    localparam [1:0] RX_IDLE=2'd0, RX_START=2'd1, RX_DATA=2'd2, RX_STOP=2'd3;
    reg [1:0]        rxst = RX_IDLE;
    reg [CNT_W-1:0]  rxcnt = 0;
    reg [2:0]        rxbit = 0;
    reg [7:0]        rxsh  = 0;
    reg              rx_valid = 1'b0;
    reg [7:0]        rx_byte  = 0;

    always @(posedge clk) begin
        if (rst) begin
            rxst <= RX_IDLE; rx_valid <= 1'b0; rxcnt <= 0; rxbit <= 0;
        end else begin
            rx_valid <= 1'b0;
            case (rxst)
            RX_IDLE:  if (rx_s2 == 1'b0) begin rxcnt <= 0; rxst <= RX_START; end
            RX_START: if (rxcnt == CLKS_PER_BIT/2) begin
                          if (rx_s2 == 1'b0) begin rxcnt <= 0; rxbit <= 0; rxst <= RX_DATA; end
                          else rxst <= RX_IDLE;                    // falso start
                      end else rxcnt <= rxcnt + 1'b1;
            RX_DATA:  if (rxcnt == CLKS_PER_BIT-1) begin
                          rxcnt <= 0;
                          rxsh  <= {rx_s2, rxsh[7:1]};
                          if (rxbit == 3'd7) rxst <= RX_STOP;
                          else rxbit <= rxbit + 1'b1;
                      end else rxcnt <= rxcnt + 1'b1;
            RX_STOP:  if (rxcnt == CLKS_PER_BIT-1) begin
                          rxcnt <= 0; rxst <= RX_IDLE;
                          if (rx_s2 == 1'b1) begin                 // stop valido
                              rx_byte  <= rxsh;
                              rx_valid <= 1'b1;
                          end
                      end else rxcnt <= rxcnt + 1'b1;
            default:  rxst <= RX_IDLE;
            endcase
        end
    end

    // ---- FIFO 2048x8 (1 BSRAM) ----
    reg [7:0]  fifo [0:2047];
    reg [10:0] wp = 0, rp = 0;          // punteros de 11 bits (wrap natural en 2048
    wire [10:0] fill = wp - rp;         // con aritmetica modulo-2048 del indexado)
    wire full  = (fill >= 11'd2047);
    wire empty = (wp == rp);
    assign fill_dbg = fill;

    // ---- RTR con histeresis ----
    reg rtr_r = 1'b1;
    assign rtr = rtr_r;

    // ---- pop: servir UNA vez por flanco de pop_req ----
    reg served = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            wp <= 0; rp <= 0; rtr_r <= 1'b1;
            pop_valid <= 1'b0; served <= 1'b0; pop_data <= 8'h00;
        end else begin
            if (flush) begin
                // flush vacia el FIFO pero NO resetea la FSM del RX (otro always).
                // Es SEGURO porque flush solo pulsa cuando el C6 esta ocioso: se
                // dispara en el load-edge de cas_stream, que top.v genera al
                // arrancar y al terminar la cinta (S_DONE) — y la reproduccion
                // KCS es siempre MAS LENTA que la transmision UART (solo el
                // piloto ya dura >100ms al reproducir vs ~10ms al enviar), asi
                // que el C6 acabo de mandar mucho antes de que el FPGA llegue a
                // S_DONE. No hay byte a medio recibir que pudiera colarse en el
                // FIFO recien vaciado. (Revisado en la auditoria 2026-07; si algun
                // dia flush pudiera dispararse con el C6 transmitiendo, habria que
                // resetear tambien rxst aqui.)
                wp <= 0; rp <= 0; rtr_r <= 1'b1;
                pop_valid <= 1'b0; served <= 1'b0;
            end else begin
                // escritura desde la UART (descarta si lleno; el C6 respeta RTR).
                // Punteros de 11 bits con capacidad util 2047 (esquema un-hueco:
                // wp==rp solo puede ser "vacio" porque full para antes).
                if (rx_valid && !full) begin
                    fifo[wp] <= rx_byte;
                    wp <= wp + 11'd1;
                end
                // lectura hacia cas_stream
                if (pop_req && !served && !empty) begin
                    pop_data  <= fifo[rp];
                    rp        <= rp + 11'd1;
                    pop_valid <= 1'b1;
                    served    <= 1'b1;
                end
                if (!pop_req) begin
                    pop_valid <= 1'b0;
                    served    <= 1'b0;
                end
                // histeresis RTR
                if (fill >= FILL_STOP) rtr_r <= 1'b0;
                else if (fill <  FILL_GO) rtr_r <= 1'b1;
            end
        end
    end
endmodule
