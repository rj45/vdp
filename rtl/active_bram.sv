// (C) 2025 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

`include "sprite_types.sv"

module active_bram (
    input  logic                 clk_draw,

    input  logic                 write_enable,
    input  logic [8:0]           write_index,
    input  active_tilemap_addr_t write_tilemap_addr,
    input  active_bitmap_addr_t  write_bitmap_addr,

    input  logic [8:0]           read_index,
    output active_tilemap_addr_t read_tilemap_addr,
    output active_bitmap_addr_t  read_bitmap_addr
);
    reg [(36*2)-1:0] bram[0:511];
    reg [(36*2)-1:0] sprite_data;

    always_ff @(posedge clk_draw) begin
        if (write_enable) begin
            bram[write_index] <= {write_bitmap_addr, write_tilemap_addr};
        end
    end

    always_ff @(posedge clk_draw) begin
        sprite_data     <= bram[read_index];
    end

    always_comb begin
        read_tilemap_addr = sprite_data[35:0];
        read_bitmap_addr  = sprite_data[71:36];
    end

endmodule
