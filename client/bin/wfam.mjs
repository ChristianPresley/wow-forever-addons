#!/usr/bin/env node
// Command-line form of the Forever Addon Manager.
//
//   wfam detect                     list the WoW: Forever installs
//   wfam list                       list the addons of an install
//   wfam market                     list the marketplace addons
//   wfam install <id> [--force]     install or update an addon
//   wfam uninstall <id> [--force]   remove an addon
//
// Options: --install <folder>  use this World of Warcraft folder
//          --source <url|path> use this marketplace index
//          --force             also replace or remove a copy that the manager did not install

import os from 'node:os';
import path from 'node:path';

import { compareVersions } from '../src/core/version.mjs';
import { Service } from '../src/service.mjs';

const argv = process.argv.slice(2);
function option(name) {
  const i = argv.indexOf(name);
  if (i < 0) return null;
  const [, value] = argv.splice(i, 2);
  return value ?? null;
}
function flag(name) {
  const i = argv.indexOf(name);
  if (i < 0) return false;
  argv.splice(i, 1);
  return true;
}

const installFolder = option('--install');
const source = option('--source') ?? process.env.WFAM_SOURCE;
const force = flag('--force');
const [command, addonId] = argv;

const configDir = process.env.APPDATA ?? path.join(os.homedir(), '.config');
const service = new Service({
  settingsFile: path.join(configDir, 'wow-forever-addon-manager', 'cli-settings.json'),
  ...(source ? { defaultSource: source } : {}),
});
if (installFolder) service.settings.extraRoots.push(installFolder);

async function pickInstall() {
  const { installs } = await service.scan();
  const wanted = installFolder ? path.resolve(installFolder).toLowerCase() : null;
  const matches = wanted ? installs.filter((install) => install.flavorDir.toLowerCase().startsWith(wanted)) : installs;
  if (matches.length === 0) throw new Error('No WoW: Forever install found. Use --install <folder>.');
  if (matches.length > 1) throw new Error(`More than one install found. Choose one with --install:\n${matches.map((m) => `  ${m.root}`).join('\n')}`);
  return matches[0];
}

try {
  if (command === 'detect') {
    const { installs } = await service.scan();
    if (installs.length === 0) console.log('No WoW: Forever install found.');
    for (const install of installs) {
      console.log(`${install.flavorDir}\n  version ${install.version ?? 'unknown'}, product ${install.product}, ${install.addons.length} addons`);
    }
  } else if (command === 'list') {
    const install = await pickInstall();
    for (const addon of install.addons) {
      const kind = addon.linked ? 'link' : addon.managed ? 'managed' : 'by hand';
      console.log(`${addon.folder.padEnd(28)} ${String(addon.version || '-').padEnd(14)} ${kind}`);
    }
  } else if (command === 'market') {
    const index = await service.marketplace();
    const install = await pickInstall().catch(() => null);
    for (const addon of index.addons) {
      const present = install?.addons.find((item) => addon.folders.includes(item.folder));
      const status = !present ? '' : compareVersions(present.version, addon.version) < 0 ? `update from ${present.version}` : 'installed';
      console.log(`${addon.id.padEnd(22)} ${addon.version.padEnd(8)} ${status.padEnd(20)} ${addon.summary}`);
    }
  } else if (command === 'install' && addonId) {
    const install = await pickInstall();
    const addon = await service.install(install.id, addonId, { allowUnmanaged: force });
    console.log(`Installed ${addon.name} ${addon.version} in ${install.addonsDir}`);
  } else if (command === 'uninstall' && addonId) {
    const install = await pickInstall();
    const addon = await service.findAddon(addonId);
    await service.uninstall(install.id, addon.folders, { allowUnmanaged: force });
    console.log(`Removed ${addon.name} from ${install.addonsDir}`);
  } else {
    console.log('Usage: wfam detect | list | market | install <id> | uninstall <id>  [--install <folder>] [--source <url|path>] [--force]');
    process.exitCode = command ? 1 : 0;
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
