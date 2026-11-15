// Reads the addons in the `addons/` folder of this repository.

import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseToc } from '../../client/src/core/toc.mjs';

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const ADDONS_DIR = path.join(REPO_ROOT, 'addons');

/** Files that stay in the repository and do not go into a package. */
const NOT_PACKAGED = new Set(['addon.json']);

async function walk(dir, prefix = '') {
  const files = [];
  for (const entry of (await fs.readdir(dir, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.name.startsWith('.')) continue;
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) files.push(...(await walk(path.join(dir, entry.name), relative)));
    else if (!prefix && NOT_PACKAGED.has(entry.name)) continue;
    else files.push(relative);
  }
  return files;
}

/**
 * @returns {Promise<{folder: string, dir: string, toc: ReturnType<typeof parseToc> | null, meta: object | null, files: string[]}[]>}
 */
export async function readAddons() {
  const addons = [];
  for (const entry of (await fs.readdir(ADDONS_DIR, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
    if (!entry.isDirectory()) continue;
    const dir = path.join(ADDONS_DIR, entry.name);
    const tocText = await fs.readFile(path.join(dir, `${entry.name}.toc`), 'utf8').catch(() => null);
    const metaText = await fs.readFile(path.join(dir, 'addon.json'), 'utf8').catch(() => null);
    let meta = null;
    try {
      meta = metaText ? JSON.parse(metaText) : null;
    } catch {
      meta = null;
    }
    addons.push({
      folder: entry.name,
      dir,
      toc: tocText ? parseToc(tocText) : null,
      meta,
      files: await walk(dir),
    });
  }
  return addons;
}
