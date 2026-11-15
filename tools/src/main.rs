//! Repository tools for the WoW: Forever addons.
//!
//!   cargo dev lint            check each addon: TOC, addon.json, file list and Lua syntax
//!   cargo dev marketplace     build dist/marketplace: one ZIP for each addon, and index.json
//!   cargo dev icon <out.png>  draw the source image of the app icon

mod addons;
mod icon;
mod lint;
mod marketplace;

use std::path::{Path, PathBuf};
use std::process::ExitCode;

const USAGE: &str = "\
Usage: cargo dev <command>

Commands:
  lint            check each addon: TOC, addon.json, file list and Lua syntax
  marketplace     build dist/marketplace: one ZIP for each addon, and index.json
  icon <out.png>  draw the source image of the app icon";

/// The repository root: the parent of this crate's folder.
fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().expect("the tools crate is inside the repository").to_path_buf()
}

fn run() -> Result<bool, String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let root = repo_root();
    match (args.first().map(String::as_str), args.get(1)) {
        (Some("lint"), _) => {
            let addons = addons::read_addons(&root.join("addons"))?;
            let problems = lint::lint(&addons);
            if problems.is_empty() {
                println!("{} addons checked, no problems.", addons.len());
                return Ok(true);
            }
            for problem in &problems {
                eprintln!("{problem}");
            }
            eprintln!("\n{} problem(s) in {} addon(s).", problems.len(), addons.len());
            Ok(false)
        }
        (Some("marketplace"), _) => {
            let addons = addons::read_addons(&root.join("addons"))?;
            let out_dir = root.join("dist").join("marketplace");
            for line in marketplace::build(&addons, &out_dir)? {
                println!("{line}");
            }
            println!("-> {}", out_dir.display());
            Ok(true)
        }
        (Some("icon"), Some(out)) => {
            icon::write(Path::new(out))?;
            println!("{out}  {0}x{0}", icon::SIZE);
            Ok(true)
        }
        (None, _) => {
            println!("{USAGE}");
            Ok(true)
        }
        _ => {
            eprintln!("{USAGE}");
            Ok(false)
        }
    }
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
