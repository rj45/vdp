`default_nettype none
`timescale 1ns / 1ps

module register_toggle
#(
    parameter WORD_WIDTH  = 0,
    parameter RESET_VALUE = 0
)
(
    input   logic                        clock,
    input   logic                        clock_enable,
    input   logic                        clear,
    input   logic                        toggle,
    input   logic    [WORD_WIDTH-1:0]    data_in,
    output  logic    [WORD_WIDTH-1:0]    data_out
);

    reg [WORD_WIDTH-1:0] new_value;

    register #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (RESET_VALUE)
    ) toggle_register (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (clear),
        .data_in        (new_value),
        .data_out       (data_out)
    );

    always @(*) begin
        new_value = (toggle == 1'b1) ? ~data_out : data_in;
    end

endmodule
