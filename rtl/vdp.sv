// (C) 2025 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps

`include "sprite_types.sv"

module vdp #(parameter CORDW=11) ( // coordinate width
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
    output logic [7:0] b,           // 8-bit blue

    // SDRAM
    output      logic        sdram_clk,
    output      logic        sdram_cke,
    output      logic        sdram_csn,
    output      logic        sdram_wen,
    output      logic        sdram_rasn,
    output      logic        sdram_casn,
    output      logic [12:0] sdram_a,
    output      logic [1:0]  sdram_ba,
    output      logic [1:0]  sdram_dqm,
    inout       logic [15:0] sdram_d
);
    ////////////////////////////////////////////////////////////////
    // SDRAM controller
    ////////////////////////////////////////////////////////////////

    logic [22:0] ram_addr;
    logic [31:0] ram_data;
    logic        ram_we;
    logic        ram_req;
    logic        ram_ack;
    logic        ram_valid;
    logic [31:0] ram_q;

    assign sdram_clk = clk_draw; // SDRAM clock runs at draw clock speed

    sdram sdram_inst (
        .reset(rst_draw),
        .clk(clk_draw),
        .addr(ram_addr),
        .data(ram_data),
        .we(ram_we),
        .req(ram_req),
        .ack(ram_ack),
        .valid(ram_valid),
        .q(ram_q),

        .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_csn),
        .sdram_we_n(sdram_wen),
        .sdram_ras_n(sdram_rasn),
        .sdram_cas_n(sdram_casn),
        .sdram_a(sdram_a),
        .sdram_ba(sdram_ba),
        .sdram_dqml(sdram_dqm[0]),
        .sdram_dqmh(sdram_dqm[1]),
        .sdram_dq(sdram_d)
    );


    //////////////////////////////////////////////////////////////////////
    // Pix cycle p0 / Draw cycle d0: Generate the VGA signals
    //////////////////////////////////////////////////////////////////////

    logic             x0_line;
    logic             x0_frame;
    logic [CORDW-1:0] x0_sx;
    logic [CORDW-1:0] x0_sy;
    logic [CORDW-1:0] x0_sy_plus1;
    logic [CORDW-1:0] x0_sy_plus2;
    logic             x0_de;
    logic             x0_vsync;
    logic             x0_hsync;

    // display sync signals and coordinates
    vga #(CORDW) vga_inst (
        .clk_pix,
        .rst_pix,
        .sx(x0_sx),
        .sy(x0_sy),
        .sy_plus1(x0_sy_plus1),
        .sy_plus2(x0_sy_plus2),
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


    // CDC of de from pix clock to draw clock
    logic d0_de;
    cdc_pulse_synchronizer_2phase de_cdc (
        .sending_clock(clk_pix),
        .sending_pulse_in(x0_de),
        // verilator lint_off PINCONNECTEMPTY
        // .sending_ready(),
        // verilator lint_on PINCONNECTEMPTY

        .receiving_clock(clk_draw),
        .receiving_pulse_out(d0_de)
    );

    // CDC from pix clock to draw clock -- part 1
    // this isn't entirely required, since d0_line is already synchronized
    // and y should be stable by the time the pulse goes through CDC
    logic [CORDW-1:0] d0x0_sy;
    logic [CORDW-1:0] d0x0_sy_plus1;
    logic [CORDW-1:0] d0x0_sy_plus2;
    logic [CORDW-1:0] d0x0_sx;
    always_ff @(posedge clk_draw) begin
        d0x0_sy <= x0_sy;
        d0x0_sy_plus1 <= x0_sy_plus1;
        d0x0_sy_plus2 <= x0_sy_plus2;
        d0x0_sx <= x0_sx;
    end


    // CDC from pix clock to draw clock -- part 2
    logic [CORDW-1:0] d0_sy;
    logic [CORDW-1:0] d0_sy_plus1;
    logic [CORDW-1:0] d0_sy_plus2;
    logic [CORDW-1:0] d0_sx;
    always_ff @(posedge clk_draw) begin
        // y should only increment on line going high
        if (d0_line) begin
            d0_sy <= d0x0_sy;
            d0_sy_plus1 <= d0x0_sy_plus1;
            d0_sy_plus2 <= d0x0_sy_plus2;
        end

        d0_sx <= d0x0_sx;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d1: Calculate addresses
    //////////////////////////////////////////////////////////////////////

    logic [11:0]      d1_frame_counter;
    logic [8:0]       d1_sprite_index;
    logic             d1_sprite_done;
    logic             d1_sprite_loading;
    logic             d1_sprite_loaded;

    logic [CORDW-1:0] d1_sy_plus1;
    logic [CORDW-1:0] d1_sy_plus2;
    logic             d1_line;
    logic             d1_bufsel;

    always_ff @(posedge clk_draw) begin
        if (d0_frame) d1_frame_counter <= d1_frame_counter + 1;

        if (d0_line) begin
            d1_sprite_index <= 9'h0;
        end else begin
            if (d1_sprite_done && d1_sprite_index < 9'h1ff) begin
                d1_sprite_index <= d1_sprite_index + 1;
                d1_sprite_loading <= 1'b1;
            end else begin
                d1_sprite_loading <= 1'b0;
            end
        end

        d1_line <= d0_line;
        d1_bufsel <= d0_sy_plus1[0];
        d1_sy_plus1 <= d0_sy_plus1;
        d1_sy_plus2 <= d0_sy_plus2;
        d1_sprite_loaded <= d1_sprite_loading;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d2: Load the sprite data from the sprite BRAM
    //////////////////////////////////////////////////////////////////////

    logic [11:0]          d2_lb_x;
    logic [11:0]          d2_sprite_x;

    logic                 d2_sprite_valid;
    active_tilemap_addr_t d2_tilemap_addr;
    active_bitmap_addr_t  d2_bitmap_addr;

    logic                 d2_line;
    logic                 d2_bufsel;

    sprite_matcher sprite_matcher_inst (
        .clk_draw(clk_draw),
        .rst_draw(rst_draw),
        .enable(1'b1), // TODO: hook this to ~vblank
        .line(d1_line),
        .sy_plus2(d1_sy_plus2),
        .sprite_index(d1_sprite_index),

        .valid(d2_sprite_valid),
        .tilemap_addr(d2_tilemap_addr),
        .bitmap_addr(d2_bitmap_addr)
    );

    always_ff @(posedge clk_draw) begin
        if (d1_line) begin
            d2_sprite_x <= 0;
            d2_lb_x <= 12'hfff; // draw off screen for this cycle while sprite loads
            d1_sprite_done <= 1'b0;
        end else if (d2_line) begin // delayed by a clock to allow d2_bitmap_addr to load
            d2_sprite_x <= 0;
            d2_lb_x <= d2_bitmap_addr.lb_addr;
            d1_sprite_done <= 1'b0;
        end else if (d1_sprite_loaded) begin
            d1_sprite_done <= 1'b0;
            d2_sprite_x <= 0;
            d2_lb_x <= d2_bitmap_addr.lb_addr;
        end else if (d2_sprite_valid && d1_sprite_index < 9'h1ff && d2_sprite_x == {3'd0, d2_tilemap_addr.tile_count, 1'd0}) begin
            d1_sprite_done <= 1'b1;
            d2_sprite_x <= 0;
            d2_lb_x <= 12'hfe0; // draw off screen
        end else if (d2_sprite_valid) begin
            d1_sprite_done <= 1'b0;
            d2_sprite_x <= d2_sprite_x + 1;
            d2_lb_x <= d2_lb_x + 8;
        end else begin
            d1_sprite_done <= 1'b0;
        end

        d2_line <= d1_line;
        d2_bufsel <= d1_bufsel;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d3: Load the tile map data from the tile map BRAM
    //////////////////////////////////////////////////////////////////////

    logic [11:0]  d3_lb_x;
    logic [15:0]  d3_tilemap_data;
    logic         d3_line;
    logic         d3_bufsel;

    tile_map_bram #("tile_map.hex") tile_map_inst (
        .clk_draw(clk_draw),

        .tilemap_addr(d2_tilemap_addr.tilemap_addr[9:0] + d2_sprite_x[10:1]),

        .tilemap_data(d3_tilemap_data)
    );

    always_ff @(posedge clk_draw) begin
        d3_lb_x <= d2_lb_x;
        d3_line <= d2_line;
        d3_bufsel <= d2_bufsel;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d4: Load the pixel data from the tile BRAM
    //////////////////////////////////////////////////////////////////////

    logic [15:0]  d4_tile_data;
    logic [35:0]  d4_tile_pixels;
    logic [3:0]   d4_tile_valid_mask = 4'b1111;
    logic [11:0]  d4_lb_x;
    logic         d4_line;
    logic         d4_bufsel;
    logic [4:0]   d4_palette_index;

    tile_bram #("tiles.hex") tile_inst (
        .clk_draw(clk_draw),
        // FIXME: the ~d2_sprite_x[0] is a temporary hack to fix a timing issue elsewhere
        .tile_addr(d2_bitmap_addr.tile_bitmap_addr[13:0] + {5'd0, d3_tilemap_data[7:0], 1'd0} + {13'd0, ~d2_sprite_x[0]}),

        .tile_data(d4_tile_data)
    );

    always_comb begin
        d4_tile_pixels = {
            d4_palette_index, d4_tile_data[3:0],
            d4_palette_index, d4_tile_data[7:4],
            d4_palette_index, d4_tile_data[11:8],
            d4_palette_index, d4_tile_data[15:12]
        };
    end

    always_ff @(posedge clk_draw) begin
        d4_lb_x <= d3_lb_x;
        d4_line <= d3_line;
        d4_bufsel <= d3_bufsel;
        d4_palette_index <= d3_tilemap_data[14:10];
    end


    //////////////////////////////////////////////////////////////////////
    // Draw cycle d5: Double the pixels
    //////////////////////////////////////////////////////////////////////

    logic [8:0]   d5_lb_addr_draw;
    logic [143:0] d5_unaligned_pixels;
    logic [15:0]  d5_unaligned_valid_mask;
    logic [2:0]   d5_alignment_shift;
    logic         d5_line;
    logic         d5_bufsel;

    pixel_doubler double_inst (
        .clk_draw,
        .rst_draw(d4_line),

        .tile_pixels(d4_tile_pixels),
        .tile_valid_mask(d4_tile_valid_mask),
        .lb_x(d4_lb_x),

        .lb_addr(d5_lb_addr_draw),
        .unaligned_pixels(d5_unaligned_pixels),
        .unaligned_valid_mask(d5_unaligned_valid_mask),
        .alignment_shift(d5_alignment_shift)
    );

    always_ff @(posedge clk_draw) begin
        d5_line <= d4_line;
        d5_bufsel <= d4_bufsel;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d6: Shift align the pixels
    //////////////////////////////////////////////////////////////////////

    logic [71:0]  d6_lb_colour_draw;
    logic [7:0]   d6_lb_mask_draw;
    logic [8:0]   d6_lb_addr_draw;
    logic         d6_bufsel;

    shift_aligner shifter_inst (
        .clk_draw,
        .rst_draw(d5_line),

        .unaligned_pixels(d5_unaligned_pixels),
        .unaligned_valid_mask(d5_unaligned_valid_mask),
        .alignment_shift(d5_alignment_shift),

        .aligned_pixels(d6_lb_colour_draw),
        .aligned_valid_mask(d6_lb_mask_draw)
    );

    always_ff @(posedge clk_draw) begin
        d6_lb_addr_draw <= d5_lb_addr_draw;
        d6_bufsel <= d5_bufsel;
    end

    logic  [8:0]   d0_clear_addr;
    logic          d0_clearing;

    // only clear once there's no chance that the line buffer is being sent to the screen
    assign d0_clearing = d0_sx >= (1280 - 1280 / 8); // TODO: parameterize 1280

    always_ff @(posedge clk_draw) begin
        if (~d0_clearing) begin
            d0_clear_addr <= 9'd0;
        end else begin
            d0_clear_addr <= d0_clear_addr + 9'd1;
        end
    end

    ////////////////////////////////////////////////////////////////
    // Draw cycle d7: Write to the line buffer
    // Pix cycle p1: Read the line buffer
    ////////////////////////////////////////////////////////////////

    logic [8:0]       p1_colour_pix;
    logic [CORDW-1:0] p1_sx;
    logic [CORDW-1:0] p1_sy;
    logic             p1_de;
    logic             p1_vsync;
    logic             p1_hsync;

    double_buffer lb_inst (
        .clk_pix,
        .clk_draw,

        .buffsel_pix(x0_sy[0]),
        .buffsel_draw(d6_bufsel),

        .addr_on_pix({1'd0,x0_sx}),
        .colour_on_pix(p1_colour_pix),

        .addr_on_draw(d0_clear_addr), // for now
        .we_on_draw(d0_clearing), // for now
        .colour_on_draw(72'd0), // for now

        .addr_off_draw(d6_lb_addr_draw),
        .we_off_draw(d6_lb_mask_draw),
        .colour_off_draw(d6_lb_colour_draw)
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
