import test from 'node:test';
import assert from 'node:assert/strict';
import { partRowsForLine, applyStationLanePins } from '../scripts/railway/build-display-lanes.mjs';

const line = {
  id: 'fixture', stations: [['a', 'A', 139, 35], ['b', 'B', 139.001, 35], ['c', 'C', 139.002, 35]],
  segments: [[0.1, 0, [[139, 35], [139.0005, 35], [139.001, 35]]],
    [0.1, 1, [[139.0015, 35], [139.002, 35]]]],
};
const chain = [[139,35],[139.0005,35],[139.001,35],[139.0015,35],[139.002,35]];
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
