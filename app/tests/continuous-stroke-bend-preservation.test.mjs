import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";

const require = createRequire(import.meta.url);
const RailStroke = require("../public/rail-stroke.js");

const distance = (a, b) => Math.hypot(b[0] - a[0], b[1] - a[1]);

function cumulative(points) {
  const measures = [0];
  for (let index = 1; index < points.length; index += 1)
    measures.push(measures[measures.length - 1] + distance(points[index - 1], points[index]));
  return measures;
}

function distanceToSegment(point, a, b) {
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const square = dx * dx + dy * dy;
  let t = square
    ? ((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / square
    : 0;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(point[0] - a[0] - dx * t, point[1] - a[1] - dy * t);
}

function directedDeviation(from, to) {
  return Math.max(
    ...from.map((point) =>
      Math.min(
        ...to.slice(1).map((end, index) => distanceToSegment(point, to[index], end)),
      ),
    ),
  );
}

function buildConstantLane(points, lane) {
  const measures = cumulative(points);
  return RailStroke.buildStroke(points, {
    measures,
    totalMetres: measures[measures.length - 1],
    rows: [{ from: 0, to: measures[measures.length - 1], lane }],
    laneGapPx: 2.7,
    minRampPx: 24,
    cornerRadiusPx: 0,
    minCornerRadiusPx: 3,
    anchors: [0, points.length - 1],
    enforceMinimumCornerRadius: true,
  });
}

// Compact snapshots of the follow output immediately before lane offsetting.
// Each includes sub-pixel samples inserted beside surveyed bends. Before the
// stable-tangent repair those samples made fold cleanup erase 69–160 metres of
// real curve and replace it with a 541–1,141 metre chord.
const CITY_BENDS = [
  {
    name: "Hartford Line at Hartford",
    lane: -7.5,
    coordinates: [
      [-72.675745, 41.774405], [-72.679477, 41.772973],
      [-72.67947714202099, 41.77297292380303], [-72.68023, 41.772569],
      [-72.68023020194127, 41.77256884534907], [-72.680546, 41.772327],
      [-72.68054619520498, 41.772326787529195], [-72.681213, 41.771601],
      [-72.68121321817043, 41.7716006719433], [-72.681485, 41.771192],
      [-72.68148515441841, 41.771191593453544], [-72.681662, 41.770726],
      [-72.68166207264609, 41.770725520726444], [-72.681739, 41.770218],
      [-72.68173902121913, 41.77021745480389], [-72.681788, 41.768959],
    ],
  },
  {
    name: "Metrolink VC at Los Angeles Union Station",
    lane: -7.5,
    coordinates: [
      [-118.228600547171, 34.06214959712888], [-118.231212, 34.061853],
      [-118.23121458910245, 34.06185209722143], [-118.231516, 34.061747],
      [-118.23151813986206, 34.06174561878155], [-118.232035, 34.061412],
      [-118.23203635582408, 34.06141023981196], [-118.232377, 34.060968],
      [-118.23237796009823, 34.06096623700163], [-118.233336, 34.059207],
    ],
  },
  {
    name: "Adirondack at New York Penn Station",
    lane: 7.5,
    coordinates: [
      [-73.994352, 40.762464], [-73.99621942619194, 40.75986979714183],
      [-73.99622, 40.759869], [-73.9994092684513, 40.75714362515443],
      [-73.99941, 40.757143], [-74.00031711617629, 40.7566594711148],
      [-74.000318, 40.756659], [-74.0019840464355, 40.75609532262306],
    ],
  },
  {
    name: "Carl Sandburg at Chicago Union Station",
    lane: -7.5,
    coordinates: [
      [-87.67217013430279, 41.859724007936656], [-87.674336, 41.859852],
      [-87.67433613244089, 41.85985198160486], [-87.679707, 41.859106],
      [-87.67970713106308, 41.85910597677023], [-87.681157, 41.858849],
      [-87.68115712705819, 41.85884896663893], [-87.682669, 41.858452],
      [-87.6826691237772, 41.85845196038537], [-87.685078, 41.857681],
      [-87.68507811760445, 41.8576809510536], [-87.685609, 41.85746],
    ],
  },
  {
    name: "NJT NEC at Newark Penn Station",
    lane: -7.5,
    coordinates: [
      [-74.148219, 40.74165], [-74.15067793515827, 40.74143300572211],
      [-74.150678, 40.741433], [-74.15160793590306, 40.74129700937332],
      [-74.151608, 40.741297], [-74.15235693790277, 40.74111301525489],
      [-74.152357, 40.741113], [-74.15328394200789, 40.740750022708944],
      [-74.153284, 40.74075], [-74.15381894449945, 40.74049902603864],
      [-74.153819, 40.740499], [-74.15540294860821, 40.73955903049789],
    ],
  },
];

test("near-coincident follow samples preserve real city bends", () => {
  for (const fixture of CITY_BENDS) {
    const sampled = fixture.coordinates.map((coordinate) => RailStroke.project(coordinate, 16));
    const surveyed = sampled.filter(
      (point, index) => index === 0 || distance(point, sampled[index - 1]) > 0.5,
    );
    const expected = buildConstantLane(surveyed, fixture.lane);
    const actual = buildConstantLane(sampled, fixture.lane);
    assert.ok(
      directedDeviation(expected.points, actual.points) <= 0.04,
      `${fixture.name}: sampled stroke cut across the surveyed curve`,
    );
    assert.ok(
      directedDeviation(actual.points, expected.points) <= 0.04,
      `${fixture.name}: sampled stroke introduced an offset spur`,
    );
    assert.deepEqual(actual.anchors, [actual.points[0], actual.points[actual.points.length - 1]]);
  }
});

test("a sparse survey still draws a complete lane excursion", () => {
  const points = [[0, 0], [4_000, 0]];
  const rows = [
    { from: 0, to: 1_000, lane: 0 },
    { from: 1_000, to: 3_000, lane: 15 },
    { from: 3_000, to: 4_000, lane: 0 },
  ];
  const result = RailStroke.buildStroke(points, {
    measures: [0, 4_000],
    totalMetres: 4_000,
    rows,
    laneGapPx: 3,
    minRampPx: 10,
    cornerRadiusPx: 0,
    anchors: [0, 1],
    enforceMinimumCornerRadius: true,
  });
  assert.ok(result.points.some((point) => Math.abs(point[1] - 45) < 1e-8));
  assert.deepEqual(result.anchors, [[0, 0], [4_000, 0]]);
  for (let measure = 0; measure <= 4_000; measure += 17) {
    const lane = RailStroke.laneAt(RailStroke.laneProfile(rows, 4_000), measure, 300);
    assert.ok(
      directedDeviation([[measure, lane * 3]], result.points) <= 0.126,
      `lane ramp departed from its kernel at ${measure} m`,
    );
  }
});

test("strict fillets meet their radius floor or leave the surveyed vertex", () => {
  const options = (points, anchors = []) => {
    const measures = cumulative(points);
    return {
      measures,
      totalMetres: measures[measures.length - 1],
      rows: [],
      laneGapPx: 0,
      minRampPx: 0,
      cornerRadiusPx: 1,
      minCornerRadiusPx: 4,
      anchors,
      enforceMinimumCornerRadius: true,
    };
  };
  const feasible = [[-100, 0], [0, 0], [0, 100]];
  const rounded = RailStroke.buildStroke(feasible, options(feasible));
  assert.ok(Math.abs(rounded.points[1][0] + 4) < 1e-8);
  assert.ok(Math.abs(rounded.points[rounded.points.length - 2][1] - 4) < 1e-8);

  const short = [[-1, 0], [0, 0], [0, 1]];
  assert.deepEqual(RailStroke.buildStroke(short, options(short)).points, short);
  assert.deepEqual(RailStroke.buildStroke(feasible, options(feasible, [1])).points, feasible);
});

test("a shared near-reversal join uses the incoming normal without a mitre tip", () => {
  const degrees = (170 * Math.PI) / 180;
  const points = [[0, 0], [10, 0], [20, 0]];
  const result = RailStroke.buildStroke(points, {
    measures: [0, 10, 20],
    totalMetres: 20,
    rows: [{ from: 0, to: 20, lane: 1 }],
    laneGapPx: 3,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [0, 2],
    joinStart: {
      lane: 1,
      incoming: [1, 0],
      outgoing: [Math.cos(degrees), Math.sin(degrees)],
    },
    enforceMinimumCornerRadius: true,
  });
  assert.deepEqual(result.points[0], [0, 3]);
  assert.deepEqual(result.anchors[0], result.points[0]);
  assert.ok(result.points.every((point) => Math.abs(point[1] - 3) < 1e-8));
});
