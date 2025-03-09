// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module shift_aligner (
    input  logic clk_draw,
    input  logic rst_draw,

    input  logic [255:0] unaligned_pixels,      // 32 unaligned pixels
    input  logic [31:0]  unaligned_valid_mask,  // 32 valid mask bits
    input  logic [3:0]   alignment_shift,       // amount to shift by

    output logic [127:0] aligned_pixels,        // 16 aligned pixels
    output logic [15:0]  aligned_valid_mask     // 16 bit valid mask
);

    always_ff @(posedge clk_draw) begin
        if (rst_draw) begin
            aligned_pixels <= 128'h0;
            aligned_valid_mask <= 16'h0;
        end else begin
            // select 128 bits from the unaligned pixels at the offset alignment_shift*8
            aligned_pixels <= unaligned_pixels[alignment_shift*8 +: 128];
            // select 16 bits from the unaligned valid mask at the offset alignment_shift
            aligned_valid_mask <= unaligned_valid_mask[{1'b0, alignment_shift} +: 16];
        end
    end

endmodule
