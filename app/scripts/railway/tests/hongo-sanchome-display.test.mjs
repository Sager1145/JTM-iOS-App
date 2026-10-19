import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { buildCandidate, identifiedAnchors, repairPackage, repairParts } from '../repair-hongo-sanchome-display.mjs';

const network = createRequire(import.meta.url)('../../../public/rail-network.js');
const stroke = createRequire(import.meta.url)('../../../public/rail-stroke.js');
const read = relative => JSON.parse(fs.readFileSync(new URL(relative, import.meta.url), 'utf8'));
const evidence = read('../hongo-sanchome-display-evidence.json');

test('identified opposing passenger stops own separate M21 and E08 display aliases', () => {
  const anchors = identifiedAnchors(evidence);
  assert.deepEqual(anchors.Marunouchi003546, [139.7601239, 35.70650045]);
  assert.deepEqual(anchors.Oedo003546, [139.7605393, 35.7075349]);
  assert.notDeepEqual(anchors.Marunouchi003546, evidence.aggregateSearchCoordinate);
  assert.notDeepEqual(anchors.Oedo003546, evidence.aggregateSearchCoordinate);
});

test('repair is display-only, bounded, idempotent and preserves independent circles', () => {
  const input = read('../../../public/rail/jp-2025.json'), repaired = repairPackage(input, evidence);
  for (const item of evidence.lines) {
    const before = input.lines.find(row => row.id === item.lineID), after = repaired.lines.find(row => row.id === item.lineID);
    assert.deepEqual(after.stations, before.stations);
    assert.deepEqual(after.segments, before.segments);
    assert.deepEqual(after.displayStationCoordinates['003546'], item.displayAnchor);
    assert.equal(after.stationCircleOwnerByCode?.['003546'], undefined);
    const physical = network.decodeIntervals(before);
    for (const approach of item.approaches) {
      const display = after.displayIntervalCoordinates[approach.interval];
      const endpoint = approach.endpoint === 'last' ? display.at(-1) : display[0];
      assert.deepEqual(endpoint, item.displayAnchor);
      if (approach.endpoint === 'last') assert.deepEqual(display.slice(0, approach.boundaryIndex + 1), physical[approach.interval].slice(0, approach.boundaryIndex + 1));
      else assert.deepEqual(display.slice(approach.boundaryIndex), physical[approach.interval].slice(approach.boundaryIndex));
    }
  }
  assert.deepEqual(repairPackage(repaired, evidence), repaired);
});

test('source identity drift, physical-row drift and circle merging fail closed', () => {
  const input = read('../../../public/rail/jp-2025.json');
  const changedEvidence = structuredClone(evidence);
  changedEvidence.lines[0].opposedStops[0].coordinate[0] += 0.001;
  assert.throws(() => identifiedAnchors(changedEvidence), /stop coordinate changed/);
  const physical = structuredClone(input);
  physical.lines.find(row => row.id === evidence.lines[0].lineID).stations[4][2] += 0.001;
  assert.throws(() => repairPackage(physical, evidence), /physicalStation|dependency changed/);
  const merged = structuredClone(input);
  merged.lines.find(row => row.id === evidence.lines[1].lineID).stationCircleOwnerByCode = { '003546': evidence.lines[0].lineID };
  assert.throws(() => repairPackage(merged, evidence), /dependency changed|independent circle/);
});

test('candidate refreshes the exact native parts and Oedo loop anchor index 407', () => {
  const pkg = read('../../../public/rail/jp-2025.json'), lanes = read('../../../public/rail/display-lanes.json');
  const candidate = buildCandidate(pkg, lanes, evidence);
  for (const item of evidence.lines) {
    const line = candidate.pkg.lines.find(row => row.id === item.lineID), parts = network.displayPartsForLine(line);
    assert.deepEqual(parts[0][item.nativePart.anchorIndex], item.displayAnchor);
    assert.equal(parts[0].length, item.nativePart.vertexCount);
    assert.equal(candidate.lanes.partsByRegion.jp.filter(row => row[0] === item.lineID).length, 1);
  }
  const oedo = candidate.summary.find(row => row.key === 'Oedo003546');
  assert.equal(oedo.anchorIndex, 407);
  assert.equal(candidate.lanes.byRegion.jp.find(row => row[0] === evidence.lines[1].lineID)[3], oedo.afterMetres);
  const marunouchi = candidate.summary.find(row => row.key === 'Marunouchi003546');
  assert.notDeepEqual(marunouchi.measureRemap.byRegion.before, marunouchi.measureRemap.byRegion.after);
  assert.deepEqual(repairParts(candidate.pkg, candidate.lanes, evidence), candidate.lanes);
});

test('production strokes do not introduce steps at the Hongo station joins or fixed taper boundaries', () => {
  const candidate = repairPackage(read('../../../public/rail/jp-2025.json'), evidence);
  for (const item of evidence.lines) {
    const line = candidate.lines.find(row => row.id === item.lineID);
    const origin = item.displayAnchor, scale = Math.cos(origin[1]*Math.PI/180);
    const points = network.displayPartsForLine(line)[0].map(p =>
      [(p[0]-origin[0])*111320*scale,(p[1]-origin[1])*111320]);
    const seams = [[0,0], ...item.approaches.map(row =>
      [(row.boundaryCoordinate[0]-origin[0])*111320*scale,
       (row.boundaryCoordinate[1]-origin[1])*111320])];
    const measures = [0];
    for (let i=1;i<points.length;i++) measures.push(measures.at(-1)+Math.hypot(points[i][0]-points[i-1][0],points[i][1]-points[i-1][1]));
    for (const pixelsPerMetre of [1,4]) {
      const rendered = stroke.buildStroke(points.map(p => p.map(v => v*pixelsPerMetre)), {
        measures, anchors:[item.nativePart.anchorIndex], rows:[], totalMetres:measures.at(-1),
        laneGapPx:0,cornerRadiusPx:3.6,minRampPx:24 });
      let worst=0;
      for (let i=1;i<rendered.points.length-1;i++) {
        const p=rendered.points[i];
        if (!seams.some(q => Math.hypot(p[0]-q[0]*pixelsPerMetre,p[1]-q[1]*pixelsPerMetre)<15*pixelsPerMetre)) continue;
        const a=[p[0]-rendered.points[i-1][0],p[1]-rendered.points[i-1][1]],b=[rendered.points[i+1][0]-p[0],rendered.points[i+1][1]-p[1]];
        worst=Math.max(worst,Math.abs(Math.atan2(a[0]*b[1]-a[1]*b[0],a[0]*b[0]+a[1]*b[1]))*180/Math.PI);
      }
      assert(worst<20, `${item.key} contains a ${worst.toFixed(2)} degree local step`);
    }
  }
});
