//! Draws the source image of the app icon: a gold tile with a dark "F".
//! After a change, make the icon set with: cargo tauri icon <out.png>

use std::fs::File;
use std::io::BufWriter;
use std::path::Path;

pub const SIZE: u32 = 1024;

const RADIUS: f64 = 200.0;
const MARGIN: f64 = 64.0;

/// Coverage (0 to 1) of the rounded square at a pixel, with a soft edge.
fn tile(x: f64, y: f64) -> f64 {
    let lo = MARGIN + RADIUS;
    let hi = f64::from(SIZE) - MARGIN - RADIUS;
    let distance = |v: f64| if v < lo { lo - v } else if v > hi { v - hi } else { 0.0 };
    (RADIUS - distance(x).hypot(distance(y)) + 0.5).clamp(0.0, 1.0)
}

/// True inside the letter F.
fn letter(x: u32, y: u32) -> bool {
    let stem = (352..472).contains(&x) && (272..752).contains(&y);
    let top = (352..712).contains(&x) && (272..384).contains(&y);
    let middle = (352..640).contains(&x) && (468..568).contains(&y);
    stem || top || middle
}

/// A colour channel of the gradient from the top-left (`from`) to the bottom-right corner (`to`).
fn blend(from: u8, to: u8, t: f64) -> u8 {
    (f64::from(from) + (f64::from(to) - f64::from(from)) * t).round() as u8
}

fn pixels() -> Vec<u8> {
    let mut data = Vec::with_capacity((SIZE * SIZE * 4) as usize);
    for y in 0..SIZE {
        for x in 0..SIZE {
            let t = f64::from(x + y) / f64::from(2 * SIZE);
            let rgb = if letter(x, y) { [0x1a, 0x14, 0x08] } else { [blend(0xec, 0xa9, t), blend(0xc0, 0x77, t), blend(0x78, 0x2f, t)] };
            data.extend_from_slice(&rgb);
            data.push((255.0 * tile(f64::from(x), f64::from(y))).round() as u8);
        }
    }
    data
}

pub fn write(out: &Path) -> Result<(), String> {
    let file = File::create(out).map_err(|error| format!("Cannot write {}: {error}", out.display()))?;
    let mut encoder = png::Encoder::new(BufWriter::new(file), SIZE, SIZE);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().map_err(|error| error.to_string())?;
    writer.write_image_data(&pixels()).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_corners_are_clear_and_the_letter_is_dark() {
        let data = pixels();
        let at = |x: u32, y: u32| {
            let i = ((y * SIZE + x) * 4) as usize;
            [data[i], data[i + 1], data[i + 2], data[i + 3]]
        };
        assert_eq!(at(0, 0)[3], 0, "the corner is transparent");
        assert_eq!(at(400, 300), [0x1a, 0x14, 0x08, 255], "inside the letter");
        assert_eq!(at(800, 800)[3], 255, "inside the tile");
        assert!(at(800, 800)[0] > 0x80, "the tile is gold");
    }
}
