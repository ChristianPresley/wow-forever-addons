import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';

import { AddonError, installAddon, listInstalled, MANIFEST_FILE, uninstallAddon } from '../src/core/addons.mjs';
import { detectInstalls, extractPathsFromProductDb, parseBuildInfo, parseFlavorInfo } from '../src/core/detect.mjs';
import { downloadPackage, loadIndex, validateIndex } from '../src/core/marketplace.mjs';
import { parseToc, pickTocFile } from '../src/core/toc.mjs';
import { compareVersions } from '../src/core/version.mjs';
import { createZip, readZip } from '../src/core/zip.mjs';
import { Service } from '../src/service.mjs';

let tmp;
before(async () => {
  tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'wfam-test-'));
});
after(async () => {
  await fs.rm(tmp, { recursive: true, force: true });
});

/** Makes a World of Warcraft folder with a Forever flavor and, optionally, a retail flavor. */
async function makeWow(name, { retail = false } = {}) {
  const root = path.join(tmp, name);
  const forever = path.join(root, '_forever_');
  await fs.mkdir(path.join(forever, 'Interface', 'AddOns'), { recursive: true });
  await fs.writeFile(path.join(forever, '.flavor.info'), 'Product Flavor!STRING:0\nwowf\n');
  await fs.writeFile(path.join(root, '.build.info'), 'Branch!STRING:0|Version!STRING:0|Product!STRING:0\nus|12.1.5.1|wow\nus|1.60.1.70938|wowf\n');
  if (retail) {
    await fs.mkdir(path.join(root, '_retail_'), { recursive: true });
    await fs.writeFile(path.join(root, '_retail_', '.flavor.info'), 'Product Flavor!STRING:0\nwow\n');
  }
  return { root, addonsDir: path.join(forever, 'Interface', 'AddOns') };
}

function makePackage(folder, version, extra = []) {
  return createZip([
    { name: `${folder}/${folder}.toc`, data: Buffer.from(`## Interface: 16001\n## Title: |cff00ff00${folder}|r\n## Version: ${version}\n\nCore.lua\n`) },
    { name: `${folder}/Core.lua`, data: Buffer.from('print("hello")\n') },
    ...extra,
  ]);
}

test('zip: files survive a round trip', () => {
  const big = Buffer.alloc(50_000, 'forever ');
  const files = readZip(createZip([{ name: 'A/a.txt', data: Buffer.from('héllo') }, { name: 'A/sub/big.bin', data: big }, { name: 'A/empty', data: Buffer.alloc(0) }]));
  assert.deepEqual(files.map((file) => file.name), ['A/a.txt', 'A/sub/big.bin', 'A/empty']);
  assert.equal(files[0].data.toString(), 'héllo');
  assert.ok(files[1].data.equals(big));
});

test('zip: damaged data is rejected', () => {
  const zip = createZip([{ name: 'A/a.txt', data: Buffer.alloc(2000, 'x') }]);
  zip[40] ^= 0xff;
  assert.throws(() => readZip(zip));
  assert.throws(() => readZip(Buffer.from('not a zip')), /Not a ZIP/);
});

test('toc: fields, file list and Forever TOC choice', () => {
  const toc = parseToc('\uFEFF## Interface: 16001, 120100\r\n## Title: |cFF00FF00Questie|r v1\r\n## Version: v12.9.0\r\n# comment\r\nsrc\\Core.lua\r\n');
  assert.deepEqual(toc.interfaces, [16001, 120100]);
  assert.equal(toc.title, 'Questie v1');
  assert.deepEqual(toc.files, ['src/Core.lua']);
  assert.equal(pickTocFile('Questie', ['Questie.toc', 'Questie_Vanilla.toc', 'Questie_Camelot.toc']), 'Questie_Camelot.toc');
  assert.equal(pickTocFile('Plain', ['Plain.toc', 'x.lua']), 'Plain.toc');
  assert.equal(pickTocFile('None', ['x.lua']), null);
});

test('version: comparison', () => {
  assert.ok(compareVersions('0.1.0', '0.2.0') < 0);
  assert.ok(compareVersions('v1.10.0', '1.9.9') > 0);
  assert.equal(compareVersions('1.0', '1.0.0'), 0);
});

test('detect: flavor and build files', () => {
  assert.equal(parseFlavorInfo('Product Flavor!STRING:0\r\nwowf\r\n'), 'wowf');
  assert.equal(parseBuildInfo('Branch!STRING:0|Version!STRING:0|Product!STRING:0\nus|1.60.1.70938|wowf\n').get('wowf'), '1.60.1.70938');
});

test('detect: paths are read from a protobuf product database', () => {
  const str = (field, text) => Buffer.concat([Buffer.from([(field << 3) | 2, Buffer.byteLength(text)]), Buffer.from(text)]);
  const msg = (field, ...parts) => {
    const body = Buffer.concat(parts);
    return Buffer.concat([Buffer.from([(field << 3) | 2, body.length]), body]);
  };
  const db = Buffer.concat([
    msg(1, str(1, 'wowf'), msg(3, str(1, 'D:/World of Warcraft'), str(2, 'us'))),
    msg(1, str(1, 'agent'), msg(3, str(1, 'C:/ProgramData/Battle.net/Agent'))),
  ]);
  assert.deepEqual(extractPathsFromProductDb(db).sort(), ['C:/ProgramData/Battle.net/Agent', 'D:/World of Warcraft']);
});

test('detect: finds the Forever flavor only, from the root or a folder inside it', async () => {
  const { root, addonsDir } = await makeWow('wow-detect', { retail: true });
  const fromRoot = await detectInstalls({ roots: [root] });
  assert.equal(fromRoot.length, 1);
  assert.equal(fromRoot[0].folder, '_forever_');
  assert.equal(fromRoot[0].version, '1.60.1.70938');
  assert.equal(fromRoot[0].addonsDir, addonsDir);
  const fromAddons = await detectInstalls({ roots: [], extraRoots: [addonsDir] });
  assert.equal(fromAddons.length, 1);
  assert.deepEqual(await detectInstalls({ roots: [path.join(tmp, 'missing')] }), []);
});

test('addons: install, update, list and uninstall', async () => {
  const { addonsDir } = await makeWow('wow-install');
  const addon = { id: 'demo', version: '1.0.0', folders: ['Demo'] };
  await installAddon({ addonsDir, addon, zip: makePackage('Demo', '1.0.0', [{ name: 'Demo/old.lua', data: Buffer.from('') }]) });

  let [listed] = await listInstalled(addonsDir);
  assert.equal(listed.title, 'Demo');
  assert.equal(listed.version, '1.0.0');
  assert.deepEqual(listed.managed, { id: 'demo', version: '1.0.0' });

  await installAddon({ addonsDir, addon: { ...addon, version: '1.1.0' }, zip: makePackage('Demo', '1.1.0') });
  [listed] = await listInstalled(addonsDir);
  assert.equal(listed.version, '1.1.0');
  await assert.rejects(fs.access(path.join(addonsDir, 'Demo', 'old.lua')), 'files of the old version are gone');
  const leftovers = (await fs.readdir(path.dirname(addonsDir))).filter((name) => name.startsWith('.wfam'));
  assert.deepEqual(leftovers, [], 'the staging folder is removed');

  await uninstallAddon({ addonsDir, folders: ['Demo'] });
  assert.deepEqual(await listInstalled(addonsDir), []);
  await assert.rejects(uninstallAddon({ addonsDir, folders: ['Demo'] }), (error) => error.code === 'NOT_INSTALLED');
});

test('addons: a copy installed by hand is kept unless the user allows the change', async () => {
  const { addonsDir } = await makeWow('wow-unmanaged');
  await fs.mkdir(path.join(addonsDir, 'Demo'));
  await fs.writeFile(path.join(addonsDir, 'Demo', 'Demo.toc'), '## Interface: 16001\n## Version: 0.5.0\n');
  await fs.writeFile(path.join(addonsDir, 'Demo', 'mine.lua'), '-- mine');
  const options = { addonsDir, addon: { id: 'demo', version: '1.0.0', folders: ['Demo'] }, zip: makePackage('Demo', '1.0.0') };

  await assert.rejects(installAddon(options), (error) => error instanceof AddonError && error.code === 'UNMANAGED');
  await assert.rejects(uninstallAddon({ addonsDir, folders: ['Demo'] }), (error) => error.code === 'UNMANAGED');
  assert.equal(await fs.readFile(path.join(addonsDir, 'Demo', 'mine.lua'), 'utf8'), '-- mine');

  await installAddon({ ...options, allowUnmanaged: true });
  await fs.access(path.join(addonsDir, 'Demo', MANIFEST_FILE));
});

test('addons: a development link is never replaced or removed', async () => {
  const { addonsDir } = await makeWow('wow-linked');
  const work = path.join(tmp, 'work', 'Demo');
  await fs.mkdir(work, { recursive: true });
  await fs.writeFile(path.join(work, 'Demo.toc'), '## Interface: 16001\n## Version: 9.9.9\n');
  await fs.symlink(work, path.join(addonsDir, 'Demo'), 'junction');

  const [listed] = await listInstalled(addonsDir);
  assert.equal(listed.linked, true);
  const options = { addonsDir, addon: { id: 'demo', version: '1.0.0', folders: ['Demo'] }, zip: makePackage('Demo', '1.0.0'), allowUnmanaged: true };
  await assert.rejects(installAddon(options), (error) => error.code === 'LINKED');
  await assert.rejects(uninstallAddon({ addonsDir, folders: ['Demo'], allowUnmanaged: true }), (error) => error.code === 'LINKED');
  await fs.access(path.join(work, 'Demo.toc'));
});

test('addons: unsafe packages are rejected and nothing is written', async () => {
  const { addonsDir } = await makeWow('wow-unsafe');
  const addon = { id: 'demo', version: '1.0.0', folders: ['Demo'] };
  const cases = [
    makePackage('Demo', '1.0.0', [{ name: 'Demo/../../evil.lua', data: Buffer.from('') }]),
    makePackage('Demo', '1.0.0', [{ name: 'Other/Other.toc', data: Buffer.from('') }]),
    makePackage('Demo', '1.0.0', [{ name: '/abs.lua', data: Buffer.from('') }]),
    makePackage('Demo', '1.0.0', [{ name: 'Demo/C:/x.lua', data: Buffer.from('') }]),
    createZip([{ name: 'Demo/Core.lua', data: Buffer.from('') }]),
  ];
  for (const zip of cases) {
    await assert.rejects(installAddon({ addonsDir, addon, zip }), (error) => error.code === 'INVALID_PACKAGE');
  }
  assert.deepEqual(await fs.readdir(addonsDir), []);
  assert.deepEqual(await fs.readdir(path.dirname(addonsDir)), ['AddOns']);
});

test('marketplace: index validation and checksum', async () => {
  const dir = path.join(tmp, 'market');
  await fs.mkdir(dir, { recursive: true });
  const zip = makePackage('Demo', '1.0.0');
  await fs.writeFile(path.join(dir, 'Demo-1.0.0.zip'), zip);
  const entry = {
    id: 'demo',
    name: 'Demo',
    version: '1.0.0',
    folders: ['Demo'],
    download: { url: 'Demo-1.0.0.zip', sha256: createHash('sha256').update(zip).digest('hex') },
  };
  const source = path.join(dir, 'index.json');
  await fs.writeFile(source, JSON.stringify({ schema: 1, addons: [entry] }));

  const index = await loadIndex(source);
  assert.ok((await downloadPackage(source, index.addons[0])).equals(zip));
  const tampered = { ...entry, download: { ...entry.download, sha256: 'a'.repeat(64) } };
  await assert.rejects(downloadPackage(source, tampered), /checksum/);
  await assert.rejects(downloadPackage(source, { ...entry, download: { ...entry.download, url: 'https://example.com/x.zip' } }), /same kind of source/);
  assert.throws(() => validateIndex({ schema: 2, addons: [] }));
  assert.throws(() => validateIndex({ schema: 1, addons: [{ ...entry, folders: ['../x'] }] }));
  assert.throws(() => validateIndex({ schema: 1, addons: [{ ...entry, id: 'Bad Id' }] }));
});

test('service: scan, install from a marketplace, and uninstall', async () => {
  const { root, addonsDir } = await makeWow('wow-service');
  const source = path.join(tmp, 'market', 'index.json');
  const service = new Service({ settingsFile: path.join(tmp, 'settings', 'settings.json'), defaultSource: source });
  assert.equal(await service.addRoot(path.join(tmp, 'missing')), false);
  assert.equal(await service.addRoot(root), true);
  service.settings.extraRoots = [root];

  const realDetect = (await service.scan()).installs.filter((install) => install.root === root);
  assert.equal(realDetect.length, 1);
  await service.install(realDetect[0].id, 'demo');
  assert.equal((await listInstalled(addonsDir))[0].managed.id, 'demo');
  await service.uninstall(realDetect[0].id, ['Demo']);
  assert.deepEqual(await listInstalled(addonsDir), []);
  await assert.rejects(service.install('unknown', 'demo'), /no longer known/);
});
