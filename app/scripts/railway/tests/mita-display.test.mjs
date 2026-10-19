import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { buildCandidate, LINE, repairPackage, repairParts } from '../repair-mita-display.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '../../../..');
const read = file => JSON.parse(fs.readFileSync(file));
const evidence = read(path.resolve(HERE, '../mita-display-evidence.json'));
const input = read(path.resolve(REPO, 'app/public/rail/jp-2025.json'));
const inputLanes = read(path.resolve(REPO, 'app/public/rail/display-lanes.json'));
const raw = read(path.resolve(REPO, evidence.source.rawPath));
const retained = read(path.resolve(REPO, evidence.source.candidatePath));
const find = pkg => pkg.lines.find(row => row.id === LINE);
const candidate = () => repairPackage(input, evidence, raw, retained);

test('buildCandidate validates the two identified passenger chains, 27 stop pairs and terminal exclusion', () => {
  const result = buildCandidate(evidence, raw, retained);
  assert.equal(result.stations.length, 27);
  assert.equal(result.intervals.length, 26);
  assert.equal(result.validation.oppositeDirectionContinuityErrors.length, 0);
  assert.deepEqual(result.validation.intervalsWithTrackDisagreementOver20Metres, [1, 2, 23, 24]);
  assert(!result.intervals.some(interval => Object.values(interval.sourceTracks)
    .some(track => track.wayIds.includes(evidence.source.excludedPostTerminalWayId))));
  assert.deepEqual(result.stations.at(-1).selectedDisplayAnchor, [139.71566, 35.632485]);
});

test('package candidate adds only display aliases, interval overrides and frozen provenance', () => {
  const before = structuredClone(input), pkg = candidate(), oldLine = find(input), line = find(pkg);
  assert.deepEqual(input, before);
  assert.deepEqual(line.stations, oldLine.stations);
  assert.deepEqual(line.segments, oldLine.segments);
  assert.deepEqual(pkg.lines.filter(row => row.id !== LINE), input.lines.filter(row => row.id !== LINE));
  assert.deepEqual(pkg.stats, input.stats);
  for (const key of Object.keys(oldLine)) assert.deepEqual(line[key], oldLine[key]);
  assert.equal(Object.keys(line.displayStationCoordinates).length, 27);
  assert.equal(Object.keys(line.displayIntervalCoordinates).length, 26);
  assert.deepEqual(line.displayStationCoordinates['004072'], [139.71566, 35.632485]);
  retained.intervals.forEach((interval, index) => {
    assert.deepEqual(line.displayIntervalCoordinates[index][0], line.displayStationCoordinates[line.stations[index][0]]);
    assert.deepEqual(line.displayIntervalCoordinates[index].at(-1), line.displayStationCoordinates[line.stations[index + 1][0]]);
  });
  assert.equal(pkg.geometrySource.manualOverrides['mita-osm-display-candidate'].physicalTopologyChanged, false);
  assert.match(pkg.geometrySource.manualOverrides['mita-osm-display-candidate'].acceptance, /candidate-only/);
  assert.deepEqual(repairPackage(pkg, evidence, raw, retained), pkg);
});

test('native candidate rebuilds only Mita and geographically remaps lane and shared-follow measures', () => {
  const pkg = candidate(), result = repairParts(pkg, inputLanes, evidence, raw, retained);
  const rows = result.partsByRegion.jp.filter(row => row[0] === LINE);
  assert.equal(rows.length, 1);
  assert.deepEqual(rows[0].slice(0, 7), evidence.candidate.nativePartHeader);
  assert.equal(rows[0][4], 469);

  const laneRows = result.byRegion.jp.filter(row => row[0] === LINE);
  assert.deepEqual(laneRows, evidence.candidate.laneMappings.map(item => item.mapped));
  const follows = result.followsByRegion.jp.filter(row => row[0] === LINE || row[4] === LINE);
  assert.deepEqual(follows, evidence.candidate.followMappings.map(item => item.mapped));
  assert.deepEqual(follows[0].slice(0, 6), evidence.baseline.followRows[0].slice(0, 6),
    'Namboku follower identity, part and input measures stay unchanged');
  assert(follows[0][6] > follows[0][7], 'canonical Mita follow remains reversed from Meguro');
  assert.equal(evidence.candidate.followMappings[0].leaderFrom.stationInterval, 25);
  assert.equal(evidence.candidate.followMappings[0].leaderTo.stationInterval, 23);
  for (const mapping of [...evidence.candidate.laneMappings, ...evidence.candidate.followMappings]) {
    for (const endpoint of ['from', 'to', 'leaderFrom', 'leaderTo']) if (mapping[endpoint])
      assert(mapping[endpoint].displacementMetres <= evidence.candidate.maxReferenceDisplacementMetres);
  }

  assert.deepEqual(result.partsByRegion.jp.filter(row => row[0] !== LINE), inputLanes.partsByRegion.jp.filter(row => row[0] !== LINE));
  assert.deepEqual(result.byRegion.jp.filter(row => row[0] !== LINE), inputLanes.byRegion.jp.filter(row => row[0] !== LINE));
  assert.deepEqual(result.followsByRegion.jp.filter(row => row[0] !== LINE && row[4] !== LINE),
    inputLanes.followsByRegion.jp.filter(row => row[0] !== LINE && row[4] !== LINE));
  for (const key of Object.keys(inputLanes).filter(key => !['partsByRegion', 'byRegion', 'followsByRegion'].includes(key)))
    assert.deepEqual(result[key], inputLanes[key]);
  for (const region of Object.keys(inputLanes.partsByRegion).filter(region => region !== 'jp'))
    assert.deepEqual(result.partsByRegion[region], inputLanes.partsByRegion[region]);
  assert.deepEqual(repairParts(pkg, result, evidence, raw, retained), result);
});

test('source validation rejects wrong company, yard/service geometry, stop order and changed source bytes', () => {
  const wrongCompany = structuredClone(raw);
  wrongCompany.elements.find(row => row.type === 'relation' && row.id === 443286).tags.operator = '別会社';
  assert.throws(() => buildCandidate(evidence, wrongCompany, retained), /wrong company\/operator/);

  const yard = structuredClone(raw);
  yard.elements.find(row => row.type === 'way' && row.id === 184555271).tags.service = 'yard';
  assert.throws(() => buildCandidate(evidence, yard, retained), /yard\/service/);

  const reordered = structuredClone(raw), relation = reordered.elements.find(row => row.type === 'relation' && row.id === 8019910);
  const positions = relation.members.map((row, index) => row.type === 'node' && row.role?.startsWith('stop') ? index : -1).filter(index => index >= 0);
  [relation.members[positions[0]], relation.members[positions[1]]] = [relation.members[positions[1]], relation.members[positions[0]]];
  assert.throws(() => buildCandidate(evidence, reordered, retained), /stop order/);

  const changedRaw = structuredClone(raw);
  changedRaw.elements.find(row => row.type === 'node').lon += 0.000001;
  assert.throws(() => buildCandidate(evidence, changedRaw, retained), /raw source changed/);
  const changedCandidate = structuredClone(retained);
  changedCandidate.intervals[13].coordinates[2][0] += 0.000001;
  assert.throws(() => buildCandidate(evidence, raw, changedCandidate), /candidate source changed/);
});

test('replay refuses changed physical ownership, competing display state or unreviewed measured references', () => {
  const changedPhysical = structuredClone(input);
  find(changedPhysical).segments[13][2][2][0] += 0.000001;
  assert.throws(() => repairPackage(changedPhysical, evidence, raw, retained), /physical source changed/);

  const competing = structuredClone(input);
  find(competing).displayStationCoordinates = { '003461': [0, 0] };
  assert.throws(() => repairPackage(competing, evidence, raw, retained), /competing station display override/);

  const pkg = candidate(), changedPart = structuredClone(inputLanes);
  changedPart.partsByRegion.jp.find(row => row[0] === LINE)[7][12][0] += 0.000001;
  assert.throws(() => repairParts(pkg, changedPart, evidence, raw, retained), /native part baseline changed/);

  const changedLane = structuredClone(inputLanes);
  changedLane.byRegion.jp.find(row => row[0] === LINE)[2] += 1;
  assert.throws(() => repairParts(pkg, changedLane, evidence, raw, retained), /lane measured references changed/);

  const unreviewed = structuredClone(inputLanes);
  unreviewed.familyWindowsByRegion.jp.push([LINE, 0, 1, 2, 'group']);
  assert.throws(() => repairParts(pkg, unreviewed, evidence, raw, retained), /unreviewed familyWindowsByRegion reference/);
});
