// Written by GPT-4 with plain english prompts.... no idea how
// copyright works in that case.
//
// Gouldian_Finch_256x256_4b.png is public domain, photo by Bernard Spragg
// I used Gimp to scale, crop and reduce it to 15 colors

use std::fs::File;
use std::io::Write;
use image::{GenericImageView, Pixel};
use hex;

fn main() {
    // Read the PNG file.
    let img = image::open("Gouldian_Finch_256x256_4b.png").unwrap();

    // Set up the output files.
    let mut pixel_file = File::create("../rtl/tiles.hex").unwrap();
    let mut palette_file = File::create("../rtl/palette.hex").unwrap();

    // Set up the color palette.
    let mut color_palette: Vec<String> = Vec::new();

    // A buffer for storing the hex string to be written to the pixel file.
    let mut pixel_line = String::new();

    // Ensure the first palette entry is black.
    writeln!(&mut palette_file, "{}", "000000").unwrap();

    // Loop through the pixels in the image.
    for (_x, _y, pixel) in img.pixels() {
        // Convert the pixel to rgba.
        let rgba = pixel.to_rgba();

        // Convert the RGB part to a hex string.
        let pixel_hex = hex::encode(&rgba.channels()[0..3]);

        // If the color is not already in the palette, add it.
        let color_index = match color_palette.iter().position(|x| *x == pixel_hex) {
            Some(index) => index,
            None => {
                color_palette.push(pixel_hex.clone());
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
    for _ in (color_palette.len()+1)..256 {
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
