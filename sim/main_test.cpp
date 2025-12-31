// Project F: FPGA Graphics - Colour Test Verilator C++
// (C)2023 Will Green, open source software released under the MIT License
// Learn more at https://projectf.io/posts/fpga-graphics/
// Modified by (C) 2023 Ryan "rj45" Sanche, MIT License

#include <stdio.h>
#include <SDL.h>
#include <verilated.h>
#include "Vtop_test.h"
#include "sdram.h"

// screen dimensions
const int H_RES = 1280;
const int V_RES = 720;

typedef struct Pixel {  // for SDL texture
    uint8_t a;  // transparency
    uint8_t b;  // blue
    uint8_t g;  // green
    uint8_t r;  // red
} Pixel;

int main(int argc, char* argv[]) {
    Verilated::commandArgs(argc, argv);

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        printf("SDL init failed.\n");
        return 1;
    }

    Pixel screenbuffer[H_RES*V_RES];

    SDL_Window*   sdl_window   = NULL;
    SDL_Renderer* sdl_renderer = NULL;
    SDL_Texture*  sdl_texture  = NULL;

    sdl_window = SDL_CreateWindow("VDP Sim", SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED, H_RES, V_RES, SDL_WINDOW_SHOWN);
    if (!sdl_window) {
        printf("Window creation failed: %s\n", SDL_GetError());
        return 1;
    }

    sdl_renderer = SDL_CreateRenderer(sdl_window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!sdl_renderer) {
        printf("Renderer creation failed: %s\n", SDL_GetError());
        return 1;
    }

    sdl_texture = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_RGBA8888,
        SDL_TEXTUREACCESS_TARGET, H_RES, V_RES);
    if (!sdl_texture) {
        printf("Texture creation failed: %s\n", SDL_GetError());
        return 1;
    }

    // reference SDL keyboard state array: https://wiki.libsdl.org/SDL_GetKeyboardState
    const Uint8 *keyb_state = SDL_GetKeyboardState(NULL);

    printf("Simulation running. Press 'Q' in simulation window to quit.\n\n");

    // initialize Verilog module
    Vtop_test* top = new Vtop_test;

    // 32MB SDRAM
    SDRAM* sdram = new SDRAM(13, 9, FLAG_DATA_WIDTH_16 | FLAG_BANK_INTERLEAVING, "sdram_log.txt");

    // reset
    top->sim_rst = 1;
    top->clk_pix = 0;
    top->eval();
    top->clk_pix = 1;
    top->eval();
    top->clk_pix = 0;
    top->eval();
    top->clk_pix = 1;
    top->eval();
    top->sim_rst = 0;
    top->clk_pix = 0;
    top->eval();

    // initialize frame rate
    uint64_t start_ticks = SDL_GetPerformanceCounter();
    uint64_t frame_count = 0;
    uint64_t ts = 0;
    uint64_t sdram_d_out;

    // main loop
    while (1) {
        // cycle the clock
        top->clk_pix = 1;
        ts += 8334;  // 60 MHz / 2 in picoseconds
        top->eval();
        sdram->eval(ts,
            // clock
            top->sdram_clk, top->sdram_cke,
            // command signals
            top->sdram_csn, top->sdram_rasn, top->sdram_casn, top->sdram_wen,
            // address
            top->sdram_ba, top->sdram_a,
            // data
            top->sdram_dqm, top->sdram_d, sdram_d_out);
        top->sdram_d = (SData)sdram_d_out;
        ts += 8334;  // 60 MHz / 2 in picoseconds
        top->clk_pix = 0;
        top->eval();
        sdram->eval(ts,
            // clock
            top->sdram_clk, top->sdram_cke,
            // command signals
            top->sdram_csn, top->sdram_rasn, top->sdram_casn, top->sdram_wen,
            // address
            top->sdram_ba, top->sdram_a,
            // data
            top->sdram_dqm, top->sdram_d, sdram_d_out);
        top->sdram_d = (SData)sdram_d_out;

        // update pixel if not in blanking interval
        if (top->sdl_de) {
            Pixel* p = &screenbuffer[top->sdl_sy*H_RES + top->sdl_sx];
            p->a = 0xFF;  // transparency
            p->b = top->sdl_b;
            p->g = top->sdl_g;
            p->r = top->sdl_r;
        }

        // update texture once per frame (in blanking)
        if (top->sdl_sy == V_RES && top->sdl_sx == 0) {
            // check for quit event
            SDL_Event e;
            bool quit = false;
            while (SDL_PollEvent(&e)) {
                if (e.type == SDL_QUIT) {
                    quit = true;
                }
                if (keyb_state[SDL_SCANCODE_Q]) quit = true;  // quit if user presses 'Q'
            }
            if (quit) break;

            SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, H_RES*sizeof(Pixel));
            SDL_RenderClear(sdl_renderer);
            SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL);
            SDL_RenderPresent(sdl_renderer);
            frame_count++;
        }
    }

    // calculate frame rate
    uint64_t end_ticks = SDL_GetPerformanceCounter();
    double duration = ((double)(end_ticks-start_ticks))/SDL_GetPerformanceFrequency();
    double fps = (double)frame_count/duration;
    printf("Frames per second: %.1f\n", fps);

    delete sdram;
    top->final();  // simulation done

    SDL_DestroyTexture(sdl_texture);
    SDL_DestroyRenderer(sdl_renderer);
    SDL_DestroyWindow(sdl_window);
    SDL_Quit();
    return 0;
}
