import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { repairPackage, repairParts } from '../repair-sobu-nakamagome-display.mjs';
import { repairShinagawaLanes, SOBU } from '../repair-shinagawa-display-lanes.mjs';
const network = createRequire(import.meta.url)('../../../public/rail-network.js');
const e = JSON.parse(fs.readFileSync(new URL('../sobu-nakamagome-display-evidence.json', import.meta.url)));
const fixture = () => ({ format: 'compact-v1', country: 'jp', lines: [structuredClone(e.baselineLine),
  { id: 'unrelated', retain: ['geometry', 'identities'] }], geometrySource: {
    license: 'MLIT N02; OpenStreetMap ODbL 1.0', manualOverrides: {
      'shinagawa-normal-passenger-pair': structuredClone(e.baselinePassengerPairReview), concurrent: { keep: true } } } });
function lanes() {
  const result = Object.fromEntries(Object.entries(e.baselineRows).map(([key, rows]) => [key,
    { jp: structuredClone(rows), tw: [['other-region', 0]] }]));
  result.partsByRegion.jp.push(['unrelated', 0, 0, 0, 2, 10, null, null, []]);
  result.byRegion.jp.push(['unrelated', 0, 0, 10, 0]);
  result.followsByRegion.jp.push(['unrelated', 0, 0, 10, 'other-owner', 0, 20, 30]);
  result.familyWindowsByRegion.jp.push(['unrelated', 0, 0, 10, 0, 'unrelated-group']);
  result.hubReportByRegion = { jp: e.baselineHubMembers.map(({ hubID, member }) => ({ hubId: hubID,
    members: [structuredClone(member), { lineId: 'unrelated', retain: true }], classes: [{ keep: true }] })) };
  for (const [key, rows] of Object.entries(e.baselineOtherReferences)) result[key] = { jp: structuredClone(rows) };
  for (const [key, value] of Object.entries(e.baselineIdentityMappings)) result[key] = {
    jp: { [SOBU]: structuredClone(value), unrelated: 'retained' }, tw: { retained: true } };
  result.concurrentMetadata = { keep: true };
  return result;
}
const ownRows = (data, key) => data[key].jp.filter(row => row[0] === SOBU || key === 'followsByRegion' && row[4] === SOBU);

test('one attributed passenger fragment preserves exact raw boundaries and every physical/station input', () => {
  const input = fixture(), original = structuredClone(input), output = repairPackage(input, e), line = output.lines[0];
  const before = network.decodeIntervals(e.baselineLine)[3], f = e.fragment, after = line.displayIntervalCoordinates[3];
  assert.deepEqual(after, [...before.slice(0, 13), ...f.coordinates, ...before.slice(33)]);
  assert.deepEqual(after.slice(0, 14), before.slice(0, 14));
  assert.deepEqual(after.slice(34), before.slice(33));
  assert.deepEqual(after[13], [139.70858, 35.59237]);
  assert.deepEqual(after[33], [139.69821, 35.58934]);
  assert(!after.some(point => point[0] === 139.70808 && point[1] === 35.59208), 'Old off-band support survived');
  assert.equal(after.length, 94);
  assert.deepEqual(line.stations, e.baselineLine.stations);
  assert.deepEqual(line.segments, e.baselineLine.segments);
  assert.deepEqual(network.decodeIntervals(line), network.decodeIntervals(e.baselineLine));
  for (const index of [0, 1, 2]) assert.deepEqual(line.displayIntervalCoordinates[index], e.baselineLine.displayIntervalCoordinates[index]);
  assert.deepEqual(line.displayStationCoordinates, e.baselineLine.displayStationCoordinates);
  assert.deepEqual(line.stationLaneByCode, e.baselineLine.stationLaneByCode);
  assert.deepEqual(output.lines[1], input.lines[1]);
  assert.deepEqual(output.geometrySource.manualOverrides.concurrent, { keep: true });
  assert.equal(output.geometrySource.license, input.geometrySource.license);
  assert.deepEqual(input, original, 'Input mutated');
  assert.deepEqual(repairPackage(output, e), output);
});

test('existing Sobu ruler updates only the native part, one lane end and two downstream canonical follow spans', () => {
  const pkg = repairPackage(fixture(), e), input = lanes(), before = structuredClone(input), result = repairParts(pkg, input, e);
  const row = ownRows(result, 'partsByRegion')[0];
  assert.deepEqual(row.slice(0, 7), [SOBU, 0, -1, -1, 347, 24425, 'complex']);
  assert.deepEqual(row[7], network.displayPartsForLine(pkg.lines[0])[0]);
  assert.deepEqual(row[8], []);
  const oldLanes = ownRows(input, 'byRegion'), newLanes = ownRows(result, 'byRegion');
  assert.deepEqual(newLanes.slice(0, 7), oldLanes.slice(0, 7));
  assert.deepEqual(newLanes[7].slice(0, 3), oldLanes[7].slice(0, 3));
  assert(Math.abs(newLanes[7][3] - 17245.115481825414) < 1e-8);
  assert.equal(newLanes[7][4], -0.5);
  const oldFollows = ownRows(input, 'followsByRegion'), newFollows = ownRows(result, 'followsByRegion');
  for (let i = 0; i < oldFollows.length; i++) {
    assert.deepEqual(newFollows[i].slice(0, 6), oldFollows[i].slice(0, 6));
    if (oldFollows[i][0] === 'jp-東日本旅客鉄道-東海道線-3') {
      for (const column of [6, 7]) assert(Math.abs(newFollows[i][column] - oldFollows[i][column] - e.expectedRulerDeltaMetres) < 1e-8);
    } else assert.deepEqual(newFollows[i], oldFollows[i], 'Retained Osaki prefix follow changed');
  }
  assert.deepEqual(ownRows(result, 'familyWindowsByRegion'), e.baselineRows.familyWindowsByRegion);
  assert.deepEqual(result.hubReportByRegion, input.hubReportByRegion);
  for (const key of Object.keys(e.baselineRows)) {
    assert.deepEqual(result[key].tw, input[key].tw);
    assert.deepEqual(result[key].jp.filter(row => row[0] === 'unrelated'),
      input[key].jp.filter(row => row[0] === 'unrelated'));
  }
  for (const key of Object.keys(e.baselineOtherReferences)) assert.deepEqual(result[key], input[key]);
  for (const key of Object.keys(e.baselineIdentityMappings)) assert.deepEqual(result[key], input[key]);
  assert.deepEqual(result.concurrentMetadata, input.concurrentMetadata);
  assert.deepEqual(input, before);
  assert.deepEqual(repairParts(pkg, result, e), result);
});

test('unknown sources, physical changes, partial ruler updates and new owner dependencies reject', () => {
  for (const mutate of [value => value.lines[0].stations[3][0] = 'unknown',
    value => value.lines[0].segments[3][0] += 1,
    value => value.lines[0].displayIntervalCoordinates[3] = [[1, 2], [3, 4]]]) {
    const input = fixture(); mutate(input); assert.throws(() => repairPackage(input, e), /Sobu own physical\/display baseline changed/);
  }
  for (const mutate of [value => value.source.wayID = 365183499,
    value => value.source.wayVersion = 17,
    value => value.source.routeVersion += 1,
    value => value.source.files['way-365183512-full.json'].sha256 = '0'.repeat(64),
    value => value.fragment.nodeIDs[0] += 1,
    value => value.fragment.coordinates[1][0] += .00001,
    value => value.fragment.startBoundary.witness.point[0] += .00001]) {
    const evidence = structuredClone(e); mutate(evidence); assert.throws(() => repairPackage(fixture(), evidence));
  }
  const pkg = repairPackage(fixture(), e), repaired = repairParts(pkg, lanes(), e);
  for (const mutate of [value => value.byRegion.jp[0][4] = 99,
    value => value.followsByRegion.jp.push([SOBU, 0, 12100, 12200, 'foreign', 0, 0, 100]),
    value => value.followsByRegion.jp.push(['foreign', 0, 0, 100, SOBU, 0, 12100, 12200]),
    value => value.familyWindowsByRegion.jp[0][2] = 12100,
    value => value.hubReportByRegion.jp[0].members[0].from = 12100,
    value => value.chainBoundariesByRegion.jp.push([SOBU, 0, 1]),
    value => value.renderGroupByRegion.jp[SOBU] = 'unreviewed-owner',
    value => value.partsByRegion.jp[0] = structuredClone(ownRows(repaired, 'partsByRegion')[0])]) {
    const input = lanes(); mutate(input); assert.throws(() => repairParts(pkg, input, e), /Unreviewed Sobu measured reference changed/);
  }
});

test('existing ruler owner admits only the known prefix family and rejects an interior family', () => {
  const pkg = repairPackage(fixture(), e), before = { lines: [e.baselineLine], geometrySource: {
    manualOverrides: { 'shinagawa-normal-passenger-pair': e.baselinePassengerPairReview } } };
  const after = { ...before, lines: [pkg.lines[0]] };
  const result = repairShinagawaLanes(lanes(), before, after);
  assert.deepEqual(ownRows(result, 'familyWindowsByRegion'), e.baselineRows.familyWindowsByRegion);
  const input = lanes(); input.familyWindowsByRegion.jp[0][2] = 12100;
  assert.throws(() => repairShinagawaLanes(input, before, after), /Unexpected Sobu family window/);
});
