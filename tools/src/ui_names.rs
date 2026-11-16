//! Names of the game that Blizzard's API documentation does not list, read from the game's own
//! UI files: the fonts that a font string can inherit, and the events that the game's code
//! registers and the documentation leaves out.
//!
//! The UI files come from outside this repository. They are read as text only, and a name is
//! taken only if it is made of letters, digits and underscores.

use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

/// Folders with the files of another game client. This client reads Mainline, Camelot and Shared.
const OTHER_CLIENTS: [&str; 9] = ["Classic", "Cata", "Mists", "Wrath", "Vanilla", "TBC", "WoWLabs", "WoWHack", "Unused"];

/// Parts of the game that an addon never runs in: the screens before the game world, the shop
/// and the debug tools. An event that only these register is not taken.
const NOT_IN_THE_WORLD: [&str; 9] = ["Glue", "CharacterCreate", "CharacterSelect", "Login", "Store", "Debug", "APIDocumentation", "Console", "Kiosk"];

fn is_name(text: &str) -> bool {
    !text.is_empty() && text.len() <= 80 && text.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn is_event_name(text: &str) -> bool {
    is_name(text) && text.chars().next().is_some_and(|c| c.is_ascii_uppercase()) && text.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
}

/// The value of an attribute in the text of one XML tag.
fn attribute<'a>(tag: &'a str, name: &str) -> Option<&'a str> {
    let mut rest = tag;
    while let Some(at) = rest.find(name) {
        let before_ok = at == 0 || rest[..at].ends_with(|c: char| c.is_whitespace());
        let after = rest[at + name.len()..].trim_start();
        if before_ok && after.starts_with('=') {
            let value = after[1..].trim_start();
            let quote = value.chars().next()?;
            if quote == '"' || quote == '\'' {
                let end = value[1..].find(quote)?;
                return Some(&value[1..1 + end]);
            }
        }
        rest = &rest[at + name.len()..];
    }
    None
}

/// The fonts of an XML file: each `Font` and `FontFamily` with a name, and each virtual `FontString`.
fn fonts_of(xml: &str, out: &mut BTreeSet<String>) {
    let mut rest = xml;
    while let Some(at) = rest.find('<') {
        rest = &rest[at + 1..];
        let end = rest.find('>').unwrap_or(rest.len());
        let tag = &rest[..end];
        let element = tag.split(|c: char| c.is_whitespace() || c == '/').next().unwrap_or("");
        let wanted = match element {
            "Font" | "FontFamily" => true,
            "FontString" => attribute(tag, "virtual") == Some("true"),
            _ => false,
        };
        if wanted {
            if let Some(name) = attribute(tag, "name") {
                if is_name(name) {
                    out.insert(name.to_string());
                }
            }
        }
    }
}

/// The event names that a Lua file registers with a literal text.
fn events_of(lua: &str, out: &mut BTreeSet<String>) {
    for call in ["RegisterEvent(", "RegisterUnitEvent("] {
        let mut rest = lua;
        while let Some(at) = rest.find(call) {
            rest = &rest[at + call.len()..];
            let argument = rest.trim_start();
            let Some(quote) = argument.chars().next().filter(|c| *c == '"' || *c == '\'') else { continue };
            if let Some(end) = argument[1..].find(quote) {
                let name = &argument[1..1 + end];
                if is_event_name(name) {
                    out.insert(name.to_string());
                }
            }
        }
    }
}

fn walk(dir: &Path, in_world: bool, fonts: &mut BTreeSet<String>, events: &mut BTreeSet<String>, files: &mut usize) -> Result<(), String> {
    let mut entries: Vec<_> = fs::read_dir(dir).map_err(|error| format!("Cannot read {}: {error}", dir.display()))?.flatten().map(|entry| entry.path()).collect();
    entries.sort();
    for path in entries {
        let name = path.file_name().unwrap_or_default().to_string_lossy().into_owned();
        if path.is_dir() {
            if !OTHER_CLIENTS.contains(&name.as_str()) {
                walk(&path, in_world, fonts, events, files)?;
            }
            continue;
        }
        let extension = path.extension().map(|extension| extension.to_string_lossy().to_ascii_lowercase()).unwrap_or_default();
        if extension != "xml" && extension != "lua" {
            continue;
        }
        // Not every file of the game is UTF-8: bytes that are not are replaced, and a name with
        // such a byte is not taken.
        let text = String::from_utf8_lossy(&fs::read(&path).map_err(|error| format!("Cannot read {}: {error}", path.display()))?).into_owned();
        *files += 1;
        if extension == "xml" {
            fonts_of(&text, fonts);
        } else if in_world {
            events_of(&text, events);
        }
    }
    Ok(())
}

/// Reads the `Interface/AddOns` folder of the UI source. `snapshot`: the API snapshot, for the
/// events that the documentation has already and for the note of the source.
pub fn collect(addons_dir: &Path, snapshot: &serde_json::Value) -> Result<(String, Vec<String>), String> {
    let mut fonts = BTreeSet::new();
    let mut events = BTreeSet::new();
    let mut files = 0;
    let mut folders: Vec<_> = fs::read_dir(addons_dir).map_err(|error| format!("Cannot read {}: {error}", addons_dir.display()))?.flatten().map(|entry| entry.path()).filter(|path| path.is_dir()).collect();
    folders.sort();
    for folder in &folders {
        let name = folder.file_name().unwrap_or_default().to_string_lossy().into_owned();
        let in_world = !NOT_IN_THE_WORLD.iter().any(|part| name.contains(part));
        walk(folder, in_world, &mut fonts, &mut events, &mut files)?;
    }
    if fonts.is_empty() {
        return Err(format!("{} has no font in its XML files. Give the Interface/AddOns folder of the UI source.", addons_dir.display()));
    }
    let documented = snapshot.get("events").and_then(|value| value.as_object());
    let events: Vec<String> = events.into_iter().filter(|name| documented.is_none_or(|map| !map.contains_key(name))).collect();
    let fonts: Vec<String> = fonts.into_iter().collect();
    let lines = vec![format!("{files} files in {} folders: {} fonts, {} events that the documentation does not have", folders.len(), fonts.len(), events.len())];
    let value = serde_json::json!({
        "source": snapshot.get("source").cloned().unwrap_or(serde_json::Value::String(String::new())),
        "fonts": fonts,
        "undocumentedEvents": events,
    });
    let text = serde_json::to_string_pretty(&value).map_err(|error| error.to_string())? + "\n";
    Ok((text, lines))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fonts_are_the_named_fonts_and_the_virtual_font_strings() {
        let mut out = BTreeSet::new();
        fonts_of(
            r#"<Ui><Font name="GameFontNormal" inherits="SystemFont_Shadow_Med1" virtual="true"/>
            <FontFamily name="SystemFont_Med1" virtual="true"><Member alphabet="roman"/></FontFamily>
            <FontString name="GameTooltipText" inherits="GameFontNormal" virtual="true"/>
            <FontString name="$parentText" inherits="GameFontNormal"/>
            <FontString parentKey="Title" name="NotVirtual"/>
            <Frame name="NotAFont"/></Ui>"#,
            &mut out,
        );
        assert_eq!(out.into_iter().collect::<Vec<_>>(), ["GameFontNormal", "GameTooltipText", "SystemFont_Med1"]);
    }

    #[test]
    fn events_are_the_literal_names_of_register_calls() {
        let mut out = BTreeSet::new();
        events_of(
            "self:RegisterEvent(\"PLAYTIME_CHANGED\");\nf:RegisterUnitEvent('UNIT_AURA', \"player\")\nf:RegisterEvent(event)\nf:RegisterEvent(\"not an event\")",
            &mut out,
        );
        assert_eq!(out.into_iter().collect::<Vec<_>>(), ["PLAYTIME_CHANGED", "UNIT_AURA"]);
    }
}
