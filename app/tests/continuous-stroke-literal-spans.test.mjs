import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';
const { buildStroke, smoothCentreline } = createRequire(import.meta.url)('../public/rail-stroke.js');
const points = [[0,-40],[100,-15],[230,-3],[360,0],[3360,0],[3490,5],[3620,24],[3720,50]];
const measures = [0, 103, 234, 364, 3364, 3495, 3627, 3730];
const hint = { edgeIndex: 3, witnesses: points.slice(2,6) };
const options = { measures, anchors: [0,7], cornerRadiusPx: 3, literalSpans: [hint] };

test('reviewed literal body stays on its chord with real curved shoulders and no new anchors', () => {
  const before = structuredClone(points);
  const result = buildStroke(points, options);
  const body = result.points.filter((_, i) => result.measures[i] >= 364 && result.measures[i] <= 3364);
  assert.ok(body.length >= 2);
  assert.ok(body.every(p => p[1] === 0), 'literal body must have zero chord departure');
  assert.deepEqual(result.appliedLiteralSpanEdges, [3]);
  for (const [lo, hi, a, b] of [[234,364,points[2],points[3]], [3364,3495,points[4],points[5]]]) {
    const shoulder = result.points.filter((_, i) => result.measures[i] > lo && result.measures[i] < hi);
    assert.ok(shoulder.length > 0, 'shoulder retains curved samples');
    assert.ok(shoulder.some(p => Math.abs((p[0]-a[0])*(b[1]-a[1])-(p[1]-a[1])*(b[0]-a[0])) > 1e-6));
  }
  assert.deepEqual(result.anchors, [points[0],points[7]]);
  assert.deepEqual(points,before);
  assert.ok(result.measures.every((m,i) => !i || m >= result.measures[i-1]));
});

// Recover a cubic's endpoint derivative from four observed samples. These
// Lagrange weights are independent of the centreline tangent construction.
function derivative(curve, lo, hi, end) {
  const weights = end ? [-3,32/3,-12,13/3] : [-7,32/3,-4,1/3];
  const samples = [0,0.25,0.5,1].map(u => {
    const at = curve.measures.indexOf(lo+(hi-lo)*u);
    assert.ok(at >= 0, 'ordinary adaptive sampler exposes the cubic samples');
    return curve.points[at];
  });
  return [0,1].map(axis => samples.reduce((n,p,i) => n+weights[i]*p[axis],0)/(hi-lo));
}
function nearVector(actual, expected) {
  actual.forEach((v,i) => assert.ok(Math.abs(v-expected[i]) < 1e-9, `${actual} != ${expected}`));
}

test('shoulder inner derivatives equal the body metre derivative and outer derivatives stay legacy', () => {
  const ordinary = smoothCentreline(points, measures);
  const literal = smoothCentreline(points, measures, [], [], [hint]);
  assert.deepEqual(literal.appliedLiteralSpanEdges,[3]);
  nearVector(derivative(literal,234,364,true), [1,0]);
  nearVector(derivative(literal,3364,3495,false), [1,0]);
  nearVector(derivative(literal,234,364,false), derivative(ordinary,234,364,false));
  nearVector(derivative(literal,3364,3495,true), derivative(ordinary,3364,3495,true));
});

test('invalid, overlapping and incompatible hints are exactly the ordinary result', () => {
  const ordinary = buildStroke(points,{...options,literalSpans:[]});
  const invalid = [null, {}, {edgeIndex:3,witnesses:points.slice(1,5)}, {edgeIndex:99,witnesses:hint.witnesses}];
  for (const value of invalid)
    assert.deepEqual(buildStroke(points,{...options,literalSpans:[value]}),ordinary);
  assert.deepEqual(buildStroke(points,{...options,literalSpans:[hint,hint]}),ordinary);
  for (const extra of [
    {curveCentreline:false}, {cornerRadiusPx:0},
    {rows:[{from:0,to:3730,lane:1}],laneGapPx:3},
    {shapeBoundaryMeasures:[364]},
    {follows:[{points,measures,from:0,to:3730,canonFrom:0,canonTo:3730}]},
  ]) assert.deepEqual(buildStroke(points,{...options,...extra}),
    buildStroke(points,{...options,...extra,literalSpans:[]}));
});

test('a downstream footprint alteration discards the entire constraint', () => {
  // At this scale the ordinary final rounding changes the analytic samples.
  const small = points.map(p => p.map(v => v*0.01));
  const literalSpans = [{edgeIndex:3,witnesses:small.slice(2,6)}];
  assert.deepEqual(smoothCentreline(small,measures,[],[],literalSpans).appliedLiteralSpanEdges,[3]);
  const ordinary = buildStroke(small,{...options,literalSpans:[]});
  assert.deepEqual(buildStroke(small,{...options,literalSpans}),ordinary);
  assert.equal('appliedLiteralSpanEdges' in ordinary,false);
});

test('zero lane rows do not suppress a valid literal span', () => {
  const result = buildStroke(points,{...options,rows:[{from:0,to:3730,lane:0}],laneGapPx:3});
  assert.deepEqual(result.appliedLiteralSpanEdges,[3]);
});

test('deduplication cannot reuse a different measure as a footprint witness', () => {
  const repeated = points.map(p => p.slice());
  repeated[1] = repeated[2].slice();
  const literalSpans = [{edgeIndex:3,witnesses:repeated.slice(2,6)}];
  assert.deepEqual(buildStroke(repeated,{...options,literalSpans}),
    buildStroke(repeated,{...options,literalSpans:[]}));
});

test('a hidden lane offset cannot authorize literal interpolation', () => {
  for (const context of [
    {rows:[{from:0,to:3730,lane:1}]},
    {joinStart:{lane:1}},
    {joinEnd:{targetLane:1}},
  ]) {
    const opts = {...options,...context,laneGapPx:0};
    assert.deepEqual(buildStroke(points,opts),buildStroke(points,{...opts,literalSpans:[]}));
  }
  assert.deepEqual(buildStroke(points,{...options,laneGapPx:0,joinStart:{lane:0},joinEnd:{targetLane:0}}).appliedLiteralSpanEdges,[3]);
});
