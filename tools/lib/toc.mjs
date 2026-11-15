// Reader for WoW addon .toc files, for the lint and the marketplace build.
// The addon manager has its own reader in client/core/src/toc.rs.

/** Interface number of the WoW: Forever client (1.60.x). */
export const FOREVER_INTERFACE = 16001;

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
  return { fields, files, interfaces, title: fields.Title ?? '', version: fields.Version ?? '' };
}
