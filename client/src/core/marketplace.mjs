// Loads the marketplace index and downloads addon packages.
//
// The index is a JSON file. Each package URL in it is relative to the index, so the
// same index works from a GitHub release and from a local folder.

import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const DEFAULT_SOURCE =
  'https://github.com/ChristianPresley/wow-forever-addons/releases/download/marketplace/index.json';

export const INDEX_SCHEMA = 1;

const ID = /^[a-z0-9][a-z0-9-]*$/;
const FOLDER = /^[A-Za-z0-9][A-Za-z0-9 _!.-]*$/;
const SHA256 = /^[0-9a-f]{64}$/;
const MAX_PACKAGE_BYTES = 64 * 1024 * 1024;

/** Turns an https URL or a local file path into a URL object. */
export function sourceToUrl(source) {
  if (/^https?:\/\//i.test(source)) return new URL(source);
  if (/^file:\/\//i.test(source)) return new URL(source);
  return pathToFileURL(path.resolve(source));
}

async function read(url) {
  if (url.protocol === 'file:') return fs.readFile(fileURLToPath(url));
  if (url.protocol !== 'https:') throw new Error(`The marketplace must use https: ${url.href}`);
  const response = await fetch(url, { redirect: 'follow', headers: { 'user-agent': 'wow-forever-addon-manager' } });
  if (!response.ok) throw new Error(`Download failed with status ${response.status}: ${url.href}`);
  const length = Number(response.headers.get('content-length') ?? 0);
  if (length > MAX_PACKAGE_BYTES) throw new Error(`The file is too large: ${url.href}`);
  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.length > MAX_PACKAGE_BYTES) throw new Error(`The file is too large: ${url.href}`);
  return buffer;
}

/** Throws if the index is not well-formed. Returns the index. */
export function validateIndex(index) {
  if (!index || index.schema !== INDEX_SCHEMA || !Array.isArray(index.addons)) {
    throw new Error('The marketplace index has an unknown format.');
  }
  for (const addon of index.addons) {
    const ok =
      typeof addon.id === 'string' &&
      ID.test(addon.id) &&
      typeof addon.name === 'string' &&
      typeof addon.version === 'string' &&
      Array.isArray(addon.folders) &&
      addon.folders.length > 0 &&
      addon.folders.every((folder) => typeof folder === 'string' && FOLDER.test(folder)) &&
      addon.download &&
      typeof addon.download.url === 'string' &&
      SHA256.test(addon.download.sha256 ?? '');
    if (!ok) throw new Error(`The marketplace index has an invalid entry: ${addon?.id ?? '(no id)'}`);
  }
  return index;
}

/**
 * @param {string} source https URL or local path of index.json
 * @returns {Promise<{schema: number, generatedAt: string, addons: object[]}>}
 */
export async function loadIndex(source) {
  const buffer = await read(sourceToUrl(source));
  let index;
  try {
    index = JSON.parse(buffer.toString('utf8'));
  } catch {
    throw new Error('The marketplace index is not valid JSON.');
  }
  return validateIndex(index);
}

/**
 * Downloads the package of an addon and checks it against the SHA-256 in the index.
 * @param {string} source the source that the index came from
 * @param {{download: {url: string, sha256: string}}} addon
 * @returns {Promise<Buffer>}
 */
export async function downloadPackage(source, addon) {
  const indexUrl = sourceToUrl(source);
  const packageUrl = new URL(addon.download.url, indexUrl);
  if (packageUrl.protocol !== indexUrl.protocol) {
    throw new Error('The package must come from the same kind of source as the index.');
  }
  const buffer = await read(packageUrl);
  const digest = createHash('sha256').update(buffer).digest('hex');
  if (digest !== addon.download.sha256) {
    throw new Error(`The package of ${addon.id} failed its checksum. It was not installed.`);
  }
  return buffer;
}
