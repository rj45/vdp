`default_nettype none
`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst;
    reg [35:0] tile_pixels;
    reg [3:0] tile_valid_mask;
    reg [11:0] lb_x;

    wire [8:0] lb_addr;
    wire [143:0] unaligned_pixels;
    wire [15:0] unaligned_valid_mask;
    wire [2:0] alignment_shift;

    pixel_doubler DUT (
        .clk_draw(clk),
        .rst_draw(rst),
        .tile_pixels(tile_pixels),
        .tile_valid_mask(tile_valid_mask),
        .lb_x(lb_x),
        .lb_addr(lb_addr),
        .unaligned_pixels(unaligned_pixels),
        .unaligned_valid_mask(unaligned_valid_mask),
        .alignment_shift(alignment_shift)
    );

    initial begin
        clk = 0;
        rst = 0;
        tile_pixels = 0;
        tile_valid_mask = 0;
        lb_x = 0;
    end

    // Clock generator
    always #5 clk = ~clk;

    // Test sequence
    initial begin
        #10;
        rst = 1;
        #10;
        rst = 0;
        #10;

        // Test sequences
        tile_pixels = {9'h1, 9'h2, 9'h3, 9'h4};
        tile_valid_mask = 4'b1111;
        lb_x = 12'b000000001000;
        #10;
        assert(lb_addr == lb_x[11:3]) else $fatal(1, "lb_addr is not correct");
        assert(alignment_shift == lb_x[2:0]) else $fatal(1, "alignment_shift is not correct");
        $display("unaligned_pixels = %h", unaligned_pixels);
        assert(unaligned_pixels == {
            9'h0, 9'h0, 9'h0, 9'h0, 9'h0, 9'h0, 9'h0, 9'h0,
            9'h1, 9'h1, 9'h2, 9'h2, 9'h3, 9'h3, 9'h4, 9'h4
        }) else $fatal(1, "unaligned_pixels is not correct");

        tile_pixels = {9'h5, 9'h6, 9'h7, 9'h8};
        tile_valid_mask = 4'b1111;
        lb_x = 12'b000001010010;
        #10;
        assert(lb_addr == lb_x[11:3]) else $fatal(1, "lb_addr is not correct");
        assert(alignment_shift == lb_x[2:0]) else $fatal(1, "alignment_shift is not correct");
        $display("unaligned_pixels = %h", unaligned_pixels);
        assert(unaligned_pixels == {
            9'h1, 9'h1, 9'h2, 9'h2, 9'h3, 9'h3, 9'h4, 9'h4,
            9'h5, 9'h5, 9'h6, 9'h6, 9'h7, 9'h7, 9'h8, 9'h8
        }) else $fatal(1, "unaligned_pixels is not correct");
        #10;

        $display("PASS");

        $finish;
    end

endmodule
