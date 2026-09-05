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
//         sample count was chosen to promise.
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

function buildStroke(probe, radiusPx) {
  return RailStroke.buildStroke(probe.points, {
    measures: probe.measures || undefined,
    rows: probe.rows,
    totalMetres: probe.totalMetres,
    laneGapPx: probe.laneGapPx,
    minRampPx: probe.minRampPx,
    cornerRadiusPx: radiusPx === undefined ? probe.cornerRadiusPx : radiusPx,
    minCornerRadiusPx: probe.minCornerRadiusPx || 0,
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
    // The polyline the fillet pass actually saw: the identical build with the
    // rounding switched off, which is exactly what filletPolyline receives
    // (it returns its input unchanged at radius 0).
    const pre = buildStroke(probe, 0).points;
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
