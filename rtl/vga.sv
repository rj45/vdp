// Project F: FPGA Graphics - Simple VGA timing controller
// (C)2023 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io/posts/fpga-graphics/
// Modified by (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module vga #(parameter CORDW=11) (
    input  logic             clk_pix,  // pixel clock
    input  logic             rst_pix,  // reset in pixel clock domain
    output logic [CORDW-1:0] sx,       // horizontal screen position
    output logic [CORDW-1:0] sy,       // vertical screen position
    output logic [CORDW-1:0] sy_plus1, // upcoming vertical screen position
    output logic [CORDW-1:0] sy_plus2, // upcoming vertical screen position 2
    output logic             hsync,    // horizontal sync
    output logic             vsync,    // vertical sync
    output logic             de,       // data enable (low in blanking interval)
    output logic             line,     // reached end of line
    output logic             frame     // reached end of frame
    );

    // horizontal timings (720p)
    parameter HA_END = 1279;           // end of active pixels
    parameter HS_STA = HA_END + 8;     // sync starts after front porch
    parameter HS_END = HS_STA + 32;    // sync ends
    parameter LINE   = 1359;           // last pixel on line (after back porch)

    // vertical timings
    parameter VA_END = 719;            // end of active pixels
    parameter VS_STA = VA_END + 7;     // sync starts after front porch
    parameter VS_END = VS_STA + 8;     // sync ends
    parameter SCREEN = 740;            // last line on screen (after back porch)

    logic [CORDW-1:0] nsx;
    logic [CORDW-1:0] nsy;
    logic [CORDW-1:0] nsy_plus1;
    logic [CORDW-1:0] nsy_plus2;
    logic nhsync;
    logic nvsync;
    logic nde;
    logic nline;
    logic nframe;
    logic nnframe;
    logic nnnframe;

    always_comb begin
        nhsync = (sx >= HS_STA && sx < HS_END);
        nvsync = ~(sy >= VS_STA && sy < VS_END);  // invert: negative polarity
        nde = (sx <= HA_END && sy <= VA_END);
        nline = (sx == LINE);
        nframe = (sx == LINE && sy == SCREEN);
        nnframe = (sx == LINE && sy_plus1 == SCREEN);
        nnnframe = (sx == LINE && sy_plus2 == SCREEN);

        nsx = nline ? 0 : sx + 1;
        nsy = nline ? (nframe ? 0 : sy + 1) : sy;
        nsy_plus1 = nline ? (nnframe ? 0 : sy_plus1 + 1) : sy_plus1;
        nsy_plus2 = nline ? (nnnframe ? 0 : sy_plus2 + 1) : sy_plus2;
    end

    // register everything for speed
    always_ff @(posedge clk_pix) begin
        if (rst_pix) begin
            sx <= 0;
            sy <= 0;
            sy_plus1 <= 1;
            sy_plus2 <= 2;
            hsync <= 0;
            vsync <= 0;
            de <= 0;
            line <= 0;
            frame <= 0;
        end else begin
            sx <= nsx;
            sy <= nsy;
            sy_plus1 <= nsy_plus1;
            sy_plus2 <= nsy_plus2;
            hsync <= nhsync;
            vsync <= nvsync;
            de <= nde;
            line <= nline;
            frame <= nframe;
        end
    end
endmodule
