// (C) 2026 Ryan "rj45" Sanche, MIT License
//
// Code is AI regurgitated and likely comes from somewhere, let me know if you recognize it.

`default_nettype none
`timescale 1ns / 1ps

// Simple skid buffer to prevent long combinational paths on ready signals
module skid_buffer #(
    parameter WIDTH = 16
) (
    input  logic clk,
    input  logic rst,

    // Input side
    input  logic [WIDTH-1:0] i_data,
    input  logic             i_valid,
    output logic             i_ready,

    // Output side
    output logic [WIDTH-1:0] o_data,
    output logic             o_valid,
    input  logic             o_ready
);
    // Internal buffer for when downstream stalls
    logic [WIDTH-1:0] buffer;
    logic             buffered;

    // We can accept input when buffer is empty
    assign i_ready = !buffered;

    // Output is valid when we have buffered data OR input is valid
    assign o_valid = buffered || i_valid;
    assign o_data  = buffered ? buffer : i_data;

    always_ff @(posedge clk) begin
        if (rst) begin
            buffered <= 1'b0;
        end else begin
            if (buffered) begin
                // We have buffered data
                if (o_ready) begin
                    // Downstream accepted it
                    buffered <= 1'b0;
                end
            end else begin
                // No buffered data
                if (i_valid && !o_ready) begin
                    // Input valid but downstream stalled - buffer it
                    buffer   <= i_data;
                    buffered <= 1'b1;
                end
            end
        end
    end
endmodule
