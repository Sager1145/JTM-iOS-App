#!/usr/bin/env node
// Reviewed owner-platform display only; physical station rows, km and segments stay intact.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { applyStationLanePins, partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const EVIDENCE = 'scripts/railway/yokohama-itoigawa-own-platform-display-evidence.json';
const KEY = 'yokohama-itoigawa-own-platform-display';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const distance = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360), (b[1] - a[1]) * 111320);
const length = points => points.slice(1).reduce((sum, point, index) => sum + distance(points[index], point), 0);

function validateEvidence(e) {
  assert.equal(e.format, 'jtm-yokohama-itoigawa-own-platform-display-v1');
  assert.deepEqual(e.items.map(item => [item.lineID, item.stationID, item.intervalIndex]),
    [['jp-相模鉄道-相鉄本線', '004633', 0], ['jp-西日本旅客鉄道-大糸線', '001666', 7]]);
  assert.deepEqual(e.sources.yokohama, ['https://www.mlit.go.jp/common/000145491.pdf', 'https://www.openstreetmap.org/relation/9552394'], 'Unreviewed source');
  assert.deepEqual(e.sources.itoigawa, ['https://eki.jr-odekake.net/premises?id=0541482', 'https://www.openstreetmap.org/way/1262851197'], 'Unreviewed source');
}

function repairedLine(item) {
  const line = structuredClone(item.baselineLine), intervals = network.decodeIntervals(line);
  assert.equal(line.id, item.lineID);
  if (item.intervalIndex === 0) {
    assert.equal(line.stations[0][0], item.stationID);
    assert.deepEqual(intervals[0][0], line.stations[0].slice(2, 4));
    line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates,
      0: [intervals[0][0], ...intervals[0].slice(2)] };
    line.stationLaneByCode = { ...line.stationLaneByCode, [item.stationID]: 0 };
  } else {
    assert.equal(item.guardIndex, 32);
    assert.equal(line.stations.at(-1)[0], item.stationID);
    assert.deepEqual(intervals[7].slice(item.guardIndex), item.baselineTail, 'Unreviewed Itoigawa tail');
    assert.deepEqual(item.ownDisplayTail[0], intervals[7][item.guardIndex]);
    assert.deepEqual(item.ownDisplayTail.at(-1), item.displayAnchor);
    assert(item.ownDisplayTail.every(point => point.length === 2 && point.every(Number.isFinite)));
    line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates,
      7: [...intervals[7].slice(0, item.guardIndex + 1), ...structuredClone(item.ownDisplayTail.slice(1))] };
    line.displayStationCoordinates = { ...line.displayStationCoordinates, [item.stationID]: structuredClone(item.displayAnchor) };
  }
  return line;
}

export function repairPackage(input, e = read(EVIDENCE)) {
  validateEvidence(e);
  assert.match(input.geometrySource?.license || '', /OpenStreetMap.*ODbL/i, 'Existing OSM license attribution required');
  const pkg = structuredClone(input);
  for (const item of e.items) {
    const indices = pkg.lines.flatMap((line, index) => line.id === item.lineID ? [index] : []);
    assert.equal(indices.length, 1, 'Unreviewed source line identity');
    const proposed = repairedLine(item), current = pkg.lines[indices[0]];
    assert(equal(current, item.baselineLine) || equal(current, proposed), 'Unreviewed source line changed');
    pkg.lines[indices[0]] = proposed;
  }
  const provenance = { reviewedAt: e.reviewedAt, scope: e.scope, sources: e.sources,
    items: e.items.map(({ lineID, stationID, intervalIndex, researchPath }) => ({ lineID, stationID, intervalIndex, researchPath })),
    script: 'app/scripts/railway/repair-yokohama-itoigawa-own-platform-display.mjs',
    evidence: 'app/' + EVIDENCE, physicalTopologyChanged: false };
  pkg.geometrySource.manualOverrides ||= {};
  const previous = pkg.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'Unreviewed repair provenance');
  pkg.geometrySource.manualOverrides[KEY] = provenance;
  return pkg;
}

function displayInputs(line) {
  const stations = line.stations.map(row => line.displayStationCoordinates?.[row[0]]
    ? [...row.slice(0, 2), ...line.displayStationCoordinates[row[0]], ...row.slice(4)] : row);
  const segments = line.segments.map((row, index) => line.displayIntervalCoordinates?.[index]
    ? [row[0], 0, line.displayIntervalCoordinates[index]] : row);
  return { stations, intervals: network.decodeIntervals({ ...line, stations, segments }) };
}

// Keep interleaved unrelated rows in place while replacing this owner's rows.
function replaceRows(rows, id, replacement) {
  let index = 0;
  const result = rows.flatMap(row => row[0] === id ? (index < replacement.length ? [replacement[index++]] : []) : [row]);
  assert.equal(index, replacement.length, 'Missing owner rows');
  return result;
}

export function repairParts(pkg, input, e = read(EVIDENCE)) {
  validateEvidence(e);
  const ids = e.items.map(item => item.lineID), owns = value => ids.some(id => JSON.stringify(value).includes(id));
  const result = structuredClone(input), proposed = {};
  for (const item of e.items) {
    const line = pkg.lines.find(row => row.id === item.lineID);
    assert(equal(line, repairedLine(item)), 'Package display repair missing');
    const before = network.displayPartsForLine(item.baselineLine), after = network.displayPartsForLine(line);
    assert.equal(before.length, 1); assert.equal(after.length, 1);
    const rows = partRowsForLine(line, after, displayInputs(line), null);
    assert.equal(rows.length, 1);
    proposed[item.lineID] = rows;
  }
  const yoko = e.items[0], rows = proposed[yoko.lineID];
  const oldTotal = length(network.displayPartsForLine(yoko.baselineLine)[0]);
  const newTotal = length(network.displayPartsForLine(repairedLine(yoko))[0]);
  const boundary = Number((1100 + newTotal - oldTotal).toFixed(1));
  const seeds = [[yoko.lineID, 0, 0, 25, .5], [yoko.lineID, 0, 25, boundary, 1.5], [yoko.lineID, 0, boundary, rows[0][5], .5]];
  const pinned = applyStationLanePins({ lines: [repairedLine(yoko)] }, rows, seeds);
  const expected = { ...e.baselineRows, partsByRegion: ids.flatMap(id => proposed[id]), byRegion: pinned };
  for (const [key, baseline] of Object.entries(e.baselineRows)) {
    const current = (input[key]?.jp || []).filter(owns);
    assert(equal(current, baseline) || equal(current, expected[key]), 'Unreviewed owner metadata: ' + key);
  }
  // Any additional owner metadata (including incoming follows) requires review.
  for (const [key, value] of Object.entries(input)) {
    if (Object.hasOwn(e.baselineRows, key) || key === 'hubReportByRegion') continue;
    assert(!owns(value), 'Unreviewed owner metadata: ' + key);
  }
  for (const [key, replacement] of Object.entries(expected)) {
    if (!input[key]?.jp) { assert.equal(replacement.length, 0); continue; }
    for (const id of ids) result[key].jp = replaceRows(result[key].jp, id, replacement.filter(row => row[0] === id));
  }
  const oldMembers = e.baselineHubMembers;
  const newMembers = oldMembers.map(row => ({ ...row, member: { ...row.member, from: 300, to: boundary, previousLane: 0 } }));
  const currentMembers = (input.hubReportByRegion?.jp || []).flatMap(hub =>
    (hub.members || []).filter(member => ids.includes(member.lineId)).map(member => ({ hubID: hub.hubId, member })));
  assert(equal(currentMembers, oldMembers) || equal(currentMembers, newMembers), 'Unreviewed owner hub metadata');
  if (result.hubReportByRegion?.jp) for (const hub of result.hubReportByRegion.jp) {
    if (!(hub.members || []).some(member => ids.includes(member.lineId))) continue;
    hub.members = hub.members.map(member => ids.includes(member.lineId)
      ? structuredClone(newMembers.find(row => row.hubID === hub.hubId && row.member.lineId === member.lineId).member) : member);
  }
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
  console.log(JSON.stringify({ mode: candidate ? 'candidate' : 'applied', lines: e.items.map(item => item.lineID), physicalTopologyChanged: false }));
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
