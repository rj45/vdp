// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module  palette_bram #(parameter FILENAME="") (
  input  logic        clk_pix,
  input  logic [7:0]  colour_pix,
  output logic [23:0] rgb
);

  reg [23:0] rom[0:255];

  initial begin
    if (FILENAME!="")
      $readmemh(FILENAME, rom);
  end

  always @(posedge clk_pix) begin
    rgb <= rom[colour_pix];
  end
endmodule