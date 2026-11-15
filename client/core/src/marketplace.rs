//! Loads the marketplace index and downloads addon packages.
//!
//! The index is a JSON file. Each package URL in it is relative to the index, so the
//! same index works from a GitHub release and from a local folder.

use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::addons::is_safe_folder_name;
use crate::error::{Error, ErrorCode, Result};

pub const DEFAULT_SOURCE: &str = "https://github.com/ChristianPresley/wow-forever-addons/releases/download/marketplace/index.json";

pub const INDEX_SCHEMA: u32 = 1;

const MAX_DOWNLOAD_BYTES: u64 = 64 * 1024 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Download {
    /// Location of the package, relative to the index.
    pub url: String,
    pub sha256: String,
    #[serde(default)]
    pub size: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MarketAddon {
    pub id: String,
    pub name: String,
    pub version: String,
    #[serde(default)]
    pub category: String,
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub author: String,
    #[serde(default)]
    pub homepage: String,
    #[serde(default)]
    pub interfaces: Vec<u32>,
    /// Folders that the package puts into AddOns.
    pub folders: Vec<String>,
    pub download: Download,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Index {
    pub schema: u32,
    #[serde(default)]
    pub generated_at: Option<String>,
    pub addons: Vec<MarketAddon>,
}

enum Location {
    Https(String),
    File(PathBuf),
}

fn locate(source: &str) -> Result<Location> {
    let lower = source.to_lowercase();
    if lower.starts_with("https://") {
        Ok(Location::Https(source.to_string()))
    } else if lower.starts_with("http://") {
        Err(Error::other(format!("The marketplace must use https: {source}")))
    } else {
        Ok(Location::File(PathBuf::from(source)))
    }
}

fn read(location: &Location) -> Result<Vec<u8>> {
    match location {
        Location::File(path) => fs::read(path).map_err(|error| Error::other(format!("Cannot read {}: {error}", path.display()))),
        Location::Https(url) => {
            let response = ureq::get(url).set("User-Agent", "wow-forever-addon-manager").call().map_err(|error| match error {
                ureq::Error::Status(status, _) => Error::other(format!("Download failed with status {status}: {url}")),
                other => Error::other(format!("Download failed: {other}")),
            })?;
            let mut data = Vec::new();
            response.into_reader().take(MAX_DOWNLOAD_BYTES + 1).read_to_end(&mut data)?;
            if data.len() as u64 > MAX_DOWNLOAD_BYTES {
                return Err(Error::other(format!("The file is too large: {url}")));
            }
            Ok(data)
        }
    }
}

fn is_valid_id(id: &str) -> bool {
    let mut chars = id.chars();
    chars.next().is_some_and(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

fn is_sha256(text: &str) -> bool {
    text.len() == 64 && text.chars().all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c))
}

/// Fails if the index is not well-formed.
pub fn validate_index(index: &Index) -> Result<()> {
    if index.schema != INDEX_SCHEMA {
        return Err(Error::new(ErrorCode::InvalidPackage, "The marketplace index has an unknown format."));
    }
    for addon in &index.addons {
        let ok = is_valid_id(&addon.id)
            && !addon.name.is_empty()
            && !addon.version.is_empty()
            && !addon.folders.is_empty()
            && addon.folders.iter().all(|folder| is_safe_folder_name(folder))
            && !addon.download.url.is_empty()
            && is_sha256(&addon.download.sha256);
        if !ok {
            return Err(Error::new(ErrorCode::InvalidPackage, format!("The marketplace index has an invalid entry: {}", addon.id)));
        }
    }
    Ok(())
}

/// Loads the index from an https URL or a local path of `index.json`.
pub fn load_index(source: &str) -> Result<Index> {
    let bytes = read(&locate(source)?)?;
    let index: Index = serde_json::from_slice(&bytes)
        .map_err(|_| Error::new(ErrorCode::InvalidPackage, "The marketplace index is not valid, or it has an unknown format."))?;
    validate_index(&index)?;
    Ok(index)
}

/// Location of a package: an https URL next to an https index, or a file next to a local index.
fn package_location(source: &str, url: &str) -> Result<Location> {
    let index = locate(source)?;
    if url.contains("://") {
        return match index {
            Location::Https(_) if url.to_lowercase().starts_with("https://") => Ok(Location::Https(url.to_string())),
            _ => Err(Error::new(ErrorCode::InvalidPackage, "The package must come from the same kind of source as the index.")),
        };
    }
    let relative_ok = !url.starts_with('/') && !url.contains('\\') && url.split('/').all(|part| !part.is_empty() && part != "." && part != "..");
    if !relative_ok {
        return Err(Error::new(ErrorCode::InvalidPackage, format!("The marketplace index has an unsafe package location: {url}")));
    }
    Ok(match index {
        Location::Https(index_url) => {
            let base = index_url.rsplit_once('/').map(|(base, _)| base).unwrap_or(&index_url);
            Location::Https(format!("{base}/{url}"))
        }
        Location::File(index_path) => Location::File(index_path.parent().unwrap_or(Path::new(".")).join(url)),
    })
}

/// Downloads the package of an addon and checks it against the SHA-256 in the index.
pub fn download_package(source: &str, addon: &MarketAddon) -> Result<Vec<u8>> {
    let data = read(&package_location(source, &addon.download.url)?)?;
    let digest = format!("{:x}", Sha256::digest(&data));
    if digest != addon.download.sha256 {
        return Err(Error::new(
            ErrorCode::InvalidPackage,
            format!("The package of {} failed its checksum. It was not installed.", addon.id),
        ));
    }
    Ok(data)
}
