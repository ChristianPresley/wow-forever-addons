// Builds one ZIP package for each addon and the marketplace index.
// Output: dist/marketplace/index.json and dist/marketplace/<Folder>-<version>.zip

import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

import { INDEX_SCHEMA } from '../client/src/core/marketplace.mjs';
import { createZip } from '../client/src/core/zip.mjs';
import { REPO_ROOT, readAddons } from './lib/addons.mjs';

const OUT_DIR = path.join(REPO_ROOT, 'dist', 'marketplace');

await fs.rm(OUT_DIR, { recursive: true, force: true });
await fs.mkdir(OUT_DIR, { recursive: true });

const entries = [];
for (const addon of await readAddons()) {
  if (!addon.toc || !addon.meta) throw new Error(`${addon.folder} is incomplete. Run "npm run lint".`);
  const files = [];
  for (const file of addon.files) {
    files.push({ name: `${addon.folder}/${file}`, data: await fs.readFile(path.join(addon.dir, file)) });
  }
  const zip = createZip(files);
  const fileName = `${addon.folder}-${addon.toc.version}.zip`;
  await fs.writeFile(path.join(OUT_DIR, fileName), zip);
  entries.push({
    id: addon.meta.id,
    name: addon.toc.title,
    version: addon.toc.version,
    category: addon.meta.category,
    summary: addon.meta.summary,
    description: addon.meta.description,
    author: addon.toc.fields.Author ?? '',
    homepage: addon.toc.fields['X-Website'] ?? '',
    interfaces: addon.toc.interfaces,
    folders: [addon.folder],
    download: {
      url: fileName,
      sha256: createHash('sha256').update(zip).digest('hex'),
      size: zip.length,
    },
  });
  console.log(`${fileName}  ${zip.length} bytes`);
}

const index = { schema: INDEX_SCHEMA, generatedAt: new Date().toISOString(), addons: entries };
await fs.writeFile(path.join(OUT_DIR, 'index.json'), `${JSON.stringify(index, null, 2)}\n`);
console.log(`index.json  ${entries.length} addons -> ${path.relative(REPO_ROOT, OUT_DIR)}`);
