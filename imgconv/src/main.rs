// Written by GPT-4 with plain english prompts.... no idea how
// copyright works in that case.
//
// Gouldian_Finch_256x256_4b.png is public domain, photo by Bernard Spragg
// I used Gimp to scale, crop and reduce it to 15 colors

use image::{GenericImageView, Pixel};
use std::fs::File;
use std::io::Write;

fn main() {
    // Read the PNG file.
    let img = image::open("imgconv/Gouldian_Finch_256x256_4b.png").unwrap();

    // Set up the output files.
    let mut tile_map_file = File::create("rtl/tile_map.hex").unwrap();
    let mut pixel_file = File::create("rtl/tiles.hex").unwrap();
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

    // Loop through the pixels in the image.
    for (x, y, pixel) in img.pixels() {
        let tilemap_x = x / 8;
        let tilemap_y = y / 8;
        let tile_x = x % 8;
        let tile_y = y % 8;

        if tile_x == 0 && tile_y == 0 {
            if tilemap_x == 0 && y != 0 {
                writeln!(&mut tile_map_file).unwrap();
            }
            // Write the tilemap entry to the file.
            write!(
                &mut tile_map_file,
                "{:04x} ",
                tilemap_y * tilemap_width + tilemap_x
            )
            .unwrap();
        }

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

        // Add the palette index to the pixel line, incrementing its index.
        pixel_line.push_str(&format!("{:01x}", color_index + 1));

        // If there are 256 pixels on the line, write it to the file and start a new line.
        if pixel_line.len() == 256 {
            writeln!(&mut pixel_file, "{}", chunk_into_four_chars(&pixel_line)).unwrap();
            pixel_line.clear();
        }
    }

    // Write any remaining pixels to the file.
    if !pixel_line.is_empty() {
        writeln!(&mut pixel_file, "{}", chunk_into_four_chars(&pixel_line)).unwrap();
    }

    // Fill the rest of the palette file with "000000" until it has 256 entries.
    for _ in (color_palette.len() + 1)..256 {
        writeln!(&mut palette_file, "000000").unwrap();
    }
}

// Takes a string and chunks it into four-characters groups, adding a space between each group.
fn chunk_into_four_chars(s: &str) -> String {
    s.as_bytes()
        .chunks(4)
        .map(std::str::from_utf8)
        .collect::<Result<Vec<&str>, _>>()
        .unwrap()
        .join(" ")
}
