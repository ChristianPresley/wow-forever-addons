// Finds World of Warcraft: Forever installations.
//
// A World of Warcraft folder holds one sub-folder for each game flavor. Forever is
// in `_forever_`, and its `.flavor.info` file holds the product code `wowf`.

import { execFile } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const FOREVER_PRODUCT = /^wowf/i;
const FOREVER_FOLDER = /^_forever.*_$/i;
const FLAVOR_FOLDER = /^_.+_$/;

const WINDOWS_SUBPATHS = [
  'World of Warcraft',
  'Games\\World of Warcraft',
  'Program Files (x86)\\World of Warcraft',
  'Program Files\\World of Warcraft',
  'Blizzard\\World of Warcraft',
];

async function exists(target) {
  try {
    await fs.access(target);
    return true;
  } catch {
    return false;
  }
}

async function readText(file) {
  try {
    return await fs.readFile(file, 'utf8');
  } catch {
    return null;
  }
}

/** Product code from a flavor folder's `.flavor.info`, or null. */
export function parseFlavorInfo(text) {
  const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  return lines.length >= 2 ? lines[1] : null;
}

/** Map of product code to version from a `.build.info` file. */
export function parseBuildInfo(text) {
  const lines = text.split(/\r?\n/).filter((line) => line.trim());
  const versions = new Map();
  if (lines.length < 2) return versions;
  const columns = lines[0].split('|').map((column) => column.split('!')[0].trim());
  const productColumn = columns.indexOf('Product');
  const versionColumn = columns.indexOf('Version');
  if (productColumn < 0 || versionColumn < 0) return versions;
  for (const line of lines.slice(1)) {
    const cells = line.split('|');
    if (cells[productColumn]) versions.set(cells[productColumn].trim(), (cells[versionColumn] ?? '').trim());
  }
  return versions;
}

/**
 * Collects the path strings from Battle.net's `product.db`, which is a protobuf message.
 * The walker does not need the schema: it visits each length-delimited field and keeps
 * those that are an absolute path.
 * @param {Buffer} buffer
 * @returns {string[]}
 */
export function extractPathsFromProductDb(buffer) {
  const found = new Set();
  const looksLikePath = /^(?:[A-Za-z]:[\\/]|\/)[^\0-\x1f"<>|?*]{2,259}$/;

  function varint(buf, pos) {
    let value = 0;
    let shift = 0;
    for (let i = 0; i < 10; i++) {
      if (pos >= buf.length) return null;
      const byte = buf[pos++];
      if (shift < 35) value += (byte & 0x7f) * 2 ** shift;
      shift += 7;
      if (!(byte & 0x80)) return { value, pos };
    }
    return null;
  }

  // Returns false if the bytes are not a well-formed message.
  function walk(buf, depth) {
    let pos = 0;
    const strings = [];
    const nested = [];
    while (pos < buf.length) {
      const tag = varint(buf, pos);
      if (!tag || tag.value >>> 3 === 0) return false;
      pos = tag.pos;
      const wire = tag.value & 7;
      if (wire === 0) {
        const v = varint(buf, pos);
        if (!v) return false;
        pos = v.pos;
      } else if (wire === 1) {
        pos += 8;
      } else if (wire === 5) {
        pos += 4;
      } else if (wire === 2) {
        const length = varint(buf, pos);
        if (!length || length.pos + length.value > buf.length) return false;
        nested.push(buf.subarray(length.pos, length.pos + length.value));
        pos = length.pos + length.value;
      } else {
        return false;
      }
      if (pos > buf.length) return false;
    }
    for (const chunk of nested) {
      const text = chunk.toString('utf8');
      if (looksLikePath.test(text)) strings.push(text);
      else if (depth < 8 && chunk.length > 1) walk(chunk, depth + 1);
    }
    for (const text of strings) found.add(text);
    return true;
  }

  walk(buffer, 0);
  return [...found];
}

function registryInstallPaths() {
  if (process.platform !== 'win32') return Promise.resolve([]);
  const keys = [
    'HKLM\\SOFTWARE\\WOW6432Node\\Blizzard Entertainment\\World of Warcraft',
    'HKLM\\SOFTWARE\\Blizzard Entertainment\\World of Warcraft',
  ];
  return Promise.all(
    keys.map(
      (key) =>
        new Promise((resolve) => {
          execFile('reg', ['query', key, '/v', 'InstallPath'], { windowsHide: true }, (error, stdout) => {
            const match = !error && /InstallPath\s+REG_SZ\s+(.+)/.exec(stdout);
            resolve(match ? [match[1].trim()] : []);
          });
        }),
    ),
  ).then((lists) => lists.flat());
}

async function windowsDrives() {
  const letters = 'CDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
  const checks = await Promise.all(letters.map((letter) => exists(`${letter}:\\`)));
  return letters.filter((_, i) => checks[i]).map((letter) => `${letter}:\\`);
}

async function candidateRoots() {
  const candidates = [];
  if (process.platform === 'win32') {
    const programData = process.env.ProgramData ?? 'C:\\ProgramData';
    try {
      const db = await fs.readFile(path.join(programData, 'Battle.net', 'Agent', 'product.db'));
      candidates.push(...extractPathsFromProductDb(db));
    } catch {
      // Battle.net is not installed, or the file cannot be read.
    }
    candidates.push(...(await registryInstallPaths()));
    for (const drive of await windowsDrives()) {
      for (const sub of WINDOWS_SUBPATHS) candidates.push(path.join(drive, sub));
    }
  } else if (process.platform === 'darwin') {
    candidates.push('/Applications/World of Warcraft', path.join(os.homedir(), 'Applications', 'World of Warcraft'));
  } else {
    const home = os.homedir();
    candidates.push(
      path.join(home, 'Games', 'world-of-warcraft', 'drive_c', 'Program Files (x86)', 'World of Warcraft'),
      path.join(home, '.wine', 'drive_c', 'Program Files (x86)', 'World of Warcraft'),
    );
  }
  return candidates;
}

/**
 * Returns the Forever installs under one World of Warcraft folder.
 * @param {string} root
 * @returns {Promise<Install[]>}
 */
export async function inspectRoot(root) {
  let entries;
  try {
    entries = await fs.readdir(root, { withFileTypes: true });
  } catch {
    return [];
  }
  const buildInfo = await readText(path.join(root, '.build.info'));
  const versions = buildInfo ? parseBuildInfo(buildInfo) : new Map();
  const installs = [];
  for (const entry of entries) {
    if (!entry.isDirectory() || !FLAVOR_FOLDER.test(entry.name)) continue;
    const flavorDir = path.join(root, entry.name);
    const flavorInfo = await readText(path.join(flavorDir, '.flavor.info'));
    const product = flavorInfo ? parseFlavorInfo(flavorInfo) : null;
    const isForever = product ? FOREVER_PRODUCT.test(product) : FOREVER_FOLDER.test(entry.name);
    if (!isForever) continue;
    installs.push({
      id: flavorDir.toLowerCase(),
      root,
      flavorDir,
      folder: entry.name,
      product: product ?? 'wowf',
      version: (product && versions.get(product)) || null,
      addonsDir: path.join(flavorDir, 'Interface', 'AddOns'),
    });
  }
  return installs;
}

/**
 * A folder the user picked can be the World of Warcraft folder, the `_forever_`
 * folder, or a folder inside it. This returns the folder and its three nearest parents.
 */
function withParents(folder) {
  const list = [];
  let current = path.resolve(folder);
  for (let i = 0; i < 4; i++) {
    list.push(current);
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
  return list;
}

/**
 * @typedef {object} Install
 * @property {string} id stable key of the install
 * @property {string} root the World of Warcraft folder
 * @property {string} flavorDir the `_forever_` folder
 * @property {string} folder name of the flavor folder
 * @property {string} product Battle.net product code
 * @property {string | null} version client version from `.build.info`
 * @property {string} addonsDir the `Interface/AddOns` folder (it can be absent before the first launch)
 */

/**
 * @param {{extraRoots?: string[], roots?: string[]}} [options]
 *   extraRoots: folders the user added by hand.
 *   roots: replaces the automatic search (used by tests).
 * @returns {Promise<Install[]>}
 */
export async function detectInstalls({ extraRoots = [], roots } = {}) {
  const candidates = roots ?? (await candidateRoots());
  const expanded = [];
  for (const candidate of candidates) expanded.push(...withParents(candidate).slice(0, 2));
  for (const extra of extraRoots) expanded.push(...withParents(extra));

  const seen = new Set();
  const installs = [];
  for (const candidate of expanded) {
    const key = path.resolve(candidate).toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    for (const install of await inspectRoot(path.resolve(candidate))) {
      if (!installs.some((known) => known.id === install.id)) installs.push(install);
    }
  }
  return installs;
}
