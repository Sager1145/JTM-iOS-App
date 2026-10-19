#!/usr/bin/env node
// Candidate-only owner for the Toei Mita representative display centreline.
// It never writes production resources; the CLI is restricted to /private/tmp.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';

export const LINE = 'jp-東京都-6号線三田線';
const STAGE = 'mita-osm-display-candidate';
const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.resolve(APP, '..');
const require = createRequire(import.meta.url);
const network = require('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const hash = value => crypto.createHash('sha256').update(typeof value === 'string' || Buffer.isBuffer(value) ? value : JSON.stringify(value)).digest('hex');
const read = relative => JSON.parse(fs.readFileSync(path.resolve(APP, relative)));
const readRepo = relative => JSON.parse(fs.readFileSync(path.resolve(REPO, relative)));
const evidenceDefault = () => read('scripts/railway/mita-display-evidence.json');
const rawDefault = evidence => readRepo(evidence.source.rawPath);
const candidateDefault = evidence => readRepo(evidence.source.candidatePath);
const coordEqual = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];

function relationStops(raw, relation) {
  const nodes = new Map(raw.elements.filter(row => row.type === 'node').map(row => [row.id, row]));
  return relation.members.filter(row => row.type === 'node' && row.role?.startsWith('stop')).map(row => {
    const node = nodes.get(row.ref);
    assert(node, `Mita source changed: stop node ${row.ref} missing`);
    return { id: row.ref, name: node.tags?.name, coordinate: [node.lon, node.lat] };
  });
}

function validateRelation(raw, expected) {
  const relation = raw.elements.find(row => row.type === 'relation' && row.id === expected.id);
  assert(relation, `Mita source changed: relation ${expected.id} missing`);
  const tags = relation.tags || {};
  assert(tags.type === 'route' && tags.route === 'subway' && tags.ref === 'I' && tags.official_ref === '6',
    `Mita source changed: relation ${expected.id} passenger route tags`);
  assert(tags.operator === '東京都交通局' && tags.network === '都営地下鉄',
    `Mita source changed: relation ${expected.id} wrong company/operator`);
  assert(tags['public_transport:version'] === '2' && tags.from === expected.tags.from && tags.to === expected.tags.to,
    `Mita source changed: relation ${expected.id} direction tags`);
  const stops = relationStops(raw, relation);
  assert.deepEqual(stops.map(row => row.id), expected.stopNodeIds,
    `Mita source changed: relation ${expected.id} stop order`);
  const wayIds = relation.members.filter(row => row.type === 'way' && !row.role).map(row => row.ref);
  assert.deepEqual(wayIds, expected.roleEmptyWayIds,
    `Mita source changed: relation ${expected.id} passenger way order`);
  return { relation, stops, wayIds };
}

/** Validate and return the retained paired-track display candidate. */
export function buildCandidate(evidence = evidenceDefault(), raw = rawDefault(evidence), candidate = candidateDefault(evidence)) {
  assert.equal(evidence.format, 'jtm-mita-display-evidence-v1');
  assert.equal(evidence.lineID, LINE);
  assert.equal(candidate.format, 'jtm-osm-display-candidate-v1');
  assert.equal(candidate.lineId, LINE);
  assert.equal(raw.osm3s?.timestamp_osm_base, evidence.source.osmBaseTimestamp,
    'Mita raw source changed: OSM base timestamp');

  const relations = evidence.source.relations.map(expected => validateRelation(raw, expected));
  const ways = new Map(raw.elements.filter(row => row.type === 'way').map(row => [row.id, row]));
  for (const { wayIds } of relations) for (const id of wayIds) {
    const way = ways.get(id);
    assert(way, `Mita source changed: passenger way ${id} missing`);
    assert(way.tags?.railway === 'subway', `Mita source changed: way ${id} is not subway passenger track`);
    assert(!way.tags?.service, `Mita source changed: yard/service way ${id} entered passenger chain`);
    assert(String(way.tags?.operator || '').includes('東京都交通局'),
      `Mita source changed: way ${id} wrong company/operator`);
  }

  const tail = ways.get(evidence.source.excludedPostTerminalWayId);
  assert(tail && tail.nodes[0] === evidence.source.relations[0].stopNodeIds.at(-1),
    'Mita source changed: post-terminal tail identity');
  assert(candidate.sourceChains.find(row => row.relationId === 443286)?.excludedWayIds?.includes(tail.id),
    'Mita candidate changed: post-terminal tail exclusion missing');
  assert(!candidate.intervals.some(interval => Object.values(interval.sourceTracks).some(source => source.wayIds.includes(tail.id))),
    'Mita candidate changed: post-terminal tail entered an interval');

  assert.equal(candidate.stationCount, 27);
  assert.equal(candidate.intervalCount, 26);
  assert.equal(candidate.stations.length, 27);
  assert.equal(candidate.intervals.length, 26);
  assert(candidate.validation?.all27StopPairsFound && candidate.validation?.all26IntervalsProduced
    && candidate.validation?.sourceWayJoinsContinuous && candidate.validation?.opposingStopMeasuresStrictlyMonotone
    && candidate.validation?.candidateIntervalSeamsContinuous && candidate.validation?.simplificationWithinHalfMetre
    && candidate.validation?.oppositeDirectionContinuityErrors?.length === 0,
  'Mita candidate changed: continuity or pairing validation');

  const expectedNames = evidence.baseline.owningLine.stationNames;
  assert.deepEqual(candidate.stations.map(row => row.name), expectedNames, 'Mita candidate changed: station order');
  assert.deepEqual(candidate.stations.map(row => row.stationCode), evidence.baseline.owningLine.stationCodes,
    'Mita candidate changed: station identity');
  const relation443286Stops = relations[0].stops.toReversed();
  const relation8019910Stops = relations[1].stops;
  candidate.stations.forEach((station, index) => {
    assert.equal(station.opposingStopPair.relation443286.nodeId, relation443286Stops[index].id,
      `Mita candidate changed: ${station.name} relation 443286 stop pairing`);
    assert.equal(station.opposingStopPair.relation8019910.nodeId, relation8019910Stops[index].id,
      `Mita candidate changed: ${station.name} relation 8019910 stop pairing`);
    assert.equal(relation443286Stops[index].name, station.name, `Mita source changed: relation 443286 stop name/order`);
    assert.equal(relation8019910Stops[index].name, station.name, `Mita source changed: relation 8019910 stop name/order`);
  });

  const rawNodeIds = new Set(raw.elements.filter(row => row.type === 'node').map(row => row.id));
  const permitted = new Map(relations.map(({ relation, wayIds }) => [relation.id,
    new Set(wayIds.filter(id => id !== evidence.source.excludedPostTerminalWayId))]));
  candidate.intervals.forEach((interval, index) => {
    assert.equal(interval.index, index);
    assert.equal(interval.from.stationCode, candidate.stations[index].stationCode);
    assert.equal(interval.to.stationCode, candidate.stations[index + 1].stationCode);
    assert(coordEqual(interval.coordinates[0], candidate.stations[index].selectedDisplayAnchor)
      && coordEqual(interval.coordinates.at(-1), candidate.stations[index + 1].selectedDisplayAnchor),
    `Mita candidate changed: interval ${index} station seam`);
    for (const source of Object.values(interval.sourceTracks)) {
      assert(source.wayIds.every(id => permitted.get(source.relationId)?.has(id)),
        `Mita candidate changed: interval ${index} has non-passenger way`);
      assert(source.nodeIds.every(id => rawNodeIds.has(id)), `Mita raw source changed: interval ${index} node missing`);
    }
  });
  assert.deepEqual(candidate.stations.at(-1).selectedDisplayAnchor, evidence.candidate.meguroAnchor,
    'Mita candidate changed: registered Meguro alias');
  assert.deepEqual(candidate.candidate.coordinates[0], candidate.stations[0].selectedDisplayAnchor);
  assert.deepEqual(candidate.candidate.coordinates.at(-1), evidence.candidate.meguroAnchor);

  // Semantic failures above are intentionally more useful than a bare hash error.
  assert.equal(hash(raw), evidence.source.rawCanonicalSHA256, 'Mita raw source changed');
  assert.equal(hash(candidate), evidence.source.candidateCanonicalSHA256, 'Mita candidate source changed');
  return structuredClone(candidate);
}

function stageRecord(evidence) {
  return {
    reviewedAt: evidence.reviewedAt,
    script: 'app/scripts/railway/repair-mita-display.mjs',
    evidence: 'app/scripts/railway/mita-display-evidence.json',
    lineID: LINE,
    source: { kind: 'identified paired OSM passenger route relations', relations: evidence.source.relations.map(row => row.id),
      rawSHA256: evidence.source.rawFileSHA256, candidateSHA256: evidence.source.candidateFileSHA256,
      osmBaseTimestamp: evidence.source.osmBaseTimestamp },
    displayPolicy: evidence.policy,
    stationAliasCount: 27,
    intervalCount: 26,
    excludedPostTerminalWayId: evidence.source.excludedPostTerminalWayId,
    physicalTopologyChanged: false,
    acceptance: 'candidate-only; production promotion requires root visual acceptance against the identified Apple corridor',
  };
}

/** Add display-only station aliases and interval geometry; physical compact data is untouched. */
export function repairPackage(input, evidence = evidenceDefault(), raw = rawDefault(evidence), retained = candidateDefault(evidence)) {
  const candidate = buildCandidate(evidence, raw, retained);
  const pkg = structuredClone(input);
  const index = pkg.lines.findIndex(row => row.id === LINE);
  assert.equal(index, evidence.baseline.packageLineIndex, 'Mita baseline owning line index changed');
  const line = pkg.lines[index];
  const physical = structuredClone(line);
  delete physical.displayStationCoordinates;
  delete physical.displayIntervalCoordinates;
  assert.equal(hash(physical), evidence.baseline.owningLineSHA256, 'Mita baseline physical source changed');

  const aliases = Object.fromEntries(candidate.stations.map(row => [row.stationCode, row.selectedDisplayAnchor]));
  const intervals = Object.fromEntries(candidate.intervals.map(row => [row.index, row.coordinates]));
  assert.deepEqual(aliases, evidence.candidate.stationAliases, 'Mita candidate station aliases changed');
  assert.deepEqual(aliases['004072'], evidence.candidate.meguroAnchor, 'Mita registered Meguro alias changed');
  assert(!line.displayStationCoordinates || equal(line.displayStationCoordinates, aliases), 'Mita competing station display override');
  assert(!line.displayIntervalCoordinates || equal(line.displayIntervalCoordinates, intervals), 'Mita competing interval display override');
  line.displayStationCoordinates = structuredClone(aliases);
  line.displayIntervalCoordinates = structuredClone(intervals);
  assert.deepEqual(line.stations, physical.stations);
  assert.deepEqual(line.segments, physical.segments);

  pkg.geometrySource.manualOverrides ||= {};
  const record = stageRecord(evidence);
  assert(!pkg.geometrySource.manualOverrides[STAGE] || equal(pkg.geometrySource.manualOverrides[STAGE], record),
    'Mita competing provenance stage');
  pkg.geometrySource.manualOverrides[STAGE] = record;
  return pkg;
}

function displayedLine(line) {
  return {
    ...line,
    stations: line.stations.map(row => line.displayStationCoordinates?.[row[0]]
      ? [...row.slice(0, 2), ...line.displayStationCoordinates[row[0]], ...row.slice(4)] : row),
    segments: line.segments.map((row, index) => line.displayIntervalCoordinates?.[index]
      ? [row[0], 0, line.displayIntervalCoordinates[index]] : row),
  };
}

function distance(a, b) {
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
    (b[1] - a[1]) * 111320);
}
function cumulative(points) {
  const values = [0];
  for (let index = 1; index < points.length; index += 1)
    values.push(values.at(-1) + distance(points[index - 1], points[index]));
  return values;
}
function pointAt(points, measures, measure) {
  if (measure <= 0) return points[0];
  if (measure >= measures.at(-1)) return points.at(-1);
  let index = 1;
  while (measures[index] < measure) index += 1;
  const fraction = (measure - measures[index - 1]) / (measures[index] - measures[index - 1]);
  return [points[index - 1][0] + fraction * (points[index][0] - points[index - 1][0]),
    points[index - 1][1] + fraction * (points[index][1] - points[index - 1][1])];
}
function project(point, a, b) {
  const lat = (a[1] + b[1] + point[1]) / 3 * Math.PI / 180;
  const sx = 111320 * Math.cos(lat), sy = 111320;
  const vx = (b[0] - a[0]) * sx, vy = (b[1] - a[1]) * sy;
  const px = (point[0] - a[0]) * sx, py = (point[1] - a[1]) * sy;
  const fraction = Math.max(0, Math.min(1, (px * vx + py * vy) / (vx * vx + vy * vy || 1)));
  const coordinate = [a[0] + fraction * (b[0] - a[0]), a[1] + fraction * (b[1] - a[1])];
  return { fraction, coordinate, displacementMetres: distance(point, coordinate) };
}

function mappedReferences(line, beforePart, afterPart, evidence) {
  const oldPoints = beforePart[7], newPoints = afterPart[7];
  const oldMeasures = cumulative(oldPoints), newMeasures = cumulative(newPoints);
  const locate = (points, target) => points.findIndex(point => coordEqual(point, target));
  const oldStationIndices = line.stations.map(row => locate(oldPoints, row.slice(2, 4)));
  const newStationIndices = line.stations.map(row => locate(newPoints, line.displayStationCoordinates[row[0]]));
  assert(oldStationIndices.every(index => index >= 0) && newStationIndices.every(index => index >= 0),
    'Mita station seam missing from native part');
  const oldStationMeasures = oldStationIndices.map(index => oldMeasures[index]);

  function mapMeasure(measure) {
    const terminal = Math.abs(measure - oldMeasures.at(-1)) <= 0.2;
    const clamped = terminal ? oldMeasures.at(-1) : Math.max(0, Math.min(oldMeasures.at(-1), measure));
    let stationInterval = oldStationMeasures.length - 2;
    for (let index = 0; index < oldStationMeasures.length - 1; index += 1) {
      if (clamped <= oldStationMeasures[index + 1] + 1e-6) { stationInterval = index; break; }
    }
    const oldCoordinate = pointAt(oldPoints, oldMeasures, clamped);
    let best = null;
    for (let index = newStationIndices[stationInterval]; index < newStationIndices[stationInterval + 1]; index += 1) {
      const candidate = project(oldCoordinate, newPoints[index], newPoints[index + 1]);
      if (!best || candidate.displacementMetres < best.displacementMetres)
        best = { ...candidate, stationInterval, newMeasure: newMeasures[index]
          + candidate.fraction * (newMeasures[index + 1] - newMeasures[index]), oldMeasure: measure, oldCoordinate };
    }
    if (terminal) best = { ...best, newMeasure: newMeasures.at(-1), coordinate: newPoints.at(-1),
      displacementMetres: distance(oldCoordinate, newPoints.at(-1)) };
    assert(best.displacementMetres <= evidence.candidate.maxReferenceDisplacementMetres,
      `Mita measured reference displacement ${best.displacementMetres.toFixed(3)}m exceeds review bound`);
    return best;
  }

  const lanes = evidence.baseline.laneRows.map(row => {
    const from = mapMeasure(row[2]), to = mapMeasure(row[3]);
    assert(from.stationInterval <= to.stationInterval && from.newMeasure < to.newMeasure,
      'Mita lane reference order changed');
    return { row: [...row.slice(0, 2), Number(from.newMeasure.toFixed(1)), Number(to.newMeasure.toFixed(1)), row[4]], from, to };
  });
  const follows = evidence.baseline.followRows.map(row => {
    assert(row[4] === LINE, 'Mita reviewed follow must use Mita as canonical leader');
    const from = mapMeasure(row[6]), to = mapMeasure(row[7]);
    assert(from.newMeasure > to.newMeasure, 'Mita canonical reverse follow order changed');
    return { row: [...row.slice(0, 6), from.newMeasure,
      Math.abs(row[7] - oldMeasures.at(-1)) <= 0.2 ? newMeasures.at(-1) : Number(to.newMeasure.toFixed(1))], from, to };
  });
  assert.deepEqual(lanes.map(item => item.row), evidence.candidate.laneMappings.map(item => item.mapped),
    'Mita lane geographic remap changed');
  assert.deepEqual(follows.map(item => item.row), evidence.candidate.followMappings.map(item => item.mapped),
    'Mita follow geographic remap changed');
  return { lanes, follows };
}

/** Rebuild only Mita's native part and its three measured-reference rows. */
export function repairParts(pkg, input, evidence = evidenceDefault(), raw = rawDefault(evidence), retained = candidateDefault(evidence)) {
  buildCandidate(evidence, raw, retained);
  const lanes = structuredClone(input), line = pkg.lines.find(row => row.id === LINE);
  assert(line, 'Mita candidate package line missing');
  const shown = displayedLine(line);
  const parts = network.displayPartsForLine(shown);
  assert.equal(parts.length, 1, 'Mita candidate part topology changed');
  const rows = partRowsForLine(line, parts, { stations: shown.stations, intervals: network.decodeIntervals(shown) }, null);
  assert.equal(rows.length, 1);
  assert.equal(hash(rows[0]), evidence.candidate.nativePartSHA256, 'Mita candidate native part changed');

  const currentParts = lanes.partsByRegion.jp.filter(row => row[0] === LINE);
  assert(currentParts.length === 1 && (equal(currentParts[0], evidence.baseline.nativePart) || equal(currentParts[0], rows[0])),
    'Mita native part baseline changed');
  const currentLaneRows = lanes.byRegion.jp.filter(row => row[0] === LINE);
  const expectedLaneRows = evidence.candidate.laneMappings.map(item => item.mapped);
  assert(equal(currentLaneRows, evidence.baseline.laneRows) || equal(currentLaneRows, expectedLaneRows),
    'Mita lane measured references changed');
  const currentFollowRows = lanes.followsByRegion.jp.filter(row => row[0] === LINE || row[4] === LINE);
  const expectedFollowRows = evidence.candidate.followMappings.map(item => item.mapped);
  assert(equal(currentFollowRows, evidence.baseline.followRows) || equal(currentFollowRows, expectedFollowRows),
    'Mita follow measured references changed');

  for (const key of Object.keys(lanes).filter(key => !['partsByRegion', 'byRegion', 'followsByRegion'].includes(key)))
    assert(!JSON.stringify(lanes[key]).includes(LINE), `Mita unreviewed ${key} reference`);

  const mapped = mappedReferences(line, evidence.baseline.nativePart, rows[0], evidence);
  let laneIndex = 0, followIndex = 0;
  lanes.partsByRegion.jp = lanes.partsByRegion.jp.map(row => row[0] === LINE ? rows[0] : row);
  lanes.byRegion.jp = lanes.byRegion.jp.map(row => row[0] === LINE ? mapped.lanes[laneIndex++].row : row);
  lanes.followsByRegion.jp = lanes.followsByRegion.jp.map(row => row[0] === LINE || row[4] === LINE
    ? mapped.follows[followIndex++].row : row);
  assert.equal(laneIndex, mapped.lanes.length);
  assert.equal(followIndex, mapped.follows.length);
  return lanes;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  assert(args.length === 2 && args[0] === '--candidate-dir',
    'Usage: node repair-mita-display.mjs --candidate-dir /private/tmp/<directory>');
  const output = path.resolve(args[1]);
  assert(output.startsWith('/private/tmp/'), 'Mita candidate output must be under /private/tmp');
  const evidencePath = path.resolve(APP, 'scripts/railway/mita-display-evidence.json');
  const evidence = JSON.parse(fs.readFileSync(evidencePath));
  const rawPath = path.resolve(REPO, evidence.source.rawPath), candidatePath = path.resolve(REPO, evidence.source.candidatePath);
  assert.equal(hash(fs.readFileSync(rawPath)), evidence.source.rawFileSHA256, 'Mita raw source file changed');
  assert.equal(hash(fs.readFileSync(candidatePath)), evidence.source.candidateFileSHA256, 'Mita candidate file changed');
  const raw = JSON.parse(fs.readFileSync(rawPath)), retained = JSON.parse(fs.readFileSync(candidatePath));
  const input = read('public/rail/jp-2025.json'), inputLanes = read('public/rail/display-lanes.json');
  const pkg = repairPackage(input, evidence, raw, retained), lanes = repairParts(pkg, inputLanes, evidence, raw, retained);
  assert.deepEqual(repairPackage(pkg, evidence, raw, retained), pkg, 'Mita package replay is not idempotent');
  assert.deepEqual(repairParts(pkg, lanes, evidence, raw, retained), lanes, 'Mita lane replay is not idempotent');
  fs.mkdirSync(output, { recursive: true });
  fs.writeFileSync(path.join(output, 'jp-2025.json'), JSON.stringify(pkg));
  fs.writeFileSync(path.join(output, 'display-lanes.json'), JSON.stringify(lanes) + '\n');
  fs.writeFileSync(path.join(output, 'mita-review.json'), JSON.stringify({
    mode: 'candidate-only', lineID: LINE, policy: evidence.policy,
    stationAliases: 27, intervals: 26, nativePart: evidence.candidate.nativePartHeader,
    laneRows: evidence.candidate.laneMappings.map(item => item.mapped),
    followRows: evidence.candidate.followMappings.map(item => item.mapped),
    maxReferenceDisplacementMetres: Math.max(...evidence.candidate.laneMappings.flatMap(item => [item.from.displacementMetres, item.to.displacementMetres]),
      ...evidence.candidate.followMappings.flatMap(item => [item.leaderFrom.displacementMetres, item.leaderTo.displacementMetres])),
    productionPromotion: false,
  }, null, 2) + '\n');
  console.log(JSON.stringify({ output, mode: 'candidate-only', lineID: LINE, vertices: evidence.candidate.nativePartHeader[4],
    policy: evidence.policy }));
}
