// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module main #(parameter CORDW=11) (  // coordinate width
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
    vga #(CORDW) vga_inst (
        .clk_pix,
        .rst_pix,
        .sx,
        .sy,
        .hsync,
        .vsync,
        .de
    );

    logic [7:0] colour_pix;
    logic [23:0] rgb;

    palette_bram #("testpal.hex") palbram_inst (
        .clk_pix,
        .colour_pix,
        .rgb
    );

    logic [10:0] addr_draw;
    logic [7:0] colour_draw;

    linebuffer_bram lbbram_inst (
        .clk_pix,
        .addr_pix(sx),
        .colour_pix,

        .clk_draw(clk_pix),
        .addr_draw,
        .we_draw(1'b1),
        .colour_draw
    );

    always_comb begin
        addr_draw = sx+1;
        colour_draw = sx[8] ? ~sx[7:0] : sx[7:0];
    end

    // do the palette lookup
    logic [7:0] paint_r, paint_g, paint_b;
    always_comb begin
        paint_b = rgb[7:0];
        paint_g = rgb[15:8];
        paint_r = rgb[23:16];
    end

    // display colour: paint colour but black in blanking interval
    logic [7:0] display_r, display_g, display_b;
    always_comb begin
        display_r = (de) ? paint_r : 8'h0;
        display_g = (de) ? paint_g : 8'h0;
        display_b = (de) ? paint_b : 8'h0;
    end

    always_ff @(posedge clk_pix) begin
        r <= display_r;
        g <= display_g;
        b <= display_b;
    end
endmodule
