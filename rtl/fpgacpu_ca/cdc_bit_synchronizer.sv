`default_nettype none
`timescale 1ns / 1ps

// https://fpgacpu.ca/fpga/CDC_Bit_Synchronizer.html
module cdc_bit_synchronizer
#(
    parameter EXTRA_DEPTH = 0 // Must be 0 or greater
)
(
    input   logic    receiving_clock,
    input   logic    bit_in,
    output  logic    bit_out
);

    localparam DEPTH = 2 + EXTRA_DEPTH;

    // Vivado
    (* IOB = "false" *)
    (* ASYNC_REG = "TRUE" *)

    // Quartus
    (* useioff = 0 *)
    (* PRESERVE *)
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)

    // yosys
    (* mem2reg *)
    reg sync_reg [DEPTH-1:0];

    integer i;

    initial begin
        for(i=0; i < DEPTH; i=i+1) begin
            sync_reg [i] = 1'b0;
        end
    end

    always_ff @(posedge receiving_clock) begin
        sync_reg [0] <= bit_in;

        for(i = 1; i < DEPTH; i = i+1) begin: cdc_stages
            sync_reg [i] <= sync_reg [i-1];
        end
    end

    always_comb begin
        bit_out = sync_reg [DEPTH-1];
    end

endmodule
