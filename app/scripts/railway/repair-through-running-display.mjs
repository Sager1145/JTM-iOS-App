#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { alignThroughPaths } from './lib/through_join_geometry.mjs';
import { repairPackage as repairOshiage, repairLanes as repairOshiageLanes } from './repair-oshiage-display.mjs';

const require = createRequire(import.meta.url);
const RailNetwork = require('../../public/rail-network.js');
const HERE = path.dirname(fileURLToPath(import.meta.url));
const RAIL = path.resolve(HERE, '../../public/rail');
export const registry = JSON.parse(fs.readFileSync(path.join(HERE, 'through-running-display-joins.json'), 'utf8'));

export function repairPackage(pkg) {
  repairOshiage(pkg);
  const lines = new Map(pkg.lines.map(line => [line.id, line]));
  for (const join of registry.joins) {
    const members = join.lineIds.map(id => {
      const line = lines.get(id);
      if (!line) throw new Error(`${join.id}: missing ${id}`);
      const index = line.stations.findIndex(station => station[0] === join.stationCode);
      if (index !== 0 && index !== line.stations.length - 1)
        throw new Error(`${join.id}: through join must explicitly select a terminal`);
      const interval = index === 0 ? 0 : line.segments.length - 1;
      const anchor = line.displayStationCoordinates?.[join.stationCode] || line.stations[index].slice(2, 4);
      const points = RailNetwork.decodeIntervals(line)[interval];
      return { line, index, interval, anchor, points: index === 0 ? points.reverse() : points };
    });
    if (JSON.stringify(members[0].anchor) !== JSON.stringify(members[1].anchor))
      throw new Error(`${join.id}: members do not share the same platform anchor`);
    // Oshiage first replays its independently reviewed platform correction.
    // Every other join rebuilds from physical source geometry for idempotency.
    if (!join.baseOverride) {
      const aligned = alignThroughPaths(members.map(member => member.points), members[0].anchor,
        registry.windowMetres, registry.straightMetres);
      members.forEach((member, i) => {
        member.line.displayIntervalCoordinates = { ...member.line.displayIntervalCoordinates,
          [member.interval]: member.index === 0 ? aligned[i].reverse() : aligned[i] };
      });
    }
    for (const { line } of members) {
      line.stationLaneByCode = { ...line.stationLaneByCode, [join.stationCode]: 0 };
      if (line.id !== join.circleOwner)
        line.stationCircleOwnerByCode = { ...line.stationCircleOwnerByCode, [join.stationCode]: join.circleOwner };
    }
  }
  pkg.geometrySource.manualOverrides['through-running-display-joins'] = {
    reviewedAt: registry.reviewedAt, crs: 'WGS84',
    script: 'app/scripts/railway/repair-through-running-display.mjs',
    registry: 'app/scripts/railway/through-running-display-joins.json',
    policy: 'Display only; explicit terminal platform pairs, a shared tangent and lane zero, one circle per platform family; preserve physical intervals, station identities and mileage',
    windowMetres: registry.windowMetres, straightMetres: registry.straightMetres,
    joins: registry.joins.map(join => join.id),
  };
  return pkg;
}

async function main() {
  const { partRowsForLine, applyStationLanePins } = await import('./build-display-lanes.mjs');
  const pkgPath = path.join(RAIL, 'jp-2025.json'), lanesPath = path.join(RAIL, 'display-lanes.json');
  const before = fs.readFileSync(pkgPath, 'utf8'), beforeLanes = fs.readFileSync(lanesPath, 'utf8');
  const pkg = repairPackage(JSON.parse(before)), lanes = JSON.parse(beforeLanes);
  const ids = new Set(registry.joins.flatMap(join => join.lineIds));
  const affected = pkg.lines.filter(line => ids.has(line.id));
  for (const line of affected) {
    const rows = partRowsForLine(line, RailNetwork.displayPartsForLine(line), null, null);
    const old = lanes.partsByRegion.jp, first = old.findIndex(row => row[0] === line.id);
    old.splice(first, old.filter(row => row[0] === line.id).length, ...rows);
  }
  lanes.byRegion.jp = applyStationLanePins({ lines: affected }, lanes.partsByRegion.jp, lanes.byRegion.jp);
  repairOshiageLanes(pkg, lanes);
  const after = JSON.stringify(pkg), afterLanes = `${JSON.stringify(lanes)}\n`;
  if (process.argv.includes('--check')) {
    if (before.trimEnd() !== after || beforeLanes !== afterLanes)
      throw new Error('Through-running display joins are not applied');
    console.log('Through-running display joins are current');
  } else {
    if (before.trimEnd() !== after) fs.writeFileSync(pkgPath, after);
    if (beforeLanes !== afterLanes) fs.writeFileSync(lanesPath, afterLanes);
    console.log(`Aligned ${registry.joins.length} reviewed through-running joins`);
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main().catch(error => { console.error(error); process.exitCode = 1; });
