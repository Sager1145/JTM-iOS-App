#!/usr/bin/env node
// Display-only owner for the six reviewed Matsuyama tram records in the Jounan group.
// Candidate generation stays fail-closed until the frozen evidence manifest is installed.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';
import { refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS }
  from './repair-three-reversal-extents.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const PACKAGE = 'public/rail/jp-2025.json';
const LANES = 'public/rail/display-lanes.json';
const EVIDENCE = 'scripts/railway/jounan-west-display-evidence.json';
const OVERRIDE = 'jounan-west-display';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const jsonSha256 = value => sha256(JSON.stringify(value));

export const LEGAL_LINE_IDS = Object.freeze([
  'jp-伊予鉄道-城南線',
  'jp-伊予鉄道-城北線',
  'jp-伊予鉄道-大手町線',
  'jp-伊予鉄道-本町線',
  'jp-伊予鉄道-花園線',
  'jp-伊予鉄道-連絡線',
]);
export const DIRECT_LINE_IDS = Object.freeze([
  'jp-伊予鉄道-城南線',
  'jp-伊予鉄道-大手町線',
  'jp-伊予鉄道-本町線',
  'jp-伊予鉄道-花園線',
]);
export const ACCEPTANCE_LINE_IDS = LEGAL_LINE_IDS;
const JOUNAN = DIRECT_LINE_IDS[0];
const HANAZONO = 'jp-伊予鉄道-花園線';
const HANAZONO_MINAMI = '008768';
const HANAZONO_JUNCTION_SUPPORT = Object.freeze([132.76179812, 33.83934635]);

function distance(a, b) {
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
    (b[1] - a[1]) * 111320);
}

function bearing(a, b) {
  const latitude = (a[1] + b[1]) * Math.PI / 360;
  const east = (b[0] - a[0]) * Math.cos(latitude);
  const north = b[1] - a[1];
  return (Math.atan2(east, north) * 180 / Math.PI + 360) % 360;
}

function angle(a, b) {
  const difference = Math.abs(a - b) % 360;
  return Math.min(difference, 360 - difference);
}

function artifact(relative, expected, label) {
  const file = path.join(REPO, relative);
  assert(fs.existsSync(file), `Missing frozen Jounan ${label}: ${relative}`);
  assert.equal(sha256(fs.readFileSync(file)), expected, `Frozen Jounan ${label} changed: ${relative}`);
  return file;
}

function receiptArtifact(relative, expected, label) {
  assert(typeof relative === 'string' && relative.length, `Missing Jounan ${label} path`);
  assert.match(expected || '', /^[0-9a-f]{64}$/, `Missing Jounan ${label} SHA-256`);
  const file = path.isAbsolute(relative) ? relative : path.join(REPO, relative);
  assert(fs.existsSync(file), `Missing Jounan ${label}: ${relative}`);
  assert.equal(sha256(fs.readFileSync(file)), expected, `Jounan ${label} changed: ${relative}`);
  return file;
}

function assertKnownStatus(e) {
  const accepted = e.policy?.acceptanceGate;
  assert(e.status === 'candidate-only' || (accepted && e.status === accepted),
    'Unknown Jounan review status');
}

function ownerLineIDs(e) {
  const keys = Object.keys(e.owners || {});
  assert(keys.length, 'Jounan evidence has no reviewed owners');
  for (const lineID of keys)
    assert(LEGAL_LINE_IDS.includes(lineID), `Unknown Jounan-group legal owner: ${lineID}`);
  for (const lineID of DIRECT_LINE_IDS)
    assert(keys.includes(lineID), `Missing direct Jounan owner: ${lineID}`);
  return LEGAL_LINE_IDS.filter(lineID => keys.includes(lineID));
}

function records(candidate, lineIDs) {
  assert(Array.isArray(candidate.lines), 'Jounan candidate lines missing');
  assert.deepEqual(candidate.lines.map(item => item.lineID), lineIDs,
    'Jounan candidate legal-owner order changed');
  return Object.fromEntries(candidate.lines.map(item => [item.lineID, item]));
}

function exactRetrace(interval0, interval1) {
  let count = 0;
  while (count < interval0.length && count < interval1.length &&
    equal(interval0[interval0.length - 1 - count], interval1[count])) count += 1;
  return { count, junction: count ? interval1[count - 1] : null };
}

export function validateCandidate(candidate, e) {
  assertKnownStatus(e);
  assert.equal(candidate.format, e.candidate.format, 'Jounan candidate format changed');
  assert.equal(candidate.status, 'candidate-only', 'Jounan candidate is not review-pending');
  const lineIDs = ownerLineIDs(e);
  assert.deepEqual(e.lineIDs, lineIDs, 'Jounan evidence legal-owner order changed');
  assert.deepEqual(e.acceptanceScope.lineIDs, ACCEPTANCE_LINE_IDS,
    'Jounan complete acceptance lines changed');
  assert.equal(e.acceptanceScope.intervalCount, 29,
    'Jounan complete acceptance interval count changed');
  assert.equal(e.acceptanceScope.baselineViewpointCount, 70,
    'Jounan baseline viewpoint receipt changed');
  if (e.acceptanceScope.candidateViewpointCount != null) {
    assert(Number.isInteger(e.acceptanceScope.candidateViewpointCount) &&
      e.acceptanceScope.candidateViewpointCount > 0 && e.acceptanceScope.candidateReport,
    'Jounan candidate viewpoint count requires its actual report');
    assert.equal(e.acceptanceScope.candidateReport.viewpointCount,
      e.acceptanceScope.candidateViewpointCount,
    'Jounan candidate report count changed');
    assert(Array.isArray(e.acceptanceScope.candidateReport.inspectorReports) &&
      e.acceptanceScope.candidateReport.inspectorReports.length === 3 &&
      e.acceptanceScope.candidateReport.inspectorReports.every(Boolean) &&
      e.acceptanceScope.candidateReport.mainReceipt,
    'Jounan candidate acceptance requires three Inspector reports and Main receipt');
  }
  const byLine = records(candidate, lineIDs);
  for (const lineID of lineIDs) {
    const record = byLine[lineID], owner = e.owners[lineID];
    const intervalCount = e.baseline.intervalCounts[lineID];
    const stationIDs = e.baseline.stationIDs[lineID];
    assert(Number.isInteger(intervalCount) && intervalCount > 0,
      `Missing Jounan interval bound: ${lineID}`);
    assert(Array.isArray(stationIDs) && stationIDs.length === intervalCount + 1,
      `Missing Jounan station bound: ${lineID}`);
    assert(owner.intervalIndexes.length && owner.stationIDs.length,
      `Empty reviewed Jounan owner: ${lineID}`);
    assert.deepEqual(owner.intervalIndexes,
      [...new Set(owner.intervalIndexes)].sort((a, b) => a - b),
    `Invalid Jounan interval ownership: ${lineID}`);
    assert(owner.intervalIndexes.every(index => Number.isInteger(index) && index >= 0 && index < intervalCount),
      `Out-of-range Jounan interval ownership: ${lineID}`);
    assert.deepEqual(owner.stationIDs, [...new Set(owner.stationIDs)],
      `Duplicate Jounan station ownership: ${lineID}`);
    assert(owner.stationIDs.every(stationID => stationIDs.includes(stationID)),
      `Out-of-range Jounan station ownership: ${lineID}`);
    if (DIRECT_LINE_IDS.includes(lineID)) {
      assert.deepEqual(owner.intervalIndexes, Array.from({ length: intervalCount }, (_, index) => index),
        `Direct Jounan owner is not a complete line: ${lineID}`);
      assert.deepEqual(owner.stationIDs, stationIDs,
        `Direct Jounan station ownership is not complete: ${lineID}`);
    }
    for (const stationID of owner.stationIDs) {
      const stationIndex = stationIDs.indexOf(stationID);
      const adjacent = [stationIndex - 1, stationIndex].filter(index => index >= 0 && index < intervalCount);
      assert(adjacent.every(index => owner.intervalIndexes.includes(index)),
        `Moved Jounan station lacks adjacent reviewed interval: ${lineID}:${stationID}`);
    }
    assert.deepEqual(record.candidateIntervals.map(item => item.intervalIndex), owner.intervalIndexes,
      `Jounan candidate interval ownership changed: ${lineID}`);
    assert.deepEqual(Object.keys(record.displayStationCoordinates).sort(), [...owner.stationIDs].sort(),
      `Jounan candidate station ownership changed: ${lineID}`);
    for (const item of record.candidateIntervals) {
      assert(item.coordinates.length >= 2, `Short Jounan interval: ${lineID}#${item.intervalIndex}`);
      for (const point of item.coordinates)
        assert(Array.isArray(point) && point.length === 2 && point.every(Number.isFinite),
          `Invalid Jounan point: ${lineID}#${item.intervalIndex}`);
      for (let index = 1; index < item.coordinates.length; index += 1)
        assert(distance(item.coordinates[index - 1], item.coordinates[index]) > 0,
          `Zero-length Jounan edge: ${lineID}#${item.intervalIndex}`);
    }
    for (const stationID of owner.stationIDs) {
      const point = record.displayStationCoordinates[stationID];
      assert(Array.isArray(point) && point.length === 2 && point.every(Number.isFinite),
        `Invalid Jounan station alias: ${lineID}:${stationID}`);
    }
  }
  const jounan = byLine[JOUNAN];
  const interval0 = jounan.candidateIntervals[0].coordinates;
  const interval1 = jounan.candidateIntervals[1].coordinates;
  const seam = exactRetrace(interval0, interval1);
  assert(seam.count >= 3 && seam.count < interval0.length && seam.count < interval1.length,
    'Jounan west arm must be an exact reversed >=3-point partial retrace');
  assert(!Object.values(jounan.displayStationCoordinates).some(point => equal(point, seam.junction)),
    'Jounan open-track junction became a station alias');
  const recordsWithLeadIns = lineIDs.filter(lineID =>
    byLine[lineID].displayBranchLeadIns != null);
  assert(recordsWithLeadIns.every(lineID => lineID === HANAZONO),
    'Only Hanazono may own the reviewed Jounan branch lead-in');
  const hanazono = byLine[HANAZONO];
  if (hanazono?.displayBranchLeadIns != null) {
    assert.deepEqual(recordsWithLeadIns, [HANAZONO],
      'Reviewed Hanazono branch lead-in ownership changed');
    assert(Array.isArray(hanazono.displayBranchLeadIns) &&
      hanazono.displayBranchLeadIns.length === 1,
    'Hanazono must have exactly one reviewed branch lead-in');
    const lead = hanazono.displayBranchLeadIns[0];
    assert(Array.isArray(lead) && lead.length === 2 &&
      lead.every(point => Array.isArray(point) && point.length === 2 && point.every(Number.isFinite)),
    'Hanazono branch lead-in must be the reviewed straight path');
    assert.deepEqual(lead[0], hanazono.displayStationCoordinates[HANAZONO_MINAMI],
      'Hanazono branch lead-in lost its own Minami station face');
    assert.deepEqual(lead[1], HANAZONO_JUNCTION_SUPPORT,
      'Hanazono branch lead-in lost the reviewed Apple junction support');
    const interval2 = jounan.candidateIntervals.find(item => item.intervalIndex === 2)?.coordinates;
    assert(interval2?.some(point => equal(point, lead[1])),
      'Hanazono branch lead-in does not end at the literal Jounan #2 Apple junction');
    const hanazonoInterval = hanazono.candidateIntervals.find(item => item.intervalIndex === 0)?.coordinates;
    assert(hanazonoInterval?.length >= 2 &&
      angle(bearing(hanazonoInterval.at(-2), lead[0]), bearing(lead[0], lead[1])) < 2,
    'Hanazono branch lead-in reverses its own northbound station approach');
    assert(distance(lead[0], lead[1]) > 20 && distance(lead[0], lead[1]) < 35,
      'Hanazono branch lead-in north-south support span changed');
  }
  return { candidate, records: byLine, lineIDs, junction: seam.junction,
    retracePointCount: seam.count };
}

export function loadReviewedCandidate(e) {
  assertKnownStatus(e);
  const manifestFile = artifact(e.candidate.manifest, e.candidate.manifestSha256, 'manifest');
  const manifest = JSON.parse(fs.readFileSync(manifestFile));
  assert.equal(manifest.format, e.candidate.manifestFormat, 'Jounan manifest format changed');
  for (const item of manifest.files) {
    const file = path.join(path.dirname(manifestFile), item.path);
    assert.equal(sha256(fs.readFileSync(file)), item.sha256,
      `Frozen Jounan artifact changed: ${item.path}`);
  }
  const candidateFile = artifact(e.candidate.candidateFile, e.candidate.candidateSha256, 'candidate');
  return validateCandidate(JSON.parse(fs.readFileSync(candidateFile)), e);
}

function strippedPhysicalLine(line) {
  const result = structuredClone(line);
  delete result.displayIntervalCoordinates;
  delete result.displayStationCoordinates;
  delete result.displayBranchLeadIns;
  return result;
}

function ownedSubset(object, keys) {
  return Object.fromEntries(keys.filter(key => object?.[key] != null).map(key => [key, object[key]]));
}

function unownedSubset(object, keys) {
  const owned = new Set(keys.map(String));
  return Object.fromEntries(Object.entries(object || {}).filter(([key]) => !owned.has(key)));
}

function physicalLine(current, e, lineID) {
  const line = strippedPhysicalLine(current);
  assert.equal(jsonSha256(line), e.baseline.lineSha256[lineID],
    `Unreviewed Jounan physical dependency changed: ${lineID}`);
  assert.equal(line.segments.length, e.baseline.intervalCounts[lineID],
    `Jounan interval bound changed: ${lineID}`);
  assert.deepEqual(line.stations.map(row => row[0]), e.baseline.stationIDs[lineID],
    `Jounan station identity bound changed: ${lineID}`);
  return line;
}

function effectiveStationPoint(line, aliases, stationID) {
  if (aliases[stationID]) return aliases[stationID];
  const station = line.stations.find(row => row[0] === stationID);
  assert(station, `Missing Jounan station: ${line.id}:${stationID}`);
  return [station[2], station[3]];
}

function repairedLine(current, record, e, junction) {
  const lineID = current.id, owner = e.owners[lineID], physical = physicalLine(current, e, lineID);
  assert.deepEqual(unownedSubset(current.displayIntervalCoordinates, owner.intervalIndexes),
    e.baseline.unownedDisplayIntervals[lineID], `Unreviewed Jounan display interval changed: ${lineID}`);
  assert.deepEqual(unownedSubset(current.displayStationCoordinates, owner.stationIDs),
    e.baseline.unownedDisplayStations[lineID], `Unreviewed Jounan display station changed: ${lineID}`);
  const candidateLeadIns = structuredClone(record.displayBranchLeadIns || []);
  assert(!current.displayBranchLeadIns || equal(current.displayBranchLeadIns, candidateLeadIns),
    `Unreviewed Jounan branch lead-in changed: ${lineID}`);
  const candidateIntervals = Object.fromEntries(record.candidateIntervals.map(item =>
    [item.intervalIndex, structuredClone(item.coordinates)]));
  const currentOwnedIntervals = ownedSubset(current.displayIntervalCoordinates, owner.intervalIndexes);
  const currentOwnedStations = ownedSubset(current.displayStationCoordinates, owner.stationIDs);
  assert(!Object.keys(currentOwnedIntervals).length || equal(currentOwnedIntervals, candidateIntervals),
    `Unreviewed Jounan owned interval changed: ${lineID}`);
  assert(!Object.keys(currentOwnedStations).length ||
    equal(currentOwnedStations, record.displayStationCoordinates),
  `Unreviewed Jounan owned station changed: ${lineID}`);
  const aliases = { ...e.baseline.unownedDisplayStations[lineID],
    ...structuredClone(record.displayStationCoordinates) };
  const intervals = { ...e.baseline.unownedDisplayIntervals[lineID], ...candidateIntervals };
  for (const item of record.candidateIntervals) {
    const fromID = physical.stations[item.intervalIndex][0];
    const toID = physical.stations[item.intervalIndex + 1][0];
    assert.deepEqual(item.coordinates[0], effectiveStationPoint(physical, aliases, fromID),
      `Jounan interval start is not its own station: ${lineID}#${item.intervalIndex}`);
    assert.deepEqual(item.coordinates.at(-1), effectiveStationPoint(physical, aliases, toID),
      `Jounan interval end is not its own station: ${lineID}#${item.intervalIndex}`);
  }
  const result = structuredClone(physical);
  if (Object.keys(aliases).length) result.displayStationCoordinates = aliases;
  if (Object.keys(intervals).length) result.displayIntervalCoordinates = intervals;
  if (candidateLeadIns.length) result.displayBranchLeadIns = candidateLeadIns;
  assert.deepEqual(result.stations, physical.stations);
  assert.deepEqual(result.segments, physical.segments);
  assert.deepEqual(network.decodeIntervals(result), network.decodeIntervals(physical));
  if (lineID === JOUNAN) {
    const parts = network.displayPartsForLine(result);
    assert.equal(parts.length, 2, 'Jounan display must remain exactly two parts');
    const h1 = effectiveStationPoint(physical, aliases, '008756');
    const nishi = effectiveStationPoint(physical, aliases, '008761');
    assert.deepEqual(parts[0][0], junction, 'Jounan west part lost the open-track junction');
    assert.deepEqual(parts[0].at(-1), nishi, 'Jounan west part lost Nishi-Horibata');
    assert.deepEqual(parts[1][0], h1, 'Jounan through part lost Hommachi-itchome');
    assert(parts[1].some(point => equal(point, junction)), 'Jounan through part lost its junction');
    assert(!parts[1].some(point => equal(point, nishi)),
      'Jounan through part incorrectly retained the west station excursion');
    assert(!result.stations.some(station =>
      equal(result.displayStationCoordinates?.[station[0]] || [station[2], station[3]], junction)),
      'Jounan open-track junction became a station');
  }
  return result;
}

function metadata(e) {
  return { reviewedAt: e.reviewedAt, status: e.status, lineIDs: ownerLineIDs(e),
    acceptanceScope: e.acceptanceScope, candidate: e.candidate,
    script: 'app/scripts/railway/repair-jounan-west-display.mjs',
    evidence: 'app/scripts/railway/jounan-west-display-evidence.json',
    physicalTopologyChanged: false };
}

export function repairPackage(input, e, suppliedCandidate = null) {
  const reviewed = suppliedCandidate ? validateCandidate(suppliedCandidate, e) : loadReviewedCandidate(e);
  const result = structuredClone(input);
  for (const lineID of LEGAL_LINE_IDS) {
    const index = e.baseline.packageIndices[lineID], current = input.lines[index];
    assert.equal(current?.id, lineID, `Jounan package index changed: ${lineID}`);
    physicalLine(current, e, lineID);
    const owner = e.owners[lineID];
    if (!owner) {
      assert.deepEqual(current.displayIntervalCoordinates || {},
        e.baseline.unownedDisplayIntervals[lineID],
      `Unreviewed related Jounan interval changed: ${lineID}`);
      assert.deepEqual(current.displayStationCoordinates || {},
        e.baseline.unownedDisplayStations[lineID],
      `Unreviewed related Jounan station changed: ${lineID}`);
    }
  }
  for (const lineID of reviewed.lineIDs) {
    const index = e.baseline.packageIndices[lineID], current = input.lines[index];
    result.lines[index] = repairedLine(current, reviewed.records[lineID], e, reviewed.junction);
  }
  result.geometrySource ||= {};
  result.geometrySource.manualOverrides ||= {};
  const allAlreadyRepaired = reviewed.lineIDs.every(lineID => {
    const index = e.baseline.packageIndices[lineID];
    return equal(input.lines[index], result.lines[index]);
  });
  if (allAlreadyRepaired && input.geometrySource.manualOverrides[OVERRIDE])
    assert.deepEqual(input.geometrySource.manualOverrides[OVERRIDE], metadata(e),
      'Accepted Jounan metadata changed');
  result.geometrySource.manualOverrides[OVERRIDE] = metadata(e);
  return result;
}

function displayInputs(line) {
  const displayed = { ...line,
    stations: line.stations.map(station => line.displayStationCoordinates?.[station[0]]
      ? [...station.slice(0, 2), ...line.displayStationCoordinates[station[0]], ...station.slice(4)]
      : station),
    segments: line.segments.map((segment, index) => line.displayIntervalCoordinates?.[index]
      ? [segment[0], 0, line.displayIntervalCoordinates[index]] : segment) };
  return { stations: displayed.stations, intervals: network.decodeIntervals(displayed) };
}

function measuredReferences(input) {
  const includesID = value => LEGAL_LINE_IDS.some(id => JSON.stringify(value).includes(id));
  const found = {};
  for (const [key, value] of Object.entries(input)) {
    if (key === 'partsByRegion') continue;
    const region = value?.jp;
    if (Array.isArray(region)) {
      const rows = region.filter(includesID);
      if (rows.length) found[key] = rows;
    } else if (region && typeof region === 'object') {
      const rows = Object.fromEntries(Object.entries(region).filter(([name, row]) =>
        LEGAL_LINE_IDS.includes(name) || includesID(row)));
      if (Object.keys(rows).length) found[key] = rows;
    }
  }
  return found;
}

export function deriveNativeRows(pkg, e) {
  const rows = {};
  for (const lineID of ownerLineIDs(e)) {
    const line = pkg.lines[e.baseline.packageIndices[lineID]];
    rows[lineID] = partRowsForLine(line, network.displayPartsForLine(line), displayInputs(line), null);
  }
  assert.equal(rows[JOUNAN].length, 2, 'Jounan native display must remain two parts');
  const hanazono = pkg.lines[e.baseline.packageIndices[HANAZONO]];
  assert.equal(rows[HANAZONO].length, hanazono.displayBranchLeadIns?.length ? 2 : 1,
    'Hanazono native display part count does not match its reviewed branch lead-in');
  return rows;
}

function replaceLineRows(rows, replacements, lineIDs) {
  const result = structuredClone(rows);
  for (const lineID of lineIDs) {
    const indexes = result.flatMap((row, index) => row[0] === lineID ? [index] : []);
    assert(indexes.length, `Missing Jounan group native rows: ${lineID}`);
    assert(indexes.every((index, offset) => index === indexes[0] + offset),
      `Non-contiguous Jounan native rows: ${lineID}`);
    result.splice(indexes[0], indexes.length, ...replacements[lineID]);
  }
  return result;
}

export function repairParts(pkg, input, e) {
  assert(e.nativeReplay, 'Missing reviewed Jounan native replay evidence');
  assert.deepEqual(measuredReferences(input), e.baseline.measuredReferences,
    'Unreviewed Jounan measured reference');
  const replacements = deriveNativeRows(pkg, e);
  const lineIDs = ownerLineIDs(e);
  for (const lineID of lineIDs) {
    const current = input.partsByRegion.jp.filter(row => row[0] === lineID);
    const currentHash = jsonSha256(current), expected = e.nativeReplay.candidateRowsSha256[lineID];
    assert([e.baseline.nativeRowsSha256[lineID], expected].includes(currentHash),
      `Unreviewed Jounan native dependency changed: ${lineID}`);
    assert.equal(jsonSha256(replacements[lineID]), expected,
      `Jounan native owning replay changed: ${lineID}`);
  }
  const result = structuredClone(input);
  result.partsByRegion.jp = replaceLineRows(result.partsByRegion.jp, replacements, lineIDs);
  assert.deepEqual(measuredReferences(result), e.baseline.measuredReferences,
    'Jounan repair introduced a lane, follow, family, or shared reference');
  return result;
}

export function candidateGeoJSON(pkg, e) {
  return { type: 'FeatureCollection', features: ownerLineIDs(e).flatMap(lineID => {
    const line = pkg.lines[e.baseline.packageIndices[lineID]];
    return e.owners[lineID].intervalIndexes.map(intervalIndex => ({ type: 'Feature',
      properties: { lineID, referenceLineID: lineID, intervalIndex,
        referenceIntervalIndex: intervalIndex, status: e.status,
        representation: e.policy.representation },
      geometry: { type: 'LineString', coordinates: line.displayIntervalCoordinates[intervalIndex] } }));
  }) };
}

function expectedIntervalIDs(e) {
  return e.acceptanceScope.lineIDs.flatMap(lineID =>
    Array.from({ length: e.baseline.intervalCounts[lineID] }, (_, index) => `${lineID}#${index}`));
}

export function assertApplyAccepted(e) {
  assert.equal(e.status, e.policy?.acceptanceGate,
    'Jounan candidate requires accepted three-Inspector and Main receipts before apply');
  const scope = e.acceptanceScope, report = scope.candidateReport;
  assert.equal(scope.candidateViewpointCount, 71,
    'Jounan accepted candidate viewpoint count must be the actual 71-view plan');
  assert(report && typeof report === 'object', 'Missing Jounan candidate acceptance report');
  assert.deepEqual({ candidateSha256: report.candidateSha256,
    lineIDs: report.lineIDs, intervalCount: report.intervalCount,
    viewpointCount: report.viewpointCount, panelCount: report.panelCount },
  { candidateSha256: e.candidate.candidateSha256,
    lineIDs: ACCEPTANCE_LINE_IDS, intervalCount: 29, viewpointCount: 71, panelCount: 213 },
  'Jounan candidate acceptance coverage changed');
  assert(Array.isArray(report.inspectorReports) && report.inspectorReports.length === 3,
    'Jounan apply requires three Inspector report/review receipts');
  assert.deepEqual(report.inspectorReports.map(item => item.id).sort(),
    ['primary', 'secondary', 'third'], 'Jounan Inspector receipt identities changed');
  const expectedIDs = expectedIntervalIDs(e).sort();
  for (const item of report.inspectorReports) {
    const reportFile = receiptArtifact(item.reportFile, item.reportSha256,
      `${item.id} Inspector report`);
    receiptArtifact(item.reviewFile, item.reviewSha256, `${item.id} Inspector review`);
    const actual = JSON.parse(fs.readFileSync(reportFile));
    assert.deepEqual({ capturedCount: actual.capturedCount, pendingCount: actual.pendingCount,
      failedCount: actual.failedCount, viewpointCount: actual.viewpointCount },
    { capturedCount: 71, pendingCount: 0, failedCount: 0, viewpointCount: 71 },
    `Jounan ${item.id} Inspector capture coverage changed`);
    assert(Array.isArray(actual.intervals) && actual.intervals.length === 29,
      `Jounan ${item.id} Inspector interval coverage changed`);
    assert.deepEqual(actual.intervals.map(interval => interval.itemID).sort(), expectedIDs,
      `Jounan ${item.id} Inspector identities changed`);
  }
  const main = report.mainReceipt;
  assert(main && typeof main === 'object', 'Missing Jounan Main receipt');
  receiptArtifact(main.file, main.sha256, 'Main review receipt');
  assert.deepEqual(main.coverage, { lineIDs: ACCEPTANCE_LINE_IDS, intervalCount: 29,
    completeIntervals: true, sharedStationDirections: true, fullLineContext: true },
  'Jounan Main review coverage changed');
}

function readJSON(relative) {
  return JSON.parse(fs.readFileSync(path.join(ROOT, relative)));
}

export function prepare(args) {
  const candidate = args[0] === '--candidate-root' && args.length === 2;
  const apply = equal(args, ['--apply']);
  assert(candidate || apply,
    'Usage: node repair-jounan-west-display.mjs (--candidate-root /private/tmp/<dir> | --apply)');
  assert(fs.existsSync(path.join(ROOT, EVIDENCE)),
    'Missing reviewed Jounan evidence/artifact; candidate generation remains blocked');
  const paths = { package: PACKAGE, lanes: LANES, evidence: EVIDENCE, ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative);
    return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const load = key => JSON.parse(snapshots[key].before), e = load('evidence');
  if (apply) assertApplyAccepted(e);
  const reviewed = loadReviewedCandidate(e), manifestPath = path.join(REPO, e.candidate.manifest);
  const sourceDirectory = path.dirname(manifestPath);
  const sources = [{ path: manifestPath, before: fs.readFileSync(manifestPath) },
    ...JSON.parse(fs.readFileSync(manifestPath)).files.map(item => {
      const file = path.join(sourceDirectory, item.path);
      return { path: file, before: fs.readFileSync(file) };
    })];
  assert(reviewed);
  const pkg = repairPackage(load('package'), e), lanes = repairParts(pkg, load('lanes'), e);
  const dependencies = refreshDependencyReferences(pkg,
    Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
  return { candidate: candidate ? path.resolve(args[1]) : null, apply, snapshots, sources,
    e, pkg, lanes, dependencies };
}

function main(args = process.argv.slice(2)) {
  const prepared = prepare(args);
  const outputs = { package: JSON.stringify(prepared.pkg),
    lanes: JSON.stringify(prepared.lanes) + '\n',
    ...Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key =>
      [key, JSON.stringify(prepared.dependencies[key], null, 2) + '\n'])) };
  if (prepared.candidate) {
    assert(prepared.candidate.startsWith('/private/tmp/'), 'Candidate root must be under /private/tmp');
    fs.mkdirSync(prepared.candidate, { recursive: true });
    for (const [key, contents] of Object.entries(outputs))
      fs.writeFileSync(path.join(prepared.candidate,
        path.basename(prepared.snapshots[key].path)), contents);
    fs.writeFileSync(path.join(prepared.candidate, 'jounan-west-display.geojson'),
      JSON.stringify(candidateGeoJSON(prepared.pkg, prepared.e), null, 2) + '\n');
  } else {
    const writes = Object.entries(outputs)
      .filter(([key, contents]) => contents !== prepared.snapshots[key].before)
      .map(([key, contents]) => ({ path: prepared.snapshots[key].path,
        before: prepared.snapshots[key].before, after: contents,
        temporary: `${prepared.snapshots[key].path}.jounan-west-${process.pid}.tmp` }));
    applyPreparedWrites(writes, [...Object.values(prepared.snapshots), ...prepared.sources]);
  }
  const lineIDs = ownerLineIDs(prepared.e);
  console.log(JSON.stringify({ mode: prepared.apply ? 'applied' : 'candidate',
    status: prepared.e.status, lineIDs,
    nativePartCounts: Object.fromEntries(lineIDs.map(lineID =>
      [lineID, prepared.lanes.partsByRegion.jp.filter(row => row[0] === lineID).length])),
    physicalTopologyChanged: false }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
