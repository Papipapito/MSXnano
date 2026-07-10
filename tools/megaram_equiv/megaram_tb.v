`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// Testbench de LOGICA para megaram.v (megaram_scc) del core MSXnano.
// Verifica la decodificacion de los 4 mappers (Konami4 / SCC / ASCII8 / ASCII16),
// el banco 0 fijo de Konami4, el gating de SRAM por sram_cfg (feature par 19),
// las paginas de SRAM (segs 252-255) y el reg de modo SCC+ (BFFE).
// Es logica pura de un reloj: no necesita SDRAM ni PLLs.
//
// Correr:  bash run.sh   (dentro de WSL o cualquier bash con Icarus Verilog)
// Salida:  "RESULT: PASS (N checks)"  o  "RESULT: FAIL (x/N failed)"
// -----------------------------------------------------------------------------
module megaram_tb;

    reg         clk = 0;
    reg         rstn;
    reg  [15:0] a;
    reg  [7:0]  d;
    reg         rdn, wrn, sreq, swrt;
    reg  [1:0]  msel;
    reg         mlin;
    reg  [7:0]  scfg;

    wire        mreq, mwrt;
    wire [20:0] maddr;
    wire        sdis, smp, swin;

    megaram_scc dut (
        .clk_27m           (clk),
        .bus_reset_n       (rstn),
        .bus_addr          (a),
        .cpu_dout          (d),
        .bus_rd_n          (rdn),
        .bus_wr_n          (wrn),
        .scc_req           (sreq),
        .scc_wrt           (swrt),
        .map_sel           (msel),
        .map_linear        (mlin),
        .sram_cfg          (scfg),
        .megaram_req       (mreq),
        .megaram_wrt       (mwrt),
        .megaram_addr      (maddr),
        .scc_sound_disable (sdis),
        .scc_mode_plus     (smp),
        .sccplus_win_en    (swin)
    );

    always #10 clk = ~clk;

    integer errors = 0;
    integer tests  = 0;

    // un flanco de reloj (deja asentar los FF registrados ff_scc_mode/ff_sram_mode)
    task settle; begin @(posedge clk); #1; end endtask

    // reset sincrono
    task do_reset; begin
        rstn = 0; @(posedge clk); @(posedge clk); rstn = 1; settle;
    end endtask

    // escribir un registro de banco (strobe scc_wrt durante un flanco)
    task wr; input [15:0] aa; input [7:0] dd; begin
        a = aa; d = dd; sreq = 1; swrt = 1; wrn = 0; rdn = 1;
        @(posedge clk); #1;
        swrt = 0; sreq = 0; wrn = 1;
    end endtask

    // comprobar el segmento (megaram_addr[20:13]) para una lectura en aa
    task chkseg; input [15:0] aa; input [7:0] exp; input [8*40:1] name; begin
        a = aa; rdn = 0; wrn = 1; sreq = 1; swrt = 0; #1;
        tests = tests + 1;
        if (maddr[20:13] !== exp) begin
            errors = errors + 1;
            $display("FAIL: %-34s addr=%h  seg exp=%h got=%h", name, aa, exp, maddr[20:13]);
        end else
            $display("ok  : %-34s addr=%h  seg=%h", name, aa, maddr[20:13]);
    end endtask

    // comprobar un bit de estado
    task chkbit; input val; input exp; input [8*40:1] name; begin
        tests = tests + 1;
        if (val !== exp) begin
            errors = errors + 1;
            $display("FAIL: %-34s exp=%b got=%b", name, exp, val);
        end else
            $display("ok  : %-34s = %b", name, val);
    end endtask

    initial begin
        rstn = 0; a = 0; d = 0; rdn = 1; wrn = 1; sreq = 0; swrt = 0;
        msel = 2'b10; mlin = 0; scfg = 0;
        do_reset;

        $display("== 1) Reset: bancos por defecto 0,1,2,3 (modo SCC) ==");
        msel = 2'b10; settle;
        chkseg(16'h4000, 8'h00, "reset reg0 @4000");
        chkseg(16'h6000, 8'h01, "reset reg1 @6000");
        chkseg(16'h8000, 8'h02, "reset reg2 @8000");
        chkseg(16'hA000, 8'h03, "reset reg3 @A000");

        $display("== 2) Konami4 (map_sel=00): regs 6000/8000/A000, banco0 fijo ==");
        do_reset; msel = 2'b00; settle;
        wr(16'h6000, 8'h0A); chkseg(16'h6000, 8'h0A, "K4 reg1 @6000");
        wr(16'h8000, 8'h10); chkseg(16'h8000, 8'h10, "K4 reg2 @8000");
        wr(16'hA000, 8'h20); chkseg(16'hA000, 8'h20, "K4 reg3 @A000");
        wr(16'h5000, 8'h7F); chkseg(16'h4000, 8'h00, "K4 banco0 fijo (5000 ignorado)");

        $display("== 3) SCC (map_sel=10): regs 5000/7000/9000/B000 ==");
        do_reset; msel = 2'b10; settle;
        wr(16'h5000, 8'h11); chkseg(16'h4000, 8'h11, "SCC reg0 @5000");
        wr(16'h7000, 8'h12); chkseg(16'h6000, 8'h12, "SCC reg1 @7000");
        wr(16'h9000, 8'h13); chkseg(16'h8000, 8'h13, "SCC reg2 @9000");
        wr(16'hB000, 8'h14); chkseg(16'hA000, 8'h14, "SCC reg3 @B000");

        $display("== 4) ASCII8 (map_sel=01): regs 6000/6800/7000/7800, SRAM off ==");
        do_reset; msel = 2'b01; scfg = 8'h00; settle;
        wr(16'h6000, 8'h05); chkseg(16'h4000, 8'h05, "A8 reg0 @6000");
        wr(16'h6800, 8'h06); chkseg(16'h6000, 8'h06, "A8 reg1 @6800");
        wr(16'h7000, 8'h07); chkseg(16'h8000, 8'h07, "A8 reg2 @7000");
        wr(16'h7800, 8'h08); chkseg(16'hA000, 8'h08, "A8 reg3 @7800");

        $display("== 5) SRAM gating ASCII8 (feature par 19) ==");
        // 5a) sram_cfg=0 -> el bit del banco NO abre SRAM (banco normal)
        do_reset; msel = 2'b01; scfg = 8'h00; settle;
        wr(16'h6000, 8'h84);
        chkseg(16'h4000, 8'h84, "A8 sram_cfg=0 -> banco normal");
        // 5b) sram_cfg=0x80 + bit coincide -> SRAM seg 0xFC (252)
        do_reset; msel = 2'b01; scfg = 8'h80; settle;
        wr(16'h6000, 8'h80);
        chkseg(16'h4000, 8'hFC, "A8 SRAM on -> seg 252 (0xFC)");
        // 5c) pagina: 0x83[1:0]=3 -> seg 0xFF (255)
        wr(16'h6000, 8'h83);
        chkseg(16'h4000, 8'hFF, "A8 SRAM page3 -> seg 255 (0xFF)");

        $display("== 6) ASCII16 (map_sel=11): 6000/7000, SRAM valor 0x10 ==");
        do_reset; msel = 2'b11; scfg = 8'h00; settle;
        wr(16'h6000, 8'h02);                              // reg0=0x04, reg1=0x05
        chkseg(16'h4000, 8'h04, "A16 reg0 (low) @6000");
        chkseg(16'h6000, 8'h05, "A16 reg1 (high) @6000");
        do_reset; msel = 2'b11; scfg = 8'h01; settle;
        wr(16'h6000, 8'h10);                              // valor exacto 0x10 -> SRAM
        chkseg(16'h4000, 8'hFC, "A16 SRAM (val 0x10) -> seg 252");

        $display("== 7) Registro de modo SCC+ (BFFE) ==");
        do_reset; msel = 2'b10; settle;
        chkbit(smp, 1'b0, "SCC mode_plus reset = 0");
        wr(16'hBFFE, 8'h20);                              // mode_b bit5 = SCC+ layout
        chkbit(smp, 1'b1, "SCC mode_plus tras BFFE=0x20");

        if (errors == 0)
            $display("\nRESULT: PASS  (%0d checks)", tests);
        else
            $display("\nRESULT: FAIL  (%0d/%0d failed)", errors, tests);
        $finish;
    end

endmodule
