import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { repairPackage, repairParts } from '../repair-kisuki-minami-daito-display.mjs';
const network = createRequire(import.meta.url)('../../../public/rail-network.js');
const stroke = createRequire(import.meta.url)('../../../public/rail-stroke.js');
const read = relative => JSON.parse(fs.readFileSync(new URL(relative, import.meta.url)));
const evidence = read('../kisuki-minami-daito-display-evidence.json');

test('Minami-Daito shares the identified passenger rail anchor across both display approaches', () => {
  const pkg = read('../../../public/rail/jp-2025.json');
  const line = pkg.lines.find(row => row.id === evidence.lineID);
  const anchor = [132.9280737672415, 35.30806118393788];
  assert.deepEqual(line.displayStationCoordinates['005094'], anchor);
  assert.deepEqual(line.displayIntervalCoordinates[4].at(-1), anchor);
  assert.deepEqual(line.displayIntervalCoordinates[5][0], anchor);
  const parts = network.displayPartsForLine(line);
  assert(parts.some(part => part.some(p => p[0] === 132.9295752 && p[1] === 35.3076292)),
    'Eastern passenger-rail curve support must reach the actual display');
  assert(parts.some(part => part.some(p => p[0] === anchor[0] && p[1] === anchor[1])),
    'Station must remain on the display stroke');
});

test('bounded approaches preserve physical fields, outside supports and prior Miinohara/reversal work on replay', () => {
  const original = { lines: [structuredClone(evidence.baselineLine), { id: 'unrelated', stations: [] }], geometrySource: {} };
  const repaired = repairPackage(original, evidence), line = repaired.lines[0];
  assert.deepEqual(line.stations, original.lines[0].stations);
  assert.deepEqual(line.segments, original.lines[0].segments);
  assert.deepEqual(line.reversalTails, original.lines[0].reversalTails);
  assert.deepEqual(repaired.lines[1], original.lines[1]);
  const physical = network.decodeIntervals(original.lines[0]);
  assert.deepEqual(line.displayIntervalCoordinates[4].slice(0, 64), physical[4].slice(0, 64));
  assert.deepEqual(line.displayIntervalCoordinates[5].slice(-physical[5].slice(12).length), physical[5].slice(12));
  for (const i of [14, 15]) assert.deepEqual(line.displayIntervalCoordinates[i], original.lines[0].displayIntervalCoordinates[i]);
  assert.deepEqual(line.displayStationCoordinates['005725'], original.lines[0].displayStationCoordinates['005725']);
  assert.deepEqual(repairPackage(repaired, evidence), repaired);
  const lanes = { partsByRegion: { jp: structuredClone(evidence.baselineNativeRows) } };
  for (const [key, rows] of Object.entries(evidence.baselineMeasuredReferences)) lanes[key] = { jp: structuredClone(rows) };
  const native = repairParts(repaired, lanes, evidence);
  for (const i of [0, 2]) assert.deepEqual(native.partsByRegion.jp[i], lanes.partsByRegion.jp[i]);
  assert.deepEqual(repairParts(repaired, native, evidence), native);
});

test('unreviewed passenger graph, unrelated source edits and changed measured references are rejected', () => {
  const fixture = () => ({ lines: [structuredClone(evidence.baselineLine)], geometrySource: {} });
  for (const alter of [e => e.ways[0].nodes[0]++, e => e.ways[0].tags.service = 'siding']) {
    const changed = structuredClone(evidence); alter(changed);
    assert.throws(() => repairPackage(fixture(), changed));
  }
  const changed = fixture(); changed.lines[0].segments[0][0] += 1;
  assert.throws(() => repairPackage(changed, evidence), /Unreviewed Kisuki dependency/);
  const repaired = repairPackage(fixture(), evidence);
  const lanes = { partsByRegion: { jp: structuredClone(evidence.baselineNativeRows) } };
  for (const [key, rows] of Object.entries(evidence.baselineMeasuredReferences)) lanes[key] = { jp: structuredClone(rows) };
  lanes.followsByRegion.jp.push([evidence.lineID, 1, 0, 300, 'unreviewed', 0, 0, 300]);
  assert.throws(() => repairParts(repaired, lanes, evidence), /measured references require separate review/);
});

test('physical passenger rides retain their station identities while mapping to the repaired rail in either direction', () => {
  const repaired = repairPackage({ lines: [structuredClone(evidence.baselineLine)], geometrySource: {} }, evidence);
  const line = repaired.lines[0];
  const net = network.buildNetworkFromCompactPackage({ ...repaired, format: 'compact-v1', country: 'jp' });
  const intervals = network.decodeIntervals(line);
  for (const i of [4, 5]) for (const reverse of [false, true]) {
    const from = line.stations[reverse ? i + 1 : i], to = line.stations[reverse ? i : i + 1];
    const source = reverse ? intervals[i].toReversed() : intervals[i];
    const feature = { type: 'Feature', geometry: { type: 'LineString', coordinates: source }, properties: {
      from_n02_station_code: from[0], to_n02_station_code: to[0],
      required_line_names: [line.name], required_operator_names: [line.operator],
      section_codes: [`${line.id}@${[from[0], to[0]].sort().join(':')}`] } };
    const mapped = network.canonicalizeRouteFeature(net, feature);
    assert(mapped, 'Physical interval failed to map to reviewed display');
    const parts = mapped.geometry.type === 'LineString' ? [mapped.geometry.coordinates] : mapped.geometry.coordinates;
    const coordinate = station => line.displayStationCoordinates?.[station[0]] || station.slice(2, 4);
    assert.deepEqual(parts[0][0], coordinate(from));
    assert.deepEqual(parts.at(-1).at(-1), coordinate(to));
    assert.deepEqual(feature.geometry.coordinates, source, 'Physical ride input mutated');
  }
});

test('reviewed approach seams have no artificial hard corner in the production stroke', () => {
  const pkg = read('../../../public/rail/jp-2025.json');
  const line = pkg.lines.find(row => row.id === evidence.lineID);
  for (const seam of evidence.seamAliases) {
    const origin = seam.point, scale = Math.cos(origin[1] * Math.PI / 180);
    const points = line.displayIntervalCoordinates[seam.interval]
      .map(p => [(p[0] - origin[0]) * 111320 * scale, (p[1] - origin[1]) * 111320]);
    const measures = [0];
    for (let i = 1; i < points.length; i++) measures.push(measures.at(-1) + Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]));
    for (const pixelsPerMetre of [1, 4]) {
      const rendered = stroke.buildStroke(points.map(p => p.map(v => v * pixelsPerMetre)), {
        measures, anchors: [0, points.length - 1], rows: [], totalMetres: measures.at(-1),
        laneGapPx: 0, cornerRadiusPx: 3.6, minRampPx: 24 });
      let worst = 0;
      for (let i = 1; i < rendered.points.length - 1; i++) {
        const p = rendered.points[i];
        if (Math.hypot(...p) > 150 * pixelsPerMetre) continue;
        const a = [p[0] - rendered.points[i - 1][0], p[1] - rendered.points[i - 1][1]],
          b = [rendered.points[i + 1][0] - p[0], rendered.points[i + 1][1] - p[1]];
        worst = Math.max(worst, Math.abs(Math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1])) * 180 / Math.PI);
      }
      assert(worst < 20, `Interval${seam.interval} preserved an artificial ${worst.toFixed(2)}° seam corner`);
    }
  }
});
