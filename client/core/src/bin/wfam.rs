//! Command-line form of the Forever Addon Manager.

use std::cmp::Ordering;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use wfam_core::detect::Install;
use wfam_core::marketplace::DEFAULT_SOURCE;
use wfam_core::service::{InstallState, Service};
use wfam_core::version::compare_versions;
use wfam_core::{Error, Result};

const USAGE: &str = "\
Usage: wfam <command> [options]   (in this repository: cargo wfam <command> [options])

Commands:
  detect            list the WoW: Forever installs
  list              list the addons of an install
  market            list the marketplace addons
  install <id>      install or update an addon
  update            update each addon that the manager installed, in every install
  uninstall <id>    remove an addon
  link <folder>     link each addon in <folder> into the install (for development)
  unlink <folder>   remove those links

Options:
  --install <folder>   use this World of Warcraft folder
  --source <url|path>  use this marketplace index
  --force              also replace or remove a copy that the manager did not install";

struct Args {
    positional: Vec<String>,
    install: Option<PathBuf>,
    source: Option<String>,
    force: bool,
}

fn parse_args() -> Result<Args> {
    let mut args = Args { positional: Vec::new(), install: None, source: std::env::var("WFAM_SOURCE").ok(), force: false };
    let mut input = std::env::args().skip(1);
    while let Some(arg) = input.next() {
        match arg.as_str() {
            "--install" => args.install = Some(PathBuf::from(input.next().ok_or_else(|| Error::other("--install needs a folder."))?)),
            "--source" => args.source = Some(input.next().ok_or_else(|| Error::other("--source needs a URL or a path."))?),
            "--force" => args.force = true,
            _ => args.positional.push(arg),
        }
    }
    Ok(args)
}

fn pick_install(service: &mut Service, wanted: Option<&Path>) -> Result<InstallState> {
    let mut installs = service.scan().installs;
    if let Some(wanted) = wanted {
        let wanted = std::path::absolute(wanted).unwrap_or_else(|_| wanted.to_path_buf()).to_string_lossy().to_lowercase();
        installs.retain(|state| state.install.id.starts_with(&wanted) || wanted.starts_with(&state.install.id));
    }
    match installs.len() {
        0 => Err(Error::other("No WoW: Forever install found. Use --install <folder>.")),
        1 => Ok(installs.remove(0)),
        _ => {
            let list: Vec<String> = installs.iter().map(|state| format!("  {}", state.install.root.display())).collect();
            Err(Error::other(format!("More than one install found. Choose one with --install:\n{}", list.join("\n"))))
        }
    }
}

fn is_link(path: &Path) -> bool {
    fs::symlink_metadata(path).map(|meta| meta.file_type().is_symlink()).unwrap_or(false)
}

/// Removes a link only. Neither call touches the folder that the link points to.
fn remove_link(link: &Path) -> std::io::Result<()> {
    fs::remove_dir(link).or_else(|_| fs::remove_file(link))
}

#[cfg(windows)]
fn create_link(source: &Path, link: &Path) -> Result<()> {
    // A junction needs no administrator rights, unlike a symbolic link.
    let status = std::process::Command::new("cmd").arg("/C").arg("mklink").arg("/J").arg(link).arg(source).output()?;
    if status.status.success() {
        Ok(())
    } else {
        Err(Error::other(format!("mklink failed: {}", String::from_utf8_lossy(&status.stderr).trim())))
    }
}

#[cfg(not(windows))]
fn create_link(source: &Path, link: &Path) -> Result<()> {
    Ok(std::os::unix::fs::symlink(source, link)?)
}

/// Links each addon folder of `source_dir` into the AddOns folder, or removes the links.
fn link_addons(install: &Install, source_dir: &Path, unlink: bool) -> Result<()> {
    let source_dir = std::path::absolute(source_dir)?;
    fs::create_dir_all(&install.addons_dir)?;
    let mut folders: Vec<PathBuf> = fs::read_dir(&source_dir)?.flatten().map(|entry| entry.path()).filter(|path| path.is_dir()).collect();
    folders.sort();
    for folder in folders {
        let Some(name) = folder.file_name().map(|name| name.to_string_lossy().into_owned()) else { continue };
        if !folder.join(format!("{name}.toc")).is_file() {
            continue;
        }
        let target = install.addons_dir.join(&name);
        let exists = fs::symlink_metadata(&target).is_ok();
        if exists && !is_link(&target) {
            println!("skipped  {name}: a real folder is installed there. Uninstall it first.");
            continue;
        }
        if exists {
            remove_link(&target)?;
        }
        if unlink {
            println!("{} {name}", if exists { "unlinked" } else { "no link " });
        } else {
            create_link(&folder, &target)?;
            println!("linked   {name} -> {}", folder.display());
        }
    }
    println!("AddOns folder: {}", install.addons_dir.display());
    Ok(())
}

fn run() -> Result<bool> {
    let args = parse_args()?;
    let config = std::env::var_os("APPDATA").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let mut service = Service::new(
        config.join("wow-forever-addon-manager").join("cli-settings.json"),
        args.source.clone().unwrap_or_else(|| DEFAULT_SOURCE.to_string()),
    );
    if let Some(folder) = &args.install {
        service.settings.extra_roots.push(folder.clone());
    }
    let wanted = args.install.as_deref();
    let command = args.positional.first().map(String::as_str);
    let operand = args.positional.get(1).map(String::as_str);

    match (command, operand) {
        (Some("detect"), _) => {
            let installs = service.scan().installs;
            if installs.is_empty() {
                println!("No WoW: Forever install found.");
            }
            for state in installs {
                let install = &state.install;
                println!("{}", install.flavor_dir.display());
                println!(
                    "  version {}, product {}, {} addons",
                    install.version.as_deref().unwrap_or("unknown"),
                    install.product,
                    state.addons.len()
                );
            }
        }
        (Some("list"), _) => {
            for addon in pick_install(&mut service, wanted)?.addons {
                let kind = if addon.linked { "link" } else if addon.managed.is_some() { "managed" } else { "by hand" };
                let version = if addon.version.is_empty() { "-" } else { &addon.version };
                println!("{:<28} {:<14} {kind}", addon.folder, version);
            }
        }
        (Some("market"), _) => {
            let index = service.marketplace()?;
            let installed = pick_install(&mut service, wanted).map(|state| state.addons).unwrap_or_default();
            for addon in index.addons {
                let status = match installed.iter().find(|item| addon.folders.contains(&item.folder)) {
                    None => String::new(),
                    Some(item) if compare_versions(&item.version, &addon.version) == Ordering::Less => format!("update from {}", item.version),
                    Some(_) => "installed".to_string(),
                };
                println!("{:<22} {:<8} {:<20} {}", addon.id, addon.version, status, addon.summary);
            }
        }
        (Some("install"), Some(id)) => {
            let state = pick_install(&mut service, wanted)?;
            let addon = service.install(&state.install.id, id, args.force)?;
            println!("Installed {} {} in {}", addon.name, addon.version, state.install.addons_dir.display());
        }
        (Some("update"), _) => {
            // With --install, only that install. Else every install.
            let only = match wanted {
                Some(_) => Some(pick_install(&mut service, wanted)?.install.id),
                None => None,
            };
            let report = service.update_all(only.as_deref())?;
            for addon in &report.updated {
                println!("Updated {} {} -> {}", addon.name, addon.from, addon.to);
            }
            for failure in &report.failed {
                eprintln!("Not updated: {}. {}", failure.name, failure.message);
            }
            if report.updated.is_empty() && report.failed.is_empty() {
                println!("Every addon that the manager installed is up to date.");
            }
            return Ok(report.failed.is_empty());
        }
        (Some("uninstall"), Some(id)) => {
            let state = pick_install(&mut service, wanted)?;
            let addon = service.find_addon(id)?;
            service.uninstall(&state.install.id, &addon.folders, args.force)?;
            println!("Removed {} from {}", addon.name, state.install.addons_dir.display());
        }
        (Some(command @ ("link" | "unlink")), Some(folder)) => {
            let state = pick_install(&mut service, wanted)?;
            link_addons(&state.install, Path::new(folder), command == "unlink")?;
        }
        (None, _) => println!("{USAGE}"),
        _ => {
            eprintln!("{USAGE}");
            return Ok(false);
        }
    }
    Ok(true)
}

fn main() -> ExitCode {
    match run() {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}
