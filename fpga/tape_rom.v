// ============================================================================
// tape_rom - ROM de imagen de cinta (.cvt) embebida en BSRAM para la cinta
// virtual. Lectura sincrona (2 ciclos de latencia: registro BSRAM + registro
// de seleccion de banco), holgadisima para cas_player (muestrea ~15 clks
// despues, via ce).
//
// TROCEADA EN BANCOS EXPLICITOS DE 2KB (1 primitivo BSRAM cada uno, con su
// propio $readmemh): inferir UN array grande repartido en varios BSRAM dejaba
// el contenido corrupto mas alla del primer primitivo (visto en HW: todo lo
// que vivia bajo 2KB se servia bien y el bloque grande no). Cada banco replica
// exactamente el patron de 1 primitivo que si esta validado en placa.
//
// Los tape_bankN.hex los genera fpga/mkbanks.py desde un .cvt (2048 lineas
// exactas por fichero, relleno a cero). Estan en .gitignore (datos de juegos
// con copyright) — regenerarlos en local antes de compilar.
// ============================================================================
module tape_rom #(
    parameter ADDRW = 16            // 9 bancos x 2KB = 18432 bytes utiles
)(
    input  wire             clk,
    input  wire [ADDRW-1:0] addr,
    output reg  [7:0]       data
);
    (* syn_ramstyle = "block_ram" *) reg [7:0] mem0 [0:2047];
    (* syn_ramstyle = "block_ram" *) reg [7:0] mem1 [0:2047];
    (* syn_ramstyle = "block_ram" *) reg [7:0] mem2 [0:2047];
    (* syn_ramstyle = "block_ram" *) reg [7:0] mem3 [0:2047];
    (* syn_ramstyle = "block_ram" *) reg [7:0] mem4 [0:2047];
    (* syn_ramstyle = "block_ram" *) reg [7:0] mem5 [0:2047];
    (* syn_ramstyle = "block_ram" *) reg [7:0] mem6 [0:2047];
    (* syn_ramstyle = "block_ram" *) reg [7:0] mem7 [0:2047];
    (* syn_ramstyle = "block_ram" *) reg [7:0] mem8 [0:2047];

    initial begin
        $readmemh("tape_bank0.hex", mem0);
        $readmemh("tape_bank1.hex", mem1);
        $readmemh("tape_bank2.hex", mem2);
        $readmemh("tape_bank3.hex", mem3);
        $readmemh("tape_bank4.hex", mem4);
        $readmemh("tape_bank5.hex", mem5);
        $readmemh("tape_bank6.hex", mem6);
        $readmemh("tape_bank7.hex", mem7);
        $readmemh("tape_bank8.hex", mem8);
    end

    reg [7:0] d0, d1, d2, d3, d4, d5, d6, d7, d8;
    reg [3:0] bank_r;
    always @(posedge clk) begin
        d0 <= mem0[addr[10:0]];
        d1 <= mem1[addr[10:0]];
        d2 <= mem2[addr[10:0]];
        d3 <= mem3[addr[10:0]];
        d4 <= mem4[addr[10:0]];
        d5 <= mem5[addr[10:0]];
        d6 <= mem6[addr[10:0]];
        d7 <= mem7[addr[10:0]];
        d8 <= mem8[addr[10:0]];
        bank_r <= addr[14:11];
        case (bank_r)
            4'd0: data <= d0;
            4'd1: data <= d1;
            4'd2: data <= d2;
            4'd3: data <= d3;
            4'd4: data <= d4;
            4'd5: data <= d5;
            4'd6: data <= d6;
            4'd7: data <= d7;
            default: data <= d8;
        endcase
    end
endmodule
