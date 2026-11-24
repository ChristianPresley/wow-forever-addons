//! Repository tools for the WoW: Forever addons.
//!
//!   cargo dev lint            check each addon: TOC, addon.json, file list and Lua syntax
//!   cargo dev test            load each addon in a stand-in for the game and use everything in it
//!   cargo dev conformance     check each API name that the addons use, without running them
//!   cargo dev api-snapshot    build the API snapshot that the stand-in is made from
//!   cargo dev ui-names        read the fonts, frame types, scripts, templates and calls of the game's UI files
//!   cargo dev marketplace     build dist/marketplace: one ZIP for each addon, and index.json
//!   cargo dev icon <out.png>  draw the source image of the app icon

mod addons;
mod conformance;
mod harness;
mod icon;
mod lint;
mod marketplace;
mod snapshot;
mod track_icon;
mod ui_names;

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
  conformance             check each API name that the addons use against the API of this client,
                          on every line, without running the addons
  api-snapshot <folder> [note]
                          build tools/api/forever-api.json from Blizzard's API documentation
                          (the Blizzard_APIDocumentationGenerated folder of the UI source)
                            --out <file>  write the new snapshot to another file
                            --check       compare with the snapshot of the repository and
                                          list the differences; nothing is written to it
  ui-names <folder>       build tools/api/forever-ui.json from the Interface/AddOns folder of the
                          UI source: the fonts, the frame types, the scripts and the templates of
                          the game, the events that the documentation does not list, and the
                          calls of widget methods in the game's own code
                            --check       compare with the file of the repository; nothing is
                                          written to it
  marketplace             build dist/marketplace: one ZIP for each addon, and index.json
                          --published <folder>  fail if an addon has the version of the
                          marketplace copy in <folder>, with other files
                          --hold <a,b>         leave these addons out; each keeps its
                          published entry (needs --published)
  icon <out.png>          draw the source image of the app icon
  track-icon              draw the symbols of Forever Quests (Media/Track.tga, Media/Compass.tga)";

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
            let value_of = |flag: &str| args.iter().position(|arg| arg == flag).and_then(|index| args.get(index + 1)).cloned();
            // `--published <folder>` names a copy of the marketplace that is published now.
            let published = value_of("--published");
            // `--hold a,b` leaves those addons out: they keep the version that is published.
            let held: Vec<String> = value_of("--hold").unwrap_or_default().split(',').filter(|folder| !folder.is_empty()).map(str::to_string).collect();
            for line in marketplace::build_holding(&addons, &out_dir, &held, published.as_deref().map(Path::new))? {
                println!("{line}");
            }
            println!("-> {}", out_dir.display());
            if let Some(published) = published {
                println!("{}", marketplace::check_published(&out_dir, Path::new(&published))?);
            }
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
        (Some("conformance"), _) => {
            let addons = addons::read_addons(&root.join("addons"))?;
            let snapshot_file = root.join("tools").join("api").join("forever-api.json");
            let text = std::fs::read_to_string(&snapshot_file).map_err(|error| format!("Cannot read {}: {error}", snapshot_file.display()))?;
            let mut snapshot: serde_json::Value = serde_json::from_str(&text).map_err(|error| format!("The API snapshot is not valid JSON: {error}"))?;
            harness::with_ui_names(&mut snapshot)?;
            let (globals, methods) = harness::known_names(&snapshot)?;
            let known = conformance::Known::new(&snapshot, globals, methods);
            let problems = conformance::check(&addons, &known)?;
            // The stand-in itself against the game's UI files: frame types, scripts, templates,
            // and the calls of widget methods in the game's own code.
            let stand_in_problems = harness::ui_check(&snapshot)?;
            if problems.is_empty() {
                println!("{} addons: every name of the game's API that they use is in the API of this client.", addons.len());
            } else {
                for problem in &problems {
                    eprintln!("{problem}");
                }
                eprintln!("\n{} name(s) that this client does not have. Each one is a mistake, or code for another client that never runs here.", problems.len());
            }
            if stand_in_problems.is_empty() {
                println!("The stand-in for the game agrees with the game's UI files: frame types, scripts, templates and the calls of the game's own code.");
            } else {
                for problem in &stand_in_problems {
                    eprintln!("{problem}");
                }
                eprintln!("\n{} difference(s) between the stand-in for the game and the game's UI files (tools/api/forever-ui.json).", stand_in_problems.len());
            }
            Ok(problems.is_empty() && stand_in_problems.is_empty())
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
            if args.iter().any(|arg| arg == "--check") {
                // Builds the snapshot again from Blizzard's files and compares it with the one
                // in the repository. Nothing in the repository is changed.
                let committed_file = root.join("tools").join("api").join("forever-api.json");
                let committed = std::fs::read_to_string(&committed_file).map_err(|error| format!("Cannot read {}: {error}", committed_file.display()))?;
                let old: serde_json::Value = serde_json::from_str(&committed).map_err(|error| format!("The API snapshot is not valid JSON: {error}"))?;
                // The note is a part of the file: the same note gives the same bytes.
                let note = old.get("source").and_then(|value| value.as_str()).unwrap_or("").to_string();
                let fresh_file = root.join("target").join("api-check").join("forever-api.json");
                snapshot::build(Path::new(docs_dir), &fresh_file, &note)?;
                let fresh = std::fs::read_to_string(&fresh_file).map_err(|error| error.to_string())?;
                if fresh == committed {
                    println!("The API snapshot is the same as Blizzard's documentation in {docs_dir}.");
                    return Ok(true);
                }
                let new: serde_json::Value = serde_json::from_str(&fresh).map_err(|error| error.to_string())?;
                let differences = snapshot::differences(&old, &new);
                eprintln!("The API snapshot in the repository differs from Blizzard's documentation in {docs_dir}:");
                for line in differences.iter().take(60) {
                    eprintln!("  {line}");
                }
                if differences.len() > 60 {
                    eprintln!("  ... and {} more", differences.len() - 60);
                }
                eprintln!("\nIf the game was patched: build the snapshot again (cargo dev api-snapshot <folder> \"<note>\"), then run cargo dev test and cargo dev conformance.");
                return Ok(false);
            }
            for line in snapshot::build(Path::new(docs_dir), &out, &note)? {
                println!("{line}");
            }
            println!("-> {}", out.display());
            Ok(true)
        }
        (Some("ui-names"), Some(addons_dir)) => {
            let snapshot_file = root.join("tools").join("api").join("forever-api.json");
            let text = std::fs::read_to_string(&snapshot_file).map_err(|error| format!("Cannot read {}: {error}", snapshot_file.display()))?;
            let snapshot: serde_json::Value = serde_json::from_str(&text).map_err(|error| format!("The API snapshot is not valid JSON: {error}"))?;
            // The method names of the widgets of the stand-in: the calls of these in the game's
            // Lua code are collected.
            let mut with_names = snapshot.clone();
            harness::with_ui_names(&mut with_names)?;
            let widget_methods = harness::widget_methods(&with_names)?;
            let (fresh, lines) = ui_names::collect(Path::new(addons_dir), &snapshot, &widget_methods)?;
            let file = root.join("tools").join("api").join("forever-ui.json");
            if args.iter().any(|arg| arg == "--check") {
                let committed = std::fs::read_to_string(&file).map_err(|error| format!("Cannot read {}: {error}", file.display()))?;
                if committed == fresh {
                    println!("The names in tools/api/forever-ui.json are the same as in the UI files in {addons_dir}.");
                    return Ok(true);
                }
                let old: serde_json::Value = serde_json::from_str(&committed).map_err(|error| error.to_string())?;
                let new: serde_json::Value = serde_json::from_str(&fresh).map_err(|error| error.to_string())?;
                eprintln!("tools/api/forever-ui.json differs from the UI files in {addons_dir}:");
                for line in ui_names::differences(&old, &new) {
                    eprintln!("{line}");
                }
                eprintln!("\nIf the game was patched: build the file again (cargo dev ui-names <folder>), then run cargo dev test.");
                return Ok(false);
            }
            std::fs::write(&file, fresh).map_err(|error| format!("Cannot write {}: {error}", file.display()))?;
            for line in lines {
                println!("{line}");
            }
            println!("-> {}", file.display());
            Ok(true)
        }
        (Some("track-icon"), _) => {
            // The tracking symbol of Forever Quests, as a texture of the game, and a picture to look at.
            let texture = root.join("addons").join("ForeverQuests").join("Media").join("Track.tga");
            track_icon::write(&texture)?;
            // The compass symbol of the button "track in compass".
            let compass = root.join("addons").join("ForeverQuests").join("Media").join("Compass.tga");
            track_icon::write_symbol(&compass, track_icon::Symbol::Compass)?;
            println!("-> {}", compass.display());
            let preview = root.join("target").join("track-icon-preview.png");
            track_icon::write_preview(&preview)?;
            println!("{}  {0}x{0}", track_icon::SIZE);
            println!("-> {}", texture.display());
            println!("-> {} (to look at)", preview.display());
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
