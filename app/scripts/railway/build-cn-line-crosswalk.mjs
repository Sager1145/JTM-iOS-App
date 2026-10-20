#!/usr/bin/env node
// Regenerates data/registry/cn/line-crosswalk.json from the committed OSM route_master snapshot
// (osm-route-masters.json) and the CN ledger. `--check` verifies only.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const reg = join(dirname(fileURLToPath(import.meta.url)), '../../data/registry/cn');
const rows = (f) => readFileSync(join(reg, f), 'utf8').split('\n').filter(Boolean).slice(1).map((l) => JSON.parse(l));
const lpNum = (id) => Number(id.split(':')[2]);
const retired = new Set(rows('events.jsonl').filter((e) => e.event === 'retire').map((e) => e.id));

const lpsByRelation = new Map();
for (const r of rows('lp.ref.jsonl')) {
  if (r.scheme !== 'package-line' || retired.has(r.id)) continue;
  const m = /^cn-osm-relation-(\d+)(?:-branch-\d+)?$/.exec(r.value);
  if (!m) continue;
  const list = lpsByRelation.get(Number(m[1])) ?? [];
  if (!list.includes(r.id)) list.push(r.id);
  lpsByRelation.set(Number(m[1]), list);
}

const masters = JSON.parse(readFileSync(join(reg, 'osm-route-masters.json'), 'utf8')).elements
  .filter((e) => e.type === 'relation').sort((a, b) => a.id - b.id);
const claims = new Map();
for (const m of masters) for (const mem of m.members ?? []) if (mem.type === 'relation') claims.set(mem.ref, [...(claims.get(mem.ref) ?? []), m.id]);
const doubled = new Set([...claims].filter(([, ids]) => ids.length > 1).map(([ref]) => ref));
if (doubled.size) console.error(`skipped ${doubled.size} relations in two masters: ${[...doubled].sort((a, b) => a - b).join(',')}`);

const groups = [];
const grouped = new Set();
for (const m of masters) {
  const lp = [...new Set((m.members ?? []).filter((x) => x.type === 'relation' && !doubled.has(x.ref)).flatMap((x) => lpsByRelation.get(x.ref) ?? []))]
    .sort((a, b) => lpNum(a) - lpNum(b));
  if (!lp.length) continue;
  const name = m.tags?.name ?? m.tags?.ref ?? m.tags?.['name:zh'] ?? `relation ${m.id}`;
  for (const x of m.members) grouped.add(x.ref);
  groups.push({
    slug: `osm-route-master-${m.id}`, name, lp,
    why: `OSM route_master '${name}' groups these route relations as one line`,
    source: `https://www.openstreetmap.org/relation/${m.id}`, reviewedBy: 'osm-route-master 2026-10-20',
  });
}
for (const [rel, list] of [...lpsByRelation]) {
  if (list.length < 2 || grouped.has(rel)) continue;
  groups.push({
    slug: `osm-relation-${rel}`, lp: [...list].sort((a, b) => lpNum(a) - lpNum(b)),
    why: 'branches of one OSM route relation', source: `https://www.openstreetmap.org/relation/${rel}`, reviewedBy: 'osm-relation 2026-10-20',
  });
}
const out = JSON.stringify({ schema: 'jtm-line-crosswalk/1', groups }, null, 1) + '\n';
const target = join(reg, 'line-crosswalk.json');
if (process.argv.includes('--check')) {
  if (readFileSync(target, 'utf8') !== out) { console.error('line-crosswalk.json is stale; run build-cn-line-crosswalk.mjs'); process.exit(1); }
  console.log(`ok: ${groups.length} groups`);
} else { writeFileSync(target, out); console.log(`wrote ${groups.length} groups`); }
