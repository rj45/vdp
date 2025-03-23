use std::fs::File;
use std::io::Write;

use image::{GenericImageView, Pixel};
use kmeans::{KMeans, KMeansConfig};
use oklab::{self, oklab_to_srgb, srgb_to_oklab, Rgb};
use serde::{Deserialize, Serialize};

use crate::color::{oklab_delta_e, ColorFrequency, Oklab, OklabDistance};

/// Configuration for the image conversion process
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Input image file path
    pub input_file: String,
    /// Output PNG file path
    pub output_png: String,
    /// Output palette hex file path
    pub output_palette_hex: String,
    /// Output tiles hex file path
    pub output_tiles_hex: String,
    /// Output tilemap hex file path
    pub output_tilemap_hex: String,
    /// Output JSON file path (optional)
    pub output_json: Option<String>,
    /// Tile width in pixels
    pub tile_width: u32,
    /// Tile height in pixels
    pub tile_height: u32,
    /// Width of the tilemap in tiles
    pub tilemap_width: u32,
    /// Height of the tilemap in tiles
    pub tilemap_height: u32,
    /// Number of palettes to generate
    pub num_palettes: usize,
    /// Maximum colors per palette
    pub colors_per_palette: usize,
    /// Whether to apply dithering
    pub dithering: bool,
    /// Error scaling factor for dithering
    pub dither_factor: f32,
    /// Threshold for color similarity
    pub color_similarity_threshold: f32,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            input_file: "imgconv/Gouldian_Finch_256x256.png".to_string(),
            output_png: "imgconv/out.png".to_string(),
            output_palette_hex: "rtl/palette.hex".to_string(),
            output_tiles_hex: "rtl/tiles.hex".to_string(),
            output_tilemap_hex: "rtl/tile_map.hex".to_string(),
            output_json: None,
            tile_width: 8,
            tile_height: 8,
            tilemap_width: 32,
            tilemap_height: 32,
            num_palettes: 32,
            colors_per_palette: 16,
            dithering: true,
            dither_factor: 0.75,
            color_similarity_threshold: 0.005,
        }
    }
}

/// Represents an entire tilemap with all its data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TilemapData {
    pub config: Config,
    pub tiles: Vec<Tile>,
    pub palettes: Vec<Palette>,
    pub tilemap: Vec<TilemapEntry>,
}

/// Represents a single tile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tile {
    pub pixels: Vec<Oklab>,
    pub quantized: Vec<u16>,
}

/// Represents a palette of colors
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Palette {
    pub colors: Vec<ColorFrequency>,
}

/// Represents a tilemap entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TilemapEntry {
    pub palette_index: usize,
    pub tile_index: usize,
    pub raw_value: u16,
}

fn extract_colors(tile: &[Oklab], threshold: f32, colors: &mut Vec<ColorFrequency>) {
    for pixel in tile.iter() {
        let mut found = false;
        for item in colors.iter_mut() {
            if oklab_delta_e(*pixel, item.color) < threshold {
                item.frequency += 1;
                found = true;
                break;
            }
        }
        if !found {
            colors.push(ColorFrequency {
                color: *pixel,
                frequency: 1,
            });
        }
    }
}

/// Main struct for the image conversion process
pub struct ImageConverter {
    config: Config,
}

impl ImageConverter {
    pub fn new(config: Config) -> Self {
        ImageConverter { config }
    }

    /// Main execution function to run the entire conversion process
    pub fn convert(&self) -> Result<TilemapData, Box<dyn std::error::Error>> {
        // Read the input image
        let img = self.read_image()?;

        // Extract tiles from the image
        let raw_tiles = self.extract_tiles(&img)?;

        // Generate palettes
        let palettes = self.generate_palettes(&raw_tiles)?;

        // Assign palettes to tiles
        let tile_palette_assignments = self.assign_palettes(&raw_tiles, &palettes)?;

        // Quantize tiles
        let quantized_tiles =
            self.quantize_tiles(&raw_tiles, &palettes, &tile_palette_assignments)?;

        // Generate tilemap
        let tilemap = self.generate_tilemap(&tile_palette_assignments)?;

        // Write output files
        self.write_palette_file(&palettes)?;
        self.write_tilemap_file(&tilemap)?;
        self.write_tiles_file(&quantized_tiles)?;

        // Generate output image
        self.generate_output_image(&quantized_tiles, &palettes, &tilemap)?;

        // Create data for JSON output
        let tilemap_data = self.create_tilemap_data(raw_tiles, palettes, quantized_tiles, tilemap);

        // Write JSON if requested
        if let Some(json_path) = &self.config.output_json {
            self.write_json_file(json_path, &tilemap_data)?;
        }

        Ok(tilemap_data)
    }

    /// Read the input image
    fn read_image(&self) -> Result<image::DynamicImage, Box<dyn std::error::Error>> {
        let img = image::open(&self.config.input_file)?;

        // Image must have width and height that are multiples of the tile size
        if img.width() % self.config.tile_width != 0 || img.height() % self.config.tile_height != 0
        {
            return Err(format!(
                "Image dimensions must be multiples of tile size ({}x{})",
                self.config.tile_width, self.config.tile_height
            )
            .into());
        }

        // Verify tilemap dimensions match image dimensions
        let expected_width = self.config.tilemap_width * self.config.tile_width;
        let expected_height = self.config.tilemap_height * self.config.tile_height;

        if img.width() != expected_width || img.height() != expected_height {
            return Err(format!(
                "Image dimensions ({}x{}) don't match expected dimensions ({}x{}) based on tilemap size",
                img.width(), img.height(), expected_width, expected_height
            ).into());
        }

        Ok(img)
    }

    /// Extract tiles from the image
    fn extract_tiles(
        &self,
        img: &image::DynamicImage,
    ) -> Result<Vec<Vec<Oklab>>, Box<dyn std::error::Error>> {
        let tile_size = (self.config.tile_width * self.config.tile_height) as usize;
        let mut tiles =
            Vec::with_capacity((self.config.tilemap_width * self.config.tilemap_height) as usize);

        // Initialize tiles with empty vectors
        for _ in 0..(self.config.tilemap_width * self.config.tilemap_height) {
            tiles.push(Vec::with_capacity(tile_size));
        }

        // Loop through the pixels in the image, split into tiles and convert to oklab
        for (x, y, pixel) in img.pixels() {
            let tile_map_x = x / self.config.tile_width;
            let tile_map_y = y / self.config.tile_height;
            let tile_x = x % self.config.tile_width;
            let tile_y = y % self.config.tile_height;

            // Convert the pixel to oklab
            let channels = pixel.channels();
            let oklab: Oklab = srgb_to_oklab(Rgb {
                r: channels[0],
                g: channels[1],
                b: channels[2],
            })
            .into();

            // Store the oklab value in the tile
            let tile_index = (tile_map_y * self.config.tilemap_width + tile_map_x) as usize;
            let pixel_index = (tile_y * self.config.tile_width + tile_x) as usize;

            // Ensure the tile vector is initialized to the right size
            if tiles[tile_index].len() <= pixel_index {
                tiles[tile_index].resize(tile_size, Oklab::new(0.0, 0.0, 0.0));
            }

            tiles[tile_index][pixel_index] = oklab;
        }

        Ok(tiles)
    }

    /// Generate palettes from the tiles
    fn generate_palettes(
        &self,
        tiles: &[Vec<Oklab>],
    ) -> Result<Vec<Palette>, Box<dyn std::error::Error>> {
        let tile_size = (self.config.tile_width * self.config.tile_height) as usize;
        let mut cluster_data = Vec::new();

        // Prepare data for clustering
        for tile in tiles.iter() {
            let mut hue_sorted = tile.clone();
            hue_sorted.sort_by(|a, b| {
                let a_hue = a.b.atan2(a.a);
                let b_hue = b.b.atan2(b.a);
                a_hue.partial_cmp(&b_hue).unwrap()
            });

            // Store every permutation of the tile in the cluster data
            for offset in 0..tile_size {
                for i in 0..tile_size {
                    cluster_data.push(hue_sorted[(i + offset) % tile_size].l);
                }
            }
            for offset in 0..tile_size {
                for i in 0..tile_size {
                    cluster_data.push(hue_sorted[(i + offset) % tile_size].a);
                }
            }
            for offset in 0..tile_size {
                for i in 0..tile_size {
                    cluster_data.push(hue_sorted[(i + offset) % tile_size].b);
                }
            }
        }

        // Perform k-means clustering to group tiles by color similarity
        let kmean: KMeans<_, 8, _> = KMeans::new(
            cluster_data,
            tiles.len(),
            tile_size * tile_size * 3,
            OklabDistance,
        );

        let result = kmean.kmeans_lloyd(
            self.config.num_palettes,
            10000,
            KMeans::init_kmeanplusplus,
            &KMeansConfig::default(),
        );

        // Extract colors from each cluster to create palettes
        let mut colors = Vec::new();
        for _ in 0..self.config.num_palettes {
            colors.push(Vec::new());
        }

        for y in 0..self.config.tilemap_height {
            for x in 0..self.config.tilemap_width {
                let tile_index = (y * self.config.tilemap_width + x) as usize;
                let assignment = result.assignments[tile_index];
                extract_colors(
                    &tiles[tile_index],
                    self.config.color_similarity_threshold,
                    &mut colors[assignment],
                );
            }
        }

        // Process each palette to ensure it has the right number of colors
        let mut palettes = Vec::with_capacity(self.config.num_palettes);
        let mut min_colors = usize::MAX;
        let mut max_colors = 0;

        for mut color_frequencies in colors {
            let num_colors = color_frequencies.len();
            min_colors = min_colors.min(num_colors);
            max_colors = max_colors.max(num_colors);

            color_frequencies.sort_by(|a, b| b.frequency.cmp(&a.frequency));
            color_frequencies.reverse();

            // If there are more colors than allowed, reduce using k-means
            if color_frequencies.len() > self.config.colors_per_palette {
                color_frequencies = self.reduce_colors(color_frequencies)?;
            }

            // Sort colors by luminance
            color_frequencies.sort_by(|a, b| a.color.l.partial_cmp(&b.color.l).unwrap());

            palettes.push(Palette {
                colors: color_frequencies,
            });
        }

        println!("min_colors: {}, max_colors: {}", min_colors, max_colors);

        // Sort palettes by average luminance
        palettes.sort_by(|a, b| {
            let a_avg_l =
                a.colors.iter().map(|color| color.color.l).sum::<f32>() / a.colors.len() as f32;
            let b_avg_l =
                b.colors.iter().map(|color| color.color.l).sum::<f32>() / b.colors.len() as f32;
            a_avg_l.partial_cmp(&b_avg_l).unwrap()
        });

        Ok(palettes)
    }

    /// Reduce colors in a palette using k-means
    fn reduce_colors(
        &self,
        color_frequencies: Vec<ColorFrequency>,
    ) -> Result<Vec<ColorFrequency>, Box<dyn std::error::Error>> {
        // Prepare data for k-means
        let mut cluster_data = Vec::new();
        for color_frequency in color_frequencies.iter() {
            cluster_data.push(color_frequency.color.l);
            cluster_data.push(color_frequency.color.a);
            cluster_data.push(color_frequency.color.b);
        }

        // Perform k-means to reduce colors
        let kmean: KMeans<_, 1, _> =
            KMeans::new(cluster_data, color_frequencies.len(), 3, OklabDistance);

        let result = kmean.kmeans_lloyd(
            self.config.colors_per_palette,
            100000,
            KMeans::init_kmeanplusplus,
            &KMeansConfig::default(),
        );

        // Calculate new representative colors
        let mut new_colors = vec![ColorFrequency::default(); self.config.colors_per_palette];
        for (i, color) in color_frequencies.iter().enumerate() {
            let assignment = result.assignments[i];
            new_colors[assignment].color.l += color.color.l * color.frequency as f32;
            new_colors[assignment].color.a += color.color.a * color.frequency as f32;
            new_colors[assignment].color.b += color.color.b * color.frequency as f32;
            new_colors[assignment].frequency += color.frequency;
        }

        // Normalize colors
        for color in new_colors.iter_mut() {
            if color.frequency > 0 {
                color.color.l /= color.frequency as f32;
                color.color.a /= color.frequency as f32;
                color.color.b /= color.frequency as f32;

                assert!(!color.color.l.is_nan());
                assert!(!color.color.a.is_nan());
                assert!(!color.color.b.is_nan());
            }
        }

        // Calculate error metrics
        let mut total_error = 0.0;
        for (i, color) in color_frequencies.iter().enumerate() {
            let assignment = result.assignments[i];
            let error =
                oklab_delta_e(color.color, new_colors[assignment].color) * color.frequency as f32;
            assert!(!error.is_nan());
            total_error += error;
        }

        println!("Color reduction error: {} {}", result.distsum, total_error);

        Ok(new_colors)
    }

    /// Assign palettes to tiles
    fn assign_palettes(
        &self,
        tiles: &[Vec<Oklab>],
        palettes: &[Palette],
    ) -> Result<Vec<usize>, Box<dyn std::error::Error>> {
        let mut tile_palette =
            Vec::with_capacity((self.config.tilemap_width * self.config.tilemap_height) as usize);
        let mut max_tile_error = 0.0;

        // Find the best palette for each tile
        for y in 0..self.config.tilemap_height {
            for x in 0..self.config.tilemap_width {
                let tile_index = (y * self.config.tilemap_width + x) as usize;

                // Find which palette has the least error
                let mut min_error = f32::MAX;
                let mut min_palette = 0;

                for (i, palette) in palettes.iter().enumerate() {
                    let mut error = 0.0;
                    for color in tiles[tile_index].iter() {
                        let mut min_delta_e = f32::MAX;
                        for palette_color in palette.colors.iter() {
                            let delta_e = oklab_delta_e(*color, palette_color.color);
                            if delta_e < min_delta_e {
                                min_delta_e = delta_e;
                            }
                        }
                        error += min_delta_e;
                    }

                    if error < min_error {
                        min_error = error;
                        min_palette = i;
                    }
                }

                tile_palette.push(min_palette);
                if min_error > max_tile_error {
                    max_tile_error = min_error;
                }
            }
        }

        println!(
            "max_tile_error: {}",
            max_tile_error / self.config.tilemap_width as f32 / self.config.tilemap_height as f32
        );

        Ok(tile_palette)
    }

    /// Quantize tiles based on assigned palettes
    fn quantize_tiles(
        &self,
        tiles: &[Vec<Oklab>],
        palettes: &[Palette],
        tile_palette_assignments: &[usize],
    ) -> Result<Vec<Vec<u16>>, Box<dyn std::error::Error>> {
        let tile_size = (self.config.tile_width * self.config.tile_height) as usize;
        let pixels_per_chunk = 4; // 4 pixels per u16 (4 bits per pixel)
        let chunks_per_tile = tile_size.div_ceil(pixels_per_chunk);

        let mut quantized_tiles = Vec::with_capacity(tiles.len());
        let mut dither_error = Vec::new();

        // Initialize error buffer if dithering is enabled
        if self.config.dithering {
            let img_width = self.config.tilemap_width * self.config.tile_width;
            let img_height = self.config.tilemap_height * self.config.tile_height;
            let total_pixels = (img_width * img_height) as usize;

            for _ in 0..total_pixels {
                dither_error.push(Oklab::new(0.0, 0.0, 0.0));
            }
        }
        // Initialize quantized tiles
        for _ in 0..tiles.len() {
            quantized_tiles.push(vec![0u16; chunks_per_tile]);
        }

        // Quantize each tile
        for y in 0..self.config.tilemap_height {
            for ty in 0..self.config.tile_height {
                for x in 0..self.config.tilemap_width {
                    let tile_index = (y * self.config.tilemap_width + x) as usize;
                    let palette_idx = tile_palette_assignments[tile_index];
                    let palette = &palettes[palette_idx];
                    let out_tile = &mut quantized_tiles[tile_index];

                    for tx in 0..self.config.tile_width {
                        let i = (ty * self.config.tile_width + tx) as usize;
                        let gy = (y * self.config.tile_height + ty) as usize;
                        let gx = (x * self.config.tile_width + tx) as usize;
                        let img_width =
                            (self.config.tilemap_width * self.config.tile_width) as usize;

                        // Get original color, add dithering error if enabled
                        let mut color = tiles[tile_index][i];
                        if self.config.dithering {
                            color = Oklab::new(
                                color.l + dither_error[gy * img_width + gx].l,
                                color.a + dither_error[gy * img_width + gx].a,
                                color.b + dither_error[gy * img_width + gx].b,
                            );
                        }

                        // Find closest color in palette
                        let mut min_delta_e = f32::MAX;
                        let mut min_index = 0;
                        for (j, palette_color) in palette.colors.iter().enumerate() {
                            let delta_e = oklab_delta_e(color, palette_color.color);
                            if delta_e < min_delta_e {
                                min_delta_e = delta_e;
                                min_index = j;
                            }
                        }

                        // Set color index in output tile
                        let chunk_idx = i / pixels_per_chunk;
                        let pixel_pos = i % pixels_per_chunk;
                        out_tile[chunk_idx] |= (min_index as u16) << (pixel_pos * 4);

                        // Apply dithering if enabled
                        if self.config.dithering {
                            self.apply_sierra_dithering(
                                &mut dither_error,
                                color,
                                palette.colors[min_index].color,
                                gx,
                                gy,
                                img_width,
                            );
                        }
                    }
                }
            }
        }

        Ok(quantized_tiles)
    }

    /// Apply Sierra dithering algorithm to distribute quantization error
    fn apply_sierra_dithering(
        &self,
        error: &mut [Oklab],
        original: Oklab,
        quantized: Oklab,
        x: usize,
        y: usize,
        width: usize,
    ) {
        let img_height = (self.config.tilemap_height * self.config.tile_height) as usize;
        let diff = Oklab::new(
            ((original.l - quantized.l) / 32.0) * self.config.dither_factor,
            ((original.a - quantized.a) / 32.0) * self.config.dither_factor,
            ((original.b - quantized.b) / 32.0) * self.config.dither_factor,
        );

        // Sierra dithering pattern
        if x < width - 1 {
            error[y * width + x + 1].l += diff.l * 5.0;
            error[y * width + x + 1].a += diff.a * 5.0;
            error[y * width + x + 1].b += diff.b * 5.0;
        }
        if x < width - 2 {
            error[y * width + x + 2].l += diff.l * 3.0;
            error[y * width + x + 2].a += diff.a * 3.0;
            error[y * width + x + 2].b += diff.b * 3.0;
        }
        if y < img_height - 1 {
            if x > 1 {
                error[(y + 1) * width + x - 2].l += diff.l * 2.0;
                error[(y + 1) * width + x - 2].a += diff.a * 2.0;
                error[(y + 1) * width + x - 2].b += diff.b * 2.0;
            }
            if x > 0 {
                error[(y + 1) * width + x - 1].l += diff.l * 4.0;
                error[(y + 1) * width + x - 1].a += diff.a * 4.0;
                error[(y + 1) * width + x - 1].b += diff.b * 4.0;
            }
            error[(y + 1) * width + x].l += diff.l * 5.0;
            error[(y + 1) * width + x].a += diff.a * 5.0;
            error[(y + 1) * width + x].b += diff.b * 5.0;
            if x < width - 1 {
                error[(y + 1) * width + x + 1].l += diff.l * 4.0;
                error[(y + 1) * width + x + 1].a += diff.a * 4.0;
                error[(y + 1) * width + x + 1].b += diff.b * 4.0;
            }
            if x < width - 2 {
                error[(y + 1) * width + x + 2].l += diff.l * 2.0;
                error[(y + 1) * width + x + 2].a += diff.a * 2.0;
                error[(y + 1) * width + x + 2].b += diff.b * 2.0;
            }
        }
        if y < img_height - 2 {
            if x > 0 {
                error[(y + 2) * width + x - 1].l += diff.l * 2.0;
                error[(y + 2) * width + x - 1].a += diff.a * 2.0;
                error[(y + 2) * width + x - 1].b += diff.b * 2.0;
            }
            error[(y + 2) * width + x].l += diff.l * 3.0;
            error[(y + 2) * width + x].a += diff.a * 3.0;
            error[(y + 2) * width + x].b += diff.b * 3.0;
            if x < width - 1 {
                error[(y + 2) * width + x + 1].l += diff.l * 2.0;
                error[(y + 2) * width + x + 1].a += diff.a * 2.0;
                error[(y + 2) * width + x + 1].b += diff.b * 2.0;
            }
        }
    }

    /// Generate tilemap from palette assignments
    fn generate_tilemap(
        &self,
        tile_palette_assignments: &[usize],
    ) -> Result<Vec<u16>, Box<dyn std::error::Error>> {
        let mut tilemap = Vec::with_capacity(tile_palette_assignments.len());

        for y in 0..self.config.tilemap_height {
            for x in 0..self.config.tilemap_width {
                let tile_index = (y * self.config.tilemap_width + x) as usize;
                let palette_idx = tile_palette_assignments[tile_index];

                // Create tilemap entry with palette index in high bits
                tilemap.push((palette_idx << 10) as u16);
            }
        }

        Ok(tilemap)
    }

    /// Write palette data to hex file
    fn write_palette_file(&self, palettes: &[Palette]) -> Result<(), Box<dyn std::error::Error>> {
        let mut palette_file = File::create(&self.config.output_palette_hex)?;

        for palette in palettes.iter() {
            for color in palette.colors.iter() {
                let rgb = oklab_to_srgb(*color.color);
                write!(
                    &mut palette_file,
                    "{:02x}{:02x}{:02x} ",
                    rgb.r, rgb.g, rgb.b
                )?;
            }

            // Pad with zeros for missing colors
            for _ in palette.colors.len()..self.config.colors_per_palette {
                write!(&mut palette_file, "000000 ")?;
            }
            writeln!(&mut palette_file)?;
        }

        Ok(())
    }

    /// Write tilemap data to hex file
    fn write_tilemap_file(&self, tilemap: &[u16]) -> Result<(), Box<dyn std::error::Error>> {
        let mut tile_map_file = File::create(&self.config.output_tilemap_hex)?;

        for (i, item) in tilemap.iter().enumerate() {
            write!(&mut tile_map_file, "{:04x} ", item)?;
            if i % self.config.tilemap_width as usize == (self.config.tilemap_width as usize) - 1 {
                writeln!(&mut tile_map_file)?;
            }
        }

        Ok(())
    }

    /// Write tile data to hex file
    fn write_tiles_file(
        &self,
        quantized_tiles: &[Vec<u16>],
    ) -> Result<(), Box<dyn std::error::Error>> {
        let mut tile_data_file = File::create(&self.config.output_tiles_hex)?;
        let chunks_per_row = 2; // Number of u16 chunks per row in the output file

        for y in 0..self.config.tilemap_height {
            for ty in 0..self.config.tile_height {
                for x in 0..self.config.tilemap_width {
                    let tile_index = (y * self.config.tilemap_width + x) as usize;
                    let tile = &quantized_tiles[tile_index];

                    // Calculate which chunks to write for this row
                    let row_start = ty as usize * chunks_per_row;
                    let row_end = row_start + chunks_per_row;

                    // Write the chunks for this row
                    for tx in row_start..row_end {
                        if tx < tile.len() {
                            write!(&mut tile_data_file, "{:04x} ", tile[tx])?;
                        } else {
                            write!(&mut tile_data_file, "0000 ")?;
                        }
                    }
                }
                writeln!(&mut tile_data_file)?;
            }
        }

        Ok(())
    }

    /// Generate output image to visualize the result
    fn generate_output_image(
        &self,
        quantized_tiles: &[Vec<u16>],
        palettes: &[Palette],
        tilemap: &[u16],
    ) -> Result<(), Box<dyn std::error::Error>> {
        let img_width = self.config.tilemap_width * self.config.tile_width;
        let img_height = self.config.tilemap_height * self.config.tile_height;
        let mut out_img = image::ImageBuffer::new(img_width, img_height);
        let pixels_per_chunk = 4;

        for y in 0..self.config.tilemap_height {
            for x in 0..self.config.tilemap_width {
                let tile_index = (y * self.config.tilemap_width + x) as usize;
                let map_entry = tilemap[tile_index];
                let palette_index = ((map_entry >> 10) as usize) & (self.config.num_palettes - 1);
                let palette = &palettes[palette_index];

                for (chunk_idx, color) in quantized_tiles[tile_index].iter().enumerate() {
                    let base_i = chunk_idx * pixels_per_chunk;

                    for pixel_offset in 0..pixels_per_chunk {
                        if base_i + pixel_offset
                            >= (self.config.tile_width * self.config.tile_height) as usize
                        {
                            break;
                        }

                        let color_index = ((*color >> (pixel_offset * 4)) & 15) as usize;
                        if color_index < palette.colors.len() {
                            let palette_color = palette.colors[color_index].color;
                            let rgb = oklab_to_srgb(*palette_color);

                            let pixel_y = (base_i + pixel_offset) / self.config.tile_width as usize;
                            let pixel_x = (base_i + pixel_offset) % self.config.tile_width as usize;

                            out_img.put_pixel(
                                x * self.config.tile_width + pixel_x as u32,
                                y * self.config.tile_height + pixel_y as u32,
                                image::Rgb([rgb.r, rgb.g, rgb.b]),
                            );
                        }
                    }
                }
            }
        }

        out_img.save(&self.config.output_png)?;
        Ok(())
    }

    /// Create structured data for JSON output
    fn create_tilemap_data(
        &self,
        raw_tiles: Vec<Vec<Oklab>>,
        palettes: Vec<Palette>,
        quantized_tiles: Vec<Vec<u16>>,
        tilemap: Vec<u16>,
    ) -> TilemapData {
        // Create tiles with both raw and quantized data
        let tiles: Vec<Tile> = raw_tiles
            .into_iter()
            .zip(quantized_tiles)
            .map(|(pixels, quantized)| Tile { pixels, quantized })
            .collect();

        // Create tilemap entries
        let tilemap_entries: Vec<TilemapEntry> = tilemap
            .into_iter()
            .enumerate()
            .map(|(i, raw_value)| TilemapEntry {
                palette_index: ((raw_value >> 10) as usize) & (self.config.num_palettes - 1),
                tile_index: i,
                raw_value,
            })
            .collect();

        TilemapData {
            config: self.config.clone(),
            tiles,
            palettes,
            tilemap: tilemap_entries,
        }
    }

    /// Write JSON output file
    fn write_json_file(
        &self,
        path: &str,
        data: &TilemapData,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let file = File::create(path)?;
        serde_json::to_writer_pretty(file, data)?;
        Ok(())
    }
}
