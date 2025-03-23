// Written by GPT-4 with plain english prompts.... no idea how
// copyright works in that case.
//
// Gouldian_Finch_256x256.png is public domain photo by Bernard Spragg

#![feature(portable_simd)]

use std::fs::File;
use std::io::Write;
use std::simd::num::SimdFloat;
use std::simd::{LaneCount, Simd, StdFloat, SupportedLaneCount};

use image::{GenericImageView, Pixel};
use kmeans::{DistanceFunction, KMeans, KMeansConfig};
use oklab::{srgb_to_oklab, Oklab};

const JUST_NOTICEABLE_DIFFERENCE: f32 = 0.005;

#[derive(Debug, Clone, Copy)]
struct ColorFrequency {
    color: Oklab,
    frequency: usize,
}

impl Default for ColorFrequency {
    fn default() -> Self {
        ColorFrequency {
            color: Oklab {
                l: 0.0,
                a: 0.0,
                b: 0.0,
            },
            frequency: 0,
        }
    }
}

fn oklab_delta_e(a: Oklab, b: Oklab) -> f32 {
    // ΔL = L1 - L2
    // C1 = √(a1² + b1²)
    // C2 = √(a2² + b2²)
    // ΔC = C1 - C2
    // Δa = a1 - a2
    // Δb = b1 - b2
    // ΔH = √(|Δa² + Δb² - ΔC²|)
    // ΔEOK = √(ΔL² + ΔC² + ΔH²)
    let delta_l = a.l - b.l;
    let c1 = (a.a * a.a + a.b * a.b).sqrt();
    let c2 = (b.a * b.a + b.b * b.b).sqrt();
    let delta_c = c1 - c2;
    let delta_a = a.a - b.a;
    let delta_b = a.b - b.b;
    let delta_h = (delta_a * delta_a + delta_b * delta_b - delta_c * delta_c)
        .abs()
        .sqrt();
    (delta_l * delta_l + delta_c * delta_c + delta_h * delta_h).sqrt()
}

fn extract_colors(tile: [Oklab; 64], threshold: f32, colors: &mut Vec<ColorFrequency>) {
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

struct OklabDistance;

impl<const LANES: usize> DistanceFunction<f32, LANES> for OklabDistance
where
    LaneCount<LANES>: SupportedLaneCount,
{
    #[inline(always)]
    fn distance(&self, a: &[f32], b: &[f32]) -> f32 {
        let a_len = a.len() / 3;
        let b_len = b.len() / 3;

        let a_l = a[0..a_len].chunks_exact(LANES).map(|i| Simd::from_slice(i));
        let a_a = a[a_len..2 * a_len]
            .chunks_exact(LANES)
            .map(|i| Simd::from_slice(i));
        let a_b = a[2 * a_len..]
            .chunks_exact(LANES)
            .map(|i| Simd::from_slice(i));

        let b_l = b[0..b_len].chunks_exact(LANES).map(|i| Simd::from_slice(i));
        let b_a = b[b_len..2 * b_len]
            .chunks_exact(LANES)
            .map(|i| Simd::from_slice(i));
        let b_b = b[2 * b_len..]
            .chunks_exact(LANES)
            .map(|i| Simd::from_slice(i));

        // ΔL = L1 - L2
        // C1 = √(a1² + b1²)
        // C2 = √(a2² + b2²)
        // ΔC = C1 - C2
        // Δa = a1 - a2
        // Δb = b1 - b2
        // ΔH = √(|Δa² + Δb² - ΔC²|)
        // ΔEOK = √(ΔL² + ΔC² + ΔH²)

        let delta_l = a_l.zip(b_l).map(|(a_l, b_l)| a_l - b_l);
        let c1 = a_a
            .clone()
            .zip(a_b.clone())
            .map(|(a_a, a_b)| (a_a * a_a + a_b * a_b).sqrt());
        let c2 = b_a
            .clone()
            .zip(b_b.clone())
            .map(|(b_a, b_b)| (b_a * b_a + b_b * b_b).sqrt());
        let delta_c = c1.zip(c2).map(|(c1, c2)| c1 - c2);
        let delta_a = a_a.zip(b_a).map(|(a_a, b_a)| a_a - b_a);
        let delta_b = a_b.zip(b_b).map(|(a_b, b_b)| a_b - b_b);
        let sum_delta_a_b = delta_a
            .zip(delta_b)
            .map(|(delta_a, delta_b)| delta_a * delta_a + delta_b * delta_b);
        let delta_h = sum_delta_a_b
            .zip(delta_c.clone())
            .map(|(sum_delta_a_b, delta_c)| (sum_delta_a_b - delta_c * delta_c).abs().sqrt());
        let sum_delta_l_c = delta_l
            .zip(delta_c)
            .map(|(delta_l, delta_c)| delta_l * delta_l + delta_c * delta_c);
        let delta_e = sum_delta_l_c
            .zip(delta_h)
            .map(|(sum_delta_l_c, delta_h)| (sum_delta_l_c + delta_h * delta_h).sqrt());
        delta_e.map(|e| e.reduce_sum()).sum()
    }
}

fn main() {
    // Read the PNG file.
    let img = image::open("imgconv/Gouldian_Finch_256x256.png").unwrap();

    let tile_map_width = img.width() / 8;
    let tile_map_height = img.height() / 8;
    println!(
        "tile_map width: {}, height: {}",
        tile_map_width, tile_map_height,
    );

    // Image must be have a width and height that are multiples of the tile size
    assert!(img.width() % 8 == 0);
    assert!(img.height() % 8 == 0);

    let mut tiles: Vec<[Oklab; 64]> =
        Vec::with_capacity((tile_map_width * tile_map_height) as usize);
    for _ in 0..(tile_map_width * tile_map_height) {
        let tile: [Oklab; 64] = [Oklab {
            l: 0.0,
            a: 0.0,
            b: 0.0,
        }; 64];
        tiles.push(tile);
    }

    // Loop through the pixels in the image, split into 8x8 tiles and convert to oklab.
    for (x, y, pixel) in img.pixels() {
        let tile_map_x = x / 8;
        let tile_map_y = y / 8;
        let tile_x = x % 8;
        let tile_y = y % 8;

        // Convert the pixel to oklab.
        let channels = pixel.channels();
        let oklab = srgb_to_oklab(oklab::Rgb {
            r: channels[0],
            g: channels[1],
            b: channels[2],
        });

        // Store the oklab value in the tile.
        let tile_index = (tile_map_y * tile_map_width + tile_map_x) as usize;
        tiles[tile_index][(tile_y * 8 + tile_x) as usize] = oklab;
    }

    let mut cluster_data = Vec::new();
    for tile in tiles.iter() {
        let mut hue_sorted = *tile;
        hue_sorted.sort_by(|a, b| {
            let a_hue = a.b.atan2(a.a);
            let b_hue = b.b.atan2(b.a);
            a_hue.partial_cmp(&b_hue).unwrap()
        });

        // store every permutation of the tile in the cluster data
        for offset in 0..64 {
            for i in 0..64 {
                cluster_data.push(hue_sorted[(i + offset) % 64].l);
            }
        }
        for offset in 0..64 {
            for i in 0..64 {
                cluster_data.push(hue_sorted[(i + offset) % 64].a);
            }
        }
        for offset in 0..64 {
            for i in 0..64 {
                cluster_data.push(hue_sorted[(i + offset) % 64].b);
            }
        }
    }

    let kmean: KMeans<_, 8, _> = KMeans::new(cluster_data, tiles.len(), 64 * 64 * 3, OklabDistance);
    let result = kmean.kmeans_lloyd(
        32,
        10000,
        KMeans::init_kmeanplusplus,
        &KMeansConfig::default(),
    );

    let mut colors = Vec::new();
    for _ in 0..32 {
        colors.push(Vec::new());
    }
    for y in 0..32 {
        for x in 0..32 {
            let tile_index = y * 32 + x;
            let assignment = result.assignments[tile_index];
            extract_colors(
                tiles[tile_index],
                JUST_NOTICEABLE_DIFFERENCE,
                &mut colors[assignment],
            );
        }
    }

    let mut palettes = Vec::new();
    let mut min_colors = usize::MAX;
    let mut max_colors = 0;
    for color_frequencies in colors.iter_mut() {
        let num_colors = color_frequencies.len();
        if num_colors < min_colors {
            min_colors = num_colors;
        }
        if num_colors > max_colors {
            max_colors = num_colors;
        }
        color_frequencies.sort_by(|a, b| b.frequency.cmp(&a.frequency));
        color_frequencies.reverse();

        if color_frequencies.len() > 16 {
            // do kmeans on the colors to reduce them to 16
            let mut cluster_data = Vec::new();
            for color_frequency in color_frequencies.iter() {
                cluster_data.push(color_frequency.color.l);
                cluster_data.push(color_frequency.color.a);
                cluster_data.push(color_frequency.color.b);
            }
            let kmean: KMeans<_, 1, _> =
                KMeans::new(cluster_data, color_frequencies.len(), 3, OklabDistance);
            let result = kmean.kmeans_lloyd(
                16,
                100000,
                KMeans::init_kmeanplusplus,
                &KMeansConfig::default(),
            );
            let mut new_colors = [ColorFrequency::default(); 16];
            for (i, color) in color_frequencies.iter().enumerate() {
                let assignment = result.assignments[i];
                new_colors[assignment].color.l += color.color.l * color.frequency as f32;
                new_colors[assignment].color.a += color.color.a * color.frequency as f32;
                new_colors[assignment].color.b += color.color.b * color.frequency as f32;
                new_colors[assignment].frequency += color.frequency;
            }
            for color in new_colors.iter_mut() {
                color.color.l /= color.frequency as f32;
                assert!(!color.color.l.is_nan());
                color.color.a /= color.frequency as f32;
                assert!(!color.color.a.is_nan());
                color.color.b /= color.frequency as f32;
                assert!(!color.color.b.is_nan());
            }
            new_colors.sort_by(|a, b| a.color.l.partial_cmp(&b.color.l).unwrap());
            let mut total_error = 0.0;
            for (i, color) in color_frequencies.iter().enumerate() {
                let assignment = result.assignments[i];
                let error = oklab_delta_e(color.color, new_colors[assignment].color)
                    * color.frequency as f32;
                assert!(!error.is_nan());
                total_error += error;
            }
            println!("Error: {} {}", result.distsum, total_error);
            palettes.push(new_colors.to_vec());
        } else {
            println!("A palette with {} colors", color_frequencies.len());
            color_frequencies.sort_by(|a, b| a.color.l.partial_cmp(&b.color.l).unwrap());
            palettes.push(color_frequencies.clone());
        }
    }
    println!("min_colors: {}, max_colors: {}", min_colors, max_colors);
    palettes.sort_by(|a, b| {
        let a_avg_l = a.iter().map(|color| color.color.l).sum::<f32>() / a.len() as f32;
        let b_avg_l = b.iter().map(|color| color.color.l).sum::<f32>() / b.len() as f32;
        a_avg_l.partial_cmp(&b_avg_l).unwrap()
    });

    let mut max_tile_error = 0.0;
    let mut tile_palette = Vec::new();
    for y in 0..32 {
        for x in 0..32 {
            let tile_index = y * 32 + x;
            // find which palette has the least error
            let mut min_error = f32::MAX;
            let mut min_palette = 0;
            for (i, palette) in palettes.iter().enumerate() {
                let mut error = 0.0;
                for color in tiles[tile_index].iter() {
                    let mut min_delta_e = f32::MAX;
                    for palette_color in palette.iter() {
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

    println!("max_tile_error: {}", max_tile_error / 32.0 / 32.0);

    let mut palette_file = File::create("rtl/palette.hex").unwrap();

    for palette in palettes.iter() {
        for color in palette.iter() {
            let rgb = oklab::oklab_to_srgb(color.color);
            write!(
                &mut palette_file,
                "{:02x}{:02x}{:02x} ",
                rgb.r, rgb.g, rgb.b
            )
            .unwrap();
        }
        for _ in palette.len()..16 {
            write!(&mut palette_file, "000000 ").unwrap();
        }
        writeln!(&mut palette_file).unwrap();
    }

    let mut quantized_tiles = Vec::new();
    let mut error = Vec::new();
    for _ in 0..32 {
        for _ in 0..32 {
            quantized_tiles.push([0u16; 16]);
            for _ in 0..64 {
                error.push(Oklab {
                    l: 0.0,
                    a: 0.0,
                    b: 0.0,
                });
            }
        }
    }
    for y in 0..32 {
        for ty in 0..8 {
            for x in 0..32 {
                let tile_index = y * 32 + x;
                let palette = &palettes[tile_palette[tile_index]];
                let out_tile = quantized_tiles.get_mut(tile_index).unwrap();
                let tile = tiles.get(tile_index).unwrap();
                for tx in 0..8 {
                    let i = (ty * 8) + tx;
                    let gy = (y * 8) + ty;
                    let gx = (x * 8) + tx;
                    let color = Oklab {
                        l: tile[i].l + error[gy * 256 + gx].l,
                        a: tile[i].a + error[gy * 256 + gx].a,
                        b: tile[i].b + error[gy * 256 + gx].b,
                    };
                    let mut min_delta_e = f32::MAX;
                    let mut min_index = 0;
                    for (j, palette_color) in palette.iter().enumerate() {
                        let delta_e = oklab_delta_e(color, palette_color.color);
                        if delta_e < min_delta_e {
                            min_delta_e = delta_e;
                            min_index = j;
                        }
                    }
                    out_tile[i / 4] |= (min_index as u16) << ((i % 4) * 4);

                    // apply sierra dithering
                    let diff = Oklab {
                        l: ((color.l - palette[min_index].color.l) / 32.0) * 0.75,
                        a: ((color.a - palette[min_index].color.a) / 32.0) * 0.75,
                        b: ((color.b - palette[min_index].color.b) / 32.0) * 0.75,
                    };

                    if gx < 255 {
                        error[gy * 256 + gx + 1].l += diff.l * 5.0;
                        error[gy * 256 + gx + 1].a += diff.a * 5.0;
                        error[gy * 256 + gx + 1].b += diff.b * 5.0;
                    }
                    if gx < 254 {
                        error[gy * 256 + gx + 2].l += diff.l * 3.0;
                        error[gy * 256 + gx + 2].a += diff.a * 3.0;
                        error[gy * 256 + gx + 2].b += diff.b * 3.0;
                    }
                    if gy < 255 {
                        if gx > 1 {
                            error[(gy + 1) * 256 + gx - 2].l += diff.l * 2.0;
                            error[(gy + 1) * 256 + gx - 2].a += diff.a * 2.0;
                            error[(gy + 1) * 256 + gx - 2].b += diff.b * 2.0;
                        }
                        if gx > 0 {
                            error[(gy + 1) * 256 + gx - 1].l += diff.l * 4.0;
                            error[(gy + 1) * 256 + gx - 1].a += diff.a * 4.0;
                            error[(gy + 1) * 256 + gx - 1].b += diff.b * 4.0;
                        }
                        error[(gy + 1) * 256 + gx].l += diff.l * 5.0;
                        error[(gy + 1) * 256 + gx].a += diff.a * 5.0;
                        error[(gy + 1) * 256 + gx].b += diff.b * 5.0;
                        if gx < 255 {
                            error[(gy + 1) * 256 + gx + 1].l += diff.l * 4.0;
                            error[(gy + 1) * 256 + gx + 1].a += diff.a * 4.0;
                            error[(gy + 1) * 256 + gx + 1].b += diff.b * 4.0;
                        }
                        if gx < 254 {
                            error[(gy + 1) * 256 + gx + 2].l += diff.l * 2.0;
                            error[(gy + 1) * 256 + gx + 2].a += diff.a * 2.0;
                            error[(gy + 1) * 256 + gx + 2].b += diff.b * 2.0;
                        }
                    }
                    if gy < 254 {
                        if gx > 0 {
                            error[(gy + 2) * 256 + gx - 1].l += diff.l * 2.0;
                            error[(gy + 2) * 256 + gx - 1].a += diff.a * 2.0;
                            error[(gy + 2) * 256 + gx - 1].b += diff.b * 2.0;
                        }
                        error[(gy + 2) * 256 + gx].l += diff.l * 3.0;
                        error[(gy + 2) * 256 + gx].a += diff.a * 3.0;
                        error[(gy + 2) * 256 + gx].b += diff.b * 3.0;
                        if gx < 255 {
                            error[(gy + 2) * 256 + gx + 1].l += diff.l * 2.0;
                            error[(gy + 2) * 256 + gx + 1].a += diff.a * 2.0;
                            error[(gy + 2) * 256 + gx + 1].b += diff.b * 2.0;
                        }
                    }
                }
            }
        }
    }

    let mut out_tile_map = Vec::new();
    for y in 0..32 {
        for x in 0..32 {
            let tile_index = y * 32 + x;
            out_tile_map.push((tile_palette[tile_index] << 10) as u16);
        }
    }

    let mut tile_map_file = File::create("rtl/tile_map.hex").unwrap();
    let mut tile_data_file = File::create("rtl/tiles.hex").unwrap();

    for y in 0..32 {
        for ty in 0..8 {
            for x in 0..32 {
                let tile_index = y * 32 + x;
                let tile = quantized_tiles[tile_index];
                for tx in 0..2 {
                    write!(&mut tile_data_file, "{:04x} ", tile[ty * 2 + tx]).unwrap();
                }
            }
            writeln!(&mut tile_data_file).unwrap();
        }
    }

    for (i, item) in out_tile_map.iter().enumerate() {
        write!(&mut tile_map_file, "{:04x} ", item).unwrap();
        if i % 32 == 31 {
            writeln!(&mut tile_map_file).unwrap();
        }
    }

    let mut out_img = image::ImageBuffer::new(256, 256);
    for y in 0..32 {
        for x in 0..32 {
            let tile_index = y * 32 + x;
            let map_entry = out_tile_map[tile_index];
            let tile_pal = ((map_entry >> 10) as usize) & 31;
            let palette = &palettes[tile_pal];
            for (i, color) in quantized_tiles[tile_index].iter().enumerate() {
                for si in 0..4 {
                    let min_index = ((*color >> (si * 4)) & 15) as usize;
                    let palette_color = palette[min_index].color;
                    let rgb = oklab::oklab_to_srgb(palette_color);
                    out_img.put_pixel(
                        (x * 8 + ((i % 2) * 4) + si) as u32,
                        ((y * 8) + (i / 2)) as u32,
                        image::Rgb([rgb.r, rgb.g, rgb.b]),
                    );
                }
            }
        }
    }
    out_img.save("imgconv/out.png").unwrap();
}
