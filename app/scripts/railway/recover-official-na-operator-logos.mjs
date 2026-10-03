#!/usr/bin/env node
/** Recover explicitly reviewed artwork without modifying any runtime manifest.
 * Run from app/: node scripts/railway/recover-official-na-operator-logos.mjs --download
 * Audit only: node scripts/railway/recover-official-na-operator-logos.mjs
 * Requires sharp (SHARP_MODULE may name an installed absolute module directory).
 * Existing assets are never overwritten; network content must match pinned SHA.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';

const appRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const catalog = JSON.parse(await fs.readFile(new URL('./na-official-logo-catalog.json', import.meta.url), 'utf8'));
const sharp = createRequire(import.meta.url)(process.env.SHARP_MODULE || 'sharp');
const download = process.argv.includes('--download');
const packageData = JSON.parse(await fs.readFile(path.join(appRoot, 'public/rail/us-2025.json'), 'utf8'));
const sha = (body) => createHash('sha256').update(body).digest('hex');
const report = [];
let failed = false;
for (const row of catalog.operators) {
  const lineIds = packageData.lines.filter((line) => row.lineIds?.includes(line.id)
    || (row.linePrefix && line.id.startsWith(row.linePrefix))).map((line) => line.id);
  const evidence = { ...row, lineIds, checkedAt: new Date().toISOString(), retrievedAt: null, sourceSha256: null, sha256: null };
  if (!row.download) { report.push(evidence); continue; }
  const asset = path.join(appRoot, 'public', row.localFile);
  try {
    try { await fs.access(asset); }
    catch (error) {
      if (error.code !== 'ENOENT' || !download) throw error;
      const response = await fetch(row.source, { signal: AbortSignal.timeout(30000), headers: { 'User-Agent': 'JTM-RailMap-BrandAudit/1.0' } });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const body = Buffer.from(await response.arrayBuffer());
      evidence.sourceSha256 = sha(body);
      if (row.sourceSha256 && row.sourceSha256 !== evidence.sourceSha256) throw new Error('Official artwork changed: source SHA mismatch; re-review required');
      const svg = body.subarray(0, 1000).toString().includes('<svg');
      if (svg && /<(?:script|foreignObject)\b|(?:href|xlink:href)\s*=\s*["']https?:/i.test(body.toString())) throw new Error('SVG contains executable or external content');
      const png = svg ? await sharp(body).resize({ width: 512 }).png().toBuffer() : body;
      if (!png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) throw new Error('Asset is not PNG');
      await fs.writeFile(asset, png, { flag: 'wx' });
      evidence.retrievedAt = new Date().toISOString();
    }
    const body = await fs.readFile(asset);
    const meta = await sharp(body).metadata();
    if (meta.format !== 'png' || !(meta.width > 0 && meta.height > 0)) throw new Error('Invalid native PNG');
    evidence.sha256 = sha(body);
    evidence.sourceSha256 ||= row.sourceSha256 || null;
    evidence.retrievedAt ||= row.retrievedAt || null;
    if (row.sha256 && row.sha256 !== evidence.sha256) throw new Error('Local PNG SHA mismatch');
    evidence.width = meta.width; evidence.height = meta.height;
    evidence.nativeFormat = 'PNG';
  } catch (error) { evidence.error = error.message; failed = true; }
  report.push(evidence);
}
process.stdout.write(JSON.stringify({ format: catalog.format, manifestSynchronization: catalog.manifestSynchronization, operators: report }, null, 2) + '\n');
if (failed) process.exitCode = 1;
