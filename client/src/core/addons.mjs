// Lists, installs and removes addons in an `Interface/AddOns` folder.

import { randomBytes } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

import { parseToc, pickTocFile } from './toc.mjs';
import { readZip } from './zip.mjs';

/** File that the manager writes into each addon folder it installs. */
export const MANIFEST_FILE = '.wfam.json';

const SAFE_NAME = /^[A-Za-z0-9][A-Za-z0-9 _!.-]*$/;

export class AddonError extends Error {
  /** @param {'UNMANAGED' | 'LINKED' | 'INVALID_PACKAGE' | 'NOT_INSTALLED'} code */
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

async function lstatOrNull(target) {
  try {
    return await fs.lstat(target);
  } catch {
    return null;
  }
}

async function readManifest(folderPath) {
  try {
    return JSON.parse(await fs.readFile(path.join(folderPath, MANIFEST_FILE), 'utf8'));
  } catch {
    return null;
  }
}

/**
 * @typedef {object} InstalledAddon
 * @property {string} folder folder name in AddOns
 * @property {string} title
 * @property {string} version
 * @property {number[]} interfaces
 * @property {boolean} linked the folder is a symbolic link or junction (a development copy)
 * @property {{id: string, version: string} | null} managed set when the manager installed the folder
 */

/** @returns {Promise<InstalledAddon[]>} */
export async function listInstalled(addonsDir) {
  let entries;
  try {
    entries = await fs.readdir(addonsDir, { withFileTypes: true });
  } catch {
    return [];
  }
  const addons = [];
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    const folderPath = path.join(addonsDir, entry.name);
    const linked = entry.isSymbolicLink();
    if (!entry.isDirectory() && !linked) continue;
    let fileNames;
    try {
      fileNames = await fs.readdir(folderPath);
    } catch {
      continue;
    }
    const tocName = pickTocFile(entry.name, fileNames);
    if (!tocName) continue;
    const toc = parseToc(await fs.readFile(path.join(folderPath, tocName), 'utf8'));
    const manifest = linked ? null : await readManifest(folderPath);
    addons.push({
      folder: entry.name,
      title: toc.title || entry.name,
      version: toc.version,
      interfaces: toc.interfaces,
      linked,
      managed: manifest && manifest.id ? { id: manifest.id, version: manifest.version } : null,
    });
  }
  return addons.sort((a, b) => a.title.localeCompare(b.title));
}

/**
 * Splits the files of a package by top-level folder and rejects unsafe paths.
 * @returns {Map<string, {relative: string, data: Buffer}[]>}
 */
function groupByFolder(files, allowedFolders) {
  const groups = new Map();
  for (const { name, data } of files) {
    const segments = name.replace(/\\/g, '/').split('/');
    const bad = segments.some((part) => part === '' || part === '.' || part === '..' || /[:*?"<>|\0]/.test(part));
    if (bad || segments.length < 2) {
      throw new AddonError('INVALID_PACKAGE', `The package has an unsafe file path: ${name}`);
    }
    const [folder, ...rest] = segments;
    if (!allowedFolders.includes(folder)) {
      throw new AddonError('INVALID_PACKAGE', `The package has a folder that the marketplace does not list: ${folder}`);
    }
    if (!groups.has(folder)) groups.set(folder, []);
    groups.get(folder).push({ relative: rest.join('/'), data });
  }
  for (const folder of allowedFolders) {
    const group = groups.get(folder);
    if (!group || !group.some((file) => !file.relative.includes('/') && file.relative.toLowerCase().endsWith('.toc'))) {
      throw new AddonError('INVALID_PACKAGE', `The package has no .toc file for the folder ${folder}.`);
    }
  }
  return groups;
}

/** Throws if a folder must not be replaced or removed. */
async function checkReplaceable(addonsDir, folder, allowUnmanaged) {
  const target = path.join(addonsDir, folder);
  const stat = await lstatOrNull(target);
  if (!stat) return false;
  if (stat.isSymbolicLink()) {
    throw new AddonError('LINKED', `${folder} is a link to a development copy. Remove the link first (npm run unlink).`);
  }
  if (!allowUnmanaged && !(await readManifest(target))) {
    throw new AddonError('UNMANAGED', `${folder} is already installed, but not by this manager.`);
  }
  return true;
}

/**
 * Installs or updates an addon from a package.
 * The new files go to a staging folder first, and each addon folder is then swapped in
 * with a rename, so a failure does not leave a half-written addon.
 *
 * @param {object} options
 * @param {string} options.addonsDir
 * @param {{id: string, version: string, folders: string[]}} options.addon marketplace entry
 * @param {Buffer} options.zip the package, already checked against its SHA-256
 * @param {boolean} [options.allowUnmanaged] replace a folder that the manager did not install
 */
export async function installAddon({ addonsDir, addon, zip, allowUnmanaged = false }) {
  for (const folder of addon.folders) {
    if (!SAFE_NAME.test(folder)) throw new AddonError('INVALID_PACKAGE', `Invalid addon folder name: ${folder}`);
  }
  const groups = groupByFolder(readZip(zip), addon.folders);
  const existing = new Map();
  for (const folder of addon.folders) existing.set(folder, await checkReplaceable(addonsDir, folder, allowUnmanaged));

  await fs.mkdir(addonsDir, { recursive: true });
  const staging = path.join(path.dirname(addonsDir), `.wfam-staging-${randomBytes(4).toString('hex')}`);
  const swapped = [];
  try {
    for (const [folder, files] of groups) {
      const base = path.join(staging, 'new', folder);
      for (const file of files) {
        const destination = path.join(base, ...file.relative.split('/'));
        await fs.mkdir(path.dirname(destination), { recursive: true });
        await fs.writeFile(destination, file.data);
      }
      const manifest = { id: addon.id, version: addon.version, installedAt: new Date().toISOString() };
      await fs.writeFile(path.join(base, MANIFEST_FILE), JSON.stringify(manifest, null, 2));
    }
    await fs.mkdir(path.join(staging, 'old'), { recursive: true });
    for (const folder of addon.folders) {
      const target = path.join(addonsDir, folder);
      const backup = path.join(staging, 'old', folder);
      if (existing.get(folder)) await fs.rename(target, backup);
      swapped.push({ target, backup, hadOld: existing.get(folder) });
      await fs.rename(path.join(staging, 'new', folder), target);
    }
  } catch (error) {
    for (const { target, backup, hadOld } of swapped.reverse()) {
      await fs.rm(target, { recursive: true, force: true });
      if (hadOld) await fs.rename(backup, target).catch(() => {});
    }
    throw error;
  } finally {
    await fs.rm(staging, { recursive: true, force: true });
  }
}

/**
 * Removes addon folders.
 * @param {object} options
 * @param {string} options.addonsDir
 * @param {string[]} options.folders
 * @param {boolean} [options.allowUnmanaged] remove a folder that the manager did not install
 */
export async function uninstallAddon({ addonsDir, folders, allowUnmanaged = false }) {
  const present = [];
  for (const folder of folders) {
    if (!SAFE_NAME.test(folder)) throw new AddonError('INVALID_PACKAGE', `Invalid addon folder name: ${folder}`);
    if (await checkReplaceable(addonsDir, folder, allowUnmanaged)) present.push(folder);
  }
  if (present.length === 0) throw new AddonError('NOT_INSTALLED', 'The addon is not installed.');
  for (const folder of present) await fs.rm(path.join(addonsDir, folder), { recursive: true, force: true });
}
