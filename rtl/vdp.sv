// (C) 2026 Ryan "rj45" Sanche, MIT License

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

    // verilator lint_off UNDRIVEN
    // verilator lint_off UNUSEDSIGNAL
    logic [22:0] ram_addr;
    logic [31:0] ram_data;
    logic        ram_we;
    logic        ram_req;
    logic        ram_ack;
    logic        ram_valid;
    logic [31:0] ram_q;
    // verilator lint_on UNDRIVEN
    // verilator lint_on UNUSEDSIGNAL

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
    // verilator lint_off UNUSEDSIGNAL
    logic             x0_frame;
    // verilator lint_on UNUSEDSIGNAL
    logic [CORDW-1:0] x0_sx;
    logic [CORDW-1:0] x0_sy;
    // verilator lint_off UNUSEDSIGNAL
    logic [CORDW-1:0] x0_sy_plus1;
    // verilator lint_on UNUSEDSIGNAL
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

    // CDC from pix clock to draw clock -- part 1
    // this isn't entirely required, since d0_line is already synchronized
    // and y should be stable by the time the pulse goes through CDC
    logic [CORDW-1:0] d0x0_sy_plus2;
    logic [CORDW-1:0] d0x0_sx;
    logic             d0x0_bufsel;
    always_ff @(posedge clk_draw) begin
        d0x0_bufsel <= x0_sy_plus1[0];
        d0x0_sy_plus2 <= x0_sy_plus2;
        d0x0_sx <= x0_sx;
    end


    // CDC from pix clock to draw clock -- part 2
    logic [CORDW-1:0] d0_sy_plus2;
    logic [CORDW-1:0] d0_sx;
    logic             d0_bufsel;
    always_ff @(posedge clk_draw) begin
        // y should only increment on line going high
        if (d0_line) begin
            d0_sy_plus2 <= d0x0_sy_plus2;
            d0_bufsel <= d0x0_bufsel;
        end

        d0_sx <= d0x0_sx;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d1: Calculate addresses
    //////////////////////////////////////////////////////////////////////

    logic [CORDW-1:0] d1_sy_plus2;
    logic             d1_line;
    logic             d1_bufsel;


    always_ff @(posedge clk_draw) begin
        d1_line <= d0_line;
        d1_bufsel <= d0_bufsel;
        d1_sy_plus2 <= d0_sy_plus2;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d2: Load the sprite data from the sprite BRAM
    //////////////////////////////////////////////////////////////////////

    logic [11:0]          d2_lb_x;
    logic [10:0]          d2_sprite_x;
    logic [8:0]           d2_sprite_index;

    logic                 d2_sprite_ready;
    logic                 d2_sprite_valid;
    // verilator lint_off UNUSEDSIGNAL
    active_tilemap_addr_t d2_tilemap_addr;
    active_bitmap_addr_t  d2_bitmap_addr;
    // verilator lint_on UNUSEDSIGNAL
    logic [8:0]           d2_sprite_count;

    logic                 d2_line;
    logic                 d2_bufsel;

    sprite_matcher sprite_matcher_inst (
        .clk_draw(clk_draw),
        .rst_draw(rst_draw),
        .enable(1'b1), // TODO: hook this to ~vblank
        .line(d1_line),
        .sy_plus2(d1_sy_plus2),
        .sprite_index(d2_sprite_index),

        .valid(d2_sprite_ready),
        .tilemap_addr(d2_tilemap_addr),
        .bitmap_addr(d2_bitmap_addr),
        .sprite_count(d2_sprite_count)
    );

    sprite_controller sprite_controller_inst (
        .clk(clk_draw),
        .rst(rst_draw),
        .line(d1_line),

        .sprite_count(d2_sprite_count),
        .lb_addr(d2_bitmap_addr.lb_addr),
        .sprite_width(d2_tilemap_addr.tile_count),

        .sprite_ready(d2_sprite_ready),
        .sprite_valid(d2_sprite_valid),

        .sprite_index(d2_sprite_index),
        .lb_x(d2_lb_x),
        .sprite_x(d2_sprite_x)
    );

    always_ff @(posedge clk_draw) begin
        d2_line <= d1_line;
        d2_bufsel <= d1_bufsel;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d3: Load the tile map data from the tile map BRAM
    //////////////////////////////////////////////////////////////////////

    logic [11:0]  d3_lb_x;
    // verilator lint_off UNUSEDSIGNAL
    logic [15:0]  d3_tilemap_data; // bit 15 currently unused, remove lint_off when fixed
    // verilator lint_on UNUSEDSIGNAL
    logic         d3_line;
    logic         d3_bufsel;
    logic         d3_tile_half;
    logic [13:0]  d3_tile_bitmap_addr;
    logic         d3_sprite_valid;

    tile_map_bram #("tile_map.hex") tile_map_inst (
        .clk_draw(clk_draw),

        .tilemap_addr(d2_tilemap_addr.tilemap_addr[9:0] + d2_sprite_x[10:1]),

        .tilemap_data(d3_tilemap_data)
    );

    always_ff @(posedge clk_draw) begin
        d3_tile_half <= d2_sprite_x[0];
        d3_lb_x <= d2_lb_x;
        d3_line <= d2_line;
        d3_bufsel <= d2_bufsel;
        d3_tile_bitmap_addr <= d2_bitmap_addr.tile_bitmap_addr[13:0];
        d3_sprite_valid <= d2_sprite_valid;
    end

    //////////////////////////////////////////////////////////////////////
    // Draw cycle d4: Load the pixel data from the tile BRAM
    //////////////////////////////////////////////////////////////////////

    logic [15:0]  d4_tile_data;
    logic [35:0]  d4_tile_pixels;
    logic [3:0]   d4_tile_valid_mask;
    logic [11:0]  d4_lb_x;
    logic         d4_line;
    logic         d4_bufsel;
    logic [4:0]   d4_palette_index;

    tile_bram #("tiles.hex") tile_inst (
        .clk_draw(clk_draw),

        .tile_addr(d3_tile_bitmap_addr + {3'd0, d3_tilemap_data[9:0], d3_tile_half}),

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
        d4_tile_valid_mask <= {4{d3_sprite_valid}};
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

    logic [8:0]       lb_colour_pix;

    double_buffer lb_inst (
        .clk_pix,
        .clk_draw,

        .buffsel_pix(x0_sy[0]),
        .buffsel_draw(d6_bufsel),

        .addr_on_pix({1'd0,x0_sx}),
        .colour_on_pix(lb_colour_pix),

        .addr_on_draw(d0_clear_addr), // for now
        .we_on_draw(d0_clearing), // for now
        .colour_on_draw(72'd0), // for now

        .addr_off_draw(d6_lb_addr_draw),
        .we_off_draw(d6_lb_mask_draw),
        .colour_off_draw(d6_lb_colour_draw)
    );

    ////////////////////////////////////////////////////////////////
    // Pix pipeline
    ////////////////////////////////////////////////////////////////

    pix_pipeline #(CORDW) pix_pipeline_inst (
        .clk_pix(clk_pix),
        // .rst_pix(rst_pix),

        .i_colour(lb_colour_pix),
        .i_sx(x0_sx),
        .i_sy(x0_sy),
        .i_de(x0_de),
        .i_vsync(x0_vsync),
        .i_hsync(x0_hsync),

        .o_sx(sx),
        .o_sy(sy),
        .o_de(de),
        .o_vsync(vsync),
        .o_hsync(hsync),
        .o_r(r),
        .o_g(g),
        .o_b(b)
    );

endmodule
