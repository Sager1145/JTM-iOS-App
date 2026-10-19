#!/usr/bin/env node
// Bounded own-direction display proposal; retain the real compound turn and physical data.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const EVIDENCE = 'scripts/railway/denentoshi-shimmachi-display-evidence.json';
const KEY = 'denentoshi-shimmachi-display';
const LINE = 'jp-東急電鉄-田園都市線';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const owns = value => JSON.stringify(value).includes(JSON.stringify(LINE));
const distance = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360), (b[1] - a[1]) * 111320);
const length = points => points.slice(1).reduce((total, point, index) => total + distance(points[index], point), 0);

function validateEvidence(e) {
  assert.equal(e.format, 'jtm-denentoshi-shimmachi-display-v1');
  assert.equal(e.lineID, LINE);
  assert.equal(e.intervalIndex, 3);
  assert.deepEqual(e.guardIndices, [7, 13]);
  assert.deepEqual(e.guards, [[139.65614, 35.63095], [139.65139, 35.63089]]);
  assert.equal(e.reference.wayID, '169057662', 'Unreviewed own direction');
  assert.equal(e.reference.version, '25', 'Unreviewed way version');
  assert.equal(e.reference.tags.source, 'KSJ2', 'Unreviewed source ancestry');
  assert.deepEqual(e.reference.directionRelationIDs, ['9341815'], 'Unreviewed own direction');
  assert.equal(e.referenceRelation.id, '9341815');
  assert.equal(e.referenceRelation.tags.from, '渋谷');
  assert.equal(e.referenceRelation.tags.to, '中央林間');
  assert(e.referenceRelation.localRailwayMembers.some(row => row.ref === e.reference.wayID));
  assert.equal(e.reference.coordinates.length, 10);
  assert(e.reference.coordinates.every(point => point.length === 2 && point.every(Number.isFinite)));
  assert.equal(e.sources.engineering, 'https://www.tokyu.co.jp/history/shintamasen/pdf/shintamasen_chapter06.pdf', 'Unreviewed source');
  assert.equal(e.sources.way, 'https://www.openstreetmap.org/way/169057662', 'Unreviewed source');
  assert.equal(e.sources.relation, 'https://www.openstreetmap.org/relation/9341815', 'Unreviewed source');
}

function repairedLine(e) {
  const line = structuredClone(e.baselineLine), original = network.decodeIntervals(line)[3];
  assert.equal(line.id, LINE);
  assert.deepEqual([original[7], original[13]], e.guards, 'Unreviewed splice guards');
  assert.equal(line.displayIntervalCoordinates?.[3], undefined, 'Unreviewed baseline display interval');
  line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates,
    3: [...original.slice(0, 8), ...structuredClone(e.reference.coordinates.slice(1, -1)), ...original.slice(13)] };
  return line;
}

export function repairPackage(input, e = read(EVIDENCE)) {
  validateEvidence(e);
  assert.match(input.geometrySource?.license || '', /OpenStreetMap.*ODbL/i, 'Existing OSM license attribution required');
  const pkg = structuredClone(input), indices = pkg.lines.flatMap((line, index) => line.id === LINE ? [index] : []);
  assert.equal(indices.length, 1, 'Unreviewed source line identity');
  const proposed = repairedLine(e);
  assert(equal(pkg.lines[indices[0]], e.baselineLine) || equal(pkg.lines[indices[0]], proposed), 'Unreviewed source line changed');
  pkg.lines[indices[0]] = proposed;
  const provenance = { reviewedAt: e.reviewedAt, scope: e.scope, sources: e.sources,
    lineID: LINE, intervalIndex: 3, guardIndices: e.guardIndices, wayID: e.reference.wayID,
    researchPath: e.researchPath, script: 'app/scripts/railway/repair-denentoshi-shimmachi-display.mjs',
    evidence: 'app/' + EVIDENCE, physicalTopologyChanged: false };
  pkg.geometrySource.manualOverrides ||= {};
  const previous = pkg.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'Unreviewed repair provenance');
  pkg.geometrySource.manualOverrides[KEY] = provenance;
  return pkg;
}

export function repairParts(pkg, input, e = read(EVIDENCE)) {
  validateEvidence(e);
  const line = pkg.lines.find(row => row.id === LINE);
  assert(equal(line, repairedLine(e)), 'Unreviewed package display repair');
  assert.equal(e.baselineRows.partsByRegion.length, 1);
  const expected = structuredClone(e.baselineRows), row = expected.partsByRegion[0];
  assert.deepEqual(row.slice(0, 4), [LINE, 0, -1, -1]);
  assert.equal(row[6], 'station-approach/groomed');
  assert.equal(row[4], row[7].length);
  const old = network.decodeIntervals(e.baselineLine)[3].slice(7, 14);
  const matches = row[7].flatMap((point, index) => equal(row[7].slice(index, index + old.length), old) ? [index] : []);
  assert.equal(matches.length, 1, 'Unreviewed native splice sequence');
  const start = matches[0];
  row[7] = [...row[7].slice(0, start + 1), ...structuredClone(e.reference.coordinates.slice(1, -1)), ...row[7].slice(start + old.length - 1)];
  row[4] = row[7].length;
  row[5] = Number(length(row[7]).toFixed(1));
  const webParts = network.displayPartsForLine(line);
  assert.equal(webParts.length, 1);
  assert(equal(webParts[0], row[7]), 'Unreviewed Web/native display difference');
  for (const [key, baseline] of Object.entries(e.baselineRows)) {
    const current = (input[key]?.jp || []).filter(owns);
    assert(equal(current, baseline) || equal(current, expected[key]), 'Unreviewed owner metadata: ' + key);
  }
  for (const [key, value] of Object.entries(input)) {
    if (Object.hasOwn(e.baselineRows, key) || key === 'hubReportByRegion') continue;
    assert(!owns(value), 'Unreviewed owner metadata: ' + key);
  }
  const hubMembers = (input.hubReportByRegion?.jp || []).flatMap(hub => (hub.members || [])
    .filter(member => member.lineId === LINE).map(member => ({ hubID: hub.hubId, member })));
  assert(equal(hubMembers, e.baselineHubMembers), 'Unreviewed owner hub metadata');
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(current => current[0] === LINE ? structuredClone(row) : current);
  return result;
}

function main(args = process.argv.slice(2)) {
  const candidate = args.length === 2 && args[0] === '--candidate-root' ? path.resolve(args[1]) : null;
  assert(candidate || equal(args, ['--apply']), 'Use --candidate-root /private/tmp/<dir> or --apply');
  if (candidate) assert(candidate.startsWith('/private/tmp/'), 'Candidate root must be under /private/tmp');
  const paths = { package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json', evidence: EVIDENCE, ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), e = load('evidence');
  const pkg = repairPackage(load('package'), e), lanes = repairParts(pkg, load('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg, Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  const outputs = { package: JSON.stringify(pkg), lanes: JSON.stringify(lanes) + '\n',
    ...Object.fromEntries(Object.entries(dependencies).map(([key, value]) => [key, JSON.stringify(value, null, 2) + '\n'])) };
  if (candidate) {
    fs.mkdirSync(candidate, { recursive: true });
    for (const [key, after] of Object.entries(outputs)) fs.writeFileSync(path.join(candidate, path.basename(snapshots[key].path)), after);
  } else {
    const writes = Object.entries(outputs).filter(([key, after]) => after !== snapshots[key].before)
      .map(([key, after]) => ({ ...snapshots[key], after }));
    applyPreparedWrites(writes, Object.values(snapshots));
  }
  console.log(JSON.stringify({ mode: candidate ? 'candidate' : 'applied', lineID: LINE, intervalIndex: 3, physicalTopologyChanged: false }));
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
