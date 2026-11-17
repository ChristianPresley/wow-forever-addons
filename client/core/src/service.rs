//! The operations of the manager. The desktop app and the command line both use this.

use std::cmp::Ordering;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::addons::{install_addon, list_installed, uninstall_addon, InstalledAddon};
use crate::detect::{detect_installs, inspect_root, DetectOptions, Install};
use crate::error::{Error, Result};
use crate::marketplace::{download_package, load_index, Index, MarketAddon};
use crate::version::compare_versions;

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    /// World of Warcraft folders that the user added by hand.
    pub extra_roots: Vec<PathBuf>,
    /// Marketplace that the user chose. `None` means the default one.
    pub source: Option<String>,
    /// Install each available update without a question. On unless the user turns it off.
    pub auto_update: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self { extra_roots: Vec::new(), source: None, auto_update: true }
    }
}

/// One addon that `Service::update_all` updated.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdatedAddon {
    pub install_id: String,
    pub addon_id: String,
    pub name: String,
    pub from: String,
    pub to: String,
}

/// One addon that `Service::update_all` could not update.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FailedUpdate {
    pub install_id: String,
    pub name: String,
    pub message: String,
}

#[derive(Debug, Default, Serialize)]
pub struct UpdateReport {
    pub updated: Vec<UpdatedAddon>,
    pub failed: Vec<FailedUpdate>,
}

#[derive(Debug, Serialize)]
pub struct InstallState {
    #[serde(flatten)]
    pub install: Install,
    pub addons: Vec<InstalledAddon>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanResult {
    pub installs: Vec<InstallState>,
    pub source: String,
    pub is_default_source: bool,
    pub auto_update: bool,
}

/// Environment variable that names the one World of Warcraft folder to work in. With it,
/// the manager searches nowhere else, so a trial run cannot reach the real game folder.
pub const ONLY_ROOT_VAR: &str = "WFAM_ROOT";

/// Name of the settings file that a run with `ONLY_ROOT_VAR` keeps in that folder.
pub const ONLY_ROOT_SETTINGS: &str = "wfam-settings.json";

/// The folder that `ONLY_ROOT_VAR` names, if it is set.
pub fn only_root_from_env() -> Option<PathBuf> {
    std::env::var_os(ONLY_ROOT_VAR).filter(|value| !value.is_empty()).map(PathBuf::from)
}

pub struct Service {
    settings_file: PathBuf,
    default_source: String,
    pub settings: Settings,
    installs: Vec<Install>,
    index: Option<Index>,
    only_root: Option<PathBuf>,
}

impl Service {
    /// `settings_file` is where the settings are kept. `default_source` is the
    /// marketplace to use when the settings name none.
    pub fn new(settings_file: PathBuf, default_source: String) -> Self {
        Self { settings_file, default_source, settings: Settings::default(), installs: Vec::new(), index: None, only_root: None }
    }

    /// A service that works in the World of Warcraft folder `root` and nowhere else: no
    /// automatic search, and no folder from the settings. The settings are kept in `root`,
    /// so the settings of the user stay as they are. If `root` holds no Forever install,
    /// an empty one is made there.
    pub fn in_only_root(root: &Path, default_source: String) -> Result<Self> {
        let root = std::path::absolute(root)?;
        if inspect_root(&root).is_empty() {
            fs::create_dir_all(root.join("_forever_").join("Interface").join("AddOns"))?;
        }
        let mut service = Self::new(root.join(ONLY_ROOT_SETTINGS), default_source);
        service.only_root = Some(root);
        Ok(service)
    }

    /// The one folder that this service works in, if it was made with `in_only_root`.
    pub fn only_root(&self) -> Option<&Path> {
        self.only_root.as_deref()
    }

    /// Reads the settings file. A missing or damaged file leaves the defaults.
    pub fn load_settings(&mut self) {
        let saved = fs::read_to_string(&self.settings_file).ok().and_then(|text| serde_json::from_str::<Settings>(&text).ok());
        if let Some(mut settings) = saved {
            settings.source = settings.source.filter(|source| !source.trim().is_empty());
            self.settings = settings;
        }
    }

    pub fn save_settings(&self) -> Result<()> {
        if let Some(parent) = self.settings_file.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&self.settings_file, serde_json::to_string_pretty(&self.settings)?)?;
        Ok(())
    }

    pub fn source(&self) -> &str {
        self.settings.source.as_deref().unwrap_or(&self.default_source)
    }

    /// Searches for installs and reads the addons of each one.
    pub fn scan(&mut self) -> ScanResult {
        self.installs = match &self.only_root {
            Some(root) => inspect_root(root),
            None => detect_installs(&DetectOptions { extra_roots: self.settings.extra_roots.clone(), roots: None }),
        };
        let installs = self
            .installs
            .iter()
            .map(|install| InstallState { addons: list_installed(&install.addons_dir), install: install.clone() })
            .collect();
        ScanResult {
            installs,
            source: self.source().to_string(),
            is_default_source: self.settings.source.is_none(),
            auto_update: self.settings.auto_update,
        }
    }

    pub fn set_auto_update(&mut self, enabled: bool) -> Result<()> {
        self.settings.auto_update = enabled;
        self.save_settings()
    }

    /// Updates each addon that the manager installed and that is older than the marketplace
    /// version, in `only_install` or, with `None`, in every install.
    ///
    /// It reads the marketplace again first. It never touches a copy that the user installed
    /// by hand or a development link, and it installs nothing that is not there already.
    /// One addon that fails does not stop the others.
    pub fn update_all(&mut self, only_install: Option<&str>) -> Result<UpdateReport> {
        let index = self.marketplace()?;
        let scan = self.scan();
        let mut report = UpdateReport::default();
        for state in &scan.installs {
            if only_install.is_some_and(|id| id != state.install.id) {
                continue;
            }
            for addon in &index.addons {
                let present: Vec<&InstalledAddon> =
                    addon.folders.iter().filter_map(|folder| state.addons.iter().find(|item| &item.folder == folder)).collect();
                let Some(first) = present.first() else { continue };
                let managed = present.iter().all(|item| item.managed.is_some() && !item.linked);
                if !managed || compare_versions(&first.version, &addon.version) != Ordering::Less {
                    continue;
                }
                match self.install(&state.install.id, &addon.id, false) {
                    Ok(_) => report.updated.push(UpdatedAddon {
                        install_id: state.install.id.clone(),
                        addon_id: addon.id.clone(),
                        name: addon.name.clone(),
                        from: first.version.clone(),
                        to: addon.version.clone(),
                    }),
                    Err(error) => report.failed.push(FailedUpdate {
                        install_id: state.install.id.clone(),
                        name: addon.name.clone(),
                        message: error.message,
                    }),
                }
            }
        }
        Ok(report)
    }

    /// Adds a folder that the user picked. Returns false if it holds no Forever install.
    pub fn add_root(&mut self, folder: &Path) -> Result<bool> {
        if let Some(root) = &self.only_root {
            return Err(Error::other(format!("This run works in {} only ({ONLY_ROOT_VAR} is set). No folder was added.", root.display())));
        }
        let found = detect_installs(&DetectOptions { extra_roots: vec![folder.to_path_buf()], roots: Some(Vec::new()) });
        if found.is_empty() {
            return Ok(false);
        }
        if !self.settings.extra_roots.iter().any(|root| root == folder) {
            self.settings.extra_roots.push(folder.to_path_buf());
        }
        self.save_settings()?;
        Ok(true)
    }

    /// Sets the marketplace. An empty string, or the default one, goes back to the default.
    pub fn set_source(&mut self, source: &str) -> Result<()> {
        let source = source.trim();
        self.settings.source = (!source.is_empty() && source != self.default_source).then(|| source.to_string());
        self.index = None;
        self.save_settings()
    }

    pub fn marketplace(&mut self) -> Result<Index> {
        let index = load_index(self.source())?;
        self.index = Some(index.clone());
        Ok(index)
    }

    pub fn find_install(&self, install_id: &str) -> Result<&Install> {
        self.installs
            .iter()
            .find(|install| install.id == install_id)
            .ok_or_else(|| Error::other("That install is no longer known. Scan again."))
    }

    pub fn find_addon(&mut self, addon_id: &str) -> Result<MarketAddon> {
        let index = match &self.index {
            Some(index) => index.clone(),
            None => self.marketplace()?,
        };
        index
            .addons
            .into_iter()
            .find(|addon| addon.id == addon_id)
            .ok_or_else(|| Error::other(format!("The marketplace has no addon with the id {addon_id}.")))
    }

    /// Installs an addon, or updates it to the marketplace version.
    pub fn install(&mut self, install_id: &str, addon_id: &str, allow_unmanaged: bool) -> Result<MarketAddon> {
        let addons_dir = self.find_install(install_id)?.addons_dir.clone();
        let addon = self.find_addon(addon_id)?;
        let zip = download_package(self.source(), &addon)?;
        install_addon(&addons_dir, &addon, &zip, allow_unmanaged)?;
        Ok(addon)
    }

    /// Removes addon folders from an install.
    pub fn uninstall(&mut self, install_id: &str, folders: &[String], allow_unmanaged: bool) -> Result<()> {
        let addons_dir = self.find_install(install_id)?.addons_dir.clone();
        uninstall_addon(&addons_dir, folders, allow_unmanaged)
    }
}
