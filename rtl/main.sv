// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module main #(parameter CORDW=11) ( // coordinate width
    input  logic clk_pix,           // pixel clock
    input  logic rst_pix,           // pixel reset
    output logic [CORDW-1:0] sx,    // horizontal position
    output logic [CORDW-1:0] sy,    // vertical position
    output logic de,                // data enable (low in blanking interval)
    output logic vsync,             // vertical sync
    output logic hsync,             // horizontal sync
    output logic [7:0] r,           // 8-bit red
    output logic [7:0] g,           // 8-bit green
    output logic [7:0] b            // 8-bit blue
);
    //////////////////////////////////////////////////////////////////////
    // Pix cycle p0 / Draw cycle d0: Generate the VGA signals
    //////////////////////////////////////////////////////////////////////

    logic             x0_line;
    logic             x0_frame;
    logic [CORDW-1:0] x0_sx;
    logic [CORDW-1:0] x0_sy;
    logic             x0_de;
    logic             x0_vsync;
    logic             x0_hsync;

    // display sync signals and coordinates
    vga #(CORDW) vga_inst (
        .clk_pix,
        .rst_pix,
        .sx(x0_sx),
        .sy(x0_sy),
        .hsync(x0_hsync),
        .vsync(x0_vsync),
        .de(x0_de),
        .line(x0_line),
        .frame(x0_frame)
    );

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d1: Calculate addresses
    //////////////////////////////////////////////////////////////////////

    logic [10:0]  d1_lb_x;
    logic [255:0] d1_unaligned_pixels;
    logic [31:0]  d1_unaligned_valid_mask;
    logic [3:0]   d1_alignment_shift;

    logic [4:0]   d1_tile_y;
    logic [4:0]   d1_tile_x;
    logic [2:0]   d1_tile_row;
    logic         d1_tile_col;

    logic [10:0]  d1_frame_counter;
    logic [7:0]   d1_tile_counter;

    logic         d1_line;
    logic         d1_bufsel;

    always_ff @(posedge clk_pix) begin
        if (x0_frame) d1_frame_counter <= d1_frame_counter + 1;

        if (x0_line) begin
            d1_lb_x <= d1_frame_counter;

            d1_tile_y <= 5'h0;
            d1_tile_row <= 3'h0;
            d1_tile_x <= 5'h0;
            d1_tile_col <= 1'h0;

            d1_tile_counter <= 8'h0;
        end else begin
            d1_lb_x <= d1_lb_x + 16;

            d1_tile_y <= x0_sy[9:5]; // repeat each row 4 times
            d1_tile_row <= x0_sy[4:2];
            d1_tile_x <= d1_tile_counter[5:1];
            d1_tile_col <= d1_tile_counter[0];

            d1_tile_counter <= d1_tile_counter + 1;
        end

        d1_line <= x0_line;
        d1_bufsel <= x0_sy[0];
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d2: Load the pixel data from the tile BRAM
    //////////////////////////////////////////////////////////////////////

    logic [15:0]  d2_tile_data;
    logic [31:0]  d2_tile_pixels;
    logic [3:0]   d2_tile_valid_mask = 4'b1111;
    logic [10:0]  d2_lb_x;
    logic         d2_line;
    logic         d2_bufsel;

    tile_bram #("tiles.hex") tile_inst (
        .clk_draw(clk_pix),
        .tile_y(d1_tile_y),
        .tile_x(d1_tile_x),
        .tile_row(d1_tile_row),
        .tile_col(d1_tile_col),

        .tile_data(d2_tile_data)
    );

    always_comb begin
        d2_tile_pixels = {
            4'h0, d2_tile_data[15:12],
            4'h0, d2_tile_data[11:8],
            4'h0, d2_tile_data[7:4],
            4'h0, d2_tile_data[3:0]
        };
    end

    always_ff @(posedge clk_pix) begin
        d2_lb_x <= d1_lb_x;
        d2_line <= d1_line;
        d2_bufsel <= d1_bufsel;
    end


    //////////////////////////////////////////////////////////////////////
    // Draw cycle d3: Quadruple the pixels
    //////////////////////////////////////////////////////////////////////

    logic [6:0]   d3_lb_addr_draw;
    logic [255:0] d3_unaligned_pixels;
    logic [31:0]  d3_unaligned_valid_mask;
    logic [3:0]   d3_alignment_shift;
    logic         d3_line;
    logic         d3_bufsel;

    pixel_quadrupler quad_inst (
        .clk_draw(clk_pix),
        .rst_draw(d2_line),

        .tile_pixels(d2_tile_pixels),
        .tile_valid_mask(d2_tile_valid_mask),
        .lb_x(d2_lb_x),

        .lb_addr(d3_lb_addr_draw),
        .unaligned_pixels(d3_unaligned_pixels),
        .unaligned_valid_mask(d3_unaligned_valid_mask),
        .alignment_shift(d3_alignment_shift)
    );

    always_ff @(posedge clk_pix) begin
        d3_line <= d2_line;
        d3_bufsel <= d2_bufsel;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d4: Shift align the pixels
    //////////////////////////////////////////////////////////////////////

    logic [127:0] d4_lb_colour_draw;
    logic [15:0]  d4_lb_mask_draw;
    logic [6:0]   d4_lb_addr_draw;
    logic         d4_bufsel;

    shift_aligner shifter_inst (
        .clk_draw(clk_pix),
        .rst_draw(d3_line),

        .unaligned_pixels(d3_unaligned_pixels),
        .unaligned_valid_mask(d3_unaligned_valid_mask),
        .alignment_shift(d3_alignment_shift),

        .aligned_pixels(d4_lb_colour_draw),
        .aligned_valid_mask(d4_lb_mask_draw)
    );

    always_ff @(posedge clk_pix) begin
        d4_lb_addr_draw <= d3_lb_addr_draw;
        d4_bufsel <= d3_bufsel;
    end

    ////////////////////////////////////////////////////////////////
    // Draw cycle d5: Write to the line buffer
    // Pix cycle p1: Read the line buffer
    ////////////////////////////////////////////////////////////////

    logic [7:0]       p1_colour_pix;
    logic [CORDW-1:0] p1_sx;
    logic [CORDW-1:0] p1_sy;
    logic             p1_de;
    logic             p1_vsync;
    logic             p1_hsync;

    double_buffer db_inst (
        .clk_pix,
        .clk_draw(clk_pix), // for now

        .buffsel_pix(x0_sy[0]),
        .buffsel_draw(d4_bufsel), // for now

        .addr_on_pix(x0_sx),
        .colour_on_pix(p1_colour_pix),

        .addr_on_draw(7'd0), // for now
        .we_on_draw(1'd0), // for now
        .colour_on_draw(128'd0), // for now

        .addr_off_draw(d4_lb_addr_draw),
        .we_off_draw(d4_lb_mask_draw),
        .colour_off_draw(d4_lb_colour_draw)
    );

    always_ff @(posedge clk_pix) begin
        p1_sx <= x0_sx;
        p1_sy <= x0_sy;
        p1_de <= x0_de;
        p1_vsync <= x0_vsync;
        p1_hsync <= x0_hsync;
    end

    ////////////////////////////////////////////////////////////////
    // Pix cycle p2: Lookup the palette entry
    ////////////////////////////////////////////////////////////////

    logic [CORDW-1:0] p2_sx;
    logic [CORDW-1:0] p2_sy;
    logic             p2_de;
    logic             p2_vsync;
    logic             p2_hsync;
    logic [23:0]      p2_rgb;

    palette_bram #("palette.hex") palbram_inst (
        .clk_pix,
        .colour_pix(p1_colour_pix),
        .rgb(p2_rgb)
    );

    // do the palette lookup
    logic [7:0] p2_paint_r, p2_paint_g, p2_paint_b;
    always_comb begin
        p2_paint_b = p2_rgb[7:0];
        p2_paint_g = p2_rgb[15:8];
        p2_paint_r = p2_rgb[23:16];
    end

    // display colour: paint colour but black in blanking interval
    logic [7:0] p2_display_r, p2_display_g, p2_display_b;
    always_comb begin
        p2_display_r = (de) ? p2_paint_r : 8'h0;
        p2_display_g = (de) ? p2_paint_g : 8'h0;
        p2_display_b = (de) ? p2_paint_b : 8'h0;
    end

    always_ff @(posedge clk_pix) begin
        p2_sx <= p1_sx;
        p2_sy <= p1_sy;
        p2_de <= p1_de;
        p2_vsync <= p1_vsync;
        p2_hsync <= p1_hsync;
    end

    ////////////////////////////////////////////////////////////////
    // Pix cycle p3: output to screen
    ////////////////////////////////////////////////////////////////

    always_ff @(posedge clk_pix) begin
        sx <= p2_sx;
        sy <= p2_sy;
        de <= p2_de;
        vsync <= p2_vsync;
        hsync <= p2_hsync;
        r <= p2_display_r;
        g <= p2_display_g;
        b <= p2_display_b;
    end
endmodule
