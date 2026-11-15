//! Finds World of Warcraft: Forever installations.
//!
//! A World of Warcraft folder holds one sub-folder for each game flavor. Forever is
//! in `_forever_`, and its `.flavor.info` file holds the product code `wowf`.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde::Serialize;

#[cfg(windows)]
const WINDOWS_SUBPATHS: [&str; 5] = [
    "World of Warcraft",
    "Games\\World of Warcraft",
    "Program Files (x86)\\World of Warcraft",
    "Program Files\\World of Warcraft",
    "Blizzard\\World of Warcraft",
];

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Install {
    /// Stable key of the install.
    pub id: String,
    /// The World of Warcraft folder.
    pub root: PathBuf,
    /// The `_forever_` folder.
    pub flavor_dir: PathBuf,
    /// Name of the flavor folder.
    pub folder: String,
    /// Battle.net product code.
    pub product: String,
    /// Client version from `.build.info`.
    pub version: Option<String>,
    /// The `Interface/AddOns` folder. It can be absent before the first launch.
    pub addons_dir: PathBuf,
}

#[derive(Debug, Default)]
pub struct DetectOptions {
    /// Folders that the user added by hand.
    pub extra_roots: Vec<PathBuf>,
    /// Replaces the automatic search (used by tests).
    pub roots: Option<Vec<PathBuf>>,
}

/// Product code from a flavor folder's `.flavor.info`.
pub fn parse_flavor_info(text: &str) -> Option<String> {
    text.lines().map(str::trim).filter(|line| !line.is_empty()).nth(1).map(str::to_string)
}

/// Map of product code to version from a `.build.info` file.
pub fn parse_build_info(text: &str) -> HashMap<String, String> {
    let mut versions = HashMap::new();
    let mut lines = text.lines().filter(|line| !line.trim().is_empty());
    let Some(header) = lines.next() else { return versions };
    let columns: Vec<&str> = header.split('|').map(|column| column.split('!').next().unwrap_or("").trim()).collect();
    let product = columns.iter().position(|column| *column == "Product");
    let version = columns.iter().position(|column| *column == "Version");
    let (Some(product), Some(version)) = (product, version) else { return versions };
    for line in lines {
        let cells: Vec<&str> = line.split('|').collect();
        if let Some(code) = cells.get(product).filter(|code| !code.trim().is_empty()) {
            versions.insert(code.trim().to_string(), cells.get(version).unwrap_or(&"").trim().to_string());
        }
    }
    versions
}

fn looks_like_path(text: &str) -> bool {
    let bytes = text.as_bytes();
    let rooted = text.starts_with('/')
        || (bytes.len() > 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' && (bytes[2] == b'\\' || bytes[2] == b'/'));
    rooted
        && (4..=260).contains(&text.chars().count())
        && !text.chars().skip(2).any(|c| c.is_control() || "\"<>|?*:".contains(c))
}

fn read_varint(buf: &[u8], pos: &mut usize) -> Option<u64> {
    let mut value = 0u64;
    for i in 0..10 {
        let byte = *buf.get(*pos)?;
        *pos += 1;
        if i < 9 {
            value |= u64::from(byte & 0x7f) << (7 * i);
        }
        if byte & 0x80 == 0 {
            return Some(value);
        }
    }
    None
}

/// Visits a protobuf message without its schema. Returns false if the bytes are not a
/// well-formed message.
fn walk_message(buf: &[u8], depth: usize, found: &mut BTreeSet<String>) -> bool {
    let mut pos = 0;
    let mut chunks = Vec::new();
    while pos < buf.len() {
        let Some(tag) = read_varint(buf, &mut pos) else { return false };
        if tag >> 3 == 0 {
            return false;
        }
        match tag & 7 {
            0 => {
                if read_varint(buf, &mut pos).is_none() {
                    return false;
                }
            }
            1 => pos += 8,
            5 => pos += 4,
            2 => {
                let Some(length) = read_varint(buf, &mut pos) else { return false };
                let Some(end) = usize::try_from(length).ok().and_then(|length| pos.checked_add(length)) else { return false };
                if end > buf.len() {
                    return false;
                }
                chunks.push(&buf[pos..end]);
                pos = end;
            }
            _ => return false,
        }
        if pos > buf.len() {
            return false;
        }
    }
    for chunk in chunks {
        match std::str::from_utf8(chunk) {
            Ok(text) if looks_like_path(text) => {
                found.insert(text.to_string());
            }
            _ => {
                if depth < 8 && chunk.len() > 1 {
                    walk_message(chunk, depth + 1, found);
                }
            }
        }
    }
    true
}

/// Collects the path strings from Battle.net's `product.db`, which is a protobuf message.
pub fn extract_paths_from_product_db(buffer: &[u8]) -> Vec<String> {
    let mut found = BTreeSet::new();
    walk_message(buffer, 0, &mut found);
    found.into_iter().collect()
}

#[cfg(windows)]
fn candidate_roots() -> Vec<PathBuf> {
    use winreg::enums::HKEY_LOCAL_MACHINE;
    use winreg::RegKey;

    let mut candidates = Vec::new();
    let program_data = std::env::var("ProgramData").unwrap_or_else(|_| "C:\\ProgramData".to_string());
    if let Ok(db) = fs::read(Path::new(&program_data).join("Battle.net").join("Agent").join("product.db")) {
        candidates.extend(extract_paths_from_product_db(&db).into_iter().map(PathBuf::from));
    }
    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    for key in [
        "SOFTWARE\\WOW6432Node\\Blizzard Entertainment\\World of Warcraft",
        "SOFTWARE\\Blizzard Entertainment\\World of Warcraft",
    ] {
        if let Ok(path) = hklm.open_subkey(key).and_then(|key| key.get_value::<String, _>("InstallPath")) {
            candidates.push(PathBuf::from(path));
        }
    }
    for letter in 'C'..='Z' {
        let drive = PathBuf::from(format!("{letter}:\\"));
        if drive.exists() {
            candidates.extend(WINDOWS_SUBPATHS.iter().map(|sub| drive.join(sub)));
        }
    }
    candidates
}

#[cfg(not(windows))]
fn candidate_roots() -> Vec<PathBuf> {
    let home = PathBuf::from(std::env::var("HOME").unwrap_or_default());
    if cfg!(target_os = "macos") {
        vec![PathBuf::from("/Applications/World of Warcraft"), home.join("Applications/World of Warcraft")]
    } else {
        vec![
            home.join("Games/world-of-warcraft/drive_c/Program Files (x86)/World of Warcraft"),
            home.join(".wine/drive_c/Program Files (x86)/World of Warcraft"),
        ]
    }
}

fn is_flavor_folder(name: &str) -> bool {
    name.len() > 2 && name.starts_with('_') && name.ends_with('_')
}

/// Returns the Forever installs under one World of Warcraft folder.
pub fn inspect_root(root: &Path) -> Vec<Install> {
    let Ok(entries) = fs::read_dir(root) else { return Vec::new() };
    let versions = fs::read_to_string(root.join(".build.info")).map(|text| parse_build_info(&text)).unwrap_or_default();
    let mut installs = Vec::new();
    for entry in entries.flatten() {
        let folder = entry.file_name().to_string_lossy().into_owned();
        let flavor_dir = entry.path();
        if !is_flavor_folder(&folder) || !flavor_dir.is_dir() {
            continue;
        }
        let product = fs::read_to_string(flavor_dir.join(".flavor.info")).ok().and_then(|text| parse_flavor_info(&text));
        let is_forever = match &product {
            Some(code) => code.to_lowercase().starts_with("wowf"),
            None => folder.to_lowercase().starts_with("_forever"),
        };
        if !is_forever {
            continue;
        }
        installs.push(Install {
            id: flavor_dir.to_string_lossy().to_lowercase(),
            root: root.to_path_buf(),
            addons_dir: flavor_dir.join("Interface").join("AddOns"),
            version: product.as_ref().and_then(|code| versions.get(code)).filter(|version| !version.is_empty()).cloned(),
            product: product.unwrap_or_else(|| "wowf".to_string()),
            folder,
            flavor_dir,
        });
    }
    installs.sort_by(|a, b| a.id.cmp(&b.id));
    installs
}

fn absolute(path: &Path) -> PathBuf {
    std::path::absolute(path).unwrap_or_else(|_| path.to_path_buf())
}

/// The folder and its nearest parents, `count` folders in all. A folder that the user
/// picks can be the World of Warcraft folder, the `_forever_` folder, or a folder in it.
fn with_parents(folder: &Path, count: usize) -> Vec<PathBuf> {
    absolute(folder).ancestors().take(count).map(Path::to_path_buf).collect()
}

pub fn detect_installs(options: &DetectOptions) -> Vec<Install> {
    let candidates = options.roots.clone().unwrap_or_else(candidate_roots);
    let mut expanded = Vec::new();
    for candidate in &candidates {
        expanded.extend(with_parents(candidate, 2));
    }
    for extra in &options.extra_roots {
        expanded.extend(with_parents(extra, 4));
    }

    let mut seen = HashSet::new();
    let mut installs: Vec<Install> = Vec::new();
    for candidate in expanded {
        if !seen.insert(candidate.to_string_lossy().to_lowercase()) {
            continue;
        }
        for install in inspect_root(&candidate) {
            if !installs.iter().any(|known| known.id == install.id) {
                installs.push(install);
            }
        }
    }
    installs
}
