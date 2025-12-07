// Initially:
// (C)2023 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io/posts/fpga-graphics/
// Modified by (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module top_up5k  (
    input  wire logic    clk,           // input clock

    output      logic    P2_1,
    output      logic    P2_2,
    output      logic    P2_3,
    output      logic    P2_4,
    output      logic    P2_9,
    output      logic    P2_10,
    output      logic    P2_11,
    output      logic    P2_12,

    output      logic    LED_G
    );

    // HDMI
    logic [3:0]  gpdi_dp, gpdi_dn;
    assign {P2_1, P2_2, P2_3, P2_4} = gpdi_dp;
    assign {P2_9, P2_10, P2_11, P2_12} = gpdi_dn;

    // clock
    logic clk_pix, clk_pix5x, clk_draw, locked;
    pll pll_inst (
        .clock_in(clk),
        .clock_out(clk_pix5x),
        .locked
    );

    // Generate clk_pix from clk_bit with ring counter (hack)
    (* keep = 1'b1 *) reg [4:0] bit_pix_div;
    assign clk_pix = bit_pix_div[0];
    assign clk_draw = bit_pix_div[0];

    always @ (posedge clk_pix5x or negedge locked) begin
       	if (!locked) begin
      		bit_pix_div <= 5'b11100;
       	end else begin
      		bit_pix_div <= {bit_pix_div[3:0], bit_pix_div[4]};
       	end
    end

    // reset -- TODO: make more robust
    logic rst_pix;
    always_ff @(posedge clk_pix) rst_pix <= ~locked;

    logic rst_draw;
    always_ff @(posedge clk_draw) rst_draw <= ~locked;

    logic hsync, vsync, de;
    logic [7:0] r, g, b;

    smoldvi smoldvi_inst (
        .clk_pix,
        .rst_n_pix(~rst_pix),
        .clk_bit(clk_pix5x),
        .rst_n_bit(~rst_pix),
        .r(r[7:1]), .g(g[7:1]), .b(b[7:1]),
        .den(de), .hsync, .vsync,
        .dvi_p(gpdi_dp), .dvi_n(gpdi_dn)
    );

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

    assign LED_G = counter[30];

endmodule
