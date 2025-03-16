// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

// This module has the following specs:
// - Two clock domains, the pix clock and the draw clock
// - Two line buffers, one on-screen `on` and one off-screen `off`
// - On-screen buffer is read one pixel at a time in the pix clock domain
// - On-screen buffer is cleared 8 pixels at a time in the draw clock domain
// - Off-screen buffer is written 8 pixels at a time in the draw clock domain
// - Buffers must be flipped, but because of CDC issues, the flip happens separately in each domain

module double_buffer (
    // read port clock
    input  logic         clk_pix,

    // write port clock
    input  logic         clk_draw,

    // buffer select for each clock domain
    input  logic         buffsel_pix,
    input  logic         buffsel_draw,

    // on-screen buffer read port
    input  logic [11:0]  addr_on_pix,
    output logic [8:0]   colour_on_pix,

    // on-screen buffer write port (for clearing)
    input  logic [8:0]   addr_on_draw,
    input  logic         we_on_draw,
    input  logic [71:0]  colour_on_draw,

    // off-screen buffer write port
    input  logic [8:0]   addr_off_draw,
    input  logic [7:0]   we_off_draw,
    input  logic [71:0]  colour_off_draw
);

    logic [11:0]  lb0_addr_pix;
    logic [8:0]   lb0_colour_pix;
    logic [8:0]   lb0_addr_draw;
    logic [7:0]   lb0_we_draw;
    logic [71:0]  lb0_colour_draw;

    linebuffer_bram lb0 (
        .clk_pix,
        .addr_pix(lb0_addr_pix),
        .colour_pix(lb0_colour_pix),

        .clk_draw,
        .addr_draw(lb0_addr_draw),
        .we_draw(lb0_we_draw),
        .colour_draw(lb0_colour_draw)
    );

    logic [11:0] lb1_addr_pix;
    logic [8:0]  lb1_colour_pix;
    logic [8:0]  lb1_addr_draw;
    logic [7:0]  lb1_we_draw;
    logic [71:0] lb1_colour_draw;

    linebuffer_bram lb1 (
        .clk_pix,
        .addr_pix(lb1_addr_pix),
        .colour_pix(lb1_colour_pix),

        .clk_draw,
        .addr_draw(lb1_addr_draw),
        .we_draw(lb1_we_draw),
        .colour_draw(lb1_colour_draw)
    );

    // The addr_on_pix needs to be delayed by one cycle because the bram takes a cycle to read
    logic [2:0]  prev_addr_on_pix;

    // handle the pix side reading
    always_comb begin
        if (buffsel_pix) begin
            lb0_addr_pix = addr_on_pix;
            lb1_addr_pix = 0;
            colour_on_pix = lb0_colour_pix;
        end else begin
            lb1_addr_pix = addr_on_pix;
            lb0_addr_pix = 0;
            colour_on_pix = lb1_colour_pix;
        end
    end

    // draw write ports
    always_comb begin
        if (buffsel_draw) begin
            lb0_addr_draw = addr_on_draw;
            lb0_we_draw = {8{we_on_draw}};
            lb0_colour_draw = colour_on_draw;

            lb1_addr_draw = addr_off_draw;
            lb1_we_draw = we_off_draw;
            lb1_colour_draw = colour_off_draw;
        end else begin
            lb1_addr_draw = addr_on_draw;
            lb1_we_draw = {8{we_on_draw}};
            lb1_colour_draw = colour_on_draw;

            lb0_addr_draw = addr_off_draw;
            lb0_we_draw = we_off_draw;
            lb0_colour_draw = colour_off_draw;
        end
    end

endmodule
