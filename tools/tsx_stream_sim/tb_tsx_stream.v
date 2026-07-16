// ============================================================================
// tb_tsx_stream - Testbench de la cadena de cinta por STREAM:
//   sender UART (modelo del ESP32-C6, respeta RTR) -> tape_uart (FIFO 2KB)
//   -> cas_stream (KCS) -> decodificador KCS del TB -> compara byte a byte
//   con expected.hex. Ademas: pausa de MOTOR a mitad de carga (como hace la
//   BIOS entre bloques) y chequeo de que el FIFO nunca pierde bytes.
//
// SIM_FAST: pulsos KCS /10 (73/146) para acelerar; la logica es identica y el
// decodificador clasifica por umbral relativo. Pasa igualmente con los valores
// reales quitando -DSIM_FAST (mas lento).
//
// PASS = "TB PASS" y $finish con 0 errores. Cualquier discrepancia -> $fatal.
// ============================================================================
`timescale 1ns/1ns
module tb_tsx_stream;

`ifdef SIM_TURBO                      // /50: para imagenes grandes (70KB)
    localparam P_ONE  = 16'd15,  P_ZERO = 16'd30;
    localparam P_PLNG = 16'd320, P_PSHT = 16'd120;
`elsif SIM_FAST                       // /10: por defecto
    localparam P_ONE  = 16'd73,  P_ZERO = 16'd146;
    localparam P_PLNG = 16'd800, P_PSHT = 16'd300;
`else                                 // valores reales (lento)
    localparam P_ONE  = 16'd731,  P_ZERO = 16'd1463;
    localparam P_PLNG = 16'd8000, P_PSHT = 16'd3000;
`endif

    // ---- relojes: clk ~54MHz; ce = 1 de cada 15 (T-state 3.6MHz) ----
    reg clk = 0;
    always #9 clk = ~clk;
    reg [3:0] cediv = 0;
    reg ce = 0;
    always @(posedge clk) begin
        cediv <= (cediv == 4'd14) ? 4'd0 : cediv + 4'd1;
        ce    <= (cediv == 4'd14);
    end

    // ---- DUTs ----
    reg  rst = 1, motor = 0, load = 0, rx = 1;
    wire pop_req, pop_valid, flush, casin, playing, rtr;
    wire [7:0]  pop_data;
    wire [3:0]  dbg_st;
    wire [10:0] fill;

    tape_uart #(.CLK_FREQ(54_000_000), .BAUD(115_200)) uut_fifo (
        .clk(clk), .rst(rst), .rx(rx), .flush(flush),
        .pop_req(pop_req), .pop_valid(pop_valid), .pop_data(pop_data),
        .rtr(rtr), .fill_dbg(fill)
    );
    cas_stream #(.PULSE_ONE(P_ONE), .PULSE_ZERO(P_ZERO),
                 .PILOT_LONG(P_PLNG), .PILOT_SHORT(P_PSHT)) uut_cas (
        .clk(clk), .ce(ce), .rst(rst), .motor(motor), .load(load),
        .pop_req(pop_req), .pop_valid(pop_valid), .pop_data(pop_data),
        .flush(flush), .casin(casin), .playing(playing), .dbg_st(dbg_st)
    );

    // ---- datos ----
    reg [7:0] stream   [0:262143];
    reg [7:0] expected [0:262143];
    integer   stream_len, expected_len;

    // ---- sender UART: manda stream[] respetando RTR (modelo del C6) ----
    localparam BITCLKS = 468;           // 54e6/115200
    task uart_byte(input [7:0] b);
        integer i;
        begin
            rx = 0; repeat (BITCLKS) @(posedge clk);            // start
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i]; repeat (BITCLKS) @(posedge clk);      // datos LSB
            end
            rx = 1; repeat (BITCLKS) @(posedge clk);            // stop
        end
    endtask
    integer sent = 0;
    reg sender_on = 0;
    initial begin : sender
        wait (sender_on);
        while (sent < stream_len) begin
            wait (rtr === 1'b1);         // flow control por nivel
            uart_byte(stream[sent]);
            sent = sent + 1;
        end
        $display("[TB] sender: %0d bytes mandados", sent);
    end

    // ---- perdida de bytes: si llega rx_valid con FIFO lleno seria un drop ----
    always @(posedge clk)
        if (!rst && uut_fifo.rx_valid && uut_fifo.full)
            $fatal(1, "[TB] FIFO OVERFLOW: byte descartado (RTR no respetado?)");

    // ---- decodificador KCS: mide medios-ciclos de casin en ticks de ce ----
    integer halfticks = 0;
    reg     casin_p = 1;
    integer nbits, nbytes, errors;
    reg [7:0] cur;
    integer pulse_is_one;
    // clasifica el medio ciclo: < umbral -> "one", si no -> "zero"
    localparam THRESH = (P_ONE + P_ZERO) / 2;
    // estado del ensamblador de bytes
    integer dstate;   // 0=espera start, 1..8=bits de datos, 9=stops
    integer zcnt, ocnt, stopcnt;
    initial begin dstate = 0; zcnt = 0; ocnt = 0; stopcnt = 0;
                  nbits = 0; nbytes = 0; errors = 0; end

    task got_pulse(input integer isone);
        begin
            if (dstate == 0) begin
                // pilot/idle: pulsos "one" se ignoran; un "zero" arranca el start
                if (!isone) begin
                    zcnt = zcnt + 1;
                    if (zcnt == 2) begin dstate = 1; zcnt = 0; ocnt = 0; cur = 0; end
                end else zcnt = 0;
            end else if (dstate >= 1 && dstate <= 8) begin
                if (isone) begin
                    ocnt = ocnt + 1;
                    if (ocnt == 4) begin
                        cur[dstate-1] = 1'b1;
                        dstate = dstate + 1; ocnt = 0; zcnt = 0;
                    end
                end else begin
                    if (ocnt != 0) begin
                        errors = errors + 1;
                        $fatal(1, "[TB] pulso zero a mitad de bit-1 (byte %0d)", nbytes);
                    end
                    zcnt = zcnt + 1;
                    if (zcnt == 2) begin
                        cur[dstate-1] = 1'b0;
                        dstate = dstate + 1; zcnt = 0;
                    end
                end
                if (dstate == 9) begin stopcnt = 0; end
            end else begin // dstate==9: 2 bits de stop = 8 pulsos "one"
                if (!isone) $fatal(1, "[TB] pulso zero en los stop bits (byte %0d)", nbytes);
                stopcnt = stopcnt + 1;
                if (stopcnt == 8) begin
                    if (cur !== expected[nbytes]) begin
                        errors = errors + 1;
                        $display("[TB] MISMATCH byte %0d: dec=%02x esp=%02x",
                                 nbytes, cur, expected[nbytes]);
                        if (errors > 5) $fatal(1, "[TB] demasiados errores");
                    end
                    nbytes = nbytes + 1;
                    dstate = 0; zcnt = 0; ocnt = 0;
                end
            end
        end
    endtask

    always @(posedge clk) if (ce) begin
        if (casin !== casin_p) begin
            if (playing && halfticks > 0)
                got_pulse((halfticks < THRESH) ? 1 : 0);
            casin_p   <= casin;
            halfticks <= 1;
        end else halfticks <= halfticks + 1;
    end

    // ---- pausa de motor a mitad de carga (la BIOS para el motor entre
    //      bloques; el stream debe congelarse y el FIFO absorber via RTR) ----
    initial begin : motorpause
        wait (nbytes > 20);
        motor = 0;
        $display("[TB] motor OFF en byte %0d (fill=%0d)", nbytes, fill);
        repeat (200000) @(posedge clk);
        $display("[TB] motor ON (fill=%0d)", fill);
        motor = 1;
    end

    // ---- secuencia principal ----
    integer t0;
    initial begin
        $readmemh("out/stream.hex", stream);
        $readmemh("out/expected.hex", expected);
        stream_len   = `STREAM_LEN;
        expected_len = `EXPECTED_LEN;
        $display("[TB] stream=%0d bytes, payload esperado=%0d bytes",
                 stream_len, expected_len);
        repeat (20) @(posedge clk);
        rst = 0; motor = 1;
        repeat (20) @(posedge clk);
        sender_on = 1;                   // el C6 empieza a mandar
        repeat (100) @(posedge clk);
        load = 1;                        // el MSX arma la cinta (RUN"CAS:")
        repeat (40) @(posedge clk);

        // esperar el final: todos los bytes decodificados y FSM en S_DONE
        t0 = 0;
        while ((nbytes < expected_len) && (t0 < 2_000_000_000)) begin
            repeat (10000) @(posedge clk);
            t0 = t0 + 10000;
        end
        if (nbytes != expected_len)
            $fatal(1, "[TB] TIMEOUT: %0d/%0d bytes decodificados", nbytes, expected_len);
        // dar tiempo a que el FSM cierre el ultimo bloque
        repeat (200000) @(posedge clk);
        if (dbg_st != 4'd13)             // S_DONE
            $fatal(1, "[TB] FSM no llego a S_DONE (st=%0d)", dbg_st);
        if (errors != 0)
            $fatal(1, "[TB] %0d errores de byte", errors);
        $display("[TB] PASS: %0d bytes byte-exactos, S_DONE, motor-pause OK, 0 drops",
                 nbytes);
        $finish;
    end
endmodule
