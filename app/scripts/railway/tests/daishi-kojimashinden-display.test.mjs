import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {repairPackage, repairParts, validateCandidateReview} from '../repair-daishi-kojimashinden-display.mjs';

const net = createRequire(import.meta.url)('../../../public/rail-network.js');
const authority = JSON.parse(fs.readFileSync(new URL('../../../../railway-evidence/local/proposals/daishi-kojimashinden-20261020/bounded-upper-track-candidate.json', import.meta.url)));
const LINE = authority.lineID;
const packageInput = () => ({lines: [structuredClone(authority.baselineLine), {id: 'unrelated', stations: [], segments: []}],
  geometrySource: {manualOverrides: {unrelated: {keep: true}}}});

test('Kojimashinden moves only the display tail and terminal alias onto the selected own track', () => {
  const input = packageInput(), result = repairPackage(input, authority), line = result.lines[0];
  assert.deepEqual(line, authority.candidateLine);
  assert.deepEqual(line.stations, input.lines[0].stations);
  assert.deepEqual(line.segments, input.lines[0].segments);
  assert.deepEqual(net.decodeIntervals(line), net.decodeIntervals(input.lines[0]));
  assert.deepEqual(line.displayIntervalCoordinates[5].slice(0, 7), net.decodeIntervals(input.lines[0])[5].slice(0, 7));
  assert.equal(line.displayIntervalCoordinates[5].length, 16);
  assert.deepEqual(line.displayIntervalCoordinates[5].at(-1), [139.7471446220207, 35.53493575339516]);
  assert.deepEqual(net.displayPartsForLine(line)[0].slice(0,44), net.displayPartsForLine(input.lines[0])[0].slice(0,44));
  assert.deepEqual(net.displayPartsForLine(line)[0][43], [139.74315,35.53615]);
  const physical = structuredClone(line);
  delete physical.displayStationCoordinates;
  delete physical.displayIntervalCoordinates;
  assert.deepEqual(physical, input.lines[0]);
  assert.deepEqual(result.lines[1], input.lines[1]);
  assert.deepEqual(result.geometrySource.manualOverrides.unrelated, {keep: true});
  assert.deepEqual(repairPackage(result, authority), result);
  assert.equal(input.lines[0].displayStationCoordinates, undefined);
});

test('apply requires an explicit scoped receipt tied to the exact candidate, rather than capture completion', () => {
  const line = repairPackage(packageInput(), authority).lines[0];
  assert.throws(() => validateCandidateReview(null, line), /receipt required/);
  const review = {format: 'jtm-daishi-kojimashinden-candidate-review-v1', status: 'bounded-candidate-reviewed',
    lineID: LINE, stationID: '004418', intervalIndices: [5], wholeLineAccepted: false, MainCertified: false,
    reviewedOwnLineSha256: createHash('sha256').update(JSON.stringify(line)).digest('hex'), captures: []};
  assert.throws(() => validateCandidateReview(review, line), /four reviewed captures/);
  const stale = {...review, reviewedOwnLineSha256: 'stale'};
  assert.throws(() => validateCandidateReview(stale, line), /reviewed own line changed/);
  assert.throws(() => validateCandidateReview({...review, stationID: 'foreign'}, line), /review scope changed/);
});

test('root scoped review receipt binds the four retained pairs and rejects changed evidence bytes', () => {
  const line = repairPackage(packageInput(), authority).lines[0];
  const receipt = JSON.parse(fs.readFileSync(new URL('../../../../railway-evidence/local/proposals/daishi-kojimashinden-20261020/native-candidate-review.json', import.meta.url)));
  assert.equal(validateCandidateReview(receipt, line).length, 12);
  const changed = structuredClone(receipt); changed.captures[0].basemapSha256 = 'stale';
  assert.throws(() => validateCandidateReview(changed, line), /reviewed capture bytes changed/);
});

test('native fallback reproduces actual JS geometry and terminal alias, rejecting stale or foreign own rows', () => {
  const pkg = repairPackage(packageInput(), authority), other = ['unrelated',0,0,0,2,100,null,null,[]];
  const input = {partsByRegion: {jp: [[LINE,0,0,5,48,4378.1,null,null,[]], other]},
    byRegion: {jp: [['unrelated',0,0,50,-1]]}, followsByRegion: {jp: []}, colorByRegion: {jp: {unrelated: 'blue'}}};
  const result = repairParts(pkg, input, authority), row = result.partsByRegion.jp[0];
  assert.deepEqual(row.slice(2,4), [-1,-1]);
  assert.deepEqual(row[7], net.displayPartsForLine(pkg.lines[0])[0]);
  assert.deepEqual(row[7].at(-1), [139.7471446220207,35.53493575339516]);
  assert.equal(row[4], row[7].length);
  assert.deepEqual(result.partsByRegion.jp[1], other);
  for (const k of Object.keys(input).filter(k => k !== 'partsByRegion')) assert.deepEqual(result[k], input[k]);
  assert.deepEqual(repairParts(pkg, result, authority), result);
  for (const change of [x => x.partsByRegion.jp[0][4]++, x => x.partsByRegion.jp[0][1] = 1,
    x => x.partsByRegion.jp.push(x.partsByRegion.jp[0]), x => x.partsByRegion.jp.shift()]) {
    const bad = structuredClone(input); change(bad);
    assert.throws(() => repairParts(pkg, bad, authority), /stale\/foreign own native row/);
  }
  const foreign = structuredClone(input); foreign.followsByRegion.jp.push(['unrelated',0,0,1,LINE,0,0,1]);
  assert.throws(() => repairParts(pkg, foreign, authority), /own native reference requires review/);
});

test('repair refuses the rejected roof/intertrack point and changes outside the exact physical baseline', () => {
  const bad = structuredClone(authority);
  bad.displayStationCoordinate = [139.7470990249634,35.5348931915326];
  assert.throws(() => repairPackage(packageInput(), bad), /upper-track target changed/);
  const roof = structuredClone(authority); roof.supportAuthority.at(-1).pixel = [1030,884];
  assert.throws(() => repairPackage(packageInput(), roof), /own-track pixel authority changed/);
  const changed = packageInput(); changed.lines[0].segments[0][0] += .01;
  assert.throws(() => repairPackage(changed, authority), /current own source changed/);
  const wrongStation = packageInput(); wrongStation.lines[0].stations[6][0] = 'foreign';
  assert.throws(() => repairPackage(wrongStation, authority), /current own source changed/);
});
