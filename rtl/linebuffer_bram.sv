// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module  linebuffer_bram (
    // read port
    input  wire logic         clk_pix,
    input  wire logic [6:0]   addr_pix,
    output      logic [127:0] colour_pix,

    // write port
    input wire logic          clk_draw,
    input wire logic [6:0]    addr_draw,
    input wire logic [15:0]   we_draw,
    input wire logic [127:0]  colour_draw
);

    reg [127:0] mem[0:127];

    always @(posedge clk_pix) begin
        colour_pix <= mem[addr_pix];
    end

    always @(posedge clk_draw) begin
        if (we_draw[4'h0]) mem[addr_draw][7:0] <= colour_draw[7:0];
        if (we_draw[4'h1]) mem[addr_draw][15:8] <= colour_draw[15:8];
        if (we_draw[4'h2]) mem[addr_draw][23:16] <= colour_draw[23:16];
        if (we_draw[4'h3]) mem[addr_draw][31:24] <= colour_draw[31:24];
        if (we_draw[4'h4]) mem[addr_draw][39:32] <= colour_draw[39:32];
        if (we_draw[4'h5]) mem[addr_draw][47:40] <= colour_draw[47:40];
        if (we_draw[4'h6]) mem[addr_draw][55:48] <= colour_draw[55:48];
        if (we_draw[4'h7]) mem[addr_draw][63:56] <= colour_draw[63:56];
        if (we_draw[4'h8]) mem[addr_draw][71:64] <= colour_draw[71:64];
        if (we_draw[4'h9]) mem[addr_draw][79:72] <= colour_draw[79:72];
        if (we_draw[4'ha]) mem[addr_draw][87:80] <= colour_draw[87:80];
        if (we_draw[4'hb]) mem[addr_draw][95:88] <= colour_draw[95:88];
        if (we_draw[4'hc]) mem[addr_draw][103:96] <= colour_draw[103:96];
        if (we_draw[4'hd]) mem[addr_draw][111:104] <= colour_draw[111:104];
        if (we_draw[4'he]) mem[addr_draw][119:112] <= colour_draw[119:112];
        if (we_draw[4'hf]) mem[addr_draw][127:120] <= colour_draw[127:120];
    end

endmodule