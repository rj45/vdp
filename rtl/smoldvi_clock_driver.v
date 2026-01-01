// We can drive a clock by passing 10'b11111_00000 into a 10:1 serialiser, but this
// is wasteful, because the tools won't trim the CDC hardware. It's worth it
// (area-wise) to specialise this.
//
// This module takes a half-rate bit clock (5x pixel clock) and drives a
// pseudodifferential pixel clock using DDR outputs.

`default_nettype none
`timescale 1ns / 1ps

module smoldvi_clock_driver (
	input  wire       clk_x5,
	input  wire       rst_n_x5,

	output wire       qp,
	output wire       qn
);

reg [9:0] ring_ctr;

always @ (posedge clk_x5 or negedge rst_n_x5) begin
	if (!rst_n_x5) begin
		ring_ctr <= 10'b11111_00000;
	end else begin
		ring_ctr <= {ring_ctr[1:0], ring_ctr[9:2]};
	end
end

`ifdef __ICARUS__
  // (pseudo-) differential DDR driver (pure verilog version)
  //
  assign qp = clk_x5 ? ring_ctr[0] : ring_ctr[1];
  assign qn = clk_x5 ? ring_ctr[5] : ring_ctr[6];
`elsif FPGA_ICE40

  reg d_fall_r;
  always @ (posedge clk or negedge rst_n)
	if (!rst_n)
		d_fall_r <= 1'b0;
	else
		d_fall_r <= d_fall;

  SB_IO #(
	.PIN_TYPE (6'b01_00_00),
	//            |  |  |
	//            |  |  \----- Registered input (and no clock!)
	//            |  \-------- DDR output
	//            \----------- Permanent output enable
	.PULLUP (1'b 0)
  ) buffer (
	.PACKAGE_PIN  (qp),
	.OUTPUT_CLK   (clk_x5),
	.CLOCK_ENABLE (1'b1),
	.D_OUT_0      (ring_ctr[0]),
	.D_OUT_1      (ring_ctr[1])
  );

  SB_IO #(
	.PIN_TYPE (6'b01_00_00),
	//            |  |  |
	//            |  |  \----- Registered input (and no clock!)
	//            |  \-------- DDR output
	//            \----------- Permanent output enable
	.PULLUP (1'b 0)
  ) buffer (
	.PACKAGE_PIN  (qn),
	.OUTPUT_CLK   (clk_x5),
	.CLOCK_ENABLE (1'b1),
	.D_OUT_0      (ring_ctr[5]),
	.D_OUT_1      (ring_ctr[6])
  );

`elsif FPGA_ECP5
  // (pseudo-) differential DDR driver (ECP5 synthesis version)
  //*
  ODDRX1F ddrp( .Q(qp), .SCLK(clk_x5), .D0(ring_ctr[0]), .D1(ring_ctr[1]), .RST(1'b0) );

  // It's marked as LVCMOS33D in the constraints, so the `n` side of the pair should work automatically
  // ODDRX1F ddrn( .Q(qn), .SCLK(clk_x5), .D0(ring_ctr[5]), .D1(ring_ctr[6]), .RST(1'b0) );
`endif

endmodule
