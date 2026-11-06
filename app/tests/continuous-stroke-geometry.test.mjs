// =========================================================================
//  continuous-stroke-geometry.test.mjs — properties of the DRAWN stroke.
//
//  port-fixtures/continuous-stroke.json pins rail-stroke.js and the Swift
//  port to each other coordinate by coordinate. It cannot pin what that
//  answer has to BE: regenerate the fixture and both sides agree on the new
//  shape, however bad it is. These two assertions are that missing half, and
//  RailCoreTests/ContinuousStrokeParityTests.swift asserts the identical two
//  over the identical cases on the Swift side.
//
//    (i)  nothing malformed reaches the renderer — no NaN, no measure that
//         runs backwards, no zero-length edge;
//    (ii) a rounded corner is sampled at most FILLET_STEP_DEGREES of turn at
//         a time. The fillet used to draw a quadratic Bézier sampled
//         uniformly in u, which concentrates the tangent rotation mid-arc:
//         14.3 degrees per facet at a 90-degree corner, 19.7 at 120, and
//         28.8 on the shipped cta-orange-line case, against the 12 the
//         sample count was chosen to promise;
//    (iii) a SHARP surveyed corner is rounded too, but only a little: its
//         radius is capped per corner so the drawn line stays within
//         HARD_CORNER_MAX_DEVIATION_PX (screen pixels, half the rail width)
//         of the surveyed vertex, and a corner left sharp could not have
//         been rounded under that cap.
//
//  Run:  cd app && npm test    — `node --test` with no path argument,
//  which discovers this file. Node 26 rejects a bare directory path,
//  so `node --test app/tests/` from the repo root does not work.
// =========================================================================

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const RailStroke = require(path.join(HERE, "..", "public", "rail-stroke.js"));
const fixture = JSON.parse(
  fs.readFileSync(
    path.join(HERE, "..", "..", "port-fixtures", "continuous-stroke.json"),
    "utf8",
  ),
);

// The radius-0 build switches the curve pass off with the rounding, so it is
// NOT the polyline the fillet sees. An infinitesimal radius keeps every pass
// before the fillet and rounds nothing: no tangent survives DEGENERATE_EDGE_PX.
const PRE_FILLET_RADIUS_PX = 1e-9;

function buildStroke(probe, radiusPx, extra = {}) {
  return RailStroke.buildStroke(probe.points, {
    ...extra,
    measures: probe.measures || undefined,
    rows: probe.rows,
    totalMetres: probe.totalMetres,
    laneGapPx: probe.laneGapPx,
    minRampPx: probe.minRampPx,
    cornerRadiusPx: radiusPx === undefined ? probe.cornerRadiusPx : radiusPx,
    // A strict build promotes cornerRadiusPx to this floor, so the explicit
    // pre-fillet probe used below must clear both values to expose the actual
    // pre-fillet polyline.
    minCornerRadiusPx: radiusPx === undefined ? probe.minCornerRadiusPx || 0 : 0,
    enforceMinimumCornerRadius: probe.enforceMinimumCornerRadius === true,
    anchors: probe.anchors,
    follows: probe.follows || [],
    joinStart: probe.joinStart || null,
    joinEnd: probe.joinEnd || null,
  });
}

// The deflection at interior vertex `index`, in degrees.
function turnDegrees(points, index) {
  const ax = points[index][0] - points[index - 1][0];
  const ay = points[index][1] - points[index - 1][1];
  const bx = points[index + 1][0] - points[index][0];
  const by = points[index + 1][1] - points[index][1];
  const la = Math.hypot(ax, ay);
  const lb = Math.hypot(bx, by);
  if (!(la > 0) || !(lb > 0)) return 0;
  const dot = Math.max(-1, Math.min(1, (ax * bx + ay * by) / (la * lb)));
  return (Math.acos(dot) * 180) / Math.PI;
}

test("every stroke is well formed", () => {
  fixture.cases.forEach((probe, index) => {
    const stroke = buildStroke(probe);
    const where = `case ${index}: ${probe.note}`;
    for (const point of stroke.points.concat(stroke.anchors))
      assert.ok(
        Number.isFinite(point[0]) && Number.isFinite(point[1]),
        `${where} — non-finite point`,
      );
    for (const measure of stroke.measures.concat(stroke.anchorMeasures))
      assert.ok(Number.isFinite(measure), `${where} — non-finite measure`);
    assert.equal(stroke.measures.length, stroke.points.length, `${where} — measure count`);
    for (let at = 1; at < stroke.measures.length; at += 1)
      assert.ok(
        stroke.measures[at] >= stroke.measures[at - 1],
        `${where} — measure runs backwards at ${at}`,
      );
    // A part of fewer than two distinct vertices degenerates, on purpose, to
    // two copies of its only point (see buildStroke's early return); every
    // other stroke owes us distinct neighbours.
    if (stroke.points.length <= 2) return;
    for (let at = 1; at < stroke.points.length; at += 1)
      assert.ok(
        stroke.points[at][0] !== stroke.points[at - 1][0] ||
          stroke.points[at][1] !== stroke.points[at - 1][1],
        `${where} — duplicate point at ${at}`,
      );
  });
});

test("rounded corners honour the sampling step", () => {
  const ceiling = RailStroke.FILLET_STEP_DEGREES + 0.5;
  fixture.cases.forEach((probe, index) => {
    if (!(probe.cornerRadiusPx > 0)) return;
    const stroke = buildStroke(probe);
    if (stroke.points.length < 3) return;
    // The polyline the fillet pass actually saw: the identical build with an
    // infinitesimal radius, which is exactly what filletPolyline receives
    // and returns unchanged.
    const pre = buildStroke(probe, PRE_FILLET_RADIUS_PX).points;
    // Two kinds of vertex are exempt, and both are geometry the fillet is
    // FORBIDDEN to touch rather than geometry it drew badly: a surveyed
    // reversal (turn >= FILLET_MAX_TURN_DEGREES — a switchback is not a
    // corner) and a station anchor, whose arc is drawn THROUGH the platform
    // vertex and therefore meets the edges either side at an angle of its
    // own. Excluded by POSITION, within two radii, because the output has no
    // index back to the input.
    const exempt = stroke.anchors.slice();
    for (let at = 1; at + 1 < pre.length; at += 1)
      if (turnDegrees(pre, at) >= RailStroke.FILLET_MAX_TURN_DEGREES) exempt.push(pre[at]);
    const reach = 2 * probe.cornerRadiusPx;
    let worst = 0;
    let worstAt = -1;
    for (let at = 1; at + 1 < stroke.points.length; at += 1) {
      const vertex = stroke.points[at];
      // The production radius floor deliberately keeps a surveyed corner
      // when no bounded arc fits. It is not a sampled fillet; only exact
      // retained vertices are exempt, never their surrounding geometry.
      if (probe.enforceMinimumCornerRadius &&
          pre.some((point) => point[0] === vertex[0] && point[1] === vertex[1])) continue;
      if (
        exempt.some(
          (point) => Math.hypot(point[0] - vertex[0], point[1] - vertex[1]) <= reach,
        )
      )
        continue;
      const turn = turnDegrees(stroke.points, at);
      if (turn > worst) {
        worst = turn;
        worstAt = at;
      }
    }
    assert.ok(
      worst <= ceiling,
      `case ${index}: ${probe.note} — ${worst.toFixed(2)}° facet at vertex ${worstAt}`,
    );
  });
});

function distanceToPolyline(point, polyline) {
  let best = Infinity;
  for (let at = 0; at + 1 < polyline.length; at += 1) {
    const [ax, ay] = polyline[at];
    const [bx, by] = polyline[at + 1];
    const dx = bx - ax;
    const dy = by - ay;
    const square = dx * dx + dy * dy;
    let t = square > 0 ? ((point[0] - ax) * dx + (point[1] - ay) * dy) / square : 0;
    t = Math.max(0, Math.min(1, t));
    best = Math.min(best, Math.hypot(point[0] - ax - dx * t, point[1] - ay - dy * t));
  }
  return best;
}

const TOLERANCE = RailStroke.HARD_CORNER_MAX_DEVIATION_PX;
const same = (a, b) => a[0] === b[0] && a[1] === b[1];

// How far a vertex turning by `turnRadians`, rounded at radius r, ends up from
// the drawn polyline, per unit r: exact for the sample count the fillet uses.
function gapPerRadius(turnRadians) {
  const n = Math.max(2, Math.ceil(turnRadians / ((RailStroke.FILLET_STEP_DEGREES * Math.PI) / 180)));
  return 1 / Math.cos(turnRadians / 2) - (n % 2 === 1 ? Math.cos(turnRadians / (2 * n)) : 1);
}

// The largest radius a lone sharp corner can take, and whether the rule
// lets it go below a strict floor.
function sharpCornerReach(points, at, probe) {
  const turn = (turnDegrees(points, at) * Math.PI) / 180;
  const la = Math.hypot(points[at][0] - points[at - 1][0], points[at][1] - points[at - 1][1]);
  const lb = Math.hypot(points[at + 1][0] - points[at][0], points[at + 1][1] - points[at][1]);
  const floor = probe.minCornerRadiusPx || 0;
  const requested = probe.enforceMinimumCornerRadius ? Math.max(probe.cornerRadiusPx, floor) : probe.cornerRadiusPx;
  const reach = Math.min(
    requested,
    TOLERANCE / gapPerRadius(turn),
    (RailStroke.FILLET_MAX_TANGENT_SHARE * Math.min(la, lb)) / Math.tan(turn / 2),
  );
  const gap = Math.abs(probe.laneGapPx || 0);
  const waived = !gap || gap < RailStroke.RAIL_WIDTH_PX
    || gap >= RailStroke.HARD_CORNER_FLOOR_WAIVER_GAP_TOLERANCES * TOLERANCE;
  const required = probe.enforceMinimumCornerRadius && !waived ? floor : 0;
  return { reach, required, tangent: reach * Math.tan(turn / 2) };
}

test("sharp surveyed corners are rounded within the deviation tolerance", () => {
  let rounded = 0;
  let checked = 0;
  fixture.cases.forEach((probe, index) => {
    if (!(probe.cornerRadiusPx > 0)) return;
    const stroke = buildStroke(probe);
    // The same build with a zero tolerance leaves every sharp surveyed corner
    // exactly as surveyed — every class of them: lone, localized, windowed,
    // and runs merged into one corner.
    const kept = buildStroke(probe, undefined, { hardCornerMaxDeviationPx: 0 });
    const pre = buildStroke(probe, PRE_FILLET_RADIUS_PX).points;
    const where = `case ${index}: ${probe.note}`;
    for (const vertex of pre) {
      if (!kept.points.some((p) => same(p, vertex)) || stroke.points.some((p) => same(p, vertex))) continue;
      const moved = distanceToPolyline(vertex, stroke.points);
      assert.ok(moved <= TOLERANCE + 1e-9, `${where} — a sharp corner moved ${moved} px`);
      rounded += 1;
    }
    // Nothing else moves further than that either: the ink of the two builds
    // is within one tolerance of each other in both directions.
    if (kept.points.length >= 2 && stroke.points.length >= 2) {
      for (const point of kept.points)
        assert.ok(distanceToPolyline(point, stroke.points) <= TOLERANCE + 1e-9, `${where} — ink moved`);
      for (const point of stroke.points)
        assert.ok(distanceToPolyline(point, kept.points) <= TOLERANCE + 1e-9, `${where} — ink moved`);
    }
    // A corner sharper than CURVE_HARD_TURN_DEGREES is always a surveyed
    // corner. Left sharp, it must have been impossible to round: its reach
    // under the cap is degenerate, or under a floor the rule keeps.
    for (let at = 1; at + 1 < pre.length; at += 1) {
      const turn = turnDegrees(pre, at);
      if (!(turn > RailStroke.CURVE_HARD_TURN_DEGREES && turn < RailStroke.FILLET_MAX_TURN_DEGREES)) continue;
      if (stroke.anchors.some((a) => same(a, pre[at]))) continue;
      checked += 1;
      if (!stroke.points.some((p) => same(p, pre[at]))) continue;
      const { reach, required, tangent } = sharpCornerReach(pre, at, probe);
      assert.ok(tangent <= 1e-6 || reach < required,
        `${where} — vertex ${at} (${turn.toFixed(1)}°) left sharp, reach ${reach} px, floor ${required} px`);
    }
  });
  assert.ok(rounded > 0, "the corpus holds no sharp surveyed corner");
  // The left-sharp proof above must have had corners to judge.
  assert.ok(checked > 0, "no corner sharper than CURVE_HARD_TURN_DEGREES was examined");
});

// One corner, long edges, the radius request and the tolerance varied.
function corner(degrees, { radius = 3.6, tolerance, floor = 0, strict = false, lane = 0, gap = 0 } = {}) {
  const a = (degrees * Math.PI) / 180;
  const points = [[-100, 0], [0, 0], [100 * Math.cos(a), 100 * Math.sin(a)]];
  const options = {
    measures: [0, 100, 200], rows: [{ from: 0, to: 200, lane }], totalMetres: 200,
    laneGapPx: gap, minRampPx: 24, cornerRadiusPx: radius, minCornerRadiusPx: floor,
    enforceMinimumCornerRadius: strict, anchors: [0, 2],
  };
  if (tolerance !== undefined) options.hardCornerMaxDeviationPx = tolerance;
  return { points, stroke: RailStroke.buildStroke(points, options) };
}

test("a sharp corner's radius is the smallest of request, edge share and tolerance, exactly", () => {
  // 100 degrees is sampled in nine (odd) steps, so the drawn line passes the
  // vertex at a chord's midpoint, not a sample: the cap accounts for it.
  for (const degrees of [60, 90, 100, 120, 140])
    for (const tolerance of [0.25, 0.75, 3]) {
      const { points, stroke } = corner(degrees, { tolerance });
      const turn = (degrees * Math.PI) / 180;
      const expected = Math.min(3.6, tolerance / gapPerRadius(turn));
      const moved = distanceToPolyline(points[1], stroke.points);
      const label = `${degrees}° at ${tolerance} px`;
      assert.ok(stroke.points.length > points.length, `${label}: left sharp`);
      assert.ok(Math.abs(moved - expected * gapPerRadius(turn)) < 1e-9, `${label}: moved ${moved}`);
      assert.ok(moved <= tolerance + 1e-12, `${label}: ${moved} px over ${tolerance}`);
      for (const point of stroke.points)
        assert.ok(distanceToPolyline(point, points) <= tolerance + 1e-12, `${label}: ink off the survey`);
    }
});

test("a sharp corner goes under a strict floor only where no lane can be crowded", () => {
  // 90 degrees at 0.75 px reaches 1.81 px, under a 3 px floor.
  const reach = TOLERANCE / gapPerRadius(Math.PI / 2);
  const options = { floor: 3, strict: true, lane: 1 };
  // No lane geometry, a lane gap under one rail width (the z9–12 half-gap
  // lane LOD draws 1.35 px), and a gap of at least three tolerances (2.7 px
  // from z12): rounded.
  for (const gap of [0, 1.35, RailStroke.HARD_CORNER_FLOOR_WAIVER_GAP_TOLERANCES * TOLERANCE, 2.7]) {
    const { points, stroke } = corner(90, { ...options, gap });
    assert.ok(stroke.points.length > points.length, `gap ${gap}: left sharp`);
    for (let at = 2; at + 2 < stroke.points.length; at += 1) {
      const [a, b, c] = [stroke.points[at - 1], stroke.points[at], stroke.points[at + 1]];
      const cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]);
      const r = Math.hypot(b[0] - a[0], b[1] - a[1]) * Math.hypot(c[0] - b[0], c[1] - b[1])
        * Math.hypot(c[0] - a[0], c[1] - a[1]) / (2 * Math.abs(cross));
      assert.ok(Math.abs(r - reach) < 1e-6, `gap ${gap}: radius ${r}`);
    }
  }
  // Between one rail width and three tolerances the floor binds: no arc
  // fits, the corner stays exact.
  for (const gap of [RailStroke.RAIL_WIDTH_PX, 2])
    assert.equal(corner(90, { ...options, gap }).stroke.points.length, 3, `gap ${gap}`);
});

test("neighbouring lanes rounded to different radii keep their separation", () => {
  // The worst case the waiver allows: one lane left sharp (tolerance 0), its
  // neighbour rounded at the full tolerance. They close by at most one.
  for (const degrees of [60, 90, 120, 140])
    for (const gap of [1.35, 2.7])
      for (const [sharpLane, roundLane] of [[0, 1], [0, -1], [1, 0], [-1, 0]]) {
        const options = { floor: 3, strict: true, gap };
        const kept = corner(degrees, { ...options, lane: sharpLane, tolerance: 0 }).stroke.points;
        const { points, stroke } = corner(degrees, { ...options, lane: roundLane });
        assert.ok(stroke.points.length > points.length, `${degrees}° lane ${roundLane}: left sharp`);
        let separation = Infinity;
        for (const point of stroke.points) separation = Math.min(separation, distanceToPolyline(point, kept));
        for (const point of kept) separation = Math.min(separation, distanceToPolyline(point, stroke.points));
        assert.ok(separation >= gap - TOLERANCE - 1e-9,
          `${degrees}° gap ${gap}, lanes ${sharpLane}/${roundLane}: ${separation} px apart`);
      }
});

test("a corner split across sub-pixel vertices is rounded as one, within the tolerance", () => {
  // Five vertices 0.3 px apart turn 70 degrees in all: a windowed surveyed
  // corner, merged into one run by the floor.
  const points = [[0, 0], [60, 0]];
  let heading = 0;
  for (let k = 0; k < 4; k += 1) {
    heading += (17.5 * Math.PI) / 180;
    const [x, y] = points.at(-1);
    points.push([x + 0.3 * Math.cos(heading), y + 0.3 * Math.sin(heading)]);
  }
  const [x, y] = points.at(-1);
  points.push([x + 60 * Math.cos(heading), y + 60 * Math.sin(heading)]);
  const metres = [0];
  for (let at = 1; at < points.length; at += 1)
    metres.push(metres[at - 1] + Math.hypot(points[at][0] - points[at - 1][0], points[at][1] - points[at - 1][1]));
  for (const tolerance of [0.25, 0.75]) {
    const stroke = RailStroke.buildStroke(points, {
      measures: metres, rows: [], totalMetres: metres.at(-1), laneGapPx: 0, minRampPx: 24,
      cornerRadiusPx: 3.6, minCornerRadiusPx: 1.5, anchors: [0, points.length - 1],
      hardCornerMaxDeviationPx: tolerance,
    });
    // ONE corner: none of the run's vertices survives.
    for (let at = 1; at + 1 < points.length; at += 1)
      assert.ok(!stroke.points.some((p) => same(p, points[at])), `${tolerance}: vertex ${at} kept`);
    for (const point of points)
      assert.ok(distanceToPolyline(point, stroke.points) <= tolerance + 1e-9, `${tolerance}: a vertex moved too far`);
    for (let at = 1; at + 1 < stroke.points.length; at += 1)
      assert.ok(turnDegrees(stroke.points, at) <= RailStroke.FILLET_STEP_DEGREES + 0.5);
  }
});
