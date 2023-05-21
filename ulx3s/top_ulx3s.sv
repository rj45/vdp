// Initially:
// (C)2023 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io/posts/fpga-graphics/
// Modified by (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module top_ulx3s (
    input  wire logic clk_25mhz,           // input clock

    // HDMI
    output      logic [3:0]  gpdi_dp,
    output      logic [3:0]  gpdi_dn,

    output      logic [7:0]  led
    );

    // clock
    logic clk_pix, clk_pix5x, locked;
    pll pll_inst (
        .clkin(clk_25mhz),
        .clk_pix,
        .clk_pix5x,
        .locked
    );

    // reset -- TODO: make more robust
    logic rst_pix;
    always_ff @(posedge clk_pix) rst_pix <= ~locked;

    logic hsync, vsync, de;
    logic [7:0] r, g, b;

    hdmi hdmi_inst (
        .clk_pix,
        .clk_pix5x,
        .r, .g, .b,
        .de, .hsync, .vsync,
        .gpdi_dp, .gpdi_dn
    );

    main test_inst (
        .clk_pix,
        .rst_pix,
        .sx(),
        .sy(),
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
