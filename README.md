# rjvdp

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
- [x] Tile maps
- [ ] Sprite sheets
- [ ] Sprites

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

## Contributing

**Contributions are welcome!**

- Please follow the existing style.
- Fork and submit a PR

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.
