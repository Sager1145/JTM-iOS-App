#!/usr/bin/env node
// Bounded display repair; canonical topology, stations and mileage stay intact.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';

const require = createRequire(import.meta.url);
const RailNetwork = require('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const EVIDENCE = path.join(ROOT, 'scripts/railway/tabata-curve-overrides.json');
const POLICY = 'tabata-yamanote-display-curve';
export const LINE = 'jp-東日本旅客鉄道-山手線';
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];

export function surveyedPath(evidence) {
  const points = [];
  for (const id of evidence.path) {
    const way = evidence.ways[id];
    assert(way.tags.name === '山手線' && way.tags.railway === 'rail' && way.tags.oneway === 'yes');
    if (points.length) assert(same(points.at(-1), way.coordinates[0]), 'Disconnected surveyed ways');
    points.push(...way.coordinates.slice(points.length ? 1 : 0));
  }
  const direction = evidence.directionEvidence;
  assert(same(points.at(-1), direction.connectingWay.coordinates[0]), 'Disconnected directional continuation');
  assert(same(direction.connectingWay.coordinates.at(-1), direction.adjoiningWay.firstCoordinate));
  assert.equal(direction.adjoiningWay.trackRef, '山手線 : 外回り');
  return points;
}

export function repairPackage(input, evidence) {
  const pkg = structuredClone(input);
  const line = pkg.lines.find(row => row.id === LINE);
  assert(line && evidence.lineId === LINE && evidence.interval === 15);
  assert.deepEqual(line.stations.slice(15, 17).map(row => row[1]), ['駒込', '田端']);
  const original = RailNetwork.decodeIntervals(line)[15];
  const a = original.findIndex(p => same(p, evidence.start));
  const b = original.findIndex(p => same(p, evidence.end));
  assert(a >= 0 && b > a, 'Tabata source changed: reviewed seams missing');
  assert.deepEqual(original.slice(a + 1, b), evidence.replaced, 'Tabata source changed: interior differs');
  const survey = surveyedPath(evidence);
  const replacement = survey.slice(...evidence.surveySlice);
  const display = [...original.slice(0, a + 1), ...replacement, ...original.slice(b)];
  const existing = line.displayIntervalCoordinates?.['15'];
  assert(!existing || JSON.stringify(existing) === JSON.stringify(display), 'Tabata display override changed; review before replacing');
  line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates, 15: display };
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides[POLICY] = {
    reviewedAt: evidence.reviewedAt, crs: evidence.crs,
    script: 'app/scripts/railway/repair-tabata-curve.mjs',
    evidence: 'app/scripts/railway/tabata-curve-overrides.json',
    source: evidence.source, wayIds: evidence.path,
    displayPolicy: evidence.displayPolicy,
    transformation: 'Replace two sparse display vertices in Komagome–Tabata with exact connected OSM outer-track curve vertices; retain both N02 seams, full interval endpoints, physical segments, station IDs and mileage',
  };
  return pkg;
}

function distance(a, b) {
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
    (b[1] - a[1]) * 111320);
}

export function repairParts(pkg, input) {
  const lanes = structuredClone(input);
  const line = pkg.lines.find(row => row.id === LINE);
  const reviewed = JSON.parse(fs.readFileSync(path.join(ROOT, 'public/rail/shared-corridors.json')));
  const override = RailNetwork.reviewedSharedCorridorOverrides(pkg, reviewed).get(LINE);
  const parts = RailNetwork.displayPartsForLine(
    override ? { ...line, stations: override.stations } : line,
    override?.intervals || null, override?.protectedPoints || [], override?.sharedStationCodes || new Set());
  const rows = partRowsForLine(line, parts, override);
  const old = lanes.partsByRegion.jp.filter(row => row[0] === LINE);
  assert(old.length === 1 && rows.length === 1 && old[0][7] && rows[0][7], 'Tabata display part topology changed');
  const evidence = JSON.parse(fs.readFileSync(EVIDENCE));
  const oldPoints = old[0][7], newPoints = rows[0][7];
  const a = oldPoints.findIndex(p => same(p, evidence.start));
  const b = oldPoints.findIndex(p => same(p, evidence.end));
  const na = newPoints.findIndex(p => same(p, evidence.start));
  const nb = newPoints.findIndex(p => same(p, evidence.end));
  assert(a >= 0 && b > a && na === a && nb > na, 'Tabata native seams changed');
  assert.deepEqual(oldPoints.slice(0, a + 1), newPoints.slice(0, na + 1));
  assert.deepEqual(oldPoints.slice(b), newPoints.slice(nb));
  const changedFrom = oldPoints.slice(1, a + 1).reduce((m, p, i) => m + distance(oldPoints[i], p), 0);
  // Existing lane/follow/window measures are reusable only before this curve.
  // A new dependency at or beyond it requires a reviewed regional derivation.
  for (const key of ['byRegion', 'familyWindowsByRegion'])
    for (const row of lanes[key]?.jp || [])
      if (row[0] === LINE) assert(row[1] === 0 && Math.max(row[2], row[3]) < changedFrom, 'Affected lane/window measure requires re-derivation');
  for (const row of lanes.followsByRegion?.jp || []) {
    if (row[0] === LINE) assert(row[1] === 0 && Math.max(row[2], row[3]) < changedFrom, 'Affected follower measure requires re-derivation');
    if (row[4] === LINE) assert(row[5] === 0 && Math.max(row[6], row[7]) < changedFrom, 'Affected leader measure requires re-derivation');
  }
  assert(!old[0][8]?.length && !rows[0][8]?.length, 'Tabata withheld measure requires re-derivation');
  lanes.partsByRegion.jp = lanes.partsByRegion.jp.map(row => row[0] === LINE ? rows[0] : row);
  return lanes;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const packagePath = path.join(ROOT, 'public/rail/jp-2025.json');
  const lanesPath = path.join(ROOT, 'public/rail/display-lanes.json');
  const before = fs.readFileSync(packagePath, 'utf8'), oldLanes = fs.readFileSync(lanesPath, 'utf8');
  const pkg = repairPackage(JSON.parse(before), JSON.parse(fs.readFileSync(EVIDENCE)));
  const lanes = repairParts(pkg, JSON.parse(oldLanes));
  const after = JSON.stringify(pkg), afterLanes = `${JSON.stringify(lanes)}\n`;
  if (process.argv.includes('--check')) {
    assert.equal(before.trimEnd(), after, 'Tabata package override is stale');
    assert.equal(oldLanes.trimEnd(), afterLanes.trimEnd(), 'Tabata native part row is stale');
  } else {
    if (before.trimEnd() !== after) fs.writeFileSync(packagePath, after);
    if (oldLanes.trimEnd() !== afterLanes.trimEnd()) fs.writeFileSync(lanesPath, afterLanes);
  }
  console.log('Tabata curve: reviewed display interval and native part row are current');
}
