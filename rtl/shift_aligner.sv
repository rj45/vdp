// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module shift_aligner (
    input  logic clk_draw,
    input  logic rst_draw,

    input  logic [143:0] unaligned_pixels,      // 16 unaligned pixels
    input  logic [15:0]  unaligned_valid_mask,  // 16 valid mask bits
    input  logic [2:0]   alignment_shift,       // amount to shift by

    output logic [71:0] aligned_pixels,        // 8 aligned pixels
    output logic [7:0]  aligned_valid_mask     // 8 bit valid mask
);
    logic [7:0] shift_amt;

    always_comb begin
        case (alignment_shift)
            3'd0: shift_amt = 8'd0;
            3'd1: shift_amt = 8'd9;
            3'd2: shift_amt = 8'd18;
            3'd3: shift_amt = 8'd27;
            3'd4: shift_amt = 8'd36;
            3'd5: shift_amt = 8'd45;
            3'd6: shift_amt = 8'd54;
            3'd7: shift_amt = 8'd63;
            default: shift_amt = 8'd0;
        endcase
    end

    always_ff @(posedge clk_draw or posedge rst_draw) begin
        if (rst_draw) begin
            aligned_pixels <= 72'h0;
            aligned_valid_mask <= 8'h0;
        end else begin
            // select 72 bits from the unaligned pixels at the offset alignment_shift*9
            aligned_pixels <= unaligned_pixels[shift_amt +: 72];
            // select 8 bits from the unaligned valid mask at the offset alignment_shift
            aligned_valid_mask <= unaligned_valid_mask[{1'b0, alignment_shift} +: 8];
        end
    end

endmodule
