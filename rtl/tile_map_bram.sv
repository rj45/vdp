// (C) 2025 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

// tile_map_bram is a temporary ROM storage for tile map data,
// eventually this will be stored in main memory.
//
// It's arranged as a 32x32 grid of 16 bit values.

module tile_map_bram #(parameter FILENAME="") (
  input  logic        clk_draw,
  input  logic [9:0]  tilemap_addr,
  output logic [15:0] tilemap_data
);

    // This should be 1 BRAM on the ECP5, 4 on the up5k
    reg [15:0] rom[0:1023];

    initial begin
        if (FILENAME!="")
            $readmemh(FILENAME, rom);
    end

    always_ff @(posedge clk_draw) begin
        tilemap_data <= rom[tilemap_addr];
    end

endmodule
