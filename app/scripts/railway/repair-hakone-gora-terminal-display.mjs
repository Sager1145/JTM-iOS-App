#!/usr/bin/env node
// Final Gora terminal display stage; all earlier Hakone repairs remain strict.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { applyStationLanePins, partRowsForLine } from './build-display-lanes.mjs';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { repairPackage as repairYamasaki } from './repair-hakone-yamasaki-display.mjs';
import { refreshDependencyReferences, DEPENDENCY_PATHS } from './repair-three-reversal-extents.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));
const distance = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
  (b[1] - a[1]) * 111320);
const length = points => points.slice(1).reduce((total, point, index) => total + distance(points[index], point), 0);
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function reviewedTerminal(e) {
  assert.equal(e.format, 'jtm-hakone-gora-terminal-display-v1');
  assert.deepEqual([e.lineID, e.stationID, e.interval, e.nativePart],
    ['jp-小田急箱根-鉄道線', '005231', 9, 6]);
  const analysisPath = path.join(REPO, e.source.analysisPath);
  const imagePath = path.join(REPO, e.source.imagePath);
  assert.equal(sha256(analysisPath), e.source.analysisSha256, 'Reviewed native analysis changed');
  assert.equal(sha256(imagePath), e.source.imageSha256, 'Reviewed native image changed');
  const analysis = JSON.parse(fs.readFileSync(analysisPath));
  assert.deepEqual([analysis.format, analysis.lineID, analysis.intervalIndex, analysis.width, analysis.height],
    ['jtm-apple-map-extraction-v1', e.lineID, e.interval, 999, 654]);
  assert.equal(e.stationFrame.railSamplePair, 66);
  const samples = [e.stationFrame.railSamplePair, e.stationFrame.railSamplePair + 1]
    .map(index => analysis.samples[index]);
  assert(samples.every(sample => sample?.supported), 'Reviewed rail-glyph support changed');
  assert.equal(e.stationFrame.centrePixelY,
    (e.stationFrame.northPixelY + e.stationFrame.southPixelY) / 2);
  assert(e.stationFrame.northPixelY < e.stationFrame.centrePixelY &&
    e.stationFrame.centrePixelY < e.stationFrame.southPixelY);
  assert(samples[0].pixel[1] > e.stationFrame.centrePixelY && samples[1].pixel[1] < e.stationFrame.centrePixelY,
    'Reviewed midpoint is no longer bracketed by rail samples');
  assert(e.stationFrame.centrePixel[0] >= Math.min(samples[0].pixel[0], samples[1].pixel[0]) &&
    e.stationFrame.centrePixel[0] <= Math.max(samples[0].pixel[0], samples[1].pixel[0]));
  const [longitude, latitude] = e.displayAnchor, world = 2 ** 28;
  const radians = latitude * Math.PI / 180;
  const mapPoint = [(longitude + 180) / 360 * world,
    (1 - Math.log(Math.tan(radians) + 1 / Math.cos(radians)) / Math.PI) / 2 * world];
  const pixel = [(mapPoint[0] - analysis.mapRect.x) / (analysis.mapRect.width / analysis.width),
    (mapPoint[1] - analysis.mapRect.y) / (analysis.mapRect.height / analysis.height)];
  assert(Math.abs(pixel[0] - e.stationFrame.centrePixel[0]) < 1e-6 &&
    Math.abs(pixel[1] - e.stationFrame.centrePixel[1]) < 1e-6,
  'Reviewed MapKit coordinate changed');
  const interval = e.baselineLine.displayIntervalCoordinates?.[e.interval];
  assert(interval && e.window.guardIndex === 45);
  assert.deepEqual(interval[e.window.guardIndex], e.window.guard, 'Terminal guard changed');
  const oldTail = interval.slice(e.window.guardIndex);
  const projection = projectPointOntoPolyline(e.displayAnchor, oldTail);
  assert(projection.distanceM < e.window.maximumTransverseMetres, 'Reviewed endpoint escaped old rail direction');
  assert(length(oldTail) - distance(e.window.guard, e.displayAnchor) < e.window.maximumTrimMetres,
    'Reviewed terminal trim exceeds bound');
  return [...interval.slice(0, e.window.guardIndex + 1), structuredClone(e.displayAnchor)];
}

function repairedLine(e) {
  const line = structuredClone(e.baselineLine);
  line.displayStationCoordinates = { ...line.displayStationCoordinates,
    [e.stationID]: structuredClone(e.displayAnchor) };
  line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates,
    [e.interval]: reviewedTerminal(e) };
  line.stationLaneByCode = { ...line.stationLaneByCode, [e.stationID]: 0 };
  return line;
}

export function repairPackage(input, e = read('scripts/railway/hakone-gora-terminal-display-evidence.json')) {
  const repaired = repairedLine(e);
  const current = input.lines.find(line => line.id === e.lineID);
  assert(current && (equal(current, e.baselineLine) || equal(current, repaired)),
    'Unreviewed Hakone terminal dependency changed');
  const yamasaki = read('scripts/railway/hakone-yamasaki-display-evidence.json');
  const replay = repairYamasaki({ lines: [structuredClone(yamasaki.baselineLine)], geometrySource: {} }, yamasaki);
  assert.deepEqual(replay.lines[0], e.baselineLine, 'Earlier Yamasaki outer stage changed');
  assert.deepEqual(repaired.stations, e.baselineLine.stations);
  assert.deepEqual(repaired.segments, e.baselineLine.segments);
  const beforeParts = network.displayPartsForLine(e.baselineLine), afterParts = network.displayPartsForLine(repaired);
  assert.equal(beforeParts.length, 7); assert.equal(afterParts.length, 7);
  for (let index = 0; index < e.nativePart; index++) assert.deepEqual(afterParts[index], beforeParts[index]);
  let sharedPrefix = 0;
  while (sharedPrefix < beforeParts[e.nativePart].length && sharedPrefix < afterParts[e.nativePart].length &&
    same(beforeParts[e.nativePart][sharedPrefix], afterParts[e.nativePart][sharedPrefix])) sharedPrefix++;
  assert(sharedPrefix > 350, 'Terminal grooming escaped the reviewed final approach');
  assert.deepEqual(afterParts[e.nativePart].at(-1), e.displayAnchor);
  assert.deepEqual(repaired.displayReversalBranches, e.baselineLine.displayReversalBranches);
  const pkg = structuredClone(input);
  pkg.lines[pkg.lines.findIndex(line => line.id === e.lineID)] = repaired;
  pkg.geometrySource ||= {}; pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['hakone-gora-terminal-display'] = {
    reviewedAt: e.reviewedAt, lineID: e.lineID, stationID: e.stationID, interval: e.interval,
    nativePart: e.nativePart, source: e.source, stationFrame: e.stationFrame,
    displayAnchor: e.displayAnchor, window: e.window, stationLane: 0,
    script: 'app/scripts/railway/repair-hakone-gora-terminal-display.mjs',
    evidence: 'app/scripts/railway/hakone-gora-terminal-display-evidence.json',
    physicalTopologyChanged: false, policy: e.policy,
  };
  return pkg;
}

function replaceLineRows(rows, lineID, replacement) {
  const first = rows.findIndex(row => row[0] === lineID);
  assert(first >= 0, `Missing measured rows for ${lineID}`);
  const result = rows.filter(row => row[0] !== lineID);
  result.splice(first, 0, ...replacement);
  return result;
}

function expectedReferences(line, rows, e) {
  const expected = structuredClone(e.baselineMeasuredReferences);
  const total = rows[e.nativePart][5];
  const base = expected.byRegion.map(row => row[0] === e.lineID && row[1] === e.nativePart
    ? [e.lineID, e.nativePart, 0, total, .5] : row);
  expected.byRegion = applyStationLanePins({ lines: [line] }, rows, base);
  return expected;
}

export function repairParts(pkg, input, e = read('scripts/railway/hakone-gora-terminal-display-evidence.json')) {
  const line = pkg.lines.find(row => row.id === e.lineID);
  assert(line && equal(line, repairedLine(e)), 'Gora package repair missing');
  const parts = network.displayPartsForLine(line);
  const displayLine = { ...line,
    stations: line.stations.map(station => line.displayStationCoordinates?.[station[0]]
      ? [...station.slice(0, 2), ...line.displayStationCoordinates[station[0]], ...station.slice(4)] : station),
    segments: line.segments.map((segment, index) => line.displayIntervalCoordinates?.[index]
      ? [segment[0], 0, line.displayIntervalCoordinates[index]] : segment) };
  const rows = partRowsForLine(line, parts,
    { stations: displayLine.stations, intervals: network.decodeIntervals(displayLine) }, null);
  assert.equal(rows.length, 7);
  for (let index = 0; index < e.nativePart; index++)
    assert.deepEqual(rows[index], e.baselineNativeRows[index], 'Unrelated Hakone native part changed');
  const cached = input.partsByRegion.jp.filter(row => row[0] === e.lineID);
  assert(equal(cached, e.baselineNativeRows) || equal(cached, rows), 'Hakone native rows changed');
  const expected = expectedReferences(line, rows, e);
  for (const [key, baseline] of Object.entries(e.baselineMeasuredReferences)) {
    const ours = (input[key]?.jp || []).filter(row => JSON.stringify(row).includes(e.lineID));
    assert(equal(ours, baseline) || equal(ours, expected[key]), 'Unreviewed Hakone measured references: ' + key);
  }
  const result = structuredClone(input);
  result.partsByRegion.jp = replaceLineRows(result.partsByRegion.jp, e.lineID, rows);
  result.byRegion.jp = replaceLineRows(result.byRegion.jp, e.lineID, expected.byRegion);
  return result;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), apply = equal(args, ['--apply']);
  assert(!args.length || apply, 'Usage: node repair-hakone-gora-terminal-display.mjs [--apply]');
  const evidence = read('scripts/railway/hakone-gora-terminal-display-evidence.json');
  const paths = { package: 'public/rail/jp-2025.json', lanes: 'public/rail/display-lanes.json',
    evidence: 'scripts/railway/hakone-gora-terminal-display-evidence.json',
    yamasaki: 'scripts/railway/hakone-yamasaki-display-evidence.json', ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.join(ROOT, relative); return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const sourceSnapshots = [evidence.source.imagePath, evidence.source.analysisPath].map(relative => {
    const file = path.join(REPO, relative); return { path: file, before: fs.readFileSync(file) };
  });
  const load = key => JSON.parse(snapshots[key].before), pkg = repairPackage(load('package'), load('evidence'));
  const lanes = repairParts(pkg, load('lanes'), load('evidence'));
  if (apply) {
    const dependencies = refreshDependencyReferences(pkg,
      Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, load(key)])));
    const writes = [{ ...snapshots.package, after: JSON.stringify(pkg) },
      { ...snapshots.lanes, after: JSON.stringify(lanes) + '\n' },
      ...Object.keys(DEPENDENCY_PATHS).map(key => ({ ...snapshots[key], after: JSON.stringify(dependencies[key], null, 2) + '\n' }))];
    const prepared = writes.filter(write => write.before !== write.after)
      .map(write => ({ ...write, temporary: `${write.path}.gora-${process.pid}.tmp` }));
    try {
      for (const write of prepared) fs.writeFileSync(write.temporary, write.after);
      for (const snapshot of Object.values(snapshots))
        assert.equal(fs.readFileSync(snapshot.path, 'utf8'), snapshot.before, 'Concurrent input changed before Gora apply');
      for (const snapshot of sourceSnapshots)
        assert(fs.readFileSync(snapshot.path).equals(snapshot.before), 'Concurrent source evidence changed before Gora apply');
      for (const write of prepared) fs.renameSync(write.temporary, write.path);
    } finally {
      for (const write of prepared) if (fs.existsSync(write.temporary)) fs.unlinkSync(write.temporary);
    }
  }
  const line = pkg.lines.find(row => row.id === evidence.lineID);
  const part = lanes.partsByRegion.jp.find(row => row[0] === evidence.lineID && row[1] === evidence.nativePart);
  console.log(JSON.stringify({ mode: apply ? 'applied' : 'candidate', lineID: evidence.lineID,
    stationID: evidence.stationID, displayAnchor: line.displayStationCoordinates[evidence.stationID],
    intervalPointCount: line.displayIntervalCoordinates[evidence.interval].length,
    nativePart: evidence.nativePart, nativePartMetres: part[5], physicalTopologyChanged: false }));
}
