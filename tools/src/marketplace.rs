//! Builds one ZIP package for each addon and the marketplace index.
//! Output: `<out>/index.json` and `<out>/<Folder>-<version>.zip`.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::{Cursor, Read, Write};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use sha2::{Digest, Sha256};
use wfam_core::marketplace::{load_index, validate_index, Download, Index, MarketAddon, INDEX_SCHEMA};
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, DateTime, ZipWriter};

use crate::addons::Addon;

/// The package of an addon: every file under a top-level folder with the addon's name.
/// Each entry has the same fixed date, so the same files give the same archive.
fn package(addon: &Addon) -> Result<Vec<u8>, String> {
    let options = SimpleFileOptions::default()
        .compression_method(CompressionMethod::Deflated)
        .last_modified_time(DateTime::default())
        .unix_permissions(0o644);
    let mut writer = ZipWriter::new(Cursor::new(Vec::new()));
    for file in &addon.files {
        let data = fs::read(addon.dir.join(file)).map_err(|error| format!("Cannot read {}/{file}: {error}", addon.folder))?;
        writer.start_file(format!("{}/{file}", addon.folder), options).map_err(|error| error.to_string())?;
        writer.write_all(&data).map_err(|error| error.to_string())?;
    }
    Ok(writer.finish().map_err(|error| error.to_string())?.into_inner())
}

/// The UTC time as `2026-11-15T09:30:00Z`.
fn iso_time(seconds: u64) -> String {
    let days = seconds / 86_400;
    let rest = seconds % 86_400;
    // Days since 1970-01-01 to a calendar date (Howard Hinnant's civil_from_days).
    let z = days as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let day_of_era = z.rem_euclid(146_097);
    let year_of_era = (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_index = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_index + 2) / 5 + 1;
    let month = if month_index < 10 { month_index + 3 } else { month_index - 9 };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    format!("{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z", rest / 3_600, rest % 3_600 / 60, rest % 60)
}

/// Writes the packages and the index. Returns one line of report for each file written.
pub fn build(addons: &[Addon], out_dir: &Path) -> Result<Vec<String>, String> {
    let io = |error: std::io::Error| format!("Cannot write to {}: {error}", out_dir.display());
    if out_dir.exists() {
        fs::remove_dir_all(out_dir).map_err(io)?;
    }
    fs::create_dir_all(out_dir).map_err(io)?;

    let mut report = Vec::new();
    let mut entries = Vec::new();
    for addon in addons {
        let (Some(toc), Some(meta)) = (&addon.toc, &addon.meta) else {
            return Err(format!("{} is incomplete. Run \"cargo dev lint\".", addon.folder));
        };
        let zip = package(addon)?;
        let file_name = format!("{}-{}.zip", addon.folder, toc.version);
        fs::write(out_dir.join(&file_name), &zip).map_err(io)?;
        report.push(format!("{file_name}  {} bytes", zip.len()));
        let field = |key: &str| toc.fields.get(key).cloned().unwrap_or_default();
        entries.push(MarketAddon {
            id: meta.id.clone(),
            name: toc.title.clone(),
            version: toc.version.clone(),
            category: meta.category.clone(),
            summary: meta.summary.clone(),
            description: meta.description.clone(),
            author: field("Author"),
            homepage: field("X-Website"),
            interfaces: toc.interfaces.clone(),
            folders: vec![addon.folder.clone()],
            download: Download { url: file_name, sha256: format!("{:x}", Sha256::digest(&zip)), size: zip.len() as u64 },
        });
    }

    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|elapsed| elapsed.as_secs()).unwrap_or(0);
    let index = Index { schema: INDEX_SCHEMA, generated_at: Some(iso_time(now)), addons: entries };
    // The manager refuses an index that fails this check, so do not publish one.
    validate_index(&index).map_err(|error| format!("The index is not valid: {error}. Run \"cargo dev lint\"."))?;
    let json = serde_json::to_string_pretty(&index).map_err(|error| error.to_string())?;
    fs::write(out_dir.join("index.json"), format!("{json}\n")).map_err(io)?;
    report.push(format!("index.json  {} addons", index.addons.len()));
    Ok(report)
}

/// The files of a package, by name.
fn package_files(path: &Path) -> Result<BTreeMap<String, Vec<u8>>, String> {
    let problem = |error: &dyn std::fmt::Display| format!("Cannot read {}: {error}", path.display());
    let bytes = fs::read(path).map_err(|error| problem(&error))?;
    let mut archive = zip::ZipArchive::new(Cursor::new(bytes)).map_err(|error| problem(&error))?;
    let mut files = BTreeMap::new();
    for index in 0..archive.len() {
        let mut file = archive.by_index(index).map_err(|error| problem(&error))?;
        let mut data = Vec::new();
        file.read_to_end(&mut data).map_err(|error| problem(&error))?;
        files.insert(file.name().to_string(), data);
    }
    Ok(files)
}

/// Compares the marketplace in `out_dir` with the one that is published now, of which
/// `published_dir` holds a copy (the index and the packages).
///
/// The manager finds an update by the version alone. So an addon whose files changed while
/// its version stayed the same would never reach a user who has that version. This is an
/// error. A package that only differs in its bytes, with the same files, is not.
/// Returns one line of report. A folder without an index means that nothing is published yet.
pub fn check_published(out_dir: &Path, published_dir: &Path) -> Result<String, String> {
    let published_index = published_dir.join("index.json");
    if !published_index.is_file() {
        return Ok(format!("No published index in {}. Nothing to compare.", published_dir.display()));
    }
    let load = |path: &Path| load_index(&path.to_string_lossy()).map_err(|error| format!("{}: {error}", path.display()));
    let published = load(&published_index)?;
    let built = load(&out_dir.join("index.json"))?;

    let mut problems = Vec::new();
    let mut same = 0;
    for addon in &built.addons {
        let Some(old) = published.addons.iter().find(|old| old.id == addon.id && old.version == addon.version) else { continue };
        same += 1;
        if old.download.sha256 == addon.download.sha256 {
            continue;
        }
        let old_files = package_files(&published_dir.join(&old.download.url))?;
        let new_files = package_files(&out_dir.join(&addon.download.url))?;
        if old_files != new_files {
            let names: BTreeSet<&String> = old_files.keys().chain(new_files.keys()).collect();
            let changed: Vec<&str> = names.into_iter().filter(|name| old_files.get(*name) != new_files.get(*name)).map(String::as_str).collect();
            problems.push(format!(
                "{} {} is published already, and its files are different now ({}). Raise the version in the .toc file.",
                addon.name,
                addon.version,
                changed.join(", ")
            ));
        }
    }
    if problems.is_empty() {
        Ok(format!("{same} addon(s) have the published version, with the published files."))
    } else {
        Err(problems.join("\n"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::addons::{read_addons, testing::write_addon};
    use wfam_core::addons::{install_addon, list_installed};
    use wfam_core::marketplace::download_package;

    /// Builds the marketplace of one addon "Demo" 1.2.3 with this Lua code, in `<tmp>/<name>`.
    fn build_demo(tmp: &Path, name: &str, lua: &str) -> std::path::PathBuf {
        let source = tmp.join(format!("{name}-addons"));
        write_addon(&source, "Demo", "demo", lua);
        let out = tmp.join(name);
        build(&read_addons(&source).unwrap(), &out).unwrap();
        out
    }

    #[test]
    fn changed_files_under_a_published_version_are_an_error() {
        let tmp = tempfile::TempDir::new().unwrap();
        let published = build_demo(tmp.path(), "published", "print(1)\n");

        let same = build_demo(tmp.path(), "same", "print(1)\n");
        assert!(check_published(&same, &published).unwrap().starts_with("1 addon(s)"));

        let changed = build_demo(tmp.path(), "changed", "print(2)\n");
        let error = check_published(&changed, &published).unwrap_err();
        assert!(error.contains("Demo 1.2.3") && error.contains("(Demo/Core.lua)") && error.contains("Raise the version"), "{error}");

        // The same files in a package with other bytes: the checksum differs, the files do not.
        let index_path = published.join("index.json");
        let mut index = load_index(&index_path.to_string_lossy()).unwrap();
        index.addons[0].download.sha256 = "0".repeat(64);
        fs::write(&index_path, serde_json::to_string(&index).unwrap()).unwrap();
        assert!(check_published(&same, &published).is_ok());

        // Another version is a new package, and an empty folder means nothing is published.
        index.addons[0].version = "1.2.2".to_string();
        fs::write(&index_path, serde_json::to_string(&index).unwrap()).unwrap();
        assert!(check_published(&changed, &published).unwrap().starts_with("0 addon(s)"));
        assert!(check_published(&changed, &tmp.path().join("nothing")).unwrap().contains("Nothing to compare"));
    }

    #[test]
    fn iso_time_matches_known_dates() {
        assert_eq!(iso_time(0), "1970-01-01T00:00:00Z");
        assert_eq!(iso_time(951_782_400), "2000-02-29T00:00:00Z");
        assert_eq!(iso_time(1_794_735_005), "2026-11-15T09:30:05Z");
    }

    #[test]
    fn the_manager_can_install_what_the_build_makes() {
        let tmp = tempfile::TempDir::new().unwrap();
        let source = tmp.path().join("addons");
        write_addon(&source, "Demo", "demo", "print(1)\n");
        let addons = read_addons(&source).unwrap();
        let out = tmp.path().join("dist");
        fs::create_dir_all(&out).unwrap();
        fs::write(out.join("stale.zip"), "old output").unwrap();

        let report = build(&addons, &out).unwrap();
        assert_eq!(report.len(), 2);
        assert!(!out.join("stale.zip").exists(), "old output is removed");

        // Read the index and install the package with the manager's own code.
        let index_path = out.join("index.json").to_string_lossy().into_owned();
        let index = load_index(&index_path).unwrap();
        let entry = &index.addons[0];
        assert_eq!((entry.id.as_str(), entry.name.as_str(), entry.version.as_str()), ("demo", "Demo", "1.2.3"));
        assert_eq!(entry.author, "Tester");
        assert_eq!(entry.folders, ["Demo"]);
        assert_eq!(entry.download.url, "Demo-1.2.3.zip");

        let zip = download_package(&index_path, entry).unwrap();
        let game = tmp.path().join("game").join("AddOns");
        install_addon(&game, entry, &zip, false).unwrap();
        assert_eq!(list_installed(&game)[0].version, "1.2.3");
        assert!(game.join("Demo").join("lib").join("Util.lua").is_file());
        assert!(!game.join("Demo").join("addon.json").exists(), "addon.json is not packaged");
        assert!(!game.join("Demo").join(".hidden").exists(), "dotfiles are not packaged");
    }

    #[test]
    fn the_same_files_give_the_same_package() {
        let tmp = tempfile::TempDir::new().unwrap();
        write_addon(tmp.path(), "Demo", "demo", "print(1)\n");
        let addons = read_addons(tmp.path()).unwrap();
        assert_eq!(package(&addons[0]).unwrap(), package(&addons[0]).unwrap());
    }

    #[test]
    fn an_incomplete_addon_stops_the_build() {
        let tmp = tempfile::TempDir::new().unwrap();
        fs::create_dir_all(tmp.path().join("addons").join("NoToc")).unwrap();
        let addons = read_addons(&tmp.path().join("addons")).unwrap();
        assert!(build(&addons, &tmp.path().join("dist")).unwrap_err().contains("incomplete"));
    }
}
