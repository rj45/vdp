// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module main #(parameter CORDW=11) (  // coordinate width
    input  logic clk_pix,             // pixel clock
    input  logic rst_pix,             // pixel reset
    output logic [CORDW-1:0] sx,  // horizontal position
    output logic [CORDW-1:0] sy,  // vertical position
    output logic de,              // data enable (low in blanking interval)
    output logic vsync,           // vertical sync
    output logic hsync,           // horizontal sync
    output logic [7:0] r,         // 8-bit red
    output logic [7:0] g,         // 8-bit green
    output logic [7:0] b          // 8-bit blue
    );

    logic line;
    logic frame;

    // display sync signals and coordinates
    vga #(CORDW) vga_inst (
        .clk_pix,
        .rst_pix,
        .sx,
        .sy,
        .hsync,
        .vsync,
        .de,
        .line,
        .frame
    );

    logic [7:0] colour_pix;
    logic [23:0] rgb;

    palette_bram #("palette.hex") palbram_inst (
        .clk_pix,
        .colour_pix,
        .rgb
    );

    logic [6:0] lb_addr_draw;
    logic [127:0] lb_colour_draw;
    logic [15:0] lb_mask_draw;

    double_buffer db_inst (
        .clk_pix,
        .clk_draw(clk_pix), // for now

        .buffsel_pix(sy[0]),
        .buffsel_draw(sy[0]), // for now

        .addr_on_pix(sx),
        .colour_on_pix(colour_pix),

        .addr_on_draw(7'd0), // for now
        .we_on_draw(1'd0), // for now
        .colour_on_draw(128'd0), // for now

        .addr_off_draw(lb_addr_draw),
        .we_off_draw(lb_mask_draw),
        .colour_off_draw(lb_colour_draw)
    );

    logic [31:0]  tile_pixels;
    logic [3:0]   tile_valid_mask = 4'b1111;
    logic [10:0]  lb_x;
    logic [255:0] unaligned_pixels;
    logic [31:0]  unaligned_valid_mask;
    logic [3:0]   alignment_shift;

    pixel_quadrupler quad_inst (
        .clk_draw(clk_pix),
        .rst_draw(line),

        .tile_pixels,
        .tile_valid_mask,
        .lb_x,

        .lb_addr(lb_addr_draw),
        .unaligned_pixels,
        .unaligned_valid_mask,
        .alignment_shift
    );

    shift_aligner shifter_inst (
        .clk_draw(clk_pix),
        .rst_draw(line),

        .unaligned_pixels,
        .unaligned_valid_mask,
        .alignment_shift,

        .aligned_pixels(lb_colour_draw),
        .aligned_valid_mask(lb_mask_draw)
    );


    logic [4:0]  tile_y;
    logic [4:0]  tile_x;
    logic [2:0]  tile_row;
    logic        tile_col;
    logic [15:0] tile_data;

    tile_bram #("tiles.hex") tile_inst (
        .clk_draw(clk_pix),
        .tile_y,
        .tile_x,
        .tile_row,
        .tile_col,
        .tile_data
    );

    logic [10:0] frame_counter;
    logic [7:0] tile_counter;

    always_ff @(posedge clk_pix) begin
        if (frame) frame_counter <= frame_counter + 1;

        if (line) begin
            lb_x <= frame_counter;

            tile_y <= 5'h0;
            tile_row <= 3'h0;
            tile_x <= 5'h0;
            tile_col <= 1'h0;
            tile_pixels <= 32'h0;

            tile_counter <= 8'h0;
        end else begin
            lb_x <= lb_x + 16;

            tile_y <= sy[9:5]; // repeat each row 4 times
            tile_row <= sy[4:2];
            tile_x <= tile_counter[5:1];
            tile_col <= tile_counter[0];
            tile_pixels <= {
                4'h0, tile_data[15:12],
                4'h0, tile_data[11:8],
                4'h0, tile_data[7:4],
                4'h0, tile_data[3:0]
            };

            tile_counter <= tile_counter + 1;
        end
    end

    // do the palette lookup
    logic [7:0] paint_r, paint_g, paint_b;
    always_comb begin
        paint_b = rgb[7:0];
        paint_g = rgb[15:8];
        paint_r = rgb[23:16];
    end

    // display colour: paint colour but black in blanking interval
    logic [7:0] display_r, display_g, display_b;
    always_comb begin
        display_r = (de) ? paint_r : 8'h0;
        display_g = (de) ? paint_g : 8'h0;
        display_b = (de) ? paint_b : 8'h0;
    end

    always_ff @(posedge clk_pix) begin
        r <= display_r;
        g <= display_g;
        b <= display_b;
    end
endmodule
