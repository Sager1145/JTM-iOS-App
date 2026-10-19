#!/usr/bin/env node
// Replay one reviewed switchback protection and its existing measured dependants.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';

const require = createRequire(import.meta.url);
const RailNetwork = require('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const EVIDENCE = path.join(ROOT, 'scripts/railway/nihongi-switchback-evidence.json');
const POLICY = 'nihongi-switchback-display';
export const LINE = 'jp-えちごトキめき鉄道-妙高はねうまライン';
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const readEvidence = () => JSON.parse(fs.readFileSync(EVIDENCE));
const round = value => Number(value.toFixed(1));

function distance(a, b) {
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
    (b[1] - a[1]) * 111320);
}

function length(points) {
  return points.slice(1).reduce((total, point, i) => total + distance(points[i], point), 0);
}

function reviewedLine(pkg, evidence) {
  assert.equal(evidence.format, 'jtm-nihongi-switchback-v1');
  assert.equal(evidence.lineId, LINE);
  const line = pkg.lines.find(row => row.id === LINE);
  assert(line, 'Nihongi line is missing');
  assert.equal(line.stations[2][0], evidence.stationCode, 'Nihongi source changed: station identity');
  assert.deepEqual(line.stations.slice(1, 4).map(row => row[1]), ['関山', '二本木', '新井']);
  assert.deepEqual(line.stations[2].slice(2, 4), evidence.station, 'Nihongi source changed: station coordinate');
  const intervals = RailNetwork.decodeIntervals(line);
  assert.deepEqual(intervals[1].slice(-evidence.incomingTail.length), evidence.incomingTail,
    'Nihongi source changed: incoming track');
  assert.deepEqual(intervals[2].slice(0, evidence.outgoingPrefix.length), evidence.outgoingPrefix,
    'Nihongi source changed: outgoing track');
  assert(evidence.outgoingPrefix.some(point => same(point, evidence.protectedExtent)),
    'Nihongi protection must name an existing surveyed vertex');
  assert(!line.displayStationCoordinates && !line.displayIntervalCoordinates && !line.displayBranchLeadIns,
    'Nihongi display inputs changed; review the switchback again');
  return line;
}

export function repairPackage(input, evidence = readEvidence()) {
  const pkg = structuredClone(input);
  const line = reviewedLine(pkg, evidence);
  const protection = [evidence.protectedExtent];
  assert(!line.reversalTails?.length || equal(line.reversalTails, protection),
    'Nihongi reversal protection changed; review before replacing');
  // This bounds the real switchback's extent. It is not a claimed buffer at
  // the south junction: the train reverses at Nihongi, already a station key.
  line.reversalTails = structuredClone(protection);
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides[POLICY] = {
    reviewedAt: evidence.reviewedAt, crs: evidence.crs,
    script: 'app/scripts/railway/repair-nihongi-switchback.mjs',
    evidence: 'app/scripts/railway/nihongi-switchback-evidence.json',
    operatorEvidence: evidence.operatorEvidence,
    osmEvidence: {
      source: evidence.osmEvidence.source, cache: evidence.osmEvidence.cache,
      centralCache: evidence.osmEvidence.centralCache, coverage: evidence.osmEvidence.coverage,
      fetchedAt: evidence.osmEvidence.fetchedAt, license: evidence.osmEvidence.license,
      wayIds: evidence.osmEvidence.ways.map(way => way.id),
    },
    protectedExtent: evidence.protectedExtent,
    displayPolicy: evidence.displayPolicy,
    revision: evidence.revision,
    transformation: 'Use the reviewed exact short-retrace extent to draw the physical station spur once and keep the main continuous; preserve physical segments, station IDs, coordinates and mileage. Remap the unchanged terminal lane onto the new main part and remove the obsolete identity self-follow. No added geometry or duplicate main lead-in.',
  };
  return pkg;
}

export function repairParts(pkg, input, evidence = readEvidence()) {
  const line = reviewedLine(pkg, evidence);
  assert.deepEqual(line.reversalTails, [evidence.protectedExtent], 'Apply Nihongi package protection first');
  const unprotected = structuredClone(line);
  delete unprotected.reversalTails;
  const beforeParts = RailNetwork.displayPartsForLine(unprotected);
  const afterParts = RailNetwork.displayPartsForLine(line);
  const intervals = RailNetwork.decodeIntervals(line);
  // The first protection-only repair kept the two original station legs.
  // Accept its exact source-backed cache as well as the original and current
  // rows, so this bounded repair can replay from either shipped revision.
  const previousParts = [intervals[0].concat(intervals[1].slice(1)),
    intervals.slice(2).flatMap((points, i) => i ? points.slice(1) : points)];
  assert.deepEqual(afterParts.map(points => points.length), [7, 472], 'Nihongi part topology changed');
  assert.deepEqual(beforeParts[1].slice(0, 2), [evidence.station, evidence.oldDiagonalEnd]);
  assert.deepEqual(afterParts[0], evidence.incomingTail, 'Nihongi physical spur changed');
  const cut = previousParts[0].findIndex(point => same(point, evidence.protectedExtent));
  assert(cut >= 0, 'Nihongi junction is missing');
  const shared = evidence.incomingTail.length;
  assert.deepEqual(previousParts[0].slice(cut).reverse(), previousParts[1].slice(0, shared));
  const main = previousParts[0].slice(0, cut + 1).concat(previousParts[1].slice(shared));
  assert.deepEqual(afterParts[1], main, 'Nihongi through main changed; measures need review');
  const originalRows = partRowsForLine(unprotected, beforeParts, null, null);
  const previousRows = partRowsForLine(line, previousParts, null, null);
  const rows = partRowsForLine(line, afterParts, null, null);
  const lanes = structuredClone(input);
  const cached = lanes.partsByRegion.jp.filter(row => row[0] === LINE);
  assert([originalRows, previousRows, rows].some(known => equal(cached, known)),
    'Nihongi native part topology changed; review before replacing');
  assert(rows.every(row => !row[8]?.length), 'Nihongi withheld measure requires review');

  const oldLane = [LINE, 1, 22100, 22695.4, -0.5];
  const previousLane = [LINE, 1, 22505.6, 23101, -0.5];
  // Both changes alter only the head before the unchanged terminal suffix.
  const delta = length(afterParts[1]) - length(beforeParts[1]);
  const newLane = [LINE, 1, round(oldLane[2] + delta), rows[1][5], -0.5];
  assert.deepEqual(newLane.slice(2), [35929.1, 36524.5, -0.5]);
  let laneCount = 0;
  lanes.byRegion.jp = lanes.byRegion.jp.map(row => {
    if (row[0] !== LINE) return row;
    assert([oldLane, previousLane, newLane].some(known => equal(row, known)),
      'Nihongi affected lane measure requires review');
    laneCount++;
    return newLane;
  });
  assert.equal(laneCount, 1, 'Nihongi terminal lane measure changed');
  for (const row of lanes.familyWindowsByRegion?.jp || [])
    assert(row[0] !== LINE, 'Nihongi affected family-window measure requires review');

  const oldFollow = [LINE, 0, 13950, 14002.021865360595, LINE, 1, 25, 0];
  const previousFollow = [...oldFollow.slice(0, 6), 52.02186536059526, 0];
  assert(Math.abs(length(previousParts[0]) - oldFollow[3]) < 1e-8,
    'Nihongi incoming follow measure changed');
  const originalSpurStart = length(previousParts[0].slice(0, cut + 1));
  assert(oldFollow[2] >= originalSpurStart, 'Nihongi follow reaches outside the physical spur');
  // Both sides of this old self-follow now identify the same spur vertices.
  // Removing it preserves the real reversal for routes without duplicate ink.
  let followCount = 0;
  lanes.followsByRegion.jp = lanes.followsByRegion.jp.filter(row => {
    if (row[0] !== LINE && row[4] !== LINE) return true;
    assert(equal(row, oldFollow) || equal(row, previousFollow),
      'Nihongi affected follow measure requires review');
    followCount++;
    return false;
  });
  assert(followCount <= 1, 'Nihongi duplicate self-follow measure changed');
  if (!equal(cached, rows)) assert.equal(followCount, 1, 'Nihongi self-follow measure is missing');
  lanes.partsByRegion.jp = lanes.partsByRegion.jp.map(row => row[0] === LINE ? rows[row[1]] : row);
  return lanes;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const packagePath = path.join(ROOT, 'public/rail/jp-2025.json');
  const lanesPath = path.join(ROOT, 'public/rail/display-lanes.json');
  const before = fs.readFileSync(packagePath, 'utf8');
  const beforeLanes = fs.readFileSync(lanesPath, 'utf8');
  const pkg = repairPackage(JSON.parse(before));
  const lanes = repairParts(pkg, JSON.parse(beforeLanes));
  const after = JSON.stringify(pkg);
  const afterLanes = `${JSON.stringify(lanes)}\n`;
  if (process.argv.includes('--check')) {
    assert.equal(before.trimEnd(), after, 'Nihongi package protection is stale');
    assert.equal(beforeLanes.trimEnd(), afterLanes.trimEnd(), 'Nihongi native part/measures are stale');
  } else {
    if (before.trimEnd() !== after) fs.writeFileSync(packagePath, after);
    if (beforeLanes.trimEnd() !== afterLanes.trimEnd()) fs.writeFileSync(lanesPath, afterLanes);
  }
  console.log('Nihongi switchback: reviewed protection, native part and existing measures are current');
}
