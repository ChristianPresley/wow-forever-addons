// The operations of the manager. The desktop app and the command line both use this.

import fs from 'node:fs/promises';
import path from 'node:path';

import { installAddon, listInstalled, uninstallAddon } from './core/addons.mjs';
import { detectInstalls } from './core/detect.mjs';
import { DEFAULT_SOURCE, downloadPackage, loadIndex } from './core/marketplace.mjs';

export class Service {
  /**
   * @param {object} options
   * @param {string} options.settingsFile where the settings are kept
   * @param {string} [options.defaultSource] marketplace to use when the settings name none
   */
  constructor({ settingsFile, defaultSource = DEFAULT_SOURCE }) {
    this.settingsFile = settingsFile;
    this.defaultSource = defaultSource;
    this.settings = { extraRoots: [], source: null };
    this.installs = [];
    this.index = null;
  }

  async loadSettings() {
    try {
      const saved = JSON.parse(await fs.readFile(this.settingsFile, 'utf8'));
      if (Array.isArray(saved.extraRoots)) this.settings.extraRoots = saved.extraRoots.filter((root) => typeof root === 'string');
      if (typeof saved.source === 'string' && saved.source) this.settings.source = saved.source;
    } catch {
      // First start: there is no settings file yet.
    }
  }

  async saveSettings() {
    await fs.mkdir(path.dirname(this.settingsFile), { recursive: true });
    await fs.writeFile(this.settingsFile, JSON.stringify(this.settings, null, 2));
  }

  get source() {
    return this.settings.source ?? this.defaultSource;
  }

  /** Searches for installs and reads the addons of each one. */
  async scan() {
    this.installs = await detectInstalls({ extraRoots: this.settings.extraRoots });
    const installs = [];
    for (const install of this.installs) {
      installs.push({ ...install, addons: await listInstalled(install.addonsDir) });
    }
    return { installs, source: this.source, isDefaultSource: this.settings.source === null };
  }

  /** Adds a folder that the user picked. Returns false if it holds no Forever install. */
  async addRoot(folder) {
    const found = await detectInstalls({ roots: [], extraRoots: [folder] });
    if (found.length === 0) return false;
    if (!this.settings.extraRoots.includes(folder)) this.settings.extraRoots.push(folder);
    await this.saveSettings();
    return true;
  }

  async setSource(source) {
    this.settings.source = source && source !== this.defaultSource ? source : null;
    this.index = null;
    await this.saveSettings();
  }

  async marketplace() {
    this.index = await loadIndex(this.source);
    return this.index;
  }

  findInstall(installId) {
    const install = this.installs.find((candidate) => candidate.id === installId);
    if (!install) throw new Error('That install is no longer known. Scan again.');
    return install;
  }

  async findAddon(addonId) {
    const index = this.index ?? (await this.marketplace());
    const addon = index.addons.find((candidate) => candidate.id === addonId);
    if (!addon) throw new Error(`The marketplace has no addon with the id ${addonId}.`);
    return addon;
  }

  /** Installs an addon, or updates it to the marketplace version. */
  async install(installId, addonId, { allowUnmanaged = false } = {}) {
    const install = this.findInstall(installId);
    const addon = await this.findAddon(addonId);
    const zip = await downloadPackage(this.source, addon);
    await installAddon({ addonsDir: install.addonsDir, addon, zip, allowUnmanaged });
    return addon;
  }

  /** Removes addon folders from an install. */
  async uninstall(installId, folders, { allowUnmanaged = false } = {}) {
    const install = this.findInstall(installId);
    await uninstallAddon({ addonsDir: install.addonsDir, folders, allowUnmanaged });
  }
}
