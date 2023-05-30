// (C) 2023 Ryan "rj45" Sanche, MIT License

// This module takes a pair of pixels from the tile reader and prepares them
// for writing to the line buffer.
// Note: there must be at least one cycle where in_valid_mask is zero between
// sprites in order to flush the remaining pixels out.


`default_nettype none
`timescale 1ns / 1ps

module pixel_quadrupler (
    input  logic         clk_draw,
    input  logic         rst_draw,

    input  logic [31:0]  tile_pixels,         // 4 input pixels
    input  logic [3:0]   tile_valid_mask,     // mask indicating which pixels to draw
    input  logic [10:0]  lb_x,                // x position of left-most pixel in sub-pixels in linebuffer

    output logic [6:0]   lb_addr,             // line buffer address
    output logic [255:0] unaligned_pixels,    // pixels prepared to be aligned
    output logic [31:0]  unaligned_valid_mask,// valid bits for each pixel in unaligned_pixels
    output logic [3:0]   alignment_shift     // amount to shift in order to align the pixels
);

    reg [127:0] prev_pixels;
    reg [15:0] prev_valid;

    logic [127:0] next_pixels;
    logic [15:0] next_valid;

    // quadruple the input pixels and their valid bits
    always_comb begin
        next_pixels = {
            { 4{tile_pixels[31:24]} },
            { 4{tile_pixels[23:16]} },
            { 4{tile_pixels[15:8]} },
            { 4{tile_pixels[7:0]} }
        };
        next_valid = {
            { 4{tile_valid_mask[3]} },
            { 4{tile_valid_mask[2]} },
            { 4{tile_valid_mask[1]} },
            { 4{tile_valid_mask[0]} }
        };
    end

    // concat the previous pixels with the new pixels so that the `shift_aligner`
    // module has all the pixels necessary to to write up to 16 pixels per cycle
    // into the line buffer
    always_ff @(posedge clk_draw) begin
        if (rst_draw) begin
            lb_addr <= 7'h0;
            unaligned_pixels <= 256'h0;
            unaligned_valid_mask <= 32'h0;
            alignment_shift <= 4'h0;
            prev_pixels <= 128'h0;
            prev_valid <= 16'h0;
        end else begin
            lb_addr <= lb_x[10:4];
            unaligned_pixels <= {prev_pixels, next_pixels};
            unaligned_valid_mask <= {prev_valid, next_valid};
            alignment_shift <= lb_x[3:0];

            prev_pixels <= next_pixels;
            prev_valid <= next_valid;
        end
    end


endmodule
