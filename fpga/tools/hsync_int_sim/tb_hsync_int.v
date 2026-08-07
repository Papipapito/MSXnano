// ============================================================================
// tb_hsync_int.v - Demuestra la DOBLE interrupcion de linea del VDP y valida
//                  el arreglo.
//
// ---------------------------------------------------------------------------
// QUE ES ESTO Y QUE NO ES
// ---------------------------------------------------------------------------
// Icarus no simula VHDL y no hay GHDL instalado, asi que esto NO es el RTL de
// produccion: es una TRANSCRIPCION LITERAL a Verilog de los tres trozos de VHDL
// que intervienen. Cada bloque lleva citado el original. Sirve para demostrar el
// mecanismo y validar el arreglo; NO sustituye a una prueba en placa.
//
//   1) vdp.vhd:1142-1151  -- generacion de ACTIVE_LINE
//        IF( PREDOTCOUNTER_X = 255+25 OR PREDOTCOUNTER_X = "111111111" )THEN
//            ACTIVE_LINE <= '1';
//
//   2) vdp_ssg.vhd:399-400 -- avance de linea
//        W_HSYNC <= '1' WHEN( W_H_CNT(1 DOWNTO 0) = "10" AND
//                             FF_PRE_X_CNT = "111111111" ) ELSE '0';
//      ...y el retardo de un ciclo del contador Y (vdp_ssg.vhd:454):
//        FF_PRE_Y_CNT <= FF_MONITOR_LINE + ("0" & REG_R23_VSTART_LINE);
//
//   3) vdp_interrupt.vhd:116-129 -- el latch de la peticion
//        IF( CLR_HSYNC_INT = '1' OR ... )THEN  FF_HSYNC_INT_N <= '1';
//        ELSIF( ACTIVE_LINE = '1' AND Y_CNT = REG_R19 )THEN FF_HSYNC_INT_N <= '0';
//
// ---------------------------------------------------------------------------
// EL BUG
// ---------------------------------------------------------------------------
// ACTIVE_LINE se activa DOS veces por linea: en PREDOTCOUNTER_X=280 y otra vez
// en 511. Y 511 es EXACTAMENTE el punto donde avanza la linea, con el contador
// Y todavia un ciclo por detras -o sea, aun valiendo el numero de la linea
// ANTERIOR-. Resultado: la misma linea casa dos veces con R#19, separadas por
// decenas de microsegundos.
//
// Como el borrado (leer S#1) es un PULSO, si el software hace el ack entre las
// dos ventanas, la segunda vuelve a pedir interrupcion y la ISR corre DOS VECES
// en la misma linea. Que caiga dentro o fuera depende de que instruccion
// estuviera ejecutando el Z80 al aceptar la INT -> falla en un PORCENTAJE de
// frames, no siempre. Es el sintoma exacto del jitter de R-Type con el parche
// de smooth-scroll.
//
// Ni el upstream OCM (una sola ventana, calibrada por KdL segun el modo) ni el
// clon independiente TangCartMSX (PREDOTCOUNTER_X = 255) tienen el segundo
// termino: es exclusivo del linaje goauld.
//
//   iverilog -g2012 -o tb tb_hsync_int.v && vvp tb
// ============================================================================
`timescale 1ns / 1ps

module tb_hsync_int;

    // ---- parametros del modelo -------------------------------------------
    localparam LINE_END   = 428;   // ultimo valor de PRE_X_CNT antes de recargar
    localparam PRE_START  = 504;   // recarga a -8 (en 9 bits, 504)
    localparam WIN_A      = 280;   // 255+25, la ventana "buena"
    localparam WIN_B      = 511;   // "111111111", la ventana ESPURIA
    localparam R19        = 8'd100;// linea de interrupcion programada

    reg clk = 0;
    always #5 clk = ~clk;          // 100 MHz de mentira: solo cuentan los ciclos

    // ---- 1) contador de puntos: +1 cada 4 ciclos (W_H_CNT(1:0)="10") ------
    reg [1:0] h_phase   = 0;
    reg [8:0] pre_x_cnt = PRE_START;
    reg [7:0] monitor_line = 0;
    reg [7:0] y_cnt       = 0;     // FF_PRE_Y_CNT: UN CICLO por detras

    wire tick = (h_phase == 2'b10);
    // vdp_ssg.vhd:399 -- el avance de linea cae en el MISMO 511
    wire w_hsync = tick && (pre_x_cnt == 9'h1FF);

    always @(posedge clk) begin
        h_phase <= h_phase + 1'b1;
        if (tick) begin
            if (pre_x_cnt == LINE_END) pre_x_cnt <= PRE_START;
            else                       pre_x_cnt <= pre_x_cnt + 1'b1;
            if (w_hsync) monitor_line <= monitor_line + 1'b1;
        end
        y_cnt <= monitor_line;     // el retardo de un ciclo, que es la clave
    end

    // ---- 2) ACTIVE_LINE: con y sin el termino espurio ---------------------
    reg active_bug = 0, active_fix = 0;
    always @(posedge clk) begin
        active_bug <= (pre_x_cnt == WIN_A) || (pre_x_cnt == WIN_B);  // ACTUAL
        active_fix <= (pre_x_cnt == WIN_A);                          // ARREGLADO
    end

    // ---- 3) el latch de peticion (vdp_interrupt.vhd) ----------------------
    reg  int_n_bug = 1, int_n_fix = 1;
    reg  clr = 0;
    always @(posedge clk) begin
        if (clr)                                        int_n_bug <= 1'b1;
        else if (active_bug && (y_cnt == R19))          int_n_bug <= 1'b0;
        if (clr)                                        int_n_fix <= 1'b1;
        else if (active_fix && (y_cnt == R19))          int_n_fix <= 1'b0;
    end

    // ---- el "software": ack (leer S#1) N ciclos despues de ver la IRQ -----
    integer ack_delay;
    integer irqs_bug, irqs_fix;
    reg     seen_bug, seen_fix;
    integer wait_bug, wait_fix;
    integer fallos = 0;

    task automatic prueba(input integer delay_ciclos);
        integer ciclo;
        begin
            ack_delay = delay_ciclos;
            irqs_bug = 0; irqs_fix = 0;
            seen_bug = 0; seen_fix = 0;
            // arrancar limpio en la linea 0
            @(negedge clk);
            pre_x_cnt = PRE_START; monitor_line = 0; y_cnt = 0;
            int_n_bug = 1; int_n_fix = 1; clr = 0;

            // dos lineas completas de margen alrededor de la linea R19
            for (ciclo = 0; ciclo < 4*(LINE_END+16)*(R19+3); ciclo = ciclo + 1) begin
                @(negedge clk);
                clr = 0;
                // contar flancos de peticion
                if (!int_n_bug && !seen_bug) begin
                    irqs_bug = irqs_bug + 1; seen_bug = 1; wait_bug = ack_delay;
                end
                if (!int_n_fix && !seen_fix) begin
                    irqs_fix = irqs_fix + 1; seen_fix = 1; wait_fix = ack_delay;
                end
                // el ack del software, ack_delay ciclos despues
                if (seen_bug) begin
                    if (wait_bug == 0) begin clr = 1; seen_bug = 0; end
                    else wait_bug = wait_bug - 1;
                end
                if (seen_fix && wait_fix > 0) wait_fix = wait_fix - 1;
            end
        end
    endtask

    // El ack tiene que llegar por el mismo camino para los dos, asi que se
    // hace una pasada por variante para no mezclar los pulsos de clr.
    task automatic mide(input integer delay_ciclos, input integer usar_fix,
                        output integer cuenta);
        integer ciclo;
        begin
            cuenta = 0;
            @(negedge clk);
            pre_x_cnt = PRE_START; monitor_line = 0; y_cnt = 0;
            int_n_bug = 1; int_n_fix = 1; clr = 0; seen_bug = 0;
            wait_bug = 0;
            for (ciclo = 0; ciclo < 4*(LINE_END+16)*(R19+3); ciclo = ciclo + 1) begin
                @(negedge clk);
                clr = 0;
                if (usar_fix) begin
                    if (!int_n_fix && !seen_bug) begin
                        cuenta = cuenta + 1; seen_bug = 1; wait_bug = delay_ciclos;
                    end
                end else begin
                    if (!int_n_bug && !seen_bug) begin
                        cuenta = cuenta + 1; seen_bug = 1; wait_bug = delay_ciclos;
                    end
                end
                if (seen_bug) begin
                    if (wait_bug == 0) begin clr = 1; seen_bug = 0; end
                    else wait_bug = wait_bug - 1;
                end
            end
        end
    endtask

    integer d, n_bug, n_fix, dobles = 0;

    initial begin
        $display("== Interrupcion de linea del VDP: doble disparo y arreglo ==");
        $display("   R#19 = %0d ; ventanas ACTUALES: PRE=%0d y PRE=%0d", R19, WIN_A, WIN_B);
        $display("");
        $display("   ack tras   ACTUAL   ARREGLADO");
        $display("   --------   ------   ---------");

        // barrido del retardo del ack, en ciclos (1 punto = 4 ciclos)
        for (d = 4; d <= 2400; d = d + 190) begin
            mide(d, 0, n_bug);
            mide(d, 1, n_fix);
            $display("   %6d c   %4d     %4d %s", d, n_bug, n_fix,
                     (n_bug > 1) ? "  <-- DOS interrupciones para la MISMA linea" : "");
            if (n_bug > 1) dobles = dobles + 1;
            if (n_fix != 1) begin
                $display("   FALLO: el arreglo dio %0d interrupciones (esperaba 1)", n_fix);
                fallos = fallos + 1;
            end
        end

        $display("");
        if (dobles == 0) begin
            $display("FALLO: no se ha reproducido el doble disparo; el modelo no vale");
            fallos = fallos + 1;
        end else begin
            $display("OK  el codigo ACTUAL dispara dos veces en %0d de los retardos probados", dobles);
        end
        if (fallos == 0)
            $display("OK  el ARREGLADO dispara EXACTAMENTE una vez con cualquier retardo");

        $display("");
        // OJO: $display con un ternario de cadenas las trata como enteros y
        // saca un numero. Hay que ramificar de verdad.
        if (fallos == 0) $display("== PASS ==");
        else             $display("== HAY FALLOS ==");
        $finish;
    end

endmodule
