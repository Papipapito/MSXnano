// ============================================================================
// tape_flash - Lector de la imagen de cinta (.cvt) desde la flash SPI, para
// juegos grandes (48-70KB) que no caben en BSRAM.
//
// Sirve las peticiones de cas_player (req/addr) leyendo 1 byte ALEATORIO de la
// flash en TAPE_BASE + addr, a traves del controlador flash_rw ya presente en
// el core. Como flash_rw esta orientado a lectura secuencial, para cada byte
// aleatorio: terminate -> reinit (rapido, STARTUP_WAIT=1) -> cmd(0x03)+addr+dato.
//
// La flash queda LIBRE tras el arranque (el streamer del pack acaba en IDLE),
// asi que en top.v se muxean addr/rd/terminate del controlador entre el
// streamer (durante boot) y este modulo (tras flash_idle) — sin tocar el FSM
// de arranque ni el controlador SDRAM.
//
// Presupuesto: 1200 baud => ~9ms por byte; una lectura SPI ~1.5us. Holgadisimo.
// El byte leido (data) se MANTIENE hasta la siguiente lectura, para que
// cas_player lo consuma con calma tras ver ready.
// ============================================================================
module tape_flash #(
    parameter [23:0] TAPE_BASE = 24'h300000,   // offset de la imagen en la flash
    parameter        ADDRW     = 20            // hasta 1MB de cinta
)(
    input  wire             clk,          // clk_54m
    input  wire             rst,          // sincrono activo-alto (=~bus_reset_n)
    // --- interfaz con cas_player (handshake req/ready) ---
    input  wire             req,          // pide un byte (nivel)
    input  wire [ADDRW-1:0] addr,
    output reg  [7:0]       data,         // valido con ready; se mantiene
    output reg              ready,
    // --- interfaz con el controlador flash_rw (muxeada en top por flash_idle) ---
    output reg  [23:0]      fl_addr,
    output reg              fl_rd,
    output reg              fl_terminate,
    input  wire [7:0]       fl_dout,
    input  wire             fl_busy
);
    localparam S_IDLE=3'd0, S_START=3'd1, S_RD=3'd2, S_WAIT=3'd3, S_HOLD=3'd4;
    reg [2:0] st;

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; fl_rd <= 1'b0; fl_terminate <= 1'b1;
            ready <= 1'b0; fl_addr <= 24'd0; data <= 8'hFF;
        end else begin
            case (st)
                S_IDLE: begin
                    // Mantiene el controlador terminado -> re-init -> listo para un
                    // comando fresco (lectura aleatoria) en la siguiente peticion.
                    fl_terminate <= 1'b1;
                    fl_rd        <= 1'b0;
                    ready        <= 1'b0;
                    if (req) st <= S_START;
                end
                S_START: begin
                    fl_terminate <= 1'b0;
                    if (!fl_busy) begin              // controlador listo (LOAD_CMD)
                        fl_addr <= TAPE_BASE + addr;
                        fl_rd   <= 1'b1;
                        st <= S_RD;
                    end
                end
                S_RD: begin
                    if (fl_busy) begin               // la lectura arranco
                        fl_rd <= 1'b0;               // 1 byte (no secuencial)
                        st <= S_WAIT;
                    end
                end
                S_WAIT: begin
                    if (!fl_busy) begin              // lectura hecha, fl_dout valido
                        data  <= fl_dout;
                        ready <= 1'b1;
                        st <= S_HOLD;
                    end
                end
                S_HOLD: begin
                    if (!req) begin                  // cas_player consumio el byte
                        ready <= 1'b0;
                        st <= S_IDLE;
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
