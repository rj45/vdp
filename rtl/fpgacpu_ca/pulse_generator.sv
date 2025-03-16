`default_nettype none
`timescale 1ns / 1ps

module pulse_generator
(
    input   wire    clock,
    input   wire    level_in,
    output  reg     pulse_posedge_out,
    output  reg     pulse_negedge_out,
    output  reg     pulse_anyedge_out
);

    wire level_in_delayed;

    register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    delay
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (1'b0),
        .data_in        (level_in),
        .data_out       (level_in_delayed)
    );

    always_comb begin
        pulse_posedge_out = (level_in          == 1'b1) && (level_in_delayed  == 1'b0);
        pulse_negedge_out = (level_in          == 1'b0) && (level_in_delayed  == 1'b1);
        pulse_anyedge_out = (pulse_posedge_out == 1'b1) || (pulse_negedge_out == 1'b1);
    end

endmodule
