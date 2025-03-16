`default_nettype none
`timescale 1ns / 1ps

module cdc_pulse_synchronizer_2phase
#(
    parameter CDC_EXTRA_DEPTH   = 0
)
(
    input   logic    sending_clock,
    input   logic    sending_pulse_in,
    // output  logic    sending_ready,

    input   logic    receiving_clock,
    output  logic    receiving_pulse_out
);

    // Clean up the input pulse to a single cycle pulse, so we cannot have
    // a situation where the 2-phase handshake has completed and a long
    // input pulse is still high, causing a second toggle and thus a second
    // pulse in the receiving clock domain.
    wire cleaned_pulse_in;
    pulse_generator pulse_cleaner (
        .clock              (sending_clock),
        .level_in           (sending_pulse_in),
        .pulse_posedge_out  (cleaned_pulse_in),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_negedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    // logic toggle_response;
    // logic enable_toggle = 1'b0;
    logic sending_toggle;

    register_toggle #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    ) start_handshake (
        .clock          (sending_clock),
        .clock_enable   (1'b1), //(enable_toggle),
        .clear          (1'b0),
        .toggle         (cleaned_pulse_in),
        .data_in        (sending_toggle),
        .data_out       (sending_toggle)
    );

    // always @(*) begin
    //     enable_toggle = (sending_toggle == toggle_response);
    //     sending_ready = enable_toggle;
    // end

    logic receiving_toggle;

    cdc_bit_synchronizer #(
        .EXTRA_DEPTH        (CDC_EXTRA_DEPTH)
    ) to_receiving (
        .receiving_clock    (receiving_clock),
        .bit_in             (sending_toggle),
        .bit_out            (receiving_toggle)
    );

    // cdc_bit_synchronizer #(
    //     .EXTRA_DEPTH        (CDC_EXTRA_DEPTH)
    // ) to_sending (
    //     .receiving_clock    (sending_clock),
    //     .bit_in             (receiving_toggle),
    //     .bit_out            (toggle_response)
    // );

    pulse_generator receiving_toggle_to_pulse (
        .clock              (receiving_clock),
        .level_in           (receiving_toggle),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_posedge_out  (),
        .pulse_negedge_out  (),
        // verilator lint_on  PINCONNECTEMPTY
        .pulse_anyedge_out  (receiving_pulse_out)
    );

endmodule
