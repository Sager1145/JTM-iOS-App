#!/usr/bin/env node
// Scoped candidate: two true reversals and one separate paired-platform repair.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { encodeIntervals } from './jp-manual-corrections/geo.mjs';
import { partRowsForLine } from './build-display-lanes.mjs';

const network = createRequire(import.meta.url)('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const EVIDENCE = path.join(ROOT, 'scripts/railway/three-reversal-extents-evidence.json');
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const pretty = value => JSON.stringify(value, null, 2) + '\n';
const hash = value => createHash('sha256').update(value).digest('hex');
export const DEPENDENCY_PATHS = {
  englishSource: 'data/station-english-verified-jp-east.json',
  kanaSource: 'data/station-name-sources/jp-kana-evidence.json',
  english: 'data/station-english.json',
  coverage: 'data/station-names-coverage.json'
};
const readEvidence = () => JSON.parse(fs.readFileSync(EVIDENCE));
const readSources = () => ({
  sections: JSON.parse(fs.readFileSync(path.join(ROOT, 'data/rail-sections.json'))),
  stations: JSON.parse(fs.readFileSync(path.join(ROOT, 'data/stations.json')))
});

function validateRawExtent(item, sections) {
  for (const row of item.rawExtentEvidence.features) {
    const feature = sections.features[row.featureIndex];
    assert(feature?.geometry.type === 'LineString', 'source changed: raw railway geometry');
    assert.deepEqual(feature.properties, row.properties, 'source changed: raw railway identity');
    const points = feature.geometry.coordinates;
    assert.deepEqual(points.slice(Math.max(0, row.vertexIndex - 3), row.vertexIndex + 4), row.extentWindow,
      'source changed: raw reversal extent');
    assert.deepEqual([points[0], points.at(-1)], [row.first, row.last], 'source changed: raw survey seams');
    assert.deepEqual(points[row.vertexIndex], item.protectedExtent, 'source changed: exact raw extent');
  }
}

function validateLine(line, item) {
  assert(line, 'source changed: selected line missing');
  assert.deepEqual(line.stations.slice(item.stationStart, item.stationStart + item.stationRows.length),
    item.stationRows, 'source changed: station identities or anchors');
  assert(!line.displayStationCoordinates && !line.displayIntervalCoordinates && !line.displayBranchLeadIns,
    'source changed: display override requires review');
  const intervals = network.decodeIntervals(line), points = intervals[item.interval];
  assert.equal(points.length, item.sourceIntervalVertexCount, 'source changed: interval length');
  assert.deepEqual(points.slice(0, item.sourcePrefix.length), item.sourcePrefix, 'source changed: reversal prefix');
  assert.deepEqual(points.slice(-item.sourceSuffix.length), item.sourceSuffix, 'source changed: interval suffix');
  if (item.incomingTail) assert.deepEqual(intervals[item.interval - 1].slice(-item.incomingTail.length),
    item.incomingTail, 'source changed: incoming station spur');
}

function validateOrderedOutgoing(line, item, sources) {
  const proof = item.rawOrderedOutgoingEvidence;
  if (!proof) return;
  for (const [index, feature] of Object.entries(proof.railFeatures))
    assert.deepEqual(sources.sections.features[index], feature, 'source changed: ordered outgoing railway survey');
  for (const [index, feature] of Object.entries(proof.stationFeatures))
    assert.deepEqual(sources.stations.features[index], feature, 'source changed: ordered outgoing platform survey');
  const station = code => Object.values(proof.stationFeatures).find(feature => feature.properties.n02_station_code === code);
  const from = station(proof.fromStationCode), to = station(proof.toStationCode);
  assert.equal(line.stations[item.interval][0], proof.fromStationCode, 'source changed: ordered outgoing origin');
  assert.equal(line.stations[item.interval + 1][0], proof.toStationCode, 'source changed: ordered outgoing destination');
  const points = [from.properties.display_point, from.geometry.coordinates.at(-1)];
  for (const [index, reverse] of proof.orderedRailChain) {
    const feature = proof.railFeatures[index];
    assert.equal(feature.properties.N02_001, '11', 'source changed: ordered outgoing passenger railway');
    assert.equal(feature.properties.N02_004, '九州旅客鉄道', 'source changed: ordered outgoing operator');
    const next = structuredClone(feature.geometry.coordinates);
    if (reverse) next.reverse();
    assert(same(points.at(-1), next[0]), 'source changed: ordered outgoing exact seam');
    points.push(...next.slice(1));
  }
  assert(to.geometry.coordinates.some(point => same(point, points.at(-1))), 'source changed: ordered outgoing destination platform');
  points.push(to.properties.display_point);
  assert.deepEqual(network.decodeIntervals(line)[item.interval], points,
    'source changed: ordered outgoing station interval');
}

function repairedPairedLine(item, sources) {
  for (const [index, feature] of Object.entries(item.rawRailFeatures))
    assert.deepEqual(sources.sections.features[index], feature, 'source changed: paired alignment survey');
  for (const [index, feature] of Object.entries(item.rawStationFeatures))
    assert.deepEqual(sources.stations.features[index], feature, 'source changed: platform survey');
  const start = sources.stations.features[item.startStationFeature];
  const end = sources.stations.features[item.endStationFeature];
  assert.deepEqual(start.properties.display_point, item.originalLine.stations[0].slice(2, 4),
    'source changed: Nishiyashiki anchor');
  assert.deepEqual(end.properties.display_point, item.newStationAnchor, 'source changed: Tateishi south anchor');
  assert.equal(end.properties.n02_station_code, item.originalLine.stations[1][0], 'source changed: platform code');
  const points = [structuredClone(start.properties.display_point), structuredClone(start.geometry.coordinates.at(-1))];
  for (const index of item.railChain) {
    const feature = sources.sections.features[index];
    assert.equal(feature.properties.N02_003, '日豊線', 'source changed: paired passenger line');
    assert.equal(feature.properties.N02_004, '九州旅客鉄道', 'source changed: paired passenger operator');
    const next = feature.geometry.coordinates;
    assert(same(points.at(-1), next[0]), 'source changed: paired survey is disconnected');
    points.push(...structuredClone(next.slice(1)));
  }
  assert(same(points.at(-1), end.geometry.coordinates[0]), 'source changed: south platform seam');
  assert.deepEqual(points, item.originalLine.segments[0][2].slice(0, points.length),
    'source changed: preserved paired source prefix');
  // This is the existing N02 display_point, the midpoint on its own straight
  // south-platform survey. No geometry is routed through the north platform.
  points.push(structuredClone(end.properties.display_point));
  const line = structuredClone(item.originalLine);
  line.stations[1].splice(2, 2, ...item.newStationAnchor);
  line.segments = encodeIntervals([points]);
  return line;
}

export function repairPackage(input, evidence = readEvidence(), sources = readSources()) {
  assert.equal(evidence.format, 'jtm-three-reversal-extents-candidate-v1');
  const pkg = structuredClone(input);
  for (const item of evidence.items) {
    const index = pkg.lines.findIndex(line => line.id === item.lineId), line = pkg.lines[index];
    assert(line, 'source changed: selected line missing');
    validateRawExtent(item, sources.sections);
    if (item.repairPlatformBinding) {
      const proposed = repairedPairedLine(item, sources);
      assert(equal(line, item.originalLine) || equal(line, proposed), 'source changed: paired source line');
      pkg.lines[index] = proposed;
    } else if (item.protect) {
      validateLine(line, item);
      validateOrderedOutgoing(line, item, sources);
      const tails = [...item.originalReversalTails, item.protectedExtent];
      assert(equal(line.reversalTails || [], item.originalReversalTails) || equal(line.reversalTails, tails),
        'source changed: reversal protection');
      line.reversalTails = structuredClone(tails);
    }
  }
  return pkg;
}

function distance(a, b) {
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
    (b[1] - a[1]) * 111320);
}

function unchangedSpan(before, after, from, to) {
  if (equal(before, after)) return true;
  let prefix = 0;
  while (prefix < Math.min(before.length, after.length) && same(before[prefix], after[prefix])) prefix++;
  let prefixMetres = 0;
  for (let i = 1; i < prefix; i++) prefixMetres += distance(before[i - 1], before[i]);
  return Math.min(from, to) >= 0 && Math.max(from, to) <= prefixMetres;
}

export function repairParts(pkg, input, evidence = readEvidence()) {
  const result = structuredClone(input), paired = evidence.items.find(item => item.repairPlatformBinding);
  const changed = new Map();
  for (const item of evidence.items) {
    const line = pkg.lines.find(row => row.id === item.lineId);
    assert(line, 'source changed: repaired line missing');
    const oldLine = item.repairPlatformBinding ? item.originalLine : structuredClone(line);
    if (item.protect) {
      assert.deepEqual(line.reversalTails, [...item.originalReversalTails, item.protectedExtent]);
      if (item.originalReversalTails.length) oldLine.reversalTails = item.originalReversalTails;
      else delete oldLine.reversalTails;
    }
    const before = network.displayPartsForLine(oldLine), after = network.displayPartsForLine(line);
    assert.deepEqual(before.map(part => part.length), item.beforePartCounts, 'source changed: baseline display parts');
    if (item.protect) assert.deepEqual(after.map(part => part.length), item.afterPartCounts, 'source changed: protected parts');
    assert.equal(before.length, after.length, 'source changed: part indexing requires review');
    changed.set(item.lineId, { before, after });
    const cached = input.partsByRegion.jp.filter(row => row[0] === item.lineId);
    if (!cached.length) {
      assert((input.strokeExcludedByRegion.jp || []).some(row => row[0] === item.lineId && row[1] === 'partial_service_suspended'),
        'source changed: missing native parts');
      continue;
    }
    const oldRows = partRowsForLine(oldLine, before, null, null), rows = partRowsForLine(line, after, null, null);
    assert(equal(cached, oldRows) || equal(cached, rows), 'source changed: cached native parts');
    assert(rows.every(row => !row[8]?.length), 'affected withheld measures require review');
    result.partsByRegion.jp = result.partsByRegion.jp.map(row => row[0] === item.lineId ? rows[row[1]] : row);
  }
  for (const key of ['byRegion', 'familyWindowsByRegion']) {
    for (const row of input[key]?.jp || []) {
      const parts = changed.get(row[0]);
      if (parts) assert(unchangedSpan(parts.before[row[1]], parts.after[row[1]], row[2], row[3]),
        'affected measured span requires review');
    }
  }
  const relevantPairedFollows = input.followsByRegion.jp.filter(row => row[0] === paired.lineId || row[4] === paired.lineId);
  assert(equal(relevantPairedFollows, [paired.preservedInitialFollow, paired.obsoleteTerminalFollow]) ||
    equal(relevantPairedFollows, [paired.preservedInitialFollow]), 'affected paired follows require review');
  assert.deepEqual(input.familyWindowsByRegion.jp.filter(row => row[0] === paired.lineId),
    [paired.preservedFamilyWindow], 'affected paired family window requires review');
  result.followsByRegion.jp = result.followsByRegion.jp.filter(row => !equal(row, paired.obsoleteTerminalFollow));
  for (const row of result.followsByRegion.jp) {
    for (const offset of [0, 4]) {
      const parts = changed.get(row[offset]);
      if (parts) assert(unchangedSpan(parts.before[row[offset + 1]], parts.after[row[offset + 1]], row[offset + 2], row[offset + 3]),
        'affected follow measure requires review');
    }
  }
  // Existing physical-fork boundaries carry part indices, not metre offsets.
  // Their endpoint identities must survive even when the outgoing extent grows.
  for (const row of input.chainBoundariesByRegion?.jp || []) {
    const parts = changed.get(row[0]);
    if (parts) assert(same(parts.before[row[1]].at(-1), parts.after[row[1]].at(-1)) &&
      same(parts.before[row[2]][0], parts.after[row[2]][0]), 'affected physical-fork boundary requires review');
  }
  return result;
}

// Station names and canonical memberships do not change. Refresh only the
// established input references, in their existing dependency order.
export function refreshDependencyReferences(pkg, input) {
  const result = structuredClone(input), packagePath = 'public/rail/jp-2025.json';
  const packageHash = hash(JSON.stringify(pkg));
  const update = (key, reference, value) => {
    assert(result[key]?.inputSha256, 'source changed: dependency references missing');
    if (Object.hasOwn(result[key].inputSha256, reference)) result[key].inputSha256[reference] = value;
  };
  update('englishSource', packagePath, packageHash);
  const sourceHash = hash(pretty(result.englishSource));
  update('kanaSource', DEPENDENCY_PATHS.englishSource, sourceHash);
  update('kanaSource', packagePath, packageHash);
  update('english', packagePath, packageHash);
  update('english', DEPENDENCY_PATHS.englishSource, sourceHash);
  update('coverage', packagePath, packageHash);
  update('coverage', DEPENDENCY_PATHS.kanaSource, hash(pretty(result.kanaSource)));
  update('coverage', DEPENDENCY_PATHS.english, hash(pretty(result.english)));
  return result;
}

export function applyPreparedWrites(writes, inputs) {
  const sameSnapshot = (left, right) => Buffer.isBuffer(left) && Buffer.isBuffer(right)
    ? left.equals(right) : typeof left === typeof right && left === right;
  for (const input of inputs) {
    const current = Buffer.isBuffer(input.before)
      ? fs.readFileSync(input.path) : fs.readFileSync(input.path, 'utf8');
    assert(sameSnapshot(current, input.before),
      'three-repair input changed before apply: ' + input.path);
  }
  for (const write of writes)
    assert(inputs.some(input => input.path === write.path && sameSnapshot(input.before, write.before)),
      'three-repair destination is missing its exact input snapshot');
  for (const write of writes)
    if (!sameSnapshot(write.before, write.after)) fs.writeFileSync(write.path, write.after);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  assert(!args.length || equal(args, ['--apply']), 'Usage: node repair-three-reversal-extents.mjs [--apply]');
  const paths = { package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json',
    sections: 'data/rail-sections.json', stations: 'data/stations.json',
    evidence: 'scripts/railway/three-reversal-extents-evidence.json',
    network: 'public/rail-network.js', geo: 'scripts/railway/jp-manual-corrections/geo.mjs',
    partsBuilder: 'scripts/railway/build-display-lanes.mjs', ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative);
    return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const read = key => JSON.parse(snapshots[key].before);
  const evidence = read('evidence'), pkg = repairPackage(read('package'), evidence,
    { sections: read('sections'), stations: read('stations') });
  const lanes = repairParts(pkg, read('lanes'), evidence);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, read(key)])));
  if (args[0] === '--apply') {
    const writes = [
      { ...snapshots.package, after: JSON.stringify(pkg) },
      { ...snapshots.lanes, after: JSON.stringify(lanes) + '\n' },
      ...Object.keys(DEPENDENCY_PATHS).map(key => ({ ...snapshots[key], after: pretty(dependencies[key]) }))
    ];
    applyPreparedWrites(writes, Object.values(snapshots));
  }
  console.log(JSON.stringify({ mode: args[0] === '--apply' ? 'applied' : 'candidate-only',
    lines: evidence.items.map(item => ({ id: item.lineId, kind: item.protect ? 'exact source reversal protection' : 'surveyed south platform binding',
      partCounts: network.displayPartsForLine(pkg.lines.find(line => line.id === item.lineId)).map(part => part.length) })),
    removedFollow: evidence.items.find(item => item.repairPlatformBinding).obsoleteTerminalFollow,
    refreshedDependencyPaths: Object.values(DEPENDENCY_PATHS) }));
}
