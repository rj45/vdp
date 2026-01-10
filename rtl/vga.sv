// Copyright (C) 2025 Ryan "rj45" Sanche, MIT License
//
// Originally vaguely based on:
// Project F: FPGA Graphics - Simple VGA timing controller
// (C)2023 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io/posts/fpga-graphics/

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

    `ifdef VERILATOR

    /// In verilator we use reduced blanking for faster simulation

    // horizontal timings (720p)
    parameter HA_END = 1279;           // end of active pixels
    parameter HS_STA = HA_END + 1;     // sync starts after front porch
    parameter HS_END = HS_STA + 1;     // sync ends
    parameter LINE   = 1283;           // last pixel on line (after back porch)

    // vertical timings
    parameter VA_END = 719;            // end of active pixels
    parameter VS_STA = VA_END + 1;     // sync starts after front porch
    parameter VS_END = VS_STA + 1;     // sync ends
    parameter SCREEN = 722;            // last line on screen (after back porch)

    `else

    // horizontal timings (720p)
    parameter HA_END = 1279;           // end of active pixels
    parameter HS_STA = HA_END + 48;    // sync starts after front porch
    parameter HS_END = HS_STA + 32;    // sync ends
    parameter LINE   = 1439;           // last pixel on line (after back porch)

    // vertical timings
    parameter VA_END = 719;            // end of active pixels
    parameter VS_STA = VA_END + 3;     // sync starts after front porch
    parameter VS_END = VS_STA + 5;     // sync ends
    parameter SCREEN = 740;            // last line on screen (after back porch)

    `endif

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
    logic hblank;
    logic vblank;
    logic nhblank;
    logic nvblank;

    always_comb begin
        nline = (sx == LINE);
        nframe = (sx == LINE && sy == SCREEN);
        nnframe = (sx == LINE && sy_plus1 == SCREEN);
        nnnframe = (sx == LINE && sy_plus2 == SCREEN);

        if (nline) begin
            nsx = 0;
            nsy = (nframe ? 0 : sy + 1);
            nsy_plus1 = (nnframe ? 0 : sy_plus1 + 1);
            nsy_plus2 = (nnnframe ? 0 : sy_plus2 + 1);

            if (sy == VA_END)
                nvblank = 1;
            else if (sy == SCREEN)
                nvblank = 0;
            else
                nvblank = vblank;

            if (sy == VS_STA)
                nvsync = 0; // negative polarity
            else if (sy == VS_END)
                nvsync = 1;
            else
                nvsync = vsync;
        end else begin
            nsx = sx + 1;
            nsy = sy;
            nsy_plus1 = sy_plus1;
            nsy_plus2 = sy_plus2;
            nvblank = vblank;
            nvsync = vsync;
        end

        if (sx == HA_END)
            nhblank = 1;
        else if (sx == LINE)
            nhblank = 0;
        else
            nhblank = hblank;

        if (sx == HS_STA)
            nhsync = 1; // positive polarity
        else if (sx == HS_END)
            nhsync = 0;
        else
            nhsync = hsync;

        nde = ~(nhblank | nvblank);
    end

    // register everything for speed
    always_ff @(posedge clk_pix) begin
        if (rst_pix) begin
            sx <= 0;
            sy <= 0;
            sy_plus1 <= 1;
            sy_plus2 <= 2;
            de <= 1;
            line <= 0;
            frame <= 0;

            hblank <= 0;
            vblank <= 0;
            hsync <= 0;
            vsync <= 1;
        end else begin
            sx <= nsx;
            sy <= nsy;
            sy_plus1 <= nsy_plus1;
            sy_plus2 <= nsy_plus2;
            hblank <= nhblank;
            vblank <= nvblank;
            hsync <= nhsync;
            vsync <= nvsync;
            de <= nde;
            line <= nline;
            frame <= nframe;
        end
    end
endmodule
