//! `cargo dev conformance`: checks each name of the game's API that an addon uses against
//! Blizzard's published API, without running the addon.
//!
//! `cargo dev test` finds a wrong name only on a line that it reaches. This check reads every
//! line. It takes the source of each addon apart into words and finds:
//!
//! - `C_Name.Function`: the namespace and the function must be in the API snapshot.
//! - `Enum.Name.Field`: the enumeration and its field must be in the snapshot.
//! - an event name given to `RegisterEvent` and the like, or in a list of event names: the
//!   event must be in the snapshot.
//! - `object:Method(`: the method must be a documented widget method, a method of an object
//!   that the game's Lua code hands out, or one that the addon defines itself.
//! - a global name that the addon does not define: it must be a documented function or
//!   namespace, or a name of the game's own UI code that the stand-in has (each of those cites
//!   the game file).
//!
//! A name that fails here is either a mistake, or a fallback for another game client: code
//! behind `if Name then` that never runs on this client. Both should go.
//!
//! What it cannot see: a name that is built at run time, and whether a method belongs to the
//! kind of object it is called on (`cargo dev test` checks that, on the lines it reaches).

use std::collections::{BTreeMap, BTreeSet};
use std::fs;

use crate::addons::Addon;

/// A word of Lua source.
#[derive(Debug, Clone, PartialEq)]
enum Token {
    Name(String),
    Text(String),
    Number,
    Symbol(String),
}

struct Word {
    token: Token,
    line: u32,
}

/// The level of a long bracket that starts at `index` (`[[` is 0, `[=[` is 1), or `None`.
fn long_bracket(chars: &[char], index: usize) -> Option<usize> {
    if chars.get(index) != Some(&'[') {
        return None;
    }
    let mut level = 0;
    while chars.get(index + 1 + level) == Some(&'=') {
        level += 1;
    }
    (chars.get(index + 1 + level) == Some(&'[')).then_some(level)
}

/// The index after the end of a long bracket of `level` that starts at `index`, and its text.
fn read_long(chars: &[char], index: usize, level: usize, line: &mut u32) -> (usize, String) {
    let mut at = index + level + 2;
    let mut text = String::new();
    while at < chars.len() {
        if chars[at] == ']' {
            let mut equals = 0;
            while chars.get(at + 1 + equals) == Some(&'=') {
                equals += 1;
            }
            if equals == level && chars.get(at + 1 + equals) == Some(&']') {
                return (at + level + 2, text);
            }
        }
        if chars[at] == '\n' {
            *line += 1;
        }
        text.push(chars[at]);
        at += 1;
    }
    (at, text)
}

/// Takes Lua source apart into names, texts, numbers and symbols. Comments are left out.
fn words(source: &str) -> Vec<Word> {
    let chars: Vec<char> = source.chars().collect();
    let mut out = Vec::new();
    let mut line = 1;
    let mut index = 0;
    while index < chars.len() {
        let c = chars[index];
        if c == '\n' {
            line += 1;
            index += 1;
        } else if c.is_whitespace() {
            index += 1;
        } else if c == '-' && chars.get(index + 1) == Some(&'-') {
            if let Some(level) = long_bracket(&chars, index + 2) {
                index = read_long(&chars, index + 2, level, &mut line).0;
            } else {
                while index < chars.len() && chars[index] != '\n' {
                    index += 1;
                }
            }
        } else if let Some(level) = long_bracket(&chars, index) {
            let start = line;
            let (next, text) = read_long(&chars, index, level, &mut line);
            out.push(Word { token: Token::Text(text), line: start });
            index = next;
        } else if c == '"' || c == '\'' {
            let mut text = String::new();
            index += 1;
            while index < chars.len() && chars[index] != c && chars[index] != '\n' {
                if chars[index] == '\\' && index + 1 < chars.len() {
                    text.push(chars[index + 1]);
                    index += 2;
                } else {
                    text.push(chars[index]);
                    index += 1;
                }
            }
            index += 1;
            out.push(Word { token: Token::Text(text), line });
        } else if c.is_ascii_alphabetic() || c == '_' {
            let start = index;
            while index < chars.len() && (chars[index].is_ascii_alphanumeric() || chars[index] == '_') {
                index += 1;
            }
            out.push(Word { token: Token::Name(chars[start..index].iter().collect()), line });
        } else if c.is_ascii_digit() || (c == '.' && chars.get(index + 1).is_some_and(char::is_ascii_digit)) {
            while index < chars.len() && (chars[index].is_ascii_alphanumeric() || chars[index] == '.') {
                index += 1;
            }
            out.push(Word { token: Token::Number, line });
        } else {
            let pair: String = chars[index..(index + 2).min(chars.len())].iter().collect();
            let triple: String = chars[index..(index + 3).min(chars.len())].iter().collect();
            let symbol = if triple == "..." {
                triple
            } else if ["==", "~=", "<=", ">=", ".."].contains(&pair.as_str()) {
                pair
            } else {
                c.to_string()
            };
            index += symbol.chars().count();
            out.push(Word { token: Token::Symbol(symbol), line });
        }
    }
    out
}

const KEYWORDS: [&str; 21] = [
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not", "or", "repeat",
    "return", "then", "true", "until", "while",
];

/// Names of Lua itself that the game has and that are not in Blizzard's documentation.
const LUA_GLOBALS: [&str; 30] = [
    "_G", "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset", "select",
    "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "string", "table", "math", "coroutine", "bit", "loadstring",
    "getfenv", "setfenv", "date", "time", "self",
];

/// Functions that take an event name: the text after them is checked as an event.
const EVENT_FUNCTIONS: [&str; 5] = ["RegisterEvent", "RegisterUnitEvent", "UnregisterEvent", "IsEventRegistered", "SafeRegister"];

fn is_event_like(text: &str) -> bool {
    text.len() > 3
        && text.contains('_')
        && text.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
        && text.chars().next().is_some_and(|c| c.is_ascii_uppercase())
}

fn name(word: Option<&Word>) -> Option<&str> {
    match word.map(|word| &word.token) {
        Some(Token::Name(name)) => Some(name.as_str()),
        _ => None,
    }
}

fn symbol(word: Option<&Word>) -> Option<&str> {
    match word.map(|word| &word.token) {
        Some(Token::Symbol(symbol)) => Some(symbol.as_str()),
        _ => None,
    }
}

/// What the game has, from the API snapshot and from the stand-in.
pub struct Known {
    /// Namespace -> its functions.
    pub namespaces: BTreeMap<String, BTreeSet<String>>,
    /// Enumeration -> its fields.
    pub enums: BTreeMap<String, BTreeSet<String>>,
    pub events: BTreeSet<String>,
    pub globals: BTreeSet<String>,
    pub methods: BTreeSet<String>,
}

impl Known {
    /// `globals` and `methods` are the names of the stand-in (see `tools/harness/names.lua`).
    pub fn new(snapshot: &serde_json::Value, globals: Vec<String>, methods: Vec<String>) -> Self {
        let keys = |value: Option<&serde_json::Value>| -> BTreeSet<String> {
            value.and_then(|value| value.as_object()).map(|map| map.keys().cloned().collect()).unwrap_or_default()
        };
        let nested = |key: &str| -> BTreeMap<String, BTreeSet<String>> {
            snapshot
                .get(key)
                .and_then(|value| value.as_object())
                .map(|map| map.iter().map(|(name, inner)| (name.clone(), keys(Some(inner)))).collect())
                .unwrap_or_default()
        };
        let mut enums = nested("enums");
        // Enum.<Name>Meta has the number of values and the lowest and the highest one.
        for name in keys(snapshot.get("enumMeta")) {
            enums.insert(format!("{name}Meta"), ["NumValues", "MinValue", "MaxValue"].iter().map(|field| field.to_string()).collect());
        }
        Self {
            namespaces: nested("namespaces"),
            enums,
            events: keys(snapshot.get("events")),
            globals: globals.into_iter().collect(),
            methods: methods.into_iter().collect(),
        }
    }
}

/// What the files of one addon define themselves.
#[derive(Default)]
struct Defined {
    globals: BTreeSet<String>,
    methods: BTreeSet<String>,
    /// Every text of the addon: a frame made with a name becomes a global of that name.
    texts: BTreeSet<String>,
}

/// The local names of a file (not by scope: a name that is local anywhere in the file counts).
fn locals(list: &[Word]) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    let mut index = 0;
    while index < list.len() {
        match name(list.get(index)) {
            Some("local") => {
                index += 1;
                if name(list.get(index)) == Some("function") {
                    // `local function name(...)`: the name is local, and the parameters follow.
                    if let Some(found) = name(list.get(index + 1)) {
                        out.insert(found.to_string());
                    }
                    continue;
                }
                while let Some(found) = name(list.get(index)) {
                    out.insert(found.to_string());
                    index += 1;
                    if symbol(list.get(index)) == Some(",") {
                        index += 1;
                    } else {
                        break;
                    }
                }
            }
            Some("function") => {
                // The parameters, after the name of the function if it has one.
                index += 1;
                while index < list.len() && symbol(list.get(index)) != Some("(") {
                    index += 1;
                }
                index += 1;
                while index < list.len() && symbol(list.get(index)) != Some(")") {
                    if let Some(found) = name(list.get(index)) {
                        out.insert(found.to_string());
                    }
                    index += 1;
                }
            }
            Some("for") => {
                index += 1;
                while let Some(found) = name(list.get(index)) {
                    if found == "in" {
                        break;
                    }
                    out.insert(found.to_string());
                    index += 1;
                    if symbol(list.get(index)) == Some(",") {
                        index += 1;
                    } else {
                        break;
                    }
                }
            }
            _ => index += 1,
        }
    }
    out
}

/// True if the word at `index` is a name that stands alone: not a field and not a method.
fn stands_alone(list: &[Word], index: usize) -> bool {
    index == 0 || !matches!(symbol(list.get(index - 1)), Some(".") | Some(":"))
}

/// True if the name at `index` ends the name of a function definition: `function a.b:name`.
/// A call, `a.b:name(`, has no `function` before it.
fn after_function(list: &[Word], index: usize) -> bool {
    let mut at = index;
    while at >= 2 && matches!(symbol(list.get(at - 1)), Some(".") | Some(":")) && name(list.get(at - 2)).is_some() {
        at -= 2;
    }
    at >= 1 && name(list.get(at - 1)) == Some("function")
}

/// Reads what a file defines: global names it assigns, and methods and function fields.
fn definitions(list: &[Word], file_locals: &BTreeSet<String>, defined: &mut Defined) {
    let mut braces = 0usize;
    for index in 0..list.len() {
        match &list[index].token {
            Token::Symbol(found) if found == "{" => braces += 1,
            Token::Symbol(found) if found == "}" => braces = braces.saturating_sub(1),
            Token::Text(text) => {
                defined.texts.insert(text.clone());
            }
            Token::Name(found) => {
                let next = symbol(list.get(index + 1));
                let previous = if index > 0 { symbol(list.get(index - 1)) } else { None };
                // `function Object:Method(`, `function Object.Field(`, `Object.Field = function`,
                // and a key of a table: each can be called as a method or a field later.
                if matches!(previous, Some(".") | Some(":")) && (next == Some("=") || (next == Some("(") && after_function(list, index))) {
                    defined.methods.insert(found.clone());
                } else if braces > 0 && next == Some("=") && stands_alone(list, index) {
                    defined.methods.insert(found.clone());
                } else if braces == 0 && stands_alone(list, index) && !file_locals.contains(found) && !KEYWORDS.contains(&found.as_str()) {
                    // `Name = value` and `function Name(` outside a table make a global.
                    let function_name = index > 0 && name(list.get(index - 1)) == Some("function");
                    if next == Some("=") || function_name {
                        defined.globals.insert(found.clone());
                    }
                }
            }
            _ => {}
        }
    }
}

/// Checks one file. `problems` gets one line for each name that the game does not have.
fn check_file(place: &str, list: &[Word], file_locals: &BTreeSet<String>, defined: &Defined, known: &Known, problems: &mut Vec<String>) {
    let mut seen: BTreeSet<String> = BTreeSet::new();
    let mut report = |line: u32, text: String| {
        if seen.insert(text.clone()) {
            problems.push(format!("{place}:{line}: {text}"));
        }
    };
    let mut braces = 0usize;
    for index in 0..list.len() {
        let line = list[index].line;
        match &list[index].token {
            Token::Symbol(found) if found == "{" => {
                braces += 1;
                // A list of texts that look like event names, with at least one event among them.
                let mut texts = Vec::new();
                let mut at = index + 1;
                let mut only_texts = true;
                while at < list.len() && symbol(list.get(at)) != Some("}") {
                    match &list[at].token {
                        Token::Text(text) => texts.push((list[at].line, text.clone())),
                        Token::Symbol(separator) if separator == "," => {}
                        _ => {
                            only_texts = false;
                            break;
                        }
                    }
                    at += 1;
                }
                if only_texts && texts.len() > 1 && texts.iter().all(|(_, text)| is_event_like(text)) && texts.iter().any(|(_, text)| known.events.contains(text)) {
                    for (text_line, text) in texts {
                        if !known.events.contains(&text) {
                            report(text_line, format!("the event {text} is not in the API of this client"));
                        }
                    }
                }
            }
            Token::Symbol(found) if found == "}" => braces = braces.saturating_sub(1),
            Token::Name(found) => {
                let next = symbol(list.get(index + 1));
                let after = name(list.get(index + 2));
                let alone = stands_alone(list, index);
                if alone && found.starts_with("C_") && !file_locals.contains(found) {
                    match known.namespaces.get(found) {
                        None if !known.globals.contains(found) => report(line, format!("{found} is not in the API of this client")),
                        Some(functions) if next == Some(".") => {
                            if let Some(function) = after {
                                if !functions.contains(function) {
                                    report(line, format!("{found}.{function} is not in the API of this client"));
                                }
                            }
                        }
                        _ => {}
                    }
                } else if alone && found == "Enum" && next == Some(".") {
                    if let Some(enumeration) = after {
                        match known.enums.get(enumeration) {
                            None => report(line, format!("Enum.{enumeration} is not in the API of this client")),
                            Some(fields) => {
                                if symbol(list.get(index + 3)) == Some(".") {
                                    if let Some(field) = name(list.get(index + 4)) {
                                        if !fields.contains(field) {
                                            report(line, format!("Enum.{enumeration}.{field} is not in the API of this client"));
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else if !alone && index > 0 && symbol(list.get(index - 1)) == Some(":") {
                    // `object:Method(...)`, `object:Method "text"`, `object:Method { ... }`.
                    let called = matches!(next, Some("(") | Some("{")) || matches!(list.get(index + 1).map(|word| &word.token), Some(Token::Text(_)));
                    if called && !known.methods.contains(found) && !defined.methods.contains(found) {
                        report(line, format!("no object of the game and no table of the addon has a method {found}"));
                    }
                } else if alone
                    && !KEYWORDS.contains(&found.as_str())
                    && !LUA_GLOBALS.contains(&found.as_str())
                    && !file_locals.contains(found)
                    && !(braces > 0 && next == Some("="))
                    && !known.globals.contains(found)
                    && !defined.globals.contains(found)
                    && !defined.texts.contains(found)
                {
                    report(line, format!("the global name {found} is not in the API of this client and the addon does not define it"));
                }
                // The event name after RegisterEvent and the like.
                if EVENT_FUNCTIONS.contains(&found.as_str()) {
                    for word in list.iter().skip(index + 1).take(6) {
                        match &word.token {
                            Token::Text(text) if is_event_like(text) => {
                                if !known.events.contains(text) {
                                    report(word.line, format!("the event {text} is not in the API of this client"));
                                }
                                break;
                            }
                            Token::Symbol(end) if end == ")" => break,
                            _ => {}
                        }
                    }
                }
            }
            _ => {}
        }
    }
}

/// Checks every addon. Returns one line for each name that the game does not have.
pub fn check(addons: &[Addon], known: &Known) -> Result<Vec<String>, String> {
    let mut problems = Vec::new();
    for addon in addons {
        let Some(toc) = &addon.toc else { continue };
        let mut files = Vec::new();
        for file in &toc.files {
            // The settings kit is the same file in every addon: one report is enough.
            if !file.to_lowercase().ends_with(".lua") {
                continue;
            }
            let path = addon.dir.join(file);
            let source = fs::read_to_string(&path).map_err(|error| format!("Cannot read {}: {error}", path.display()))?;
            let list = words(&source);
            let file_locals = locals(&list);
            files.push((file.clone(), list, file_locals));
        }
        // What one file defines, another file of the addon can use.
        let mut defined = Defined::default();
        if let Some(saved) = toc.fields.get("SavedVariables") {
            defined.globals.extend(saved.split(',').map(|name| name.trim().to_string()));
        }
        if let Some(saved) = toc.fields.get("SavedVariablesPerCharacter") {
            defined.globals.extend(saved.split(',').map(|name| name.trim().to_string()));
        }
        for (_, list, file_locals) in &files {
            definitions(list, file_locals, &mut defined);
        }
        for (file, list, file_locals) in &files {
            check_file(&format!("{}/{file}", addon.folder), list, file_locals, &defined, known, &mut problems);
        }
    }
    Ok(problems)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn known() -> Known {
        let snapshot = serde_json::json!({
            "namespaces": { "C_Item": { "GetItemInfo": "s|a|" } },
            "enums": { "BagIndex": { "Backpack": 0 } },
            "enumMeta": { "BagIndex": [1, 0, 0] },
            "events": { "PLAYER_LOGIN": "", "BAG_UPDATE": "n" },
        });
        Known::new(&snapshot, vec!["UnitName".into(), "CreateFrame".into(), "C_Item".into()], vec!["SetText".into(), "RegisterEvent".into(), "lower".into()])
    }

    fn problems(source: &str) -> Vec<String> {
        let list = words(source);
        let file_locals = locals(&list);
        let mut defined = Defined::default();
        definitions(&list, &file_locals, &mut defined);
        let mut out = Vec::new();
        check_file("Addon/File.lua", &list, &file_locals, &defined, &known(), &mut out);
        out
    }

    #[test]
    fn source_is_taken_apart_without_comments_and_with_line_numbers() {
        let list = words("local a = 1 -- C_Fake.Call()\n--[[ long\ncomment ]] b:Method('text', [[long\ntext]])\n");
        let names: Vec<&str> = list.iter().filter_map(|word| name(Some(word))).collect();
        assert_eq!(names, ["local", "a", "b", "Method"]);
        assert_eq!(list.last().unwrap().line, 4);
        assert!(list.iter().any(|word| word.token == Token::Text("long\ntext".into())));
    }

    #[test]
    fn names_of_the_api_pass() {
        let source = r#"
            local name, ns = ...
            local frame = CreateFrame("Frame", "MyGlobalFrame")
            frame:RegisterEvent("PLAYER_LOGIN")
            local text = UnitName("player"):lower()
            local info = C_Item.GetItemInfo(1)
            local bag = Enum.BagIndex.Backpack + Enum.BagIndexMeta.NumValues
            function ns.Helper(value) return value end
            function ns:Update() self:SetText("x") end
            ns:Update()
            MyAddonDB = MyAddonDB or {}
            MyGlobalFrame:SetText(ns.Helper(1))
            local t = { key = 1, other = text, Run = function() end }
            t:Run()
            for _, event in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE" }) do frame:RegisterEvent(event) end
        "#;
        assert_eq!(problems(source), Vec::<String>::new());
    }

    #[test]
    fn names_that_the_game_does_not_have_are_reported_with_file_and_line() {
        let found = problems("local a = C_Item.GetItemCount(1)\nlocal b = C_Fake.Call()\n");
        assert_eq!(found, [
            "Addon/File.lua:1: C_Item.GetItemCount is not in the API of this client",
            "Addon/File.lua:2: C_Fake is not in the API of this client",
        ]);
        assert!(problems("local x = Enum.BagIndex.Bank")[0].contains("Enum.BagIndex.Bank"));
        assert!(problems("local x = Enum.NoSuchEnum.Value")[0].contains("Enum.NoSuchEnum"));
        assert!(problems("local f = CreateFrame('Frame')\nf:RegisterEvent('PLAYER_LOGGED_IN')")[0].contains("the event PLAYER_LOGGED_IN"));
        assert!(problems("local list = { 'PLAYER_LOGIN', 'BAG_UPDATED' }")[0].contains("the event BAG_UPDATED"));
        assert!(problems("local f = CreateFrame('Frame')\nf:SetTextt('x')")[0].contains("a method SetTextt"));
        // A fallback for another client: the name is not on this client, so the code is dead.
        assert!(problems("local get = C_Item and C_Item.GetItemInfo or GetItemInfo")[0].contains("the global name GetItemInfo"));
        // A comment and a text are not code.
        assert_eq!(problems("-- C_Fake.Call()\nlocal s = 'C_Fake.Call() NoSuchGlobal'"), Vec::<String>::new());
    }
}
