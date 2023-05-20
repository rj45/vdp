// Project F: FPGA Graphics - Test Pattern
// (C)2023 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io/posts/fpga-graphics/
// Modified by (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module test_pattern #(parameter CORDW=10) (  // coordinate width
    input  wire logic clk_pix,             // pixel clock
    input  wire logic rst_pix,             // pixel reset
    output      logic [CORDW-1:0] sx,  // horizontal position
    output      logic [CORDW-1:0] sy,  // vertical position
    output      logic de,              // data enable (low in blanking interval)
    output      logic vsync,           // vertical sync
    output      logic hsync,           // horizontal sync
    output      logic [7:0] r,         // 8-bit red
    output      logic [7:0] g,         // 8-bit green
    output      logic [7:0] b          // 8-bit blue
    );

    // display sync signals and coordinates
    vga vga_inst (
        .clk_pix,
        .rst_pix,
        .sx,
        .sy,
        .hsync,
        .vsync,
        .de
    );

    // paint colour: based on screen position
    logic [7:0] paint_r, paint_g, paint_b;
    always_comb begin
        if (sx < 256 && sy < 256) begin  // colour square in top-left 256x256 pixels
            paint_r = sx[7:0];
            paint_g = sy[7:0];
            paint_b = ~sy[7:0];
        end else begin  // background colour
            paint_r = 8'h00;
            paint_g = 8'h11;
            paint_b = 8'h33;
        end
    end

    // display colour: paint colour but black in blanking interval
    logic [7:0] display_r, display_g, display_b;
    always_comb begin
        display_r = (de) ? paint_r : 8'h0;
        display_g = (de) ? paint_g : 8'h0;
        display_b = (de) ? paint_b : 8'h0;
    end

    // SDL output (8 bits per colour channel)
    always_ff @(posedge clk_pix) begin
        r <= display_r;
        g <= display_g;
        b <= display_b;
    end
endmodule
