//! What Blizzard's API documentation does not list, read from the game's own UI files:
//!
//! - the fonts that a font string can inherit;
//! - the events that the game's code registers and the documentation leaves out;
//! - the frame types and the animation types (`Blizzard_SharedXML/UI.xsd` and the intrinsic frames);
//! - the scripts that the game's XML files put on each kind of widget;
//! - every template of the XML files: its kind, what it inherits, its mixins, its child keys;
//! - the methods of the mixins that the templates name;
//! - the calls of widget methods in the game's Lua code whose arguments are all written out
//!   (`frame:SetAttribute("shown", true)`): the stand-in must accept each of them.
//!
//! The UI files come from outside this repository. They are read as text only, and a name is
//! taken only if it is made of letters, digits and underscores.

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::fs;
use std::path::Path;

use serde_json::{json, Value};

/// Folders with the files of another game client. This client reads Mainline, Camelot and Shared.
const OTHER_CLIENTS: [&str; 9] = ["Classic", "Cata", "Mists", "Wrath", "Vanilla", "TBC", "WoWLabs", "WoWHack", "Unused"];

/// Parts of the game that an addon never runs in: the screens before the game world, the shop
/// and the debug tools. An event, a template or a call that only these have is not taken.
const NOT_IN_THE_WORLD: [&str; 9] = ["Glue", "CharacterCreate", "CharacterSelect", "Login", "Store", "Debug", "APIDocumentation", "Console", "Kiosk"];

fn is_name(text: &str) -> bool {
    !text.is_empty() && text.len() <= 80 && text.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn is_event_name(text: &str) -> bool {
    // Nearly all are upper case; the game also has Perks_Program_CLOSE.
    let upper = text.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_');
    is_name(text) && text.chars().next().is_some_and(|c| c.is_ascii_uppercase()) && (upper || text.contains('_'))
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

/// The names in an attribute with a list: `inherits="A, B"`.
fn names_of(list: Option<&str>) -> Vec<String> {
    list.unwrap_or("").split(|c: char| c == ',' || c.is_whitespace()).filter(|name| is_name(name)).map(String::from).collect()
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

/// The event names that a Lua file registers, or takes away, with a literal text.
fn events_of(lua: &str, out: &mut BTreeSet<String>) {
    for call in ["RegisterEvent(", "RegisterUnitEvent(", "UnregisterEvent("] {
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

// ---------------------------------------------------------------------------------------------
// UI.xsd: the element types of the game's XML files

/// What `UI.xsd` says about the elements of the XML files.
#[derive(Default)]
pub struct Schema {
    /// Element name -> the kind of widget that it makes: `Button` -> `Button`,
    /// `NormalTexture` -> `Texture`, `ButtonText` -> `FontString`.
    objects: BTreeMap<String, String>,
    /// Frame type -> the frame type that it is made from (`CheckButton` -> `Button`); `Frame` -> "".
    frame_types: BTreeMap<String, String>,
    animation_types: BTreeSet<String>,
    /// The lists of allowed texts: `DRAWLAYER` -> BACKGROUND, BORDER, ...
    enumerations: BTreeMap<String, Vec<String>>,
}

fn strip_prefix(name: &str) -> &str {
    name.strip_prefix("ui:").unwrap_or(name)
}

fn kind_of_type(type_name: &str) -> &str {
    type_name.strip_suffix("Type").unwrap_or(type_name)
}

fn schema_of(xsd: &str) -> Schema {
    // complexType name -> the type that it extends
    let mut bases: BTreeMap<String, String> = BTreeMap::new();
    let mut rest = xsd;
    while let Some(at) = rest.find("<xs:complexType") {
        rest = &rest[at + 1..];
        let end = rest.find('>').unwrap_or(rest.len());
        let Some(name) = attribute(&rest[..end], "name") else { continue };
        let body_end = rest.find("</xs:complexType>").unwrap_or(rest.len());
        let body = &rest[..body_end];
        if let Some(extension) = body.find("<xs:extension") {
            let tag_end = body[extension..].find('>').map(|end| extension + end).unwrap_or(body.len());
            if let Some(base) = attribute(&body[extension + 1..tag_end], "base") {
                bases.insert(name.to_string(), strip_prefix(base).to_string());
            }
        }
    }
    // The elements with a name and a type: (name, type, substitution group).
    let mut elements: Vec<(String, String, String)> = Vec::new();
    let mut rest = xsd;
    while let Some(at) = rest.find("<xs:element") {
        rest = &rest[at + 1..];
        let end = rest.find('>').unwrap_or(rest.len());
        let tag = &rest[..end];
        let (Some(name), Some(type_name)) = (attribute(tag, "name"), attribute(tag, "type")) else { continue };
        if is_name(name) {
            let group = attribute(tag, "substitutionGroup").map(strip_prefix).unwrap_or("");
            elements.push((name.to_string(), strip_prefix(type_name).to_string(), group.to_string()));
        }
    }
    // An element of the group FrameRef is a frame type, one of LayoutFrameRef a region, one of
    // AnimationRef an animation.
    let frames: BTreeSet<&str> = elements.iter().filter(|(_, _, group)| group == "FrameRef").map(|(name, _, _)| name.as_str()).collect();
    let regions: BTreeSet<&str> = elements.iter().filter(|(name, _, group)| group == "LayoutFrameRef" && name != "FrameRef").map(|(name, _, _)| name.as_str()).collect();
    let mut schema = Schema::default();
    // <xs:simpleType name="DRAWLAYER"> with a list of <xs:enumeration value="..."/>.
    let mut rest = xsd;
    while let Some(at) = rest.find("<xs:simpleType") {
        rest = &rest[at + 1..];
        let end = rest.find('>').unwrap_or(rest.len());
        let Some(name) = attribute(&rest[..end], "name").filter(|name| is_name(name)) else { continue };
        let body = &rest[..rest.find("</xs:simpleType>").unwrap_or(rest.len())];
        let mut values = Vec::new();
        let mut inner = body;
        while let Some(at) = inner.find("<xs:enumeration") {
            inner = &inner[at + 1..];
            let end = inner.find('>').unwrap_or(inner.len());
            if let Some(value) = attribute(&inner[..end], "value").filter(|value| is_name(value)) {
                values.push(value.to_string());
            }
        }
        if !values.is_empty() {
            schema.enumerations.insert(name.to_string(), values);
        }
    }
    for (name, type_name, group) in &elements {
        if frames.contains(name.as_str()) {
            // The frame type that this one is made from: the type of the element if the element
            // has another name (ItemButton is a ButtonType), else the type that its type extends
            // (CheckButtonType extends ButtonType), else Frame.
            let own = format!("{name}Type");
            let base = if *type_name != own {
                kind_of_type(type_name).to_string()
            } else {
                bases.get(type_name).map(|base| kind_of_type(base).to_string()).filter(|base| frames.contains(base.as_str())).unwrap_or_else(|| "Frame".to_string())
            };
            let base = if name == "Frame" { String::new() } else { base };
            schema.frame_types.entry(name.clone()).or_insert(base);
            schema.objects.entry(name.clone()).or_insert_with(|| name.clone());
        } else if regions.contains(name.as_str()) || name == "AnimationGroup" || name == "Actor" {
            schema.objects.entry(name.clone()).or_insert_with(|| name.clone());
        } else if group == "AnimationRef" {
            schema.animation_types.insert(name.clone());
            schema.objects.entry(name.clone()).or_insert_with(|| name.clone());
        } else if regions.contains(kind_of_type(type_name)) {
            // A part of a frame that is a region: NormalTexture is a Texture, ButtonText a FontString.
            schema.objects.entry(name.clone()).or_insert_with(|| kind_of_type(type_name).to_string());
        }
    }
    schema
}

// ---------------------------------------------------------------------------------------------
// The XML files: scripts, templates

struct Tag<'a> {
    name: &'a str,
    text: &'a str,
    closes: bool,
    opens: bool,
}

struct Scanner<'a> {
    text: &'a str,
    at: usize,
}

impl<'a> Scanner<'a> {
    fn next_tag(&mut self) -> Option<Tag<'a>> {
        loop {
            let start = self.at + self.text[self.at..].find('<')?;
            let rest = &self.text[start..];
            for (open, close) in [("<!--", "-->"), ("<![CDATA[", "]]>"), ("<?", "?>")] {
                if rest.starts_with(open) {
                    self.at = rest.find(close).map(|end| start + end + close.len()).unwrap_or(self.text.len());
                }
            }
            if self.at > start {
                continue;
            }
            // The end of the tag: a `>` outside a quoted value.
            let mut quote = None;
            let mut end = None;
            for (index, c) in rest.char_indices().skip(1) {
                match quote {
                    Some(q) if c == q => quote = None,
                    Some(_) => {}
                    None if c == '"' || c == '\'' => quote = Some(c),
                    None if c == '>' => {
                        end = Some(index);
                        break;
                    }
                    None => {}
                }
            }
            let Some(end) = end else {
                self.at = self.text.len();
                return None;
            };
            self.at = start + end + 1;
            let inner = rest[1..end].trim();
            if inner.starts_with('!') {
                continue;
            }
            let closes_only = inner.starts_with('/');
            let self_closing = inner.ends_with('/');
            let body = inner.trim_start_matches('/').trim_end_matches('/').trim();
            let name = body.split(|c: char| c.is_whitespace()).next().unwrap_or("");
            return Some(Tag { name, text: body, closes: closes_only || self_closing, opens: !closes_only });
        }
    }

    /// Skips the body of an element that holds Lua code: it can have a `<` that is not a tag.
    fn skip_past(&mut self, element: &str) {
        let close = format!("</{element}");
        let Some(start) = self.text[self.at..].find(&close).map(|end| self.at + end) else {
            self.at = self.text.len();
            return;
        };
        // Past the closing tag too: the element was not put on the list of open elements.
        self.at = self.text[start..].find('>').map(|end| start + end + 1).unwrap_or(self.text.len());
    }
}

/// One widget that an XML file makes: a template, or a child of one.
#[derive(Default)]
struct Widget {
    element: String,
    kind: String,
    key: Option<String>,
    array: Option<String>,
    /// The part of the name after `$parent`.
    name: Option<String>,
    inherits: Vec<String>,
    mixin: Vec<String>,
    children: Vec<usize>,
    values: BTreeMap<String, (String, String)>,
    scripts: BTreeSet<String>,
    /// A template: a frame that inherits it can be of another kind (a Button from a Frame
    /// template), so its scripts say nothing about the kind of the element.
    template: bool,
}

#[derive(Default)]
struct Found {
    /// Element name -> the scripts that the XML files put on it.
    scripts: BTreeMap<String, BTreeSet<String>>,
    /// Template name -> its record.
    templates: BTreeMap<String, Value>,
    /// Intrinsic frame type -> the frame type that it is made from.
    intrinsics: BTreeMap<String, String>,
    /// Mixins that a template or a child of one names.
    mixins: BTreeSet<String>,
}

fn record(widgets: &[Widget], index: usize, root: bool, mixins: &mut BTreeSet<String>) -> Value {
    let widget = &widgets[index];
    let mut map = serde_json::Map::new();
    map.insert("kind".into(), json!(widget.kind));
    if !root && widget.element != widget.kind {
        // A part of a frame with its own element: <ButtonText> is the font string of a button.
        map.insert("part".into(), json!(widget.element));
    }
    if !root {
        if let Some(key) = &widget.key {
            map.insert("key".into(), json!(key));
        }
        if let Some(array) = &widget.array {
            map.insert("array".into(), json!(array));
        }
        if let Some(name) = &widget.name {
            map.insert("name".into(), json!(name));
        }
    }
    if !widget.inherits.is_empty() {
        map.insert("inherits".into(), json!(widget.inherits));
    }
    if !widget.mixin.is_empty() {
        map.insert("mixin".into(), json!(widget.mixin));
        mixins.extend(widget.mixin.iter().cloned());
    }
    // A child that nothing can reach (no key, no place in a list, no name) is left out, with
    // what is under it.
    let children: Vec<Value> = widget
        .children
        .iter()
        .filter(|child| {
            let child = &widgets[**child];
            child.key.is_some() || child.array.is_some() || child.name.is_some()
        })
        .map(|child| record(widgets, *child, false, mixins))
        .collect();
    if !children.is_empty() {
        map.insert("children".into(), json!(children));
    }
    if !widget.values.is_empty() {
        let values: BTreeMap<&String, [&String; 2]> = widget.values.iter().map(|(key, (kind, value))| (key, [kind, value])).collect();
        map.insert("values".into(), json!(values));
    }
    if root && !widget.scripts.is_empty() {
        map.insert("scripts".into(), json!(widget.scripts));
    }
    Value::Object(map)
}

/// Reads one XML file. `templates`: take the templates of this file too (not for the parts of
/// the game that an addon never runs in).
fn xml_of(xml: &str, schema: &Schema, templates: bool, found: &mut Found) {
    let mut scanner = Scanner { text: xml, at: 0 };
    let mut widgets: Vec<Widget> = Vec::new();
    // The open elements: the name, and the widget that the element makes, if it makes one.
    let mut stack: Vec<(String, Option<usize>)> = Vec::new();
    let mut roots: Vec<(String, usize)> = Vec::new();
    while let Some(tag) = scanner.next_tag() {
        if !tag.opens {
            // A closing tag without its opening tag is passed over.
            if let Some(at) = stack.iter().rposition(|(name, _)| name == tag.name) {
                stack.truncate(at);
            }
            continue;
        }
        let parent = stack.last().map(|(name, _)| name.as_str()).unwrap_or("");
        let owner = stack.iter().rev().find_map(|(_, widget)| *widget);
        if parent == "Scripts" {
            if is_name(tag.name) {
                if let Some(owner) = owner {
                    if !widgets[owner].template {
                        found.scripts.entry(widgets[owner].element.clone()).or_default().insert(tag.name.to_string());
                    }
                    widgets[owner].scripts.insert(tag.name.to_string());
                }
            }
            if !tag.closes {
                scanner.skip_past(tag.name);
            }
            continue;
        }
        if tag.name == "Script" {
            if !tag.closes {
                scanner.skip_past(tag.name);
            }
            continue;
        }
        if tag.name == "KeyValue" && parent == "KeyValues" {
            if let (Some(owner), Some(key)) = (owner, attribute(tag.text, "key")) {
                if is_name(key) {
                    let kind = attribute(tag.text, "type").unwrap_or("string");
                    let value = attribute(tag.text, "value").unwrap_or("");
                    if is_name(kind) && value.len() <= 120 && !value.contains(['\\', '"']) && value.is_ascii() {
                        widgets[owner].values.insert(key.to_string(), (kind.to_string(), value.to_string()));
                    }
                }
            }
        }
        let mut made = None;
        if let Some(kind) = schema.objects.get(tag.name) {
            let name = attribute(tag.text, "name");
            let mut mixin = names_of(attribute(tag.text, "mixin"));
            mixin.extend(names_of(attribute(tag.text, "secureMixin")));
            let widget = Widget {
                element: tag.name.to_string(),
                kind: kind.clone(),
                key: attribute(tag.text, "parentKey").filter(|key| is_name(key)).map(String::from),
                array: attribute(tag.text, "parentArray").filter(|key| is_name(key)).map(String::from),
                name: name.and_then(|name| name.strip_prefix("$parent")).filter(|suffix| is_name(suffix)).map(String::from),
                inherits: names_of(attribute(tag.text, "inherits")),
                mixin,
                template: owner.is_none() && attribute(tag.text, "virtual") == Some("true"),
                ..Widget::default()
            };
            let index = widgets.len();
            widgets.push(widget);
            match owner {
                Some(owner) => widgets[owner].children.push(index),
                None => {
                    if let Some(name) = name.filter(|name| is_name(name)) {
                        if attribute(tag.text, "intrinsic") == Some("true") {
                            found.intrinsics.insert(name.to_string(), tag.name.to_string());
                            roots.push((name.to_string(), index));
                        } else if attribute(tag.text, "virtual") == Some("true") {
                            roots.push((name.to_string(), index));
                        }
                    }
                }
            }
            made = Some(index);
        }
        if !tag.closes {
            stack.push((tag.name.to_string(), made));
        }
    }
    if templates {
        for (name, index) in roots {
            if widgets[index].element != "Font" && widgets[index].element != "FontFamily" {
                let value = record(&widgets, index, true, &mut found.mixins);
                found.templates.entry(name).or_insert(value);
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// The Lua files: mixins and calls

/// `function Name:Method(` and `function Name.Method(` at the start of a line, and
/// `Name = CreateFromMixins(A, B)`.
fn mixins_of(lua: &str, methods: &mut BTreeMap<String, BTreeSet<String>>, parents: &mut BTreeMap<String, BTreeSet<String>>) {
    for line in lua.lines() {
        if let Some(rest) = line.strip_prefix("function ") {
            let Some(paren) = rest.find('(') else { continue };
            let head = rest[..paren].trim();
            let Some(split) = head.find([':', '.']) else { continue };
            let (owner, method) = (&head[..split], &head[split + 1..]);
            if is_name(owner) && is_name(method) {
                methods.entry(owner.to_string()).or_default().insert(method.to_string());
            }
        } else if let Some(at) = line.find("CreateFromMixins(") {
            let Some(name) = line[..at].trim_end().strip_suffix('=').map(str::trim) else { continue };
            if !is_name(name) {
                continue;
            }
            let arguments = &line[at + "CreateFromMixins(".len()..];
            let arguments = &arguments[..arguments.find(')').unwrap_or(arguments.len())];
            for parent in names_of(Some(arguments)) {
                parents.entry(name.to_string()).or_default().insert(parent);
            }
        }
    }
}

/// The length of a Lua literal at the start of the text: a quoted text, a number, true, false or nil.
fn literal(text: &str) -> Option<usize> {
    let bytes = text.as_bytes();
    let first = *bytes.first()?;
    if first == b'"' || first == b'\'' {
        let mut index = 1;
        while index < bytes.len() {
            match bytes[index] {
                b'\\' => index += 2,
                b'\n' | b'\r' => return None,
                c if c == first => return Some(index + 1),
                _ => index += 1,
            }
        }
        return None;
    }
    for word in ["true", "false", "nil"] {
        if text.starts_with(word) && !bytes.get(word.len()).is_some_and(|c| c.is_ascii_alphanumeric() || *c == b'_') {
            return Some(word.len());
        }
    }
    let mut index = usize::from(first == b'-');
    let digits = index;
    while bytes.get(index).is_some_and(u8::is_ascii_digit) {
        index += 1;
    }
    if index == digits {
        return None;
    }
    if bytes.get(index) == Some(&b'.') && bytes.get(index + 1).is_some_and(u8::is_ascii_digit) {
        index += 1;
        while bytes.get(index).is_some_and(u8::is_ascii_digit) {
            index += 1;
        }
    }
    // `1e5`, `0x10` and a name after the digits are not taken.
    if bytes.get(index).is_some_and(|c| c.is_ascii_alphanumeric() || *c == b'_' || *c == b'.') {
        return None;
    }
    Some(index)
}

/// The calls `receiver:Method(literal, literal, ...)` of one Lua file, for the given methods.
/// The text of a call is `Method(arguments)` with one space after each comma.
fn calls_of(lua: &str, methods: &HashSet<String>, out: &mut BTreeSet<String>) {
    for line in lua.lines() {
        if line.trim_start().starts_with("--") {
            continue;
        }
        let bytes = line.as_bytes();
        let mut from = 0;
        while let Some(colon) = line[from..].find(':').map(|at| from + at) {
            from = colon + 1;
            // The receiver ends with a name, `]` or `)`.
            if colon == 0 || !(bytes[colon - 1].is_ascii_alphanumeric() || matches!(bytes[colon - 1], b'_' | b']' | b')')) {
                continue;
            }
            let rest = &line[colon + 1..];
            let name_length = rest.bytes().take_while(|c| c.is_ascii_alphanumeric() || *c == b'_').count();
            if name_length == 0 || rest.as_bytes().get(name_length) != Some(&b'(') {
                continue;
            }
            let name = &rest[..name_length];
            if !methods.contains(name) {
                continue;
            }
            let mut arguments: Vec<&str> = Vec::new();
            let mut at = name_length + 1;
            let complete = loop {
                at += rest[at..].len() - rest[at..].trim_start().len();
                if rest[at..].starts_with(')') {
                    break arguments.is_empty();
                }
                let Some(length) = literal(&rest[at..]) else { break false };
                arguments.push(&rest[at..at + length]);
                at += length;
                at += rest[at..].len() - rest[at..].trim_start().len();
                if rest[at..].starts_with(')') {
                    break true;
                }
                if !rest[at..].starts_with(',') {
                    break false;
                }
                at += 1;
            };
            if complete && arguments.iter().all(|argument| argument.is_ascii()) {
                out.insert(format!("{name}({})", arguments.join(", ")));
            }
        }
    }
}

/// The anchors of a tooltip that a Lua file names: `tooltip:SetOwner(self, "ANCHOR_RIGHT")`.
fn anchors_of(lua: &str, out: &mut BTreeSet<String>) {
    let mut rest = lua;
    while let Some(at) = rest.find("\"ANCHOR_") {
        rest = &rest[at + 1..];
        if let Some(end) = rest.find('"') {
            let name = &rest[..end];
            if is_name(name) && name.chars().all(|c| c.is_ascii_uppercase() || c == '_') {
                out.insert(name.to_string());
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------

struct Collected {
    fonts: BTreeSet<String>,
    events: BTreeSet<String>,
    found: Found,
    mixin_methods: BTreeMap<String, BTreeSet<String>>,
    mixin_parents: BTreeMap<String, BTreeSet<String>>,
    calls: BTreeSet<String>,
    anchors: BTreeSet<String>,
    files: usize,
}

fn walk(dir: &Path, in_world: bool, schema: &Schema, methods: &HashSet<String>, out: &mut Collected) -> Result<(), String> {
    let mut entries: Vec<_> = fs::read_dir(dir).map_err(|error| format!("Cannot read {}: {error}", dir.display()))?.flatten().map(|entry| entry.path()).collect();
    entries.sort();
    for path in entries {
        let name = path.file_name().unwrap_or_default().to_string_lossy().into_owned();
        if path.is_dir() {
            if !OTHER_CLIENTS.contains(&name.as_str()) {
                walk(&path, in_world, schema, methods, out)?;
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
        out.files += 1;
        if extension == "xml" {
            fonts_of(&text, &mut out.fonts);
            xml_of(&text, schema, in_world, &mut out.found);
        } else if in_world {
            events_of(&text, &mut out.events);
            mixins_of(&text, &mut out.mixin_methods, &mut out.mixin_parents);
            calls_of(&text, methods, &mut out.calls);
            anchors_of(&text, &mut out.anchors);
        }
    }
    Ok(())
}

/// A JSON object with one entry on each line.
fn lines_of(map: &BTreeMap<String, Value>) -> String {
    if map.is_empty() {
        return "{}".to_string();
    }
    let entries: Vec<String> = map.iter().map(|(key, value)| format!("    {}: {}", Value::String(key.clone()), value)).collect();
    format!("{{\n{}\n  }}", entries.join(",\n"))
}

/// A JSON list of texts with one entry on each line.
fn list_of(names: impl IntoIterator<Item = String>) -> String {
    let entries: Vec<String> = names.into_iter().map(|name| format!("    {}", Value::String(name))).collect();
    if entries.is_empty() {
        return "[]".to_string();
    }
    format!("[\n{}\n  ]", entries.join(",\n"))
}

/// Reads the `Interface/AddOns` folder of the UI source.
///
/// `snapshot`: the API snapshot, for the events that the documentation has already and for the
/// note of the source. `widget_methods`: the names of the methods of the widgets, for the calls.
pub fn collect(addons_dir: &Path, snapshot: &Value, widget_methods: &[String]) -> Result<(String, Vec<String>), String> {
    let xsd_file = addons_dir.join("Blizzard_SharedXML").join("UI.xsd");
    let xsd = fs::read(&xsd_file).map_err(|error| format!("Cannot read {}: {error}. Give the Interface/AddOns folder of the UI source.", xsd_file.display()))?;
    let schema = schema_of(&String::from_utf8_lossy(&xsd));
    if !schema.frame_types.contains_key("Button") {
        return Err(format!("{} does not have the frame types.", xsd_file.display()));
    }
    let methods: HashSet<String> = widget_methods.iter().cloned().collect();
    let mut out = Collected {
        fonts: BTreeSet::new(),
        events: BTreeSet::new(),
        found: Found::default(),
        mixin_methods: BTreeMap::new(),
        mixin_parents: BTreeMap::new(),
        calls: BTreeSet::new(),
        anchors: BTreeSet::new(),
        files: 0,
    };
    let mut folders: Vec<_> = fs::read_dir(addons_dir).map_err(|error| format!("Cannot read {}: {error}", addons_dir.display()))?.flatten().map(|entry| entry.path()).filter(|path| path.is_dir()).collect();
    folders.sort();
    for folder in &folders {
        let name = folder.file_name().unwrap_or_default().to_string_lossy().into_owned();
        let in_world = !NOT_IN_THE_WORLD.iter().any(|part| name.contains(part));
        walk(folder, in_world, &schema, &methods, &mut out)?;
    }
    if out.fonts.is_empty() {
        return Err(format!("{} has no font in its XML files. Give the Interface/AddOns folder of the UI source.", addons_dir.display()));
    }
    let documented = snapshot.get("events").and_then(|value| value.as_object());
    let events: Vec<String> = out.events.into_iter().filter(|name| documented.is_none_or(|map| !map.contains_key(name))).collect();

    // The frame types: those of UI.xsd, and the intrinsic frames of the XML files.
    let mut frame_types = schema.frame_types.clone();
    for (name, base) in &out.found.intrinsics {
        frame_types.entry(name.clone()).or_insert_with(|| base.clone());
    }
    let frame_types: BTreeMap<String, Value> = frame_types.into_iter().map(|(name, base)| (name, json!(base))).collect();
    // An intrinsic frame is made from another frame type, and says that it is of that type.
    let intrinsics: BTreeMap<String, Value> = out.found.intrinsics.iter().map(|(name, base)| (name.clone(), json!(base))).collect();
    let scripts: BTreeMap<String, Value> = out.found.scripts.iter().map(|(element, names)| (element.clone(), json!(names))).collect();
    let enumerations: BTreeMap<String, Value> = schema.enumerations.iter().map(|(name, values)| (name.clone(), json!(values))).collect();

    // The mixins that the templates name, and the mixins that those are made from.
    let mut wanted: Vec<String> = out.found.mixins.iter().cloned().collect();
    let mut mixins: BTreeMap<String, Value> = BTreeMap::new();
    while let Some(name) = wanted.pop() {
        if mixins.contains_key(&name) {
            continue;
        }
        let mut map = serde_json::Map::new();
        if let Some(parents) = out.mixin_parents.get(&name) {
            map.insert("from".into(), json!(parents));
            wanted.extend(parents.iter().cloned());
        }
        if let Some(methods) = out.mixin_methods.get(&name) {
            map.insert("methods".into(), json!(methods));
        }
        mixins.insert(name, Value::Object(map));
    }

    let lines = vec![format!(
        "{} files in {} folders: {} fonts, {} events that the documentation does not have, {} frame types, {} animation types, {} templates, {} mixins, {} calls of widget methods",
        out.files,
        folders.len(),
        out.fonts.len(),
        events.len(),
        frame_types.len(),
        schema.animation_types.len(),
        out.found.templates.len(),
        mixins.len(),
        out.calls.len()
    )];
    let source = snapshot.get("source").cloned().unwrap_or(Value::String(String::new()));
    // The file is written by hand, one entry on each line, so that a change of the game shows
    // as a short difference. The keys are in the order of the alphabet.
    let text = format!(
        "{{\n  \"animationTypes\": {},\n  \"calls\": {},\n  \"enumerations\": {},\n  \"fonts\": {},\n  \"frameTypes\": {},\n  \"intrinsics\": {},\n  \"mixins\": {},\n  \"scripts\": {},\n  \"source\": {},\n  \"templates\": {},\n  \"tooltipAnchors\": {},\n  \"undocumentedEvents\": {}\n}}\n",
        list_of(schema.animation_types.iter().cloned()),
        list_of(out.calls),
        lines_of(&enumerations),
        list_of(out.fonts),
        lines_of(&frame_types),
        lines_of(&intrinsics),
        lines_of(&mixins),
        lines_of(&scripts),
        source,
        lines_of(&out.found.templates),
        list_of(out.anchors),
        list_of(events),
    );
    Ok((text, lines))
}

/// The differences between two files of names, one line for each, for `--check`.
pub fn differences(old: &Value, new: &Value) -> Vec<String> {
    let mut lines = Vec::new();
    let mut keys: BTreeSet<&String> = BTreeSet::new();
    for value in [old, new] {
        if let Some(map) = value.as_object() {
            keys.extend(map.keys());
        }
    }
    for key in keys {
        let entries = |value: &Value| -> BTreeMap<String, String> {
            match value.get(key.as_str()) {
                Some(Value::Array(list)) => list.iter().map(|entry| (entry.as_str().map(String::from).unwrap_or_else(|| entry.to_string()), String::new())).collect(),
                Some(Value::Object(map)) => map.iter().map(|(name, entry)| (name.clone(), entry.to_string())).collect(),
                Some(other) => BTreeMap::from([(String::new(), other.to_string())]),
                None => BTreeMap::new(),
            }
        };
        let (before, after) = (entries(old), entries(new));
        let mut count = 0;
        for (name, value) in &after {
            let line = match before.get(name) {
                None => format!("  added    {key}.{name}"),
                Some(was) if was != value => format!("  changed  {key}.{name}"),
                Some(_) => continue,
            };
            count += 1;
            if count <= 40 {
                lines.push(line);
            }
        }
        for name in before.keys().filter(|name| !after.contains_key(*name)) {
            count += 1;
            if count <= 40 {
                lines.push(format!("  removed  {key}.{name}"));
            }
        }
        if count > 40 {
            lines.push(format!("  ... and {} more in {key}", count - 40));
        }
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;

    // The form of Blizzard_SharedXML/UI.xsd.
    const XSD: &str = r#"
        <xs:simpleType name="DRAWLAYER"><xs:restriction base="xs:NMTOKEN"><xs:enumeration value="BACKGROUND"/><xs:enumeration value="ARTWORK"/></xs:restriction></xs:simpleType>
        <xs:complexType name="TextureType"><xs:complexContent><xs:extension base="LayoutFrameRefType"/></xs:complexContent></xs:complexType>
        <xs:complexType name="FrameType"><xs:complexContent><xs:extension base="ui:FrameRefType"/></xs:complexContent></xs:complexType>
        <xs:complexType name="ButtonType"><xs:complexContent><xs:extension base="FrameRefType"/></xs:complexContent></xs:complexType>
        <xs:complexType name="CheckButtonType"><xs:complexContent><xs:extension base="ButtonType"/></xs:complexContent></xs:complexType>
        <xs:complexType name="AlphaType"><xs:complexContent><xs:extension base="AnimationType"/></xs:complexContent></xs:complexType>
        <xs:element name="Texture" type="TextureType" substitutionGroup="LayoutFrameRef"/>
        <xs:element name="FontString" type="FontStringType" substitutionGroup="LayoutFrameRef"/>
        <xs:element name="FrameRef" type="FrameRefType" substitutionGroup="LayoutFrameRef"/>
        <xs:element name="NormalTexture" type="ui:TextureType" substitutionGroup="ButtonField"/>
        <xs:element name="ButtonText" type="FontStringType" substitutionGroup="ButtonField"/>
        <xs:element name="NormalColor" type="ColorType" substitutionGroup="ButtonField"/>
        <xs:element name="Frame" type="FrameType" substitutionGroup="FrameRef"/>
        <xs:element name="Button" type="ButtonType" substitutionGroup="ui:FrameRef"/>
        <xs:element name="CheckButton" type="ui:CheckButtonType" substitutionGroup="ui:FrameRef"/>
        <xs:element name="ItemButton" type="ButtonType" substitutionGroup="ui:FrameRef"/>
        <xs:element name="Alpha" type="AlphaType" substitutionGroup="AnimationRef"/>
        <xs:element name="AnimationGroup" type="AnimationGroupType" substitutionGroup="UiField"/>
        <xs:element name="Anchors" type="AnchorsType" substitutionGroup="LayoutField"/>
        <xs:element name="OnLoad" type="ScriptType"/>
    "#;

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
            "self:RegisterEvent(\"PLAYTIME_CHANGED\");\nf:RegisterUnitEvent('UNIT_AURA', \"player\")\nf:RegisterEvent(event)\nf:RegisterEvent(\"not an event\")\nf:UnregisterEvent(\"TRIAL_CAP_REACHED_LEVEL\")\nf:RegisterEvent(\"Perks_Program_CLOSE\")\nf:RegisterEvent(\"lowercase_name\")",
            &mut out,
        );
        assert_eq!(out.into_iter().collect::<Vec<_>>(), ["PLAYTIME_CHANGED", "Perks_Program_CLOSE", "TRIAL_CAP_REACHED_LEVEL", "UNIT_AURA"]);
    }

    #[test]
    fn the_schema_has_the_frame_types_and_what_each_element_makes() {
        let schema = schema_of(XSD);
        let frame_types: Vec<(&str, &str)> = schema.frame_types.iter().map(|(name, base)| (name.as_str(), base.as_str())).collect();
        assert_eq!(frame_types, [("Button", "Frame"), ("CheckButton", "Button"), ("Frame", ""), ("ItemButton", "Button")]);
        assert_eq!(schema.animation_types.iter().collect::<Vec<_>>(), ["Alpha"]);
        assert_eq!(schema.objects.get("NormalTexture").map(String::as_str), Some("Texture"));
        assert_eq!(schema.objects.get("ButtonText").map(String::as_str), Some("FontString"));
        assert!(!schema.objects.contains_key("Anchors") && !schema.objects.contains_key("OnLoad") && !schema.objects.contains_key("NormalColor"));
        assert!(schema.objects.contains_key("AnimationGroup") && !schema.objects.contains_key("FrameRef"));
        assert_eq!(schema.enumerations["DRAWLAYER"], ["BACKGROUND", "ARTWORK"]);
    }

    #[test]
    fn a_template_has_its_kind_its_keys_and_its_scripts() {
        let schema = schema_of(XSD);
        let mut found = Found::default();
        xml_of(
            r#"<Ui>
            <!-- <Button name="NotThis" virtual="true"/> -->
            <Button name="PanelButton" inherits="BaseButton, Other" mixin="PanelMixin" virtual="true">
              <KeyValues><KeyValue key="padding" value="40" type="number"/></KeyValues>
              <Layers><Layer level="BACKGROUND">
                <Texture parentKey="Left" file="a>b"/>
                <Texture/>
              </Layer></Layers>
              <Frames>
                <Frame parentKey="Inner"><Layers><Layer><FontString parentKey="Label" name="$parentLabel"/></Layer></Layers></Frame>
                <Frame><Layers><Layer><Texture parentKey="Unreachable"/></Layer></Layers></Frame>
              </Frames>
              <ButtonText name="$parentText" parentKey="Text"/>
              <Scripts>
                <OnLoad>if 1 < 2 then self:OnLoad() end</OnLoad>
                <OnClick method="OnClick"/>
              </Scripts>
            </Button>
            <Frame name="NotATemplate"><Scripts><OnShow function="f"/></Scripts></Frame>
            <ItemButton name="Slot" intrinsic="true"/>
            </Ui>"#,
            &schema,
            true,
            &mut found,
        );
        assert_eq!(
            found.templates["PanelButton"].to_string(),
            r#"{"children":[{"key":"Left","kind":"Texture"},{"children":[{"key":"Label","kind":"FontString","name":"Label"}],"key":"Inner","kind":"Frame"},{"key":"Text","kind":"FontString","name":"Text","part":"ButtonText"}],"inherits":["BaseButton","Other"],"kind":"Button","mixin":["PanelMixin"],"scripts":["OnClick","OnLoad"],"values":{"padding":["number","40"]}}"#
        );
        assert!(!found.templates.contains_key("NotThis") && !found.templates.contains_key("NotATemplate"));
        assert_eq!(found.intrinsics.get("Slot").map(String::as_str), Some("ItemButton"));
        // The scripts of a template are not scripts of its element: a Button can inherit a Frame template.
        assert!(!found.scripts.contains_key("Button"));
        assert_eq!(found.scripts["Frame"].iter().collect::<Vec<_>>(), ["OnShow"]);
        assert!(found.mixins.contains("PanelMixin"));
    }

    #[test]
    fn mixins_have_their_methods_and_what_they_are_made_from() {
        let (mut methods, mut parents) = (BTreeMap::new(), BTreeMap::new());
        mixins_of(
            "PanelMixin = CreateFromMixins(BaseMixin, OtherMixin);\nfunction PanelMixin:OnLoad()\nend\nfunction PanelMixin.Static(a)\nend\nlocal function helper()\nend\n  function Indented:No()\n",
            &mut methods,
            &mut parents,
        );
        assert_eq!(methods["PanelMixin"].iter().collect::<Vec<_>>(), ["OnLoad", "Static"]);
        assert_eq!(parents["PanelMixin"].iter().collect::<Vec<_>>(), ["BaseMixin", "OtherMixin"]);
        assert!(!methods.contains_key("Indented"));
    }

    #[test]
    fn calls_are_the_calls_with_literal_arguments_only() {
        let methods: HashSet<String> = ["SetPoint", "SetAttribute", "Show", "SetText"].iter().map(|name| name.to_string()).collect();
        let mut out = BTreeSet::new();
        calls_of(
            "self:SetPoint(\"TOPLEFT\",  10, -5.5);\nf.Child:SetAttribute('shown',true)\nlist[1]:Show()\nself:SetPoint(\"CENTER\", parent)\nself:SetText(\"a, (b)\")\n-- self:SetText(\"comment\")\nself:Other(1)\nlocal t = a and b:SetText(nil) or c\nself:SetText(1e5)\nx = \"text:SetText(1)\"",
            &methods,
            &mut out,
        );
        assert_eq!(
            out.into_iter().collect::<Vec<_>>(),
            ["SetAttribute('shown', true)", "SetPoint(\"TOPLEFT\", 10, -5.5)", "SetText(\"a, (b)\")", "SetText(1)", "SetText(nil)", "Show()"]
        );
    }

    #[test]
    fn differences_name_what_was_added_removed_and_changed() {
        let old = json!({ "fonts": ["A", "B"], "templates": { "T": { "kind": "Frame" }, "Gone": {} } });
        let new = json!({ "fonts": ["A", "C"], "templates": { "T": { "kind": "Button" } } });
        assert_eq!(differences(&old, &new), ["  added    fonts.C", "  removed  fonts.B", "  changed  templates.T", "  removed  templates.Gone"]);
    }
}
