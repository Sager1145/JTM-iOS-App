import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createMeasureMapper, validateSharedStationPassage, LINE_IDS, INTERVAL_INDEXES } from '../scripts/railway/repair-yodo-shared-stations-display.mjs';
import { partRowsForLine, applyStationLanePins, computeHubOverrides, samplesFor } from '../scripts/railway/build-display-lanes.mjs';

const line = {
  id: 'fixture', stations: [['a', 'A', 139, 35], ['b', 'B', 139.001, 35], ['c', 'C', 139.002, 35]],
  segments: [[0.1, 0, [[139, 35], [139.0005, 35], [139.001, 35]]],
    [0.1, 1, [[139.0015, 35], [139.002, 35]]]],
};
const chain = [[139,35],[139.0005,35],[139.001,35],[139.0015,35],[139.002,35]];

test('shared through-station aliases preserve forward passage and native measured boundaries', () => {
  const w = [139, 35], k = [140, 35];
  const north = p => [p[0], p[1] + 0.001], south = p => [p[0], p[1] - 0.001];
  const prefix = [w, south(w), [139,34.998]];
  const tail = [[140,35.003], [140,35.002], north(k), k];
  const candidate = { lines: [
    { lineID: LINE_IDS[0], displayStationCoordinates: { '009535': w, '009471': k },
      candidateIntervals: [{ intervalIndex: 0, coordinates: prefix }, { intervalIndex: 18, coordinates: tail }] },
    { lineID: LINE_IDS[1], displayStationCoordinates: { '009535': w, '009571': prefix.at(-1) },
      candidateIntervals: [{ intervalIndex: 0, coordinates: [[139,35.002], north(w), w] },
        { intervalIndex: 1, coordinates: prefix },
        { intervalIndex: 2, coordinates: [prefix.at(-1), [139,34.997], [139,34.996]] }] },
    { lineID: LINE_IDS[2], displayStationCoordinates: { '009471': k },
      candidateIntervals: [{ intervalIndex: 87, coordinates: tail },
        { intervalIndex: 88, coordinates: [k, south(k), [140,34.998], [140,34.997], [140,34.996]] }] },
  ] };
  validateSharedStationPassage(candidate);
  const backwards = structuredClone(candidate);
  backwards.lines[2].candidateIntervals[1].coordinates[1] = north(k);
  assert.throws(() => validateSharedStationPassage(backwards), /backwards passage/);
  const split = structuredClone(candidate);
  split.lines[1].displayStationCoordinates['009535'] = [139.0001,35];
  assert.throws(() => validateSharedStationPassage(split), /owner aliases differ/);

  // A station moves forward along the same geographic railway. Its old
  // boundary measure must follow the new alias, not reproject the old point.
  const after = structuredClone(line);
  after.displayStationCoordinates = { b: [139.0012,35] };
  after.displayIntervalCoordinates = {
    0: [[139,35],[139.0005,35],[139.001,35],[139.0012,35]],
    1: [[139.0012,35],[139.0015,35],[139.002,35]],
  };
  const ruler = createMeasureMapper(line, after, [0,1]);
  assert.equal(ruler.map(ruler.oldTotal / 2), Number((ruler.newTotal * 0.6).toFixed(1)));
  assert.equal(ruler.map(Number(ruler.oldTotal.toFixed(1))), Number(ruler.newTotal.toFixed(1)));
  assert(Math.abs(ruler.map(ruler.oldTotal / 4) - ruler.oldTotal / 4) < 0.1);
  assert.throws(() => ruler.map(ruler.oldTotal + 100), /outside old native ruler/);
  const suffixOnly = structuredClone(line);
  suffixOnly.displayStationCoordinates = { c: [139.0022,35] };
  suffixOnly.displayIntervalCoordinates = { 1: [[139.001,35],[139.0015,35],[139.002,35],[139.0022,35]] };
  const suffixRuler = createMeasureMapper(line, suffixOnly, [1]);
  const precisePrefixBoundary = suffixRuler.oldTotal / 2;
  assert.equal(suffixRuler.map(precisePrefixBoundary), precisePrefixBoundary,
    'An unchanged prefix station/follow boundary must retain its exact unrounded ruler value');

  // After formal apply, check shipped coordinates directly; no archived
  // report candidate becomes a permanent production regression dependency.
  const pkg = JSON.parse(fs.readFileSync(new URL('../public/rail/jp-2025.json', import.meta.url)));
  const shipped = LINE_IDS.map(id => pkg.lines.find(row => row.id === id));
  if (shipped.every(row => INTERVAL_INDEXES[row.id].every(i => row.displayIntervalCoordinates?.[i])))
    validateSharedStationPassage({ lines: shipped.map(row => ({ lineID: row.id,
      displayStationCoordinates: row.displayStationCoordinates,
      candidateIntervals: INTERVAL_INDEXES[row.id].map(i => ({ intervalIndex: i, coordinates: row.displayIntervalCoordinates[i] })),
    })) });
});

test('Nishibiwajima own glyph controls remain forward across overlapping native views', () => {
  const pkg = JSON.parse(fs.readFileSync(new URL('../public/rail/jp-2025.json', import.meta.url)));
  const owner = pkg.lines.find(row => row.id === 'jp-名古屋鉄道-名古屋本線');
  const points = owner.displayIntervalCoordinates[20];
  assert(points.length >= 3, 'Main#20 must retain its reviewed own glyph supports');
  // The identified Futatsuiri→Nishibiwajima glyph advances east throughout its
  // shallow curve. A later camera must not append an upstream support point.
  for (let i = 1; i < points.length; i++)
    assert(points[i][0] > points[i - 1][0], `Main#20 goes backwards at vertex ${i}`);
  for (let i = 1; i + 1 < points.length; i++) {
    const cos = Math.cos(points[i][1] * Math.PI / 180);
    const incoming = [(points[i][0] - points[i - 1][0]) * cos,
      points[i][1] - points[i - 1][1]];
    const outgoing = [(points[i + 1][0] - points[i][0]) * cos,
      points[i + 1][1] - points[i][1]];
    assert(incoming[0] * outgoing[0] + incoming[1] * outgoing[1] > 0,
      `Main#20 has a sharp reversal at vertex ${i}`);
  }
});
test('plain rows reconstruct the exact decoded chain with one shared seam removed', () => {
  const [row] = partRowsForLine(line, [chain], null, null);
  assert.deepEqual(row.slice(2,4), [0,1]);
  assert.equal(row[7], null);
});
test('equal-length station approaches embed final coordinates instead of a raw range', () => {
  const changed = chain.map(point => point.slice());
  changed[1][0] += 0.000001;
  changed.withheld = [[0,50]];
  const [row] = partRowsForLine(line, [changed], null, null);
  assert.deepEqual(row.slice(2,4), [-1,-1]);
  assert.equal(row[6], 'station-approach/groomed');
  assert.deepEqual(row[7], changed);
  assert.deepEqual(row[8], [[0,50]]);
});
test('removed grooming vertices cannot masquerade as a plain interval chain', () => {
  const changed = chain.filter((_, index) => index !== 1);
  const [row] = partRowsForLine(line, [changed], null, null);
  assert.equal(row[6], 'station-approach/groomed');
});

test('terminal lane pins clip old offsets and preserve other parts', () => {
  const pkg = { lines: [{ ...line, stationLaneByCode: { a: 0, c: 0 } }] };
  const parts = [['fixture', 0, 0, 1, 5, 1000]];
  const lanes = [['fixture', 0, 0, 1000, -0.5], ['other', 0, 0, 500, 1]];
  assert.deepEqual(applyStationLanePins(pkg, parts, lanes), [
    ['fixture', 0, 0, 300, 0], ['fixture', 0, 300, 700, -0.5],
    ['fixture', 0, 700, 1000, 0], ['other', 0, 0, 500, 1],
  ]);
});
test('terminal pin refresh is idempotent', () => {
  const pkg = { lines: [{ ...line, stationLaneByCode: { a: 0 } }] };
  const parts = [['fixture', 0, 0, 1, 5, 1000]];
  const once = applyStationLanePins(pkg, parts, [['fixture', 0, 0, 1000, 1]]);
  assert.deepEqual(applyStationLanePins(pkg, parts, once), once);
});

test('interior lane pins follow the reviewed display anchor on embedded geometry', () => {
  const coordinates = [[139, 35], [139, 35.01], [139, 35.02]];
  const pinned = { ...line, stationLaneByCode: { b: 0 },
    displayStationCoordinates: { b: coordinates[1] } };
  const parts = [['fixture', 0, -1, -1, 3, 2226.4, 'complex', coordinates]];
  const lanes = [['fixture', 0, 0, 2226.4, -1]];
  const expected = [['fixture', 0, 0, 813.2, -1],
    ['fixture', 0, 813.2, 1413.2, 0], ['fixture', 0, 1413.2, 2226.4, -1]];
  const once = applyStationLanePins({ lines: [pinned] }, parts, lanes);
  assert.deepEqual(once, expected);
  assert.deepEqual(applyStationLanePins({ lines: [pinned] }, parts, once), once);
  assert.throws(() => applyStationLanePins({ lines: [{ ...pinned,
    displayStationCoordinates: { b: [140, 36] } }] }, parts, lanes), /has no display anchor/);
});

test('interior lane pins measure plain chained intervals', () => {
  const pinned = { ...line, stationLaneByCode: { b: 0 } };
  const parts = [['fixture', 0, 0, 1, 5, 182.4]];
  const result = applyStationLanePins({ lines: [pinned] }, parts,
    [['fixture', 0, 0, 182.4, -1]], 20);
  assert.deepEqual(result, [['fixture', 0, 0, 71.2, -1],
    ['fixture', 0, 71.2, 111.2, 0], ['fixture', 0, 111.2, 182.4, -1]]);
});

test('terminal lane pins select only their boundary part on a split line', () => {
  const pinned = { ...line, stationLaneByCode: { a: 0, c: 0 } };
  const parts = [['fixture', 0, 0, 0, 3, 1000], ['fixture', 1, 1, 1, 3, 1000]];
  assert.deepEqual(applyStationLanePins({ lines: [pinned] }, parts,
    [['fixture', 0, 0, 1000, -1], ['fixture', 1, 0, 1000, -1]]), [
    ['fixture', 0, 0, 300, 0], ['fixture', 0, 300, 1000, -1],
    ['fixture', 1, 0, 700, -1], ['fixture', 1, 700, 1000, 0],
  ]);
});

test('an interior pin cannot guess between repeated display anchors', () => {
  const pinned = { ...line, stationLaneByCode: { b: 0 } };
  const coordinates = [[139, 35], [139.001, 35], [139.002, 35], [139.001, 35]];
  assert.throws(() => applyStationLanePins({ lines: [pinned] },
    [['fixture', 0, -1, -1, 4, 300, 'complex', coordinates]], []), /ambiguous display anchors/);
});

test('a hub negates the slot of a non-follower running anti-parallel to the trunk', () => {
  const ys = [35.01, 35.005, 35, 34.995, 34.99];
  const mk = (lineId, displayClass, lon, order) => ({
    lineId, partIndex: 0, displayClass,
    coordinates: (order > 0 ? ys : [...ys].reverse()).map((y) => [lon, y]),
  });
  const parts = [
    mk('trunk', 'T', 139, 1), // southbound
    mk('anti', 'A', 139.0002, -1), // northbound, never follows
    mk('same', 'S', 138.9998, 1), // southbound
  ];
  const metrics = new Map(parts.map((part) => [`${part.lineId}#0`, samplesFor(part)]));
  const grid = new Map(); // same buckets as the builder's cell(): 0.00055 degrees
  for (const metric of metrics.values())
    for (const sample of metric.samples) {
      const key = `${Math.floor(sample.point[0] / 0.00055)}|${Math.floor(sample.point[1] / 0.00055)}`;
      if (!grid.has(key)) grid.set(key, []);
      grid.get(key).push(sample);
    }
  const hubs = [{ id: 'fixture-hub', name: 'Fixture', centre: [139, 35], radiusMetres: 500, trunkLineId: 'trunk' }];
  const { hubRowsByPart, report } = computeHubOverrides(parts, metrics, [], hubs, grid);
  const members = new Map(report[0].members.map((member) => [member.lineId, member]));
  assert.equal(members.get('trunk').reversed, false);
  assert.equal(members.get('same').reversed, false);
  assert.equal(members.get('anti').reversed, true);
  const laneOf = (id) => hubRowsByPart.get(`${id}#0`)[0].lane;
  assert.notEqual(members.get('anti').slot, 0);
  assert.equal(laneOf('anti'), -members.get('anti').slot);
  assert.equal(laneOf('same'), members.get('same').slot);
});

test('a non-follower on its own track far from the trunk gets no hub override', () => {
  const trunk = { lineId: 'trunk', partIndex: 0, displayClass: 'T',
    coordinates: [35.01, 35.005, 35, 34.995, 34.99].map((y) => [139, y]) };
  const same = { lineId: 'same', partIndex: 0, displayClass: 'S',
    coordinates: [35.01, 35.005, 35, 34.995, 34.99].map((y) => [138.9998, y]) };
  // Touches the trunk at the top of the hub window, then veers ~200 m east.
  const far = { lineId: 'far', partIndex: 0, displayClass: 'F',
    coordinates: [[139.0001, 35.0043], [139.0001, 35.0035], [139.0022, 35.0030], [139.0022, 34.99]] };
  const parts = [trunk, same, far];
  const metrics = new Map(parts.map((part) => [`${part.lineId}#0`, samplesFor(part)]));
  const grid = new Map();
  for (const metric of metrics.values())
    for (const sample of metric.samples) {
      const key = `${Math.floor(sample.point[0] / 0.00055)}|${Math.floor(sample.point[1] / 0.00055)}`;
      if (!grid.has(key)) grid.set(key, []);
      grid.get(key).push(sample);
    }
  const hubs = [{ id: 'fixture-hub', name: 'Fixture', centre: [139, 35], radiusMetres: 500, trunkLineId: 'trunk' }];
  const { hubRowsByPart, report } = computeHubOverrides(parts, metrics, [], hubs, grid);
  const farReport = report[0].members.find((member) => member.lineId === 'far');
  assert.equal(farReport.excluded, 'separate-alignment');
  assert.equal(hubRowsByPart.has('far#0'), false);
  assert.ok(hubRowsByPart.has('same#0'));
});

test('a member coincident with the trunk for a stretch then diverging is clipped to that run', () => {
  const ys = [35.01, 35.005, 35, 34.995, 34.99];
  const trunk = { lineId: 'trunk', partIndex: 0, displayClass: 'T', coordinates: ys.map((y) => [139, y]) };
  const same = { lineId: 'same', partIndex: 0, displayClass: 'S', coordinates: ys.map((y) => [138.9998, y]) };
  // Runs on the trunk from y=35.0045 down to y=35.0009 (~400 m), then bends away east.
  const diverge = { lineId: 'diverge', partIndex: 0, displayClass: 'D',
    coordinates: [[139, 35.0045], [139, 35.0009], [139.003, 35.0], [139.006, 34.995]] };
  const parts = [trunk, same, diverge];
  const metrics = new Map(parts.map((part) => [`${part.lineId}#0`, samplesFor(part)]));
  const grid = new Map();
  for (const metric of metrics.values())
    for (const sample of metric.samples) {
      const key = `${Math.floor(sample.point[0] / 0.00055)}|${Math.floor(sample.point[1] / 0.00055)}`;
      if (!grid.has(key)) grid.set(key, []);
      grid.get(key).push(sample);
    }
  const hubs = [{ id: 'fixture-hub', name: 'Fixture', centre: [139, 35], radiusMetres: 600, trunkLineId: 'trunk' }];
  const { hubRowsByPart, report } = computeHubOverrides(parts, metrics, [], hubs, grid);
  const member = report[0].members.find((entry) => entry.lineId === 'diverge');
  assert.equal(member.excluded, undefined);
  const row = hubRowsByPart.get('diverge#0')[0];
  assert.ok(row.from <= 25, `row starts at the shared stretch: ${row.from}`);
  assert.ok(row.to >= 380 && row.to < 600, `row clipped to the coincident run (+ <=120 m alongside): ${row.to}`);
});

test('an east-west member crossing a north-south trunk at the hub centre is excluded', () => {
  const ys = [35.01, 35.005, 35, 34.995, 34.99];
  const trunk = { lineId: 'trunk', partIndex: 0, displayClass: 'T', coordinates: ys.map((y) => [139, y]) };
  const same = { lineId: 'same', partIndex: 0, displayClass: 'S', coordinates: ys.map((y) => [138.9998, y]) };
  const cross = { lineId: 'cross', partIndex: 0, displayClass: 'X',
    coordinates: [138.994, 138.997, 139, 139.003, 139.006].map((x) => [x, 35]) };
  const parts = [trunk, same, cross];
  const metrics = new Map(parts.map((part) => [`${part.lineId}#0`, samplesFor(part)]));
  const grid = new Map();
  for (const metric of metrics.values())
    for (const sample of metric.samples) {
      const key = `${Math.floor(sample.point[0] / 0.00055)}|${Math.floor(sample.point[1] / 0.00055)}`;
      if (!grid.has(key)) grid.set(key, []);
      grid.get(key).push(sample);
    }
  const hubs = [{ id: 'fixture-hub', name: 'Fixture', centre: [139, 35], radiusMetres: 500, trunkLineId: 'trunk' }];
  const { hubRowsByPart, report } = computeHubOverrides(parts, metrics, [], hubs, grid);
  const crossReport = report[0].members.find((member) => member.lineId === 'cross');
  assert.equal(crossReport.excluded, 'crossing');
  assert.equal(hubRowsByPart.has('cross#0'), false);
  assert.ok(hubRowsByPart.has('same#0'));
});
