#!/usr/bin/env node
// Replay the reviewed Oshiage display alignment; physical intervals stay intact.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { alignThroughPaths } from './lib/through_join_geometry.mjs';

const require = createRequire(import.meta.url);
const RailNetwork = require('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const MAIN = 'jp-東武鉄道-伊勢崎線';
export const BRANCH = `${MAIN}-2`;
export const METRO = 'jp-東京地下鉄-11号線半蔵門線';
export const OSHIAGE = [139.81335, 35.71026];
const POLICY = 'oshiage-platform-display';

export function repairPackage(pkg) {
  const branch = pkg.lines.find(line => line.id === BRANCH);
  const metro = pkg.lines.find(line => line.id === METRO);
  if (!branch || !metro) throw new Error('Missing Oshiage line');
  const branchPath = RailNetwork.decodeIntervals(branch)[0];
  const last = metro.segments.length - 1;
  const metroPath = RailNetwork.decodeIntervals(metro)[last];
  // The existing N02-25 fragments contain this railway-boundary vertex and
  // the approach through 35.70908/35.71012. The old anchor truncates Metro
  // south of it and extends Tobu back south beyond it.
  const boundary = branchPath.findIndex(p => p[0] === 139.81336 && p[1] === 35.71012);
  if (boundary < 0 || metroPath.at(-1)[1] !== 35.70847)
    throw new Error('Oshiage survey changed; review the override again');
  const [branchApproach, metroApproach] = alignThroughPaths([
    [...branchPath.slice(0, boundary + 1), OSHIAGE],
    [...metroPath.slice(0, -1), [139.81359, 35.70908], [139.81336, 35.71012], OSHIAGE],
  ], OSHIAGE);
  branch.displayIntervalCoordinates = {
    ...branch.displayIntervalCoordinates,
    0: branchApproach,
  };
  metro.displayIntervalCoordinates = {
    ...metro.displayIntervalCoordinates,
    [last]: metroApproach,
  };
  for (const line of [branch, metro])
    line.displayStationCoordinates = { ...line.displayStationCoordinates, '003526': OSHIAGE };
  metro.stationLaneByCode = { ...metro.stationLaneByCode, '003526': 0 };
  branch.stationCircleOwnerByCode = {
    ...branch.stationCircleOwnerByCode, '003479': MAIN, '003526': METRO,
  };
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides[POLICY] = {
    reviewedAt: '2026-10-01', crs: 'WGS84',
    script: 'app/scripts/railway/repair-oshiage-display.mjs',
    source: 'N02-25 fragments: 東武鉄道|伊勢崎線, endpoint [139.81335,35.71026]',
    evidence: [
      'https://www.tobu.co.jp/railway/guide/station/info/1120.html',
      'https://www.tokyometro.jp/station/oshiage/yardmap/index_print.html',
    ],
    transformation: 'Display only: place shared Tobu/Metro circle at surveyed railway boundary; trim Tobu approach and extend Metro over existing N02 vertices; align the final 120 m on a common terminal tangent with a 20 m straight platform approach; draw Tobu branch on its own alignment without trunk follow/tenant suppression or screen lane',
  };
  return pkg;
}

// Called after both full lane derivation and --refresh-parts, so a rebuild
// cannot reinstate the measured-but-wrong branch/trunk handoff.
export function repairLanes(pkg, lanes) {
  if (!pkg.geometrySource?.manualOverrides?.[POLICY]) return lanes;
  const pair = new Set([MAIN, BRANCH]);
  lanes.byRegion.jp = lanes.byRegion.jp.filter(row => row[0] !== BRANCH);
  lanes.followsByRegion.jp = lanes.followsByRegion.jp.filter(row =>
    !(pair.has(row[0]) && pair.has(row[4])));
  lanes.familyWindowsByRegion.jp = lanes.familyWindowsByRegion.jp.filter(row =>
    !(pair.has(row[0]) && row[5] === '東武鉄道:伊勢崎線'));
  // Keep the shared platform on lane zero after a fresh corridor derivation.
  const terminal = lanes.partsByRegion.jp.filter(row => row[0] === METRO).at(-1);
  const end = terminal[5], start = Math.max(0, end - 300), part = terminal[1];
  lanes.byRegion.jp = lanes.byRegion.jp.flatMap(row => {
    if (row[0] !== METRO || row[1] !== part || row[3] <= start) return [row];
    return row[2] < start ? [[...row.slice(0, 3), start, row[4]]] : [];
  });
  lanes.byRegion.jp.push([METRO, part, start, end, 0]);
  return lanes;
}

async function main() {
  const { partRowsForLine } = await import('./build-display-lanes.mjs');
  const packagePath = path.join(ROOT, 'public/rail/jp-2025.json');
  const lanesPath = path.join(ROOT, 'public/rail/display-lanes.json');
  const before = fs.readFileSync(packagePath, 'utf8');
  const beforeLanes = fs.readFileSync(lanesPath, 'utf8');
  const pkg = repairPackage(JSON.parse(before));
  const lanes = JSON.parse(beforeLanes);
  for (const id of [BRANCH, METRO]) {
    const line = pkg.lines.find(line => line.id === id);
    const parts = RailNetwork.displayPartsForLine(line);
    const rows = partRowsForLine(line, parts, null, null);
    const old = lanes.partsByRegion.jp;
    const first = old.findIndex(row => row[0] === id);
    if (first < 0) throw new Error(`Missing display part: ${id}`);
    old.splice(first, old.filter(row => row[0] === id).length, ...rows);
  }
  repairLanes(pkg, lanes);
  const after = JSON.stringify(pkg);
  const afterLanes = `${JSON.stringify(lanes)}\n`;
  if (process.argv.includes('--check')) {
    if (before.trimEnd() !== after || beforeLanes !== afterLanes)
      throw new Error('Oshiage display override is not applied');
    console.log('Oshiage display override is current');
  } else {
    if (before.trimEnd() !== after) fs.writeFileSync(packagePath, after);
    if (beforeLanes !== afterLanes) fs.writeFileSync(lanesPath, afterLanes);
    console.log('Applied Oshiage display alignment and branch junction');
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main().catch(error => { console.error(error); process.exitCode = 1; });
