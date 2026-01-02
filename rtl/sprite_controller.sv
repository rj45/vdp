// (C) 2026 Ryan "rj45" Sanche, MIT License

`default_nettype none
`timescale 1ns / 1ps


module sprite_controller (
    input  logic        clk,
    input  logic        rst,

    // Scanline synchronization
    input  logic        line,             // pulse at start of new line

    // Sprite parameters
    input  logic [8:0] sprite_count,     // number of sprites to process
    input  logic [11:0] lb_addr,          // initial linebuffer address for sprite
    input  logic [7:0]  sprite_width,     // width of each sprite in pixels

    // Pipeline feedback
    input  logic        sprite_ready,     // pipeline can accept new sprite

    // Sprite command output
    output logic [8:0]  sprite_index,     // which sprite to process
    output logic        sprite_valid,     // sprite_index is valid
    // output logic        sprites_complete, // all sprites for this line done
    output logic [11:0] lb_x,             // linebuffer x position for sprite data
    output logic [10:0] sprite_x          // current sprite x position
);
    // State: idle until line_start, then iterate through sprites
    typedef enum logic [1:0] {
        LOADING,
        LOADED,
        DRAWING,
        DONE
    } state_t;

    state_t state;
    logic [8:0] index;

    logic [10:0] sprite_end;

    assign sprite_index = index;
    // assign sprites_complete = (state == DONE);

    // TODO: replace this with `valid` signal
    localparam OFF_SCREEN = 12'hff8; // 8 pixels from end of linebuffer

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            index <= 9'd0;
            lb_x <= OFF_SCREEN;
            sprite_valid <= 1'b0;
            sprite_x <= 11'd0;
            state <= LOADING;
        end else if (line) begin
            index <= 9'd0;
            lb_x <= OFF_SCREEN;
            sprite_valid <= 1'b0;
            sprite_x <= 11'd0;
            state <= LOADING;
        end else begin
            case (state)
                LOADING: begin
                    lb_x <= OFF_SCREEN;
                    sprite_valid <= 1'b0;
                    if (sprite_ready) begin
                        state <= LOADED;
                    end
                end

                LOADED: begin
                    state <= DRAWING;
                    sprite_valid <= 1'b1;
                    lb_x <= lb_addr;
                    sprite_x <= 11'd0;
                    sprite_end <= {2'd0, sprite_width, 1'd0} - 1;
                end

                DRAWING: begin
                    if (sprite_x == sprite_end) begin
                        lb_x <= OFF_SCREEN;
                        sprite_valid <= 1'b0;

                        if (index < sprite_count) begin
                            index <= index + 1;
                            state <= LOADING;
                        end else begin
                            state <= DONE;
                        end
                    end else begin
                        sprite_valid <= 1'b1;
                        lb_x <= lb_x + 8;
                        sprite_x <= sprite_x + 1;
                    end
                end

                DONE: begin
                    lb_x <= OFF_SCREEN;
                    sprite_valid <= 1'b0;
                end
            endcase
        end
    end
endmodule
