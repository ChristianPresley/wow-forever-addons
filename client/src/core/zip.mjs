// Minimal ZIP writer and reader (store and deflate, no zip64, no encryption).
// It covers what addon packages need and keeps the client free of dependencies.

import { deflateRawSync, inflateRawSync } from 'node:zlib';

const LOCAL_SIG = 0x04034b50;
const CENTRAL_SIG = 0x02014b50;
const END_SIG = 0x06054b50;
const UTF8_FLAG = 0x0800;
const DOS_DATE = 0x21; // 1980-01-01, fixed so that the same input gives the same archive

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

export function crc32(buffer) {
  let c = 0xffffffff;
  for (let i = 0; i < buffer.length; i++) c = CRC_TABLE[(c ^ buffer[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** @param {{name: string, data: Buffer}[]} entries @returns {Buffer} */
export function createZip(entries) {
  const parts = [];
  const central = [];
  let offset = 0;
  for (const { name, data } of entries) {
    const nameBuf = Buffer.from(name, 'utf8');
    const compressed = deflateRawSync(data, { level: 9 });
    const crc = crc32(data);

    const local = Buffer.alloc(30);
    local.writeUInt32LE(LOCAL_SIG, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(UTF8_FLAG, 6);
    local.writeUInt16LE(8, 8);
    local.writeUInt16LE(0, 10);
    local.writeUInt16LE(DOS_DATE, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    parts.push(local, nameBuf, compressed);

    const header = Buffer.alloc(46);
    header.writeUInt32LE(CENTRAL_SIG, 0);
    header.writeUInt16LE(20, 4);
    header.writeUInt16LE(20, 6);
    header.writeUInt16LE(UTF8_FLAG, 8);
    header.writeUInt16LE(8, 10);
    header.writeUInt16LE(0, 12);
    header.writeUInt16LE(DOS_DATE, 14);
    header.writeUInt32LE(crc, 16);
    header.writeUInt32LE(compressed.length, 20);
    header.writeUInt32LE(data.length, 24);
    header.writeUInt16LE(nameBuf.length, 28);
    header.writeUInt32LE(offset, 42);
    central.push(header, nameBuf);

    offset += local.length + nameBuf.length + compressed.length;
  }
  const centralBuf = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(END_SIG, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(centralBuf.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, centralBuf, end]);
}

/**
 * Reads all files of an archive into memory. Directory entries are skipped.
 * @param {Buffer} buffer
 * @param {{maxTotalSize?: number}} [options] limit on the total uncompressed size
 * @returns {{name: string, data: Buffer}[]}
 */
export function readZip(buffer, { maxTotalSize = 256 * 1024 * 1024 } = {}) {
  let end = -1;
  for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 22 - 0xffff); i--) {
    if (buffer.readUInt32LE(i) === END_SIG) {
      end = i;
      break;
    }
  }
  if (end < 0) throw new Error('Not a ZIP archive.');
  const count = buffer.readUInt16LE(end + 10);
  let p = buffer.readUInt32LE(end + 16);
  if (count === 0xffff || p === 0xffffffff) throw new Error('ZIP64 archives are not supported.');

  const files = [];
  let total = 0;
  for (let i = 0; i < count; i++) {
    if (p + 46 > buffer.length || buffer.readUInt32LE(p) !== CENTRAL_SIG) throw new Error('Damaged ZIP directory.');
    const flags = buffer.readUInt16LE(p + 8);
    const method = buffer.readUInt16LE(p + 10);
    const crc = buffer.readUInt32LE(p + 16);
    const compressedSize = buffer.readUInt32LE(p + 20);
    const size = buffer.readUInt32LE(p + 24);
    const nameLength = buffer.readUInt16LE(p + 28);
    const extraLength = buffer.readUInt16LE(p + 30);
    const commentLength = buffer.readUInt16LE(p + 32);
    const localOffset = buffer.readUInt32LE(p + 42);
    const name = buffer.toString('utf8', p + 46, p + 46 + nameLength);
    p += 46 + nameLength + extraLength + commentLength;

    if (flags & 1) throw new Error('Encrypted ZIP archives are not supported.');
    if (name.endsWith('/')) continue;
    if (localOffset + 30 > buffer.length || buffer.readUInt32LE(localOffset) !== LOCAL_SIG) {
      throw new Error(`Damaged ZIP entry: ${name}`);
    }
    const start = localOffset + 30 + buffer.readUInt16LE(localOffset + 26) + buffer.readUInt16LE(localOffset + 28);
    if (start + compressedSize > buffer.length) throw new Error(`Damaged ZIP entry: ${name}`);
    total += size;
    if (total > maxTotalSize) throw new Error('ZIP archive is too large.');

    const raw = buffer.subarray(start, start + compressedSize);
    let data;
    if (method === 0) data = Buffer.from(raw);
    else if (method === 8) data = inflateRawSync(raw, { maxOutputLength: Math.max(size, 1) });
    else throw new Error(`Unsupported ZIP compression method ${method}: ${name}`);
    if (data.length !== size || crc32(data) !== crc) throw new Error(`ZIP entry failed its checksum: ${name}`);
    files.push({ name, data });
  }
  return files;
}
