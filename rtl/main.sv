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

    logic [6:0] lb_addr_draw;
    logic [127:0] lb_colour_draw;

    double_buffer db_inst (
        .clk_pix,
        .clk_draw(clk_pix), // for now

        .buffsel_pix(sy[0]),
        .buffsel_draw(sy[0]), // for now

        .addr_on_pix(sx),
        .colour_on_pix(colour_pix),

        .addr_on_draw(7'd0), // for now
        .we_on_draw(1'd0), // for now
        .colour_on_draw(128'd0), // for now

        .addr_off_draw(lb_addr_draw),
        .we_off_draw(16'hffff),
        .colour_off_draw(lb_colour_draw)
    );

    always_comb begin
        lb_addr_draw = sx[10:4];
        lb_colour_draw = {
            sx[7:0] + sy[7:0] + 8'hf,
            sx[7:0] + sy[7:0] + 8'he,
            sx[7:0] + sy[7:0] + 8'hd,
            sx[7:0] + sy[7:0] + 8'hc,
            sx[7:0] + sy[7:0] + 8'hb,
            sx[7:0] + sy[7:0] + 8'ha,
            sx[7:0] + sy[7:0] + 8'h9,
            sx[7:0] + sy[7:0] + 8'h8,
            sx[7:0] + sy[7:0] + 8'h7,
            sx[7:0] + sy[7:0] + 8'h6,
            sx[7:0] + sy[7:0] + 8'h5,
            sx[7:0] + sy[7:0] + 8'h4,
            sx[7:0] + sy[7:0] + 8'h3,
            sx[7:0] + sy[7:0] + 8'h2,
            sx[7:0] + sy[7:0] + 8'h1,
            sx[7:0] + sy[7:0] + 8'h0
        };
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
