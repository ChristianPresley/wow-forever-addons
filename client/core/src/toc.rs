//! Reader for WoW addon `.toc` files.

use std::collections::BTreeMap;

/// Interface number of the WoW: Forever client (1.60.x).
pub const FOREVER_INTERFACE: u32 = 16001;

/// TOC name suffixes that the Forever client loads in preference to the plain file.
const FOREVER_SUFFIXES: [&str; 5] = ["_Camelot", "-Camelot", "_Forever", "-Forever", ""];

#[derive(Debug, Default)]
pub struct Toc {
    pub fields: BTreeMap<String, String>,
    /// Files that the TOC loads, with forward slashes.
    pub files: Vec<String>,
    pub interfaces: Vec<u32>,
    /// `## Title` without colour codes.
    pub title: String,
    /// `## Version` without colour codes.
    pub version: String,
}

pub fn parse_toc(text: &str) -> Toc {
    let mut toc = Toc::default();
    for raw in text.trim_start_matches('\u{feff}').lines() {
        let line = raw.trim();
        if line.is_empty() {
            continue;
        }
        if let Some(rest) = line.strip_prefix("##") {
            if let Some((key, value)) = rest.split_once(':') {
                toc.fields.insert(key.trim().to_string(), value.trim().to_string());
            }
        } else if !line.starts_with('#') {
            toc.files.push(line.replace('\\', "/"));
        }
    }
    toc.interfaces = toc
        .fields
        .get("Interface")
        .map(|value| value.split(',').filter_map(|part| part.trim().parse().ok()).collect())
        .unwrap_or_default();
    toc.title = strip_escapes(toc.fields.get("Title").map(String::as_str).unwrap_or(""));
    toc.version = strip_escapes(toc.fields.get("Version").map(String::as_str).unwrap_or(""));
    toc
}

/// Removes WoW colour (`|cAARRGGBB`, `|r`) and texture (`|T...|t`) escape codes.
pub fn strip_escapes(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '|' && i + 1 < chars.len() {
            match chars[i + 1] {
                'r' => {
                    i += 2;
                    continue;
                }
                'c' if i + 10 <= chars.len() && chars[i + 2..i + 10].iter().all(char::is_ascii_hexdigit) => {
                    i += 10;
                    continue;
                }
                'T' => {
                    let end = (i + 2..chars.len().saturating_sub(1)).find(|&j| chars[j] == '|' && chars[j + 1] == 't');
                    if let Some(end) = end {
                        i = end + 2;
                        continue;
                    }
                }
                _ => {}
            }
        }
        out.push(chars[i]);
        i += 1;
    }
    out.trim().to_string()
}

/// Picks the TOC file that the Forever client would load for an addon folder.
pub fn pick_toc_file(folder: &str, file_names: &[String]) -> Option<String> {
    let tocs: Vec<&String> = file_names.iter().filter(|name| name.to_lowercase().ends_with(".toc")).collect();
    for suffix in FOREVER_SUFFIXES {
        let wanted = format!("{folder}{suffix}.toc").to_lowercase();
        if let Some(name) = tocs.iter().find(|name| name.to_lowercase() == wanted) {
            return Some((*name).clone());
        }
    }
    tocs.first().map(|name| (*name).clone())
}
