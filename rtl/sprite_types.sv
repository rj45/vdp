// (C) 2026 Ryan "rj45" Sanche, MIT License
//
// Data types for sprite handling

`ifndef SPRITE_TYPES_SV
`define SPRITE_TYPES_SV

// (1 << 7) + (1 << 7) = 128 + 128 = 256
// (1 << 7) + (1 << 5) = 128 + 32 = 160
// (1 << 6) + (1 << 6) = 64 + 64 = 128
// (1 << 6) + (1 << 4) = 64 + 16 = 80
// (1 << 5) + (1 << 5) = 32 + 32 = 64
// (1 << 4) + (1 << 4) = 16 + 16 = 32

typedef struct packed {
    // tilemap size: (1 << (tilemap_size_a + 4)) + (1 << (tilemap_size_b + 4))
    // tilemap addr: (y << (tilemap_size_a + 4)) + (y << (tilemap_size_b + 4)) + (tilemap_addr << 9)
    bit [1:0]  tilemap_size_a;
    bit [1:0]  tilemap_size_b;
    bit [7:0]  height;
    bit [7:0]  tilemap_y;
    bit [15:4] screen_y;
    bit [3:0]  screen_sub_y;
} sprite_y_height_t;

typedef struct packed {
    bit [1:0]  unused;
    bit        y_flip;
    bit        x_flip;
    bit [7:0]  width;
    bit [7:0]  tilemap_x;
    bit [15:4] screen_x;
    bit [3:0]  screen_sub_x;
} sprite_x_width_t;

typedef struct packed {
    bit [17:0] tilemap_addr;
    bit [17:0] tile_bitmap_addr;
} sprite_addr_t;

typedef struct packed {
    bit [17:0] x_velocity;
    bit [17:0] y_velocity;
} sprite_velocity_t;

typedef struct packed {
    bit        x_flip;
    bit [7:0]  tile_count;
    bit [26:0] tilemap_addr;
} active_tilemap_addr_t;

typedef struct packed {
    bit [5:0]  unused;
    bit [11:0] lb_addr;
    bit [17:0] tile_bitmap_addr; // actual addr: tile_bitmap_addr << 9
} active_bitmap_addr_t;

`endif
