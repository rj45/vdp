use bitfield::bitfield;
use macroquad::prelude::*;

// --- Configuration ---
// Dimensions of the emulated VDP screen
const VDP_WIDTH: u32 = 960;
const VDP_HEIGHT: u32 = 540;

// How much to scale the VDP output on the main window
const SCREEN_SCALE: f32 = 2.0;

const WINDOW_WIDTH: u32 = (VDP_WIDTH as f32 * SCREEN_SCALE) as u32;
const WINDOW_HEIGHT: u32 = (VDP_HEIGHT as f32 * SCREEN_SCALE) as u32;

// tilemaps must fit into a 2K-word page

bitfield! {
    struct TilemapMetadata(u64);
    impl Debug;
    u32;

    /// Width in tiles, as a power of 2
    width, set_width: 2, 0;

    /// Address of the page containing the tilemap in VRAM
    /// This must be 2048-word (4KB) aligned, so this value is shifted left by
    /// 11 bits to get the (word) address.
    tilemap_address, set_tilemap_address: 15, 3;

    /// Extra non-displayed width expressed as a power of 2
    /// For example if size is 6 indicating a 64x64 tilemap, and extra_stride is 4 (16),
    /// then the tilemap will be effectively 80x64 with only the leftmost 64x64 being displayed.
    /// The formula is index = y << width + y << extra_stride + x
    /// This is useful for a 80-column text mode, where a 64x32 and a few 16x16 sprites can be
    /// used to display 80x32 characters.
    extra_stride, set_extra_stride: 18, 16;

    /// Address of the start of the texture in VRAM
    /// This must be 2048-word (4KB) aligned, so this value is shifted left by
    /// 11 bits to get the (word) address.
    texture_address, set_texture_address: 31, 19;


}

struct Sprite {
    y: u16,
    height: u8,
    y_flip: bool,

    x: u16,
    width: u8,
    x_flip: bool,
}

// --- Simple VDP State Simulation ---
struct VdpState {
    width: u32,
    height: u32,
    /// Represents the VDP's video memory or generated output for a frame
    frame_buffer: Vec<u8>,
    frame_count: u64, // To add some simple animation

    vram: Vec<u8>,
    tilemaps: Vec<TilemapMetadata>,
    sprites: Vec<Sprite>,
}

impl VdpState {
    fn new(width: u32, height: u32) -> Self {
        VdpState {
            width,
            height,
            // Initialize with black pixels
            frame_buffer: vec![0; (width * height * 4) as usize],
            frame_count: 0,

            vram: vec![0; 8 * 1024 * 1024], // 8MB of VRAM
            tilemaps: Vec::new(),
            sprites: Vec::new(),
        }
    }

    fn update_frame_buffer_data(&mut self) {
        self.frame_count += 1;
        let frame_count = self.frame_count;
        for y in 0..self.height {
            let row_offset = y * (self.width << 2);
            for x in 0..self.width {
                let index = (row_offset + (x << 2)) as usize;
                // Simple pattern based on coordinates and time
                let r = (((x + frame_count as u32) >> 1) & 0xff) as u8;
                let g = (((y + frame_count as u32) >> 2) & 0xff) as u8;
                let b = ((x + y + frame_count as u32) & 0xff) as u8;
                self.frame_buffer[index] = r;
                self.frame_buffer[index + 1] = g;
                self.frame_buffer[index + 2] = b;
                self.frame_buffer[index + 3] = 255;
            }
        }
    }

    fn draw_to_texture(&self, texture: &mut Texture2D) {
        texture.update_from_bytes(self.width, self.height, &self.frame_buffer);
    }

    fn texture(&self) -> Texture2D {
        let tex = Texture2D::from_rgba8(self.width as u16, self.height as u16, &self.frame_buffer);
        tex.set_filter(FilterMode::Nearest);
        tex
    }
}

fn window_conf() -> Conf {
    Conf {
        window_title: "VDP Scanline Emulator Example".to_string(),
        window_width: WINDOW_WIDTH as i32,
        window_height: WINDOW_HEIGHT as i32,
        window_resizable: false,
        ..Default::default()
    }
}

#[macroquad::main(window_conf)]
async fn main() {
    // Initialize our simulated VDP state
    let mut vdp_state = VdpState::new(VDP_WIDTH, VDP_HEIGHT);

    // let image = Image::gen_image_color(WINDOW_WIDTH as u16, WINDOW_HEIGHT as u16, BLACK);
    let mut texture = vdp_state.texture();

    loop {
        vdp_state.update_frame_buffer_data();
        vdp_state.draw_to_texture(&mut texture);

        // Draw the texture, scaling it up
        draw_texture_ex(
            &texture,
            0.0, // Draw at top-left corner of the window
            0.0,
            WHITE, // Tint (WHITE = no tint)
            DrawTextureParams {
                dest_size: Some(vec2(WINDOW_WIDTH as f32, WINDOW_HEIGHT as f32)),
                source: None, // Use the whole texture
                rotation: 0.0,
                flip_x: false,
                flip_y: false,
                pivot: None,
            },
        );

        draw_text(&format!("FPS: {}", get_fps()), 10.0, 40.0, 20.0, YELLOW);

        // Advance to the next frame
        next_frame().await
    }
}
