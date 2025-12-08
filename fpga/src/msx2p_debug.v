// ============================================================================
// msx2p_debug - extended debug for MSX2+ project (CORRECTED VERSION)
//  - removed multiple control of the same registers in different always blocks
//  - counters are NOT automatically cleared after each log (avoiding multi-driver)
// ============================================================================
module msx2p_debug(
    input        clk_27m,
    input        clk,           // CPU clock (Z80)
    input        clk_enable,    // enable for CPU cycles
    input        reset_n,

    input  [15:0] bus_addr,
    input  [7:0]  bus_data,
    input         bus_iorq_n,
    input         bus_mreq_n,
    input         bus_rd_n,
    input         bus_wr_n,

    input         send,         // log sending enable

    output        uart_tx,
    output        boot_ok
);

    // ===========================================
    // Tic generator - approx. 10Hz (every ~100ms) in clk_27m domain
    // ===========================================
    reg [31:0] counter_tic = 32'd0;
    wire       tic;

    always @ (posedge clk_27m or negedge reset_n) begin
        if (!reset_n) begin
            counter_tic <= 32'd0;
        end else begin
            if (counter_tic >= 32'd2700000) begin
                counter_tic <= 32'd0;
            end else begin
                counter_tic <= counter_tic + 1;
            end
        end
    end

    assign tic = (counter_tic == 32'd0);

    // ===========================================
    // Slots / mapper / addresses
    // ===========================================

    // Port A8 - Primary Slot Select
    reg [7:0] port_a8_value       = 8'h00;
    reg [7:0] port_a8_write_count = 8'h00;

    // Address FFFF - Secondary Slot Select  
    reg [7:0] port_ffff_value       = 8'h00;
    reg [7:0] port_ffff_write_count = 8'h00;

    // Mapper ports FC-FF - last values
    reg [7:0] port_fc_value = 8'h00;
    reg [7:0] port_fd_value = 8'h00;
    reg [7:0] port_fe_value = 8'h00;
    reg [7:0] port_ff_value = 8'h00;

    // Mapper ports FC-FF - W/R counters
    reg [7:0] map_fc_wcnt = 8'h00;
    reg [7:0] map_fd_wcnt = 8'h00;
    reg [7:0] map_fe_wcnt = 8'h00;
    reg [7:0] map_ff_wcnt = 8'h00;

    reg [7:0] map_fc_rcnt = 8'h00;
    reg [7:0] map_fd_rcnt = 8'h00;
    reg [7:0] map_fe_rcnt = 8'h00;
    reg [7:0] map_ff_rcnt = 8'h00;

    // Last memory address
    reg [15:0] last_addr = 16'h0000;
    reg [15:0] max_addr  = 16'h0000;

    // ===========================================
    // AUDIO + VDP DEBUG – audio ports, VDP and 90–9F
    // ===========================================

    // Last I/O port
    reg [7:0] last_io_port = 8'h00;

    // PSG: A0, A1, A2 (write counters)
    reg [7:0] psg_a0_cnt = 8'h00;
    reg [7:0] psg_a1_cnt = 8'h00;
    reg [7:0] psg_a2_cnt = 8'h00;

    // OPLL (MSX-MUSIC): 7C–7F (write counters)
    reg [7:0] opll_7c_cnt = 8'h00;
    reg [7:0] opll_7d_cnt = 8'h00;
    reg [7:0] opll_7e_cnt = 8'h00;
    reg [7:0] opll_7f_cnt = 8'h00;

    // MSX-AUDIO (C0–C3) – W/R counters
    reg [7:0] aud_c0_wcnt = 8'h00;
    reg [7:0] aud_c1_wcnt = 8'h00;
    reg [7:0] aud_c2_wcnt = 8'h00;
    reg [7:0] aud_c3_wcnt = 8'h00;
    reg [7:0] aud_c0_rcnt = 8'h00;
    reg [7:0] aud_c1_rcnt = 8'h00;
    reg [7:0] aud_c2_rcnt = 8'h00;
    reg [7:0] aud_c3_rcnt = 8'h00;

    // VDP: 98/99/9A/9B – W/R counters
    reg [7:0] vdp_98_wcnt = 8'h00;
    reg [7:0] vdp_99_wcnt = 8'h00;
    reg [7:0] vdp_9a_wcnt = 8'h00;
    reg [7:0] vdp_9b_wcnt = 8'h00;
    reg [7:0] vdp_98_rcnt = 8'h00;
    reg [7:0] vdp_99_rcnt = 8'h00;
    reg [7:0] vdp_9a_rcnt = 8'h00;
    reg [7:0] vdp_9b_rcnt = 8'h00;

    // VDP registers we want to track (R1/R2/R9)
    reg [4:0] vdp_reg_sel           = 5'd0;
    reg       vdp_reg_pending       = 1'b0;  // waiting for second OUT (command)
    reg [7:0] vdp_reg_pending_value = 8'h00;
    reg [7:0] vdp_r1 = 8'h00;
    reg [7:0] vdp_r2 = 8'h00;
    reg [7:0] vdp_r9 = 8'h00;

    // General counter for port access 90–9F
    reg [7:0] io_90_9f_cnt = 8'h00;

    // History of last 4 I/O operations (port + R/W)
    reg [7:0] io_hist_port0 = 8'h00;
    reg [7:0] io_hist_port1 = 8'h00;
    reg [7:0] io_hist_port2 = 8'h00;
    reg [7:0] io_hist_port3 = 8'h00;

    reg       io_hist_is_write0 = 1'b0;
    reg       io_hist_is_write1 = 1'b0;
    reg       io_hist_is_write2 = 1'b0;
    reg       io_hist_is_write3 = 1'b0;

    // "Loop" on 9Bh
    reg [7:0] stuck_9b = 8'h00;

    // Buffers of last values sent to 99h and 9Bh
    reg [7:0] last_99_val0 = 8'h00;
    reg [7:0] last_99_val1 = 8'h00;
    reg [7:0] last_99_val2 = 8'h00;

    reg [7:0] last_9b_val0 = 8'h00;
    reg [7:0] last_9b_val1 = 8'h00;
    reg [7:0] last_9b_val2 = 8'h00;

    // ===========================================
    // Port A8
    // ===========================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            port_a8_value       <= 8'h00;
            port_a8_write_count <= 8'h00;
        end else if (clk_enable) begin
            if (!bus_iorq_n && !bus_wr_n && bus_addr[7:0] == 8'hA8) begin
                port_a8_value <= bus_data;
                if (port_a8_write_count != 8'hFF)
                    port_a8_write_count <= port_a8_write_count + 1;
            end
        end
    end

    // ===========================================
    // Address FFFF
    // ===========================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            port_ffff_value       <= 8'h00;
            port_ffff_write_count <= 8'h00;
        end else if (clk_enable) begin
            if (!bus_mreq_n && !bus_wr_n && bus_addr == 16'hFFFF) begin
                port_ffff_value <= bus_data;
                if (port_ffff_write_count != 8'hFF)
                    port_ffff_write_count <= port_ffff_write_count + 1;
            end
        end
    end

    // ===========================================
    // Mapper ports FC-FF – last value (W)
    // ===========================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            port_fc_value <= 8'h00;
            port_fd_value <= 8'h00;
            port_fe_value <= 8'h00;
            port_ff_value <= 8'h00;
        end else if (clk_enable) begin
            if (!bus_iorq_n && !bus_wr_n) begin
                case (bus_addr[7:0])
                    8'hFC: port_fc_value <= bus_data;
                    8'hFD: port_fd_value <= bus_data;
                    8'hFE: port_fe_value <= bus_data;
                    8'hFF: port_ff_value <= bus_data;
                endcase
            end
        end
    end

    // ===========================================
    // AUDIO + VDP + mapper – I/O capture
    // ===========================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            last_io_port <= 8'h00;

            psg_a0_cnt <= 8'h00;
            psg_a1_cnt <= 8'h00;
            psg_a2_cnt <= 8'h00;

            opll_7c_cnt <= 8'h00;
            opll_7d_cnt <= 8'h00;
            opll_7e_cnt <= 8'h00;
            opll_7f_cnt <= 8'h00;

            aud_c0_wcnt <= 8'h00;
            aud_c1_wcnt <= 8'h00;
            aud_c2_wcnt <= 8'h00;
            aud_c3_wcnt <= 8'h00;
            aud_c0_rcnt <= 8'h00;
            aud_c1_rcnt <= 8'h00;
            aud_c2_rcnt <= 8'h00;
            aud_c3_rcnt <= 8'h00;

            vdp_98_wcnt <= 8'h00;
            vdp_99_wcnt <= 8'h00;
            vdp_9a_wcnt <= 8'h00;
            vdp_9b_wcnt <= 8'h00;
            vdp_98_rcnt <= 8'h00;
            vdp_99_rcnt <= 8'h00;
            vdp_9a_rcnt <= 8'h00;
            vdp_9b_rcnt <= 8'h00;

            vdp_reg_sel           <= 5'd0;
            vdp_reg_pending       <= 1'b0;
            vdp_reg_pending_value <= 8'h00;
            vdp_r1 <= 8'h00;
            vdp_r2 <= 8'h00;
            vdp_r9 <= 8'h00;

            io_90_9f_cnt <= 8'h00;

            io_hist_port0 <= 8'h00;
            io_hist_port1 <= 8'h00;
            io_hist_port2 <= 8'h00;
            io_hist_port3 <= 8'h00;
            io_hist_is_write0 <= 1'b0;
            io_hist_is_write1 <= 1'b0;
            io_hist_is_write2 <= 1'b0;
            io_hist_is_write3 <= 1'b0;

            stuck_9b <= 8'h00;

            last_99_val0 <= 8'h00;
            last_99_val1 <= 8'h00;
            last_99_val2 <= 8'h00;

            last_9b_val0 <= 8'h00;
            last_9b_val1 <= 8'h00;
            last_9b_val2 <= 8'h00;

            map_fc_wcnt <= 8'h00;
            map_fd_wcnt <= 8'h00;
            map_fe_wcnt <= 8'h00;
            map_ff_wcnt <= 8'h00;
            map_fc_rcnt <= 8'h00;
            map_fd_rcnt <= 8'h00;
            map_fe_rcnt <= 8'h00;
            map_ff_rcnt <= 8'h00;
        end else if (clk_enable) begin
            if (!bus_iorq_n) begin
                last_io_port <= bus_addr[7:0];

                // History of 4 last I/O operations
                io_hist_port3     <= io_hist_port2;
                io_hist_is_write3 <= io_hist_is_write2;
                io_hist_port2     <= io_hist_port1;
                io_hist_is_write2 <= io_hist_is_write1;
                io_hist_port1     <= io_hist_port0;
                io_hist_is_write1 <= io_hist_is_write0;
                io_hist_port0     <= bus_addr[7:0];
                io_hist_is_write0 <= (bus_wr_n == 1'b0);

                // Counter for range 90–9F
                if (bus_addr[7:4] == 4'h9) begin
                    if (io_90_9f_cnt != 8'hFF)
                        io_90_9f_cnt <= io_90_9f_cnt + 1;
                end

                // Loop detector on 9Bh
                if (bus_addr[7:0] == 8'h9B && (!bus_wr_n || !bus_rd_n)) begin
                    if (stuck_9b != 8'hFF)
                        stuck_9b <= stuck_9b + 1;
                end else if (!bus_wr_n || !bus_rd_n) begin
                    stuck_9b <= 8'h00;
                end

                // WRITES
                if (!bus_wr_n) begin
                    case (bus_addr[7:0])
                        // PSG
                        8'hA0: if (psg_a0_cnt != 8'hFF) psg_a0_cnt <= psg_a0_cnt + 1;
                        8'hA1: if (psg_a1_cnt != 8'hFF) psg_a1_cnt <= psg_a1_cnt + 1;
                        8'hA2: if (psg_a2_cnt != 8'hFF) psg_a2_cnt <= psg_a2_cnt + 1;

                        // OPLL
                        8'h7C: if (opll_7c_cnt != 8'hFF) opll_7c_cnt <= opll_7c_cnt + 1;
                        8'h7D: if (opll_7d_cnt != 8'hFF) opll_7d_cnt <= opll_7d_cnt + 1;
                        8'h7E: if (opll_7e_cnt != 8'hFF) opll_7e_cnt <= opll_7e_cnt + 1;
                        8'h7F: if (opll_7f_cnt != 8'hFF) opll_7f_cnt <= opll_7f_cnt + 1;

                        // MSX-AUDIO (C0–C3) write
                        8'hC0: if (aud_c0_wcnt != 8'hFF) aud_c0_wcnt <= aud_c0_wcnt + 1;
                        8'hC1: if (aud_c1_wcnt != 8'hFF) aud_c1_wcnt <= aud_c1_wcnt + 1;
                        8'hC2: if (aud_c2_wcnt != 8'hFF) aud_c2_wcnt <= aud_c2_wcnt + 1;
                        8'hC3: if (aud_c3_wcnt != 8'hFF) aud_c3_wcnt <= aud_c3_wcnt + 1;

                        // Mapper FC–FF write
                        8'hFC: if (map_fc_wcnt != 8'hFF) map_fc_wcnt <= map_fc_wcnt + 1;
                        8'hFD: if (map_fd_wcnt != 8'hFF) map_fd_wcnt <= map_fd_wcnt + 1;
                        8'hFE: if (map_fe_wcnt != 8'hFF) map_fe_wcnt <= map_fe_wcnt + 1;
                        8'hFF: if (map_ff_wcnt != 8'hFF) map_ff_wcnt <= map_ff_wcnt + 1;

                        // VDP 98/99/9A/9B write
                        8'h98: if (vdp_98_wcnt != 8'hFF) vdp_98_wcnt <= vdp_98_wcnt + 1;

                        8'h99: begin
                            // remember last values on 99h
                            last_99_val2 <= last_99_val1;
                            last_99_val1 <= last_99_val0;
                            last_99_val0 <= bus_data;

                            // register protocol: value -> (99h), then reg|80h -> (99h)
                            if (!vdp_reg_pending) begin
                                vdp_reg_pending_value <= bus_data;
                                vdp_reg_pending       <= 1'b1;
                            end else begin
                                if (bus_data[7]) begin
                                    vdp_reg_sel <= bus_data[4:0];
                                    case (bus_data[4:0])
                                        5'd1: vdp_r1 <= vdp_reg_pending_value;
                                        5'd2: vdp_r2 <= vdp_reg_pending_value;
                                        5'd9: vdp_r9 <= vdp_reg_pending_value;
                                    endcase
                                end
                                vdp_reg_pending <= 1'b0;
                            end

                            if (vdp_99_wcnt != 8'hFF) vdp_99_wcnt <= vdp_99_wcnt + 1;
                        end

                        8'h9A: if (vdp_9a_wcnt != 8'hFF) vdp_9a_wcnt <= vdp_9a_wcnt + 1;

                        8'h9B: begin
                            last_9b_val2 <= last_9b_val1;
                            last_9b_val1 <= last_9b_val0;
                            last_9b_val0 <= bus_data;
                            if (vdp_9b_wcnt != 8'hFF) vdp_9b_wcnt <= vdp_9b_wcnt + 1;
                        end
                    endcase
                end

                // READS
                if (!bus_rd_n) begin
                    case (bus_addr[7:0])
                        // MSX-AUDIO
                        8'hC0: if (aud_c0_rcnt != 8'hFF) aud_c0_rcnt <= aud_c0_rcnt + 1;
                        8'hC1: if (aud_c1_rcnt != 8'hFF) aud_c1_rcnt <= aud_c1_rcnt + 1;
                        8'hC2: if (aud_c2_rcnt != 8'hFF) aud_c2_rcnt <= aud_c2_rcnt + 1;
                        8'hC3: if (aud_c3_rcnt != 8'hFF) aud_c3_rcnt <= aud_c3_rcnt + 1;

                        // Mapper FC–FF read
                        8'hFC: if (map_fc_rcnt != 8'hFF) map_fc_rcnt <= map_fc_rcnt + 1;
                        8'hFD: if (map_fd_rcnt != 8'hFF) map_fd_rcnt <= map_fd_rcnt + 1;
                        8'hFE: if (map_fe_rcnt != 8'hFF) map_fe_rcnt <= map_fe_rcnt + 1;
                        8'hFF: if (map_ff_rcnt != 8'hFF) map_ff_rcnt <= map_ff_rcnt + 1;

                        // VDP read
                        8'h98: if (vdp_98_rcnt != 8'hFF) vdp_98_rcnt <= vdp_98_rcnt + 1;
                        8'h99: if (vdp_99_rcnt != 8'hFF) vdp_99_rcnt <= vdp_99_rcnt + 1;
                        8'h9A: if (vdp_9a_rcnt != 8'hFF) vdp_9a_rcnt <= vdp_9a_rcnt + 1;
                        8'h9B: if (vdp_9b_rcnt != 8'hFF) vdp_9b_rcnt <= vdp_9b_rcnt + 1;
                    endcase
                end
            end
        end
    end

    // ===========================================
    // Memory address tracking
    // ===========================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            last_addr <= 16'h0000;
            max_addr  <= 16'h0000;
        end else if (clk_enable) begin
            if (!bus_mreq_n) begin
                last_addr <= bus_addr;
                if (bus_addr > max_addr)
                    max_addr <= bus_addr;
            end
        end
    end

    // ===========================================
    // BIOS reset (staying at 0000h with F3)
    // ===========================================
    reg [7:0] reset_count = 8'h00;
    reg       was_at_0000 = 1'b0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            reset_count <= 8'h00;
            was_at_0000 <= 1'b0;
        end else if (clk_enable) begin
            if (bus_addr == 16'h0000 && bus_data == 8'hF3) begin
                if (!was_at_0000) begin
                    was_at_0000 <= 1'b1;
                    if (reset_count != 8'hFF)
                        reset_count <= reset_count + 1;
                end
            end else begin
                was_at_0000 <= 1'b0;
            end
        end
    end

    // ===========================================
    // BIOS milestone flags
    // ===========================================
    reg flag_0416 = 1'b0;  // CHKRAM
    reg flag_7b61 = 1'b0;  // INIT2  
    reg flag_7c76 = 1'b0;  // INIT3/BASIC
    reg flag_411f = 1'b0;  // BASIC main loop

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            flag_0416 <= 1'b0;
            flag_7b61 <= 1'b0;
            flag_7c76 <= 1'b0;
            flag_411f <= 1'b0;
        end else if (clk_enable) begin
            if (bus_addr == 16'h0416) flag_0416 <= 1'b1;
            if (bus_addr == 16'h7b61) flag_7b61 <= 1'b1;
            if (bus_addr == 16'h7c76) flag_7c76 <= 1'b1;
            if (bus_addr == 16'h411f) flag_411f <= 1'b1;
        end
    end

    // ===========================================
    // Port A9 read counter (keyboard)
    // ===========================================
    reg [7:0] port_a9_read_count = 8'h00;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            port_a9_read_count <= 8'h00;
        end else if (clk_enable) begin
            if (!bus_iorq_n && !bus_rd_n && bus_addr[7:0] == 8'hA9) begin
                if (port_a9_read_count != 8'hFF)
                    port_a9_read_count <= port_a9_read_count + 1;
            end
        end
    end

    // ===========================================
    // Old sequential debugger (BIOS start)
    // ===========================================
    reg [7:0] debug_state = 8'd0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            debug_state <= 8'd0;
        end else if (clk_enable) begin
            case (debug_state)
                8'd00: begin
                    if (bus_addr == 16'h0000 && bus_data == 8'hf3)
                        debug_state <= 8'd1;
                end
                8'd01: begin
                    if (bus_addr == 16'h0001 && bus_data == 8'hc3)
                        debug_state <= 8'd2;
                end
                8'd02: begin
                    if (bus_addr == 16'h0002 && bus_data == 8'h16)
                        debug_state <= 8'd3;
                end
                8'd03: begin
                    if (bus_addr == 16'h0003 && bus_data == 8'h04)
                        debug_state <= 8'd4;
                end
                8'd04: begin
                    if (bus_addr == 16'h0416)
                        debug_state <= 8'd5;
                end
                default: begin
                    // Stay in state 5+
                end
            endcase
        end
    end

    // ===========================================
    // UART - logging
    // ===========================================
`include "print.v"
    defparam tx.uart_freq = 115200;
    defparam tx.clk_freq  = 27000000;
    assign print_clk = clk_27m;
    assign uart_tx   = uart_txp;

    reg [7:0] send_state = 8'd0;

    always @ (posedge clk_27m or negedge reset_n) begin
        if (!reset_n) begin
            send_state <= 8'd0;
        end 
        else if (tic) begin
            case (send_state)
                8'd00: begin
                    if (send) begin
                        send_state <= 8'd1;
                    end
                end

                // 1: state, A8, FFFF
                8'd01: begin `print("state=", STR);           send_state <= 8'd02; end
                8'd02: begin `print(debug_state, HEX);        send_state <= 8'd03; end
                8'd03: begin `print(" A8=", STR);             send_state <= 8'd04; end
                8'd04: begin `print(port_a8_value, HEX);      send_state <= 8'd05; end
                8'd05: begin `print(" A8cnt=", STR);          send_state <= 8'd06; end
                8'd06: begin `print(port_a8_write_count, HEX);send_state <= 8'd07; end
                8'd07: begin `print(" FFFF=", STR);           send_state <= 8'd08; end
                8'd08: begin `print(port_ffff_value, HEX);    send_state <= 8'd09; end
                8'd09: begin `print(" FFFFcnt=", STR);        send_state <= 8'd10; end
                8'd10: begin `print(port_ffff_write_count, HEX); send_state <= 8'd11; end
                8'd11: begin `print("\n", STR);               send_state <= 8'd12; end

                // 2: mapper FC–FF + W/R counters
                8'd12: begin `print("FC=", STR);              send_state <= 8'd13; end
                8'd13: begin `print(port_fc_value, HEX);      send_state <= 8'd14; end
                8'd14: begin `print(" FD=", STR);             send_state <= 8'd15; end
                8'd15: begin `print(port_fd_value, HEX);      send_state <= 8'd16; end
                8'd16: begin `print(" FE=", STR);             send_state <= 8'd17; end
                8'd17: begin `print(port_fe_value, HEX);      send_state <= 8'd18; end
                8'd18: begin `print(" FF=", STR);             send_state <= 8'd19; end
                8'd19: begin `print(port_ff_value, HEX);      send_state <= 8'd20; end
                8'd20: begin `print("\nMAP W=", STR);         send_state <= 8'd21; end
                8'd21: begin `print(map_fc_wcnt, HEX);        send_state <= 8'd22; end
                8'd22: begin `print("/", STR);                send_state <= 8'd23; end
                8'd23: begin `print(map_fd_wcnt, HEX);        send_state <= 8'd24; end
                8'd24: begin `print("/", STR);                send_state <= 8'd25; end
                8'd25: begin `print(map_fe_wcnt, HEX);        send_state <= 8'd26; end
                8'd26: begin `print("/", STR);                send_state <= 8'd27; end
                8'd27: begin `print(map_ff_wcnt, HEX);        send_state <= 8'd28; end
                8'd28: begin `print(" R=", STR);              send_state <= 8'd29; end
                8'd29: begin `print(map_fc_rcnt, HEX);        send_state <= 8'd30; end
                8'd30: begin `print("/", STR);                send_state <= 8'd31; end
                8'd31: begin `print(map_fd_rcnt, HEX);        send_state <= 8'd32; end
                8'd32: begin `print("/", STR);                send_state <= 8'd33; end
                8'd33: begin `print(map_fe_rcnt, HEX);        send_state <= 8'd34; end
                8'd34: begin `print("/", STR);                send_state <= 8'd35; end
                8'd35: begin `print(map_ff_rcnt, HEX);        send_state <= 8'd36; end
                8'd36: begin `print("\n", STR);               send_state <= 8'd37; end

                // 3: addresses
                8'd37: begin `print("last=", STR);            send_state <= 8'd38; end
                8'd38: begin `print(last_addr[15:8], HEX);    send_state <= 8'd39; end
                8'd39: begin `print(last_addr[7:0], HEX);     send_state <= 8'd40; end
                8'd40: begin `print(" max=", STR);            send_state <= 8'd41; end
                8'd41: begin `print(max_addr[15:8], HEX);     send_state <= 8'd42; end
                8'd42: begin `print(max_addr[7:0], HEX);      send_state <= 8'd43; end
                8'd43: begin `print("\n", STR);               send_state <= 8'd44; end

                // 4: BIOS flags + A9 + reset
                8'd44: begin `print(" flags=", STR);          send_state <= 8'd45; end
                8'd45: begin `print({4'b0, flag_411f, flag_7c76, flag_7b61, flag_0416}, HEX);
                                                        send_state <= 8'd46; end
                8'd46: begin `print(" A9_count=", STR);       send_state <= 8'd47; end
                8'd47: begin `print(port_a9_read_count, HEX); send_state <= 8'd48; end
                8'd48: begin `print(" reset_count=", STR);    send_state <= 8'd49; end
                8'd49: begin `print(reset_count, HEX);        send_state <= 8'd50; end
                8'd50: begin `print("\n", STR);               send_state <= 8'd51; end

                // 5: AUDIO – PSG/OPLL/AUDIO
                8'd51: begin `print(" IO_last=", STR);        send_state <= 8'd52; end
                8'd52: begin `print(last_io_port, HEX);       send_state <= 8'd53; end
                8'd53: begin `print(" PSG A0/1/2=", STR);     send_state <= 8'd54; end
                8'd54: begin `print(psg_a0_cnt, HEX);         send_state <= 8'd55; end
                8'd55: begin `print("/", STR);                send_state <= 8'd56; end
                8'd56: begin `print(psg_a1_cnt, HEX);         send_state <= 8'd57; end
                8'd57: begin `print("/", STR);                send_state <= 8'd58; end
                8'd58: begin `print(psg_a2_cnt, HEX);         send_state <= 8'd59; end
                8'd59: begin `print("\n", STR);               send_state <= 8'd60; end

                8'd60: begin `print(" OPLL 7C/D/E/F=", STR);  send_state <= 8'd61; end
                8'd61: begin `print(opll_7c_cnt, HEX);        send_state <= 8'd62; end
                8'd62: begin `print("/", STR);                send_state <= 8'd63; end
                8'd63: begin `print(opll_7d_cnt, HEX);        send_state <= 8'd64; end
                8'd64: begin `print("/", STR);                send_state <= 8'd65; end
                8'd65: begin `print(opll_7e_cnt, HEX);        send_state <= 8'd66; end
                8'd66: begin `print("/", STR);                send_state <= 8'd67; end
                8'd67: begin `print(opll_7f_cnt, HEX);        send_state <= 8'd68; end
                8'd68: begin `print("\n", STR);               send_state <= 8'd69; end

                8'd69: begin `print(" AUD C0-3 W=", STR);     send_state <= 8'd70; end
                8'd70: begin `print(aud_c0_wcnt, HEX);        send_state <= 8'd71; end
                8'd71: begin `print("/", STR);                send_state <= 8'd72; end
                8'd72: begin `print(aud_c1_wcnt, HEX);        send_state <= 8'd73; end
                8'd73: begin `print("/", STR);                send_state <= 8'd74; end
                8'd74: begin `print(aud_c2_wcnt, HEX);        send_state <= 8'd75; end
                8'd75: begin `print("/", STR);                send_state <= 8'd76; end
                8'd76: begin `print(aud_c3_wcnt, HEX);        send_state <= 8'd77; end
                8'd77: begin `print(" R=", STR);              send_state <= 8'd78; end
                8'd78: begin `print(aud_c0_rcnt, HEX);        send_state <= 8'd79; end
                8'd79: begin `print("/", STR);                send_state <= 8'd80; end
                8'd80: begin `print(aud_c1_rcnt, HEX);        send_state <= 8'd81; end
                8'd81: begin `print("/", STR);                send_state <= 8'd82; end
                8'd82: begin `print(aud_c2_rcnt, HEX);        send_state <= 8'd83; end
                8'd83: begin `print("/", STR);                send_state <= 8'd84; end
                8'd84: begin `print(aud_c3_rcnt, HEX);        send_state <= 8'd85; end
                8'd85: begin `print("\n", STR);               send_state <= 8'd86; end

                // 6: VDP registers + counters
                8'd86: begin `print(" VDP R1/R2/R9=", STR);   send_state <= 8'd87; end
                8'd87: begin `print(vdp_r1, HEX);             send_state <= 8'd88; end
                8'd88: begin `print("/", STR);                send_state <= 8'd89; end
                8'd89: begin `print(vdp_r2, HEX);             send_state <= 8'd90; end
                8'd90: begin `print("/", STR);                send_state <= 8'd91; end
                8'd91: begin `print(vdp_r9, HEX);             send_state <= 8'd92; end
                8'd92: begin `print("\n", STR);               send_state <= 8'd93; end

                8'd93: begin `print(" VDP 98/99 W=", STR);    send_state <= 8'd94; end
                8'd94: begin `print(vdp_98_wcnt, HEX);        send_state <= 8'd95; end
                8'd95: begin `print("/", STR);                send_state <= 8'd96; end
                8'd96: begin `print(vdp_99_wcnt, HEX);        send_state <= 8'd97; end
                8'd97: begin `print(" R=", STR);              send_state <= 8'd98; end
                8'd98: begin `print(vdp_98_rcnt, HEX);        send_state <= 8'd99; end
                8'd99: begin `print("/", STR);                send_state <= 8'd100; end
                8'd100: begin `print(vdp_99_rcnt, HEX);       send_state <= 8'd101; end
                8'd101: begin `print("\n", STR);              send_state <= 8'd102; end

                8'd102: begin `print(" VDP 9A/9B W=", STR);   send_state <= 8'd103; end
                8'd103: begin `print(vdp_9a_wcnt, HEX);       send_state <= 8'd104; end
                8'd104: begin `print("/", STR);               send_state <= 8'd105; end
                8'd105: begin `print(vdp_9b_wcnt, HEX);       send_state <= 8'd106; end
                8'd106: begin `print(" R=", STR);             send_state <= 8'd107; end
                8'd107: begin `print(vdp_9a_rcnt, HEX);       send_state <= 8'd108; end
                8'd108: begin `print("/", STR);               send_state <= 8'd109; end
                8'd109: begin `print(vdp_9b_rcnt, HEX);       send_state <= 8'd110; end
                8'd110: begin `print("\n", STR);              send_state <= 8'd111; end

                // 7: IO 90–9F + history and 9B loop
                8'd111: begin `print(" IO 90-9F cnt=", STR);  send_state <= 8'd112; end
                8'd112: begin `print(io_90_9f_cnt, HEX);      send_state <= 8'd113; end
                8'd113: begin `print(" IO_hist:", STR);       send_state <= 8'd114; end

                // hist[0]
                8'd114: begin `print(" ", STR);               send_state <= 8'd115; end
                8'd115: begin `print(io_hist_port0, HEX);     send_state <= 8'd116; end
                8'd116: begin 
                            if (io_hist_is_write0) `print("W", STR);
                            else                    `print("R", STR);
                            send_state <= 8'd117;
                        end

                // hist[1]
                8'd117: begin `print(" ", STR);               send_state <= 8'd118; end
                8'd118: begin `print(io_hist_port1, HEX);     send_state <= 8'd119; end
                8'd119: begin 
                            if (io_hist_is_write1) `print("W", STR);
                            else                    `print("R", STR);
                            send_state <= 8'd120;
                        end

                // hist[2]
                8'd120: begin `print(" ", STR);               send_state <= 8'd121; end
                8'd121: begin `print(io_hist_port2, HEX);     send_state <= 8'd122; end
                8'd122: begin 
                            if (io_hist_is_write2) `print("W", STR);
                            else                    `print("R", STR);
                            send_state <= 8'd123;
                        end

                // hist[3]
                8'd123: begin `print(" ", STR);               send_state <= 8'd124; end
                8'd124: begin `print(io_hist_port3, HEX);     send_state <= 8'd125; end
                8'd125: begin 
                            if (io_hist_is_write3) `print("W", STR);
                            else                    `print("R", STR);
                            send_state <= 8'd126;
                        end
                8'd126: begin `print("\n", STR);              send_state <= 8'd127; end

                // 9B loop + last values 99/9B
                8'd127: begin `print(" 9B_loop=", STR);       send_state <= 8'd128; end
                8'd128: begin `print(stuck_9b, HEX);          send_state <= 8'd129; end
                8'd129: begin `print(" last99=", STR);        send_state <= 8'd130; end
                8'd130: begin `print(last_99_val0, HEX);      send_state <= 8'd131; end
                8'd131: begin `print("/", STR);               send_state <= 8'd132; end
                8'd132: begin `print(last_99_val1, HEX);      send_state <= 8'd133; end
                8'd133: begin `print("/", STR);               send_state <= 8'd134; end
                8'd134: begin `print(last_99_val2, HEX);      send_state <= 8'd135; end
                8'd135: begin `print(" last9B=", STR);        send_state <= 8'd136; end
                8'd136: begin `print(last_9b_val0, HEX);      send_state <= 8'd137; end
                8'd137: begin `print("/", STR);               send_state <= 8'd138; end
                8'd138: begin `print(last_9b_val1, HEX);      send_state <= 8'd139; end
                8'd139: begin `print("/", STR);               send_state <= 8'd140; end
                8'd140: begin `print(last_9b_val2, HEX);      send_state <= 8'd141; end

                // 8: end of log – newline
                8'd141: begin
                    `print("\n", STR);
                    send_state <= 8'd0;
                end

                default: begin
                    send_state <= 8'd0;
                end
            endcase
        end
    end

    assign boot_ok = (debug_state >= 8'd5);

endmodule