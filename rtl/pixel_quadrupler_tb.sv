`default_nettype none
`timescale 1ns / 1ps

module testbench;

    reg clk;
    reg rst;
    reg [31:0] tile_pixels;
    reg [3:0] tile_valid_mask;
    reg [10:0] tile_x;

    wire [6:0] lb_addr;
    wire [255:0] unaligned_pixels;
    wire [31:0] unaligned_valid_mask;
    wire [3:0] alignment_shift;

    pixel_quadrupler DUT (
        .clk_draw(clk),
        .rst_draw(rst),
        .tile_pixels(tile_pixels),
        .tile_valid_mask(tile_valid_mask),
        .tile_x(tile_x),
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
        tile_x = 0;
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
        tile_pixels = 32'h01020304;
        tile_valid_mask = 4'b1111;
        tile_x = 11'b00000001000;
        #10;
        assert(lb_addr == tile_x[10:4]) else $fatal(1, "lb_addr is not correct");
        assert(alignment_shift == tile_x[3:0]) else $fatal(1, "alignment_shift is not correct");
        assert(unaligned_pixels == 256'h01010101020202020303030304040404) else $fatal(1, "unaligned_pixels is not correct");

        tile_pixels = 32'h05060708;
        tile_valid_mask = 4'b1111;
        tile_x = 11'b00001010010;
        #10;
        assert(lb_addr == tile_x[10:4]) else $fatal(1, "lb_addr is not correct");
        assert(alignment_shift == tile_x[3:0]) else $fatal(1, "alignment_shift is not correct");
        assert(unaligned_pixels == 256'h0101010102020202030303030404040405050505060606060707070708080808) else $fatal(1, "unaligned_pixels is not correct");

        #10;

        $display("PASS");

        $finish;
    end

endmodule
