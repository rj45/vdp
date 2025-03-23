// Written by GPT-4 with plain english prompts.... no idea how
// copyright works in that case.
//
// Gouldian_Finch_256x256.png is public domain photo by Bernard Spragg

#![feature(portable_simd)]

mod color;
mod imgconv;
use imgconv::{Config, ImageConverter};

/// Command line interface to make it easier to use different configurations
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();

    // If no arguments provided, run with default config
    if args.len() <= 1 {
        let config = Config::default();
        println!("Running with default configuration:");
        println!("Input: {}", config.input_file);
        println!("Output PNG: {}", config.output_png);
        println!("Tile size: {}x{}", config.tile_width, config.tile_height);
        println!(
            "Tilemap size: {}x{}",
            config.tilemap_width, config.tilemap_height
        );
        println!("Palettes: {}", config.num_palettes);
        println!("Colors per palette: {}", config.colors_per_palette);
        println!("Dithering: {}", if config.dithering { "on" } else { "off" });

        let converter = ImageConverter::new(config);
        converter.convert()?;
        return Ok(());
    }

    // Parse arguments and create custom config
    let mut config = Config::default();
    let mut i = 1;

    while i < args.len() {
        match args[i].as_str() {
            "-i" | "--input" => {
                i += 1;
                if i < args.len() {
                    config.input_file = args[i].clone();
                }
            }
            "-o" | "--output" => {
                i += 1;
                if i < args.len() {
                    config.output_png = args[i].clone();
                }
            }
            "--palette-hex" => {
                i += 1;
                if i < args.len() {
                    config.output_palette_hex = args[i].clone();
                }
            }
            "--tiles-hex" => {
                i += 1;
                if i < args.len() {
                    config.output_tiles_hex = args[i].clone();
                }
            }
            "--tilemap-hex" => {
                i += 1;
                if i < args.len() {
                    config.output_tilemap_hex = args[i].clone();
                }
            }
            "--json" => {
                i += 1;
                if i < args.len() {
                    config.output_json = Some(args[i].clone());
                }
            }
            "--tile-size" => {
                i += 1;
                if i < args.len() {
                    let parts: Vec<&str> = args[i].split('x').collect();
                    if parts.len() == 2 {
                        if let Ok(width) = parts[0].parse::<u32>() {
                            config.tile_width = width;
                        }
                        if let Ok(height) = parts[1].parse::<u32>() {
                            config.tile_height = height;
                        }
                    }
                }
            }
            "--tilemap-size" => {
                i += 1;
                if i < args.len() {
                    let parts: Vec<&str> = args[i].split('x').collect();
                    if parts.len() == 2 {
                        if let Ok(width) = parts[0].parse::<u32>() {
                            config.tilemap_width = width;
                        }
                        if let Ok(height) = parts[1].parse::<u32>() {
                            config.tilemap_height = height;
                        }
                    }
                }
            }
            "--palettes" => {
                i += 1;
                if i < args.len() {
                    if let Ok(num) = args[i].parse::<usize>() {
                        config.num_palettes = num;
                    }
                }
            }
            "--colors" => {
                i += 1;
                if i < args.len() {
                    if let Ok(num) = args[i].parse::<usize>() {
                        config.colors_per_palette = num.min(16);
                    }
                }
            }
            "--no-dither" => {
                config.dithering = false;
            }
            "--dither-factor" => {
                i += 1;
                if i < args.len() {
                    if let Ok(factor) = args[i].parse::<f32>() {
                        config.dither_factor = factor;
                    }
                }
            }
            "--help" => {
                println!("Image Converter - Converts images to tilemap format");
                println!();
                println!("Usage:");
                println!("  imgconv [options]");
                println!();
                println!("Options:");
                println!("  -i, --input FILE         Input image file (default: imgconv/Gouldian_Finch_256x256.png)");
                println!("  -o, --output FILE        Output PNG file (default: imgconv/out.png)");
                println!(
                    "  --palette-hex FILE       Output palette hex file (default: rtl/palette.hex)"
                );
                println!(
                    "  --tiles-hex FILE         Output tiles hex file (default: rtl/tiles.hex)"
                );
                println!("  --tilemap-hex FILE       Output tilemap hex file (default: rtl/tile_map.hex)");
                println!("  --json FILE              Output JSON file (optional)");
                println!("  --tile-size WIDTHxHEIGHT Tile size in pixels (default: 8x8)");
                println!(
                    "  --tilemap-size WIDTHxHEIGHT Tilemap dimensions in tiles (default: 32x32)"
                );
                println!("  --palettes NUM           Number of palettes to generate (default: 32)");
                println!("  --colors NUM             Max colors per palette, 1-16 (default: 16)");
                println!("  --no-dither              Disable dithering");
                println!(
                    "  --dither-factor FLOAT    Error scaling factor for dithering (default: 0.75)"
                );
                println!("  --help                   Show this help message");
                return Ok(());
            }
            _ => {
                println!("Unknown option: {}", args[i]);
                println!("Use --help for usage information.");
                return Ok(());
            }
        }
        i += 1;
    }

    println!("Running with custom configuration:");
    println!("Input: {}", config.input_file);
    println!("Output PNG: {}", config.output_png);
    println!("Tile size: {}x{}", config.tile_width, config.tile_height);
    println!(
        "Tilemap size: {}x{}",
        config.tilemap_width, config.tilemap_height
    );
    println!("Palettes: {}", config.num_palettes);
    println!("Colors per palette: {}", config.colors_per_palette);
    println!("Dithering: {}", if config.dithering { "on" } else { "off" });

    let converter = ImageConverter::new(config);
    converter.convert()?;
    Ok(())
}
