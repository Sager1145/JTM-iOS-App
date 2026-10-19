#!/usr/bin/env node
// One proven source reversal; no shared grooming change. Default is read-only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const EVIDENCE = path.join(ROOT, 'scripts/railway/hakone-source-reversal-evidence.json');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
const readEvidence = () => JSON.parse(fs.readFileSync(EVIDENCE));
const distance = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
  (b[1] - a[1]) * 111320);
const length = points => points.slice(1).reduce((sum, point, i) => sum + distance(points[i], point), 0);

export function repairPackage(input, sources, evidence = readEvidence()) {
  assert.equal(evidence.format, 'jtm-hakone-source-reversal-candidate-v1');
  const pkg = structuredClone(input), line = pkg.lines.find(row => row.id === evidence.id);
  assert(line, 'source changed: Hakone line missing');
  assert.deepEqual(line.stations.slice(evidence.interval, evidence.interval + 2), evidence.stationRows,
    'source changed: Hakone station identity or anchor');
  assert(!line.displayStationCoordinates && !line.displayIntervalCoordinates && !line.displayBranchLeadIns,
    'source changed: Hakone display override requires review');
  for (const [index, feature] of Object.entries(evidence.rawRailFeatures))
    assert.deepEqual(sources.sections.features[index], feature, 'source changed: Hakone outgoing railway survey');
  for (const [index, feature] of Object.entries(evidence.rawStationFeatures))
    assert.deepEqual(sources.stations.features[index], feature, 'source changed: Hakone platform survey');
  const from = evidence.rawStationFeatures[8590], to = evidence.rawStationFeatures[8588];
  const points = [from.properties.display_point, from.geometry.coordinates[0]];
  for (const [index, reverse] of evidence.orderedRailChain) {
    const feature = evidence.rawRailFeatures[index];
    assert.equal(feature.properties.N02_004, '小田急箱根');
    assert.equal(feature.properties.N02_003, '鉄道線');
    assert.equal(feature.properties.N02_001, '12');
    const next = structuredClone(feature.geometry.coordinates);
    if (reverse) next.reverse();
    assert(same(points.at(-1), next[0]), 'source changed: Hakone exact raw seam');
    points.push(...next.slice(1));
  }
  assert(to.geometry.coordinates.some(point => same(points.at(-1), point)), 'source changed: Hakone destination platform');
  points.push(to.properties.display_point);
  assert.deepEqual(points, evidence.sourceInterval, 'source changed: pinned Hakone outgoing chain');
  assert.deepEqual(network.decodeIntervals(line)[evidence.interval], points, 'source changed: compiled Hakone outgoing chain');
  const tails = [...evidence.originalReversalTails, evidence.protectedExtent];
  assert(equal(line.reversalTails || [], evidence.originalReversalTails) || equal(line.reversalTails, tails),
    'source changed: Hakone reversal metadata');
  line.reversalTails = structuredClone(tails);
  return pkg;
}

export function repairParts(pkg, input, evidence = readEvidence()) {
  const result = structuredClone(input), line = pkg.lines.find(row => row.id === evidence.id);
  assert.deepEqual(line?.reversalTails, [...evidence.originalReversalTails, evidence.protectedExtent]);
  const oldLine = structuredClone(line);
  if (evidence.originalReversalTails.length) oldLine.reversalTails = evidence.originalReversalTails;
  else delete oldLine.reversalTails;
  const before = network.displayPartsForLine(oldLine), after = network.displayPartsForLine(line);
  assert.deepEqual(before.map(part => part.length), evidence.beforePartCounts, 'source changed: Hakone baseline display');
  assert.deepEqual(after.map(part => part.length), evidence.afterPartCounts, 'source changed: Hakone restored display');
  assert.deepEqual(before.slice(0, 2), after.slice(0, 2), 'source changed: unrelated Hakone parts');
  assert.deepEqual(after[2].filter(point => !same(point, evidence.protectedExtent)), before[2],
    'source changed: restoration must insert only the surveyed tip');
  const cached = input.partsByRegion.jp.filter(row => row[0] === evidence.id);
  const oldRows = partRowsForLine(oldLine, before, null, null), newRows = partRowsForLine(line, after, null, null);
  assert(equal(cached, oldRows) || equal(cached, newRows), 'source changed: Hakone cached parts');
  result.partsByRegion.jp = result.partsByRegion.jp.map(row => row[0] === evidence.id ? newRows[row[1]] : row);
  const oldWindows = evidence.dependencyBaseline.byRegion, newWindows = structuredClone(oldWindows);
  assert.equal(oldWindows[2][1], 2);
  assert.equal(oldWindows[2][2], 0);
  assert.equal(oldWindows[2][3], length(before[2]), 'source changed: lane must cover exact complete part');
  newWindows[2][3] = length(after[2]);
  const windows = input.byRegion.jp.filter(row => row[0] === evidence.id);
  assert(equal(windows, oldWindows) || equal(windows, newWindows), 'source changed: Hakone measured lane windows');
  result.byRegion.jp = result.byRegion.jp.map(row => row[0] === evidence.id ? newWindows[row[1]] : row);
  const follows = input.followsByRegion.jp.filter(row => row[0] === evidence.id || row[4] === evidence.id);
  assert.deepEqual(follows, evidence.dependencyBaseline.follows, 'source changed: Hakone follows');
  let prefix = 0;
  while (prefix < before[2].length && same(before[2][prefix], after[2][prefix])) prefix++;
  const prefixMetres = length(before[2].slice(0, prefix));
  for (const row of follows) for (const offset of [0, 4]) {
    if (row[offset] === evidence.id && row[offset + 1] === 2)
      assert(Math.min(row[offset + 2], row[offset + 3]) >= 0 &&
        Math.max(row[offset + 2], row[offset + 3]) <= prefixMetres,
      'source changed: follow crosses restored Hakone tip');
  }
  for (const key of ['familyWindowsByRegion', 'loopsByRegion', 'hubReportByRegion'])
    assert(!(input[key]?.jp || []).some(row => equal(row[0], evidence.id)), 'source changed: affected Hakone measured reference');
  assert(!(input.reversedLoopParts?.jp || []).some(row => row.startsWith(evidence.id + '#')),
    'source changed: affected Hakone reversed loop');
  const boundaries = input.chainBoundariesByRegion?.jp.filter(row => row[0] === evidence.id) || [];
  assert.deepEqual(boundaries, evidence.dependencyBaseline.chainBoundaries, 'source changed: Hakone boundary');
  for (const row of boundaries)
    assert(same(before[row[1]].at(-1), after[row[1]].at(-1)) && same(before[row[2]][0], after[row[2]][0]),
      'source changed: physical-fork endpoints');
  return result;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), apply = equal(args, ['--apply']);
  assert(!args.length || apply, 'Usage: node repair-hakone-source-reversal.mjs [--apply]');
  const paths = { package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json',
    sections: 'data/rail-sections.json', stations: 'data/stations.json',
    evidence: 'scripts/railway/hakone-source-reversal-evidence.json', network: 'public/rail-network.js',
    builder: 'scripts/railway/build-display-lanes.mjs', helper: 'scripts/railway/repair-three-reversal-extents.mjs',
    geo: 'scripts/railway/jp-manual-corrections/geo.mjs', ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const read = key => JSON.parse(snapshots[key].before), evidence = read('evidence');
  const pkg = repairPackage(read('package'), { sections: read('sections'), stations: read('stations') }, evidence);
  const lanes = repairParts(pkg, read('lanes'), evidence);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, read(key)])));
  if (apply) applyPreparedWrites([
    { ...snapshots.package, after: JSON.stringify(pkg) },
    { ...snapshots.lanes, after: JSON.stringify(lanes) + '\n' },
    ...Object.keys(DEPENDENCY_PATHS).map(key => ({ ...snapshots[key], after: JSON.stringify(dependencies[key], null, 2) + '\n' }))
  ], Object.values(snapshots));
  console.log(JSON.stringify({ mode: apply ? 'applied' : 'candidate-only', id: evidence.id,
    protectedExtent: evidence.protectedExtent, partCounts: evidence.afterPartCounts,
    measuredLaneWindows: lanes.byRegion.jp.filter(row => row[0] === evidence.id) }));
}
