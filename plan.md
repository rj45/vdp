# VDP Pipeline Refactoring Plan

## Design Decisions

- **Plain signals** for valid/ready (not SystemVerilog interfaces) - max tool compatibility
- **Pix pipeline: simple extraction only** - no valid/ready needed (real-time HDMI can't stall)
- **Draw pipeline: full valid/ready with skid buffers** - needs backpressure for SDRAM/complex operations
- **Extract sprite controller** - separate control logic from datapath

---

## Current Architecture Summary

The VDP has two pipelines across two clock domains:

**Draw Pipeline (clk_draw):** d0 → d1 → d2 → d3 → d4 → d5 → d6 → d7
- d0: CDC and coordinate capture
- d1: Sprite index control
- d2: Sprite matching (sprite_matcher module)
- d3: Tilemap lookup (tile_map_bram)
- d4: Tile bitmap lookup (tile_bram)
- d5: Pixel doubling (pixel_doubler)
- d6: Shift alignment (shift_aligner)
- d7: Line buffer write (double_buffer)

**Pix Pipeline (clk_pix):** x0 → p1 → p1b → p2 → p3
- x0: VGA timing generation (vga module)
- p1: Line buffer read
- p1b: Extra register stage
- p2: Palette lookup (palette_bram)
- p3: Final output

**Current Issues:**
1. Signals threaded manually through stages (error-prone)
2. No backpressure - if a stage stalls, data is lost
3. Control logic mixed with data path in vdp.sv
4. Timing bugs noted in comments (e.g., line 301-302)

---

## Target Architecture

### 1. Standard Valid/Ready Interface

Each pipeline stage will use a standard handshaking protocol with plain signals:

```systemverilog
// Producer → Consumer handshake
// - valid: Producer has data ready
// - ready: Consumer can accept data
// - Transfer occurs when valid && ready

// Naming convention for stage N:
//   stageN_data   - payload going downstream
//   stageN_valid  - data is valid
//   stageN_ready  - downstream can accept (comes from stage N+1)
```

**Timing diagram:**
```
clk      ___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___
valid    ___/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_______________
ready    ‾‾‾‾‾‾‾\___________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
data     ===<  A  ><  B  >==================
              ↑       ↑
              |       transfer (valid && ready)
              held (valid && !ready)
```

### 2. Skid Buffer

A skid buffer allows a stage to accept one item even when downstream is stalled:

```systemverilog
module skid_buffer #(
    parameter WIDTH = 8
) (
    input  logic clk,
    input  logic rst,

    // Input side
    input  logic [WIDTH-1:0] in_data,
    input  logic             in_valid,
    output logic             in_ready,

    // Output side
    output logic [WIDTH-1:0] out_data,
    output logic             out_valid,
    input  logic             out_ready
);
    // Internal buffer for when downstream stalls
    logic [WIDTH-1:0] buffer;
    logic             buffered;

    // We can accept input when buffer is empty
    assign in_ready = !buffered;

    // Output is valid when we have buffered data OR input is valid
    assign out_valid = buffered || in_valid;
    assign out_data  = buffered ? buffer : in_data;

    always_ff @(posedge clk) begin
        if (rst) begin
            buffered <= 1'b0;
        end else begin
            if (buffered) begin
                // We have buffered data
                if (out_ready) begin
                    // Downstream accepted it
                    buffered <= 1'b0;
                end
            end else begin
                // No buffered data
                if (in_valid && !out_ready) begin
                    // Input valid but downstream stalled - buffer it
                    buffer   <= in_data;
                    buffered <= 1'b1;
                end
            end
        end
    end
endmodule
```

---

## Example: Wrapping tile_bram with Valid/Ready

Here's how to wrap an existing BRAM module:

**Before (current):**
```systemverilog
tile_bram tile_inst (
    .clk_draw,
    .tile_addr(some_addr),
    .tile_data(d4_tile_data)  // 1-cycle latency
);
```

**After (with handshaking):**
```systemverilog
module tile_bram_stage (
    input  logic        clk,
    input  logic        rst,

    // Input interface
    input  logic [13:0] in_addr,
    input  logic        in_valid,
    output logic        in_ready,

    // Output interface
    output logic [15:0] out_data,
    output logic        out_valid,
    input  logic        out_ready
);
    // The BRAM has 1-cycle latency
    logic [15:0] bram_data;
    logic        pending;  // We have a read in flight

    tile_bram tile_inst (
        .clk_draw(clk),
        .tile_addr(in_addr),
        .tile_data(bram_data)
    );

    // We can accept new input when:
    // 1. No read pending, OR
    // 2. Output will be consumed this cycle
    assign in_ready = !pending || out_ready;

    // Track pending reads
    always_ff @(posedge clk) begin
        if (rst) begin
            pending <= 1'b0;
        end else begin
            if (in_valid && in_ready) begin
                pending <= 1'b1;
            end else if (out_ready) begin
                pending <= 1'b0;
            end
        end
    end

    assign out_valid = pending;
    assign out_data  = bram_data;
endmodule
```

---

## Key Concepts Explained

### Why Valid/Ready?

The current pipeline has no backpressure. If any stage needs extra time (e.g., waiting for SDRAM), data flows through anyway and gets corrupted. Valid/ready solves this:

- **valid**: "I have data for you"
- **ready**: "I can accept data"
- **Transfer only when both are high**

### Why Skid Buffers?

Without a skid buffer, when downstream deasserts ready, the upstream must immediately stop. This creates a combinational path from output ready to input ready across all stages.

A skid buffer breaks this path by storing one item when downstream stalls:

```
         Without skid buffer:
         ready must propagate combinationally

         [Stage A] --valid--> [Stage B] --valid--> [Stage C]
         [Stage A] <--ready-- [Stage B] <--ready-- [Stage C]
                    ↑ combinational path ↑

         With skid buffer:
         ready is registered, no comb path

         [Stage A] --> [Skid] --> [Stage B] --> [Skid] --> [Stage C]
```

### Packed Structs for Pipeline Data

Instead of passing many individual signals through each stage:
```systemverilog
// Bad: easy to make mistakes
logic [10:0] d3_sx, d4_sx, d5_sx, d6_sx;
logic [10:0] d3_sy, d4_sy, d5_sy, d6_sy;
logic        d3_de, d4_de, d5_de, d6_de;
// ... many more
```

Use packed structs:
```systemverilog
// Good: single bundle
typedef struct packed {
    logic [10:0] sx;
    logic [10:0] sy;
    logic        de;
    // ... all fields
} stage_data_t;

stage_data_t d3_data, d4_data, d5_data, d6_data;
```

---

## Testing Strategy

Each step should be testable:

1. **Behavioral equivalence**: Run simulation before and after each change. Output should match.

2. **Formal verification**: SVA assertions can prove valid/ready protocols are correct.

3. **Incremental integration**: Test each stage wrapper individually before connecting.

4. **Waveform comparison**: Dump VCD files and compare key signals.

---

## Implementation Steps

### Step 1: Infrastructure (Safe, No Behavior Change)

**1.1 Create `rtl/pipeline_types.sv`**
```systemverilog
`default_nettype none

package pipeline_types;
    parameter CORDW = 11;

    // Sync signals passed through pix pipeline
    typedef struct packed {
        logic [CORDW-1:0] sx;
        logic [CORDW-1:0] sy;
        logic             de;
        logic             vsync;
        logic             hsync;
    } pix_sync_t;  // 25 bits

    // After linebuffer read (p1)
    typedef struct packed {
        pix_sync_t sync;
        logic [8:0] colour;  // palette index
    } pix_lb_t;  // 34 bits

    // After palette lookup (p2)
    typedef struct packed {
        pix_sync_t sync;
        logic [7:0] r;
        logic [7:0] g;
        logic [7:0] b;
    } pix_rgb_t;  // 49 bits

endpackage
```

**1.2 Create `rtl/skid_buffer.sv`**
(See skid buffer code in plan above)

**1.3 Create `rtl/skid_buffer_tb.sv`**
- Verify handshaking works correctly
- Test backpressure behavior
- Run with: `make test`

**Testing:** `make lint` should pass, `make sim` should still work

---

### Step 2: Extract Pix Pipeline (Simple Refactor)

The pix pipeline runs in real-time for HDMI output - it can't stall, so no valid/ready needed.
Just extract into a separate module for cleaner organization.

**2.1 Create `rtl/pix_pipeline.sv`**

Move p1/p1b/p2/p3 logic from vdp.sv:

```systemverilog
module pix_pipeline #(parameter CORDW=11) (
    input  logic clk_pix,
    input  logic rst_pix,

    // Input from linebuffer
    input  logic [8:0]       lb_colour,
    input  logic [CORDW-1:0] in_sx,
    input  logic [CORDW-1:0] in_sy,
    input  logic             in_de,
    input  logic             in_vsync,
    input  logic             in_hsync,

    // Output to HDMI
    output logic [CORDW-1:0] out_sx,
    output logic [CORDW-1:0] out_sy,
    output logic             out_de,
    output logic             out_vsync,
    output logic             out_hsync,
    output logic [7:0]       out_r,
    output logic [7:0]       out_g,
    output logic [7:0]       out_b
);
    // Internal pipeline registers (same structure as before)
    // p1 → p1b → p2 → p3 stages with palette_bram
endmodule
```

**2.2 Update `vdp.sv`**

Replace inline p1-p3 code with instantiation.

**Testing:** `make sim` - output should be identical

---

### Step 3: Create Draw Pipeline Types

Define packed structs for each draw pipeline stage's payload.

**3.1 Add draw types to `rtl/pipeline_types.sv`**

```systemverilog
// Import the existing sprite_types
`include "sprite_types.sv"

package pipeline_types;
    parameter CORDW = 11;

    //==========================================================
    // Draw Pipeline Structs
    //==========================================================

    // Common sync info passed through draw pipeline
    typedef struct packed {
        logic [CORDW-1:0] sy_plus1;   // 11 bits
        logic [CORDW-1:0] sy_plus2;   // 11 bits
        logic             bufsel;      // 1 bit
    } draw_sync_t;  // 23 bits

    // d1 → d2: Sprite command to process
    typedef struct packed {
        draw_sync_t       sync;
        logic [8:0]       sprite_index;
    } d1_payload_t;  // 32 bits

    // d2 → d3: Sprite matched, tilemap address ready
    typedef struct packed {
        draw_sync_t             sync;
        logic [11:0]            lb_x;           // line buffer X position
        logic [11:0]            sprite_x;       // X within sprite (for iteration)
        active_tilemap_addr_t   tilemap_addr;   // from sprite_types.sv
        active_bitmap_addr_t    bitmap_addr;    // from sprite_types.sv
    } d2_payload_t;

    // d3 → d4: Tilemap data loaded
    typedef struct packed {
        draw_sync_t       sync;
        logic [11:0]      lb_x;
        logic [11:0]      sprite_x;
        logic [15:0]      tilemap_data;     // tile index + palette
        active_bitmap_addr_t bitmap_addr;
    } d3_payload_t;

    // d4 → d5: Tile pixels loaded
    typedef struct packed {
        draw_sync_t       sync;
        logic [11:0]      lb_x;
        logic [35:0]      tile_pixels;      // 4 pixels × 9 bits
        logic [3:0]       tile_valid_mask;
    } d4_payload_t;

    // d5 → d6: Pixels doubled
    typedef struct packed {
        draw_sync_t       sync;
        logic [8:0]       lb_addr;          // line buffer byte address
        logic [143:0]     unaligned_pixels; // 16 pixels × 9 bits
        logic [15:0]      unaligned_valid_mask;
        logic [2:0]       alignment_shift;
    } d5_payload_t;

    // d6 → d7 (linebuffer): Aligned pixels ready to write
    typedef struct packed {
        logic [8:0]       lb_addr;
        logic [71:0]      lb_colour;        // 8 pixels × 9 bits
        logic [7:0]       lb_mask;          // per-pixel write enable
        logic             bufsel;
    } d6_payload_t;  // 90 bits

endpackage
```

**Testing:** `make lint` should pass

---

### Step 4: Extract Sprite Controller

Separate the sprite iteration control logic from the pipeline datapath.

**4.1 Create `rtl/sprite_controller.sv`**

```systemverilog
`default_nettype none

module sprite_controller (
    input  logic        clk,
    input  logic        rst,

    // Scanline synchronization
    input  logic        line_start,       // pulse at start of new line

    // Pipeline feedback
    input  logic        pipeline_ready,   // pipeline can accept new sprite
    input  logic        sprite_done,      // current sprite finished

    // Sprite command output
    output logic [8:0]  sprite_index,     // which sprite to process
    output logic        sprite_valid,     // sprite_index is valid
    output logic        sprites_complete  // all sprites for this line done
);
    // State: idle until line_start, then iterate through sprites
    typedef enum logic [1:0] {
        IDLE,
        LOADING,
        PROCESSING,
        DONE
    } state_t;

    state_t state;
    logic [8:0] index;

    assign sprite_index = index;
    assign sprite_valid = (state == LOADING);
    assign sprites_complete = (state == DONE);

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            index <= 9'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (line_start) begin
                        index <= 9'd0;
                        state <= LOADING;
                    end
                end

                LOADING: begin
                    if (pipeline_ready) begin
                        state <= PROCESSING;
                    end
                end

                PROCESSING: begin
                    if (sprite_done) begin
                        if (index < 9'h1ff) begin
                            index <= index + 1;
                            state <= LOADING;
                        end else begin
                            state <= DONE;
                        end
                    end
                end

                DONE: begin
                    if (line_start) begin
                        index <= 9'd0;
                        state <= LOADING;
                    end
                end
            endcase
        end
    end
endmodule
```

**4.2 Update vdp.sv to use sprite_controller**

Replace the inline d1 sprite iteration logic with instantiation.

**Testing:** `make sim` - same behavior

---

### Step 5: Extract Draw Pipeline Shell (No Handshaking Yet)

First extract the draw pipeline as-is, then add handshaking incrementally.

**5.1 Create `rtl/draw_pipeline.sv` with current behavior**

```systemverilog
`default_nettype none
`include "sprite_types.sv"

module draw_pipeline #(parameter CORDW=11) (
    input  logic        clk_draw,
    input  logic        rst_draw,

    // From sprite controller
    input  logic [8:0]  sprite_index,
    input  logic        sprite_load,

    // Sync info from CDC
    input  logic [CORDW-1:0] sy_plus1,
    input  logic [CORDW-1:0] sy_plus2,
    input  logic             line,

    // To sprite controller
    output logic        ready,            // can accept sprite_load
    output logic        sprite_done,      // finished current sprite

    // To double_buffer (linebuffer write port)
    output logic [8:0]  lb_addr,
    output logic [71:0] lb_data,
    output logic [7:0]  lb_we,
    output logic        lb_bufsel
);
    // Move d2-d7 stages here from vdp.sv
    // Keep existing implementation initially
endmodule
```

**5.2 Move stages d2-d7 from vdp.sv into draw_pipeline.sv**

Move these components:
- sprite_matcher instantiation
- tile_map_bram instantiation
- tile_bram instantiation
- pixel_doubler instantiation
- shift_aligner instantiation
- All the d2_*, d3_*, d4_*, d5_*, d6_* registers

**Testing:** `make sim` - identical output (pure refactor)

---

### Step 6: Add Valid/Ready to d2→d3 (First Handshake)

Start adding handshaking one stage at a time.

**6.1 Add valid/ready between sprite_matcher and tile_map_bram**

```systemverilog
// d2 output
logic d2_valid;
d2_payload_t d2_data;
logic d2_ready;  // from d3

// Pack d2 outputs into struct
assign d2_data.sync.sy_plus1 = d2_sy_plus1;
assign d2_data.sync.sy_plus2 = d2_sy_plus2;
assign d2_data.sync.bufsel = d2_bufsel;
assign d2_data.lb_x = d2_lb_x;
assign d2_data.sprite_x = d2_sprite_x;
assign d2_data.tilemap_addr = d2_tilemap_addr;
assign d2_data.bitmap_addr = d2_bitmap_addr;

// Valid when sprite_matcher has valid output
assign d2_valid = d2_sprite_valid;
```

**6.2 Add skid buffer between d2 and d3**

```systemverilog
d2_payload_t d2_skid_out;
logic d2_skid_valid, d2_skid_ready;

skid_buffer #(.WIDTH($bits(d2_payload_t))) d2_skid (
    .clk(clk_draw),
    .rst(rst_draw || line),  // reset on new line
    .in_data(d2_data),
    .in_valid(d2_valid),
    .in_ready(d2_ready),
    .out_data(d2_skid_out),
    .out_valid(d2_skid_valid),
    .out_ready(d2_skid_ready)
);
```

**6.3 Update tile_map_bram stage to use handshaking**

```systemverilog
// d3 accepts when it can forward to d4
assign d2_skid_ready = d3_ready;

// tilemap address from skid buffer output
assign tilemap_read_addr = d2_skid_out.tilemap_addr.tilemap_addr[9:0]
                         + d2_skid_out.sprite_x[10:1];
```

**Testing:** `make sim` - still works, now with first handshake point

---

### Step 7: Add Valid/Ready to d3→d4

**7.1 Pack d3 outputs into struct**

```systemverilog
logic d3_valid;
d3_payload_t d3_data;
logic d3_ready;

// d3 is valid one cycle after d2 (BRAM latency)
always_ff @(posedge clk_draw) begin
    if (rst_draw || line) begin
        d3_valid <= 1'b0;
    end else begin
        d3_valid <= d2_skid_valid && d2_skid_ready;
    end
end

assign d3_data.sync = d2_skid_out.sync;
assign d3_data.lb_x = d2_skid_out.lb_x;
assign d3_data.sprite_x = d2_skid_out.sprite_x;
assign d3_data.tilemap_data = tilemap_data_out;  // from BRAM
assign d3_data.bitmap_addr = d2_skid_out.bitmap_addr;
```

**7.2 Add skid buffer between d3 and d4**

Same pattern as d2→d3.

**Testing:** `make sim`

---

### Step 8: Add Valid/Ready to d4→d5

**8.1 Wrap tile_bram with valid/ready**

tile_bram has 1-cycle latency, need to track pending reads:

```systemverilog
logic d4_valid;
d4_payload_t d4_data;
logic d4_ready;

// Track pending BRAM read
logic tile_read_pending;
always_ff @(posedge clk_draw) begin
    if (rst_draw || line) begin
        tile_read_pending <= 1'b0;
    end else if (d3_skid_valid && d3_skid_ready) begin
        tile_read_pending <= 1'b1;
    end else if (d4_ready) begin
        tile_read_pending <= 1'b0;
    end
end

assign d4_valid = tile_read_pending;
```

**Testing:** `make sim`

---

### Step 9: Add Valid/Ready to d5→d6

**9.1 Wrap pixel_doubler with valid/ready**

pixel_doubler already produces output every cycle when fed valid input:

```systemverilog
logic d5_valid;
d5_payload_t d5_data;
logic d5_ready;

// pixel_doubler output is valid when d4 was valid
always_ff @(posedge clk_draw) begin
    d5_valid <= d4_skid_valid && d4_skid_ready;
end
```

**Testing:** `make sim`

---

### Step 10: Add Valid/Ready to d6→d7 (Linebuffer Write)

**10.1 Final stage writes to linebuffer**

```systemverilog
logic d6_valid;
d6_payload_t d6_data;

// Linebuffer always ready (no backpressure from buffer)
assign d5_skid_ready = 1'b1;

// Unpack for linebuffer write
assign lb_addr = d6_data.lb_addr;
assign lb_data = d6_data.lb_colour;
assign lb_we = d6_valid ? d6_data.lb_mask : 8'd0;
assign lb_bufsel = d6_data.bufsel;
```

**Testing:** `make sim` - full pipeline with handshaking complete

---

### Step 11: Cleanup and Assertions

**11.1 Simplify vdp.sv**

Final vdp.sv structure:
```systemverilog
module vdp (/* ports */);
    // VGA timing
    vga vga_inst (...);

    // CDC
    cdc_pulse_synchronizer_2phase line_cdc (...);
    cdc_pulse_synchronizer_2phase frame_cdc (...);

    // Sprite controller
    sprite_controller ctrl_inst (...);

    // Draw pipeline
    draw_pipeline draw_inst (...);

    // Double buffer
    double_buffer lb_inst (...);

    // Pix pipeline
    pix_pipeline pix_inst (...);

    // SDRAM
    sdram sdram_inst (...);
endmodule
```

**11.2 Add SVA assertions**

```systemverilog
// In skid_buffer.sv or separate file
`ifdef FORMAL
    // Valid must not change while waiting for ready
    property valid_stable;
        @(posedge clk) disable iff (rst)
        (in_valid && !in_ready) |=> $stable(in_data);
    endproperty
    assert property (valid_stable);
`endif
```

---

## Quick Reference: Files Changed

| Step | File | Action | Notes |
|------|------|--------|-------|
| 1 | `rtl/pipeline_types.sv` | Create | Draw pipeline struct definitions |
| 1 | `rtl/skid_buffer.sv` | Create | Reusable skid buffer |
| 1 | `rtl/skid_buffer_tb.sv` | Create | Unit test for skid buffer |
| 2 | `rtl/pix_pipeline.sv` | Create | Simple extraction (no valid/ready) |
| 2 | `rtl/vdp.sv` | Modify | Remove p1-p3 code |
| 3 | `rtl/pipeline_types.sv` | Modify | Add draw_sync_t, d2_payload_t, etc. |
| 4 | `rtl/sprite_controller.sv` | Create | Sprite iteration FSM |
| 4 | `rtl/vdp.sv` | Modify | Remove d1 inline logic |
| 5 | `rtl/draw_pipeline.sv` | Create | Move d2-d7 stages |
| 5 | `rtl/vdp.sv` | Modify | Remove d2-d7 inline logic |
| 6-10 | `rtl/draw_pipeline.sv` | Modify | Add valid/ready stage by stage |
| 11 | `rtl/vdp.sv` | Modify | Final cleanup |
| 11 | `Makefile` | Modify | Add new files to lint/test |
