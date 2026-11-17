use std::cmp::Ordering;
use std::fs;
use std::io::{Cursor, Write};
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};
use tempfile::TempDir;

use wfam_core::addons::{install_addon, list_installed, uninstall_addon, Managed, MANIFEST_FILE};
use wfam_core::detect::{detect_installs, extract_paths_from_product_db, parse_build_info, parse_flavor_info, DetectOptions};
use wfam_core::marketplace::{download_package, load_index, validate_index, Download, Index, MarketAddon};
use wfam_core::service::Service;
use wfam_core::toc::{parse_toc, pick_toc_file};
use wfam_core::version::compare_versions;
use wfam_core::ErrorCode;

/// Makes a World of Warcraft folder with a Forever flavor and, optionally, a retail flavor.
/// Returns the root and the AddOns folder.
fn make_wow(tmp: &Path, name: &str, retail: bool) -> (PathBuf, PathBuf) {
    let root = tmp.join(name);
    let forever = root.join("_forever_");
    let addons = forever.join("Interface").join("AddOns");
    fs::create_dir_all(&addons).unwrap();
    fs::write(forever.join(".flavor.info"), "Product Flavor!STRING:0\nwowf\n").unwrap();
    fs::write(
        root.join(".build.info"),
        "Branch!STRING:0|Version!STRING:0|Product!STRING:0\nus|12.1.5.1|wow\nus|1.60.1.70938|wowf\n",
    )
    .unwrap();
    if retail {
        fs::create_dir_all(root.join("_retail_")).unwrap();
        fs::write(root.join("_retail_").join(".flavor.info"), "Product Flavor!STRING:0\nwow\n").unwrap();
    }
    (root, addons)
}

fn make_zip(files: &[(&str, &[u8])]) -> Vec<u8> {
    let mut writer = zip::ZipWriter::new(Cursor::new(Vec::new()));
    for (name, data) in files {
        writer.start_file(*name, zip::write::SimpleFileOptions::default()).unwrap();
        writer.write_all(data).unwrap();
    }
    writer.finish().unwrap().into_inner()
}

fn make_package(folder: &str, version: &str, extra: &[(&str, &[u8])]) -> Vec<u8> {
    let toc_name = format!("{folder}/{folder}.toc");
    let lua_name = format!("{folder}/Core.lua");
    let toc = format!("## Interface: 16001\n## Title: |cff00ff00{folder}|r\n## Version: {version}\n\nCore.lua\n");
    let mut files: Vec<(&str, &[u8])> = vec![(&toc_name, toc.as_bytes()), (&lua_name, b"print(\"hello\")\n")];
    files.extend_from_slice(extra);
    make_zip(&files)
}

fn market_addon(version: &str) -> MarketAddon {
    MarketAddon {
        id: "demo".into(),
        name: "Demo".into(),
        version: version.into(),
        category: String::new(),
        summary: String::new(),
        description: String::new(),
        author: String::new(),
        homepage: String::new(),
        interfaces: vec![16001],
        folders: vec!["Demo".into()],
        download: Download { url: "Demo-1.0.0.zip".into(), sha256: "0".repeat(64), size: 0 },
    }
}

/// Writes a marketplace with the Demo addon. Returns the path of its index and the entry.
fn make_market(tmp: &Path) -> (String, MarketAddon) {
    let dir = tmp.join("market");
    fs::create_dir_all(&dir).unwrap();
    let zip = make_package("Demo", "1.0.0", &[]);
    fs::write(dir.join("Demo-1.0.0.zip"), &zip).unwrap();
    let mut entry = market_addon("1.0.0");
    entry.download.sha256 = format!("{:x}", Sha256::digest(&zip));
    let index = Index { schema: 1, generated_at: None, addons: vec![entry.clone()] };
    let source = dir.join("index.json");
    fs::write(&source, serde_json::to_string(&index).unwrap()).unwrap();
    (source.to_string_lossy().into_owned(), entry)
}

fn make_link(target: &Path, link: &Path) {
    #[cfg(windows)]
    {
        let output = std::process::Command::new("cmd").arg("/C").arg("mklink").arg("/J").arg(link).arg(target).output().unwrap();
        assert!(output.status.success(), "mklink failed: {}", String::from_utf8_lossy(&output.stderr));
    }
    #[cfg(not(windows))]
    std::os::unix::fs::symlink(target, link).unwrap();
}

#[test]
fn toc_fields_file_list_and_forever_toc_choice() {
    let toc = parse_toc("\u{feff}## Interface: 16001, 120100\r\n## Title: |cFF00FF00Questie|r v1\r\n## Version: v12.9.0\r\n# comment\r\nsrc\\Core.lua\r\n");
    assert_eq!(toc.interfaces, vec![16001, 120100]);
    assert_eq!(toc.title, "Questie v1");
    assert_eq!(toc.version, "v12.9.0");
    assert_eq!(toc.files, vec!["src/Core.lua"]);

    let names = |list: &[&str]| list.iter().map(|name| name.to_string()).collect::<Vec<_>>();
    assert_eq!(
        pick_toc_file("Questie", &names(&["Questie.toc", "Questie_Vanilla.toc", "Questie_Camelot.toc"])).as_deref(),
        Some("Questie_Camelot.toc")
    );
    assert_eq!(pick_toc_file("Plain", &names(&["Plain.toc", "x.lua"])).as_deref(), Some("Plain.toc"));
    assert_eq!(pick_toc_file("None", &names(&["x.lua"])), None);
}

#[test]
fn version_comparison() {
    assert_eq!(compare_versions("0.1.0", "0.2.0"), Ordering::Less);
    assert_eq!(compare_versions("v1.10.0", "1.9.9"), Ordering::Greater);
    assert_eq!(compare_versions("1.0", "1.0.0"), Ordering::Equal);
    assert_eq!(compare_versions("1.2.3-beta", "1.2.3"), Ordering::Equal);
}

#[test]
fn detect_flavor_and_build_files() {
    assert_eq!(parse_flavor_info("Product Flavor!STRING:0\r\nwowf\r\n").as_deref(), Some("wowf"));
    let versions = parse_build_info("Branch!STRING:0|Version!STRING:0|Product!STRING:0\nus|1.60.1.70938|wowf\n");
    assert_eq!(versions.get("wowf").map(String::as_str), Some("1.60.1.70938"));
}

#[test]
fn detect_reads_paths_from_a_protobuf_product_database() {
    fn field(number: u8, body: &[u8]) -> Vec<u8> {
        let mut out = vec![(number << 3) | 2, body.len() as u8];
        out.extend_from_slice(body);
        out
    }
    let wow = [field(1, b"D:/World of Warcraft"), field(2, b"us")].concat();
    let agent = field(1, b"C:/ProgramData/Battle.net/Agent");
    let db = [
        field(1, &[field(1, b"wowf"), field(3, &wow)].concat()),
        field(1, &[field(1, b"agent"), field(3, &agent)].concat()),
    ]
    .concat();
    assert_eq!(extract_paths_from_product_db(&db), vec!["C:/ProgramData/Battle.net/Agent", "D:/World of Warcraft"]);
    assert!(extract_paths_from_product_db(b"\xff\xff\xff not protobuf").is_empty());
}

#[test]
fn detect_finds_the_forever_flavor_only_from_the_root_or_a_folder_inside_it() {
    let tmp = TempDir::new().unwrap();
    let (root, addons) = make_wow(tmp.path(), "wow", true);

    let from_root = detect_installs(&DetectOptions { roots: Some(vec![root.clone()]), extra_roots: vec![] });
    assert_eq!(from_root.len(), 1);
    assert_eq!(from_root[0].folder, "_forever_");
    assert_eq!(from_root[0].version.as_deref(), Some("1.60.1.70938"));
    assert_eq!(from_root[0].addons_dir, addons);

    let from_addons = detect_installs(&DetectOptions { roots: Some(vec![]), extra_roots: vec![addons] });
    assert_eq!(from_addons.len(), 1);
    let missing = detect_installs(&DetectOptions { roots: Some(vec![tmp.path().join("missing")]), extra_roots: vec![] });
    assert!(missing.is_empty());
}

#[test]
fn addons_install_update_list_and_uninstall() {
    let tmp = TempDir::new().unwrap();
    let (_, addons) = make_wow(tmp.path(), "wow", false);
    install_addon(&addons, &market_addon("1.0.0"), &make_package("Demo", "1.0.0", &[("Demo/old.lua", b"")]), false).unwrap();

    let listed = list_installed(&addons);
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].title, "Demo");
    assert_eq!(listed[0].version, "1.0.0");
    assert_eq!(listed[0].managed, Some(Managed { id: "demo".into(), version: "1.0.0".into() }));

    install_addon(&addons, &market_addon("1.1.0"), &make_package("Demo", "1.1.0", &[]), false).unwrap();
    assert_eq!(list_installed(&addons)[0].version, "1.1.0");
    assert!(!addons.join("Demo").join("old.lua").exists(), "files of the old version are gone");
    let leftovers = fs::read_dir(addons.parent().unwrap()).unwrap().flatten().filter(|entry| entry.file_name().to_string_lossy().starts_with(".wfam")).count();
    assert_eq!(leftovers, 0, "the staging folder is removed");

    uninstall_addon(&addons, &["Demo".to_string()], false).unwrap();
    assert!(list_installed(&addons).is_empty());
    assert_eq!(uninstall_addon(&addons, &["Demo".to_string()], false).unwrap_err().code, ErrorCode::NotInstalled);
}

#[test]
fn addons_a_copy_installed_by_hand_is_kept_unless_the_user_allows_the_change() {
    let tmp = TempDir::new().unwrap();
    let (_, addons) = make_wow(tmp.path(), "wow", false);
    let demo = addons.join("Demo");
    fs::create_dir_all(&demo).unwrap();
    fs::write(demo.join("Demo.toc"), "## Interface: 16001\n## Version: 0.5.0\n").unwrap();
    fs::write(demo.join("mine.lua"), "-- mine").unwrap();
    let zip = make_package("Demo", "1.0.0", &[]);

    assert_eq!(install_addon(&addons, &market_addon("1.0.0"), &zip, false).unwrap_err().code, ErrorCode::Unmanaged);
    assert_eq!(uninstall_addon(&addons, &["Demo".to_string()], false).unwrap_err().code, ErrorCode::Unmanaged);
    assert_eq!(fs::read_to_string(demo.join("mine.lua")).unwrap(), "-- mine");

    install_addon(&addons, &market_addon("1.0.0"), &zip, true).unwrap();
    assert!(demo.join(MANIFEST_FILE).exists());
    assert!(!demo.join("mine.lua").exists());
}

#[test]
fn addons_a_development_link_is_never_replaced_or_removed() {
    let tmp = TempDir::new().unwrap();
    let (_, addons) = make_wow(tmp.path(), "wow", false);
    let work = tmp.path().join("work").join("Demo");
    fs::create_dir_all(&work).unwrap();
    fs::write(work.join("Demo.toc"), "## Interface: 16001\n## Version: 9.9.9\n").unwrap();
    make_link(&work, &addons.join("Demo"));

    let listed = list_installed(&addons);
    assert_eq!(listed.len(), 1);
    assert!(listed[0].linked);
    assert_eq!(listed[0].version, "9.9.9");

    let zip = make_package("Demo", "1.0.0", &[]);
    assert_eq!(install_addon(&addons, &market_addon("1.0.0"), &zip, true).unwrap_err().code, ErrorCode::Linked);
    assert_eq!(uninstall_addon(&addons, &["Demo".to_string()], true).unwrap_err().code, ErrorCode::Linked);
    assert!(work.join("Demo.toc").exists());
}

#[test]
fn addons_unsafe_packages_are_rejected_and_nothing_is_written() {
    let tmp = TempDir::new().unwrap();
    let (_, addons) = make_wow(tmp.path(), "wow", false);
    let cases = [
        make_package("Demo", "1.0.0", &[("Demo/../../evil.lua", b"")]),
        make_package("Demo", "1.0.0", &[("Other/Other.toc", b"")]),
        make_package("Demo", "1.0.0", &[("/abs.lua", b"")]),
        make_package("Demo", "1.0.0", &[("Demo/C:/x.lua", b"")]),
        make_package("Demo", "1.0.0", &[("loose.lua", b"")]),
        make_zip(&[("Demo/Core.lua", b"")]),
        b"not a zip".to_vec(),
    ];
    for (number, zip) in cases.iter().enumerate() {
        let error = install_addon(&addons, &market_addon("1.0.0"), zip, false).unwrap_err();
        assert_eq!(error.code, ErrorCode::InvalidPackage, "case {number}: {error}");
    }
    assert_eq!(fs::read_dir(&addons).unwrap().count(), 0);
    assert_eq!(fs::read_dir(addons.parent().unwrap()).unwrap().count(), 1);
}

#[test]
fn marketplace_index_validation_and_checksum() {
    let tmp = TempDir::new().unwrap();
    let (source, entry) = make_market(tmp.path());

    let index = load_index(&source).unwrap();
    assert_eq!(index.addons.len(), 1);
    assert_eq!(download_package(&source, &index.addons[0]).unwrap(), make_package("Demo", "1.0.0", &[]));

    let mut tampered = entry.clone();
    tampered.download.sha256 = "a".repeat(64);
    assert!(download_package(&source, &tampered).unwrap_err().message.contains("checksum"));

    let mut remote = entry.clone();
    remote.download.url = "https://example.com/x.zip".into();
    assert!(download_package(&source, &remote).unwrap_err().message.contains("same kind of source"));

    let mut escaping = entry.clone();
    escaping.download.url = "../Demo-1.0.0.zip".into();
    assert!(download_package(&source, &escaping).is_err());

    let index_with = |change: &dyn Fn(&mut MarketAddon)| {
        let mut addon = entry.clone();
        change(&mut addon);
        Index { schema: 1, generated_at: None, addons: vec![addon] }
    };
    assert!(validate_index(&Index { schema: 2, generated_at: None, addons: vec![] }).is_err());
    assert!(validate_index(&index_with(&|addon| addon.folders = vec!["../x".into()])).is_err());
    assert!(validate_index(&index_with(&|addon| addon.id = "Bad Id".into())).is_err());
    assert!(validate_index(&index_with(&|addon| addon.download.sha256 = "xyz".into())).is_err());
    assert!(load_index("http://example.com/index.json").unwrap_err().message.contains("https"));
}

#[test]
fn service_scan_install_from_a_marketplace_and_uninstall() {
    let tmp = TempDir::new().unwrap();
    let (root, addons) = make_wow(tmp.path(), "wow", false);
    let (source, _) = make_market(tmp.path());
    let settings_file = tmp.path().join("settings").join("settings.json");
    let mut service = Service::new(settings_file.clone(), source.clone());

    assert!(!service.add_root(&tmp.path().join("missing")).unwrap());
    assert!(service.add_root(&root).unwrap());

    let scan = service.scan();
    assert!(scan.is_default_source);
    let state = scan.installs.iter().find(|state| state.install.root == root).expect("the added install is found");
    let id = state.install.id.clone();

    service.install(&id, "demo", false).unwrap();
    assert_eq!(list_installed(&addons)[0].managed.as_ref().unwrap().id, "demo");
    service.uninstall(&id, &["Demo".to_string()], false).unwrap();
    assert!(list_installed(&addons).is_empty());
    assert!(service.install("unknown", "demo", false).unwrap_err().message.contains("no longer known"));
    assert!(service.install(&id, "absent", false).unwrap_err().message.contains("no addon"));

    // The settings survive a restart.
    let mut restarted = Service::new(settings_file, source);
    restarted.load_settings();
    assert_eq!(restarted.settings.extra_roots, vec![root]);
}

#[test]
fn service_in_only_root_works_in_that_folder_and_nowhere_else() {
    let tmp = TempDir::new().unwrap();
    let (other, other_addons) = make_wow(tmp.path(), "other", false);
    let (source, _) = make_market(tmp.path());
    let root = tmp.path().join("trial");

    // An empty folder gets an empty Forever install, and the settings file is in it.
    let mut service = Service::in_only_root(&root, source.clone()).unwrap();
    assert_eq!(service.only_root(), Some(root.as_path()));
    let addons = root.join("_forever_").join("Interface").join("AddOns");
    assert!(addons.is_dir());

    // A folder from the settings is not searched, and none can be added.
    service.settings.extra_roots.push(other.clone());
    let scan = service.scan();
    assert_eq!(scan.installs.len(), 1);
    assert_eq!(scan.installs[0].install.root, root);
    assert!(service.add_root(&other).unwrap_err().message.contains("WFAM_ROOT"));

    let id = scan.installs[0].install.id.clone();
    service.install(&id, "demo", false).unwrap();
    assert_eq!(list_installed(&addons)[0].managed.as_ref().unwrap().id, "demo");
    assert!(list_installed(&other_addons).is_empty());

    service.set_auto_update(false).unwrap();
    assert!(root.join("wfam-settings.json").is_file());

    // An install that is there already is used as it is.
    let again = Service::in_only_root(&other, source).unwrap().scan();
    assert_eq!(again.installs.len(), 1);
    assert_eq!(again.installs[0].install.version.as_deref(), Some("1.60.1.70938"));
}

/// Puts version `version` of the Demo addon in the marketplace at `source`.
fn publish_demo(source: &str, version: &str) {
    let dir = Path::new(source).parent().unwrap();
    let file = format!("Demo-{version}.zip");
    let zip = make_package("Demo", version, &[]);
    fs::write(dir.join(&file), &zip).unwrap();
    let mut entry = market_addon(version);
    entry.download.url = file;
    entry.download.sha256 = format!("{:x}", Sha256::digest(&zip));
    let index = Index { schema: 1, generated_at: None, addons: vec![entry] };
    fs::write(source, serde_json::to_string(&index).unwrap()).unwrap();
}

#[test]
fn service_update_all_updates_managed_addons_only() {
    let tmp = TempDir::new().unwrap();
    let (root, addons) = make_wow(tmp.path(), "wow", false);
    let (source, _) = make_market(tmp.path());
    let settings_file = tmp.path().join("settings").join("settings.json");
    let mut service = Service::new(settings_file.clone(), source.clone());
    assert!(service.add_root(&root).unwrap());
    let scan = service.scan();
    assert!(scan.auto_update, "automatic updates are on by default");
    let id = scan.installs.iter().find(|state| state.install.root == root).unwrap().install.id.clone();

    // Nothing is installed: an update installs nothing new.
    let report = service.update_all(Some(&id)).unwrap();
    assert!(report.updated.is_empty() && report.failed.is_empty());
    assert!(list_installed(&addons).is_empty());

    // A managed addon at the marketplace version stays as it is.
    service.install(&id, "demo", false).unwrap();
    assert!(service.update_all(Some(&id)).unwrap().updated.is_empty());

    // A newer version in the marketplace is installed.
    publish_demo(&source, "1.1.0");
    let report = service.update_all(Some(&id)).unwrap();
    assert!(report.failed.is_empty());
    assert_eq!(report.updated.len(), 1);
    assert_eq!((report.updated[0].from.as_str(), report.updated[0].to.as_str()), ("1.0.0", "1.1.0"));
    assert_eq!(list_installed(&addons)[0].version, "1.1.0");

    // A copy that the user installed by hand is not updated.
    fs::remove_file(addons.join("Demo").join(MANIFEST_FILE)).unwrap();
    publish_demo(&source, "1.2.0");
    assert!(service.update_all(Some(&id)).unwrap().updated.is_empty());
    assert_eq!(list_installed(&addons)[0].version, "1.1.0");

    // The switch is saved.
    service.set_auto_update(false).unwrap();
    let mut restarted = Service::new(settings_file, source);
    restarted.load_settings();
    assert!(!restarted.settings.auto_update);
}
