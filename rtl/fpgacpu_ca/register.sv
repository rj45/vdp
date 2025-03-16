`default_nettype none
`timescale 1ns / 1ps

module register
#(
    parameter WORD_WIDTH  = 0,
    parameter RESET_VALUE = 0
)
(
    input   logic                        clock,
    input   logic                        clock_enable,
    input   logic                        clear,
    input   logic    [WORD_WIDTH-1:0]    data_in,
    output  logic    [WORD_WIDTH-1:0]    data_out
);

    initial begin
        data_out = RESET_VALUE;
    end

    always_ff @(posedge clock) begin
        if (clock_enable == 1'b1) begin
            data_out <= data_in;
        end

        if (clear == 1'b1) begin
            data_out <= RESET_VALUE;
        end
    end

endmodule
