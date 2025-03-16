// Written by GPT-4 with plain english prompts.... no idea how
// copyright works in that case.
//
// Gouldian_Finch_256x256_4b.png is public domain, photo by Bernard Spragg
// I used Gimp to scale, crop and reduce it to 15 colors

use image::{GenericImageView, Pixel};
use std::collections::HashMap;
use std::fs::File;
use std::io::Write;

fn main() {
    // Read the PNG file.
    let img = image::open("imgconv/Gouldian_Finch_256x256_4b.png").unwrap();

    // Set up the output files.
    let mut tile_map_file = File::create("rtl/tile_map.hex").unwrap();
    let mut tile_data_file = File::create("rtl/tiles.hex").unwrap();
    let mut palette_file = File::create("rtl/palette.hex").unwrap();

    // Set up the color palette.
    let mut color_palette: Vec<String> = Vec::new();

    // A buffer for storing the hex string to be written to the pixel file.
    let mut pixel_line = String::new();

    // Ensure the first palette entry is black.
    writeln!(&mut palette_file, "000000").unwrap();

    let tilemap_width = img.width() / 8;
    let tilemap_height = img.height() / 8;
    println!(
        "tilemap width: {}, height: {}",
        tilemap_width, tilemap_height,
    );

    // Image must be have a width and height that are multiples of the tile size
    assert!(img.width() % 8 == 0);
    assert!(img.height() % 8 == 0);

    let mut tiles: Vec<[u16; 16]> =
        Vec::with_capacity(tilemap_width as usize * tilemap_height as usize);
    for _ in 0..tilemap_width * tilemap_height {
        tiles.push([0; 16]);
    }

    // Loop through the pixels in the image and generate tiles.
    for (x, y, pixel) in img.pixels() {
        let tilemap_x = x / 8;
        let tilemap_y = y / 8;
        let tile_x = x % 8;
        let tile_y = y % 8;

        // Convert the pixel to rgba.
        let rgba = pixel.to_rgba();

        // Convert the RGB part to a hex string.
        let pixel_hex = hex::encode(&rgba.channels()[0..3]);

        // If the color is not already in the palette, add it.
        let color_index = match color_palette.iter().position(|x| *x == pixel_hex) {
            Some(index) => index,
            None => {
                let channels = rgba.channels();
                let (r, g, b) = (
                    (channels[0] >> 1) as i16,
                    (channels[1] >> 1) as i16,
                    (channels[2] >> 1) as i16,
                );

                let co = r.wrapping_sub(b);
                let tmp = b.wrapping_add(co >> 1);
                let cg = g.wrapping_sub(tmp);
                let y = tmp.wrapping_add(cg >> 1);

                let tmp = y.wrapping_sub(cg >> 1);
                let g2 = cg.wrapping_add(tmp);
                let b2 = tmp.wrapping_sub(co >> 1);
                let r2 = b2.wrapping_add(co);

                // Print the pixel values.
                println!(
                    "rgb({},{},{}) rgb2({},{},{}) co: {}, cg: {}, y: {}",
                    r, g, b, r2, g2, b2, co, cg, y
                );

                color_palette.push(pixel_hex.clone());

                let pixel_hex = hex::encode([y as u8, co as u8, cg as u8]);

                // Write the palette color to the file.
                writeln!(&mut palette_file, "{}", pixel_hex).unwrap();
                color_palette.len() - 1
            }
        };

        let tile = tiles
            .get_mut(tilemap_y as usize * tilemap_width as usize + tilemap_x as usize)
            .unwrap();
        let tile_index = (tile_y * 2 + tile_x / 4) as usize;
        tile[tile_index] |= ((color_index + 1) << ((3 - (tile_x % 4)) * 4)) as u16;
    }

    // Deduplicate tiles
    let mut dupe_tile_count = 0;
    let mut tile_data_dedup_map: HashMap<[u16; 16], u16> = HashMap::new();
    let mut tile_dedupe_map: HashMap<u16, u16> = HashMap::new();
    let mut deduped_tiles: Vec<[u16; 16]> = Vec::new();
    for (i, tile) in tiles.iter().enumerate() {
        let index = if let Some(&index) = tile_data_dedup_map.get(tile) {
            println!("tile {} == tile {}", i, index);
            dupe_tile_count += 1;
            index
        } else {
            let index = deduped_tiles.len() as u16;
            deduped_tiles.push(*tile);
            tile_data_dedup_map.insert(*tile, index);

            index
        };
        tile_dedupe_map.insert(i as u16, index);
    }
    println!(
        "dupe tile count: {} unique tile count: {}",
        dupe_tile_count,
        tile_data_dedup_map.len()
    );

    // Write the tile map to the file.
    for y in 0..tilemap_height {
        for x in 0..tilemap_width {
            let index = tile_dedupe_map
                .get(&((y * tilemap_width + x) as u16))
                .unwrap_or_else(|| panic!("tile {} not found", y * tilemap_width + x));
            write!(&mut tile_map_file, "{:04x} ", index).unwrap();
        }
        writeln!(&mut tile_map_file).unwrap();
    }

    // Write the deduped tiles to the file.
    for grid_y in 0..tilemap_height {
        for y in 0..8 {
            for grid_x in 0..tilemap_width {
                let tile = deduped_tiles
                    .get(grid_y as usize * tilemap_width as usize + grid_x as usize)
                    .copied()
                    .unwrap_or_default();
                write!(
                    &mut tile_data_file,
                    "{:04x} {:04x} ",
                    tile[y * 2],
                    tile[y * 2 + 1]
                )
                .unwrap();
            }
            writeln!(&mut tile_data_file).unwrap();
        }
    }

    // Fill the rest of the palette file with "000000" until it has 256 entries.
    for _ in (color_palette.len() + 1)..256 {
        writeln!(&mut palette_file, "000000").unwrap();
    }
}
