// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module  linebuffer_bram (
    // read port
    input  wire logic        clk_pix,
    input  wire logic [10:0] addr_pix,
    output      logic [7:0]  colour_pix,

    // write port
    input wire logic         clk_draw,
    input wire logic [10:0]  addr_draw,
    input wire logic         we_draw,
    input      logic [7:0]   colour_draw
);

    reg [7:0] mem[0:2047];

    always @(posedge clk_pix) begin
        colour_pix <= mem[addr_pix];
    end

    always @(posedge clk_draw) begin
        if (we_draw) begin
            mem[addr_draw] <= colour_draw;
        end
    end

endmodule