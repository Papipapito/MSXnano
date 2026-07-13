// ============================================================================
// tape_rom - ROM de imagen de cinta (.cvt) embebida en BSRAM para el test de
// cinta virtual. Lectura sincrona (1 ciclo de latencia) que encaja con el
// estado S_RD de cas_player. Inicializada por $readmemh desde un .hex (un byte
// hex por linea). Gowin infiere BSRAM de este patron (read sincrono).
// ============================================================================
module tape_rom #(
    parameter ADDRW   = 16,
    parameter DEPTH   = 512,
    parameter HEXFILE = "testcv.hex"
)(
    input  wire             clk,
    input  wire [ADDRW-1:0] addr,
    output reg  [7:0]       data
);
    (* syn_ramstyle = "block_ram" *) reg [7:0] mem [0:DEPTH-1];
    initial $readmemh(HEXFILE, mem);
    always @(posedge clk) data <= mem[addr];
endmodule
