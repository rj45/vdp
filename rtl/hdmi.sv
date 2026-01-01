// from: https://github.com/lawrie/ulx3s_zx_spectrum/
// Original origin / license unknown

`default_nettype none
`timescale 1ns / 1ps

// module port
//
module hdmi(
  input  logic clk_pix,
  input  logic clk_pix5x,
  input  logic rst_pix,
  input  logic rst_pix5x,
  input  logic [7:0] r, g, b,
  input  logic de, hsync, vsync,
  output logic [3:0] gpdi_dp, gpdi_dn
);

    logic [7:0] r_r;
    logic [7:0] g_r;
    logic [7:0] b_r;
    logic       de_r;
    logic       hsync_r;
    logic       vsync_r;

    // register inputs to improve performance
    always_ff @(posedge clk_pix) begin
        r_r     <= r;
        g_r     <= g;
        b_r     <= b;
        de_r    <= de;
        hsync_r <= hsync;
        vsync_r <= vsync;
    end

    // 10b8b TMDS encoding of RGB and Sync
    //
    wire [9:0] TMDS_red, TMDS_green, TMDS_blue;
    tmds_encoder encode_R(.clk(clk_pix), .i_reset(rst_pix), .VD(r_r), .CD(2'b00)            , .VDE(de_r), .TMDS(TMDS_red));
    tmds_encoder encode_G(.clk(clk_pix), .i_reset(rst_pix), .VD(g_r), .CD(2'b00)            , .VDE(de_r), .TMDS(TMDS_green));
    tmds_encoder encode_B(.clk(clk_pix), .i_reset(rst_pix), .VD(b_r), .CD({vsync_r,hsync_r}), .VDE(de_r), .TMDS(TMDS_blue));

    smoldvi_clock_driver ser_ck (
    	.clk_x5    (clk_pix5x),
    	.rst_n_x5  (~rst_pix5x),

    	.qp        (gpdi_dp[3]),
    	.qn        (gpdi_dn[3])
    );

    smoldvi_serialiser ser_red (
    	.clk_pix   (clk_pix),
    	.rst_n_pix (~rst_pix),
    	.clk_x5    (clk_pix5x),
    	.rst_n_x5  (~rst_pix5x),

    	.d         (TMDS_red),
    	.qp        (gpdi_dp[2]),
    	.qn        (gpdi_dn[2])
    );

    smoldvi_serialiser ser_green (
    	.clk_pix   (clk_pix),
    	.rst_n_pix (~rst_pix),
    	.clk_x5    (clk_pix5x),
    	.rst_n_x5  (~rst_pix5x),

    	.d         (TMDS_green),
    	.qp        (gpdi_dp[1]),
    	.qn        (gpdi_dn[1])
    );

    smoldvi_serialiser ser_blue (
    	.clk_pix   (clk_pix),
    	.rst_n_pix (~rst_pix),
    	.clk_x5    (clk_pix5x),
    	.rst_n_x5  (~rst_pix5x),

    	.d         (TMDS_blue),
    	.qp        (gpdi_dp[0]),
    	.qn        (gpdi_dn[0])
    );

endmodule
