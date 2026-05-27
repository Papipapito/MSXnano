module esp8266e_rom(
    input [13:0] address,
    input clock,
    input [7:0] data,
    input wren,
    output [7:0] q
);

    reg [7:0] mem_r[0:16383];
    reg [7:0] q_r;

initial begin
    $readmemh("./rom/esp8266e.hex", mem_r);
end

    always @(posedge clock) begin
        q_r <= mem_r[address];
    end

    assign q = q_r;

endmodule
