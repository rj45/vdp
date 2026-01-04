//! Image conversion module for converting images to tiles and palettes
//!
//! This module handles the conversion of images to tiles, palettes, and tilemaps
//! for use in graphics hardware or software.

use std::fs::File;
use std::io::{self, Write};

use image::{GenericImageView, Pixel, RgbImage};
use kmeans::{KMeans, KMeansConfig};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::color::{find_similar_color, oklab_delta_e, ColorFrequency, Oklab, OklabDistance};

// Constants to replace magic numbers
/// Number of bits per color index in output tile data
const BITS_PER_COLOR: usize = 4;
/// Number of pixels per u16 chunk in output tile data (16 bits / 4 bits per pixel)
const PIXELS_PER_CHUNK: usize = 16 / BITS_PER_COLOR;
/// Divisor used for dithering error calculation
const DITHER_ERROR_DIVISOR: f32 = 32.0;
/// Maximum number of k-means iterations for palette generation
const KMEANS_MAX_ITERATIONS: usize = 10000;
/// Maximum number of k-means iterations for color reduction
const COLOR_REDUCTION_MAX_ITERATIONS: usize = 100000;
/// Number of u16 chunks per row in output file
const CHUNKS_PER_ROW: usize = 2;
/// Bit position for palette index in tilemap entry
const PALETTE_INDEX_SHIFT: usize = 10;
/// Delta E multiplier for error metrics display
const DELTA_E_DISPLAY_FACTOR: f32 = 100.0;
/// Maximum pixel value for PSNR calculation (8-bit color)
const MAX_PIXEL_VALUE: f32 = 255.0;

/// Errors that can occur during image conversion
#[derive(Error, Debug)]
pub enum ConversionError {
    #[error("Image dimensions {0}x{1} are not multiples of tile size {2}x{3}")]
    InvalidDimensions(u32, u32, u32, u32),

    #[error("Image dimensions {0}x{1} don't match expected {2}x{3} based on tilemap size")]
    DimensionMismatch(u32, u32, u32, u32),

    #[error("Failed to read image: {0}")]
    ImageReadError(#[from] image::ImageError),

    #[error("IO error: {0}")]
    IoError(#[from] io::Error),

    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("Error generating palettes: {0}")]
    PaletteGeneration(String),
}

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
    /// Maximum number of unique tiles (default 256, max 1024)
    pub max_unique_tiles: usize,
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
            max_unique_tiles: 256,
        }
    }
}

impl Config {
    /// Get total number of tiles in the tilemap
    pub fn total_tiles(&self) -> usize {
        (self.tilemap_width * self.tilemap_height) as usize
    }

    /// Get the number of pixels in a single tile
    pub fn tile_size(&self) -> usize {
        (self.tile_width * self.tile_height) as usize
    }

    /// Get the total width in pixels
    pub fn total_width(&self) -> u32 {
        self.tilemap_width * self.tile_width
    }

    /// Get the total height in pixels
    pub fn total_height(&self) -> u32 {
        self.tilemap_height * self.tile_height
    }

    /// Get the number of chunks needed per tile
    pub fn chunks_per_tile(&self) -> usize {
        self.tile_size().div_ceil(PIXELS_PER_CHUNK)
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

impl Palette {
    /// Find the best matching color index for the given color
    pub fn find_best_color(&self, color: Oklab) -> usize {
        let mut min_delta_e = f32::MAX;
        let mut min_index = 0;

        for (i, palette_color) in self.colors.iter().enumerate() {
            let delta_e = oklab_delta_e(color, palette_color.color);
            if delta_e < min_delta_e {
                min_delta_e = delta_e;
                min_index = i;
            }
        }

        min_index
    }

    /// Calculate the average luminance of colors in this palette
    pub fn average_luminance(&self) -> f32 {
        if self.colors.is_empty() {
            return 0.0;
        }

        self.colors.iter().map(|c| c.color.l).sum::<f32>() / self.colors.len() as f32
    }

    /// Sort colors by luminance
    pub fn sort_by_luminance(&mut self) {
        self.colors
            .sort_by(|a, b| a.color.l.partial_cmp(&b.color.l).unwrap());
    }
}

/// Represents a tilemap entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TilemapEntry {
    pub palette_index: usize,
    pub tile_index: usize,
    pub raw_value: u16,
}

impl TilemapEntry {
    /// Create a new tilemap entry with the given palette and tile indices
    pub fn new(palette_index: usize, tile_index: usize) -> Self {
        TilemapEntry {
            palette_index,
            tile_index,
            raw_value: ((palette_index << PALETTE_INDEX_SHIFT) | tile_index) as u16,
        }
    }
}

/// Represents a unique tile after clustering
#[derive(Debug, Clone)]
pub struct UniqueTile {
    /// The quantized pixel data
    pub quantized: Vec<u16>,
    /// Original tile index this was derived from (for debugging)
    #[allow(dead_code)]
    pub source_tile: usize,
}

/// Represents a tilemap position's assignment to a unique tile and palette
#[derive(Debug, Clone)]
pub struct TileAssignment {
    /// Index into the unique tiles array
    pub unique_tile_index: usize,
    /// Palette index to use for this position
    pub palette_index: usize,
}

/// Extract unique colors from a tile into a color frequency list
fn extract_colors(tile: &[Oklab], threshold: f32, colors: &mut Vec<ColorFrequency>) {
    for pixel in tile.iter() {
        if let Some(index) = find_similar_color(*pixel, colors, threshold) {
            colors[index].frequency += 1;
        } else {
            colors.push(ColorFrequency::new(*pixel, 1));
        }
    }
}

/// Main struct for the image conversion process
pub struct ImageConverter {
    config: Config,
}

impl ImageConverter {
    /// Create a new image converter with the given configuration
    pub fn new(config: Config) -> Self {
        ImageConverter { config }
    }

    /// Main execution function to run the entire conversion process
    pub fn convert(&self) -> Result<TilemapData, ConversionError> {
        // Read the input image
        let img = self.read_image()?;

        // Extract tiles from the image
        let raw_tiles = self.extract_tiles(&img)?;

        // Generate palettes
        let palettes = self.generate_palettes(&raw_tiles)?;

        // Assign palettes to tiles (initial assignment for quantization)
        let tile_palette_assignments = self.assign_palettes(&raw_tiles, &palettes)?;

        // Quantize tiles with initial palette assignments
        let quantized_tiles =
            self.quantize_tiles(&raw_tiles, &palettes, &tile_palette_assignments)?;

        // Cluster quantized tiles to find unique representative tiles
        let unique_tiles =
            self.cluster_quantized_tiles(&quantized_tiles, &tile_palette_assignments, &palettes)?;

        // Find the best (unique_tile, palette) combination for each tilemap position
        let tile_assignments = self.find_best_tile_assignments(&raw_tiles, &unique_tiles, &palettes);

        // Generate tilemap with tile indices and palette indices
        let tilemap = self.generate_tilemap_from_assignments(&tile_assignments);

        // Write output files
        self.write_palette_file(&palettes)?;
        self.write_tilemap_file(&tilemap)?;
        self.write_tiles_file(&unique_tiles)?;

        // Generate output image using unique tiles and assignments
        let output_img =
            self.generate_output_image_from_assignments(&unique_tiles, &palettes, &tile_assignments)?;

        // Create data for JSON output (using original quantized tiles for compatibility)
        let tilemap_data = self.create_tilemap_data(raw_tiles, palettes, quantized_tiles, tilemap);

        // Write JSON if requested
        if let Some(json_path) = &self.config.output_json {
            self.write_json_file(json_path, &tilemap_data)?;
        }

        // Generate error metrics for the output image
        self.generate_error_metrics(&output_img, &img)?;

        Ok(tilemap_data)
    }

    /// Read the input image
    fn read_image(&self) -> Result<image::DynamicImage, ConversionError> {
        let img = image::open(&self.config.input_file)?;

        // Image must have width and height that are multiples of the tile size
        if img.width() % self.config.tile_width != 0 || img.height() % self.config.tile_height != 0
        {
            return Err(ConversionError::InvalidDimensions(
                img.width(),
                img.height(),
                self.config.tile_width,
                self.config.tile_height,
            ));
        }

        // Verify tilemap dimensions match image dimensions
        let expected_width = self.config.total_width();
        let expected_height = self.config.total_height();

        if img.width() != expected_width || img.height() != expected_height {
            return Err(ConversionError::DimensionMismatch(
                img.width(),
                img.height(),
                expected_width,
                expected_height,
            ));
        }

        Ok(img)
    }

    /// Extract tiles from the image
    fn extract_tiles(&self, img: &image::DynamicImage) -> Result<Vec<Vec<Oklab>>, ConversionError> {
        let tile_size = self.config.tile_size();
        let total_tiles = self.config.total_tiles();
        let mut tiles = Vec::with_capacity(total_tiles);

        // Initialize tiles with empty vectors
        for _ in 0..total_tiles {
            let mut tile = Vec::with_capacity(tile_size);
            tile.resize(tile_size, Oklab::new(0.0, 0.0, 0.0));
            tiles.push(tile);
        }

        // Loop through the pixels in the image, split into tiles and convert to oklab
        for (x, y, pixel) in img.pixels() {
            let tile_map_x = x / self.config.tile_width;
            let tile_map_y = y / self.config.tile_height;
            let tile_x = x % self.config.tile_width;
            let tile_y = y % self.config.tile_height;

            // Convert the pixel to oklab
            let channels = pixel.channels();
            let oklab = Oklab::from_rgb(channels[0], channels[1], channels[2]);

            // Store the oklab value in the tile
            let tile_index = (tile_map_y * self.config.tilemap_width + tile_map_x) as usize;
            let pixel_index = (tile_y * self.config.tile_width + tile_x) as usize;
            tiles[tile_index][pixel_index] = oklab;
        }

        Ok(tiles)
    }

    /// Generate palettes from the tiles
    fn generate_palettes(&self, tiles: &[Vec<Oklab>]) -> Result<Vec<Palette>, ConversionError> {
        let tile_size = self.config.tile_size();
        let mut cluster_data = Vec::new();

        // Prepare data for clustering
        self.prepare_clustering_data(tiles, tile_size, &mut cluster_data);

        // Perform k-means clustering to group tiles by color similarity
        let kmean: KMeans<_, 8, _> = KMeans::new(
            cluster_data,
            tiles.len(),
            tile_size * tile_size * 3,
            OklabDistance,
        );

        let result = kmean.kmeans_lloyd(
            self.config.num_palettes,
            KMEANS_MAX_ITERATIONS,
            KMeans::init_kmeanplusplus,
            &KMeansConfig::default(),
        );

        // Extract colors from each cluster to create palettes
        let colors = self.extract_palette_colors(tiles, &result)?;

        // Process each palette to ensure it has the right number of colors
        let mut palettes = self.process_palettes(colors)?;

        // Sort palettes by average luminance for better visual organization
        palettes.sort_by(|a, b| {
            a.average_luminance()
                .partial_cmp(&b.average_luminance())
                .unwrap()
        });

        // fix palette 0, index 0 to be black
        palettes.get_mut(0).map(|p| {
            if let Some(color) = p.colors.get_mut(0) {
                color.color = Oklab::from_rgb(0, 0, 0);
            }
        });

        Ok(palettes)
    }

    /// Prepare data for k-means clustering
    fn prepare_clustering_data(
        &self,
        tiles: &[Vec<Oklab>],
        tile_size: usize,
        cluster_data: &mut Vec<f32>,
    ) {
        for tile in tiles.iter() {
            let mut hue_sorted = tile.clone();
            hue_sorted.sort_by(|a, b| a.hue().partial_cmp(&b.hue()).unwrap());

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
    }

    /// Extract colors for each palette from the clustered tiles
    fn extract_palette_colors(
        &self,
        tiles: &[Vec<Oklab>],
        clustering_result: &kmeans::KMeansState<f32>,
    ) -> Result<Vec<Vec<ColorFrequency>>, ConversionError> {
        let mut colors = vec![Vec::new(); self.config.num_palettes];

        for y in 0..self.config.tilemap_height {
            for x in 0..self.config.tilemap_width {
                let tile_index = (y * self.config.tilemap_width + x) as usize;
                if tile_index >= clustering_result.assignments.len() {
                    return Err(ConversionError::PaletteGeneration(format!(
                        "Tile index {} out of bounds for assignments",
                        tile_index
                    )));
                }

                let assignment = clustering_result.assignments[tile_index];
                if assignment >= self.config.num_palettes {
                    return Err(ConversionError::PaletteGeneration(format!(
                        "Palette assignment {} exceeds num_palettes {}",
                        assignment, self.config.num_palettes
                    )));
                }

                extract_colors(
                    &tiles[tile_index],
                    self.config.color_similarity_threshold,
                    &mut colors[assignment],
                );
            }
        }

        Ok(colors)
    }

    /// Process palette color sets into final palettes
    fn process_palettes(
        &self,
        colors: Vec<Vec<ColorFrequency>>,
    ) -> Result<Vec<Palette>, ConversionError> {
        let mut palettes = Vec::with_capacity(self.config.num_palettes);
        let mut min_colors = usize::MAX;
        let mut max_colors = 0;

        for mut color_frequencies in colors {
            let num_colors = color_frequencies.len();
            min_colors = min_colors.min(num_colors);
            max_colors = max_colors.max(num_colors);

            // Sort by frequency (most frequent first)
            color_frequencies.sort_by(|a, b| b.frequency.cmp(&a.frequency));

            // If there are more colors than allowed, reduce using k-means
            let processed_colors = if color_frequencies.len() > self.config.colors_per_palette {
                self.reduce_colors(color_frequencies)?
            } else {
                color_frequencies
            };

            // Create a new palette with the processed colors
            let mut palette = Palette {
                colors: processed_colors,
            };
            palette.sort_by_luminance();
            palettes.push(palette);
        }

        println!("min_colors: {}, max_colors: {}", min_colors, max_colors);
        Ok(palettes)
    }

    /// Reduce colors in a palette using k-means
    fn reduce_colors(
        &self,
        color_frequencies: Vec<ColorFrequency>,
    ) -> Result<Vec<ColorFrequency>, ConversionError> {
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
            COLOR_REDUCTION_MAX_ITERATIONS,
            KMeans::init_kmeanplusplus,
            &KMeansConfig::default(),
        );

        // Calculate new representative colors by weighted averaging
        let mut new_colors = vec![ColorFrequency::default(); self.config.colors_per_palette];

        for (i, color) in color_frequencies.iter().enumerate() {
            let assignment = result.assignments[i];
            // Accumulate weighted components
            new_colors[assignment].color.l += color.color.l * color.frequency as f32;
            new_colors[assignment].color.a += color.color.a * color.frequency as f32;
            new_colors[assignment].color.b += color.color.b * color.frequency as f32;
            new_colors[assignment].frequency += color.frequency;
        }

        // Normalize colors by dividing by total frequency
        for color in new_colors.iter_mut().filter(|c| c.frequency > 0) {
            color.color.l /= color.frequency as f32;
            color.color.a /= color.frequency as f32;
            color.color.b /= color.frequency as f32;
        }

        Ok(new_colors)
    }

    /// Assign palettes to tiles
    fn assign_palettes(
        &self,
        tiles: &[Vec<Oklab>],
        palettes: &[Palette],
    ) -> Result<Vec<usize>, ConversionError> {
        let total_tiles = self.config.total_tiles();
        let mut tile_palette = Vec::with_capacity(total_tiles);

        // Find the best palette for each tile
        for y in 0..self.config.tilemap_height {
            for x in 0..self.config.tilemap_width {
                let tile_index = (y * self.config.tilemap_width + x) as usize;
                let palette_index = self.find_best_palette_for_tile(tiles, palettes, tile_index);

                tile_palette.push(palette_index);
            }
        }

        Ok(tile_palette)
    }

    /// Find the best palette for a specific tile
    fn find_best_palette_for_tile(
        &self,
        tiles: &[Vec<Oklab>],
        palettes: &[Palette],
        tile_index: usize,
    ) -> usize {
        let mut min_error = f32::MAX;
        let mut min_palette = 0;

        for (i, palette) in palettes.iter().enumerate() {
            let mut error = 0.0;
            for color in tiles[tile_index].iter() {
                let mut min_delta_e = f32::MAX;
                for palette_color in palette.colors.iter() {
                    let delta_e = oklab_delta_e(*color, palette_color.color);
                    min_delta_e = min_delta_e.min(delta_e);
                }
                error += min_delta_e;
            }

            if error < min_error {
                min_error = error;
                min_palette = i;
            }
        }

        min_palette
    }

    /// Cluster quantized tiles to find unique representative tiles
    fn cluster_quantized_tiles(
        &self,
        quantized_tiles: &[Vec<u16>],
        tile_palette_assignments: &[usize],
        palettes: &[Palette],
    ) -> Result<Vec<UniqueTile>, ConversionError> {
        let num_tiles = quantized_tiles.len();

        // If under max, no clustering needed - each tile is unique
        if num_tiles <= self.config.max_unique_tiles {
            return Ok(quantized_tiles
                .iter()
                .enumerate()
                .map(|(i, q)| UniqueTile {
                    quantized: q.clone(),
                    source_tile: i,
                })
                .collect());
        }

        // Convert quantized tiles to color-space feature vectors for clustering
        let tile_size = self.config.tile_size();
        let feature_size = tile_size * 3; // 3 LAB components per pixel
        let mut cluster_data = Vec::with_capacity(num_tiles * feature_size);

        for (tile_idx, tile) in quantized_tiles.iter().enumerate() {
            let palette = &palettes[tile_palette_assignments[tile_idx]];

            // Convert each pixel to Oklab color
            for chunk_idx in 0..(tile_size / PIXELS_PER_CHUNK) {
                for pixel_offset in 0..PIXELS_PER_CHUNK {
                    let color_idx =
                        ((tile[chunk_idx] >> (pixel_offset * BITS_PER_COLOR)) & 0xF) as usize;
                    let color = palette
                        .colors
                        .get(color_idx)
                        .map(|c| c.color)
                        .unwrap_or_else(|| Oklab::new(0.0, 0.0, 0.0));
                    cluster_data.push(color.l);
                    cluster_data.push(color.a);
                    cluster_data.push(color.b);
                }
            }
        }

        // Run k-means clustering
        let kmean: KMeans<_, 8, _> =
            KMeans::new(cluster_data, num_tiles, feature_size, OklabDistance);

        let result = kmean.kmeans_lloyd(
            self.config.max_unique_tiles,
            KMEANS_MAX_ITERATIONS,
            KMeans::init_kmeanplusplus,
            &KMeansConfig::default(),
        );

        // Find representative tile for each cluster (the one assigned to that cluster)
        let mut unique_tiles = Vec::with_capacity(self.config.max_unique_tiles);
        let mut used_clusters = vec![false; self.config.max_unique_tiles];

        for (tile_idx, &cluster_id) in result.assignments.iter().enumerate() {
            if !used_clusters[cluster_id] {
                used_clusters[cluster_id] = true;
                unique_tiles.push(UniqueTile {
                    quantized: quantized_tiles[tile_idx].clone(),
                    source_tile: tile_idx,
                });
            }
        }

        println!(
            "Clustered {} tiles into {} unique tiles",
            num_tiles,
            unique_tiles.len()
        );

        Ok(unique_tiles)
    }

    /// Find the best (unique_tile, palette) combination for each tilemap position
    fn find_best_tile_assignments(
        &self,
        raw_tiles: &[Vec<Oklab>],
        unique_tiles: &[UniqueTile],
        palettes: &[Palette],
    ) -> Vec<TileAssignment> {
        let mut assignments = Vec::with_capacity(raw_tiles.len());

        for original_tile in raw_tiles.iter() {
            let mut best_error = f32::MAX;
            let mut best_unique_idx = 0;
            let mut best_palette_idx = 0;

            // Try each unique tile with each palette
            for (unique_idx, unique_tile) in unique_tiles.iter().enumerate() {
                for (palette_idx, palette) in palettes.iter().enumerate() {
                    let error = self.calculate_reconstruction_error(
                        original_tile,
                        &unique_tile.quantized,
                        palette,
                    );

                    if error < best_error {
                        best_error = error;
                        best_unique_idx = unique_idx;
                        best_palette_idx = palette_idx;
                    }
                }
            }

            assignments.push(TileAssignment {
                unique_tile_index: best_unique_idx,
                palette_index: best_palette_idx,
            });
        }

        assignments
    }

    /// Calculate reconstruction error between original tile and quantized representation
    fn calculate_reconstruction_error(
        &self,
        original: &[Oklab],
        quantized: &[u16],
        palette: &Palette,
    ) -> f32 {
        let mut total_error = 0.0;

        for (pixel_idx, &original_color) in original.iter().enumerate() {
            let chunk_idx = pixel_idx / PIXELS_PER_CHUNK;
            let pixel_offset = pixel_idx % PIXELS_PER_CHUNK;

            let color_idx =
                ((quantized[chunk_idx] >> (pixel_offset * BITS_PER_COLOR)) & 0xF) as usize;

            if let Some(palette_color) = palette.colors.get(color_idx) {
                total_error += oklab_delta_e(original_color, palette_color.color);
            } else {
                total_error += 1.0; // Penalty for missing color
            }
        }

        total_error
    }

    /// Quantize tiles based on assigned palettes
    fn quantize_tiles(
        &self,
        tiles: &[Vec<Oklab>],
        palettes: &[Palette],
        tile_palette_assignments: &[usize],
    ) -> Result<Vec<Vec<u16>>, ConversionError> {
        let chunks_per_tile = self.config.chunks_per_tile();
        let mut quantized_tiles = Vec::with_capacity(tiles.len());
        let mut dither_error = Vec::new();

        // Initialize error buffer if dithering is enabled
        if self.config.dithering {
            let total_pixels = (self.config.total_width() * self.config.total_height()) as usize;
            dither_error = vec![Oklab::new(0.0, 0.0, 0.0); total_pixels];
        }

        // Initialize quantized tiles
        for _ in 0..tiles.len() {
            quantized_tiles.push(vec![0u16; chunks_per_tile]);
        }

        // Process each pixel row by row for better cache locality
        self.quantize_pixels(
            tiles,
            palettes,
            tile_palette_assignments,
            &mut quantized_tiles,
            &mut dither_error,
        )?;

        Ok(quantized_tiles)
    }

    /// Quantize all pixels and apply dithering if enabled
    fn quantize_pixels(
        &self,
        tiles: &[Vec<Oklab>],
        palettes: &[Palette],
        tile_palette_assignments: &[usize],
        quantized_tiles: &mut [Vec<u16>],
        dither_error: &mut [Oklab],
    ) -> Result<(), ConversionError> {
        let img_width = self.config.total_width() as usize;

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

                        // Get original color, add dithering error if enabled
                        let color = if self.config.dithering {
                            tiles[tile_index][i].add(&dither_error[gy * img_width + gx])
                        } else {
                            tiles[tile_index][i]
                        };

                        // Find closest color in palette
                        let min_index = palette.find_best_color(color);

                        // Set color index in output tile
                        let chunk_idx = i / PIXELS_PER_CHUNK;
                        let pixel_pos = i % PIXELS_PER_CHUNK;
                        out_tile[chunk_idx] |= (min_index as u16) << (pixel_pos * BITS_PER_COLOR);

                        // Apply dithering if enabled
                        if self.config.dithering {
                            self.apply_sierra_dithering(
                                dither_error,
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

        Ok(())
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
        let img_height = self.config.total_height() as usize;
        let diff =
            original.dither_error_term(&quantized, self.config.dither_factor, DITHER_ERROR_DIVISOR);

        // Sierra dithering pattern - Apply error diffusion to neighboring pixels
        // This is the classic Sierra filter pattern with 16 coefficients

        // Current row
        if x < width - 1 {
            error[y * width + x + 1].weighted_add(&diff, 5.0);
        }
        if x < width - 2 {
            error[y * width + x + 2].weighted_add(&diff, 3.0);
        }

        // Next row
        if y < img_height - 1 {
            if x > 1 {
                error[(y + 1) * width + x - 2].weighted_add(&diff, 2.0);
            }
            if x > 0 {
                error[(y + 1) * width + x - 1].weighted_add(&diff, 4.0);
            }
            error[(y + 1) * width + x].weighted_add(&diff, 5.0);
            if x < width - 1 {
                error[(y + 1) * width + x + 1].weighted_add(&diff, 4.0);
            }
            if x < width - 2 {
                error[(y + 1) * width + x + 2].weighted_add(&diff, 2.0);
            }
        }

        // Two rows below
        if y < img_height - 2 {
            if x > 0 {
                error[(y + 2) * width + x - 1].weighted_add(&diff, 2.0);
            }
            error[(y + 2) * width + x].weighted_add(&diff, 3.0);
            if x < width - 1 {
                error[(y + 2) * width + x + 1].weighted_add(&diff, 2.0);
            }
        }
    }

    /// Generate tilemap from tile assignments (with unique tile indices)
    fn generate_tilemap_from_assignments(&self, tile_assignments: &[TileAssignment]) -> Vec<u16> {
        tile_assignments
            .iter()
            .map(|assignment| {
                TilemapEntry::new(assignment.palette_index, assignment.unique_tile_index).raw_value
            })
            .collect()
    }

    /// Write palette data to hex file
    fn write_palette_file(&self, palettes: &[Palette]) -> Result<(), ConversionError> {
        let mut palette_file = File::create(&self.config.output_palette_hex)?;

        for palette in palettes.iter() {
            for color in palette.colors.iter() {
                let (r, g, b) = color.color.to_rgb();
                write!(&mut palette_file, "{:02x}{:02x}{:02x} ", r, g, b)?;
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
    fn write_tilemap_file(&self, tilemap: &[u16]) -> Result<(), ConversionError> {
        let mut tile_map_file = File::create(&self.config.output_tilemap_hex)?;

        for (i, item) in tilemap.iter().enumerate() {
            write!(&mut tile_map_file, "{:04x} ", item)?;
            if i % self.config.tilemap_width as usize == (self.config.tilemap_width as usize) - 1 {
                writeln!(&mut tile_map_file)?;
            }
        }

        Ok(())
    }

    /// Write tile data to hex file (unique tiles only)
    ///
    /// Output format: 8 lines (one per tile row 0-7)
    /// Each line: for each unique tile, write 2 chunks for that row
    fn write_tiles_file(&self, unique_tiles: &[UniqueTile]) -> Result<(), ConversionError> {
        let mut tile_data_file = File::create(&self.config.output_tiles_hex)?;

        // For each row of the tile (0-7 for 8x8 tiles)
        for row in 0..self.config.tile_height as usize {
            // For each unique tile
            for tile in unique_tiles.iter() {
                let row_start = row * CHUNKS_PER_ROW;

                // Write 2 chunks for this row of this tile
                for chunk_offset in 0..CHUNKS_PER_ROW {
                    let chunk_idx = row_start + chunk_offset;
                    if chunk_idx < tile.quantized.len() {
                        write!(&mut tile_data_file, "{:04x} ", tile.quantized[chunk_idx])?;
                    } else {
                        write!(&mut tile_data_file, "0000 ")?;
                    }
                }
            }

            // Pad remaining tiles if fewer than max_unique_tiles
            for _ in unique_tiles.len()..self.config.max_unique_tiles {
                write!(&mut tile_data_file, "0000 0000 ")?;
            }

            writeln!(&mut tile_data_file)?;
        }

        Ok(())
    }

    /// Generate output image using unique tiles and tile assignments
    fn generate_output_image_from_assignments(
        &self,
        unique_tiles: &[UniqueTile],
        palettes: &[Palette],
        tile_assignments: &[TileAssignment],
    ) -> Result<RgbImage, ConversionError> {
        let img_width = self.config.total_width();
        let img_height = self.config.total_height();
        let mut out_img = image::ImageBuffer::new(img_width, img_height);

        for y in 0..self.config.tilemap_height {
            for x in 0..self.config.tilemap_width {
                let tilemap_idx = (y * self.config.tilemap_width + x) as usize;
                let assignment = &tile_assignments[tilemap_idx];
                let unique_tile = &unique_tiles[assignment.unique_tile_index];
                let palette = &palettes[assignment.palette_index];

                // Render this tile
                for (chunk_idx, &chunk) in unique_tile.quantized.iter().enumerate() {
                    let base_i = chunk_idx * PIXELS_PER_CHUNK;

                    for pixel_offset in 0..PIXELS_PER_CHUNK {
                        let pixel_idx = base_i + pixel_offset;
                        if pixel_idx >= self.config.tile_size() {
                            break;
                        }

                        let color_idx = ((chunk >> (pixel_offset * BITS_PER_COLOR)) & 0xF) as usize;
                        if let Some(color) = palette.colors.get(color_idx) {
                            let (r, g, b) = color.color.to_rgb();

                            let pixel_y = pixel_idx / self.config.tile_width as usize;
                            let pixel_x = pixel_idx % self.config.tile_width as usize;

                            out_img.put_pixel(
                                x * self.config.tile_width + pixel_x as u32,
                                y * self.config.tile_height + pixel_y as u32,
                                image::Rgb([r, g, b]),
                            );
                        }
                    }
                }
            }
        }

        out_img.save(&self.config.output_png)?;
        Ok(out_img)
    }

    /// Compare the output image with the original to calculate quality metrics
    fn generate_error_metrics(
        &self,
        output_img: &RgbImage,
        original_img: &image::DynamicImage,
    ) -> Result<(), ConversionError> {
        let mut delta_e_values =
            Vec::with_capacity((self.config.total_width() * self.config.total_height()) as usize);

        // Variables for PSNR calculation
        let mut mse_r: f64 = 0.0;
        let mut mse_g: f64 = 0.0;
        let mut mse_b: f64 = 0.0;
        let mut pixel_count: usize = 0;

        // Calculate delta_e for each pixel and squared errors for PSNR
        for (x, y, original_pixel) in original_img.pixels() {
            if x >= output_img.width() || y >= output_img.height() {
                continue;
            }

            let original_rgb = original_pixel.to_rgb();
            let output_pixel = output_img.get_pixel(x, y);

            // Calculate Delta E
            let original_oklab = Oklab::from_rgb(original_rgb[0], original_rgb[1], original_rgb[2]);
            let output_oklab = Oklab::from_rgb(output_pixel[0], output_pixel[1], output_pixel[2]);
            let delta_e = oklab_delta_e(original_oklab, output_oklab) * DELTA_E_DISPLAY_FACTOR;
            delta_e_values.push(delta_e);

            // Calculate squared error for each channel (for MSE/PSNR)
            let diff_r = (original_rgb[0] as f64 - output_pixel[0] as f64).powi(2);
            let diff_g = (original_rgb[1] as f64 - output_pixel[1] as f64).powi(2);
            let diff_b = (original_rgb[2] as f64 - output_pixel[2] as f64).powi(2);

            mse_r += diff_r;
            mse_g += diff_g;
            mse_b += diff_b;
            pixel_count += 1;
        }

        // Sort the values to calculate percentiles
        delta_e_values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        // Calculate statistics for Delta E
        let min_delta_e = delta_e_values.first().copied().unwrap_or(0.0);
        let max_delta_e = delta_e_values.last().copied().unwrap_or(0.0);

        let sum_delta_e: f32 = delta_e_values.iter().sum();
        let mean_delta_e = sum_delta_e / delta_e_values.len() as f32;

        let median_index = delta_e_values.len() / 2;
        let median_delta_e = delta_e_values.get(median_index).copied().unwrap_or(0.0);

        let p75_index = (delta_e_values.len() as f32 * 0.75) as usize;
        let p75_delta_e = delta_e_values.get(p75_index).copied().unwrap_or(0.0);

        let p90_index = (delta_e_values.len() as f32 * 0.90) as usize;
        let p90_delta_e = delta_e_values.get(p90_index).copied().unwrap_or(0.0);

        let p95_index = (delta_e_values.len() as f32 * 0.95) as usize;
        let p95_delta_e = delta_e_values.get(p95_index).copied().unwrap_or(0.0);

        let p99_index = (delta_e_values.len() as f32 * 0.99) as usize;
        let p99_delta_e = delta_e_values.get(p99_index).copied().unwrap_or(0.0);

        // Calculate PSNR for each channel and average
        let mse_r = mse_r / pixel_count as f64;
        let mse_g = mse_g / pixel_count as f64;
        let mse_b = mse_b / pixel_count as f64;
        let mse_avg = (mse_r + mse_g + mse_b) / 3.0;

        // PSNR = 20 * log10(MAX_PIXEL_VALUE) - 10 * log10(MSE)
        let psnr_r = if mse_r > 0.0 {
            20.0 * (MAX_PIXEL_VALUE as f64).log10() - 10.0 * mse_r.log10()
        } else {
            f64::INFINITY
        };
        let psnr_g = if mse_g > 0.0 {
            20.0 * (MAX_PIXEL_VALUE as f64).log10() - 10.0 * mse_g.log10()
        } else {
            f64::INFINITY
        };
        let psnr_b = if mse_b > 0.0 {
            20.0 * (MAX_PIXEL_VALUE as f64).log10() - 10.0 * mse_b.log10()
        } else {
            f64::INFINITY
        };
        let psnr_avg = if mse_avg > 0.0 {
            20.0 * (MAX_PIXEL_VALUE as f64).log10() - 10.0 * mse_avg.log10()
        } else {
            f64::INFINITY
        };

        // Print formatted results
        println!(
            "\nImage Quality {}x Delta E Comparison (lower is better):",
            DELTA_E_DISPLAY_FACTOR
        );
        println!("  Min:    {:6.3}", min_delta_e);
        println!("  Mean:   {:6.3}", mean_delta_e);
        println!("  Median: {:6.3}", median_delta_e);
        println!("  p75:    {:6.3}", p75_delta_e);
        println!("  p90:    {:6.3}", p90_delta_e);
        println!("  p95:    {:6.3}", p95_delta_e);
        println!("  p99:    {:6.3}", p99_delta_e);
        println!("  Max:    {:6.3}", max_delta_e);

        println!("\nPSNR Quality Metrics (higher is better, 30.0-50.0 is good):");
        println!("  Red channel:   {:6.3} dB", psnr_r);
        println!("  Green channel: {:6.3} dB", psnr_g);
        println!("  Blue channel:  {:6.3} dB", psnr_b);
        println!("  Average PSNR:  {:6.3} dB", psnr_avg);

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
                palette_index: ((raw_value >> PALETTE_INDEX_SHIFT) as usize)
                    & (self.config.num_palettes - 1),
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
    fn write_json_file(&self, path: &str, data: &TilemapData) -> Result<(), ConversionError> {
        let file = File::create(path)?;
        serde_json::to_writer_pretty(file, data)?;
        Ok(())
    }
}
