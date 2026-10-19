#!/usr/bin/env node
// Candidate-only reconstruction of the Toei Mita display stroke from the
// labelled Apple Maps railway glyph. Production resources are never written.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { partRowsForLine } from './build-display-lanes.mjs';

export const LINE = 'jp-東京都-6号線三田線';
const STAGE = 'mita-apple-cartography-display';
const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.resolve(APP, '..');
const require = createRequire(import.meta.url);
const network = require('../../public/rail-network.js');
const json = file => JSON.parse(fs.readFileSync(file));
const hash = value => crypto.createHash('sha256').update(Buffer.isBuffer(value) || typeof value === 'string' ? value : JSON.stringify(value)).digest('hex');
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const evidenceDefault = () => json(path.resolve(APP, 'scripts/railway/mita-apple-display-evidence.json'));
const packageDefault = () => json(path.resolve(APP, 'public/rail/jp-2025.json'));
const lanesDefault = () => json(path.resolve(APP, 'public/rail/display-lanes.json'));

function metres(a, b) {
  const lat = (a[1] + b[1]) * Math.PI / 360;
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos(lat), (b[1] - a[1]) * 111320);
}
function localVector(a, b) {
  const lat = (a[1] + b[1]) * Math.PI / 360;
  return [(b[0] - a[0]) * 111320 * Math.cos(lat), (b[1] - a[1]) * 111320];
}
function move(point, vector) {
  return [point[0] + vector[0] / (111320 * Math.cos(point[1] * Math.PI / 180)), point[1] + vector[1] / 111320];
}
function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  if (!sorted.length) return null;
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}
const medianVector = vectors => [median(vectors.map(row => row[0])), median(vectors.map(row => row[1]))];

function baselineModel(pkg, evidence) {
  const lineIndex = pkg.lines.findIndex(row => row.id === LINE);
  assert.equal(lineIndex, evidence.baseline.packageLineIndex, 'Mita owning line index changed');
  const line = pkg.lines[lineIndex];
  const physical = structuredClone(line);
  delete physical.displayStationCoordinates;
  delete physical.displayIntervalCoordinates;
  assert.equal(hash(physical), evidence.baseline.owningLineSHA256, 'Mita physical source changed');
  const intervals = network.decodeIntervals(physical);
  assert.equal(hash(intervals), evidence.baseline.decodedIntervalsSHA256, 'Mita decoded baseline changed');
  const points = [], segments = [], intervalStarts = [], stationMeasures = [0];
  let measure = 0;
  intervals.forEach((coordinates, interval) => {
    intervalStarts.push(measure);
    coordinates.forEach((coordinate, index) => {
      if (points.length && index === 0) {
        assert.deepEqual(coordinate, points.at(-1), `Mita interval ${interval} baseline seam changed`);
        return;
      }
      if (points.length) {
        const length = metres(points.at(-1), coordinate);
        segments.push({ index: segments.length, interval, from: points.length - 1, to: points.length,
          start: measure, end: measure + length, length });
        measure += length;
      }
      points.push(coordinate);
    });
    stationMeasures.push(measure);
  });
  assert.equal(points.length, evidence.baseline.decodedVertexCount);
  assert(Math.abs(measure - evidence.baseline.decodedLengthMetres) < 0.001, 'Mita decoded baseline length changed');
  return { lineIndex, line: physical, intervals, points, segments, intervalStarts, stationMeasures, total: measure };
}

function projectSeed(seed, model) {
  const candidates = [];
  for (const segment of model.segments) {
    const a = model.points[segment.from], b = model.points[segment.to];
    const latitude = (a[1] + b[1] + seed[1]) / 3 * Math.PI / 180;
    const scaleX = 111320 * Math.cos(latitude), scaleY = 111320;
    const vx = (b[0] - a[0]) * scaleX, vy = (b[1] - a[1]) * scaleY;
    const px = (seed[0] - a[0]) * scaleX, py = (seed[1] - a[1]) * scaleY;
    const fraction = Math.max(0, Math.min(1, (px * vx + py * vy) / (vx * vx + vy * vy || 1)));
    const coordinate = [a[0] + fraction * (b[0] - a[0]), a[1] + fraction * (b[1] - a[1])];
    candidates.push({ segment, fraction, coordinate, error: metres(seed, coordinate),
      measure: segment.start + fraction * segment.length });
  }
  candidates.sort((a, b) => a.error - b.error);
  const best = candidates[0];
  const competition = candidates.find(row => Math.abs(row.measure - best.measure) > 50
    && row.error <= Math.max(5, best.error + 2));
  return { ...best, discontinuousCompetition: Boolean(competition) };
}

function sourceBins(model, evidence) {
  const grouped = new Map();
  const audit = { embeddedSamples: 0, acceptedSamples: 0, projectionRejected: 0,
    discontinuousCompetitionRejected: 0, overBoundRejected: 0, insufficientViews: 0,
    vectorDisagreement: 0, longitudinalDiscontinuityRejected: 0 };
  for (const record of evidence.apple.records) for (const sample of record.samples) {
    audit.embeddedSamples += 1;
    assert(sample.supported && sample.ambiguity < evidence.policy.maximumAmbiguity,
      `${record.file}: evidence retained an ineligible sample`);
    const projected = projectSeed(sample.seed, model);
    if (projected.error > evidence.policy.maximumProjectionErrorMetres) { audit.projectionRejected += 1; continue; }
    if (projected.discontinuousCompetition) { audit.discontinuousCompetitionRejected += 1; continue; }
    const extracted = localVector(sample.seed, sample.point);
    const a = model.points[projected.segment.from], b = model.points[projected.segment.to];
    const tangent = localVector(a, b), length = Math.hypot(...tangent);
    const normal = [-tangent[1] / length, tangent[0] / length];
    const scalar = extracted[0] * normal[0] + extracted[1] * normal[1];
    const vector = [normal[0] * scalar, normal[1] * scalar];
    const maximumCorrection = evidence.policy.maximumCorrectionByInterval?.[projected.segment.interval]
      ?? evidence.policy.maximumCorrectionMetres;
    if (Math.hypot(...vector) > maximumCorrection) { audit.overBoundRejected += 1; continue; }
    const bin = Math.floor(projected.measure / evidence.policy.binMetres) * evidence.policy.binMetres;
    if (!grouped.has(bin)) grouped.set(bin, new Map());
    const views = grouped.get(bin);
    if (!views.has(record.file)) views.set(record.file, []);
    views.get(record.file).push(vector);
    audit.acceptedSamples += 1;
  }
  const accepted = [];
  for (const [bin, views] of [...grouped].sort((a, b) => a[0] - b[0])) {
    if (views.size < evidence.policy.minimumDistinctViews) { audit.insufficientViews += 1; continue; }
    const vectors = [...views.entries()].map(([file, values]) => ({ file, vector: medianVector(values) }));
    let disagreement = 0;
    for (let i = 0; i < vectors.length; i += 1) for (let j = i + 1; j < vectors.length; j += 1)
      disagreement = Math.max(disagreement, Math.hypot(vectors[i].vector[0] - vectors[j].vector[0], vectors[i].vector[1] - vectors[j].vector[1]));
    if (disagreement > evidence.policy.maximumVectorDisagreementMetres) { audit.vectorDisagreement += 1; continue; }
    const measure = Math.min(bin + evidence.policy.binMetres / 2, model.total);
    const interval = model.stationMeasures.findIndex((value, index) => index > 0 && measure <= value) - 1;
    accepted.push({ measure, interval, vector: medianVector(vectors.map(row => row.vector)),
      files: vectors.map(row => row.file), maximumDisagreementMetres: disagreement });
  }
  // Smooth only already accepted evidence; this cannot bridge an unsupported gap.
  const smoothed = accepted.map(bin => {
    const nearby = accepted.filter(row => Math.abs(row.measure - bin.measure) <= evidence.policy.smoothingRadiusMetres);
    return { ...bin, rawVector: bin.vector, vector: medianVector(nearby.map(row => row.vector)) };
  });
  // Measure order is the continuity gate: every accepted control projected
  // monotonically onto this one identified Mita chain. Projecting onto a
  // competing, discontinuous piece was rejected above. A large change in the
  // baseline-to-glyph vector alone is not discontinuity; it is exactly what a
  // coarse baseline cutting away from a labelled curve produces.
  return { bins: smoothed, audit };
}

function fieldAt(measure, anchors, baseAt, maxGap, maximumCorrection) {
  const beforeIndex = anchors.findLastIndex(row => row.measure <= measure);
  const afterIndex = anchors.findIndex(row => row.measure >= measure);
  const before = anchors[beforeIndex], after = anchors[afterIndex];
  if (before && after && before === after) return { vector: before.vector, method: before.method || 'supported' };
  if (before && after && after.measure - before.measure <= maxGap) {
    const t = (measure - before.measure) / (after.measure - before.measure || 1);
    const target = anchor => move(baseAt(anchor.measure), anchor.vector);
    const left = target(before), right = target(after), chord = localVector(left, right);
    const previous = anchors[Math.max(0, beforeIndex - 1)], following = anchors[Math.min(anchors.length - 1, afterIndex + 1)];
    const previousTarget = target(previous), followingTarget = target(following);
    const leftSpan = Math.max(1, after.measure - previous.measure), rightSpan = Math.max(1, following.measure - before.measure);
    let leftTangent = localVector(previousTarget, right).map(value => value / leftSpan);
    let rightTangent = localVector(left, followingTarget).map(value => value / rightSpan);
    const forward = tangent => tangent[0] * chord[0] + tangent[1] * chord[1] > 0;
    const mutuallyForward = leftTangent[0] * rightTangent[0] + leftTangent[1] * rightTangent[1] >= 0;
    let offset;
    if (forward(leftTangent) && forward(rightTangent) && mutuallyForward) {
      const cap = tangent => {
        const length = Math.hypot(...tangent), scale = length > 1.5 ? 1.5 / length : 1;
        return tangent.map(value => value * scale);
      };
      leftTangent = cap(leftTangent); rightTangent = cap(rightTangent);
      const gap = after.measure - before.measure, t2 = t * t, t3 = t2 * t;
      offset = [
        (2 * t3 - 3 * t2 + 1) * 0 + (t3 - 2 * t2 + t) * leftTangent[0] * gap
          + (-2 * t3 + 3 * t2) * chord[0] + (t3 - t2) * rightTangent[0] * gap,
        (2 * t3 - 3 * t2 + 1) * 0 + (t3 - 2 * t2 + t) * leftTangent[1] * gap
          + (-2 * t3 + 3 * t2) * chord[1] + (t3 - t2) * rightTangent[1] * gap,
      ];
    } else offset = chord.map(value => value * t);
    const targetCoordinate = move(left, offset), vector = localVector(baseAt(measure), targetCoordinate);
    const magnitude = Math.hypot(...vector);
    return { vector: magnitude > maximumCorrection ? vector.map(value => value * maximumCorrection / magnitude) : vector,
      method: forward(leftTangent) && forward(rightTangent) && mutuallyForward
        ? 'source-curve-interpolated-gap<=200m' : 'source-linear-interpolated-gap<=200m' };
  }
  const fromBefore = before ? measure - before.measure : Infinity;
  const toAfter = after ? after.measure - measure : Infinity;
  if (fromBefore <= maxGap && fromBefore <= toAfter)
    return { vector: before.vector.map(value => value * (1 - fromBefore / maxGap)), method: 'taper-to-zero' };
  if (toAfter <= maxGap)
    return { vector: after.vector.map(value => value * (1 - toAfter / maxGap)), method: 'taper-from-zero' };
  return { vector: [0, 0], method: 'unsupported-zero' };
}

function pointAtInterval(points, measures, target) {
  if (target <= 0) return points[0];
  if (target >= measures.at(-1)) return points.at(-1);
  let index = 1;
  while (measures[index] < target) index += 1;
  const t = (target - measures[index - 1]) / (measures[index] - measures[index - 1]);
  return [points[index - 1][0] * (1 - t) + points[index][0] * t, points[index - 1][1] * (1 - t) + points[index][1] * t];
}
function perpendicularDistance(point, a, b) {
  const latitude = (a[1] + b[1] + point[1]) / 3 * Math.PI / 180;
  const sx = 111320 * Math.cos(latitude), sy = 111320;
  const vx = (b[0] - a[0]) * sx, vy = (b[1] - a[1]) * sy, px = (point[0] - a[0]) * sx, py = (point[1] - a[1]) * sy;
  const t = Math.max(0, Math.min(1, (px * vx + py * vy) / (vx * vx + vy * vy || 1)));
  return Math.hypot(px - t * vx, py - t * vy);
}
function simplify(points, tolerance) {
  if (points.length <= 2) return points;
  let furthest = 0, index = 0;
  for (let i = 1; i < points.length - 1; i += 1) {
    const distance = perpendicularDistance(points[i], points[0], points.at(-1));
    if (distance > furthest) { furthest = distance; index = i; }
  }
  if (furthest <= tolerance) return [points[0], points.at(-1)];
  return [...simplify(points.slice(0, index + 1), tolerance).slice(0, -1), ...simplify(points.slice(index), tolerance)];
}

/** Build a deterministic Apple-cartography candidate without mutating its package. */
export function buildCandidate(input = packageDefault(), evidence = evidenceDefault()) {
  assert.equal(evidence.format, 'jtm-mita-apple-display-evidence-v1');
  assert.equal(evidence.lineID, LINE);
  assert.equal(hash(evidence.apple.records), evidence.apple.embeddedRecordsSHA256,
    'Mita Apple embedded evidence changed');
  assert.equal(hash(evidence.apple.records.map(row => ({ file: row.file, sha256: row.sha256,
    interval: row.interval, ordinal: row.ordinal }))), evidence.apple.manifestSHA256,
  'Mita Apple source manifest changed');
  assert.deepEqual(evidence.identity.routeRelationIDs, [443286, 8019910], 'Mita OSM identity reference changed');
  assert.equal(evidence.apple.records.length, 115, 'Mita Apple evidence must retain all 115 view records');
  assert.equal(new Set(evidence.apple.records.map(row => row.file)).size, 115, 'Mita Apple view filenames must be unique');
  assert.deepEqual([...new Set(evidence.apple.records.map(row => row.interval))].sort((a, b) => a - b), [...Array(26).keys()],
    'Mita Apple evidence does not cover all 26 intervals');
  const model = baselineModel(input, evidence);
  const { bins, audit } = sourceBins(model, evidence);
  const supportedByInterval = Array.from({ length: 26 }, (_, interval) => bins.filter(row => {
    const start = model.stationMeasures[interval], end = model.stationMeasures[interval + 1];
    return row.measure >= start && row.measure <= end;
  }));
  const stationVectors = model.stationMeasures.map((measure, station) => {
    if (station <= 6 || station === 26 || !supportedByInterval[station - 1]?.length || !supportedByInterval[station]?.length) return [0, 0];
    const nearby = bins.filter(row => Math.abs(row.measure - measure) <= evidence.policy.smoothingRadiusMetres);
    if (!nearby.length) return [0, 0];
    const vector = medianVector(nearby.map(row => row.vector));
    const bound = Math.min(evidence.policy.maximumCorrectionByInterval?.[station - 1] ?? evidence.policy.maximumCorrectionMetres,
      evidence.policy.maximumCorrectionByInterval?.[station] ?? evidence.policy.maximumCorrectionMetres);
    const magnitude = Math.hypot(...vector);
    return magnitude > bound ? vector.map(value => value * bound / magnitude) : vector;
  });
  const intervals = [], methods = {};
  for (let interval = 0; interval < 26; interval += 1) {
    const baseline = model.intervals[interval];
    if (interval <= 5 || !supportedByInterval[interval].length) {
      intervals.push(structuredClone(baseline)); methods[interval] = { changed: false, reason: interval <= 5 ? 'north-0-5-frozen' : 'unsupported-interval' }; continue;
    }
    const localMeasures = [0];
    for (let index = 1; index < baseline.length; index += 1) localMeasures.push(localMeasures.at(-1) + metres(baseline[index - 1], baseline[index]));
    const start = model.stationMeasures[interval], end = model.stationMeasures[interval + 1];
    const anchors = [{ measure: start, vector: stationVectors[interval], method: 'station-field' },
      ...supportedByInterval[interval], { measure: end, vector: stationVectors[interval + 1], method: 'station-field' }]
      .sort((a, b) => a.measure - b.measure);
    const measures = new Set([0, localMeasures.at(-1), ...localMeasures]);
    for (let value = 0; value < localMeasures.at(-1); value += evidence.policy.maximumSampleSpacingMetres) measures.add(value);
    for (const anchor of anchors) measures.add(Math.max(0, Math.min(localMeasures.at(-1), anchor.measure - start)));
    const baseAt = globalMeasure => pointAtInterval(baseline, localMeasures, globalMeasure - start);
    const maximumCorrection = evidence.policy.maximumCorrectionByInterval?.[interval]
      ?? evidence.policy.maximumCorrectionMetres;
    const sourceGapMetres = anchors.slice(1).map((anchor, index) => anchor.measure - anchors[index].measure)
      .filter(gap => gap > evidence.policy.binMetres * 2 && gap <= evidence.policy.maximumInterpolatedGapMetres);
    let interpolationPoints = 0, taperPoints = 0, curveInterpolationPoints = 0, linearInterpolationPoints = 0;
    const corrected = [...measures].sort((a, b) => a - b).map(local => {
      const base = pointAtInterval(baseline, localMeasures, local);
      let result = fieldAt(start + local, anchors, baseAt, evidence.policy.maximumInterpolatedGapMetres, maximumCorrection);
      if (interval === 25 && local > localMeasures.at(-1) - evidence.policy.meguroTaperMetres) {
        const factor = Math.max(0, (localMeasures.at(-1) - local) / evidence.policy.meguroTaperMetres);
        result = { vector: result.vector.map(value => value * factor), method: `${result.method}+meguro-taper` };
      }
      const magnitude = Math.hypot(...result.vector);
      assert(magnitude <= maximumCorrection + 1e-6,
        `Mita interval ${interval} correction exceeds ${maximumCorrection}m`);
      if (result.method.includes('interpolated')) interpolationPoints += 1;
      if (result.method.includes('source-curve')) curveInterpolationPoints += 1;
      if (result.method.includes('source-linear')) linearInterpolationPoints += 1;
      if (result.method.includes('taper')) taperPoints += 1;
      return move(base, result.vector);
    });
    corrected[0] = move(baseline[0], stationVectors[interval]);
    corrected[corrected.length - 1] = move(baseline.at(-1), stationVectors[interval + 1]);
    const simplified = simplify(corrected, evidence.policy.maximumSimplificationErrorMetres);
    intervals.push(simplified);
    methods[interval] = { changed: !same(simplified, baseline), supportedBins: supportedByInterval[interval].length,
      sourceGapMetres, interpolationPoints, curveInterpolationPoints, linearInterpolationPoints,
      taperPoints, inputVertices: corrected.length, outputVertices: simplified.length };
  }
  for (let interval = 0; interval < 25; interval += 1)
    assert.deepEqual(intervals[interval].at(-1), intervals[interval + 1][0], `Mita candidate station seam ${interval + 1} changed`);
  assert.deepEqual(intervals[25].at(-1), model.intervals[25].at(-1), 'Mita registered Meguro endpoint changed');
  const stationAliases = Object.fromEntries(model.line.stations.map((station, index) => [station[0], intervals[Math.min(index, 25)][index === 26 ? intervals[25].length - 1 : 0]]));
  const candidate = { intervals, stationAliases, bins, audit, methods };
  if (evidence.candidate?.coordinatesSHA256)
    assert.equal(hash(intervals), evidence.candidate.coordinatesSHA256, 'Mita Apple candidate changed');
  return candidate;
}

function stageRecord(evidence, candidate) {
  return { reviewedAt: evidence.reviewedAt, script: 'app/scripts/railway/repair-mita-apple-display.mjs',
    evidence: 'app/scripts/railway/mita-apple-display-evidence.json', lineID: LINE,
    source: 'Apple Maps labelled transit cartography extracted from 115 retained native basemap views',
    sourceManifestSHA256: evidence.apple.manifestSHA256, extractorCodeSHA256: evidence.apple.extractorCodeSHA256,
    rawOSMIdentitySHA256: evidence.identity.rawOSMSHA256, changedIntervals: Object.entries(candidate.methods).filter(([, row]) => row.changed).map(([key]) => Number(key)),
    physicalTopologyChanged: false, acceptance: 'display reference reviewed across 26 complete native intervals / 115 views; Main composition checked separately' };
}

/** Add display-only Apple interval overrides while preserving the physical line. */
export function repairPackage(input = packageDefault(), evidence = evidenceDefault()) {
  const candidate = buildCandidate(input, evidence), pkg = structuredClone(input);
  const line = pkg.lines[evidence.baseline.packageLineIndex];
  const aliases = candidate.stationAliases;
  const overrides = Object.fromEntries(candidate.intervals.map((coordinates, interval) => [interval, coordinates]));
  assert(!line.displayStationCoordinates || same(line.displayStationCoordinates, aliases), 'Mita competing station display override');
  assert(!line.displayIntervalCoordinates || same(line.displayIntervalCoordinates, overrides), 'Mita competing interval display override');
  line.displayStationCoordinates = structuredClone(aliases);
  line.displayIntervalCoordinates = structuredClone(overrides);
  pkg.geometrySource.manualOverrides ||= {};
  const record = stageRecord(evidence, candidate);
  assert(!pkg.geometrySource.manualOverrides[STAGE] || same(pkg.geometrySource.manualOverrides[STAGE], record), 'Mita competing Apple candidate provenance');
  pkg.geometrySource.manualOverrides[STAGE] = record;
  return pkg;
}

function displayedLine(line) {
  return { ...line,
    stations: line.stations.map(row => [...row.slice(0, 2), ...(line.displayStationCoordinates?.[row[0]] || row.slice(2, 4)), ...row.slice(4)]),
    segments: line.segments.map((row, index) => line.displayIntervalCoordinates?.[index] ? [row[0], 0, line.displayIntervalCoordinates[index]] : row) };
}
function cumulative(points) { const result = [0]; for (let i = 1; i < points.length; i += 1) result.push(result.at(-1) + metres(points[i - 1], points[i])); return result; }
function pointAt(points, measures, measure) { return pointAtInterval(points, measures, measure); }
function projectPoint(point, a, b) {
  const lat = (a[1] + b[1] + point[1]) / 3 * Math.PI / 180, sx = 111320 * Math.cos(lat), sy = 111320;
  const vx = (b[0] - a[0]) * sx, vy = (b[1] - a[1]) * sy, px = (point[0] - a[0]) * sx, py = (point[1] - a[1]) * sy;
  const fraction = Math.max(0, Math.min(1, (px * vx + py * vy) / (vx * vx + vy * vy || 1)));
  const coordinate = [a[0] + fraction * (b[0] - a[0]), a[1] + fraction * (b[1] - a[1])];
  return { fraction, coordinate, displacementMetres: metres(point, coordinate) };
}
function mapReferences(line, beforePart, afterPart, evidence) {
  const oldPoints = beforePart[7], newPoints = afterPart[7], oldMeasures = cumulative(oldPoints), newMeasures = cumulative(newPoints);
  const locate = (points, coordinate) => points.findIndex(row => same(row, coordinate));
  const oldStations = line.stations.map(row => locate(oldPoints, row.slice(2, 4)));
  const newStations = line.stations.map(row => locate(newPoints, line.displayStationCoordinates[row[0]]));
  assert(oldStations.every(row => row >= 0) && newStations.every(row => row >= 0), 'Mita station seam missing from native part');
  const stationMeasures = oldStations.map(index => oldMeasures[index]);
  function map(measure) {
    const terminal = Math.abs(measure - oldMeasures.at(-1)) <= 0.2;
    const bounded = terminal ? oldMeasures.at(-1) : Math.max(0, Math.min(oldMeasures.at(-1), measure));
    let interval = stationMeasures.length - 2;
    for (let i = 0; i < stationMeasures.length - 1; i += 1) if (bounded <= stationMeasures[i + 1] + 1e-6) { interval = i; break; }
    const source = pointAt(oldPoints, oldMeasures, bounded);
    let best = null;
    for (let i = newStations[interval]; i < newStations[interval + 1]; i += 1) {
      const projected = projectPoint(source, newPoints[i], newPoints[i + 1]);
      if (!best || projected.displacementMetres < best.displacementMetres)
        best = { ...projected, stationInterval: interval, newMeasure: newMeasures[i] + projected.fraction * (newMeasures[i + 1] - newMeasures[i]) };
    }
    if (terminal) best = { ...best, newMeasure: newMeasures.at(-1), displacementMetres: metres(source, newPoints.at(-1)) };
    assert(best.displacementMetres <= evidence.policy.maximumMeasuredReferenceDisplacementMetres, 'Mita measured reference exceeds bound');
    return best;
  }
  const laneRows = evidence.baseline.laneRows.map(row => { const from = map(row[2]), to = map(row[3]); assert(from.newMeasure < to.newMeasure); return [...row.slice(0, 2), +from.newMeasure.toFixed(1), +to.newMeasure.toFixed(1), row[4]]; });
  const followRows = evidence.baseline.followRows.map(row => { const from = map(row[6]), to = map(row[7]); assert(from.newMeasure > to.newMeasure); return [...row.slice(0, 6), from.newMeasure, +to.newMeasure.toFixed(1)]; });
  return { laneRows, followRows };
}

/** Rebuild only Mita's part and remap its reviewed lane/follow measures. */
export function repairParts(pkg, input = lanesDefault(), evidence = evidenceDefault()) {
  const lanes = structuredClone(input), line = pkg.lines.find(row => row.id === LINE);
  assert(line, 'Mita Apple candidate package line missing');
  const shown = displayedLine(line), parts = network.displayPartsForLine(shown);
  assert.equal(parts.length, 1, 'Mita Apple candidate part topology changed');
  const rows = partRowsForLine(line, parts, { stations: shown.stations, intervals: network.decodeIntervals(shown) }, null);
  assert.equal(rows.length, 1);
  if (evidence.candidate?.nativePartSHA256) assert.equal(hash(rows[0]), evidence.candidate.nativePartSHA256, 'Mita Apple native part changed');
  const currentParts = lanes.partsByRegion.jp.filter(row => row[0] === LINE);
  assert(currentParts.length === 1 && (same(currentParts[0], evidence.baseline.nativePart) || same(currentParts[0], rows[0])), 'Mita native part baseline changed');
  const oldLanes = lanes.byRegion.jp.filter(row => row[0] === LINE), oldFollows = lanes.followsByRegion.jp.filter(row => row[0] === LINE || row[4] === LINE);
  const mapped = mapReferences(line, evidence.baseline.nativePart, rows[0], evidence);
  assert(same(oldLanes, evidence.baseline.laneRows) || same(oldLanes, mapped.laneRows), 'Mita lane references changed');
  assert(same(oldFollows, evidence.baseline.followRows) || same(oldFollows, mapped.followRows), 'Mita follow references changed');
  for (const key of Object.keys(lanes).filter(key => !['partsByRegion', 'byRegion', 'followsByRegion'].includes(key)))
    assert(!JSON.stringify(lanes[key]).includes(LINE), `Mita unreviewed ${key} reference`);
  let lane = 0, follow = 0;
  lanes.partsByRegion.jp = lanes.partsByRegion.jp.map(row => row[0] === LINE ? rows[0] : row);
  lanes.byRegion.jp = lanes.byRegion.jp.map(row => row[0] === LINE ? mapped.laneRows[lane++] : row);
  lanes.followsByRegion.jp = lanes.followsByRegion.jp.map(row => row[0] === LINE || row[4] === LINE ? mapped.followRows[follow++] : row);
  assert.equal(lane, mapped.laneRows.length); assert.equal(follow, mapped.followRows.length);
  return lanes;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  assert(args.length === 2 && args[0] === '--candidate-dir', 'Usage: node repair-mita-apple-display.mjs --candidate-dir /private/tmp/<directory>');
  const output = path.resolve(args[1]);
  assert(output.startsWith('/private/tmp/'), 'Mita Apple candidate output must be under /private/tmp');
  const evidence = evidenceDefault();
  const coverage = fs.readFileSync(path.resolve(REPO, evidence.apple.coveragePath));
  const extractor = fs.readFileSync(path.resolve(REPO, evidence.apple.extractorPath));
  assert.equal(hash(coverage), evidence.apple.coverageSHA256, 'Mita Apple coverage source changed');
  assert.equal(hash(extractor), evidence.apple.extractorCodeSHA256, 'Mita Apple extractor source changed');
  const coverageDocument = JSON.parse(coverage);
  assert.equal(coverageDocument.intervals, 26); assert.equal(coverageDocument.viewpoints, 115);
  const coverageRows = coverageDocument.manifest.map(row => [row.interval, row.ordinal, row.directory])
    .sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const evidenceRows = evidence.apple.records.map(row => [row.interval, row.ordinal, row.sourceDirectory])
    .sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  assert.deepEqual(coverageRows, evidenceRows, 'Mita Apple coverage manifest changed');
  for (const review of evidence.apple.reviews)
    assert.equal(hash(fs.readFileSync(path.resolve(REPO, review.path))), review.sha256, `Mita review changed: ${review.path}`);
  if (fs.existsSync(evidence.apple.sourceDirectory)) {
    const names = fs.readdirSync(evidence.apple.sourceDirectory).filter(row => row.endsWith('.json')).sort();
    assert.deepEqual(names, evidence.apple.records.map(row => row.file), 'Mita retained view file set changed');
    for (const record of evidence.apple.records)
      assert.equal(hash(fs.readFileSync(path.join(evidence.apple.sourceDirectory, record.file))), record.sha256,
        `Mita retained Apple view changed: ${record.file}`);
  }
  const rawOSM = fs.readFileSync(path.resolve(REPO, evidence.identity.rawOSMPath));
  assert.equal(hash(rawOSM), evidence.identity.rawOSMSHA256, 'Mita raw OSM identity source changed');
  const pkg = repairPackage(packageDefault(), evidence), lanes = repairParts(pkg, lanesDefault(), evidence);
  assert.deepEqual(repairPackage(pkg, evidence), pkg); assert.deepEqual(repairParts(pkg, lanes, evidence), lanes);
  fs.mkdirSync(output, { recursive: true });
  fs.writeFileSync(path.join(output, 'jp-2025.json'), JSON.stringify(pkg));
  fs.writeFileSync(path.join(output, 'display-lanes.json'), JSON.stringify(lanes) + '\n');
  fs.writeFileSync(path.join(output, 'mita-apple-review.json'), JSON.stringify({ mode: 'candidate-only', productionPromotion: false,
    lineID: LINE, sourceManifestSHA256: evidence.apple.manifestSHA256, candidate: evidence.candidate }, null, 2) + '\n');
}
