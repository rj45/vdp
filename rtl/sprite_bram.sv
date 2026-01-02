// (C) 2025 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

`include "sprite_types.sv"

module sprite_bram #(parameter FILENAME="") (
    input  logic             clk_draw,
    input  logic [8:0]       sprite_index,
    output sprite_y_height_t sprite_y_height,
    output sprite_x_width_t  sprite_x_width,
    output sprite_addr_t     sprite_addr,
    output sprite_velocity_t sprite_velocity,

    input logic [8:0]        w_index,
    input sprite_y_height_t  w_sprite_y_height,
    input logic              w_sprite_y_height_en,
    input sprite_x_width_t   w_sprite_x_width,
    input logic              w_sprite_x_width_en,
    input sprite_addr_t      w_sprite_addr,
    input logic              w_sprite_addr_en,
    input sprite_velocity_t  w_sprite_velocity,
    input logic              w_sprite_velocity_en
);
    reg [(36*4)-1:0] bram[0:511];
    reg [(36*4)-1:0] sprite_data;

    initial begin
        // if (FILENAME!="")
        //     $readmemh(FILENAME, bram);
        for (int i=0; i<512; i=i+1) begin
            bram[i] = {
                // sprite_velocity_t -- my lame attempt at pseudo-randomness (doesn't work, but the pattern is pretty)
                18'((((((i + ((i / 32)*13) + 'h811c9dc5) & 'hffffffff) * 'h01000193) & 'hffffffff) % 32) - 16),// velocity_x
                18'((((((i + ((i / 32)*13) + 512 + 'h811c9dc5) & 'hffffffff) * 'h01000193) & 'hffffffff) % 32) - 16), // velocity_y

                // sprite_addr_t
                18'd0, // tilemap_addr
                18'd0, // tile_bitmap_addr

                // sprite_x_width_t
                2'd0,                    // unused
                1'b0,                    // y_flip
                1'b0,                    // x_flip
                8'd1,                    // width
                8'(i % 32),              // tilemap_x
                12'(((i % 32)*17)+384),  // screen_x
                4'd0,                    // screen_sub_x

                // sprite_y_height_t
                2'd0,                    // a
                2'd0,                    // b
                8'd2,                    // height
                8'((i / 32)*2),          // tilemap_y
                12'(((i / 32) * 33)+104),// screen_y
                4'd0                     // screen_sub_y
            };
        end
    end

    always_ff @(posedge clk_draw) begin
        sprite_data     <= bram[sprite_index];
    end

    always_ff @(posedge clk_draw) begin
        if (w_sprite_y_height_en)
            bram[w_index][35:0]    <= w_sprite_y_height;
        if (w_sprite_x_width_en)
            bram[w_index][71:36]   <= w_sprite_x_width;
        if (w_sprite_addr_en)
            bram[w_index][107:72]  <= w_sprite_addr;
        if (w_sprite_velocity_en)
            bram[w_index][143:108] <= w_sprite_velocity;
    end

    always_comb begin
        sprite_y_height = sprite_data[35:0];
        sprite_x_width  = sprite_data[71:36];
        sprite_addr     = sprite_data[107:72];
        sprite_velocity = sprite_data[143:108];
    end

endmodule
