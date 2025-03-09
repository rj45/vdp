// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

// This module has the following specs:
// - Two clock domains, the pix clock and the draw clock
// - Two line buffers, one on-screen `on` and one off-screen `off`
// - On-screen buffer is read one pixel at a time in the pix clock domain
// - On-screen buffer is cleared 16 pixels at a time in the draw clock domain
// - Off-screen buffer is written 16 pixels at a time in the draw clock domain
// - Buffers must be flipped, but because of CDC issues, the flip happens separately in each domain

module double_buffer (
    // read port clock
    input  logic         clk_pix,

    // write port clock
    input  logic         clk_draw,

    // buffer select for each clock domain
    input  logic         buffsel_pix,
    input  logic         buffsel_draw,

    // on-screen buffer read port
    input  logic [10:0]  addr_on_pix,
    output logic [7:0]   colour_on_pix,

    // on-screen buffer write port (for clearing)
    input  logic [6:0]   addr_on_draw,
    input  logic         we_on_draw,
    input  logic [127:0] colour_on_draw,

    // off-screen buffer write port
    input  logic [6:0]   addr_off_draw,
    input  logic [15:0]  we_off_draw,
    input  logic [127:0] colour_off_draw
);

    logic [6:0]   lb0_addr_pix;
    logic [127:0] lb0_colour_pix;
    logic [6:0]   lb0_addr_draw;
    logic [15:0]  lb0_we_draw;
    logic [127:0] lb0_colour_draw;

    linebuffer_bram lb0 (
        .clk_pix,
        .addr_pix(lb0_addr_pix),
        .colour_pix(lb0_colour_pix),

        .clk_draw,
        .addr_draw(lb0_addr_draw),
        .we_draw(lb0_we_draw),
        .colour_draw(lb0_colour_draw)
    );

    logic [6:0]   lb1_addr_pix;
    logic [127:0] lb1_colour_pix;
    logic [6:0]   lb1_addr_draw;
    logic [15:0]  lb1_we_draw;
    logic [127:0] lb1_colour_draw;

    linebuffer_bram lb1 (
        .clk_pix,
        .addr_pix(lb1_addr_pix),
        .colour_pix(lb1_colour_pix),

        .clk_draw,
        .addr_draw(lb1_addr_draw),
        .we_draw(lb1_we_draw),
        .colour_draw(lb1_colour_draw)
    );

    // The addr_on_pix needs to be delayed by one cycle because the bram takes a cycle to read
    logic [10:0]  prev_addr_on_pix;

    always_ff @(posedge clk_draw) begin
        prev_addr_on_pix <= addr_on_pix;
    end

    // handle the pix side reading
    always_comb begin
        if (buffsel_pix) begin
            lb0_addr_pix = addr_on_pix[10:4];
            lb1_addr_pix = 0;
            case (prev_addr_on_pix[3:0])
                // 4'h0: colour_on_pix = lb0_colour_pix[7:0];
                // 4'h1: colour_on_pix = lb0_colour_pix[15:8];
                // 4'h2: colour_on_pix = lb0_colour_pix[23:16];
                // 4'h3: colour_on_pix = lb0_colour_pix[31:24];
                // 4'h4: colour_on_pix = lb0_colour_pix[39:32];
                // 4'h5: colour_on_pix = lb0_colour_pix[47:40];
                // 4'h6: colour_on_pix = lb0_colour_pix[55:48];
                // 4'h7: colour_on_pix = lb0_colour_pix[63:56];
                // 4'h8: colour_on_pix = lb0_colour_pix[71:64];
                // 4'h9: colour_on_pix = lb0_colour_pix[79:72];
                // 4'ha: colour_on_pix = lb0_colour_pix[87:80];
                // 4'hb: colour_on_pix = lb0_colour_pix[95:88];
                // 4'hc: colour_on_pix = lb0_colour_pix[103:96];
                // 4'hd: colour_on_pix = lb0_colour_pix[111:104];
                // 4'he: colour_on_pix = lb0_colour_pix[119:112];
                // 4'hf: colour_on_pix = lb0_colour_pix[127:120];
                4'h0: colour_on_pix = lb0_colour_pix[127:120];
                4'h1: colour_on_pix = lb0_colour_pix[119:112];
                4'h2: colour_on_pix = lb0_colour_pix[111:104];
                4'h3: colour_on_pix = lb0_colour_pix[103:96];
                4'h4: colour_on_pix = lb0_colour_pix[95:88];
                4'h5: colour_on_pix = lb0_colour_pix[87:80];
                4'h6: colour_on_pix = lb0_colour_pix[79:72];
                4'h7: colour_on_pix = lb0_colour_pix[71:64];
                4'h8: colour_on_pix = lb0_colour_pix[63:56];
                4'h9: colour_on_pix = lb0_colour_pix[55:48];
                4'ha: colour_on_pix = lb0_colour_pix[47:40];
                4'hb: colour_on_pix = lb0_colour_pix[39:32];
                4'hc: colour_on_pix = lb0_colour_pix[31:24];
                4'hd: colour_on_pix = lb0_colour_pix[23:16];
                4'he: colour_on_pix = lb0_colour_pix[15:8];
                4'hf: colour_on_pix = lb0_colour_pix[7:0];
            endcase
        end else begin
            lb1_addr_pix = addr_on_pix[10:4];
            lb0_addr_pix = 0;
            case (prev_addr_on_pix[3:0])
                4'h0: colour_on_pix = lb1_colour_pix[127:120];
                4'h1: colour_on_pix = lb1_colour_pix[119:112];
                4'h2: colour_on_pix = lb1_colour_pix[111:104];
                4'h3: colour_on_pix = lb1_colour_pix[103:96];
                4'h4: colour_on_pix = lb1_colour_pix[95:88];
                4'h5: colour_on_pix = lb1_colour_pix[87:80];
                4'h6: colour_on_pix = lb1_colour_pix[79:72];
                4'h7: colour_on_pix = lb1_colour_pix[71:64];
                4'h8: colour_on_pix = lb1_colour_pix[63:56];
                4'h9: colour_on_pix = lb1_colour_pix[55:48];
                4'ha: colour_on_pix = lb1_colour_pix[47:40];
                4'hb: colour_on_pix = lb1_colour_pix[39:32];
                4'hc: colour_on_pix = lb1_colour_pix[31:24];
                4'hd: colour_on_pix = lb1_colour_pix[23:16];
                4'he: colour_on_pix = lb1_colour_pix[15:8];
                4'hf: colour_on_pix = lb1_colour_pix[7:0];
            endcase
        end
    end

    // draw write ports
    always_comb begin
        if (buffsel_draw) begin
            lb0_addr_draw = addr_on_draw;
            lb0_we_draw = {16{we_on_draw}};
            lb0_colour_draw = colour_on_draw;

            lb1_addr_draw = addr_off_draw;
            lb1_we_draw = we_off_draw;
            lb1_colour_draw = colour_off_draw;
        end else begin
            lb1_addr_draw = addr_on_draw;
            lb1_we_draw = {16{we_on_draw}};
            lb1_colour_draw = colour_on_draw;

            lb0_addr_draw = addr_off_draw;
            lb0_we_draw = we_off_draw;
            lb0_colour_draw = colour_off_draw;
        end
    end

endmodule
