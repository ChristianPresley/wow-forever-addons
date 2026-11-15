//! Reads the addons in the `addons/` folder of this repository.

use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use wfam_core::toc::{parse_toc, Toc};

/// File with the marketplace text. It stays in the repository and does not go into a package.
const META_FILE: &str = "addon.json";

/// The marketplace text of an addon, from its `addon.json`.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Meta {
    pub id: String,
    pub category: String,
    pub summary: String,
    pub description: String,
}

#[derive(Debug)]
pub struct Addon {
    /// Folder name, which is also the name of the TOC file.
    pub folder: String,
    pub dir: PathBuf,
    /// `None` if `<folder>.toc` is missing.
    pub toc: Option<Toc>,
    /// `None` if `addon.json` is missing or is not valid JSON.
    pub meta: Option<Meta>,
    /// The files that go into the package: paths inside the folder, with forward slashes, sorted.
    pub files: Vec<String>,
}

fn sorted_entries(dir: &Path) -> Result<Vec<fs::DirEntry>, String> {
    let entries = fs::read_dir(dir).map_err(|error| format!("Cannot read {}: {error}", dir.display()))?;
    let mut entries: Vec<fs::DirEntry> = entries.flatten().collect();
    entries.sort_by_key(|entry| entry.file_name());
    Ok(entries)
}

fn walk(dir: &Path, prefix: &str, files: &mut Vec<String>) -> Result<(), String> {
    for entry in sorted_entries(dir)? {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') || (prefix.is_empty() && name == META_FILE) {
            continue;
        }
        let relative = if prefix.is_empty() { name } else { format!("{prefix}/{name}") };
        if entry.path().is_dir() {
            walk(&entry.path(), &relative, files)?;
        } else {
            files.push(relative);
        }
    }
    Ok(())
}

pub fn read_addons(addons_dir: &Path) -> Result<Vec<Addon>, String> {
    let mut addons = Vec::new();
    for entry in sorted_entries(addons_dir)? {
        let dir = entry.path();
        if !dir.is_dir() {
            continue;
        }
        let folder = entry.file_name().to_string_lossy().into_owned();
        let toc = fs::read(dir.join(format!("{folder}.toc"))).ok().map(|bytes| parse_toc(&String::from_utf8_lossy(&bytes)));
        let meta = fs::read(dir.join(META_FILE)).ok().and_then(|bytes| serde_json::from_slice(&bytes).ok());
        let mut files = Vec::new();
        walk(&dir, "", &mut files)?;
        addons.push(Addon { folder, dir, toc, meta, files });
    }
    Ok(addons)
}

#[cfg(test)]
pub mod testing {
    use super::*;

    /// Writes an addon folder with a TOC, one Lua file and an `addon.json`.
    pub fn write_addon(addons_dir: &Path, folder: &str, id: &str, lua: &str) {
        let dir = addons_dir.join(folder);
        fs::create_dir_all(dir.join("lib")).unwrap();
        let toc = format!(
            "## Interface: 16001\n## Title: {folder}\n## Version: 1.2.3\n## Author: Tester\n\nCore.lua\nlib\\Util.lua\nSettingsKit.lua\nSettings.lua\n"
        );
        fs::write(dir.join(format!("{folder}.toc")), toc).unwrap();
        fs::write(dir.join("Core.lua"), lua).unwrap();
        fs::write(dir.join("SettingsKit.lua"), "local _, ns = ...\nfunction ns.NewSettingsPage() end\n").unwrap();
        fs::write(dir.join("Settings.lua"), "local _, ns = ...\nlocal page = ns.NewSettingsPage(\"Test\")\npage:Register()\n").unwrap();
        fs::write(dir.join("lib").join("Util.lua"), "local _, ns = ...\nns.util = true\n").unwrap();
        fs::write(dir.join(".hidden"), "not packaged").unwrap();
        let meta = format!(r#"{{"id":"{id}","category":"Test","summary":"A summary.","description":"A description."}}"#);
        fs::write(dir.join(META_FILE), meta).unwrap();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_toc_the_meta_and_the_package_files() {
        let tmp = tempfile::TempDir::new().unwrap();
        testing::write_addon(tmp.path(), "Beta", "beta", "print(1)\n");
        testing::write_addon(tmp.path(), "Alpha", "alpha", "print(1)\n");
        fs::write(tmp.path().join("notes.txt"), "not an addon").unwrap();

        let addons = read_addons(tmp.path()).unwrap();
        assert_eq!(addons.iter().map(|addon| addon.folder.as_str()).collect::<Vec<_>>(), ["Alpha", "Beta"]);
        let alpha = &addons[0];
        assert_eq!(alpha.toc.as_ref().unwrap().version, "1.2.3");
        assert_eq!(alpha.meta.as_ref().unwrap().id, "alpha");
        // addon.json and dotfiles stay out of the package.
        assert_eq!(alpha.files, ["Alpha.toc", "Core.lua", "Settings.lua", "SettingsKit.lua", "lib/Util.lua"]);
    }
}
