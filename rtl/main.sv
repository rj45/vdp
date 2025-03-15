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

    logic [11:0]  d1_lb_x;
    logic [143:0] d1_unaligned_pixels;
    logic [15:0]  d1_unaligned_valid_mask;
    logic [2:0]   d1_alignment_shift;

    logic [4:0]   d1_tile_y;
    logic [4:0]   d1_tile_x;
    logic [2:0]   d1_tile_row;
    logic         d1_tile_col;

    logic [11:0]  d1_frame_counter;
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
            d1_lb_x <= d1_lb_x + 8;

            d1_tile_y <= x0_sy[8:4];
            d1_tile_row <= x0_sy[3:1]; // tile is 8 rows high, repeat each row 2 times
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
    logic [35:0]  d2_tile_pixels;
    logic [3:0]   d2_tile_valid_mask = 4'b1111;
    logic [11:0]  d2_lb_x;
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
            5'h0, d2_tile_data[15:12],
            5'h0, d2_tile_data[11:8],
            5'h0, d2_tile_data[7:4],
            5'h0, d2_tile_data[3:0]
        };
    end

    always_ff @(posedge clk_pix) begin
        d2_lb_x <= d1_lb_x;
        d2_line <= d1_line;
        d2_bufsel <= d1_bufsel;
    end


    //////////////////////////////////////////////////////////////////////
    // Draw cycle d3: Double the pixels
    //////////////////////////////////////////////////////////////////////

    logic [8:0]   d3_lb_addr_draw;
    logic [143:0] d3_unaligned_pixels;
    logic [15:0]  d3_unaligned_valid_mask;
    logic [2:0]   d3_alignment_shift;
    logic         d3_line;
    logic         d3_bufsel;

    pixel_doubler double_inst (
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

    logic [71:0]  d4_lb_colour_draw;
    logic [7:0]   d4_lb_mask_draw;
    logic [8:0]   d4_lb_addr_draw;
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

    logic [8:0]       p1_colour_pix;
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

        .addr_on_pix({1'd0,x0_sx}),
        .colour_on_pix(p1_colour_pix),

        .addr_on_draw(9'd0), // for now
        .we_on_draw(1'd0), // for now
        .colour_on_draw(72'd0), // for now

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
    logic [23:0]      p2_ycocg;
    logic [6:0]       p2_y;
    logic [7:0]       p2_co;
    logic [7:0]       p2_cg;


    palette_bram #("palette.hex") palbram_inst (
        .clk_pix,
        .colour_pix(p1_colour_pix),
        .rgb(p2_ycocg)
    );

    assign p2_y = p2_ycocg[22:16];
    assign p2_co = p2_ycocg[15:8];
    assign p2_cg = p2_ycocg[7:0];

    always_ff @(posedge clk_pix) begin
        p2_sx <= p1_sx;
        p2_sy <= p1_sy;
        p2_de <= p1_de;
        p2_vsync <= p1_vsync;
        p2_hsync <= p1_hsync;
    end

    ////////////////////////////////////////////////////////////////
    // Pix cycle p2b: Fade the y value as a test
    ////////////////////////////////////////////////////////////////

    logic [CORDW-1:0] p2b_sx;
    logic [CORDW-1:0] p2b_sy;
    logic             p2b_de;
    logic             p2b_vsync;
    logic             p2b_hsync;
    logic [6:0]       p2b_y;
    logic [7:0]       p2b_co;
    logic [7:0]       p2b_cg;
    logic [7:0]      p2b_y_tmp;

    always_comb begin
        p2b_y_tmp = {1'b0,p2_y} - d1_frame_counter[7:1];
        if (p2b_y_tmp > 8'd127) p2b_y_tmp = 8'd0;
    end

    always_ff @(posedge clk_pix) begin
        p2b_sx <= p2_sx;
        p2b_sy <= p2_sy;
        p2b_de <= p2_de;
        p2b_vsync <= p2_vsync;
        p2b_hsync <= p2_hsync;

        p2b_y <= p2_y; //p2b_y_tmp[6:0];
        p2b_co <= p2_co;
        p2b_cg <= p2_cg;
    end

    ////////////////////////////////////////////////////////////////
    // Pix cycle p3: Calculate tmp from ycocg
    ////////////////////////////////////////////////////////////////

    logic [CORDW-1:0] p3_sx;
    logic [CORDW-1:0] p3_sy;
    logic             p3_de;
    logic             p3_vsync;
    logic             p3_hsync;
    logic [7:0]       p3_co;
    logic [7:0]       p3_cg;
    logic [7:0]       p3_tmp;

    always_ff @(posedge clk_pix) begin
        p3_sx <= p2b_sx;
        p3_sy <= p2b_sy;
        p3_de <= p2b_de;
        p3_vsync <= p2b_vsync;
        p3_hsync <= p2b_hsync;

        p3_co <= p2b_co;
        p3_cg <= p2b_cg;
        // p3_tmp <= {1'b0, p2b_y[6:1]} - p2b_cg[7:1];
        p3_tmp <= $signed({1'b0, p2b_y}) - $signed({p2b_cg[7], p2b_cg[7:1]});
    end

    ////////////////////////////////////////////////////////////////
    // Pix cycle p4: Calculate b, g from ycocg, tmp
    ////////////////////////////////////////////////////////////////

    logic [CORDW-1:0] p4_sx;
    logic [CORDW-1:0] p4_sy;
    logic             p4_de;
    logic             p4_vsync;
    logic             p4_hsync;
    logic [7:0]       p4_co;
    logic [7:0]       p4_g;
    logic [7:0]       p4_b;

    always_ff @(posedge clk_pix) begin
        p4_sx <= p3_sx;
        p4_sy <= p3_sy;
        p4_de <= p3_de;
        p4_vsync <= p3_vsync;
        p4_hsync <= p3_hsync;

        p4_co <= p3_co;
        p4_g <= $signed(p3_cg) + $signed(p3_tmp);
        p4_b <= $signed(p3_tmp) - $signed({p3_co[7], p3_co[7:1]});
    end

    ////////////////////////////////////////////////////////////////
    // Pix cycle p5: Calculate r from co, b
    ////////////////////////////////////////////////////////////////

    logic [CORDW-1:0] p5_sx;
    logic [CORDW-1:0] p5_sy;
    logic             p5_de;
    logic             p5_vsync;
    logic             p5_hsync;
    logic [7:0]       p5_r;
    logic [7:0]       p5_g;
    logic [7:0]       p5_b;

    always_ff @(posedge clk_pix) begin
        p5_sx <= p4_sx;
        p5_sy <= p4_sy;
        p5_de <= p4_de;
        p5_vsync <= p4_vsync;
        p5_hsync <= p4_hsync;

        p5_r <= $signed(p4_b) + $signed(p4_co);
        p5_g <= p4_g;
        p5_b <= p4_b;
    end

    ////////////////////////////////////////////////////////////////
    // Pix cycle p6: Clamp r, g, b to 7 bits
    ////////////////////////////////////////////////////////////////

    logic [CORDW-1:0] p6_sx;
    logic [CORDW-1:0] p6_sy;
    logic             p6_de;
    logic             p6_vsync;
    logic             p6_hsync;
    logic [7:0]       p6_r;
    logic [7:0]       p6_g;
    logic [7:0]       p6_b;

    always_ff @(posedge clk_pix) begin
        p6_sx <= p5_sx;
        p6_sy <= p5_sy;
        p6_de <= p5_de;
        p6_vsync <= p5_vsync;
        p6_hsync <= p5_hsync;

        p6_r <= (($signed(p5_r) < $signed(8'h0)) ? 8'h0 : ($signed(p5_r) > $signed(8'h7f)) ? 8'h7f : p5_r) << 1;
        p6_g <= (($signed(p5_g) < $signed(8'h0)) ? 8'h0 : ($signed(p5_g) > $signed(8'h7f)) ? 8'h7f : p5_g) << 1;
        p6_b <= (($signed(p5_b) < $signed(8'h0)) ? 8'h0 : ($signed(p5_b) > $signed(8'h7f)) ? 8'h7f : p5_b) << 1;
    end

    ////////////////////////////////////////////////////////////////
    // Pix cycle p7: Output to screen
    ////////////////////////////////////////////////////////////////


    always_ff @(posedge clk_pix) begin
        sx <= p6_sx;
        sy <= p6_sy;
        de <= p6_de;
        vsync <= p6_vsync;
        hsync <= p6_hsync;

        r <= p6_de ? p6_r : 8'h0;
        g <= p6_de ? p6_g : 8'h0;
        b <= p6_de ? p6_b : 8'h0;
    end

endmodule
