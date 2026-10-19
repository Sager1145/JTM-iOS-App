#!/usr/bin/env node
// Replay the reviewed corridor and northern station frames; other frame centres remain pending.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';

const network = createRequire(import.meta.url)('../../public/rail-network.js');
const evidenceURL = new URL('./toyama-port-corridor-display-evidence.json', import.meta.url);
const read = url => JSON.parse(fs.readFileSync(url));
const physical = line => Object.fromEntries(Object.entries(line).filter(([key]) =>
  !['displayStationCoordinates', 'displayIntervalCoordinates'].includes(key)));

export function repairPackage(input, evidence = read(evidenceURL)) {
  assert.equal(evidence.status, 'accepted-corridor-and-northern-frames-other-frame-centres-pending');
  assert.equal(evidence.lineID, 'jp-富山地方鉄道-富山港線');
  const result = structuredClone(input);
  const line = result.lines.find(item => item.id === evidence.lineID);
  assert(line, 'Missing Toyama Port owner');
  assert.deepEqual(physical(line), evidence.baselinePhysicalLine,
    'Toyama Port physical dependency changed; review it before replay');
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
  result.geometrySource.manualOverrides['toyama-port-corridor-display'] = {
    reviewedAt: evidence.reviewedAt, lineID: evidence.lineID,
    script: 'app/scripts/railway/repair-toyama-port-corridor-display.mjs',
    evidence: 'app/scripts/railway/toyama-port-corridor-display-evidence.json',
    physicalTopologyChanged: false, intervalCount: 14, stationCount: 15,
    frameCentreReviewPending: evidence.frameCentreReviewPending,
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
  assert(inserted, 'Missing Toyama Port part row');
  return result;
}

export function repairHistory(input, evidence = read(evidenceURL)) {
  const result = structuredClone(input);
  const rule = result.retirements.find(row => row.history_id === evidence.historyBBox.historyID);
  assert(rule, 'Missing existing Eirakucho opening rule');
  assert.equal(rule.valid_from, '2021-03-21');
  assert.deepEqual(rule.match.targets, ['stations']);
  assert.equal(rule.match.line_name, '富山港線');
  assert.equal(rule.match.operator, '富山地方鉄道');
  assert([evidence.historyBBox.before, evidence.historyBBox.after].some(box =>
    JSON.stringify(box) === JSON.stringify(rule.match.bbox)), 'Opening rule bbox changed');
  rule.match.bbox = structuredClone(evidence.historyBBox.after);
  return result;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  assert(args.length === 0 || (args.length === 1 && args[0] === '--apply'));
  const pkgURL = new URL('../../public/rail/jp-2025.json', import.meta.url);
  const partsURL = new URL('../../public/rail/display-lanes.json', import.meta.url);
  const historyURL = new URL('../../data/rail-history.json', import.meta.url);
  const pkg = repairPackage(read(pkgURL)), parts = repairParts(pkg, read(partsURL));
  const history = repairHistory(read(historyURL));
  if (args[0] === '--apply') {
    fs.writeFileSync(pkgURL, JSON.stringify(pkg));
    fs.writeFileSync(partsURL, JSON.stringify(parts));
    fs.writeFileSync(historyURL, JSON.stringify(history));
  }
  console.log(JSON.stringify({ applied: args[0] === '--apply', intervals: 14,
    aliases: 15, physicalTopologyChanged: false, otherStationFrameCentresPending: true }));
}
