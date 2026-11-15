// Checks each addon: TOC fields, the file list, addon.json and Lua syntax.

import fs from 'node:fs/promises';
import path from 'node:path';

import luaparse from 'luaparse';

import { FOREVER_INTERFACE } from '../client/src/core/toc.mjs';
import { readAddons } from './lib/addons.mjs';

const problems = [];
const addons = await readAddons();
const ids = new Set();

for (const addon of addons) {
  const fail = (message) => problems.push(`${addon.folder}: ${message}`);

  if (!addon.toc) {
    fail(`${addon.folder}.toc is missing.`);
    continue;
  }
  if (!addon.toc.interfaces.includes(FOREVER_INTERFACE)) fail(`## Interface must include ${FOREVER_INTERFACE}.`);
  if (!addon.toc.title) fail('## Title is missing.');
  if (!/^\d+\.\d+\.\d+$/.test(addon.toc.version)) fail('## Version must have the form 1.2.3.');

  if (!addon.meta) {
    fail('addon.json is missing or is not valid JSON.');
  } else {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(addon.meta.id ?? '')) fail('addon.json: id must be lower-case letters, digits and hyphens.');
    if (ids.has(addon.meta.id)) fail(`addon.json: the id ${addon.meta.id} is used by more than one addon.`);
    ids.add(addon.meta.id);
    for (const key of ['category', 'summary', 'description']) {
      if (typeof addon.meta[key] !== 'string' || !addon.meta[key]) fail(`addon.json: ${key} is missing.`);
    }
  }

  const listed = new Set(addon.toc.files.map((file) => file.toLowerCase()));
  for (const file of addon.toc.files) {
    if (!addon.files.some((present) => present.toLowerCase() === file.toLowerCase())) fail(`the TOC lists ${file}, but the file does not exist.`);
  }
  for (const file of addon.files) {
    if (!/\.(lua|xml)$/i.test(file)) continue;
    if (file.toLowerCase().endsWith('.lua')) {
      try {
        luaparse.parse(await fs.readFile(path.join(addon.dir, file), 'utf8'), { luaVersion: '5.1' });
      } catch (error) {
        fail(`${file}: ${error.message}`);
      }
    }
    if (!file.includes('/') && !listed.has(file.toLowerCase())) fail(`${file} is not listed in the TOC.`);
  }
}

if (problems.length > 0) {
  console.error(problems.join('\n'));
  console.error(`\n${problems.length} problem(s) in ${addons.length} addon(s).`);
  process.exit(1);
}
console.log(`${addons.length} addons checked, no problems.`);
