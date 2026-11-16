//! Draws the tracking symbol of Forever Quests: a ring with four marks and a dot in the middle,
//! the sight of a tracker. The picture is white on a clear background, so the addon gives it
//! its colour: grey for a quest that is not tracked, bright for one that is.
//!
//! The game reads TGA files (and its own BLP format), not PNG. The size is a power of two.

use std::fs;
use std::path::Path;

pub const SIZE: u32 = 64;
/// Sub-pixels for each pixel and direction: the edges come out smooth.
const SAMPLES: u32 = 8;

/// True inside the symbol. x and y from 0 to 64, the middle at 32.
fn inside(x: f64, y: f64) -> bool {
    let (dx, dy) = (x - 32.0, y - 32.0);
    let distance = dx.hypot(dy);
    // The ring.
    let ring = (15.5..=21.5).contains(&distance);
    // The dot in the middle.
    let dot = distance <= 6.0;
    // Four marks through the ring: up, down, left and right. Each leaves the middle free.
    let reach = (12.0..=30.0).contains(&distance);
    let mark = reach && (dx.abs() <= 2.6 || dy.abs() <= 2.6);
    ring || dot || mark
}

/// How much of each pixel the symbol covers, 0 to 255, row by row from the top.
fn coverage() -> Vec<u8> {
    let mut data = Vec::with_capacity((SIZE * SIZE) as usize);
    for y in 0..SIZE {
        for x in 0..SIZE {
            let mut hits = 0;
            for sy in 0..SAMPLES {
                for sx in 0..SAMPLES {
                    let px = f64::from(x) + (f64::from(sx) + 0.5) / f64::from(SAMPLES);
                    let py = f64::from(y) + (f64::from(sy) + 0.5) / f64::from(SAMPLES);
                    if inside(px, py) {
                        hits += 1;
                    }
                }
            }
            data.push((f64::from(hits) * 255.0 / f64::from(SAMPLES * SAMPLES)).round() as u8);
        }
    }
    data
}

/// The TGA file: 32 bits for each pixel, not compressed, the first row at the top.
pub fn tga() -> Vec<u8> {
    let size = SIZE.to_le_bytes();
    let mut file = vec![
        0, // no ID field
        0, // no colour map
        2, // true colour, not compressed
        0, 0, 0, 0, 0, // colour map: none
        0, 0, 0, 0, // the origin
        size[0], size[1], size[0], size[1], // width and height
        32,   // bits for each pixel
        0x28, // 8 bits of alpha, the first row at the top
    ];
    for alpha in coverage() {
        // Blue, green, red, alpha: white, as clear as the symbol is thin there.
        file.extend_from_slice(&[255, 255, 255, alpha]);
    }
    file
}

pub fn write(out: &Path) -> Result<(), String> {
    if let Some(parent) = out.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(out, tga()).map_err(|error| format!("Cannot write {}: {error}", out.display()))
}

/// A PNG to look at: the symbol eight times larger, grey on the left and gold on the right, on
/// the green of the COMPLETED mark.
pub fn write_preview(out: &Path) -> Result<(), String> {
    const SCALE: u32 = 8;
    let cover = coverage();
    let (width, height) = (SIZE * SCALE * 2, SIZE * SCALE);
    let mut data = Vec::with_capacity((width * height * 3) as usize);
    let back = [26.0, 128.0, 38.0];
    for y in 0..height {
        for x in 0..width {
            let tracked = x >= SIZE * SCALE;
            let alpha = f64::from(cover[((y / SCALE) * SIZE + (x % (SIZE * SCALE)) / SCALE) as usize]) / 255.0;
            let (colour, strength) = if tracked { ([255.0, 230.0, 77.0], 1.0) } else { ([140.0, 140.0, 140.0], 0.7) };
            for channel in 0..3 {
                data.push((back[channel] + (colour[channel] - back[channel]) * alpha * strength).round() as u8);
            }
        }
    }
    if let Some(parent) = out.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let file = fs::File::create(out).map_err(|error| format!("Cannot write {}: {error}", out.display()))?;
    let mut encoder = png::Encoder::new(std::io::BufWriter::new(file), width, height);
    encoder.set_color(png::ColorType::Rgb);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().map_err(|error| error.to_string())?;
    writer.write_image_data(&data).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_file_is_a_tga_of_64_by_64_with_alpha() {
        let file = tga();
        assert_eq!(file.len(), 18 + 64 * 64 * 4);
        assert_eq!((file[2], file[12], file[14], file[16], file[17]), (2, 64, 64, 32, 0x28));
    }

    #[test]
    fn the_symbol_has_a_dot_a_ring_and_clear_corners() {
        let cover = coverage();
        let at = |x: u32, y: u32| cover[(y * SIZE + x) as usize];
        assert_eq!(at(32, 32), 255, "the dot in the middle");
        assert_eq!(at(32, 14), 255, "the ring at the top");
        assert_eq!(at(22, 22), 0, "between the dot and the ring it is clear");
        assert_eq!(at(1, 1), 0, "the corner is clear");
        assert_eq!(at(32, 3), 255, "the mark at the top goes out past the ring");
        // The same on all four sides.
        assert_eq!((at(14, 32), at(50, 32), at(32, 50)), (255, 255, 255));
    }
}
