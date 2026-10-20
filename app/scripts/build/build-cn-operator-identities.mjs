#!/usr/bin/env node
// Derives cn.op<seq> operator identities from the CN registry ledger and merges them into
// ios/RailKit/Sources/RailCore/Resources/operator-identities.json. `--check` verifies only.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { VARIANTS } from './search-fold.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '../../..');
const reg = join(root, 'app/data/registry/cn');
const target = join(root, 'ios/RailKit/Sources/RailCore/Resources/operator-identities.json');
const rows = (f) => readFileSync(join(reg, f), 'utf8').split('\n').filter(Boolean).slice(1).map((l) => JSON.parse(l));

const seq = (id) => Number(id.split(':')[2]);
const merge = new Map(rows('alias.jsonl').filter((a) => a.scheme === 'operator-merge' && a.old.startsWith('op:cn:')).map((a) => [a.old, a.id]));
const resolve = (id) => { let n = 0; while (merge.has(id) && n++ < 50) id = merge.get(id); return id; };
const retired = new Set(rows('events.jsonl').filter((e) => e.event === 'retire').map((e) => e.id));
const live = rows('op.jsonl').map((r) => r.id).filter((id) => !retired.has(id) && !merge.has(id));
const spellings = new Map(live.map((id) => [id, []]));
const own = new Map();
for (const r of rows('op.ref.jsonl')) {
  if (r.scheme !== 'package-operator') continue;
  if (r.id === resolve(r.id) && !own.has(r.id)) own.set(r.id, r.value);
  const list = spellings.get(resolve(r.id));
  if (list && !list.includes(r.value)) list.push(r.value);
}
// Traditional-only characters: SearchFold variants that are not Japanese shinjitai, plus observed extras.
const HANT = new Set([...Object.entries(VARIANTS).filter(([k, v]) => k !== v && !'営広浜沢関県気発図桜竜戸楽渋円黒徳歩経塩辺恵浅駒舘庁蔵'.includes(k)).map(([k]) => k), ...'國區灣門運業團務開與華廣銀貿體資實郵齊龍陽際島萬']);
const isLatin = (s) => !/[\u3400-\u9fff]/.test(s);
const isHant = (s) => [...s].some((c) => HANT.has(c));
// Mirrors OperatorBranding.companyLabel for strings without table entries.
const labelOne = (s) => s.trim().replaceAll('株式会社', '').replaceAll('有限会社', '').replace(/^(一般社団法人|一般財団法人|公益社団法人|公益財団法人|地方独立行政法人)/, '').trim();
const label = (s) => s.split('/').map((p) => labelOne(p)).filter(Boolean).join('/');

const entries = live.filter((id) => own.has(id)).map((id) => {
  const legal = own.get(id);
  const all = [legal, ...spellings.get(id).filter((n) => n !== legal)];
  const names = { zhHans: all.filter((n) => !isLatin(n) && !isHant(n)) };
  const hant = all.filter((n) => !isLatin(n) && isHant(n));
  if (hant.length) names.zhHant = hant;
  return { code: `cn.op${seq(id)}`, region: 'cn', legal, label: label(legal), names, aliases: all.filter(isLatin), families: [] };
}).sort((a, b) => (a.code < b.code ? -1 : 1));

const doc = JSON.parse(readFileSync(target, 'utf8'));
doc.operators = [...doc.operators.filter((o) => o.region !== 'cn'), ...entries].sort((a, b) => (a.code < b.code ? -1 : a.code > b.code ? 1 : 0));
const out = JSON.stringify(doc, null, 2) + '\n';
if (process.argv.includes('--check')) {
  if (readFileSync(target, 'utf8') !== out) { console.error('operator-identities.json is stale; run build-cn-operator-identities.mjs'); process.exit(1); }
  console.log(`ok: ${entries.length} cn operators`);
} else { writeFileSync(target, out); console.log(`wrote ${entries.length} cn operators`); }
