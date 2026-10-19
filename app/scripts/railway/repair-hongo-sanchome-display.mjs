#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative), 'utf8'));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const distance = (a, b) => {
  const radius = 6371000, radians = Math.PI / 180;
  const dLat = (b[1] - a[1]) * radians, dLon = (b[0] - a[0]) * radians;
  const q = Math.sin(dLat / 2) ** 2 + Math.cos(a[1] * radians) * Math.cos(b[1] * radians) * Math.sin(dLon / 2) ** 2;
  return 2 * radius * Math.asin(Math.sqrt(q));
};
const smooth = t => t * t * t * (10 + t * (-15 + 6 * t));

function sourceFile(evidence, source) {
  return path.join(REPO, evidence.sourceDirectory, `way-${source.id}-full.json`);
}

function metricDistance(a, b) {
  const latitude = (a[1] + b[1]) * Math.PI / 360;
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos(latitude), (b[1] - a[1]) * 111320);
}

function cumulativeMeasures(points) {
  const result = [0];
  for (let index = 1; index < points.length; index++)
    result.push(result.at(-1) + metricDistance(points[index - 1], points[index]));
  return result;
}

function pointAtMeasure(points, cumulative, measure) {
  if (measure <= 0) return points[0];
  if (measure >= cumulative.at(-1)) return points.at(-1);
  let index = 1;
  while (cumulative[index] < measure) index++;
  const ratio = (measure - cumulative[index - 1]) / (cumulative[index] - cumulative[index - 1]);
  return points[index - 1].map((value, axis) => value + ratio * (points[index][axis] - value));
}

function remapMeasure(before, after, measure) {
  const oldMeasures = cumulativeMeasures(before), newMeasures = cumulativeMeasures(after);
  if (measure <= 0) return 0;
  if (measure >= oldMeasures.at(-1) - 0.05) return Number(newMeasures.at(-1).toFixed(1));
  const point = pointAtMeasure(before, oldMeasures, measure), scale = Math.cos(point[1] * Math.PI / 180);
  let best;
  for (let index = 0; index < after.length - 1; index++) {
    const a = after[index], b = after[index + 1];
    const dx = (b[0] - a[0]) * scale, dy = b[1] - a[1];
    const denominator = dx * dx + dy * dy;
    const fraction = denominator ? Math.max(0, Math.min(1,
      ((point[0] - a[0]) * scale * dx + (point[1] - a[1]) * dy) / denominator)) : 0;
    const projected = [a[0] + fraction * (b[0] - a[0]), a[1] + fraction * (b[1] - a[1])];
    const gap = metricDistance(point, projected);
    if (!best || gap < best.gap) best = { gap, measure: newMeasures[index] + fraction * metricDistance(a, b) };
  }
  assert(best.gap < 0.01, 'Hongo measured reference entered the changed approach');
  return Number(best.measure.toFixed(1));
}

function remapMeasuredReferences(result, item, beforePart, afterPart) {
  const expected = item.measuredReferences;
  const byRegionIndex = result.byRegion.jp.findIndex(row => row[0] === item.lineID && row[1] === item.nativePart.partIndex);
  const remap = value => remapMeasure(beforePart, afterPart, value);
  const beforeByRegion = expected.byRegion, afterByRegion = structuredClone(beforeByRegion);
  afterByRegion[2] = remap(beforeByRegion[2]); afterByRegion[3] = remap(beforeByRegion[3]);
  const currentByRegion = result.byRegion.jp[byRegionIndex];
  assert(equal(currentByRegion, beforeByRegion) || equal(currentByRegion, afterByRegion), `${item.key} byRegion source changed`);
  result.byRegion.jp[byRegionIndex] = afterByRegion;
  const hubs = [];
  for (const reference of expected.hubs) {
    const hub = result.hubReportByRegion.jp.find(row => row.hubId === reference.hubId);
    const member = hub?.members.find(row => row.lineId === item.lineID && row.partIndex === item.nativePart.partIndex);
    assert(member, `${item.key} hub reference missing: ${reference.hubId}`);
    const afterFields = Object.fromEntries(Object.entries(reference.fields).map(([field, value]) => [field, remap(value)]));
    const currentFields = Object.fromEntries(Object.keys(reference.fields).map(field => [field, member[field]]));
    assert(equal(currentFields, reference.fields) || equal(currentFields, afterFields),
      `${item.key} ${reference.hubId} measured source changed`);
    Object.assign(member, afterFields);
    hubs.push({ hubId: reference.hubId, before: reference.fields, after: afterFields });
  }
  return { byRegion: { before: beforeByRegion.slice(2, 4), after: afterByRegion.slice(2, 4) }, hubs };
}

export function identifiedAnchors(evidence = read('scripts/railway/hongo-sanchome-display-evidence.json')) {
  assert.equal(evidence.format, 'jtm-hongo-sanchome-display-v1');
  const primary = new Map();
  for (const source of evidence.sources) {
    const bytes = fs.readFileSync(sourceFile(evidence, source));
    assert.equal(hash(bytes), source.sha256, `Retained Hongo source ${source.id} changed`);
    const document = JSON.parse(bytes), way = document.elements.find(row => row.type === 'way' && row.id === source.id);
    assert.deepEqual([way?.version, way?.timestamp], [source.version, source.timestamp], `Hongo way ${source.id} revision changed`);
    const nodes = new Map(document.elements.filter(row => row.type === 'node').map(row => [row.id, row]));
    assert(way.nodes.every(id => nodes.has(id)), `Hongo way ${source.id} node graph is incomplete`);
    primary.set(source.id, { way, nodes });
  }
  const anchors = {};
  for (const item of evidence.lines) {
    const coordinates = item.opposedStops.map(stop => {
      const source = primary.get(stop.wayID), node = source?.nodes.get(stop.nodeID);
      assert(source && source.way.nodes.includes(stop.nodeID), `${item.key} stop is not on its identified passenger way`);
      assert.deepEqual([node?.lon, node?.lat], stop.coordinate, `${item.key} stop coordinate changed`);
      assert.equal(node.tags?.public_transport, 'stop_position');
      assert.equal(node.tags?.railway, 'stop');
      assert.equal(node.tags?.name, evidence.stationName);
      assert.equal(node.tags?.ref, stop.ref);
      assert.equal(node.tags?.operator, item.sourceOperator);
      assert.equal(source.way.tags?.name, item.sourceName);
      assert.equal(source.way.tags?.operator, item.sourceOperator);
      assert.equal(source.way.tags?.railway, 'subway');
      assert.equal(source.way.tags?.tunnel, 'yes');
      assert.equal(source.way.tags?.layer, item.layer);
      assert.equal(source.way.tags?.oneway, 'yes');
      return stop.coordinate;
    });
    const centre = [(coordinates[0][0] + coordinates[1][0]) / 2, (coordinates[0][1] + coordinates[1][1]) / 2];
    assert.deepEqual(centre, item.displayAnchor, `${item.key} opposed-stop centre changed`);
    assert(distance(coordinates[0], coordinates[1]) < 11, `${item.key} stops no longer identify one platform group`);
    assert(distance(centre, evidence.aggregateSearchCoordinate) > 40, `${item.key} accidentally uses the aggregate search centroid`);
    anchors[item.key] = centre;
  }
  assert(distance(anchors.Marunouchi003546, anchors.Oedo003546) > 100,
    'Independent Hongo platform groups were collapsed');
  return anchors;
}

function withoutOwnedAliases(line, item) {
  const baseline = structuredClone(line);
  if (baseline.displayStationCoordinates) {
    delete baseline.displayStationCoordinates[item.stationID || '003546'];
    if (!Object.keys(baseline.displayStationCoordinates).length) delete baseline.displayStationCoordinates;
  }
  if (baseline.displayIntervalCoordinates) {
    for (const approach of item.approaches) delete baseline.displayIntervalCoordinates[approach.interval];
    if (!Object.keys(baseline.displayIntervalCoordinates).length) delete baseline.displayIntervalCoordinates;
  }
  return baseline;
}

function taperedApproach(points, approach, anchor) {
  assert.deepEqual(points[approach.boundaryIndex], approach.boundaryCoordinate, 'Hongo transition boundary changed');
  const outsideIndex = approach.endpoint === 'last' ? approach.boundaryIndex - 1 : approach.boundaryIndex + 1;
  assert.deepEqual(points[outsideIndex], approach.outsideCoordinate, 'Hongo outside support changed');
  const endpointIndex = approach.endpoint === 'last' ? points.length - 1 : 0;
  const oldAnchor = points[endpointIndex], delta = anchor.map((value, axis) => value - oldAnchor[axis]);
  const indices = approach.endpoint === 'last'
    ? Array.from({ length: endpointIndex - approach.boundaryIndex + 1 }, (_, i) => approach.boundaryIndex + i)
    : Array.from({ length: approach.boundaryIndex + 1 }, (_, i) => approach.boundaryIndex - i);
  const cumulative = [0];
  for (let i = 1; i < indices.length; i++) cumulative.push(cumulative.at(-1) + distance(points[indices[i - 1]], points[indices[i]]));
  assert(cumulative.at(-1) > 140 && cumulative.at(-1) < 260, 'Hongo taper escaped its reviewed approach');
  const result = structuredClone(points), total = cumulative.at(-1);
  indices.forEach((index, offset) => {
    const weight = smooth(cumulative[offset] / total);
    result[index] = points[index].map((value, axis) => value + delta[axis] * weight);
  });
  assert.deepEqual(result[approach.boundaryIndex], approach.boundaryCoordinate);
  assert.deepEqual(result[endpointIndex], anchor);
  return result;
}

export function repairPackage(input, evidence = read('scripts/railway/hongo-sanchome-display-evidence.json')) {
  const anchors = identifiedAnchors(evidence), pkg = structuredClone(input);
  for (const item of evidence.lines) {
    const index = pkg.lines.findIndex(line => line.id === item.lineID), current = pkg.lines[index];
    assert(current, `Missing Hongo line ${item.lineID}`);
    assert.equal(current.operator, item.operator);
    assert.equal(current.stations[item.stationIndex]?.[0], evidence.stationID);
    assert.deepEqual(current.stations[item.stationIndex], item.physicalStation, `${item.key} physicalStation changed`);
    assert.equal(hash(JSON.stringify(withoutOwnedAliases(current, { ...item, stationID: evidence.stationID }))), item.baselineLineSha256,
      `Unreviewed ${item.key} dependency changed`);
    assert.equal(current.stationCircleOwnerByCode?.[evidence.stationID], undefined,
      `${item.key} must retain its independent circle`);
    const baseline = withoutOwnedAliases(current, { ...item, stationID: evidence.stationID });
    const physical = network.decodeIntervals(baseline), repaired = structuredClone(baseline);
    repaired.displayStationCoordinates = { ...baseline.displayStationCoordinates, [evidence.stationID]: anchors[item.key] };
    repaired.displayIntervalCoordinates = { ...baseline.displayIntervalCoordinates };
    for (const approach of item.approaches)
      repaired.displayIntervalCoordinates[approach.interval] = taperedApproach(physical[approach.interval], approach, anchors[item.key]);
    pkg.lines[index] = repaired;
  }
  pkg.geometrySource ||= {};
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['hongo-sanchome-display'] = {
    reviewedAt: evidence.reviewedAt,
    stationID: evidence.stationID,
    lines: evidence.lines.map(item => ({ key: item.key, lineID: item.lineID, displayAnchor: item.displayAnchor,
      intervals: item.approaches.map(row => row.interval), bounds: item.approaches.map(row => row.boundaryCoordinate) })),
    script: 'app/scripts/railway/repair-hongo-sanchome-display.mjs',
    evidence: 'app/scripts/railway/hongo-sanchome-display-evidence.json',
    physicalTopologyChanged: false,
    policy: evidence.policy
  };
  return pkg;
}

function displayOverride(line) {
  const stations = line.stations.map(row => line.displayStationCoordinates?.[row[0]]
    ? [...row.slice(0, 2), ...line.displayStationCoordinates[row[0]], ...row.slice(4)] : row);
  const displayed = { ...line, stations, segments: line.segments.map((row, index) => line.displayIntervalCoordinates?.[index]
    ? [row[0], 0, line.displayIntervalCoordinates[index]] : row) };
  return { stations, intervals: network.decodeIntervals(displayed) };
}

export function repairParts(pkg, input, evidence = read('scripts/railway/hongo-sanchome-display-evidence.json')) {
  const result = structuredClone(input), summaries = [];
  const lineIDs = new Set(evidence.lines.map(item => item.lineID));
  assert(!(input.followsByRegion?.jp || []).some(row => lineIDs.has(row[0]) || lineIDs.has(row[4])),
    'Unreviewed Hongo follow measure requires review');
  assert(!(input.familyWindowsByRegion?.jp || []).some(row => lineIDs.has(row[0])),
    'Unreviewed Hongo family window requires review');
  const measureFields = ['from', 'to', 'alongsideFrom', 'alongsideTo'];
  for (const item of evidence.lines) {
    const expectedHubs = new Map(item.measuredReferences.hubs.map(row => [row.hubId, Object.keys(row.fields).sort()]));
    for (const hub of input.hubReportByRegion?.jp || []) for (const member of hub.members || []) {
      if (member.lineId !== item.lineID || member.partIndex !== item.nativePart.partIndex) continue;
      const fields = measureFields.filter(field => member[field] !== undefined).sort();
      if (fields.length) assert.deepEqual(fields, expectedHubs.get(hub.hubId),
        `Unreviewed ${item.key} hub measure requires review: ${hub.hubId}`);
    }
  }
  for (const item of evidence.lines) {
    const line = pkg.lines.find(row => row.id === item.lineID), parts = network.displayPartsForLine(line);
    assert.equal(parts.length, 1, `${item.key} display decomposition changed`);
    const baseline = withoutOwnedAliases(line, { ...item, stationID: evidence.stationID });
    assert.equal(hash(JSON.stringify(baseline)), item.baselineLineSha256, `${item.key} native baseline changed`);
    const beforeParts = network.displayPartsForLine(baseline);
    assert.equal(beforeParts.length, 1);
    const loopWinding = item.key === 'Oedo003546' ? { reversed: [] } : null;
    const rows = partRowsForLine(line, parts, displayOverride(line), loopWinding);
    assert.deepEqual(loopWinding?.reversed || [], [], `${item.key} loop winding changed`);
    assert.equal(rows.length, 1);
    assert(rows.every(row => !row[8]?.length), `${item.key} introduced withheld spans`);
    const cached = result.partsByRegion.jp.find(row => row[0] === item.lineID && row[1] === item.nativePart.partIndex);
    assert(hash(JSON.stringify(cached)) === item.nativePart.baselineRowSha256 || equal(cached, rows[0]),
      `Unreviewed ${item.key} native part changed`);
    assert.equal(parts[0].length, item.nativePart.vertexCount, `${item.key} vertex count changed`);
    assert.deepEqual(parts[0][item.nativePart.anchorIndex], item.displayAnchor, `${item.key} native anchor index changed`);
    result.partsByRegion.jp = result.partsByRegion.jp.map(row => row[0] === item.lineID && row[1] === item.nativePart.partIndex ? rows[0] : row);
    const measureRemap = remapMeasuredReferences(result, item, beforeParts[0], parts[0]);
    summaries.push({ key: item.key, partIndex: 0, anchorIndex: item.nativePart.anchorIndex,
      vertexCount: rows[0][4], beforeMetres: item.nativePart.totalMetres, afterMetres: rows[0][5], measureRemap });
  }
  Object.defineProperty(result, '__hongoSummary', { value: summaries, enumerable: false });
  return result;
}

export function buildCandidate(packageInput, lanesInput, evidence = read('scripts/railway/hongo-sanchome-display-evidence.json')) {
  const pkg = repairPackage(packageInput, evidence), lanes = repairParts(pkg, lanesInput, evidence);
  assert.deepEqual(repairParts(pkg, lanes, evidence), lanes, 'Hongo derivative replay is not idempotent');
  return { pkg, lanes, summary: lanes.__hongoSummary };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  assert(args.length === 0 || (args.length === 2 && args[0] === '--candidate-dir'),
    'Usage: node repair-hongo-sanchome-display.mjs [--candidate-dir /private/tmp/path]');
  const candidateDirectory = path.resolve(args[1] || '/private/tmp/jtm-hongo-sanchome-display-candidate');
  assert(candidateDirectory.startsWith('/private/tmp/'), 'Candidate output must stay under /private/tmp');
  const { pkg, lanes, summary } = buildCandidate(read('public/rail/jp-2025.json'), read('public/rail/display-lanes.json'));
  fs.mkdirSync(candidateDirectory, { recursive: true });
  const packagePath = path.join(candidateDirectory, 'jp-2025.json');
  const lanesPath = path.join(candidateDirectory, 'display-lanes.json');
  fs.writeFileSync(packagePath, JSON.stringify(pkg));
  fs.writeFileSync(lanesPath, JSON.stringify(lanes) + '\n');
  console.log(JSON.stringify({ mode: 'candidate-only', packagePath, lanesPath, lines: summary, physicalTopologyChanged: false }));
}
