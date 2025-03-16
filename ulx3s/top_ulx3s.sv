// Initially:
// (C)2023 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io/posts/fpga-graphics/
// Modified by (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

// `define SMOLDVI 1

module top_ulx3s  (
    input  wire logic clk_25mhz,           // input clock

    // HDMI
    output      logic [3:0]  gpdi_dp,
    output      logic [3:0]  gpdi_dn,

    output      logic [7:0]  led
    );

    // clock
    logic clk_pix, clk_pix5x, clk_draw, locked;
    pll pll_inst (
        .clkin(clk_25mhz),
        .clk_pix,
        .clk_pix5x,
        .clk_draw,
        .locked
    );

    // reset -- TODO: make more robust
    logic rst_pix;
    always_ff @(posedge clk_pix) rst_pix <= ~locked;

    logic rst_draw;
    always_ff @(posedge clk_draw) rst_draw <= ~locked;

    logic hsync, vsync, de;
    logic [7:0] r, g, b;

`ifdef SMOLDVI
        smoldvi smoldvi_inst (
            .clk_pix,
            .rst_n_pix(~rst_pix),
            .clk_bit(clk_pix5x),
            .rst_n_bit(~rst_pix),
            .r(r[7:1]), .g(g[7:1]), .b(b[7:1]),
            .den(de), .hsync, .vsync,
            .dvi_p(gpdi_dp), .dvi_n(gpdi_dn)
        );
`else
        hdmi hdmi_inst (
            .clk_pix,
            .clk_pix5x,
            .r, .g, .b,
            .de, .hsync, .vsync,
            .gpdi_dp, .gpdi_dn
        );
`endif

    main main_inst (
        .clk_draw(clk_draw),
        .rst_draw,
        .clk_pix,
        .rst_pix,
        // verilator lint_off PINCONNECTEMPTY
        .sx(),
        .sy(),
        // verilator lint_on PINCONNECTEMPTY
        .hsync,
        .vsync,
        .de,
        .r,
        .g,
        .b
    );

    // blinky
    logic [30:0] counter;

    always_ff @(posedge clk_pix) counter <= counter + 1;

    assign led = counter[30:23];

endmodule
