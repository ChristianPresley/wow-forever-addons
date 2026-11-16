//! Repository tools for the WoW: Forever addons.
//!
//!   cargo dev lint            check each addon: TOC, addon.json, file list and Lua syntax
//!   cargo dev test            load each addon in a stand-in for the game and use everything in it
//!   cargo dev api-snapshot    build the API snapshot that the stand-in is made from
//!   cargo dev marketplace     build dist/marketplace: one ZIP for each addon, and index.json
//!   cargo dev icon <out.png>  draw the source image of the app icon

mod addons;
mod harness;
mod icon;
mod lint;
mod marketplace;
mod snapshot;

use std::path::{Path, PathBuf};
use std::process::ExitCode;

const USAGE: &str = "\
Usage: cargo dev <command>

Commands:
  lint                    check each addon: TOC, addon.json, file list and Lua syntax
  test [Addon] [options]  load each addon in a stand-in for the game and use everything in it
                            --coverage  list the code lines of each file that did not run
                            --caught    list the errors that the addon caught itself, and the
                                        names that it looked for and that are not there
  api-snapshot <folder> [note]
                          build tools/api/forever-api.json from Blizzard's API documentation
                          (the Blizzard_APIDocumentationGenerated folder of the UI source)
  marketplace             build dist/marketplace: one ZIP for each addon, and index.json
  icon <out.png>          draw the source image of the app icon";

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
        (Some("test"), filter) => {
            let mut addons = addons::read_addons(&root.join("addons"))?;
            if let Some(filter) = filter.filter(|filter| !filter.starts_with("--")) {
                addons.retain(|addon| addon.folder.eq_ignore_ascii_case(filter));
                if addons.is_empty() {
                    return Err(format!("No addon with the folder name {filter}."));
                }
            }
            let show_caught = args.iter().any(|arg| arg == "--caught");
            let show_coverage = args.iter().any(|arg| arg == "--coverage");
            let snapshot_file = root.join("tools").join("api").join("forever-api.json");
            let snapshot = std::fs::read_to_string(&snapshot_file).map_err(|error| format!("Cannot read {}: {error}", snapshot_file.display()))?;
            let reports = harness::run(&addons, &snapshot)?;
            let mut failed = 0;
            for report in &reports {
                let status = if report.failures.is_empty() { "ok" } else { "FAILED" };
                println!(
                    "{:<16} {status}  about {}% of the code lines ran  ({}; {} errors caught by the addon)",
                    report.addon,
                    report.percent(),
                    report.summary,
                    report.caught.len()
                );
                for failure in &report.failures {
                    println!("    {failure}");
                }
                if show_coverage {
                    for file in &report.coverage {
                        if file.missed.is_empty() {
                            println!("    {:<18} {:>3}%", file.name, file.percent());
                        } else {
                            println!("    {:<18} {:>3}%  did not run: {}", file.name, file.percent(), harness::ranges(&file.missed));
                        }
                    }
                }
                if show_caught {
                    for line in &report.caught {
                        println!("    caught: {line}");
                    }
                    if !report.absent.is_empty() {
                        println!("    looked for, not there: {}", report.absent.join(", "));
                    }
                }
                failed += report.failures.len();
            }
            if failed > 0 {
                eprintln!("\n{failed} error(s). Each one is a Lua error in the game.");
                return Ok(false);
            }
            println!("\n{} addons loaded and used in the stand-in for the game, no errors.", reports.len());
            Ok(true)
        }
        (Some("api-snapshot"), Some(docs_dir)) => {
            // The snapshot is what the addon tests are judged against. `--out <file>` writes a
            // new one beside it, to compare before it takes the place of the old one.
            let out_option = args.iter().position(|arg| arg == "--out").and_then(|index| args.get(index + 1));
            let out = match out_option {
                Some(file) => PathBuf::from(file),
                None => root.join("tools").join("api").join("forever-api.json"),
            };
            let note = args.get(2).filter(|note| !note.starts_with("--")).cloned().unwrap_or_default();
            for line in snapshot::build(Path::new(docs_dir), &out, &note)? {
                println!("{line}");
            }
            println!("-> {}", out.display());
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
