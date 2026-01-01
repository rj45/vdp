// Initially:
// (C)2023 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io/posts/fpga-graphics/
// Modified by (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

//`define SMOLDVI 1

module top_ulx3s  (
    input  wire logic clk_25mhz,           // input clock

    input  wire logic [6:0] btn,           // buttons

    // SDRAM
    // output      logic        sdram_clk,
    // output      logic        sdram_cke,
    // output      logic        sdram_csn,
    // output      logic        sdram_wen,
    // output      logic        sdram_rasn,
    // output      logic        sdram_casn,
    // output      logic [12:0] sdram_a,
    // output      logic [1:0]  sdram_ba,
    // output      logic [1:0]  sdram_dqm,
    // inout       logic [15:0] sdram_d,

    // HDMI
    output      logic [3:0]  gpdi_dp,
    output      logic [3:0]  gpdi_dn,

    output      logic [7:0]  led
    );

    // don't hook directly into the sdram
    logic        sdram_clk;
    logic        sdram_cke;
    logic        sdram_csn;
    logic        sdram_wen;
    logic        sdram_rasn;
    logic        sdram_casn;
    logic [12:0] sdram_a;
    logic [1:0]  sdram_ba;
    logic [1:0]  sdram_dqm;
    logic [15:0] sdram_d;

    // clock
    logic clk_pix, clk_pix5x, clk_draw, locked;
    pll pll_inst (
        .clkin(clk_25mhz),
        .clk_pix,
        .clk_pix5x,
        .clk_draw,
        .locked
    );

    logic btn_reset = ~btn[0];

    // reset -- TODO: make more robust
    logic nnrst_pix;
    always_ff @(posedge clk_pix) nnrst_pix <= ~locked || btn_reset;

    logic nrst_pix;
    always_ff @(posedge clk_pix) nrst_pix <= nnrst_pix;

    logic rst_pix;
    always_ff @(posedge clk_pix) rst_pix <= nrst_pix;

    logic nnrst_pix5x;
    always_ff @(posedge clk_pix5x) nnrst_pix5x <= ~locked || btn_reset;

    logic nrst_pix5x;
    always_ff @(posedge clk_pix5x) nrst_pix5x <= nnrst_pix5x;

    logic rst_pix5x;
    always_ff @(posedge clk_pix5x) rst_pix5x <= nrst_pix5x;

    logic nrst_draw;
    always_ff @(posedge clk_draw) nrst_draw <= ~locked || btn_reset;

    logic rst_draw;
    always_ff @(posedge clk_draw) rst_draw <= nrst_draw;

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
            .rst_pix(rst_pix),
            .rst_pix5x(rst_pix5x),
            .r, .g, .b,
            .de, .hsync, .vsync,
            .gpdi_dp, .gpdi_dn
        );
`endif

    vdp vdp_inst (
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
        .b,

        .sdram_clk,
        .sdram_cke,
        .sdram_csn,
        .sdram_wen,
        .sdram_rasn,
        .sdram_casn,
        .sdram_a,
        .sdram_ba,
        .sdram_dqm,
        .sdram_d
    );

    // blinky
    logic [30:0] counter;

    always_ff @(posedge clk_draw) begin
        if (rst_draw)
            counter <= 0;
        else
            counter <= counter + 1;
    end

    assign led = counter[30:23];

endmodule
