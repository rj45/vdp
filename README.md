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

## How does it work?

It's a sprite engine where sprites are rectangles of a tile map. There are only sprites because sprites can be the size of a whole tile map, and with transparency masks, a sprite can also be a text buffer. Many sprites can be on screen at once (specs TBD, but expecting at least 100).

At a high level, sprites are drawn to a line buffer while at the same time a previous copy of the line buffer is being drawn to the screen. A line buffer is used instead of a frame buffer in order to save on memory, so every frame every sprite is redrawn to the line buffer.

Sprite metadata is stored in BRAM, and each scanline the sprite data is scanned by a simple state machine and any sprites on that scanline are queued in a fifo. This process can happen in parallel to the sprite drawing since it is stored in a separate memory.

Sprite sheets are simply tile maps. "Tile map" is perhaps a misnomer because it isn't made up of reusable tiles per se. The transparency masks are reusable tiles, but because SDRAM and QSPI devices are large and prefer to stream data rather than do random access, the tile pixels are simply a 4bpp bitmap that's 8 times larger than the tilemap in the X and Y directions.

Each 8x8 "tile" of the tile data can use one of 16 colors from one of 32 different palettes giving 512 colours total. The palette index for each tile is stored in the tilemap.

The tile map also references a transparency mask, which is a 8x8 pixel bit mask representing which pixels should be drawn. This is used with a zbuffer to prevent overdraw. Because the cached tile map data, zbuffer and the transparency mask tiles are all stored in BRAM, this process can be done in parallel to the reading of pixel data.

Pixels can be drawn to the line buffer at 4 pixels per clock, which is convenient because 4 pixels is 16 bits of tile data, and the SDRAM is 16 bits wide. Because the line buffer is double buffered, and a different buffer is currently being drawn to the screen, then all the cycles of the scan line (including blanking time) can be used to draw into the buffer. This allows many sprites to be drawn per line.

Transparency masks can also be loaded with font data to allow a text mode. It is planned that tile maps and transparency masks can also be configured to be 16x8 pixels, allowing for a 16x8 font. Text is drawn into the tilemap in the lower 8 bits of each 16 bit word, which will select
which transparency mask is used, and thus which character is drawn. The pixel data can be used
to add texture to the text. A sprite can be drawn behind the text sprite to give background colors. Foreground colors can be selected by changing the palette index in the upper 8 bits of the tilemap.

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
