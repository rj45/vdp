// (C) 2023 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

module main #(parameter CORDW=11) ( // coordinate width
    input  logic clk_pix,           // pixel clock
    input  logic rst_pix,           // pixel reset
    input  logic clk_draw,          // draw clock
    input  logic rst_draw,          // draw reset
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

    // CDC of line from pix clock to draw clock
    logic d0_line;
    cdc_pulse_synchronizer_2phase line_cdc (
        .sending_clock(clk_pix),
        .sending_pulse_in(x0_line),
        // verilator lint_off PINCONNECTEMPTY
        // .sending_ready(),
        // verilator lint_on PINCONNECTEMPTY

        .receiving_clock(clk_draw),
        .receiving_pulse_out(d0_line)
    );

    // CDC of frame from pix clock to draw clock
    logic d0_frame;
    cdc_pulse_synchronizer_2phase frame_cdc (
        .sending_clock(clk_pix),
        .sending_pulse_in(x0_frame),
        // verilator lint_off PINCONNECTEMPTY
        // .sending_ready(),
        // verilator lint_on PINCONNECTEMPTY

        .receiving_clock(clk_draw),
        .receiving_pulse_out(d0_frame)
    );

    // CDC from pix clock to draw clock -- part 1
    // this isn't entirely required, since d0_line is already synchronized
    // and y should be stable by the time the pulse goes through CDC
    logic [CORDW-1:0] d0x0_sy;
    always_ff @(posedge clk_draw) begin
        d0x0_sy <= x0_sy;
    end


    // CDC from pix clock to draw clock -- part 2

    logic [CORDW-1:0] d0_sy;

    always_ff @(posedge clk_draw) begin
        // y should only increment on line going high
        if (d0_line) begin
            d0_sy <= d0x0_sy;
        end
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d1: Calculate addresses
    //////////////////////////////////////////////////////////////////////

    logic [11:0]  d1_lb_x;
    logic [143:0] d1_unaligned_pixels;
    logic [15:0]  d1_unaligned_valid_mask;
    logic [2:0]   d1_alignment_shift;

    logic [4:0]   d1_tile_map_y;
    logic [4:0]   d1_tile_map_x;
    logic [2:0]   d1_tile_row;
    logic         d1_tile_col;

    logic [11:0]  d1_frame_counter;
    logic [7:0]   d1_tile_counter;

    logic         d1_line;
    logic         d1_bufsel;

    always_ff @(posedge clk_draw) begin
        if (d0_frame) d1_frame_counter <= d1_frame_counter + 1;

        if (d0_line) begin
            d1_lb_x <= d1_frame_counter;

            d1_tile_map_y <= 5'h0;
            d1_tile_row <= 3'h0;
            d1_tile_map_x <= 5'h0;
            d1_tile_col <= 1'h0;

            d1_tile_counter <= 8'h0;
        end else begin
            d1_lb_x <= d1_lb_x + 8;

            d1_tile_map_y <= d0_sy[8:4];
            d1_tile_row <= d0_sy[3:1]; // tile is 8 rows high, repeat each row 2 times
            d1_tile_map_x <= d1_tile_counter[5:1];
            d1_tile_col <= d1_tile_counter[0];

            d1_tile_counter <= d1_tile_counter + 1;
        end

        d1_line <= d0_line;
        d1_bufsel <= d0_sy[0];
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d2: Load the tile map data from the tile map BRAM
    //////////////////////////////////////////////////////////////////////

    logic [11:0]  d2_lb_x;
    logic [15:0]  d2_tile_map_data;
    logic [2:0]   d2_tile_row;
    logic         d2_tile_col;
    logic         d2_line;
    logic         d2_bufsel;

    tile_map_bram #("tile_map.hex") tile_map_inst (
        .clk_draw(clk_draw),
        .tile_y(d1_tile_map_y),
        .tile_x(d1_tile_map_x),

        .tile_map_data(d2_tile_map_data)
    );

    always_ff @(posedge clk_draw) begin
        d2_lb_x <= d1_lb_x;
        d2_line <= d1_line;
        d2_bufsel <= d1_bufsel;
        d2_tile_row <= d1_tile_row;
        d2_tile_col <= d1_tile_col;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d3: Load the pixel data from the tile BRAM
    //////////////////////////////////////////////////////////////////////

    logic [15:0]  d3_tile_data;
    logic [35:0]  d3_tile_pixels;
    logic [3:0]   d3_tile_valid_mask = 4'b1111;
    logic [11:0]  d3_lb_x;
    logic         d3_line;
    logic         d3_bufsel;
    logic [4:0]   d3_palette_index;

    tile_bram #("tiles.hex") tile_inst (
        .clk_draw(clk_draw),
        // .tile_y(d2_tile_map_data[9:5]),
        // .tile_x(d2_tile_map_data[4:0]),
        .tile_index(d2_tile_map_data[9:0]),
        .tile_row(d2_tile_row),
        .tile_col(d2_tile_col),

        .tile_data(d3_tile_data)
    );

    always_comb begin
        d3_tile_pixels = {
            d3_palette_index, d3_tile_data[3:0],
            d3_palette_index, d3_tile_data[7:4],
            d3_palette_index, d3_tile_data[11:8],
            d3_palette_index, d3_tile_data[15:12]
        };
    end

    always_ff @(posedge clk_draw) begin
        d3_lb_x <= d2_lb_x;
        d3_line <= d2_line;
        d3_bufsel <= d2_bufsel;
        d3_palette_index <= d2_tile_map_data[14:10];
    end


    //////////////////////////////////////////////////////////////////////
    // Draw cycle d4: Double the pixels
    //////////////////////////////////////////////////////////////////////

    logic [8:0]   d4_lb_addr_draw;
    logic [143:0] d4_unaligned_pixels;
    logic [15:0]  d4_unaligned_valid_mask;
    logic [2:0]   d4_alignment_shift;
    logic         d4_line;
    logic         d4_bufsel;

    pixel_doubler double_inst (
        .clk_draw,
        .rst_draw(d3_line),

        .tile_pixels(d3_tile_pixels),
        .tile_valid_mask(d3_tile_valid_mask),
        .lb_x(d3_lb_x),

        .lb_addr(d4_lb_addr_draw),
        .unaligned_pixels(d4_unaligned_pixels),
        .unaligned_valid_mask(d4_unaligned_valid_mask),
        .alignment_shift(d4_alignment_shift)
    );

    always_ff @(posedge clk_draw) begin
        d4_line <= d3_line;
        d4_bufsel <= d3_bufsel;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d5: Shift align the pixels
    //////////////////////////////////////////////////////////////////////

    logic [71:0]  d5_lb_colour_draw;
    logic [7:0]   d5_lb_mask_draw;
    logic [8:0]   d5_lb_addr_draw;
    logic         d5_bufsel;

    shift_aligner shifter_inst (
        .clk_draw,
        .rst_draw(d4_line),

        .unaligned_pixels(d4_unaligned_pixels),
        .unaligned_valid_mask(d4_unaligned_valid_mask),
        .alignment_shift(d4_alignment_shift),

        .aligned_pixels(d5_lb_colour_draw),
        .aligned_valid_mask(d5_lb_mask_draw)
    );

    always_ff @(posedge clk_draw) begin
        d5_lb_addr_draw <= d4_lb_addr_draw;
        d5_bufsel <= d4_bufsel;
    end

    ////////////////////////////////////////////////////////////////
    // Draw cycle d6: Write to the line buffer
    // Pix cycle p1: Read the line buffer
    ////////////////////////////////////////////////////////////////

    logic [8:0]       p1_colour_pix;
    logic [CORDW-1:0] p1_sx;
    logic [CORDW-1:0] p1_sy;
    logic             p1_de;
    logic             p1_vsync;
    logic             p1_hsync;

    double_buffer db_inst (
        .clk_pix,
        .clk_draw,

        .buffsel_pix(x0_sy[0]),
        .buffsel_draw(d5_bufsel),

        .addr_on_pix({1'd0,x0_sx}),
        .colour_on_pix(p1_colour_pix),

        .addr_on_draw(9'd0), // for now
        .we_on_draw(1'd0), // for now
        .colour_on_draw(72'd0), // for now

        .addr_off_draw(d5_lb_addr_draw),
        .we_off_draw(d5_lb_mask_draw),
        .colour_off_draw(d5_lb_colour_draw)
    );

    always_ff @(posedge clk_pix) begin
        p1_sx <= x0_sx;
        p1_sy <= x0_sy;
        p1_de <= x0_de;
        p1_vsync <= x0_vsync;
        p1_hsync <= x0_hsync;
    end

     ////////////////////////////////////////////////////////////////
    // Pix cycle p1b: Lookup the palette entry
    ////////////////////////////////////////////////////////////////

    logic [CORDW-1:0] p1b_sx;
    logic [CORDW-1:0] p1b_sy;
    logic             p1b_de;
    logic             p1b_vsync;
    logic             p1b_hsync;
    logic [8:0]       p1b_colour_pix;


    always_ff @(posedge clk_pix) begin
        p1b_sx <= p1_sx;
        p1b_sy <= p1_sy;
        p1b_de <= p1_de;
        p1b_vsync <= p1_vsync;
        p1b_hsync <= p1_hsync;
        p1b_colour_pix <= p1_colour_pix;
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
    logic [7:0]       p2_r;
    logic [7:0]       p2_g;
    logic [7:0]       p2_b;

    palette_bram #("palette.hex") palbram_inst (
        .clk_pix,
        .colour_pix(p1b_colour_pix),
        .rgb(p2_rgb)
    );

    assign p2_r = p2_rgb[23:16];
    assign p2_g = p2_rgb[15:8];
    assign p2_b = p2_rgb[7:0];

    always_ff @(posedge clk_pix) begin
        p2_sx <= p1b_sx;
        p2_sy <= p1b_sy;
        p2_de <= p1b_de;
        p2_vsync <= p1b_vsync;
        p2_hsync <= p1b_hsync;
    end

    ////////////////////////////////////////////////////////////////
    // Pix cycle p3: Output to screen
    ////////////////////////////////////////////////////////////////

    always_ff @(posedge clk_pix) begin
        sx <= p2_sx;
        sy <= p2_sy;
        de <= p2_de;
        vsync <= p2_vsync;
        hsync <= p2_hsync;

        r <= p2_de ? p2_r : 8'h0;
        g <= p2_de ? p2_g : 8'h0;
        b <= p2_de ? p2_b : 8'h0;
    end

endmodule
