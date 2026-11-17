//! Desktop app of the Forever Addon Manager. The window calls the commands below.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::path::Path;
use std::sync::{Mutex, MutexGuard};

use serde::Serialize;
use tauri::{AppHandle, Manager, State};
use tauri_plugin_dialog::DialogExt;

use wfam_core::marketplace::{Index, MarketAddon, DEFAULT_SOURCE};
use wfam_core::service::{only_root_from_env, ScanResult, Service, UpdateReport};

/// What the window receives when a command fails.
#[derive(Serialize)]
struct CommandError {
    message: String,
    code: Option<&'static str>,
}

impl From<wfam_core::Error> for CommandError {
    fn from(error: wfam_core::Error) -> Self {
        Self { code: error.code_name(), message: error.message }
    }
}

impl From<std::io::Error> for CommandError {
    fn from(error: std::io::Error) -> Self {
        Self { code: None, message: error.to_string() }
    }
}

type CommandResult<T> = Result<T, CommandError>;
type Shared<'a> = State<'a, Mutex<Service>>;

fn lock<'a>(service: &'a Shared<'_>) -> MutexGuard<'a, Service> {
    service.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

// Each command is `async`, so it runs off the main thread and the window stays
// responsive during a download.

#[tauri::command(async)]
fn scan(service: Shared<'_>) -> ScanResult {
    lock(&service).scan()
}

#[tauri::command(async)]
fn marketplace(service: Shared<'_>) -> CommandResult<Index> {
    Ok(lock(&service).marketplace()?)
}

#[tauri::command(async)]
fn install(service: Shared<'_>, install_id: String, addon_id: String, allow_unmanaged: bool) -> CommandResult<MarketAddon> {
    Ok(lock(&service).install(&install_id, &addon_id, allow_unmanaged)?)
}

#[tauri::command(async)]
fn uninstall(service: Shared<'_>, install_id: String, folders: Vec<String>, allow_unmanaged: bool) -> CommandResult<()> {
    Ok(lock(&service).uninstall(&install_id, &folders, allow_unmanaged)?)
}

#[derive(Serialize)]
struct AddInstallResult {
    added: bool,
    canceled: bool,
}

#[tauri::command(async)]
fn add_install(app: AppHandle, service: Shared<'_>) -> CommandResult<AddInstallResult> {
    let picked = app.dialog().file().set_title("Select your World of Warcraft folder").blocking_pick_folder();
    let Some(picked) = picked else {
        return Ok(AddInstallResult { added: false, canceled: true });
    };
    let folder = picked.into_path().map_err(|error| CommandError { code: None, message: error.to_string() })?;
    Ok(AddInstallResult { added: lock(&service).add_root(&folder)?, canceled: false })
}

#[tauri::command(async)]
fn set_source(service: Shared<'_>, source: String) -> CommandResult<()> {
    Ok(lock(&service).set_source(&source)?)
}

/// Updates every addon that the manager installed, in every install.
#[tauri::command(async)]
fn update_all(service: Shared<'_>) -> CommandResult<UpdateReport> {
    Ok(lock(&service).update_all(None)?)
}

#[tauri::command(async)]
fn set_auto_update(service: Shared<'_>, enabled: bool) -> CommandResult<()> {
    Ok(lock(&service).set_auto_update(enabled)?)
}

fn open_in_file_manager(folder: &Path) -> std::io::Result<()> {
    let program = if cfg!(windows) {
        "explorer"
    } else if cfg!(target_os = "macos") {
        "open"
    } else {
        "xdg-open"
    };
    std::process::Command::new(program).arg(folder).spawn().map(|_| ())
}

#[tauri::command(async)]
fn open_addons_folder(service: Shared<'_>, install_id: String) -> CommandResult<()> {
    let install = lock(&service).find_install(&install_id)?.clone();
    let folder = if install.addons_dir.is_dir() { install.addons_dir } else { install.flavor_dir };
    Ok(open_in_file_manager(&folder)?)
}

/// The marketplace to use when the user chose none. A debug build that runs from the
/// repository prefers a locally built marketplace: run "cargo dev marketplace".
fn default_source() -> String {
    if let Ok(source) = std::env::var("WFAM_SOURCE") {
        if !source.trim().is_empty() {
            return source;
        }
    }
    if cfg!(debug_assertions) {
        let local = Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("..").join("dist").join("marketplace").join("index.json");
        if let Ok(local) = local.canonicalize() {
            // `canonicalize` gives a `\\?\` path on Windows. The plain form reads better in the window.
            return local.to_string_lossy().trim_start_matches(r"\\?\").to_string();
        }
    }
    DEFAULT_SOURCE.to_string()
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let mut service = match only_root_from_env() {
                Some(root) => Service::in_only_root(&root, default_source()).map_err(|error| error.message)?,
                None => Service::new(app.path().app_config_dir()?.join("settings.json"), default_source()),
            };
            service.load_settings();
            app.manage(Mutex::new(service));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![scan, marketplace, install, uninstall, add_install, set_source, open_addons_folder, update_all, set_auto_update])
        .run(tauri::generate_context!())
        .expect("the Forever Addon Manager could not start");
}
