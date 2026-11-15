// Version comparison for addon versions such as "1.2.3" or "v12.9.0-beta".

function parts(version) {
  return String(version ?? '')
    .trim()
    .replace(/^v/i, '')
    .split(/[-+]/)[0]
    .split('.')
    .map((part) => Number.parseInt(part, 10) || 0);
}

/** @returns {number} negative if a is older than b, positive if newer, 0 if equal */
export function compareVersions(a, b) {
  const pa = parts(a);
  const pb = parts(b);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (diff !== 0) return diff;
  }
  return 0;
}
