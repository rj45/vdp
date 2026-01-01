// (C) 2026 Ryan "rj45" Sanche, MIT License
//
// Pix pipeline: From linebuffer to screen output

`default_nettype none
`timescale 1ns / 1ps

module pix_pipeline #(parameter CORDW=11) (
    input  logic clk_pix,
    // input  logic rst_pix,

    // Input from linebuffer
    input  logic [8:0]       i_colour,
    input  logic [CORDW-1:0] i_sx,
    input  logic [CORDW-1:0] i_sy,
    input  logic             i_de,
    input  logic             i_vsync,
    input  logic             i_hsync,

    // Output to HDMI
    output logic [CORDW-1:0] o_sx,
    output logic [CORDW-1:0] o_sy,
    output logic             o_de,
    output logic             o_vsync,
    output logic             o_hsync,
    output logic [7:0]       o_r,
    output logic [7:0]       o_g,
    output logic [7:0]       o_b
);

    // Sync signals passed through pix pipeline
    typedef struct packed {
        logic [CORDW-1:0] sx;
        logic [CORDW-1:0] sy;
        logic             de;
        logic             vsync;
        logic             hsync;
    } pix_sync_t;  // 25 bits

    // After linebuffer read (p1)
    typedef struct packed {
        pix_sync_t sync;
        logic [8:0] colour;  // palette index
    } pix_lb_t;  // 34 bits

    // After palette lookup (p2)
    typedef struct packed {
        pix_sync_t sync;
        logic [7:0] r;
        logic [7:0] g;
        logic [7:0] b;
    } pix_rgb_t;  // 49 bits


    ////////////////////////////////////////////////////////////////
    // Pix cycle p1: Read the line buffer
    ////////////////////////////////////////////////////////////////

    pix_lb_t p1_data;

    assign p1_data.colour = i_colour;

    always_ff @(posedge clk_pix) begin
        p1_data.sync.sx <= i_sx;
        p1_data.sync.sy <= i_sy;
        p1_data.sync.de <= i_de;
        p1_data.sync.vsync <= i_vsync;
        p1_data.sync.hsync <= i_hsync;
    end

    ////////////////////////////////////////////////////////////////
    // Pix cycle p2: Extra register for timing
    ////////////////////////////////////////////////////////////////

    pix_lb_t p2_data;

    always_ff @(posedge clk_pix) begin
        p2_data <= p1_data;
    end


    ////////////////////////////////////////////////////////////////
    // Pix cycle p3: Lookup the palette entry
    ////////////////////////////////////////////////////////////////

    pix_rgb_t p3_data;

    palette_bram #("palette.hex") palbram_inst (
        .clk_pix,
        .colour_pix(p2_data.colour),
        .r(p3_data.r),
        .g(p3_data.g),
        .b(p3_data.b)
    );

    always_ff @(posedge clk_pix) begin
        p3_data.sync <= p2_data.sync;
    end

    ////////////////////////////////////////////////////////////////
    // Pix cycle p4: Output to screen
    ////////////////////////////////////////////////////////////////

    always_ff @(posedge clk_pix) begin
        o_sx    <= p3_data.sync.sx;
        o_sy    <= p3_data.sync.sy;
        o_de    <= p3_data.sync.de;
        o_vsync <= p3_data.sync.vsync;
        o_hsync <= p3_data.sync.hsync;
        o_r     <= p3_data.sync.de ? p3_data.r : 8'h0;
        o_g     <= p3_data.sync.de ? p3_data.g : 8'h0;
        o_b     <= p3_data.sync.de ? p3_data.b : 8'h0;
    end

endmodule
