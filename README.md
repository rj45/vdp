# vdp

A retro-inspired VDP built in Verilog for FPGA.

## Description

This is a redo of the [rjvdp](https://github.com/rj45/rjvdp) project in System Verilog instead of using Digital.

This VDP is designed to work with the ULX3S dev board, but should work with any ECP5 board (such as the IceSugar Pro) with minimal effort.

The circuit is a retro inspired Video Display Processor (VDP), sometimes also known as a Video Display Unit (VDU), or Picture Processing Unit (PPU). It's designed to work similarly to a late 80s graphics system like in the Commodore 64 / Amiga, or the various Nintendo or Sega consoles of that era. It's especially inspired by the NeoGeo.

It's updated with new capabilities of modern hardware (specifically ECP5 FPGAs), and new limitations too. For example, SDRAM and QSPI flash/PSRAM devices are common and cheap, which requires some rethinking of how tile maps work.

### Status

- [x] Displays to screen
- [x] Palette lookups
- [x] Line buffer
- [x] Tile pixels
- [x] Tile maps / Sprite sheets
- [ ] Transparency masks
- [ ] zBuffer from transparency mask
- [ ] Sprites
- [ ] Read tile pixels from QSPI and/or SDRAM

## Building and Running

You will need the [OSS Cad Suite](https://github.com/YosysHQ/oss-cad-suite-build) and make with either WSL, linux, mac or other unix.

For the simulation, run `make -C sim run`.

For building the FPGA bitstreams, run `make`.

To program the ULX3S, run `make prog`.

### Image Conversion

There is also an image conversion utility in the [imgconv](./imgconv/) folder. You need
rust installed, and then you can `cargo run --release` (debug is quite slow).

See `cargo run --release -- --help` for more information on command line arguments.

This utility uses KMeans Clustering to convert the image to a sprite sheet (tile map) usable by the VDP.

## Terminology

- Tile: A 8x8 square of pixels
- Tile Data: A 16 bit value defining several attributes of a tile in a Tile Map.
- Tile Map: A 2D grid of cells, each cell being the Tile Data for a Tile.
- Texels: An 8x8 4bpp "texture" of a tile
- Ring Buffer: A memory (Block or Distributed RAM) with a head pointer and tail pointer, with the allocated memory between the tail and the head, and the free memory between the head and the tail. Both pointers wrap around to 0 when reaching the end. 

## How does it work?

The VDP is deeply pipelined and separated into two "timing domains" by a double buffered line buffer: the draw domain and the pixel domain. A line buffer is similar to a frame buffer except it's only one scan-line. For each scan-line sent to the monitor in the pixel domain, the line buffer gets flipped. For the entire duration of the line being drawn to the screen in the pixel domain, including the horizontal blanking, the draw domain gets to draw in the off-screen line buffer.

The pipeline of the pixel domain is to read a byte from the line buffer, look up its palette entry, and send the 24 bit color to the screen. Because the line buffer has two ports: a read port and a write port, the write port is used to zero out the line buffer after sending the data to the screen.

The pipeline of the draw domain is a lot more complex, and so could run at a different clock rate. There's two different "state machines" that operate in parallel in this pipeline:

There is the sprite scanner, which acts with a Y coordinate two lines ahead of the one being drawn. This state machine scans through each sprite looking for sprites that intersect the Y coordinate and that would be visible. When it finds one, it calculates the address ranges of the tilemap data for the visible portion to be loaded and copies the relevant sprite attributes into a separate double buffer that's flipped each line.

The other state machine scans through the sprite buffer one by one, "activating" each sprite by sending its data to the draw pipeline and waiting for the draw pipeline to finish before sending the next sprite to it.

For each tile in the activated sprite, the draw pipeline loads the tilemap entry, then twice it loads 4 4-bit "texels" of the tile data. The texels are combined with the palette entry from the tilemap data to form 9 bit pixels. The 9 bit pixels are then doubled from 4 to 8 pixels. The pixels are then "aligned" such that they can be written to the line buffer 8 pixels per cycle with a possible extra cycle required to clear the alignment buffer after the sprite finishes drawing. After alignment, the pixels are drawn up to 8 pixels per clock into the draw buffer at the specific offset.

There is 1360 pixel clocks per scan line (including blanking time). Four doubled pixels can be drawn per cycle. A tile is 8 pixels, so takes 2 cycles to draw. That means as much as 680 tiles can be drawn per line. However, that presumes large sprites since it takes an extra cycle between sprites. It also assumes the tilemap data can be read from a separate memory than the tile texel data. This also assumes the draw domain is clocked at the same clock rate as the pixel domain. If all 256 sprites are drawn on a single line, and the tilemap data and texel data are in the same memory, then it could be as low as 368 tiles per line. Even lower considering SDRAM latencies.

There is an idea for making this system more efficient: A one bit z-buffer line-buffer could be implemented, where the transparency masks are stored in a separate block RAM for fast access. Sprites would first be drawn into the z-buffer and only texels which are actually drawn would get loaded from memory and blitted to the line buffer. The draw pipeline would then be a series of fifos: the tilemap data would be read, the mask data it points to would be read 16 bits at a time, and any of the 8 texels matching would be fed into a fifo to have the texel data loaded and blitted to the line buffer in the relavent locations. Any sprites entirely occluded would not even have their texel data loaded. The mask could even be at the sub-pixel level allowing portions of the doubled pixels to be masked since 16 pixels can be loaded at once. However the zbuffer and masking system is a significant amount of extra complexity.

## Sprite algorithm

- For each Y+2 scanline:
    - Increment the active sprite ring buffer's tail by the count of active sprites in the previous scanline, freeing the memory
    - For each sprite:
        - Read the Y position of the sprite and the Y height.
        - If the sprite intersects the current scan line:
            - Read the X position of the sprite and X width. 
            - If the sprite intersects the screen in the X direction:
                - If the head of the "active sprites" ring buffer meets the tail of the ring buffer:
                    - Record the error in a register flag
                - Else:
                    - Write the sprite number in the "active sprites" list into a ring buffer at the head
                    - Increment a count of the number of sprites for this scanline
    - Save the count of sprites in the current scanline to a register for use next scan line
- For each Y+1 scanline:
    - Set the index for the active sprite ring buffer to the head minus the count of active sprites
    - For each active sprite in the active sprite ring buffer:
        - Open the tile data row in the SDRAM
        - Open the tile texel row in the SDRAM
        - For each tile in the active sprite's current row:
            - Read the tile data for the sprite
            - Read two words of pixel data for the sprite
            - Draw those two pixel data words on the line buffer
       
## Audio

There is the beginnings of audio from nockieboy's work here: 

https://github.com/nockieboy/YM2149_PSG_system/

I found a different implementation of the YM2149 PSG by Matthew Hagerty here: 

https://github.com/dnotq/ym2149_audio/ 

## Credits

This design is heavily inspired by the Neo Geo's VDP, with some ideas taken from the SNES and Gameboy PPUs.

## Contributing

**Contributions are welcome!**

- Please follow the existing style.
- Fork and submit a PR

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.
