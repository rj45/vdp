// (C) 2023 Ryan "rj45" Sanche, MIT License

// This module takes 4 pixels from the tile reader and prepares them
// for writing to the line buffer.
// Note: there must be at least one cycle where tile_valid_mask is zero between
// sprites in order to flush the remaining pixels out.


`default_nettype none
`timescale 1ns / 1ps

module pixel_doubler (
    input  logic         clk_draw,
    input  logic         rst_draw,

    input  logic [35:0]  tile_pixels,         // 4 input pixels
    input  logic [3:0]   tile_valid_mask,     // mask indicating which pixels to draw
    input  logic [11:0]  lb_x,                // x position of left-most pixel in sub-pixels in linebuffer

    output logic [8:0]   lb_addr,             // line buffer address
    output logic [143:0] unaligned_pixels,    // pixels prepared to be aligned
    output logic [15:0]  unaligned_valid_mask,// valid bits for each pixel in unaligned_pixels
    output logic [2:0]   alignment_shift      // amount to shift in order to align the pixels
);

    reg [71:0] prev_pixels;
    reg [7:0] prev_valid;

    logic [71:0] next_pixels;
    logic [7:0] next_valid;

    // double the input pixels and their valid bits
    always_comb begin
        next_pixels = {
            { 2{tile_pixels[35:27]} },
            { 2{tile_pixels[26:18]} },
            { 2{tile_pixels[17:9]} },
            { 2{tile_pixels[8:0]} }
        };
        next_valid = {
            { 2{tile_valid_mask[3]} },
            { 2{tile_valid_mask[2]} },
            { 2{tile_valid_mask[1]} },
            { 2{tile_valid_mask[0]} }
        };
    end

    // concat the previous pixels with the new pixels so that the `shift_aligner`
    // module has all the pixels necessary to to write up to 8 pixels per cycle
    // into the line buffer
    always_ff @(posedge clk_draw) begin
        if (rst_draw) begin
            lb_addr <= 9'h0;
            unaligned_pixels <= 144'h0;
            unaligned_valid_mask <= 16'h0;
            alignment_shift <= 3'h0;
            prev_pixels <= 72'h0;
            prev_valid <= 8'h0;
        end else begin
            lb_addr <= lb_x[11:3];
            unaligned_pixels <= {prev_pixels, next_pixels};
            unaligned_valid_mask <= {prev_valid, next_valid};
            alignment_shift <= lb_x[2:0];

            prev_pixels <= next_pixels;
            prev_valid <= next_valid;
        end
    end


endmodule
