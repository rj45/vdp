// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module palette_bram #(parameter FILENAME="") (
    input  logic        clk_pix,
    input  logic [8:0]  colour_pix,
    output logic [7:0]  r,
    output logic [7:0]  g,
    output logic [7:0]  b
);

    reg [23:0] rom[0:511];

    initial begin
        if (FILENAME!="")
            $readmemh(FILENAME, rom);
    end

    always @(posedge clk_pix) begin
        r <= rom[colour_pix][23:16];
        g <= rom[colour_pix][15:8];
        b <= rom[colour_pix][7:0];
    end

endmodule
