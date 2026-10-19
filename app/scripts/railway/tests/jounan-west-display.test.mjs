import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { ACCEPTANCE_LINE_IDS, DIRECT_LINE_IDS, LEGAL_LINE_IDS, assertApplyAccepted, candidateGeoJSON,
  deriveNativeRows, loadReviewedCandidate, repairPackage, repairParts,
  validateCandidate } from '../repair-jounan-west-display.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const livePackage = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json', import.meta.url)));
const liveLanes = JSON.parse(fs.readFileSync(new URL('../../../public/rail/display-lanes.json', import.meta.url)));
const hash = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');

function physical(line) {
  const result = structuredClone(line);
  delete result.displayIntervalCoordinates;
  delete result.displayStationCoordinates;
  delete result.displayBranchLeadIns;
  return result;
}

function candidateFixture(e) {
  return { format: 'jtm-jounan-west-display-candidate-v1', status: 'candidate-only',
    lines: e.lineIDs.map(lineID => {
      const source = physical(livePackage.lines.find(line => line.id === lineID));
      const decoded = network.decodeIntervals(source), owner = e.owners[lineID];
      return { lineID,
        displayStationCoordinates: Object.fromEntries(owner.stationIDs.map(stationID => {
          const station = source.stations.find(row => row[0] === stationID);
          return [stationID, [station[2], station[3]]];
        })),
        candidateIntervals: owner.intervalIndexes.map(intervalIndex =>
          ({ intervalIndex, coordinates: structuredClone(decoded[intervalIndex]) })) };
    }) };
}

function evidenceFixture() {
  const packageIndices = Object.fromEntries(LEGAL_LINE_IDS.map(lineID =>
    [lineID, livePackage.lines.findIndex(line => line.id === lineID)]));
  const stationIDs = Object.fromEntries(LEGAL_LINE_IDS.map(lineID => [lineID,
    physical(livePackage.lines[packageIndices[lineID]]).stations.map(row => row[0])]));
  const intervalCounts = Object.fromEntries(LEGAL_LINE_IDS.map(lineID => [lineID,
    physical(livePackage.lines[packageIndices[lineID]]).segments.length]));
  const owners = Object.fromEntries(DIRECT_LINE_IDS.map(lineID => [lineID, {
    intervalIndexes: Array.from({ length: intervalCounts[lineID] }, (_, index) => index),
    stationIDs: stationIDs[lineID],
  }]));
  return { status: 'candidate-only', reviewedAt: 'fixture', lineIDs: DIRECT_LINE_IDS,
    owners, policy: { representation: 'display-cartography',
      acceptanceGate: 'accepted-display-cartography' },
    acceptanceScope: { lineIDs: ACCEPTANCE_LINE_IDS, intervalCount: 29,
      baselineViewpointCount: 70, candidateViewpointCount: null, candidateReport: null },
    candidate: { format: 'jtm-jounan-west-display-candidate-v1' },
    baseline: { packageIndices,
      intervalCounts, stationIDs,
      lineSha256: Object.fromEntries(LEGAL_LINE_IDS.map(lineID =>
        [lineID, hash(physical(livePackage.lines[packageIndices[lineID]]))])),
      unownedDisplayIntervals: Object.fromEntries(LEGAL_LINE_IDS.map(lineID => [lineID, {}])),
      unownedDisplayStations: Object.fromEntries(LEGAL_LINE_IDS.map(lineID => [lineID, {}])),
      nativeRowsSha256: Object.fromEntries(LEGAL_LINE_IDS.map(lineID => [lineID,
        hash(liveLanes.partsByRegion.jp.filter(row => row[0] === lineID))])),
      measuredReferences: {} } };
}

function packageFixture(e) {
  const lines = Array.from({ length: Math.max(...Object.values(e.baseline.packageIndices)) + 2 },
    (_, index) => ({ id: `unrelated-${index}` }));
  for (const lineID of LEGAL_LINE_IDS) {
    const index = e.baseline.packageIndices[lineID];
    lines[index] = physical(livePackage.lines[index]);
  }
  lines.at(-1).keep = true;
  return { format: 'compact-v1', country: 'jp', lines,
    geometrySource: { manualOverrides: { concurrent: { keep: true } } } };
}

function laneFixture() {
  const rows = [['unrelated-before', 0, 1]];
  const packageOrdered = [...LEGAL_LINE_IDS].sort((a, b) =>
    livePackage.lines.findIndex(line => line.id === a) - livePackage.lines.findIndex(line => line.id === b));
  for (const lineID of packageOrdered) {
    if (lineID === 'jp-伊予鉄道-花園線') rows.push(['unrelated-middle', 0, 1]);
    rows.push(...structuredClone(liveLanes.partsByRegion.jp.filter(row => row[0] === lineID)));
  }
  rows.push(['unrelated-after', 0, 1]);
  return { partsByRegion: { jp: rows }, byRegion: { jp: [['unrelated', 0, 0, 1, .5]] },
  followsByRegion: { jp: [['unrelated', 0, 0, 1, 'other', 0, 0, 1]] },
  familyWindowsByRegion: { jp: [] }, groupWindowsByRegion: { jp: {} },
  chainBoundariesByRegion: { jp: {} } };
}

function prepared() {
  const e = evidenceFixture(), candidate = candidateFixture(e);
  const pkg = repairPackage(packageFixture(e), e, candidate);
  const rows = deriveNativeRows(pkg, e);
  e.nativeReplay = { candidateRowsSha256: Object.fromEntries(e.lineIDs.map(lineID =>
    [lineID, hash(rows[lineID])])) };
  return { e, candidate, pkg, rows };
}

test('real Jounan baseline retains the exact non-station retrace and two legal display arms', () => {
  const e = evidenceFixture(), candidate = candidateFixture(e);
  const reviewed = validateCandidate(candidate, e);
  assert.deepEqual(reviewed.junction, [132.75865, 33.8403]);
  assert.equal(reviewed.retracePointCount, 3);
  const pkg = repairPackage(packageFixture(e), e, candidate);
  const line = pkg.lines[e.baseline.packageIndices[DIRECT_LINE_IDS[0]]];
  const parts = network.displayPartsForLine(line);
  assert.equal(parts.length, 2);
  assert.deepEqual(parts[0][0], reviewed.junction);
  assert.deepEqual(parts[0].at(-1), line.displayStationCoordinates['008761']);
  assert.deepEqual(parts[1][0], line.displayStationCoordinates['008756']);
  assert(parts[1].some(point => JSON.stringify(point) === JSON.stringify(reviewed.junction)));
  assert(!line.stations.some(station => JSON.stringify(
    line.displayStationCoordinates?.[station[0]] || [station[2], station[3]]) ===
    JSON.stringify(reviewed.junction)));
});

test('owner changes only reviewed display fields and preserves physical identity, mileage, and unrelated data', () => {
  const e = evidenceFixture(), before = packageFixture(e), candidate = candidateFixture(e);
  const originals = Object.fromEntries(LEGAL_LINE_IDS.map(lineID => {
    const index = e.baseline.packageIndices[lineID]; return [lineID, structuredClone(before.lines[index])];
  }));
  const after = repairPackage(before, e, candidate);
  for (const lineID of DIRECT_LINE_IDS) {
    const index = e.baseline.packageIndices[lineID], line = after.lines[index], original = originals[lineID];
    assert.deepEqual(line.stations, original.stations);
    assert.deepEqual(line.segments, original.segments);
    assert.deepEqual(network.decodeIntervals(line), network.decodeIntervals(original));
    assert.deepEqual(Object.keys(line.displayIntervalCoordinates).map(Number),
      e.owners[lineID].intervalIndexes);
    assert.deepEqual(Object.keys(line.displayStationCoordinates).sort(),
      [...e.owners[lineID].stationIDs].sort());
  }
  for (const lineID of LEGAL_LINE_IDS.filter(id => !DIRECT_LINE_IDS.includes(id))) {
    const index = e.baseline.packageIndices[lineID];
    assert.deepEqual(after.lines[index], originals[lineID]);
  }
  assert.deepEqual(after.lines.at(-1), before.lines.at(-1));
  assert.deepEqual(after.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.equal(after.geometrySource.manualOverrides['jounan-west-display'].physicalTopologyChanged, false);
  assert.deepEqual(repairPackage(after, e, candidate), after);
});

test('native rebuild keeps two Jounan parts and introduces no lane, follow, family, or shared reference', () => {
  const { e, pkg, rows } = prepared(), before = laneFixture();
  const after = repairParts(pkg, before, e);
  assert.equal(rows[DIRECT_LINE_IDS[0]].length, 2);
  assert.deepEqual(after.partsByRegion.jp.filter(row => row[0] === DIRECT_LINE_IDS[0]),
    rows[DIRECT_LINE_IDS[0]]);
  for (const key of ['byRegion', 'followsByRegion', 'familyWindowsByRegion',
    'groupWindowsByRegion', 'chainBoundariesByRegion']) assert.deepEqual(after[key], before[key]);
  assert.deepEqual(after.partsByRegion.jp.filter(row => row[0].startsWith('unrelated')),
    before.partsByRegion.jp.filter(row => row[0].startsWith('unrelated')));
  for (const lineID of LEGAL_LINE_IDS.filter(id => !e.lineIDs.includes(id)))
    assert.deepEqual(after.partsByRegion.jp.filter(row => row[0] === lineID),
      before.partsByRegion.jp.filter(row => row[0] === lineID));
  assert.deepEqual(repairParts(pkg, after, e), after);
});

test('reviewed Hanazono lead-in continues north from its own station face and ends on Jounan #2', () => {
  const e = evidenceFixture(), candidate = candidateFixture(e);
  const byLine = Object.fromEntries(candidate.lines.map(record => [record.lineID, record]));
  const hanazono = byLine['jp-伊予鉄道-花園線'];
  const jounan = byLine['jp-伊予鉄道-城南線'];
  const hanazonoInterval = hanazono.candidateIntervals[0].coordinates;
  hanazono.displayStationCoordinates['008768'] = [132.76179275, 33.83907901];
  hanazonoInterval.splice(-2, 2, [132.76179255357147, 33.83901622357143],
    structuredClone(hanazono.displayStationCoordinates['008768']));
  const jounanInterval2 = jounan.candidateIntervals.find(item => item.intervalIndex === 2).coordinates;
  const junction = [132.76179812, 33.83934635];
  jounanInterval2.splice(1, 0, junction);
  hanazono.displayBranchLeadIns = [[structuredClone(hanazono.displayStationCoordinates['008768']),
    junction]];
  const pkg = repairPackage(packageFixture(e), e, candidate);
  const line = pkg.lines[e.baseline.packageIndices[hanazono.lineID]];
  assert.deepEqual(line.displayBranchLeadIns, hanazono.displayBranchLeadIns);
  assert.deepEqual(line.stations, physical(livePackage.lines[e.baseline.packageIndices[hanazono.lineID]]).stations);
  assert.deepEqual(line.segments, physical(livePackage.lines[e.baseline.packageIndices[hanazono.lineID]]).segments);
  const rows = deriveNativeRows(pkg, e);
  assert.equal(rows[hanazono.lineID].length, 2);
  assert.deepEqual(network.displayPartsForLine(line).at(-1), hanazono.displayBranchLeadIns[0]);
  e.nativeReplay = { candidateRowsSha256: Object.fromEntries(e.lineIDs.map(lineID =>
    [lineID, hash(rows[lineID])])) };
  const before = laneFixture(), after = repairParts(pkg, before, e);
  assert.deepEqual(after.partsByRegion.jp.filter(row => row[0] === hanazono.lineID),
    rows[hanazono.lineID]);
  for (const key of ['byRegion', 'followsByRegion', 'familyWindowsByRegion',
    'groupWindowsByRegion', 'chainBoundariesByRegion']) assert.deepEqual(after[key], before[key]);
});

test('candidate export is restricted to evidence-selected legal owners and reviewed windows', () => {
  const { e, pkg } = prepared(), geo = candidateGeoJSON(pkg, e);
  assert.equal(geo.type, 'FeatureCollection');
  assert.deepEqual(geo.features.map(feature =>
    [feature.properties.lineID, feature.properties.referenceIntervalIndex]),
  e.lineIDs.flatMap(lineID => e.owners[lineID].intervalIndexes.map(index => [lineID, index])));
});

test('wrong seam, expanded ownership, stale physical/native data, and introduced follows fail closed', () => {
  const e = evidenceFixture(), candidate = candidateFixture(e);
  const badSeam = structuredClone(candidate);
  badSeam.lines[0].candidateIntervals[1].coordinates[2][0] += .0001;
  assert.throws(() => validateCandidate(badSeam, e), /exact reversed/);
  const expanded = structuredClone(candidate);
  expanded.lines[1].displayStationCoordinates['not-a-station'] = [0, 0];
  assert.throws(() => validateCandidate(expanded, e), /station ownership/);
  const stalePackage = packageFixture(e);
  stalePackage.lines[e.baseline.packageIndices[DIRECT_LINE_IDS[0]]].segments[0][0] += .001;
  assert.throws(() => repairPackage(stalePackage, e, candidate), /physical dependency/);
  const { pkg, e: ready } = prepared();
  const staleNative = laneFixture();
  staleNative.partsByRegion.jp.find(row => row[0] === DIRECT_LINE_IDS[0])[5] += 1;
  assert.throws(() => repairParts(pkg, staleNative, ready), /native dependency/);
  const introduced = laneFixture();
  introduced.followsByRegion.jp.push([DIRECT_LINE_IDS[0], 0, 0, 1, 'other', 0, 0, 1]);
  assert.throws(() => repairParts(pkg, introduced, ready), /measured reference/);
});

test('evidence may add a bounded related-line terminal owner without opening other intervals', () => {
  const e = evidenceFixture(), lineID = 'jp-伊予鉄道-城北線';
  const terminalIndex = e.baseline.intervalCounts[lineID] - 1;
  e.owners[lineID] = { intervalIndexes: [terminalIndex],
    stationIDs: [e.baseline.stationIDs[lineID].at(-1)] };
  e.lineIDs = LEGAL_LINE_IDS.filter(id => e.owners[id]);
  const candidate = candidateFixture(e), before = packageFixture(e);
  const after = repairPackage(before, e, candidate), line = after.lines[e.baseline.packageIndices[lineID]];
  assert.deepEqual(Object.keys(line.displayIntervalCoordinates).map(Number), [terminalIndex]);
  assert.deepEqual(Object.keys(line.displayStationCoordinates), e.owners[lineID].stationIDs);
  for (const index of Array.from({ length: terminalIndex }, (_, value) => value))
    assert.equal(line.displayIntervalCoordinates[index], undefined);
  const rows = deriveNativeRows(after, e);
  assert(rows[lineID].length > 0);
});

test('missing frozen artifact remains a hard candidate-generation failure', () => {
  const e = evidenceFixture();
  e.candidate.manifest = 'docs/does-not-exist/jounan-manifest.json';
  e.candidate.manifestSha256 = '0'.repeat(64);
  assert.throws(() => loadReviewedCandidate(e), /Missing frozen Jounan manifest/);
});

test('candidate-only evidence cannot pass the apply gate', () => {
  const pending = evidenceFixture();
  pending.status = 'candidate-only';
  assert.throws(() => assertApplyAccepted(pending),
    /accepted three-Inspector and Main receipts/);
});

test('accepted apply requires immutable complete three-Inspector and Main receipts', t => {
  const e = evidenceFixture(), directory = fs.mkdtempSync(path.join(os.tmpdir(), 'jtm-jounan-gate-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const bytesHash = value => crypto.createHash('sha256').update(value).digest('hex');
  const write = (name, contents) => {
    const file = path.join(directory, name), bytes = Buffer.from(contents);
    fs.writeFileSync(file, bytes); return { file, sha256: bytesHash(bytes) };
  };
  const counts = {
    'jp-伊予鉄道-城南線': [2, 2, 3, 2, 3, 3, 2, 2, 3, 3, 2],
    'jp-伊予鉄道-城北線': [2, 2, 3, 3, 2, 2, 3, 3],
    'jp-伊予鉄道-大手町線': [2, 3, 2, 3],
    'jp-伊予鉄道-本町線': [2, 2, 2, 3],
    'jp-伊予鉄道-花園線': [3],
    'jp-伊予鉄道-連絡線': [2],
  };
  const intervals = ACCEPTANCE_LINE_IDS.flatMap(lineID => counts[lineID].map((capturedCount, index) =>
    ({ itemID: `${lineID}#${index}`, capturedCount, pendingCount: 0, failedCount: 0,
      viewpointCount: capturedCount })));
  const reportText = JSON.stringify({ intervals, capturedCount: 71, pendingCount: 0,
    failedCount: 0, viewpointCount: 71 });
  const inspectorReports = ['primary', 'secondary', 'third'].map(id => {
    const report = write(`${id}-report.json`, reportText);
    const review = write(`${id}-review.md`, `# ${id}\n\nACCEPT complete 29/71/213 scope.\n`);
    return { id, reportFile: report.file, reportSha256: report.sha256,
      reviewFile: review.file, reviewSha256: review.sha256 };
  });
  const main = write('main-review.md', '# Main\n\nACCEPT complete six-line scope.\n');
  e.status = e.policy.acceptanceGate;
  e.candidate.candidateSha256 = 'a'.repeat(64);
  e.acceptanceScope.candidateViewpointCount = 71;
  e.acceptanceScope.candidateReport = { candidateSha256: e.candidate.candidateSha256,
    lineIDs: ACCEPTANCE_LINE_IDS, intervalCount: 29, viewpointCount: 71, panelCount: 213,
    inspectorReports, mainReceipt: { file: main.file, sha256: main.sha256,
      coverage: { lineIDs: ACCEPTANCE_LINE_IDS, intervalCount: 29, completeIntervals: true,
        sharedStationDirections: true, fullLineContext: true } } };
  assert.doesNotThrow(() => assertApplyAccepted(e));
  const missing = structuredClone(e);
  missing.acceptanceScope.candidateReport.inspectorReports[0].reportFile =
    path.join(directory, 'missing-report.json');
  assert.throws(() => assertApplyAccepted(missing), /Missing Jounan primary Inspector report/);
  fs.appendFileSync(inspectorReports[1].reviewFile, 'mutated');
  assert.throws(() => assertApplyAccepted(e), /secondary Inspector review changed/);
});
