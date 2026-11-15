// Reader for WoW addon .toc files.

/** Interface number of the WoW: Forever client (1.60.x). */
export const FOREVER_INTERFACE = 16001;

/** TOC name suffixes that the Forever client loads in preference to the plain file. */
const FOREVER_SUFFIXES = ['_Camelot', '-Camelot', '_Forever', '-Forever'];

/**
 * @param {string} text
 * @returns {{fields: Record<string, string>, files: string[], interfaces: number[], title: string, version: string}}
 */
export function parseToc(text) {
  const fields = {};
  const files = [];
  for (const rawLine of text.replace(/^﻿/, '').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;
    const field = /^##\s*([^:]+?)\s*:\s*(.*)$/.exec(line);
    if (field) fields[field[1]] = field[2].trim();
    else if (!line.startsWith('#')) files.push(line.replace(/\\/g, '/'));
  }
  const interfaces = (fields.Interface ?? '')
    .split(',')
    .map((part) => Number.parseInt(part.trim(), 10))
    .filter(Number.isFinite);
  return {
    fields,
    files,
    interfaces,
    title: stripEscapes(fields.Title ?? ''),
    version: stripEscapes(fields.Version ?? ''),
  };
}

/** Removes WoW colour and texture escape codes from a display string. */
export function stripEscapes(text) {
  return text
    .replace(/\|c[0-9a-fA-F]{8}/g, '')
    .replace(/\|cn[^:|]*:/g, '')
    .replace(/\|r/g, '')
    .replace(/\|T[^|]*\|t/g, '')
    .trim();
}

/**
 * Picks the TOC file that the Forever client would load for an addon folder.
 * @param {string} folder addon folder name
 * @param {string[]} fileNames names of the files in the folder
 * @returns {string | null}
 */
export function pickTocFile(folder, fileNames) {
  const tocs = fileNames.filter((name) => name.toLowerCase().endsWith('.toc'));
  const byLower = new Map(tocs.map((name) => [name.toLowerCase(), name]));
  for (const suffix of [...FOREVER_SUFFIXES, '']) {
    const match = byLower.get(`${folder}${suffix}.toc`.toLowerCase());
    if (match) return match;
  }
  return tocs[0] ?? null;
}
