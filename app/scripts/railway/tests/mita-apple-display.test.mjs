import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { buildCandidate, LINE, repairPackage, repairParts } from '../repair-mita-apple-display.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '../../../..');
const require = createRequire(import.meta.url);
const network = require(path.resolve(REPO, 'app/public/rail-network.js'));
const read = file => JSON.parse(fs.readFileSync(file));
const hash = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const evidence = read(path.resolve(HERE, '../mita-apple-display-evidence.json'));
const input = read(path.resolve(REPO, 'app/public/rail/jp-2025.json'));
const inputLanes = read(path.resolve(REPO, 'app/public/rail/display-lanes.json'));
const line = pkg => pkg.lines.find(row => row.id === LINE);

function distance(a, b) {
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360), (b[1] - a[1]) * 111320);
}
function turns(points) {
  const vector = (a, b) => {
    const latitude = (a[1] + b[1]) * Math.PI / 360;
    return [(b[0] - a[0]) * 111320 * Math.cos(latitude), (b[1] - a[1]) * 111320];
  };
  return points.slice(1, -1).map((point, index) => {
    const incoming = vector(points[index], point), outgoing = vector(point, points[index + 2]);
    const cosine = (incoming[0] * outgoing[0] + incoming[1] * outgoing[1])
      / (Math.hypot(...incoming) * Math.hypot(...outgoing));
    return Math.acos(Math.max(-1, Math.min(1, cosine))) * 180 / Math.PI;
  });
}

test('buildCandidate uses all retained views, freezes north 0-5 and bounds the Apple normal field', () => {
  const candidate = buildCandidate(input, evidence);
  assert.equal(evidence.apple.records.length, 115);
  assert.deepEqual([...new Set(evidence.apple.records.map(row => row.interval))].sort((a, b) => a - b), [...Array(26).keys()]);
  const baseline = network.decodeIntervals(line(input));
  for (let interval = 0; interval <= 5; interval += 1)
    assert.deepEqual(candidate.intervals[interval], baseline[interval], `interval ${interval} remains byte-exact baseline`);
  assert.deepEqual(evidence.candidate.changedIntervals, [...Array(20).keys()].map(index => index + 6));
  assert.equal(candidate.bins.length, evidence.candidate.acceptedBinCount);
  assert(candidate.bins.every(row => row.files.length >= 2 && row.maximumDisagreementMetres <= 4));
  assert(candidate.bins.every(row => Math.hypot(...row.vector) <= (row.interval === 23 ? 80 : 40)));
  assert(candidate.bins.some(row => row.interval === 23 && Math.hypot(...row.vector) > 50),
    'wide interval 23 evidence must retain the labelled blue corridor beyond the failed 40m cutoff');
  assert.equal(candidate.audit.discontinuousCompetitionRejected, 0);
  assert.deepEqual(candidate.intervals[25].at(-1), line(input).stations.at(-1).slice(2, 4));
  for (let interval = 0; interval < 25; interval += 1)
    assert.deepEqual(candidate.intervals[interval].at(-1), candidate.intervals[interval + 1][0]);
  for (const [code, alias] of Object.entries(candidate.stationAliases)) {
    const physical = line(input).stations.find(row => row[0] === code).slice(2, 4);
    assert(distance(physical, alias) <= 40.000001);
  }
});

test('interval 13 source views bridge the label gap without a baseline-return triangle', () => {
  const candidate = buildCandidate(input, evidence), method = candidate.methods[13];
  assert(method.sourceGapMetres.includes(130), '13-02/13-03 labelled gap remains identified in provenance');
  assert.equal(method.taperPoints, 0, 'the labelled gap must not taper back to the old N02 baseline');
  assert(method.curveInterpolationPoints > 0);
  assert.equal(method.linearInterpolationPoints, 0, 'forward source controls should preserve the curve');
  assert(Math.max(...turns(candidate.intervals[13])) < 35, 'candidate must not contain the observed triangular/backwards turn');
  assert.equal(candidate.methods[23].taperPoints, 0,
    'wide Apple support must not return interval 23 to the observed campus-cut baseline');
  assert(candidate.methods[23].curveInterpolationPoints > 0);
  assert(Math.max(...turns(candidate.intervals[23])) < 45, 'dashed Mita gap must not create a campus-cut corner');
});

test('repairPackage preserves physical ownership and unrelated lines with exact replay', () => {
  const before = structuredClone(input), pkg = repairPackage(input, evidence), old = line(input), changed = line(pkg);
  assert.deepEqual(input, before);
  assert.deepEqual(changed.stations, old.stations);
  assert.deepEqual(changed.segments, old.segments);
  for (const key of Object.keys(old)) assert.deepEqual(changed[key], old[key]);
  assert.deepEqual(pkg.lines.filter(row => row.id !== LINE), input.lines.filter(row => row.id !== LINE));
  assert.deepEqual(changed.displayStationCoordinates[old.stations.at(-1)[0]], old.stations.at(-1).slice(2, 4));
  assert.equal(Object.keys(changed.displayIntervalCoordinates).length, 26);
  assert.equal(pkg.geometrySource.manualOverrides['mita-apple-cartography-display'].physicalTopologyChanged, false);
  assert.match(pkg.geometrySource.manualOverrides['mita-apple-cartography-display'].acceptance, /26 complete native intervals/);
  assert.deepEqual(repairPackage(pkg, evidence), pkg);
});

test('repairParts rebuilds only Mita and remaps reviewed measures without changing the Namboku input', () => {
  const pkg = repairPackage(input, evidence), result = repairParts(pkg, inputLanes, evidence);
  const part = result.partsByRegion.jp.find(row => row[0] === LINE);
  assert.deepEqual(part.slice(0, 7), evidence.candidate.nativePartHeader);
  assert.deepEqual(result.byRegion.jp.filter(row => row[0] === LINE), evidence.candidate.laneRows);
  const follows = result.followsByRegion.jp.filter(row => row[0] === LINE || row[4] === LINE);
  assert.deepEqual(follows, evidence.candidate.followRows);
  assert.deepEqual(follows[0].slice(0, 6), evidence.baseline.followRows[0].slice(0, 6));
  assert(follows[0][6] > follows[0][7]);
  assert.deepEqual(result.partsByRegion.jp.filter(row => row[0] !== LINE), inputLanes.partsByRegion.jp.filter(row => row[0] !== LINE));
  assert.deepEqual(result.byRegion.jp.filter(row => row[0] !== LINE), inputLanes.byRegion.jp.filter(row => row[0] !== LINE));
  assert.deepEqual(result.followsByRegion.jp.filter(row => row[0] !== LINE && row[4] !== LINE),
    inputLanes.followsByRegion.jp.filter(row => row[0] !== LINE && row[4] !== LINE));
  assert.deepEqual(repairParts(pkg, result, evidence), result);
});

test('source custody rejects changed samples, manifest identity and physical geometry', () => {
  const changedSample = structuredClone(evidence);
  changedSample.apple.records[0].samples[0].point[0] += 0.000001;
  assert.throws(() => buildCandidate(input, changedSample), /embedded evidence changed/);
  const changedManifest = structuredClone(evidence);
  changedManifest.apple.records[0].sha256 = '0'.repeat(64);
  changedManifest.apple.embeddedRecordsSHA256 = hash(changedManifest.apple.records);
  assert.throws(() => buildCandidate(input, changedManifest), /source manifest changed/);
  const wrongIdentity = structuredClone(evidence);
  wrongIdentity.identity.routeRelationIDs = [443286, 1];
  assert.throws(() => buildCandidate(input, wrongIdentity), /OSM identity reference changed/);
  const changedPhysical = structuredClone(input);
  line(changedPhysical).segments[13][2][2][0] += 0.000001;
  assert.throws(() => buildCandidate(changedPhysical, evidence), /physical source changed/);
});

test('competing per-view vectors are rejected instead of moving the field', () => {
  const changed = structuredClone(evidence);
  const record = changed.apple.records.find(row => row.samples.length > 20);
  for (const sample of record.samples) {
    const latitude = (sample.seed[1] + sample.point[1]) * Math.PI / 360;
    const vector = [(sample.point[0] - sample.seed[0]) * 111320 * Math.cos(latitude),
      (sample.point[1] - sample.seed[1]) * 111320];
    const length = Math.hypot(...vector), scale = (length + 10) / length;
    sample.point = [sample.seed[0] + vector[0] * scale / (111320 * Math.cos(latitude)),
      sample.seed[1] + vector[1] * scale / 111320];
  }
  changed.apple.embeddedRecordsSHA256 = hash(changed.apple.records);
  changed.apple.manifestSHA256 = hash(changed.apple.records.map(row => ({ file: row.file, sha256: row.sha256,
    interval: row.interval, ordinal: row.ordinal })));
  changed.candidate = {};
  const candidate = buildCandidate(input, changed);
  assert(candidate.audit.vectorDisagreement > evidence.candidate.audit.vectorDisagreement);
  assert.equal(hash(candidate.intervals), evidence.candidate.coordinatesSHA256,
    'the rejected competing view must not move the candidate field');
});
