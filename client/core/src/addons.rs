//! Lists, installs and removes addons in an `Interface/AddOns` folder.

use std::collections::BTreeMap;
use std::fs;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::error::{Error, ErrorCode, Result};
use crate::marketplace::MarketAddon;
use crate::toc::{parse_toc, pick_toc_file};

/// File that the manager writes into each addon folder it installs.
pub const MANIFEST_FILE: &str = ".wfam.json";

/// Limit on the unpacked size of one package.
const MAX_UNPACKED_BYTES: u64 = 256 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Managed {
    pub id: String,
    pub version: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InstalledAddon {
    /// Folder name in AddOns.
    pub folder: String,
    pub title: String,
    pub version: String,
    pub interfaces: Vec<u32>,
    /// The folder is a symbolic link or junction (a development copy).
    pub linked: bool,
    /// Set when the manager installed the folder.
    pub managed: Option<Managed>,
}

fn invalid(message: impl Into<String>) -> Error {
    Error::new(ErrorCode::InvalidPackage, message)
}

/// Addon folder names are letters, digits, spaces and `_ ! . -`, and start with a letter or digit.
pub fn is_safe_folder_name(name: &str) -> bool {
    let mut chars = name.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphanumeric()) && chars.all(|c| c.is_ascii_alphanumeric() || " _!.-".contains(c))
}

fn is_link(path: &Path) -> bool {
    fs::symlink_metadata(path).map(|meta| meta.file_type().is_symlink()).unwrap_or(false)
}

fn read_manifest(folder: &Path) -> Option<Managed> {
    let text = fs::read_to_string(folder.join(MANIFEST_FILE)).ok()?;
    serde_json::from_str(&text).ok()
}

pub fn list_installed(addons_dir: &Path) -> Vec<InstalledAddon> {
    let Ok(entries) = fs::read_dir(addons_dir) else { return Vec::new() };
    let mut addons = Vec::new();
    for entry in entries.flatten() {
        let folder = entry.file_name().to_string_lossy().into_owned();
        let path = entry.path();
        if folder.starts_with('.') || !path.is_dir() {
            continue;
        }
        let Ok(files) = fs::read_dir(&path) else { continue };
        let names: Vec<String> = files.flatten().map(|file| file.file_name().to_string_lossy().into_owned()).collect();
        let Some(toc_name) = pick_toc_file(&folder, &names) else { continue };
        let Ok(bytes) = fs::read(path.join(toc_name)) else { continue };
        let toc = parse_toc(&String::from_utf8_lossy(&bytes));
        let linked = is_link(&path);
        addons.push(InstalledAddon {
            title: if toc.title.is_empty() { folder.clone() } else { toc.title },
            version: toc.version,
            interfaces: toc.interfaces,
            managed: if linked { None } else { read_manifest(&path) },
            linked,
            folder,
        });
    }
    addons.sort_by_key(|addon| addon.title.to_lowercase());
    addons
}

struct PackageFile {
    /// Path inside the addon folder, as its segments.
    relative: Vec<String>,
    data: Vec<u8>,
}

fn read_package(zip: &[u8]) -> Result<Vec<(String, Vec<u8>)>> {
    let mut archive = zip::ZipArchive::new(Cursor::new(zip)).map_err(|error| invalid(format!("The package is not a readable ZIP archive: {error}")))?;
    let mut files = Vec::new();
    let mut total = 0u64;
    for index in 0..archive.len() {
        let mut file = archive.by_index(index).map_err(|error| invalid(format!("The package has a damaged entry: {error}")))?;
        let name = file.name().to_string();
        if name.ends_with('/') {
            continue;
        }
        total = total.saturating_add(file.size());
        if total > MAX_UNPACKED_BYTES {
            return Err(invalid("The package is too large."));
        }
        let mut data = Vec::new();
        (&mut file)
            .take(MAX_UNPACKED_BYTES)
            .read_to_end(&mut data)
            .map_err(|error| invalid(format!("The package has a damaged entry ({name}): {error}")))?;
        files.push((name, data));
    }
    Ok(files)
}

/// Splits the files of a package by top-level folder and rejects unsafe paths.
fn group_by_folder(files: Vec<(String, Vec<u8>)>, allowed: &[String]) -> Result<BTreeMap<String, Vec<PackageFile>>> {
    let mut groups: BTreeMap<String, Vec<PackageFile>> = BTreeMap::new();
    for (name, data) in files {
        let segments: Vec<String> = name.replace('\\', "/").split('/').map(str::to_string).collect();
        let bad = segments.iter().any(|part| {
            part.is_empty() || part == "." || part == ".." || part.chars().any(|c| c.is_control() || ":*?\"<>|".contains(c))
        });
        if bad || segments.len() < 2 {
            return Err(invalid(format!("The package has an unsafe file path: {name}")));
        }
        let folder = &segments[0];
        if !allowed.contains(folder) {
            return Err(invalid(format!("The package has a folder that the marketplace does not list: {folder}")));
        }
        groups.entry(folder.clone()).or_default().push(PackageFile { relative: segments[1..].to_vec(), data });
    }
    for folder in allowed {
        let has_toc = groups
            .get(folder)
            .is_some_and(|files| files.iter().any(|file| file.relative.len() == 1 && file.relative[0].to_lowercase().ends_with(".toc")));
        if !has_toc {
            return Err(invalid(format!("The package has no .toc file for the folder {folder}.")));
        }
    }
    Ok(groups)
}

/// Returns whether the folder exists. Fails if the folder must not be replaced or removed.
fn check_replaceable(addons_dir: &Path, folder: &str, allow_unmanaged: bool) -> Result<bool> {
    let target = addons_dir.join(folder);
    if fs::symlink_metadata(&target).is_err() {
        return Ok(false);
    }
    if is_link(&target) {
        return Err(Error::new(
            ErrorCode::Linked,
            format!("{folder} is a link to a development copy. Remove the link first (cargo unlink-addons)."),
        ));
    }
    if !allow_unmanaged && read_manifest(&target).is_none() {
        return Err(Error::new(ErrorCode::Unmanaged, format!("{folder} is already installed, but not by this manager.")));
    }
    Ok(true)
}

fn unix_time() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|elapsed| elapsed.as_secs()).unwrap_or(0)
}

fn staging_dir(addons_dir: &Path) -> PathBuf {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|elapsed| elapsed.subsec_nanos()).unwrap_or(0);
    let parent = addons_dir.parent().unwrap_or(addons_dir);
    parent.join(format!(".wfam-staging-{:x}{:x}", std::process::id(), nanos))
}

struct Swap {
    target: PathBuf,
    backup: PathBuf,
    had_old: bool,
}

fn stage_and_swap(
    addons_dir: &Path,
    staging: &Path,
    addon: &MarketAddon,
    groups: &BTreeMap<String, Vec<PackageFile>>,
    existing: &BTreeMap<String, bool>,
    swapped: &mut Vec<Swap>,
) -> Result<()> {
    for (folder, files) in groups {
        let base = staging.join("new").join(folder);
        for file in files {
            let destination = file.relative.iter().fold(base.clone(), |path, part| path.join(part));
            if let Some(parent) = destination.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::write(destination, &file.data)?;
        }
        let manifest = serde_json::json!({ "id": addon.id, "version": addon.version, "installedAt": unix_time() });
        fs::write(base.join(MANIFEST_FILE), serde_json::to_string_pretty(&manifest)?)?;
    }
    fs::create_dir_all(staging.join("old"))?;
    for folder in &addon.folders {
        let target = addons_dir.join(folder);
        let backup = staging.join("old").join(folder);
        let had_old = existing.get(folder).copied().unwrap_or(false);
        if had_old {
            fs::rename(&target, &backup)?;
        }
        swapped.push(Swap { target: target.clone(), backup, had_old });
        fs::rename(staging.join("new").join(folder), &target)?;
    }
    Ok(())
}

/// Installs or updates an addon from a package that was already checked against its SHA-256.
///
/// The new files go to a staging folder first, and each addon folder is then swapped in
/// with a rename, so a failure does not leave a half-written addon. With `allow_unmanaged`,
/// a folder that the manager did not install is replaced too.
pub fn install_addon(addons_dir: &Path, addon: &MarketAddon, zip: &[u8], allow_unmanaged: bool) -> Result<()> {
    if let Some(folder) = addon.folders.iter().find(|folder| !is_safe_folder_name(folder)) {
        return Err(invalid(format!("Invalid addon folder name: {folder}")));
    }
    let groups = group_by_folder(read_package(zip)?, &addon.folders)?;
    let mut existing = BTreeMap::new();
    for folder in &addon.folders {
        existing.insert(folder.clone(), check_replaceable(addons_dir, folder, allow_unmanaged)?);
    }

    fs::create_dir_all(addons_dir)?;
    let staging = staging_dir(addons_dir);
    let mut swapped = Vec::new();
    let result = stage_and_swap(addons_dir, &staging, addon, &groups, &existing, &mut swapped);
    if result.is_err() {
        for swap in swapped.iter().rev() {
            let _ = fs::remove_dir_all(&swap.target);
            if swap.had_old {
                let _ = fs::rename(&swap.backup, &swap.target);
            }
        }
    }
    let _ = fs::remove_dir_all(&staging);
    result
}

/// Removes addon folders. With `allow_unmanaged`, a folder that the manager did not
/// install is removed too. A development link is never removed.
pub fn uninstall_addon(addons_dir: &Path, folders: &[String], allow_unmanaged: bool) -> Result<()> {
    let mut present = Vec::new();
    for folder in folders {
        if !is_safe_folder_name(folder) {
            return Err(invalid(format!("Invalid addon folder name: {folder}")));
        }
        if check_replaceable(addons_dir, folder, allow_unmanaged)? {
            present.push(folder);
        }
    }
    if present.is_empty() {
        return Err(Error::new(ErrorCode::NotInstalled, "The addon is not installed."));
    }
    for folder in present {
        fs::remove_dir_all(addons_dir.join(folder))?;
    }
    Ok(())
}
