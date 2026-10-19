#!/usr/bin/env node
// Scoped repair: restore N02's own eastern arc; do not round a false crossing turn.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';

export const LINE_ID = 'jp-西日本旅客鉄道-北陸線-p1';
export const DIRECTION_SOURCE = 'https://www.westjr.co.jp/company/info/issue/bsignal/26_vol_207/area/';
const FEATURE_INDEX = 9616;
const FEATURE_SHA = '565412f124ffee2b48e74756ba3aa2e6571e30ff41122ae852e18cdc2d8e1b33';
const digest = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const pretty = value => JSON.stringify(value, null, 2) + '\n';
export function measure(points) {
  return points.slice(1).reduce((total, point, i) => {
    const previous = points[i];
    return total + Math.hypot((point[0] - previous[0]) * 111320 *
      Math.cos((point[1] + previous[1]) / 2 * Math.PI / 180), (point[1] - previous[1]) * 111320);
  }, 0);
}

export function buildCandidate(input, sections) {
  assert.equal(input.id, LINE_ID);
  const appliedDirection = input.alignmentDirection === 'up' && input.alignmentSource === DIRECTION_SOURCE;
  assert(appliedDirection || (input.alignmentDirection === 'down' &&
    input.alignmentSource === 'https://ja.wikipedia.org/wiki/北陸本線'), 'Unreviewed direction metadata');
  assert.equal(input.stationOrderDirection, 'up');
  const frozen = structuredClone(input);
  delete frozen.displayIntervalCoordinates;
  frozen.alignmentDirection = 'down';
  frozen.alignmentSource = 'https://ja.wikipedia.org/wiki/北陸本線';
  assert.equal(digest(frozen), '39d25ac8ca1cb49e92398925302373a38758a84203936a555e3334fd5a91810f',
    'Reviewed owning physical line changed');
  assert.equal(input.segments.length, 1);
  assert.equal(input.segments[0][1], 0);
  const source = input.segments[0][2];
  assert.equal(source.length, 132);
  assert.deepEqual(source.slice(40, 43), [
    [136.08128, 35.61844], [136.08196, 35.61644], [136.08184, 35.61634],
  ], 'Crossing splice dependency changed');
  const feature = sections.features[FEATURE_INDEX];
  assert.deepEqual([feature.properties.N02_003, feature.properties.N02_004],
    ['北陸線', '西日本旅客鉄道']);
  assert.equal(digest(feature), FEATURE_SHA, 'Reviewed eastern arc source changed');
  assert.equal(feature.geometry.type, 'LineString');
  const arc = feature.geometry.coordinates;
  assert.deepEqual(arc.at(-1), source[41]);
  assert.deepEqual(source[0], input.stations[0].slice(2, 4));
  assert.deepEqual(source.at(-1), input.stations[1].slice(2, 4));
  // No shared northern vertex exists between the directional N02 sections.
  // Use the complete original own-direction section rather than invent a lateral
  // nearest-point splice. The existing station anchor remains fixed.
  const line = structuredClone(input);
  line.alignmentDirection = 'up';
  line.alignmentSource = DIRECTION_SOURCE;
  line.displayIntervalCoordinates = { 0: structuredClone([source[0], ...arc, ...source.slice(42)]) };
  if (input.displayIntervalCoordinates !== undefined)
    assert.deepEqual(input.displayIntervalCoordinates, line.displayIntervalCoordinates, 'Unreviewed display override');
  return { format: 'jtm-hokuriku-p1-loop-display-candidate-v1', status: 'candidate-only', line,
    evidence: {
      source: 'app/data/rail-sections.json', featureIndex: FEATURE_INDEX, featureSha256: FEATURE_SHA,
      sourceCRS: sections.crs, coordinateOperation: 'Use existing N02 coordinates without transformation, matching canonical ingestion.',
      replacedBaselineControlRange: [0, 41], retainedBaselineSuffixFrom: 42,
      candidatePointCount: line.displayIntervalCoordinates[0].length,
      physicalTopologyChanged: false, stationAnchorsChanged: false,
      directionEvidence: { url: DIRECTION_SOURCE, loopDirection: 'up', straightDirection: 'down',
        stationOrderDirection: 'up', statement: 'Operator identifies the loop as up and the crossing straight track toward Tsuruga as down.' },
      reason: 'Eastern directional arc crosses the straight railway; a shared survey crossing vertex is not a switch.',
      originalViews: [9, 10, 11, 12].map(n =>
        `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/hokuriku-p1-complete/unified-session/alignment/captures/000000/${String(n).padStart(6, '0')}`),
      pending: ['Review entire changed station-to-crossing prefix, including the fixed Tsuruga anchor connector.',
        'Native display parts, production lanes and Main rendering have not been rebuilt or accepted.',
        'Physical grade separation and passenger switching are not established by this display proposal.'],
    } };
}

// Only ownership of the repaired prefix is removed. The unchanged suffix keeps
// the same geographic follow/family boundaries on its new display ruler.
export function repairLanes(input, line) {
  const physical = line.segments[0][2], display = line.displayIntervalCoordinates[0];
  const delta = measure(display) - measure(physical), total = measure(display);
  const base = 'jp-西日本旅客鉄道-北陸線';
  const expected = {
    byRegion: [[LINE_ID, 0, 0, 9726.8, -0.5]],
    followsByRegion: [[LINE_ID, 0, 0, 3475, base, 0, 0, 3450],
      [LINE_ID, 0, 8350, 9726.821586632404, base, 0, 5250, 6629.699966332292]],
    familyWindowsByRegion: [[LINE_ID, 0, 0, 3175, 1, '西日本旅客鉄道:北陸線'],
      [LINE_ID, 0, 8650, 9726.8, 1, '西日本旅客鉄道:北陸線']],
    partsByRegion: [[LINE_ID, 0, 0, 0, 132, 9726.8, null, null, []]],
  };
  const updated = {
    byRegion: [[LINE_ID, 0, 0, Number(total.toFixed(1)), -0.5]],
    followsByRegion: [[LINE_ID, 0, 8350 + delta, total, base, 0, 5250, 6629.699966332292]],
    familyWindowsByRegion: [[LINE_ID, 0, 8650 + delta, 9726.8 + delta, 1, '西日本旅客鉄道:北陸線']],
    partsByRegion: partRowsForLine(line, network.displayPartsForLine(line)),
  };
  const result = structuredClone(input);
  for (const key of Object.keys(expected)) {
    const owns = row => row[0] === LINE_ID || row[4] === LINE_ID;
    const current = input[key].jp.filter(owns);
    assert(equal(current, expected[key]) || equal(current, updated[key]), `Unreviewed ${key} dependency`);
    const first = result[key].jp.findIndex(owns);
    assert(first >= 0, `Missing ${key} owner`);
    result[key].jp.splice(first, 0, ...structuredClone(updated[key]));
    // The inserted rows are followed by the original owner rows. Remove those
    // originals without shifting or rewriting any unrelated row.
    let inserted = updated[key].length;
    result[key].jp = result[key].jp.filter(row => !owns(row) || inserted-- > 0);
  }
  return { lanes: result, metadata: { displayDeltaMetres: delta, totalMetres: total,
    removedPrefixFollow: expected.followsByRegion[0], removedPrefixFamily: expected.familyWindowsByRegion[0],
    rebasedSuffixFollow: updated.followsByRegion[0], rebasedSuffixFamily: updated.familyWindowsByRegion[0] } };
}

export function repairPackage(pkg, sections) {
  const index = pkg.lines.findIndex(line => line.id === LINE_ID);
  assert(index >= 0, 'Missing owning line');
  const candidate = buildCandidate(pkg.lines[index], sections);
  const result = structuredClone(pkg);
  result.lines[index] = candidate.line;
  const base = result.lines.find(line => line.id === 'jp-西日本旅客鉄道-北陸線');
  assert(base, 'Missing paired base line');
  const pairs = base.alignmentPairs.filter(pair => pair.with === LINE_ID);
  const oldPair = { with: LINE_ID, from: '敦賀', to: '新疋田', direction: 'up', source: 'https://ja.wikipedia.org/wiki/北陸本線' };
  const newPair = { ...oldPair, direction: 'down', source: DIRECTION_SOURCE };
  assert(equal(pairs, [oldPair]) || equal(pairs, [newPair]), 'Unreviewed base pair direction');
  base.alignmentPairs = base.alignmentPairs.map(pair => pair.with === LINE_ID ? newPair : pair);
  const provenance = {
    reviewedAt: '2026-10-18', lineID: LINE_ID, intervalIndex: 0,
    script: 'app/scripts/railway/repair-hokuriku-p1-loop-display.mjs',
    source: { path: 'app/data/rail-sections.json', featureIndex: FEATURE_INDEX, featureSha256: FEATURE_SHA,
      operator: '西日本旅客鉄道', railway: '北陸線' },
    directionSource: DIRECTION_SOURCE,
    transformation: 'Replace the inherited straight-rail prefix with the existing own eastern loop arc; preserve the crossing and complete remaining loop.',
    physicalSegmentsChanged: false, stationAnchorsChanged: false,
    removedWrongPrefixFollow: [LINE_ID, 0, 0, 3475, 'jp-西日本旅客鉄道-北陸線', 0, 0, 3450],
    nativeReview: 'Full 34-view candidate geometry reviewed; retained southern-loop offsets and station platform caps remain outside acceptance.',
  };
  result.geometrySource.manualOverrides ??= {};
  const previous = result.geometrySource.manualOverrides['hokuriku-p1-loop-display'];
  assert(previous === undefined || equal(previous, provenance), 'Unreviewed repair provenance');
  result.geometrySource.manualOverrides['hokuriku-p1-loop-display'] = provenance;
  return { pkg: result, candidate };
}

export function repairDirectionSource(input) {
  const result = structuredClone(input);
  const family = result.families.find(row => row.baseLineID === 'jp-西日本旅客鉄道-北陸線');
  assert.equal(family.stationOrderDirection, 'up');
  const pair = family.pairs.find(row => row.lineID === LINE_ID);
  assert.deepEqual(pair.stationCodes, ['010186', '004256']);
  const before = ['down', 'up', 'https://ja.wikipedia.org/wiki/北陸本線'];
  const after = ['up', 'down', DIRECTION_SOURCE];
  const current = [pair.alignmentDirection, pair.mainAlignmentDirection, pair.alignmentSource];
  assert(equal(current, before) || equal(current, after), 'Unreviewed directional master');
  [pair.alignmentDirection, pair.mainAlignmentDirection, pair.alignmentSource] = after;
  return result;
}

function main(args) {
  const apply = equal(args, ['--apply']);
  assert(apply || (args.length === 2 && args[0] === '--candidate-root'),
    'Usage: node repair-hokuriku-p1-loop-display.mjs (--candidate-root /private/tmp/<directory> | --apply)');
  const out = apply ? null : path.resolve(args[1]);
  if (out) assert(out.startsWith('/private/tmp/'), 'Candidate output must be under /private/tmp');
  const paths = { package: 'public/rail/jp-2025.json', sections: 'data/rail-sections.json',
    lanes: 'public/rail/display-lanes.json', directions: 'scripts/railway/jp-directional-alignment-overrides.json',
    ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const read = key => JSON.parse(snapshots[key].before);
  const { pkg, candidate } = repairPackage(read('package'), read('sections'));
  const { lanes, metadata } = repairLanes(read('lanes'), candidate.line);
  candidate.evidence.productionMetadata = metadata;
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, read(key)])));
  const outputs = { package: JSON.stringify(pkg), lanes: JSON.stringify(lanes) + '\n',
    directions: pretty(repairDirectionSource(read('directions'))),
    ...Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, pretty(dependencies[key])])) };
  if (apply) {
    applyPreparedWrites(Object.entries(outputs).map(([key, after]) => ({ ...snapshots[key], after })),
      Object.values(snapshots));
  } else {
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, 'candidate.json'), JSON.stringify(candidate, null, 2) + '\n');
  for (const [key, contents] of Object.entries(outputs))
    fs.writeFileSync(path.join(out, path.basename(snapshots[key].path)), contents);
  fs.writeFileSync(path.join(out, 'candidate.geojson'), JSON.stringify({ type: 'FeatureCollection',
    features: [{ type: 'Feature', properties: { lineID: LINE_ID, intervalIndex: 0, status: 'candidate-only' },
      geometry: { type: 'LineString', coordinates: candidate.line.displayIntervalCoordinates[0] } }] }, null, 2) + '\n');
  }
  console.log(JSON.stringify({ output: out, status: apply ? 'applied' : candidate.status, pointCount: candidate.evidence.candidatePointCount,
    productionApplied: apply, ...metadata }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
