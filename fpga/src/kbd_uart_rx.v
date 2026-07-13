//============================================================================
// kbd_uart_rx.v
//   Virtual MSX keyboard matrix fed over UART from a Raspberry Pi Pico (RP2040).
//
//   The physical MSX keyboard is still read by the real motherboard 8255 PPI;
//   that read arrives at the FPGA on `bus_data` and is consumed passively by the
//   FPGA-Z80. This module maintains a SECOND (virtual) keyboard matrix that the
//   RP2040 drives over UART. In top.v the virtual row is merged with the physical
//   read via an active-low AND on the I/O 0xA9 keyboard-column read, so BOTH the
//   real keyboard and the USB keyboard work simultaneously. This module never
//   drives the data bus; it only exposes the selected matrix row combinationally.
//
//   UART: 115200 8N1, idle-high, LSB first. The RX FSM is modelled on the clean
//   8N1 receiver in src/ocm/uart_lite.vhd (RX_IDLE -> RX_START -> RX_DATA ->
//   RX_STOP, with a mid-bit start-bit re-sample / false-start check).
//
//   The ENTIRE module runs in a single clock domain (clk = clk_54m in top.v).
//   The only asynchronous input is the raw RX pin, which is passed through a
//   2-flop synchronizer before use. There is therefore no multi-bit CDC: the
//   matrix, decoder and the latched vkey_col selector all live in `clk`.
//
//   FROZEN protocol contract (must match the RP2040 firmware EXACTLY):
//     - Matrix cell byte = 0x80 | (bit<<4) | row, row in 0..10, bit in 0..7.
//       Matrix is ACTIVE-LOW: bit value 1 = released, 0 = pressed.
//     - 0x90 <cell> = MAKE  (press   -> clear that matrix bit to 0)
//     - 0xA0 <cell> = BREAK (release -> set   that matrix bit to 1)
//     - Command bytes (bit7 == 0):
//         0x01 = scanline toggle, 0x02 = reset, 0x03 = OSD toggle.
//       v1 decodes them to 1-clk cmd_* pulse OUTPUTS but they are left
//       UNCONNECTED at the top level (Gowin trims the logic away).
//     - Full-matrix resync: 0xFE, then 11 row bytes m0..m10 (each = an active-low
//       row state), then 0xFF. On 0xFE we enter a counted load (row 0..10),
//       writing each byte to vkey_matrix[row]; the load finishes on 0xFF or after
//       11 bytes have been consumed, whichever comes first.
//     - USB joystick state: 0xB0 <port> <joybyte> (3 bytes). port: 0 = MSX
//       joystick port 1 (joy_state0), 1 = port 2 (joy_state1). joybyte is
//       ACTIVE-HIGH: bit0=Right, bit1=Left, bit2=Down, bit3=Up, bit4=A(TrigA),
//       bit5=B(TrigB), bits6-7 unused. The active-high byte is stored verbatim;
//       top.v reorders to MSX active-low and AND-merges into the PSG 0xA2 read so
//       the real MSX joystick still works. Cleared to 0x00 on reset and on the
//       ~1 s link-loss watchdog (active-high 0 = nothing pressed).
//============================================================================

`default_nettype none

module kbd_uart_rx #(
    parameter CLK_FREQ = 54_000_000,   // clk frequency in Hz (clk_54m)
    parameter BAUD     = 115_200       // UART baud rate
)(
    input  wire        clk,            // single clock domain (clk_54m in top.v)
    input  wire        reset_n,        // active-low synchronous-ish reset (bus_reset_n)
    input  wire        rx,             // raw async UART RX pin (FPGA pin 75)

    input  wire [3:0]  vkey_col,       // selected keyboard column (PPI port C low nibble)
    output wire [7:0]  vkey_row_out,   // active-low matrix row for vkey_col (combinational)

    // USB joystick state, ACTIVE-HIGH as received (bit0=R,1=L,2=D,3=U,4=A,5=B).
    // port 0 -> joy_state0 (MSX joystick port 1), port 1 -> joy_state1 (port 2).
    // top.v reorders to MSX active-low and AND-merges into the PSG 0xA2 read.
    output reg  [7:0]  joy_state0,
    output reg  [7:0]  joy_state1,

    // v1: pulse outputs, left open at instantiation (Gowin trims them).
    output reg         cmd_scanline_toggle,
    output reg         cmd_reset_pulse,
    output reg         cmd_osd_toggle
);

    //------------------------------------------------------------------------
    // Derived timing constant. CLKS_PER_BIT = 54_000_000 / 115_200 = 468.
    //------------------------------------------------------------------------
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD;
    // Wide enough counter to hold CLKS_PER_BIT-1 (468 -> needs 9 bits, use 16 for headroom).
    localparam integer CNT_W = 16;

    //========================================================================
    // 1) Two-flop synchronizer for the asynchronous RX pin.
    //    Marked syn_preserve so Gowin will not merge/optimize the metastability
    //    guard flops away. We sample rx_s2 in the RX FSM.
    //========================================================================
    (* syn_preserve = 1 *) reg rx_s1 = 1'b1;
    (* syn_preserve = 1 *) reg rx_s2 = 1'b1;
    always @(posedge clk) begin
        rx_s1 <= rx;
        rx_s2 <= rx_s1;
    end

    //========================================================================
    // 2) UART RX FSM (8N1). Modelled on uart_lite.vhd:148-200.
    //    On a successful stop bit we assert rx_valid for exactly one clk with
    //    the received byte on rx_byte.
    //========================================================================
    localparam [1:0] RX_IDLE  = 2'd0,
                     RX_START = 2'd1,
                     RX_DATA  = 2'd2,
                     RX_STOP  = 2'd3;

    reg [1:0]        rx_state    = RX_IDLE;
    reg [CNT_W-1:0]  rx_counter  = {CNT_W{1'b0}};
    reg [2:0]        rx_bit_index= 3'd0;
    reg [7:0]        rx_buffer   = 8'h00;
    reg [7:0]        rx_byte     = 8'h00;
    reg              rx_valid    = 1'b0;

    always @(posedge clk) begin
        if (!reset_n) begin
            rx_state     <= RX_IDLE;
            rx_counter   <= {CNT_W{1'b0}};
            rx_bit_index <= 3'd0;
            rx_buffer    <= 8'h00;
            rx_byte      <= 8'h00;
            rx_valid     <= 1'b0;
        end else begin
            // rx_valid is a single-cycle strobe by default.
            rx_valid <= 1'b0;

            case (rx_state)
                //----------------------------------------------------------------
                // Idle: wait for the falling edge of the (idle-high) line = start bit.
                //----------------------------------------------------------------
                RX_IDLE: begin
                    rx_counter   <= {CNT_W{1'b0}};
                    rx_bit_index <= 3'd0;
                    if (rx_s2 == 1'b0) begin
                        rx_state <= RX_START;
                    end
                end

                //----------------------------------------------------------------
                // Start: sample at the MIDDLE of the start bit to validate it.
                //----------------------------------------------------------------
                RX_START: begin
                    if (rx_counter < (CLKS_PER_BIT/2) - 1) begin
                        rx_counter <= rx_counter + 1'b1;
                    end else begin
                        rx_counter <= {CNT_W{1'b0}};
                        if (rx_s2 == 1'b0) begin
                            rx_state <= RX_DATA;       // valid start bit confirmed
                        end else begin
                            rx_state <= RX_IDLE;       // false start (glitch)
                        end
                    end
                end

                //----------------------------------------------------------------
                // Data: from here each bit is sampled one full bit-period apart.
                // The mid-bit alignment established in RX_START keeps us centered.
                // LSB first.
                //----------------------------------------------------------------
                RX_DATA: begin
                    if (rx_counter < CLKS_PER_BIT - 1) begin
                        rx_counter <= rx_counter + 1'b1;
                    end else begin
                        rx_counter            <= {CNT_W{1'b0}};
                        rx_buffer[rx_bit_index] <= rx_s2;
                        if (rx_bit_index < 3'd7) begin
                            rx_bit_index <= rx_bit_index + 1'b1;
                        end else begin
                            rx_bit_index <= 3'd0;
                            rx_state     <= RX_STOP;
                        end
                    end
                end

                //----------------------------------------------------------------
                // Stop: wait one bit period, then emit the byte. We do not gate on
                // the stop level being high (matches uart_lite); a framing glitch
                // simply yields one byte and we resync on the next start edge.
                //----------------------------------------------------------------
                RX_STOP: begin
                    if (rx_counter < CLKS_PER_BIT - 1) begin
                        rx_counter <= rx_counter + 1'b1;
                    end else begin
                        rx_counter <= {CNT_W{1'b0}};
                        rx_byte    <= rx_buffer;
                        rx_valid   <= 1'b1;            // one-clk strobe
                        rx_state   <= RX_IDLE;
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    //========================================================================
    // 3) Virtual keyboard matrix + protocol decoder FSM.
    //    16 rows of 8 bits, active-low. Only rows 0..10 are used by the MSX;
    //    the extra entries (11..15) keep the vkey_col index combinational and
    //    safe for any 4-bit column value (they always read 0xFF = all released).
    //========================================================================
    reg [7:0] vkey_matrix [0:15];

    // Power-on / simulation initial state: everything released (active-low).
    // USB joystick state is active-high, so 0x00 = nothing pressed.
    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1)
            vkey_matrix[i] = 8'hFF;
        joy_state0 = 8'h00;
        joy_state1 = 8'h00;
    end

    localparam [2:0] D_IDLE     = 3'd0,   // waiting for a command/opcode byte
                     D_CELL     = 3'd1,   // expecting the cell byte after 0x90/0xA0
                     D_LOAD     = 3'd2,   // counted full-matrix load after 0xFE
                     D_JOY_PORT = 3'd3,   // expecting the port byte after 0xB0
                     D_JOY_BYTE = 3'd4;   // expecting the joystick byte after the port

    reg [2:0] dstate      = D_IDLE;
    reg       pending_make= 1'b0;     // 1 = MAKE (press), 0 = BREAK (release)
    reg [3:0] load_idx    = 4'd0;     // 0..10 row index during full-matrix load
    reg       joy_port    = 1'b0;     // latched port index from 0xB0 (0 or 1)

    // Field extraction from a cell byte: row = bits[3:0], col(bit#) = bits[6:4].
    wire [3:0] cell_row = rx_byte[3:0];
    wire [2:0] cell_bit = rx_byte[6:4];

    //------------------------------------------------------------------------
    // Fail-safe watchdog counter (declared before the decoder so wd_timeout is
    // visible inside it). A free-running counter that releases ALL keys if no
    // valid UART byte has been seen for ~1 second, preventing a stuck key if the
    // RP2040 link drops mid-press. Any rx_valid resets the timer. The counter
    // lives in its OWN block (it never writes the matrix); the actual matrix
    // release happens inside the single decoder block below, so vkey_matrix has
    // exactly one procedural writer (no multiple-driver conflict).
    //------------------------------------------------------------------------
    localparam integer WD_W     = 26;             // 2^26 = 67.1M > 54M, enough for 1 s
    localparam integer WD_LIMIT = CLK_FREQ;       // 54_000_000 ticks ~= 1 s
    reg [WD_W-1:0] wd_counter = {WD_W{1'b0}};

    always @(posedge clk) begin
        if (!reset_n) begin
            wd_counter <= {WD_W{1'b0}};
        end else if (rx_valid) begin
            wd_counter <= {WD_W{1'b0}};           // activity: kick the dog
        end else if (wd_counter < WD_LIMIT) begin
            wd_counter <= wd_counter + 1'b1;      // count up, then hold at WD_LIMIT
        end
    end

    // One-cycle "timeout" strobe when the watchdog first reaches the limit.
    // By construction !rx_valid here, so it is mutually exclusive with a decode.
    wire wd_timeout = (wd_counter == WD_LIMIT - 1) && !rx_valid;

    always @(posedge clk) begin
        if (!reset_n) begin
            dstate              <= D_IDLE;
            pending_make        <= 1'b0;
            load_idx            <= 4'd0;
            joy_port            <= 1'b0;
            joy_state0          <= 8'h00;  // active-high: nothing pressed
            joy_state1          <= 8'h00;
            cmd_scanline_toggle <= 1'b0;
            cmd_reset_pulse     <= 1'b0;
            cmd_osd_toggle      <= 1'b0;
            for (i = 0; i < 16; i = i + 1)
                vkey_matrix[i] <= 8'hFF;   // all keys released on reset
        end else begin
            // cmd_* are single-cycle pulses by default.
            cmd_scanline_toggle <= 1'b0;
            cmd_reset_pulse     <= 1'b0;
            cmd_osd_toggle      <= 1'b0;

            if (rx_valid) begin
                case (dstate)
                    //--------------------------------------------------------
                    // D_IDLE: interpret the opcode byte.
                    //--------------------------------------------------------
                    D_IDLE: begin
                        case (rx_byte)
                            8'h90: begin pending_make <= 1'b1; dstate <= D_CELL; end // MAKE
                            8'hA0: begin pending_make <= 1'b0; dstate <= D_CELL; end // BREAK
                            8'hB0: begin                       dstate <= D_JOY_PORT; end // USB joystick
                            8'hFE: begin load_idx <= 4'd0;     dstate <= D_LOAD; end // resync start
                            8'h01: cmd_scanline_toggle <= 1'b1;                       // command
                            8'h02: cmd_reset_pulse     <= 1'b1;                       // command
                            8'h03: cmd_osd_toggle      <= 1'b1;                       // command
                            default: ; // ignore anything else (incl. stray 0xFF/cell bytes)
                        endcase
                    end

                    //--------------------------------------------------------
                    // D_CELL: this byte is the cell. Apply MAKE/BREAK to one bit.
                    //--------------------------------------------------------
                    D_CELL: begin
                        if (cell_row <= 4'd10) begin
                            // MAKE  -> clear bit (pressed = 0)
                            // BREAK -> set   bit (released = 1)
                            vkey_matrix[cell_row][cell_bit] <= pending_make ? 1'b0 : 1'b1;
                        end
                        dstate <= D_IDLE;
                    end

                    //--------------------------------------------------------
                    // D_JOY_PORT: this byte is the port index (0 or 1). Only
                    // bit0 is meaningful (port 0 / port 1); ignore upper bits.
                    //--------------------------------------------------------
                    D_JOY_PORT: begin
                        joy_port <= rx_byte[0];
                        dstate   <= D_JOY_BYTE;
                    end

                    //--------------------------------------------------------
                    // D_JOY_BYTE: this byte is the active-high joystick state.
                    // Store verbatim into the selected port's register; top.v
                    // reorders to MSX active-low and AND-merges into 0xA2.
                    //--------------------------------------------------------
                    D_JOY_BYTE: begin
                        if (joy_port == 1'b0)
                            joy_state0 <= rx_byte;
                        else
                            joy_state1 <= rx_byte;
                        dstate <= D_IDLE;
                    end

                    //--------------------------------------------------------
                    // D_LOAD: counted full-matrix resync. Store EVERY byte into the
                    // next row (0..10); after row 10 return to D_IDLE. Do NOT treat
                    // a data 0xFF as a terminator: 0xFF is the normal "row all-
                    // released" state (active-low), so an early-out on 0xFF would
                    // abort almost every resync (row 0 is usually 0xFF). The trailing
                    // 0xFF lands in D_IDLE and is ignored (no opcode match -> default).
                    //--------------------------------------------------------
                    D_LOAD: begin
                        vkey_matrix[load_idx] <= rx_byte;   // store every byte
                        if (load_idx == 4'd10) begin
                            dstate <= D_IDLE;               // 11 rows (0..10) loaded
                        end else begin
                            load_idx <= load_idx + 1'b1;
                        end
                    end

                    default: dstate <= D_IDLE;
                endcase
            end else if (wd_timeout) begin
                // Fail-safe: link idle for ~1 s -> release every key. Mutually
                // exclusive with the rx_valid branch above (wd_timeout requires
                // !rx_valid), so this is the matrix's only other writer path and
                // there is no driver conflict. Also nudge the decoder back to a
                // clean state in case we were mid-sequence when the link dropped.
                for (i = 0; i < 16; i = i + 1)
                    vkey_matrix[i] <= 8'hFF;
                joy_state0   <= 8'h00;   // release USB joystick too (active-high)
                joy_state1   <= 8'h00;
                dstate       <= D_IDLE;
                pending_make <= 1'b0;
                load_idx     <= 4'd0;
                joy_port     <= 1'b0;
            end
        end
    end

    //========================================================================
    // 4) Combinational row read-out. vkey_col selects the row; the merge with
    //    the physical keyboard read happens in top.v (active-low AND).
    //========================================================================
    assign vkey_row_out = vkey_matrix[vkey_col];

endmodule

`default_nettype wire
