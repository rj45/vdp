// Project F: FPGA Graphics - Simple VGA timing controller
// (C)2023 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io/posts/fpga-graphics/
// Modified by (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module vga #(parameter CORDW=11) (
    input  logic clk_pix,   // pixel clock
    input  logic rst_pix,   // reset in pixel clock domain
    output logic [CORDW-1:0] sx,  // horizontal screen position
    output logic [CORDW-1:0] sy,  // vertical screen position
    output logic hsync,     // horizontal sync
    output logic vsync,     // vertical sync
    output logic de,        // data enable (low in blanking interval)
    output logic line,      // reached end of line
    output logic frame      // reached end of frame
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
    logic nhsync;
    logic nvsync;
    logic nde;
    logic nline;
    logic nframe;

    always_comb begin
        nhsync = ~(nsx >= HS_STA && nsx < HS_END);  // invert: negative polarity
        nvsync = ~(nsy >= VS_STA && nsy < VS_END);  // invert: negative polarity
        nde = (nsx <= HA_END && nsy <= VA_END);
        nline = (nsx == LINE);
        nframe = (nsx == LINE && nsy == SCREEN);
    end

    // calculate horizontal and vertical screen position
    always_ff @(posedge clk_pix) begin
        if (line) begin  // last pixel on line?
            nsx <= 0;
            nsy <= frame ? 0 : nsy + 1;  // last line on screen?
        end else begin
            nsx <= nsx + 1;
        end
        if (rst_pix) begin
            nsx <= 0;
            nsy <= 0;
        end
    end

    // register everything for speed
    always_ff @(posedge clk_pix) begin
        sx <= nsx;
        sy <= nsy;
        hsync <= nhsync;
        vsync <= nvsync;
        de <= nde;
        line <= nline;
        frame <= nframe;
    end
endmodule
