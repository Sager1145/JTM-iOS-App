import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { PUBLIC_DIR, resolveAppScript } from '../lib/app-family-sandbox.mjs';
const html = fs.readFileSync(path.join(PUBLIC_DIR, 'index.html'), 'utf8');
const assets = [...html.matchAll(/<(?:script|link)\b[^>]*\b(?:src|href)="([^"]+)"/g)]
  .map(match => match[1].split(/[?#]/)[0])
  .filter(asset => !/^(?:[a-z]+:|\/\/)/i.test(asset));
for (const asset of new Set(assets)) {
  const file = asset === 'app-core.js' ? resolveAppScript(asset)
    : asset.startsWith('api/') ? path.join(PUBLIC_DIR, '..', 'data', asset.slice(4))
    : path.join(PUBLIC_DIR, asset);
  if (!fs.existsSync(file)) throw new Error(`Missing local asset: ${asset}`);
  if (asset.endsWith('.js')) new vm.Script(fs.readFileSync(file, 'utf8'), { filename: asset });
}
console.log(`Source check passed: ${new Set(assets).size} local assets.`);
