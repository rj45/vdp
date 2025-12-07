// (C) 2025 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module sprite_bram #(parameter FILENAME="") (
    input  logic             clk_draw,
    input  logic [8:0]       sprite_index,
    output sprite_y_height_t sprite_y_height,
    output sprite_x_width_t  sprite_x_width,
    output sprite_addr_t     sprite_addr
);
    reg [(36*3)-1:0] bram[0:511];
    reg [(36*3)-1:0] sprite_data;

    initial begin
    if (FILENAME!="")
        $readmemh(FILENAME, bram);
    end

    always_ff @(posedge clk_draw) begin
        sprite_data     <= bram[sprite_index];
    end

    always_comb begin
        sprite_y_height = sprite_data[35:0];
        sprite_x_width  = sprite_data[71:36];
        sprite_addr     = sprite_data[107:72];
    end

endmodule
