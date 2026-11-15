//! Checks each addon: TOC fields, the file list, addon.json and Lua syntax.

use std::collections::HashSet;
use std::fs;

use wfam_core::toc::FOREVER_INTERFACE;

use crate::addons::Addon;

fn is_valid_id(id: &str) -> bool {
    let mut chars = id.chars();
    chars.next().is_some_and(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// True for a version of the form 1.2.3.
fn is_release_version(version: &str) -> bool {
    let parts: Vec<&str> = version.split('.').collect();
    parts.len() == 3 && parts.iter().all(|part| !part.is_empty() && part.chars().all(|c| c.is_ascii_digit()))
}

/// The parser is recursive. Real addon files overflow the default stack of 1 MB on Windows.
const PARSER_STACK_BYTES: usize = 64 * 1024 * 1024;

/// The syntax errors of a Lua 5.1 source, one line for each.
fn lua_errors(source: &str) -> Vec<String> {
    let parse = || match full_moon::parse(source) {
        Ok(_) => Vec::new(),
        Err(errors) => errors.iter().map(|error| error.to_string()).collect(),
    };
    std::thread::scope(|scope| {
        let worker = std::thread::Builder::new().stack_size(PARSER_STACK_BYTES).spawn_scoped(scope, parse);
        match worker.map(|handle| handle.join()) {
            Ok(Ok(errors)) => errors,
            Ok(Err(_)) => vec!["the Lua parser stopped with an internal error.".to_string()],
            Err(error) => vec![format!("cannot start the Lua parser: {error}")],
        }
    })
}

/// Returns one line for each problem. An empty list means that all addons are good.
pub fn lint(addons: &[Addon]) -> Vec<String> {
    let mut problems = Vec::new();
    let mut ids = HashSet::new();

    for addon in addons {
        let mut fail = |message: String| problems.push(format!("{}: {message}", addon.folder));

        let Some(toc) = &addon.toc else {
            fail(format!("{}.toc is missing.", addon.folder));
            continue;
        };
        if !toc.interfaces.contains(&FOREVER_INTERFACE) {
            fail(format!("## Interface must include {FOREVER_INTERFACE}."));
        }
        if toc.title.is_empty() {
            fail("## Title is missing.".to_string());
        }
        if !is_release_version(&toc.version) {
            fail("## Version must have the form 1.2.3.".to_string());
        }

        match &addon.meta {
            None => fail("addon.json is missing or is not valid JSON.".to_string()),
            Some(meta) => {
                if !is_valid_id(&meta.id) {
                    fail("addon.json: id must be lower-case letters, digits and hyphens.".to_string());
                } else if !ids.insert(meta.id.clone()) {
                    fail(format!("addon.json: the id {} is used by more than one addon.", meta.id));
                }
                for (key, value) in [("category", &meta.category), ("summary", &meta.summary), ("description", &meta.description)] {
                    if value.is_empty() {
                        fail(format!("addon.json: {key} is missing."));
                    }
                }
            }
        }

        let present: HashSet<String> = addon.files.iter().map(|file| file.to_lowercase()).collect();
        let listed: HashSet<String> = toc.files.iter().map(|file| file.to_lowercase()).collect();
        for file in &toc.files {
            if !present.contains(&file.to_lowercase()) {
                fail(format!("the TOC lists {file}, but the file does not exist."));
            }
        }
        for file in &addon.files {
            let lower = file.to_lowercase();
            let is_lua = lower.ends_with(".lua");
            if !is_lua && !lower.ends_with(".xml") {
                continue;
            }
            if is_lua {
                match fs::read(addon.dir.join(file)) {
                    Ok(bytes) => {
                        for error in lua_errors(&String::from_utf8_lossy(&bytes)) {
                            fail(format!("{file}: {error}"));
                        }
                    }
                    Err(error) => fail(format!("{file}: cannot read the file: {error}")),
                }
            }
            // A file in a sub-folder can be loaded by an XML file, so only top-level files must be listed.
            if !file.contains('/') && !listed.contains(&lower) {
                fail(format!("{file} is not listed in the TOC."));
            }
        }
    }
    problems
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::*;
    use crate::addons::{read_addons, testing::write_addon};

    fn problems_of(addons_dir: &Path) -> Vec<String> {
        lint(&read_addons(addons_dir).unwrap())
    }

    #[test]
    fn a_good_addon_has_no_problems() {
        let tmp = tempfile::TempDir::new().unwrap();
        write_addon(tmp.path(), "Good", "good", "local _, ns = ...\nfunction ns.Hello() print(\"hi\") end\n");
        assert_eq!(problems_of(tmp.path()), Vec::<String>::new());
    }

    #[test]
    fn lua_syntax_errors_and_newer_lua_syntax_are_reported() {
        assert!(lua_errors("local x = 1\nprint(x)\n").is_empty());
        assert!(!lua_errors("local x = = 1\n").is_empty());
        assert!(!lua_errors("if true then print(1)\n").is_empty());
        // The game runs Lua 5.1: goto labels and integer division are not available.
        assert!(!lua_errors("::top::\ngoto top\n").is_empty());
        assert!(!lua_errors("local x = 7 // 2\n").is_empty());
    }

    #[test]
    fn each_kind_of_problem_is_found() {
        let tmp = tempfile::TempDir::new().unwrap();
        write_addon(tmp.path(), "Good", "same-id", "print(1)\n");
        write_addon(tmp.path(), "Twin", "same-id", "print(1)\n");

        write_addon(tmp.path(), "Broken", "Bad Id", "local = 1\n");
        let broken = tmp.path().join("Broken");
        fs::write(broken.join("Broken.toc"), "## Interface: 11508\n## Version: v1\n\nCore.lua\nMissing.lua\n").unwrap();
        fs::write(broken.join("Extra.lua"), "print(1)\n").unwrap();

        fs::create_dir_all(tmp.path().join("NoToc")).unwrap();

        let problems = problems_of(tmp.path()).join("\n");
        for expected in [
            "Broken: ## Interface must include 16001.",
            "Broken: ## Title is missing.",
            "Broken: ## Version must have the form 1.2.3.",
            "Broken: addon.json: id must be lower-case",
            "Broken: the TOC lists Missing.lua, but the file does not exist.",
            "Broken: Extra.lua is not listed in the TOC.",
            "Broken: Core.lua: ",
            "NoToc: NoToc.toc is missing.",
            "Twin: addon.json: the id same-id is used by more than one addon.",
        ] {
            assert!(problems.contains(expected), "missing {expected:?} in:\n{problems}");
        }
        assert!(!problems.contains("Good:"), "the good addon has no problems:\n{problems}");
    }
}
