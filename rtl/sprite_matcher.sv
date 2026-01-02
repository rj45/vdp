// (C) 2025 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

`include "sprite_types.sv"

module sprite_matcher (
    input  logic                 clk_draw,
    input  logic                 rst_draw,
    input  logic                 enable,
    input  logic                 line,
    input  logic [10:0]          sy_plus2,

    input  logic [8:0]           sprite_index,
    output logic                 valid,
    output active_tilemap_addr_t tilemap_addr,
    output active_bitmap_addr_t  bitmap_addr,
    output logic [8:0]           sprite_count
);
    parameter FILENAME = "sprites.hex";

    logic [9:0]       scan_index;
    // verilator lint_off UNUSEDSIGNAL
    sprite_y_height_t sprite_y_height;
    sprite_x_width_t  sprite_x_width;
    sprite_addr_t     sprite_addr;
    sprite_velocity_t sprite_velocity;

    sprite_y_height_t w_sprite_y_height = '0;
    sprite_x_width_t  w_sprite_x_width = '0;
    // verilator lint_on UNUSEDSIGNAL

    logic [9:0]       write_index;
    logic             w_enable = 1'b0;

    sprite_bram #(FILENAME) sprite_inst (
        .clk_draw(clk_draw),
        .sprite_index(scan_index[8:0]),

        .sprite_y_height(sprite_y_height),
        .sprite_x_width(sprite_x_width),
        .sprite_addr(sprite_addr),
        .sprite_velocity(sprite_velocity),

        .w_index(write_index[8:0]),
        .w_sprite_y_height(w_sprite_y_height),
        .w_sprite_y_height_en(w_enable),
        .w_sprite_x_width(w_sprite_x_width),
        .w_sprite_x_width_en(w_enable),
        .w_sprite_addr('0),
        .w_sprite_addr_en(1'b0),
        .w_sprite_velocity('0),
        .w_sprite_velocity_en(1'b0)
    );

    logic                 sprite_match;
    active_tilemap_addr_t match_tilemap_addr;
    active_bitmap_addr_t  match_bitmap_addr;
    logic [9:0]           p2_active_count; // active count at line+2
    logic [9:0]           p2_last_index;   // last index at line+2
    logic [9:0]           p2_start_index;  // start index at line+2
    logic [9:0]           p1_active_count; // active count at line+1
    logic [9:0]           p1_start_index;  // start index at line+1
    logic                 next_valid;
    logic                 sprite_valid; // whether the data read from the sprite_bram is valid

    active_bram active_inst (
        .clk_draw(clk_draw),

        .write_enable(sprite_match),
        .write_index(p2_last_index[8:0]),
        .write_tilemap_addr(match_tilemap_addr),
        .write_bitmap_addr(match_bitmap_addr),

        .read_index(9'(sprite_index+p1_start_index)),
        .read_tilemap_addr(tilemap_addr),
        .read_bitmap_addr(bitmap_addr)
    );

    // pad the screen y coord to 13 bits
    logic [12:0] screen_sy;
    assign screen_sy = {2'b0, sy_plus2};

    // a tile is 16 pixels tall with pixel doubling so the height is
    // shifted left by 4 bits.
    logic [12:0] sprite_height;
    assign sprite_height = {1'b0, sprite_y_height.height, 4'b0};

    // determine the last y coord on screen for the sprite
    logic [12:0] sprite_last_y;
    assign sprite_last_y = {1'b0, sprite_y_height.screen_y} + sprite_height;

    // check if the current line is between the min and max y coord of the sprite
    logic sprite_y_match;
    assign sprite_y_match = (screen_sy >= {1'b0, sprite_y_height.screen_y}) && (screen_sy < sprite_last_y);

    assign sprite_match = enable && sprite_valid  && sprite_y_match;

    logic [12:0] sprite_line_y;
    assign sprite_line_y = screen_sy - {1'b0, sprite_y_height.screen_y};

    logic [12:0] sprite_offset_y;
    assign sprite_offset_y = (sprite_x_width.y_flip) ?
        (sprite_height - 13'd1 - sprite_line_y) :
        sprite_line_y;

    logic [12:0] sprite_tilemap_y;
    assign sprite_tilemap_y = (sprite_offset_y >> 4) + {4'd0, sprite_y_height.tilemap_y};

    logic [26:0] tilemap_offset_y;
    assign tilemap_offset_y =
        ({14'd0, sprite_tilemap_y} << (sprite_y_height.tilemap_size_a + 4)) +
        ({14'd0, sprite_tilemap_y} << (sprite_y_height.tilemap_size_b + 4));

    logic [17:0] tile_row;
    assign tile_row = { 6'd0, sprite_offset_y[3:1], 9'd0 };

    assign match_tilemap_addr.x_flip = sprite_x_width.x_flip;
    assign match_tilemap_addr.tile_count = sprite_x_width.width;
    assign match_tilemap_addr.tilemap_addr = {sprite_addr.tilemap_addr, 9'd0} +
        tilemap_offset_y + {19'd0,sprite_x_width.tilemap_x};

    assign match_bitmap_addr.unused = 6'd0;
    assign match_bitmap_addr.lb_addr = sprite_x_width.screen_x;
    assign match_bitmap_addr.tile_bitmap_addr = sprite_addr.tile_bitmap_addr + tile_row;

    assign next_valid = {1'd0, sprite_index} < p1_active_count;
    assign sprite_count = 9'(p1_active_count - 1); // FIXME: why is this off by one?

    logic [15:0] y_plus_velocity;
    assign y_plus_velocity = {sprite_y_height.screen_y, sprite_y_height.screen_sub_y} +
        sprite_velocity.y_velocity[15:0];

    logic [15:0] x_plus_velocity;
    assign x_plus_velocity = {sprite_x_width.screen_x, sprite_x_width.screen_sub_x} +
        sprite_velocity.x_velocity[15:0];

    logic [15:0] initial_delay = 0;

    always_ff @(posedge clk_draw) begin
        if (line) begin
            scan_index <= 10'd0;
            sprite_valid <= 1'b0;
        end else if (scan_index < 10'h200) begin
            scan_index <= scan_index + 10'd1;
            sprite_valid <= 1'b1;
        end else begin
            sprite_valid <= 1'b0;
        end
    end

    always_ff @(posedge clk_draw) begin
        if (sy_plus2 == 720) begin
            if (line) begin
                if (initial_delay < 16'd900)
                    initial_delay <= initial_delay + 16'd1;
                else
                write_index <= 10'd0;
            end else begin
                write_index <= write_index + (w_enable ? 10'd1 : 10'd0);
            end

            if (initial_delay == 16'd900) begin
                w_enable <= sprite_valid;
                w_sprite_y_height <= sprite_y_height;
                w_sprite_y_height.screen_y <= {1'b0, y_plus_velocity[14:4]};
                w_sprite_y_height.screen_sub_y <= y_plus_velocity[3:0];
                w_sprite_x_width <= sprite_x_width;
                w_sprite_x_width.screen_x <= {1'b0, x_plus_velocity[14:4]};
                w_sprite_x_width.screen_sub_x <= x_plus_velocity[3:0];
            end else begin
                w_enable <= 1'b0;
                write_index <= 10'd0;
                w_sprite_y_height <= '0;
                w_sprite_x_width <= '0;
            end
        end else begin
            w_enable <= 1'b0;
            write_index <= 10'd0;
            w_sprite_y_height <= '0;
            w_sprite_x_width <= '0;
        end
    end

    always_ff @(posedge clk_draw or posedge rst_draw) begin
        if (rst_draw) begin
            p2_start_index  <= 10'h0;
            p2_last_index   <= 10'h0;
            p2_active_count <= 10'h0;
            p1_start_index  <= 10'h0;
            p1_active_count <= 10'h0;
            valid           <= 1'b0;
        end else if (line) begin
            p1_start_index  <= p2_start_index;
            p2_start_index  <= p2_last_index;
            p1_active_count <= p2_active_count;
            p2_active_count <= 10'h0;
            valid           <= 1'b0;
        end else if (sprite_match) begin
            p2_last_index   <= p2_last_index + 1;
            p2_active_count <= p2_active_count + 1;
            valid           <= next_valid;
        end else begin
            valid           <= next_valid;
        end
    end

endmodule
