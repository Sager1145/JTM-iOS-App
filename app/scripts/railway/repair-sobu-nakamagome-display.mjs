#!/usr/bin/env node
// One own-passenger display splice; the established Sobu owner remaps its ruler.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { repairShinagawaLanes, SOBU } from './repair-shinagawa-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const EVIDENCE = 'scripts/railway/sobu-nakamagome-display-evidence.json';
const KEY = 'sobu-nakamagome-display';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));

function sourceSnapshot(e) {
  assert.deepEqual([e.source.wayID, e.source.wayVersion, e.source.routeID, e.source.routeVersion],
    [365183512, 18, 11664782, 39], 'Unreviewed Sobu source identity/version');
  assert.deepEqual(Object.keys(e.source.files).sort(), ['way-365183512-full.json', 'way-365183512-relations.json']);
  const files = Object.entries(e.source.files).map(([name, source]) => {
    const file = path.resolve(REPO, source.path);
    assert(file.startsWith(REPO + path.sep), 'Sobu source must be retained inside the repository');
    const before = fs.readFileSync(file);
    assert.equal(crypto.createHash('sha256').update(before).digest('hex'), source.sha256,
      'Reviewed Sobu passenger source changed: ' + name);
    return { name, path: file, before };
  });
  const load = name => JSON.parse(files.find(file => file.name === name).before);
  const full = load('way-365183512-full.json'), way = full.elements.find(row => row.type === 'way' && row.id === e.source.wayID);
  assert(way, 'Missing own Sobu passenger way');
  assert.deepEqual([way.id, way.version], [365183512, 18]);
  for (const [key, value] of Object.entries({ name: '東海道本線（品鶴線）', operator: '東日本旅客鉄道',
    railway: 'rail', 'railway:traffic_mode': 'passenger', usage: 'main', gauge: '1067' }))
    assert.equal(way.tags[key], value, 'Sobu passenger track identity changed: ' + key);
  assert.equal(way.tags.service, undefined, 'A siding cannot define the own passenger display');
  const nodes = new Map(full.elements.filter(row => row.type === 'node').map(row => [row.id, row]));
  assert(way.nodes.every(id => nodes.has(id) && Number.isInteger(nodes.get(id).version)), 'Versioned Sobu source nodes missing');
  const relations = load('way-365183512-relations.json').elements;
  const route = relations.find(row => row.type === 'relation' && row.id === e.source.routeID);
  assert(route, 'Own Yokosuka-Sobu route missing');
  assert.deepEqual([route.id, route.version, route.tags.name, route.tags.operator, route.tags.route],
    [11664782, 39, '横須賀・総武快速線 (千葉 → 大船)', '東日本旅客鉄道', 'train']);
  assert(route.members.some(member => member.type === 'way' && member.ref === way.id), 'Own passenger route does not include the source way');
  return { files, way, coordinates: way.nodes.map(id => [nodes.get(id).lon, nodes.get(id).lat]) };
}

function repairedLine(e) {
  assert.equal(e.format, 'jtm-sobu-nakamagome-display-v1');
  assert.deepEqual([e.lineID, e.intervalIndex, e.stationIDs, e.fragment.fromDisplayVertexIndex, e.fragment.toDisplayVertexIndex],
    [SOBU, 3, ['004235', '004301'], 13, 32]);
  const source = sourceSnapshot(e), line = structuredClone(e.baselineLine);
  assert.equal(line.id, SOBU);
  assert.deepEqual(line.stations.slice(3, 5).map(row => row[0]), e.stationIDs);
  const original = network.decodeIntervals(line)[3], f = e.fragment;
  assert.equal(line.displayIntervalCoordinates?.[3], undefined, 'Baseline already has an unreviewed Nakamagome display stage');
  assert.deepEqual(e.rawSource.feature.properties,
    { N02_001: '11', N02_002: '2', N02_003: '東海道線', N02_004: '東日本旅客鉄道' });
  assert.equal(e.rawSource.featureIndex, 16210, 'Unreviewed Nakamagome raw source identity');
  assert.deepEqual(original.slice(13, 33), e.rawSource.feature.geometry.coordinates.slice(10, 30),
    'Nakamagome raw source support window changed');
  const start = projectPointOntoPolyline(original[13], source.coordinates);
  const end = projectPointOntoPolyline(original[32], source.coordinates);
  for (const [actual, boundary, raw] of [[start, f.startBoundary, original[13]], [end, f.endBoundary, original[32]]]) {
    const recorded = boundary.witness;
    assert.deepEqual(boundary.rawCoordinate, raw, 'Sobu retained boundary changed');
    assert.deepEqual(boundary.sourceSegmentNodeIDs, source.way.nodes.slice(actual.insertIndex, actual.insertIndex + 2),
      'Sobu boundary node identity changed');
    assert.equal(actual.insertIndex, recorded.insertIndex, 'Sobu boundary projection edge changed');
    assert(Math.abs(actual.distanceM - recorded.distanceM) < 1e-9, 'Sobu boundary residual changed');
    assert.deepEqual(actual.point, recorded.point, 'Sobu boundary projection changed');
  }
  assert(start.insertIndex < end.insertIndex, 'Sobu source order changed');
  const nodeIDs = source.way.nodes.slice(start.insertIndex + 1, end.insertIndex + 1);
  assert.deepEqual(nodeIDs, f.nodeIDs, 'Sobu source node slice changed');
  const fragment = [original[13], ...source.coordinates.slice(start.insertIndex + 1, end.insertIndex + 1), original[32]];
  assert.deepEqual(fragment, f.coordinates, 'Frozen Sobu own passenger fragment changed');
  // The existing Tokyo replay owns override keys0/1/2 and preserves this key3
  // (repair-tokyo-platform-approaches.py:81-114). No extra replay hook or
  // second coordinate generator is needed for this independent local stage.
  line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates,
    3: [...original.slice(0, 13), ...fragment, ...original.slice(33)] };
  return line;
}

export function repairPackage(input, e = read(EVIDENCE)) {
  const proposed = repairedLine(e), indices = input.lines.flatMap((line, index) => line.id === SOBU ? [index] : []);
  assert.equal(indices.length, 1, 'Sobu own line identity changed');
  const current = input.lines[indices[0]];
  assert(equal(current, e.baselineLine) || equal(current, proposed), 'Sobu own physical/display baseline changed');
  assert.deepEqual(input.geometrySource?.manualOverrides?.['shinagawa-normal-passenger-pair'], e.baselinePassengerPairReview,
    'Retained Shinagawa passenger review changed');
  assert.match(input.geometrySource?.license || '', /OpenStreetMap.*ODbL/i, 'Existing OSM attribution required');
  const pkg = structuredClone(input);
  pkg.lines[indices[0]] = proposed;
  const provenance = { reviewedAt: e.reviewedAt, status: e.status, lineID: SOBU, intervalIndex: 3,
    stationIDs: e.stationIDs, source: e.source, rawSourceFeatureIndex: e.rawSource.featureIndex,
    boundaries: [e.fragment.startBoundary, e.fragment.endBoundary], policy: e.policy,
    script: 'app/scripts/railway/repair-sobu-nakamagome-display.mjs', evidence: 'app/' + EVIDENCE,
    research: e.research, physicalTopologyChanged: false };
  const previous = pkg.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'Sobu repair provenance changed');
  pkg.geometrySource.manualOverrides[KEY] = provenance;
  return pkg;
}

function references(input) {
  return { rows: Object.fromEntries(['partsByRegion', 'byRegion', 'followsByRegion', 'familyWindowsByRegion'].map(key =>
    [key, (input[key]?.jp || []).filter(row => row[0] === SOBU || key === 'followsByRegion' && row[4] === SOBU)])),
  hubs: (input.hubReportByRegion?.jp || []).flatMap(hub => (hub.members || []).filter(member => member.lineId === SOBU)
    .map(member => ({ hubID: hub.hubId, member }))),
  other: Object.fromEntries(['loopsByRegion', 'reversedLoopParts', 'chainBoundariesByRegion', 'strokeExcludedByRegion', 'releasedIntervalsByRegion']
    .map(key => [key, (input[key]?.jp || []).filter(row => JSON.stringify(row).includes(SOBU))])),
  identity: Object.fromEntries(['colorByRegion', 'renderGroupByRegion'].map(key => [key, input[key]?.jp?.[SOBU]])) };
}

function baselineLanes(e) {
  return { ...Object.fromEntries(Object.entries(e.baselineRows).map(([key, rows]) => [key, { jp: structuredClone(rows) }])),
    hubReportByRegion: { jp: e.baselineHubMembers.map(({ hubID, member }) => ({ hubId: hubID, members: [structuredClone(member)] })) },
    ...Object.fromEntries(Object.entries(e.baselineIdentityMappings).map(([key, value]) => [key, { jp: { [SOBU]: structuredClone(value) } }])),
    ...Object.fromEntries(Object.entries(e.baselineOtherReferences).map(([key, rows]) => [key, { jp: structuredClone(rows) }])) };
}

export function repairParts(pkg, input, e = read(EVIDENCE)) {
  const line = pkg.lines.find(row => row.id === SOBU);
  assert(equal(line, repairedLine(e)), 'Sobu package display stage missing');
  const before = { lines: [e.baselineLine], geometrySource: { manualOverrides: {
    'shinagawa-normal-passenger-pair': e.baselinePassengerPairReview } } };
  const after = { ...before, lines: [line] };
  const baseline = baselineLanes(e), expected = repairShinagawaLanes(baseline, before, after);
  const currentRefs = references(input), expectedRefs = references(expected);
  assert(equal(currentRefs, references(baseline)) || equal(currentRefs, expectedRefs), 'Unreviewed Sobu measured reference changed');
  if (equal(currentRefs, expectedRefs)) return structuredClone(input);
  const result = repairShinagawaLanes(input, before, after);
  assert.deepEqual(references(result), expectedRefs, 'Sobu ruler repair did not preserve the scoped references');
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
  const sourceFiles = sourceSnapshot(e).files;
  const pkg = repairPackage(load('package'), e), lanes = repairParts(pkg, load('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg, Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  const outputs = { package: JSON.stringify(pkg), lanes: JSON.stringify(lanes) + '\n',
    ...Object.fromEntries(Object.entries(dependencies).map(([key, value]) => [key, JSON.stringify(value, null, 2) + '\n'])) };
  if (candidate) {
    fs.mkdirSync(candidate, { recursive: true });
    for (const [key, after] of Object.entries(outputs)) fs.writeFileSync(path.join(candidate, path.basename(snapshots[key].path)), after);
  } else {
    applyPreparedWrites(Object.entries(outputs).filter(([key, after]) => after !== snapshots[key].before)
      .map(([key, after]) => ({ ...snapshots[key], after })), [...Object.values(snapshots), ...sourceFiles]);
  }
  console.log(JSON.stringify({ mode: candidate ? 'candidate' : 'applied', lineID: SOBU, intervalIndex: 3,
    sourceWay: e.source.wayID, sourceVersion: e.source.wayVersion, physicalTopologyChanged: false }));
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
