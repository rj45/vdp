// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

// tile_bram is a temporary ROM storage for tile pixel data,
// eventually this will be stored in main memory.
//
// It's arranged as 256x256 pixels, split into a grid of
// 32x32 8x8 tiles.
// The tile_x and tile_y are the position of the tile in the
// 32x32 grid.
// The tile_row is which of the 8 rows of the tile to reference.
// The tile_col is which of the two groups of 4 pixels on
// that tile's row to return.

module tile_bram #(parameter FILENAME="") (
  input  logic        clk_draw,
//   input  logic [4:0]  tile_y,
//   input  logic [4:0]  tile_x,
  input  logic [9:0] tile_index,
  input  logic [2:0]  tile_row,
  input  logic        tile_col,
  output logic [15:0] tile_data
);

    // This should be 16 BRAMs on the ECP5
    reg [15:0] rom[0:16383];

    initial begin
        if (FILENAME!="")
            $readmemh(FILENAME, rom);
    end

    always_ff @(posedge clk_draw) begin
        tile_data <= rom[{
            // tile_y, tile_row,  // y index of the row
            // tile_x, tile_col   // x position of the tile pixels
            tile_index, tile_row, tile_col
        }];
    end

endmodule
