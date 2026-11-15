// Draws the source image of the app icon: a gold tile with a dark "F".
// Usage: node tools/make-icon.mjs <out.png>, then in client/: npx tauri icon <out.png>

import fs from 'node:fs';
import { deflateSync } from 'node:zlib';

import { crc32 } from './lib/zip.mjs';

const SIZE = 1024;
const out = process.argv[2];
if (!out) {
  console.error('Usage: node tools/make-icon.mjs <out.png>');
  process.exit(1);
}

const RADIUS = 200;
const MARGIN = 64;

/** Coverage (0 to 1) of a rounded square at a pixel, with a soft edge. */
function tile(x, y) {
  const lo = MARGIN + RADIUS;
  const hi = SIZE - MARGIN - RADIUS;
  const dx = x < lo ? lo - x : x > hi ? x - hi : 0;
  const dy = y < lo ? lo - y : y > hi ? y - hi : 0;
  return Math.min(1, Math.max(0, RADIUS - Math.hypot(dx, dy) + 0.5));
}

/** True inside the letter F. */
function letter(x, y) {
  const stem = x >= 352 && x < 472 && y >= 272 && y < 752;
  const top = x >= 352 && x < 712 && y >= 272 && y < 384;
  const middle = x >= 352 && x < 640 && y >= 468 && y < 568;
  return stem || top || middle;
}

const rows = Buffer.alloc(SIZE * (SIZE * 4 + 1));
for (let y = 0; y < SIZE; y++) {
  const row = y * (SIZE * 4 + 1);
  for (let x = 0; x < SIZE; x++) {
    const p = row + 1 + x * 4;
    const t = (x + y) / (2 * SIZE); // gradient from the top-left to the bottom-right corner
    const dark = letter(x, y);
    rows[p] = dark ? 0x1a : Math.round(0xec + (0xa9 - 0xec) * t);
    rows[p + 1] = dark ? 0x14 : Math.round(0xc0 + (0x77 - 0xc0) * t);
    rows[p + 2] = dark ? 0x08 : Math.round(0x78 + (0x2f - 0x78) * t);
    rows[p + 3] = Math.round(255 * tile(x, y));
  }
}

function chunk(type, data) {
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const head = Buffer.alloc(4);
  head.writeUInt32BE(data.length);
  const tail = Buffer.alloc(4);
  tail.writeUInt32BE(crc32(body));
  return Buffer.concat([head, body, tail]);
}

const header = Buffer.alloc(13);
header.writeUInt32BE(SIZE, 0);
header.writeUInt32BE(SIZE, 4);
header[8] = 8; // bit depth
header[9] = 6; // RGBA

fs.writeFileSync(
  out,
  Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(rows, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]),
);
console.log(`${out}  ${SIZE}x${SIZE}`);
