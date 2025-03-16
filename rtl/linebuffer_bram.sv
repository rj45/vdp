// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module  linebuffer_bram (
    // read port
    input  logic        clk_pix,
    input  logic [11:0] addr_pix,
    output logic [8:0]  colour_pix,

    // write port
    input logic         clk_draw,
    input logic [8:0]   addr_draw,
    input logic [7:0]   we_draw,
    input logic [71:0]  colour_draw
);

    // 2 brams on the ecp5
    reg [8:0] mem[0:4095];

    always @(posedge clk_pix) begin
        colour_pix <= mem[addr_pix];
    end

    always @(posedge clk_draw) begin
        if (we_draw[3'h0]) mem[{addr_draw, 3'h7}] <= colour_draw[8:0];
        if (we_draw[3'h1]) mem[{addr_draw, 3'h6}] <= colour_draw[17:9];
        if (we_draw[3'h2]) mem[{addr_draw, 3'h5}] <= colour_draw[26:18];
        if (we_draw[3'h3]) mem[{addr_draw, 3'h4}] <= colour_draw[35:27];
        if (we_draw[3'h4]) mem[{addr_draw, 3'h3}] <= colour_draw[44:36];
        if (we_draw[3'h5]) mem[{addr_draw, 3'h2}] <= colour_draw[53:45];
        if (we_draw[3'h6]) mem[{addr_draw, 3'h1}] <= colour_draw[62:54];
        if (we_draw[3'h7]) mem[{addr_draw, 3'h0}] <= colour_draw[71:63];
    end

endmodule
