// (C) 2025 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module sprite_matcher (
    input  logic             clk_draw,
    input  logic             line,
    input  logic [11:0]      next_sy
);
    parameter FILENAME = "sprites.hex";

    logic [8:0]       sprite_index;
    sprite_y_height_t sprite_y_height;
    sprite_x_width_t  sprite_x_width;
    sprite_addr_t     sprite_addr;




    sprite_bram #(FILENAME) sprite_inst (
        .clk_draw(clk_draw),
        .sprite_index(sprite_index),

        .sprite_y_height(sprite_y_height),
        .sprite_x_width(sprite_x_width),
        .sprite_addr(sprite_addr)
    );

    // pad the screen y coord to 16 bits
    logic [15:0] screen_sy;
    assign screen_sy = {4'b0, next_sy};

    // a tile is either 16 or 32 pixels tall with pixel doubling so the height is
    // shifted left by either 4 or 5 bits.
    logic [15:0] sprite_height;
    assign sprite_height = sprite_y_height.tile_size ?
        {sprite_y_height.height, 5'b0} :
        {1'b0, sprite_y_height.height, 4'b0};

    // determine the last y coord on screen for the sprite
    logic [15:0] sprite_last_y;
    assign sprite_last_y = sprite_y_height.screen_y + sprite_height;

    // check if the current line is between the min and max y coord of the sprite
    logic sprite_y_match;
    assign sprite_y_match = (screen_sy >= sprite_y_height.screen_sy) && (screen_sy < sprite_last_y);




    always_comb begin
        if (sprite_y_height.screen_sy >= screen_sy) begin
            // determine the high
        end
    end

    always_ff @(posedge clk_draw) begin
        if (line) begin
            sprite_index <= 0;
        end else begin
            sprite_index <= sprite_index + 1;
        end
    end

endmodule
