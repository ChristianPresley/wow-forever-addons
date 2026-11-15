// Links the addons of this repository into a Forever install, so that the game loads
// the working copy. `--unlink` removes the links again.
//
//   node tools/link-addons.mjs [--unlink] [--install "D:\World of Warcraft"]

import fs from 'node:fs/promises';
import path from 'node:path';

import { detectInstalls } from '../client/src/core/detect.mjs';
import { readAddons } from './lib/addons.mjs';

const args = process.argv.slice(2);
const unlink = args.includes('--unlink');
const installArg = args.includes('--install') ? args[args.indexOf('--install') + 1] : null;

const installs = await detectInstalls(installArg ? { roots: [], extraRoots: [installArg] } : {});
if (installs.length === 0) {
  console.error('No WoW: Forever install found. Use --install <folder>.');
  process.exit(1);
}
if (installs.length > 1) {
  console.error('More than one install found. Choose one with --install <folder>:');
  for (const install of installs) console.error(`  ${install.flavorDir}`);
  process.exit(1);
}

const { addonsDir } = installs[0];
await fs.mkdir(addonsDir, { recursive: true });

// Removes a link only. A junction is removed with rmdir, a symbolic link with unlink.
// Neither call touches the folder that the link points to.
async function removeLink(target) {
  await fs.unlink(target).catch(() => fs.rmdir(target));
}

for (const addon of await readAddons()) {
  const target = path.join(addonsDir, addon.folder);
  const stat = await fs.lstat(target).catch(() => null);
  if (stat && !stat.isSymbolicLink()) {
    console.log(`skipped  ${addon.folder}: a real folder is installed there. Uninstall it first.`);
  } else if (unlink) {
    if (stat) await removeLink(target);
    console.log(`${stat ? 'unlinked' : 'no link '} ${addon.folder}`);
  } else {
    if (stat) await removeLink(target);
    await fs.symlink(addon.dir, target, 'junction');
    console.log(`linked   ${addon.folder} -> ${addon.dir}`);
  }
}
console.log(`AddOns folder: ${addonsDir}`);
