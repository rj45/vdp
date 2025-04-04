/**********************************************************************
 * DO WHAT THE FUCK YOU WANT TO AND DON'T BLAME US PUBLIC LICENSE     *
 *                    Version 3, April 2008                           *
 *                                                                    *
 * Copyright (C) 2020 Luke Wren                                       *
 *                                                                    *
 * Everyone is permitted to copy and distribute verbatim or modified  *
 * copies of this license document and accompanying software, and     *
 * changing either is allowed.                                        *
 *                                                                    *
 *   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION  *
 *                                                                    *
 * 0. You just DO WHAT THE FUCK YOU WANT TO.                          *
 * 1. We're NOT RESPONSIBLE WHEN IT DOESN'T FUCKING WORK.             *
 *                                                                    *
 *********************************************************************/

`default_nettype none
`timescale 1ns / 1ps

module smoldvi_serialiser (
	input  wire       clk_pix,
	input  wire       rst_n_pix,
	input  wire       clk_x5,
	input  wire       rst_n_x5,

	input  wire [9:0] d,
	output wire       qp,
	output wire       qn
);

reg [9:0] d_delay;
wire [1:0] data_x5;

always @ (posedge clk_pix) begin
	d_delay <= d;
end

smoldvi_fast_gearbox #(
	.W_IN         (10),
	.W_OUT        (2),
	.STORAGE_SIZE (20)
) gearbox_u (
	.clk_in     (clk_pix),
	.rst_n_in   (rst_n_pix),
	.din        (d_delay),

	.clk_out    (clk_x5),
	.rst_n_out  (rst_n_x5),
	.dout       (data_x5)
);

reg [1:0] data_x5_delay;
reg [1:0] data_x5_ndelay;

always @ (posedge clk_x5) begin
	data_x5_delay <= data_x5;
	data_x5_ndelay <= ~data_x5;
end

`ifdef __ICARUS__
  // (pseudo-) differential DDR driver (pure verilog version)
  //
  assign qp = clk_x5 ? data_x5_delay[0]  : data_x5_delay[1];
  assign qn = clk_x5 ? data_x5_ndelay[0] : data_x5_ndelay[1];
`else
  // (pseudo-) differential DDR driver (ECP5 synthesis version)
  //*
  ODDRX1F ddrp( .Q(qp), .SCLK(clk_x5), .D0(data_x5_delay[0]),  .D1(data_x5_delay[1]),  .RST(1'b0) );
  ODDRX1F ddrn( .Q(qn), .SCLK(clk_x5), .D0(data_x5_ndelay[0]), .D1(data_x5_ndelay[1]), .RST(1'b0) );
`endif

endmodule
