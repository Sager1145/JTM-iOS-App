#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const [candidatePath, repo = '/Users/sager/Documents/GitHub/JTM-iOS-App'] = process.argv.slice(2);
assert(candidatePath, 'Usage: node validate-candidate.mjs /path/candidate.json [repo]');
const read = file => JSON.parse(fs.readFileSync(file));
const hashBytes = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const hashJSON = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const packagePath = `${repo}/app/public/rail/jp-2025.json`;
const lanesPath = `${repo}/app/public/rail/display-lanes.json`;
const junctionPath = `${repo}/app/data/physical-rail-junctions.json`;
const pkg = read(packagePath), lanes = read(lanesPath), junctions = read(junctionPath), candidate = read(candidatePath);

assert.equal(candidate.format, 'jtm-matsumoto-oito-display-candidate-v1');
assert.deepEqual([candidate.lineID, candidate.stationID, candidate.intervalIndex, candidate.nativePart],
  ['jp-東日本旅客鉄道-大糸線', '002506', 31, 0]);
assert.equal(hashBytes(packagePath), candidate.dependencies.packageSha256);
assert.equal(hashBytes(lanesPath), candidate.dependencies.lanesSha256);
assert.equal(hashBytes(junctionPath), candidate.dependencies.junctionRegistrySha256);

const line = pkg.lines.find(row => row.id === candidate.lineID);
const shinonoi = pkg.lines.find(row => row.id === 'jp-東日本旅客鉄道-篠ノ井線');
const kamikochi = pkg.lines.find(row => row.id === 'jp-アルピコ交通-上高地線');
assert(line && shinonoi && kamikochi);
assert.equal(hashJSON(line), candidate.dependencies.oitoLineSha256);
assert.equal(hashJSON(shinonoi), candidate.dependencies.shinonoiLineSha256);
assert.equal(hashJSON(kamikochi), candidate.dependencies.kamikochiLineSha256);
assert.deepEqual(line.stations[31].slice(0, 4), ['002501', '北松本', 137.961089, 36.236923]);
assert.deepEqual(line.stations[32].slice(0, 4), ['002506', '松本', 137.963844, 36.231165]);
assert.deepEqual(shinonoi.stations[5].slice(0, 4), ['002506', '松本', 137.964625, 36.23027]);
assert.deepEqual(kamikochi.stations[0].slice(0, 4), ['002506', '松本', 137.96378, 36.231055]);

const physical = [line.stations[31].slice(2, 4), ...line.segments[31][2]];
assert.deepEqual(physical, candidate.baseline.interval31);
assert.deepEqual(physical.slice(0, candidate.sourceGuard.retainedThroughIndex + 1),
  candidate.intervalCoordinates.slice(0, candidate.sourceGuard.retainedThroughIndex + 1));
assert.deepEqual(physical[candidate.sourceGuard.retainedThroughIndex], candidate.sourceGuard.coordinate);
assert.deepEqual(candidate.intervalCoordinates.at(-1), candidate.displayAnchor);
assert.deepEqual(candidate.displayStationCoordinates, { '002506': candidate.displayAnchor });
assert(!candidate.intervalCoordinates.some(point => same(point, [137.96405, 36.2314])),
  'Candidate still forces the physical cross-line junction into the Oito display tail');

const world = 2 ** 28, frame = candidate.stationFrame;
assert(frame.nativeMapRect && frame.viewport && frame.centreRailPixel);
const mapX = frame.nativeMapRect.x + frame.centreRailPixel[0] * frame.nativeMapRect.width / frame.viewport[0];
const mapY = frame.nativeMapRect.y + frame.centreRailPixel[1] * frame.nativeMapRect.height / frame.viewport[1];
const anchor = [mapX / world * 360 - 180,
  Math.atan(Math.sinh(Math.PI * (1 - 2 * mapY / world))) * 180 / Math.PI];
assert(Math.hypot(anchor[0] - candidate.displayAnchor[0], anchor[1] - candidate.displayAnchor[1]) < 1e-12,
  'Display anchor is not the exact inverse of the reviewed native map frame pixel');
for (const source of candidate.sources) assert.equal(hashBytes(`${repo}/${source.path}`), source.sha256,
  `Evidence dependency changed: ${source.path}`);

const metres = (a, b) => Math.hypot((b[0] - a[0]) * 111320 * Math.cos((a[1] + b[1]) * Math.PI / 360),
  (b[1] - a[1]) * 111320);
const bearing = (a, b) => {
  const r = Math.PI / 180, p1 = a[1] * r, p2 = b[1] * r, dl = (b[0] - a[0]) * r;
  return (Math.atan2(Math.sin(dl) * Math.cos(p2), Math.cos(p1) * Math.sin(p2) -
    Math.sin(p1) * Math.cos(p2) * Math.cos(dl)) / r + 360) % 360;
};
const signedTurn = (a, b) => ((b - a + 540) % 360) - 180;
for (let index = 1; index < candidate.intervalCoordinates.length; index++)
  assert(metres(candidate.intervalCoordinates[index - 1], candidate.intervalCoordinates[index]) > 0.01,
    `Zero/near-zero candidate edge at ${index}`);
const turns = candidate.intervalCoordinates.slice(1, -1).map((_, index) => signedTurn(
  bearing(candidate.intervalCoordinates[index], candidate.intervalCoordinates[index + 1]),
  bearing(candidate.intervalCoordinates[index + 1], candidate.intervalCoordinates[index + 2])));
assert(Math.max(0, ...turns.map(Math.abs)) <= candidate.sourceGuard.maximumAbsoluteTurnDegrees,
  'Candidate ingress exceeds its reviewed turn guard');

const orient = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
for (let i = 1; i < candidate.intervalCoordinates.length; i++) for (let j = i + 2; j < candidate.intervalCoordinates.length; j++) {
  if (i === 1 && j === candidate.intervalCoordinates.length - 1) continue;
  const a = candidate.intervalCoordinates[i - 1], b = candidate.intervalCoordinates[i];
  const c = candidate.intervalCoordinates[j - 1], d = candidate.intervalCoordinates[j];
  assert(!(orient(a, b, c) * orient(a, b, d) < 0 && orient(c, d, a) * orient(c, d, b) < 0),
    `Candidate self-intersection between edges ${i - 1}-${i} and ${j - 1}-${j}`);
}

assert(junctions.junctions.some(row => row.id === 'matsumoto-east-56' &&
  same(row.from.coordinate, [137.96405, 36.2314]) && same(row.to.coordinate, [137.96405, 36.2314])));
const related = new Set([candidate.lineID, shinonoi.id, kamikochi.id]);
const references = {
  follows: lanes.followsByRegion.jp.filter(row => related.has(row[0]) || related.has(row[4])),
  families: lanes.familyWindowsByRegion.jp.filter(row => related.has(row[0])),
  chains: lanes.chainBoundariesByRegion.jp.filter(row => related.has(row[0])),
  hubs: lanes.hubReportByRegion.jp.filter(row => JSON.stringify(row).includes('松本')),
};
assert.deepEqual(references, candidate.baseline.relatedReferences);
assert.deepEqual(lanes.byRegion.jp.filter(row => related.has(row[0])), candidate.baseline.laneRows);
assert.deepEqual(candidate.baseline.laneRows, [
  ['jp-東日本旅客鉄道-大糸線', 0, 0, 70301.1, -0.5],
  ['jp-東日本旅客鉄道-篠ノ井線', 1, 13257.1, 14975, -0.5],
]);

console.log(JSON.stringify({
  status: 'candidate guards passed',
  lineID: candidate.lineID,
  intervalIndex: candidate.intervalIndex,
  pointCount: candidate.intervalCoordinates.length,
  displayAnchor: candidate.displayAnchor,
  maximumAbsoluteTurnDegrees: Math.max(0, ...turns.map(Math.abs)),
  physicalTopologyChanged: false,
  acceptance: candidate.acceptance,
}, null, 2));
