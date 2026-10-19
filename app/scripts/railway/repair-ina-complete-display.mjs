#!/usr/bin/env node
// Replay the reviewed Ina corridor; Omiya uses the declared occluded-platform reference.
// Canonical passenger topology stays fixed; see endpointEvidence for accuracy limits.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';

const network = createRequire(import.meta.url)('../../public/rail-network.js');
const evidenceURL = new URL('./ina-complete-display-evidence.json', import.meta.url);
const read = url => JSON.parse(fs.readFileSync(url));
const physical = line => Object.fromEntries(Object.entries(line).filter(([key]) =>
  !['displayStationCoordinates', 'displayIntervalCoordinates'].includes(key)));

export function repairPackage(input, evidence = read(evidenceURL)) {
  assert.equal(evidence.status, 'accepted-three-inspectors-and-main-reference-assisted-omiya');
  assert.equal(evidence.lineID, 'jp-埼玉新都市交通-伊奈線');
  const result = structuredClone(input);
  const line = result.lines.find(item => item.id === evidence.lineID);
  assert(line, 'Missing Ina owner');
  assert.deepEqual(physical(line), evidence.baselinePhysicalLine,
    'Ina physical dependency changed; review it before replay');
  assert.equal(evidence.intervals.length, line.segments.length);
  assert.equal(Object.keys(evidence.displayStationCoordinates).length, line.stations.length);
  line.displayStationCoordinates = structuredClone(evidence.displayStationCoordinates);
  line.displayIntervalCoordinates = Object.fromEntries(evidence.intervals.map((item, index) => {
    assert.equal(item.intervalIndex, index);
    assert.equal(item.fromStationID, line.stations[index][0]);
    assert.equal(item.toStationID, line.stations[index + 1][0]);
    assert.deepEqual(item.coordinates[0], line.displayStationCoordinates[item.fromStationID]);
    assert.deepEqual(item.coordinates.at(-1), line.displayStationCoordinates[item.toStationID]);
    assert(item.coordinates.length >= 2);
    return [index, structuredClone(item.coordinates)];
  }));
  assert.deepEqual(network.decodeIntervals(line), network.decodeIntervals(evidence.baselinePhysicalLine));
  result.geometrySource ||= {};
  result.geometrySource.manualOverrides ||= {};
  result.geometrySource.manualOverrides['ina-complete-display'] = {
    reviewedAt: evidence.reviewedAt, lineID: evidence.lineID,
    script: 'app/scripts/railway/repair-ina-complete-display.mjs',
    evidence: 'app/scripts/railway/ina-complete-display-evidence.json',
    physicalTopologyChanged: false, intervalCount: 12, stationCount: 13,
  };
  return result;
}

export function repairParts(pkg, input, evidence = read(evidenceURL)) {
  const line = pkg.lines.find(item => item.id === evidence.lineID);
  const stations = line.stations.map(row => [...row.slice(0, 2),
    ...line.displayStationCoordinates[row[0]], ...row.slice(4)]);
  const rows = partRowsForLine(line, network.displayPartsForLine(line), {
    stations, intervals: evidence.intervals.map(item => item.coordinates),
  }, null);
  const result = structuredClone(input);
  let inserted = false;
  result.partsByRegion.jp = result.partsByRegion.jp.flatMap(row => {
    if (row[0] !== evidence.lineID) return [row];
    if (inserted) return [];
    inserted = true;
    return rows;
  });
  assert(inserted, 'Missing Ina part row');
  return result;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  assert(args.length === 0 || (args.length === 1 && args[0] === '--apply'));
  const pkgURL = new URL('../../public/rail/jp-2025.json', import.meta.url);
  const partsURL = new URL('../../public/rail/display-lanes.json', import.meta.url);
  const pkg = repairPackage(read(pkgURL)), parts = repairParts(pkg, read(partsURL));
  if (args[0] === '--apply') {
    fs.writeFileSync(pkgURL, JSON.stringify(pkg));
    fs.writeFileSync(partsURL, JSON.stringify(parts));
  }
  console.log(JSON.stringify({ applied: args[0] === '--apply', intervals: 12,
    aliases: 13, physicalTopologyChanged: false }));
}
