// =========================================================================
//  continuous-stroke.json — rail-stroke.js, the continuous screen-space
//  stroke of one railway part: lane offset baked into the vertices through a
//  smoothed lane profile, station anchors carried along, corners rounded.
//
//  Everything pinned here is produced by calling the exported functions of
//  rail-stroke.js — never a restatement. The module works in an abstract
//  pixel space, so the cases are pixel polylines: real North American parts
//  projected at a handful of zooms (through the module's own `project`, which
//  is pinned too), plus synthetic probes for the branches a real corridor may
//  not reach at those zooms — a plateau shorter than the kernel, an exact
//  reversal, a right angle on a station anchor, a hairpin that must NOT be
//  rounded, duplicate vertices, a two-point part, an empty part.
//
//  The contract the Swift port (RailCore ContinuousStroke) is held to:
//
//      given exactly these pixel points, these lane rows, this total length,
//      this gap, ramp floor, radius and anchor set, the answer is exactly
//      this polyline and exactly these anchor positions.
//
//  Answers are compared to 1e-6 px: the arithmetic is plain (+ − × ÷, sqrt,
//  hypot, acos, tan) and both languages agree well inside that.
// =========================================================================

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

export const name = "continuous-stroke.json";

const require = createRequire(import.meta.url);

// The real parts of real lines, chosen for what they exercise: a multi-lane
// commuter trunk that changes lane six times, a subway trunk with a
// half-lane, a streetcar with station-spaced corners, and a line with no
// lane rows at all (the fillet-only path).
const REAL_CASES = [
  // Follow-inserted samples must not erase surveyed station approaches.
  { country: "us", lineId: "metrolink-vc-line", zooms: [13, 16] },
  { country: "us", lineId: "amtrak-amtrak-hartford-line", zooms: [13, 16] },
  { country: "us", lineId: "new-jersey-transit-nj-transi-nec", zooms: [9, 13, 16] },
  { country: "us", lineId: "metropolitan-transit-authori-m", zooms: [12, 15] },
  { country: "us", lineId: "trimet-portland-streetcar-a", zooms: [14, 17] },
  { country: "us", lineId: "cta-orange-line", zooms: [13] },
  // A survey seam welded sideways east of Jamaica: the taper's real case.
  { country: "us", lineId: "mta-long-island-rail-road-west-hempstead-branch", zooms: [12, 15, 17] },
  // Five seam jogs and a lane over a transcontinental part.
  { country: "us", lineId: "amtrak-empire-builder", zooms: [10] },
  // Follows Metra BNSF out of Chicago Union Station: the corridor case.
  { country: "us", lineId: "amtrak-carl-sandburg", zooms: [14] },
  { country: "ca", lineId: "go-transit-br", zooms: [11, 15] },
  // jp joined CONTINUOUS_STROKE_COUNTRIES alongside us/ca: an open arc with
  // seven lane changes across Tokyo's Shinagawa/Tamachi throat.
  { country: "jp", lineId: "jp-東日本旅客鉄道-山手線", zooms: [12, 15] },
  // The Tokaido Line local-service split near Shinagawa: its own hub-derived
  // lane window [3400, 7800]m overlaps the jp-shinagawa hub's [5250, 8250]m
  // slot on the canonical 東海道線, and it also FOLLOWS that canonical's own
  // alignment from [6500, 9650]m — one part, both mechanisms, on real data.
  { country: "jp", lineId: "jp-東日本旅客鉄道-東海道線-3", zooms: [13, 16] },
  // 大阪環状線: a closed ring stored as one embedded `loop` part (already
  // walked to the canonical winding upstream — see reversedLoopParts), with
  // two of its own reviewed lane rows straddling the 京橋/大阪 seam.
  { country: "jp", lineId: "jp-西日本旅客鉄道-大阪環状線", zooms: [13] },
  // 名城線 stores Japan's only full subway ring as two OPEN railways sharing
  // two seam stations (see display-loops.json's jp-nagoya-meijo) rather than
  // one closed line — an arc of the 2号線 half.
  { country: "jp", lineId: "jp-名古屋市-2号線名城線", zooms: [14] },
  // A route-preserving family pair (jp-render-groups.json "九州旅客鉄道:
  // 長崎線"): the base line and its own `-2` branch-service split share one
  // published colour and one family id, and are drawn as two ordinary
  // continuous strokes — the family collapse happens downstream of
  // buildStroke, not inside it — so the pair pins that a `-2` variant's
  // geometry round-trips exactly like its base line's does.
  { country: "jp", lineId: "jp-九州旅客鉄道-長崎線", zooms: [11] },
  { country: "jp", lineId: "jp-九州旅客鉄道-長崎線-2", zooms: [11] },
];

// A corner spread over vertices a hundredth of a pixel apart — a welded
// survey duplicate, or a real curve sampled every 20 m and drawn at a
// regional zoom. `turnDegrees` of total deflection is dealt out over four
// such vertices between two 60 px edges.
function splitCorner(turnDegrees, stepPx) {
  const out = [[0, 0], [60, 0]];
  let x = 60;
  let y = 0;
  let heading = 0;
  for (let index = 0; index < 4; index += 1) {
    heading += ((turnDegrees * Math.PI) / 180) / 4;
    x += Math.cos(heading) * stepPx;
    y += Math.sin(heading) * stepPx;
    out.push([x, y]);
  }
  out.push([x + Math.cos(heading) * 60, y + Math.sin(heading) * 60]);
  return out;
}

// A tight sub-pixel arc whose 5.4 px lane offset folds squarely on interior
// vertex 1: removeOffsetFolds drops it (see the "lane offset folds exactly
// at an anchor vertex" case below), so an anchor read there must come from
// the surviving edge that replaced it, not the discarded pre-fold point.
function foldAtAnchorArc() {
  const points = Array.from({ length: 7 }, (_, i) => {
    const angle = (Math.PI * 0.9 * i) / 6;
    return [Math.cos(angle) * 5, Math.sin(angle) * 5];
  });
  let totalMetres = 0;
  for (let i = 1; i < points.length; i += 1)
    totalMetres += Math.hypot(
      points[i][0] - points[i - 1][0],
      points[i][1] - points[i - 1][1],
    );
  return { points, totalMetres };
}
const FOLD_AT_ANCHOR = foldAtAnchorArc();

const SYNTHETIC = [
  {
    // The defect this measures: 0.45 of a 0.03 px edge is 0.0135 px, so each
    // of the four vertices used to be "rounded" to a radius of 0.088 px —
    // a bare kink. Rounded as ONE corner the run reaches the full 3.6.
    note: "a corner split across near-coincident vertices is rounded as ONE corner to the minimum radius",
    points: splitCorner(70, 0.03),
    rows: [],
    totalMetres: 1200,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 3.6,
    minCornerRadiusPx: 1.5,
    anchors: [],
  },
  {
    // Same geometry, no floor. Its four vertices are far under
    // STROKE_SIMPLIFY_TOLERANCE_PX, so buildStroke's pre-fillet decimation
    // now removes them whatever the floor says and the two answers are the
    // same one — which is the point: a split this fine is a survey artefact,
    // not a corner, and the run merge is no longer what rescues it.
    note: "the same split corner with no minimum radius: each vertex is rounded in isolation",
    points: splitCorner(70, 0.03),
    rows: [],
    totalMetres: 1200,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 3.6,
    anchors: [],
  },
  {
    // The same defect at a spacing the pre-fillet decimation CANNOT remove.
    // 0.03 px apart the four vertices are far under
    // STROKE_SIMPLIFY_TOLERANCE_PX and buildStroke drops them before the
    // fillet ever sees them, so the case above no longer reaches the run
    // merge at all. At 0.3 px they survive decimation and still starve a
    // per-vertex fillet — 0.45 of a 0.3 px edge is 0.135 px — so this is the
    // case that holds the run merge to its job.
    note: "a corner split coarser than the simplification tolerance is still rounded as ONE corner",
    points: splitCorner(70, 0.3),
    rows: [],
    totalMetres: 1200,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 3.6,
    minCornerRadiusPx: 1.5,
    anchors: [],
  },
  {
    // The same coarse geometry with no floor: every vertex is rounded in
    // isolation and the achieved radius collapses. Pinned so the two answers
    // can be compared.
    note: "the same coarse split corner with no minimum radius: each vertex is rounded in isolation",
    points: splitCorner(70, 0.3),
    rows: [],
    totalMetres: 1200,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 3.6,
    anchors: [],
  },
  {
    // A platform sits inside the run. It is a place a train stops, so it may
    // not be swallowed by a corner: the run stops at it on both sides.
    note: "a station anchor inside a split corner is never swallowed by the run",
    points: splitCorner(70, 0.03),
    rows: [],
    totalMetres: 1200,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 3.6,
    minCornerRadiusPx: 1.5,
    anchors: [3],
  },
  {
    // 170° at the third vertex: a switchback, not a corner. The run may not
    // cross it and it may not be rounded, whatever the floor asks for.
    //
    // The three vertices around x = 60 are hundredths of a pixel apart, so
    // the pre-fillet decimation collapses them onto the outermost one before
    // the fillet runs — which SHARPENS the reversal (163.9° surveyed, 175.2°
    // drawn) rather than softening it, and leaves the drawn line inside
    // STROKE_SIMPLIFY_TOLERANCE_PX of every surveyed vertex. What the case
    // pins is that a reversal is never ROUNDED; the exact deflection was
    // never the drawn one, because both renderers decimated the stroke on
    // the way to the screen long before this pass moved inside buildStroke.
    note: "a hairpin among near-coincident vertices is never rounded",
    points: [[0, 0], [60, 0], [60.02, 0.004], [60.04, 0.008], [0.04, 5.008], [-60, 10]],
    rows: [],
    totalMetres: 1200,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 3.6,
    minCornerRadiusPx: 1.5,
    anchors: [],
  },
  {
    // The two halves of one line that meet at a reversal. Each is offset by
    // its own rows — lane 2 on this one, no rows at all on the next — and
    // without the join they would step 2 × 2 × 2.7 px apart at the vertex
    // they share. See the pair below and `jointIsContinuous`.
    note: "joint before a reversal: the part that arrives, carrying the next part's lane and the joint's tangents",
    points: [[0, 0], [100, 0], [200, 0]],
    measures: [0, 100, 200],
    rows: [{ from: 0, to: 200, lane: 2 }],
    totalMetres: 200,
    laneGapPx: 2.7,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [],
    joinEnd: {
      lane: 0,
      incoming: [1, 0],
      outgoing: [-100 / Math.hypot(100, 5), 5 / Math.hypot(100, 5)],
    },
  },
  {
    note: "joint after a reversal: the part that leaves, carrying the previous part's lane and the same joint",
    points: [[200, 0], [100, 5], [0, 5]],
    measures: [0, 100.12492, 200.12492],
    rows: [],
    totalMetres: 200.12492,
    laneGapPx: 2.7,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [],
    joinStart: {
      lane: 2,
      incoming: [1, 0],
      outgoing: [-100 / Math.hypot(100, 5), 5 / Math.hypot(100, 5)],
    },
  },
  {
    // The other way two halves of one line come apart at the vertex they
    // share: not the lane but a CORRIDOR FOLLOW reaching the joint. Each half
    // borrows a different canonical alignment, and `canonFrom`/`canonTo` are a
    // linear correspondence with metres of slack in it — 1150 against a
    // canonical the arriving half is 1000 m along, 60 against one the leaving
    // half is 0 m along — so the two halves substitute the SAME surveyed
    // vertex to two different points, 96.6 px apart. The shipped packages did
    // exactly this: mta-…-city-terminal-zone 9.5 px at Jamaica, ttc-509
    // 37.3 px at Exhibition Loop. The join holds both follows back one blend
    // width, and the shared vertex is drawn where the survey put it. See the
    // pair below and `followedJointIsContinuous`.
    note: "followed joint: the part that arrives, its corridor follow reaching the shared vertex",
    points: [[0, 0], [500, 0], [1000, 0]],
    measures: [0, 500, 1000],
    rows: [],
    totalMetres: 1000,
    laneGapPx: 2.7,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [],
    follows: [
      {
        from: 200,
        to: 1000,
        canonFrom: 300,
        canonTo: 1150,
        points: Array.from({ length: 13 }, (_, i) => [i * 100 - 100, 20]),
        measures: Array.from({ length: 13 }, (_, i) => i * 100),
      },
    ],
    joinEnd: { lane: 0, incoming: [1, 0], outgoing: [1, 0] },
  },
  {
    note: "followed joint: the part that leaves, its own corridor follow reaching the same vertex",
    points: [[1000, 0], [1500, 0], [2000, 0]],
    measures: [0, 500, 1000],
    rows: [],
    totalMetres: 1000,
    laneGapPx: 2.7,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [],
    follows: [
      {
        from: 0,
        to: 800,
        canonFrom: 60,
        canonTo: 860,
        points: Array.from({ length: 13 }, (_, i) => [900 + i * 100, -15]),
        measures: Array.from({ length: 13 }, (_, i) => i * 100),
      },
    ],
    joinStart: { lane: 0, incoming: [1, 0], outgoing: [1, 0] },
  },
  {
    // A follow shorter than the hold-back, at a joint, has nothing left to
    // weigh with: ttc-509's Exhibition Loop stub is 57 m long and entirely a
    // follow, and drawing it from the canonical put its stop bead 31.6 m off
    // its surveyed position. The whole stub stays as surveyed.
    note: "followed joint: a stub shorter than the hold-back keeps its own survey entire",
    points: [[0, 0], [60, 0]],
    measures: [0, 60],
    rows: [],
    totalMetres: 60,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [1],
    follows: [
      {
        from: 0,
        to: 60,
        canonFrom: 0,
        canonTo: 60,
        points: Array.from({ length: 7 }, (_, i) => [i * 10, 30]),
        measures: Array.from({ length: 7 }, (_, i) => i * 10),
      },
    ],
    joinStart: { lane: 0, incoming: [1, 0], outgoing: [1, 0] },
  },
  {
    note: "right angle on a station anchor: rounded through the anchor by an arc, the bead stays on the line",
    points: [[0, 0], [100, 0], [100, 100], [200, 100], [300, 300]],
    rows: [{ from: 0, to: 100, lane: 1 }],
    totalMetres: 600,
    laneGapPx: 3,
    minRampPx: 24,
    cornerRadiusPx: 5,
    anchors: [2],
  },
  {
    note: "plateau shorter than the kernel is crossed, not held",
    points: Array.from({ length: 41 }, (_, i) => [i * 10, 0]),
    rows: [
      { from: 0, to: 1000, lane: -2 },
      { from: 1000, to: 1040, lane: -3 },
      { from: 1040, to: 4000, lane: 0 },
    ],
    totalMetres: 4000,
    laneGapPx: 2.7,
    minRampPx: 24,
    cornerRadiusPx: 3.6,
    anchors: [0, 20, 40],
  },
  {
    note: "hairpin reversal stays sharp; exact reversal uses the incoming normal",
    points: [[0, 0], [100, 0], [0, 0.0000001], [0, 100]],
    rows: [{ from: 0, to: 300, lane: 0.5 }],
    totalMetres: 300,
    laneGapPx: 2.7,
    minRampPx: 24,
    cornerRadiusPx: 3.6,
    anchors: [],
  },
  {
    note: "duplicate vertices collapse and anchors follow the survivor",
    points: [[0, 0], [0, 0], [50, 0], [50, 0], [50, 0], [50, 50], [50, 50]],
    rows: [{ from: 0, to: 100, lane: 1 }],
    totalMetres: 100,
    laneGapPx: 2.7,
    minRampPx: 0,
    cornerRadiusPx: 3.6,
    anchors: [1, 3, 6],
  },
  {
    note: "two-point part: no interior, offset only",
    points: [[10, 10], [20, 30]],
    rows: [{ from: 0, to: 50, lane: -1 }],
    totalMetres: 50,
    laneGapPx: 2.7,
    minRampPx: 24,
    cornerRadiusPx: 3.6,
    anchors: [0, 1],
  },
  {
    note: "one-point part degenerates to a zero-length stroke",
    points: [[10, 10], [10, 10]],
    rows: [],
    totalMetres: 0,
    laneGapPx: 2.7,
    minRampPx: 24,
    cornerRadiusPx: 3.6,
    anchors: [0],
  },
  {
    note: "no rows, radius 0: the polyline passes through untouched",
    points: [[0, 0], [10, 0], [10, 10], [0, 10]],
    rows: [],
    totalMetres: 30,
    laneGapPx: 2.7,
    minRampPx: 24,
    cornerRadiusPx: 0,
    anchors: [],
  },
  {
    note: "shallow bends under the fillet floor are left on their vertex",
    points: [[0, 0], [100, 2], [200, 0], [300, 4]],
    rows: [],
    totalMetres: 300,
    laneGapPx: 2.7,
    minRampPx: 24,
    cornerRadiusPx: 3.6,
    anchors: [],
  },
  {
    note: "seam jog: a 30 m sideways step is tapered over 150 m either side",
    points: Array.from({ length: 21 }, (_, i) => [i * 50, i < 10 ? 0 : 30]),
    rows: [],
    totalMetres: 1000,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [0, 20],
  },
  {
    note: "seam jog held back by a platform 60 m before it",
    points: Array.from({ length: 21 }, (_, i) => [i * 50, i < 10 ? 0 : 30]),
    rows: [],
    totalMetres: 1000,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [0, 8, 20],
  },
  {
    note: "a jog too small to be a seam (3 m) is left alone",
    points: Array.from({ length: 21 }, (_, i) => [i * 50, i < 10 ? 0 : 3]),
    rows: [],
    totalMetres: 1000,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [],
  },
  {
    note: "a street S-bend of right angles is not a seam",
    points: [[0, 0], [200, 0], [200, 30], [400, 30], [600, 30]],
    rows: [],
    totalMetres: 630,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [],
  },
  {
    note: "offset fold: a two-pixel lane on a sub-pixel hairpin curve is unfolded",
    points: Array.from({ length: 13 }, (_, i) => {
      const angle = (Math.PI * i) / 12;
      return [Math.cos(angle) * 1.2, Math.sin(angle) * 1.2];
    }),
    rows: [{ from: 0, to: 100, lane: -2 }],
    totalMetres: 100,
    laneGapPx: 2.7,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [6],
  },
  {
    note: "corridor follow: a weaving stroke is drawn from the canonical alignment, blended in and out",
    points: Array.from({ length: 41 }, (_, i) => [i * 25, Math.sin(i / 2) * 6]),
    rows: [{ from: 0, to: 1000, lane: 1 }],
    totalMetres: 1000,
    laneGapPx: 2.7,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [0, 20, 40],
    follows: [
      {
        from: 200,
        to: 800,
        canonFrom: 250,
        canonTo: 850,
        points: Array.from({ length: 51 }, (_, i) => [i * 25 - 50, 20]),
        measures: Array.from({ length: 51 }, (_, i) => i * 25),
      },
    ],
  },
  {
    note: "corridor follow against the digitised direction: canonical measures run backwards",
    points: Array.from({ length: 21 }, (_, i) => [i * 50, i % 2 ? 4 : 0]),
    rows: [],
    totalMetres: 1000,
    laneGapPx: 2.7,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [0, 20],
    follows: [
      {
        from: 100,
        to: 900,
        canonFrom: 900,
        canonTo: 100,
        points: Array.from({ length: 21 }, (_, i) => [1000 - i * 50, 10]),
        measures: Array.from({ length: 21 }, (_, i) => i * 50),
      },
    ],
  },
  {
    note: "two seam jogs 250 m apart: each gets its own taper and the windows meet without backing over each other",
    points: [[0, 0], [200, 0], [220, 30], [240, 30], [440, 30], [460, 0], [480, 0], [800, 0]],
    rows: [],
    totalMetres: 800,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [0, 7],
  },
  {
    note: "a platform at a corridor hand-over survives the substitution fold pass and its bead stays put",
    points: Array.from({ length: 21 }, (_, i) => [i * 50, i === 10 ? 40 : 0]),
    rows: [],
    totalMetres: 1000,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [0, 10, 20],
    follows: [
      {
        from: 0, to: 480, canonFrom: 0, canonTo: 480,
        points: Array.from({ length: 11 }, (_, i) => [i * 50, 12]),
        measures: Array.from({ length: 11 }, (_, i) => i * 50),
      },
      {
        from: 520, to: 1000, canonFrom: 0, canonTo: 480,
        points: Array.from({ length: 11 }, (_, i) => [520 + i * 50, -12]),
        measures: Array.from({ length: 11 }, (_, i) => i * 50),
      },
    ],
  },
  {
    note: "a single point still answers one anchor position per requested anchor",
    points: [[5, 5]],
    rows: [],
    totalMetres: 0,
    laneGapPx: 2.7,
    minRampPx: 24,
    cornerRadiusPx: 3.6,
    anchors: [0, 0],
  },
  {
    note: "two lane rows starting at the same measure keep their input order",
    points: Array.from({ length: 21 }, (_, i) => [i * 50, 0]),
    rows: [{ from: 0, to: 400, lane: 1 }, { from: 0, to: 700, lane: -1 }, { from: 700, to: 1000, lane: 0.5 }],
    totalMetres: 1000,
    laneGapPx: 2.7,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [0, 20],
  },
  {
    note: "mitre limit: a 170° turn offsets by the clamped bisector",
    points: [[0, 0], [100, 0], [0, 17.6]],
    rows: [{ from: 0, to: 200, lane: 2 }],
    totalMetres: 200,
    laneGapPx: 2.7,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [],
  },
  {
    // Two opposite 40° bends 30 m apart (≈19.3 m lateral) — a seam jog on the
    // CANONICAL alignment, not the follower. The follower is a straight line
    // that fully takes the canonical's shape end to end; if the canonical
    // were followed raw, the jog would reappear untapered on the follower,
    // but substituteFollows tapers each canonical once before any follow
    // draws from it, so the follower's own output stays smooth: no turn
    // above 15° anywhere in the jog area.
    note: "corridor follow onto a jogged canonical: the canonical's own seam jog is tapered before any follower draws from it",
    points: Array.from({ length: 21 }, (_, i) => [i * (230 / 20), 0]),
    rows: [],
    totalMetres: 230,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [],
    follows: [
      {
        from: 0,
        to: 230,
        canonFrom: 0,
        canonTo: 230,
        points: [
          [0, 0],
          [100, 0],
          [100 + 30 * Math.cos((40 * Math.PI) / 180), 30 * Math.sin((40 * Math.PI) / 180)],
          [200 + 30 * Math.cos((40 * Math.PI) / 180), 30 * Math.sin((40 * Math.PI) / 180)],
        ],
        measures: [0, 100, 130, 230],
      },
    ],
  },
  {
    // Change 1: a lane offset that folds precisely on the anchor's own
    // vertex. removeOffsetFolds drops it, so the bead must come from the
    // surviving edge that replaced it — not the discarded offset position
    // (the bug this fixture case pins).
    note: "lane offset folds exactly at an anchor vertex: the bead is read from the surviving edge, not the discarded offset point",
    points: FOLD_AT_ANCHOR.points,
    rows: [{ from: 0, to: FOLD_AT_ANCHOR.totalMetres, lane: 2 }],
    totalMetres: FOLD_AT_ANCHOR.totalMetres,
    laneGapPx: 2.7,
    minRampPx: 0,
    // Nonzero on purpose (RAILWAY_STYLE.strokeCornerRadiusPx's own value):
    // with radius 0 filletPolyline is a no-op and the projection this case
    // exists to pin — onto the FINAL, post-fillet line rather than the
    // pre-fillet edge — is exercised vacuously, since the two lines would
    // be identical either way.
    cornerRadiusPx: 3.6,
    anchors: [1],
  },
  {
    // Change 2: a shallow turn still gets its arc — FILLET_MIN_TURN is 6°,
    // well under this one.
    note: "30 degree turn on a station anchor: rounded through the anchor by an arc, the bead stays on the line",
    points: [
      [0, 0],
      [100, 0],
      [100 + 100 * Math.cos((30 * Math.PI) / 180), 100 * Math.sin((30 * Math.PI) / 180)],
    ],
    rows: [],
    totalMetres: 200,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 20,
    minCornerRadiusPx: 0,
    anchors: [1],
  },
  {
    // Change 2: the first and last vertex of a part are never interior to
    // the fillet loop, anchor or not — this pins that an anchor there stays
    // exactly as surveyed whatever radius is asked for.
    note: "a station anchor at a chain end is never filleted, whatever the radius asks for",
    points: [[0, 0], [100, 0], [100, 100]],
    rows: [],
    totalMetres: 200,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 20,
    minCornerRadiusPx: 0,
    anchors: [0, 2],
  },
  {
    // Change 2: the outgoing edge out of the anchor is 0.707 px — far
    // shorter than the 20 px radius asked for. The tangent length is
    // already capped to FILLET_MAX_TANGENT_SHARE of the shorter edge, so
    // the arc still rounds through the anchor without swallowing it.
    note: "a station anchor beside a very short edge still rounds through the anchor, the tangent capped by that edge",
    points: [[0, 0], [100, 0], [100.5, 0.5], [200, 100]],
    rows: [],
    totalMetres: 250,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 20,
    minCornerRadiusPx: 0,
    anchors: [1],
  },
  {
    // anchorCornerOf's circumcircle solve picks between the short arc
    // through the vertex and the reflex (long way round) one; past 90° the
    // vertex sits on the far side of the chord from the circle's centre, so
    // this is the case that exercises the reflex branch of that choice
    // rather than the (more common) acute one every other anchor case above
    // stays under.
    note: "a 120 degree turn on a station anchor takes the reflex arc through the vertex",
    points: [
      [0, 0],
      [100, 0],
      [
        100 + 100 * Math.cos((120 * Math.PI) / 180),
        100 * Math.sin((120 * Math.PI) / 180),
      ],
    ],
    rows: [],
    totalMetres: 200,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 20,
    minCornerRadiusPx: 0,
    anchors: [1],
  },
  {
    // FILLET_MAX_TURN_DEGREES is 150 — a reversal at or beyond it is not a
    // corner a train can be drawn rounding through, anchor or not.
    // anchorCornerOf must return null and the vertex stays exactly as
    // surveyed, however generous the radius on offer.
    note: "a 160 degree reversal at a station anchor is left unfilleted, whatever the radius asks for",
    points: [
      [0, 0],
      [100, 0],
      [
        100 + 100 * Math.cos((160 * Math.PI) / 180),
        100 * Math.sin((160 * Math.PI) / 180),
      ],
    ],
    rows: [],
    totalMetres: 200,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 20,
    minCornerRadiusPx: 0,
    anchors: [1],
  },
  {
    // The run-merged corner just before the anchor (see splitCorner above)
    // is rounded as ONE corner whose apex sits behind its own last vertex —
    // so the "forward" distance FILLET_MAX_TANGENT_SHARE caps its tangent
    // against is the apex-adjusted one, not the literal 3 px edge that
    // follows, and its endOffset can reach further into that edge than a
    // lone vertex's corner ever could. The anchor right after it, on that
    // same short edge, must have ITS tangent clamped so the two arcs cannot
    // cross (guardEdge / guardOffset).
    note: "a station anchor's tangent is clamped by the run-merged corner just before it, sharing a short edge",
    points: (() => {
      const out = [[0, 0], [60, 0]];
      let x = 60;
      let y = 0;
      let heading = 0;
      for (let index = 0; index < 4; index += 1) {
        heading += ((100 * Math.PI) / 180) / 4;
        x += Math.cos(heading) * 0.05;
        y += Math.sin(heading) * 0.05;
        out.push([x, y]);
      }
      x += Math.cos(heading) * 3;
      y += Math.sin(heading) * 3;
      out.push([x, y]);
      heading += (45 * Math.PI) / 180;
      x += Math.cos(heading) * 60;
      y += Math.sin(heading) * 60;
      out.push([x, y]);
      return out;
    })(),
    rows: [],
    totalMetres: 1200,
    laneGapPx: 0,
    minRampPx: 0,
    cornerRadiusPx: 20,
    minCornerRadiusPx: 5,
    anchors: [6],
  },
];

// familyPartition / clipRangesToComplement — the family-collapse window
// partition RailMapView.swift's `continuousStrokeBuild` (and railmap.js's
// own family-window branch) applies, pinned directly rather than only
// through a real corridor's own windows (family-windows.mjs's REAL_CASES,
// which may not happen to exercise every boundary shape). Synthetic probes
// for: no windows at all; a single tenant or landlord window; a window
// pinned to the very start or end of the part; a tenant and a landlord
// window meeting end-to-end (no base gap between them); two landlord
// windows of different groups meeting end-to-end; a tenant window covering
// the whole part; overlapping tenant+landlord windows over one stretch (not
// a shape the data contract produces, but the function must not crash or
// double-count if it ever sees one); reversed window inputs (`from > to`);
// and a `measureStart`/`measureEnd` narrower than `[0, totalMetres]` — the
// stroke's own measure range, which a joint's extension or a follow's own
// vertices can leave short of the part's nominal total.
const FAMILY_PARTITION_CASES = [
  {
    note: "no windows at all: the whole range is one base piece",
    totalMetres: 1000,
    tenantWindows: [],
    landlordWindows: [],
  },
  {
    note: "a single landlord window in the middle",
    totalMetres: 1000,
    tenantWindows: [],
    landlordWindows: [{ from: 400, to: 600, groupId: "g1" }],
  },
  {
    note: "a single tenant window in the middle",
    totalMetres: 1000,
    tenantWindows: [{ from: 400, to: 600, groupId: "g1" }],
    landlordWindows: [],
  },
  {
    note: "a tenant window pinned to the very start",
    totalMetres: 1000,
    tenantWindows: [{ from: 0, to: 250, groupId: "g1" }],
    landlordWindows: [],
  },
  {
    note: "a tenant window pinned to the very end",
    totalMetres: 1000,
    tenantWindows: [{ from: 750, to: 1000, groupId: "g1" }],
    landlordWindows: [],
  },
  {
    note: "a landlord window pinned to the very start, a tenant window pinned to the very end",
    totalMetres: 1000,
    tenantWindows: [{ from: 800, to: 1000, groupId: "g2" }],
    landlordWindows: [{ from: 0, to: 200, groupId: "g1" }],
  },
  {
    note: "a tenant and a landlord window meeting end-to-end (no base gap between them)",
    totalMetres: 1000,
    tenantWindows: [{ from: 300, to: 500, groupId: "g1" }],
    landlordWindows: [{ from: 500, to: 700, groupId: "g2" }],
  },
  {
    note: "two landlord windows of different groups meeting end-to-end",
    totalMetres: 1000,
    tenantWindows: [],
    landlordWindows: [
      { from: 300, to: 500, groupId: "g1" },
      { from: 500, to: 700, groupId: "g2" },
    ],
  },
  {
    note: "a tenant window entirely covering the part (no base pieces survive)",
    totalMetres: 1000,
    tenantWindows: [{ from: 0, to: 1000, groupId: "g1" }],
    landlordWindows: [],
  },
  {
    note: "overlapping tenant and landlord windows over one stretch (not a reviewed contract shape, but must not crash or double-count)",
    totalMetres: 1000,
    tenantWindows: [{ from: 400, to: 700, groupId: "g1" }],
    landlordWindows: [{ from: 600, to: 900, groupId: "g2" }],
  },
  {
    note: "reversed window inputs (from > to) are normalised",
    totalMetres: 1000,
    tenantWindows: [{ from: 600, to: 400, groupId: "g1" }],
    landlordWindows: [{ from: 900, to: 700, groupId: "g2" }],
  },
  {
    note: "windows outside the clamp range on both sides are clamped away entirely",
    totalMetres: 1000,
    measureStart: 200,
    measureEnd: 800,
    tenantWindows: [{ from: -100, to: 100, groupId: "g1" }],
    landlordWindows: [{ from: 900, to: 1200, groupId: "g2" }],
  },
  {
    note: "measureStart/measureEnd narrower than [0, totalMetres] (a joined stroke's own measure range)",
    totalMetres: 1000,
    measureStart: 150,
    measureEnd: 900,
    tenantWindows: [{ from: 200, to: 400, groupId: "g1" }],
    landlordWindows: [{ from: 600, to: 850, groupId: "g2" }],
  },
];

// clipRangesToComplement — a withheld span (rail-network.js `part.
// withheld`) clipped to the complement of this chain's own tenant windows.
// Probes: no tenant windows at all (identity); a span straddling a tenant
// window's leading edge, its trailing edge, and both edges at once (the
// window entirely inside the span); a span entirely swallowed by one tenant
// window (nothing survives); a span straddling two separate tenant windows;
// and a reversed span (`from > to`).
const CLIP_TO_COMPLEMENT_CASES = [
  {
    note: "no tenant windows: the range passes through untouched",
    ranges: [{ from: 100, to: 900 }],
    tenantWindows: [],
  },
  {
    note: "a withheld span straddling a tenant window's LEADING edge",
    ranges: [{ from: 300, to: 500 }],
    tenantWindows: [{ from: 400, to: 700, groupId: "g1" }],
  },
  {
    note: "a withheld span straddling a tenant window's TRAILING edge",
    ranges: [{ from: 600, to: 800 }],
    tenantWindows: [{ from: 400, to: 700, groupId: "g1" }],
  },
  {
    note: "a withheld span straddling both edges of one tenant window (the window entirely inside the span)",
    ranges: [{ from: 100, to: 900 }],
    tenantWindows: [{ from: 400, to: 700, groupId: "g1" }],
  },
  {
    note: "a withheld span entirely inside a tenant window: nothing survives",
    ranges: [{ from: 450, to: 650 }],
    tenantWindows: [{ from: 400, to: 700, groupId: "g1" }],
  },
  {
    note: "a withheld span straddling two separate tenant windows",
    ranges: [{ from: 100, to: 900 }],
    tenantWindows: [
      { from: 200, to: 400, groupId: "g1" },
      { from: 600, to: 800, groupId: "g2" },
    ],
  },
  {
    note: "a reversed withheld span (from > to)",
    ranges: [{ from: 500, to: 300 }],
    tenantWindows: [{ from: 400, to: 700, groupId: "g1" }],
  },
];

export function build({ RailNetwork, railPackage, APP_DIR }) {
  const RailStroke = require(path.join(APP_DIR, "public", "rail-stroke.js"));
  const railDir = path.join(APP_DIR, "public", "rail");
  const reviewed = JSON.parse(
    fs.readFileSync(path.join(railDir, "shared-corridors.json"), "utf8"),
  );
  const lanes = JSON.parse(
    fs.readFileSync(path.join(railDir, "display-lanes.json"), "utf8"),
  );
  const networks = new Map();
  const networkFor = (country) => {
    if (!networks.has(country))
      networks.set(
        country,
        RailNetwork.buildNetworkFromCompactPackage(railPackage(country), reviewed, lanes),
      );
    return networks.get(country);
  };

  const cases = [];
  const projections = [];
  for (const real of REAL_CASES) {
    const network = networkFor(real.country);
    const line = network.strokeModel.lines.find((held) => held.lineId === real.lineId);
    if (!line) throw new Error(`continuous-stroke fixture: ${real.lineId} has no stroke model`);
    const partsByLine = new Map(network.strokeModel.lines.map((held) => [held.lineId, held.parts]));
    line.parts.forEach((part, partIndex) => {
      for (const zoom of real.zooms) {
        const points = part.coordinates.map((point) => RailStroke.project(point, zoom));
        const follows = (part.follows || [])
          .map((follow) => {
            const canon = partsByLine.get(follow.canonLineId)?.[follow.canonPartIndex];
            return canon
              ? {
                  from: follow.from,
                  to: follow.to,
                  canonFrom: follow.canonFrom,
                  canonTo: follow.canonTo,
                  points: canon.coordinates.map((point) => RailStroke.project(point, zoom)),
                  measures: canon.measures,
                }
              : null;
          })
          .filter(Boolean);
        // The zoom ramp the web app applies to every screen-space token.
        const scale = Math.min(1, Math.max(1 / 3, Math.pow(Math.SQRT2, zoom - 7)));
        const options = {
          measures: part.measures,
          rows: part.rows,
          totalMetres: part.totalMetres,
          laneGapPx: 2.7 * scale,
          minRampPx: 24,
          cornerRadiusPx: 3.6 * scale,
          // RAILWAY_STYLE.minCornerRadiusPx — two stroke widths, the radius
          // the map promises to present. The real parts carry it so the run
          // merge is exercised on real geometry rather than only on probes.
          minCornerRadiusPx: 3 * scale,
          enforceMinimumCornerRadius: true,
          anchors: part.anchors,
          follows,
        };
        const stroke = RailStroke.buildStroke(points, options);
        cases.push({
          note: `${real.country} ${real.lineId} part ${partIndex} at z${zoom}`,
          points,
          ...options,
          expected: stroke,
        });
      }
      projections.push({
        lonLat: part.coordinates[0],
        zoom: real.zooms[0],
        px: RailStroke.project(part.coordinates[0], real.zooms[0]),
        back: RailStroke.unproject(
          RailStroke.project(part.coordinates[0], real.zooms[0]),
          real.zooms[0],
        ),
      });
    });
  }
  for (const probe of SYNTHETIC)
    cases.push({ ...probe, expected: RailStroke.buildStroke(probe.points, probe) });

  // slices — RailStroke.sliceStroke() against a handful of the cases above,
  // chosen to cover: the whole part, a sub-metre span, a span inside a
  // fillet's curve, a span across a taper window, a span across a follow, a
  // reversed span (from > to), a span clamped beyond both ends, and a
  // degenerate span.
  const findCase = (note) => {
    const index = cases.findIndex((held) => held.note === note);
    if (index < 0) throw new Error(`continuous-stroke fixture: slice case not found: ${note}`);
    return index;
  };
  const slices = [];
  const addSlice = (caseIndex, from, to) => {
    const held = cases[caseIndex];
    slices.push({
      caseIndex,
      from,
      to,
      expected: RailStroke.sliceStroke(held.expected.points, held.expected.measures, from, to),
    });
  };

  const njtIndex = findCase("us new-jersey-transit-nj-transi-nec part 0 at z9");
  const njtMeasures = cases[njtIndex].expected.measures;
  const njtLo = njtMeasures[0];
  const njtHi = njtMeasures[njtMeasures.length - 1];
  addSlice(njtIndex, njtLo, njtHi); // whole part
  addSlice(njtIndex, njtLo + (njtHi - njtLo) * 0.3, njtLo + (njtHi - njtLo) * 0.3 + 0.5); // sub-metre span
  addSlice(njtIndex, njtHi, njtLo); // reversed, whole part
  addSlice(njtIndex, njtLo - 1e6, njtHi + 1e6); // clamped beyond both ends

  const filletIndex = findCase("right angle on a station anchor: rounded through the anchor by an arc, the bead stays on the line");
  const filletMeasures = cases[filletIndex].expected.measures;
  addSlice(filletIndex, filletMeasures[2], filletMeasures[6]); // inside a fillet's curve
  addSlice(filletIndex, filletMeasures[6], filletMeasures[2]); // reversed, inside a fillet

  const jogIndex = findCase("seam jog: a 30 m sideways step is tapered over 150 m either side");
  addSlice(jogIndex, 400, 600); // across a taper window

  const followIndex = findCase(
    "corridor follow: a weaving stroke is drawn from the canonical alignment, blended in and out",
  );
  addSlice(followIndex, 150, 850); // across a follow

  const dupIndex = findCase("duplicate vertices collapse and anchors follow the survivor");
  const dupMeasures = cases[dupIndex].expected.measures;
  addSlice(dupIndex, dupMeasures[0], dupMeasures[0]); // degenerate span
  addSlice(dupIndex, -50, -10); // degenerate span, entirely out of range

  const profiles = [
    { rows: [], total: 1000 },
    { rows: [{ from: 0, to: 1000, lane: -1 }], total: 1000 },
    {
      rows: [
        { from: 0, to: 5000, lane: -2 },
        { from: 5000, to: 5100, lane: -3 },
        { from: 5100, to: 12000, lane: 0 },
        { from: 12000, to: 12030, lane: 1 },
        { from: 12030, to: 20000, lane: 1.5 },
      ],
      total: 20000,
    },
    { rows: [{ from: 900, to: 30000, lane: 0.5 }], total: 1000 },
    // With a neighbour's lane at each end: the terminal step is evaluated by
    // the kernel instead of held flat, which is what makes both halves of one
    // line read the same lane at the vertex they share.
    { rows: [{ from: 0, to: 1000, lane: 2 }], total: 1000, joinEnd: 0 },
    { rows: [], total: 1000, joinStart: 2 },
    // A neighbour that agrees coalesces away and the answer is unchanged.
    { rows: [{ from: 0, to: 1000, lane: -1 }], total: 1000, joinStart: -1, joinEnd: -1 },
  ].map(({ rows, total, joinStart, joinEnd }) => {
    const profile = RailStroke.laneProfile(rows, total, joinStart, joinEnd);
    const samples = [0, 100, 900, 1000, 4800, 5000, 5050, 5200, 5500, 11900, 12000, 12100, 13000, 19999, 20000];
    return {
      rows,
      total,
      joinStart: joinStart == null ? null : joinStart,
      joinEnd: joinEnd == null ? null : joinEnd,
      profile,
      samples: samples.map((measure) => ({
        measure,
        atWidth300: RailStroke.laneAt(profile, measure, 300),
        atWidth0: RailStroke.laneAt(profile, measure, 0),
      })),
    };
  });

  const familyPartitions = FAMILY_PARTITION_CASES.map((probe) => ({
    ...probe,
    expected: RailStroke.familyPartition(
      probe.totalMetres,
      probe.tenantWindows,
      probe.landlordWindows,
      { measureStart: probe.measureStart, measureEnd: probe.measureEnd },
    ),
  }));
  const clipsToComplement = CLIP_TO_COMPLEMENT_CASES.map((probe) => ({
    ...probe,
    expected: RailStroke.clipRangesToComplement(probe.ranges, probe.tenantWindows),
  }));

  return {
    describes:
      "rail-stroke.js buildStroke / laneProfile / laneAt / project / unproject / " +
      "familyPartition / clipRangesToComplement",
    contract:
      "One continuous polyline per part with the lane offset baked in through " +
      "a triangular-kernel lane profile and its corners rounded; station " +
      "anchors are the offset of their own vertex and are never trimmed. " +
      "Pixel space in, pixel space out; the projection is pinned separately.",
    constants: {
      LANE_RAMP_HALF_WIDTH_METRES: RailStroke.LANE_RAMP_HALF_WIDTH_METRES,
      LANE_PLATEAU_MIN_METRES: RailStroke.LANE_PLATEAU_MIN_METRES,
      LANE_JOIN_EXTENT_METRES: RailStroke.LANE_JOIN_EXTENT_METRES,
      FOLLOW_BLEND_METRES: RailStroke.FOLLOW_BLEND_METRES,
      JOG_MIN_TURN_DEGREES: RailStroke.JOG_MIN_TURN_DEGREES,
      JOG_MAX_TURN_DEGREES: RailStroke.JOG_MAX_TURN_DEGREES,
      JOG_MAX_RUN_METRES: RailStroke.JOG_MAX_RUN_METRES,
      JOG_MAX_NET_TURN_DEGREES: RailStroke.JOG_MAX_NET_TURN_DEGREES,
      JOG_MIN_LATERAL_METRES: RailStroke.JOG_MIN_LATERAL_METRES,
      JOG_TAPER_METRES: RailStroke.JOG_TAPER_METRES,
      JOG_MIN_TAPER_METRES: RailStroke.JOG_MIN_TAPER_METRES,
      JOG_TAPER_SAMPLES: RailStroke.JOG_TAPER_SAMPLES,
      FOLD_TURN_DEGREES: RailStroke.FOLD_TURN_DEGREES,
      FILLET_MIN_TURN_DEGREES: RailStroke.FILLET_MIN_TURN_DEGREES,
      FILLET_MAX_TURN_DEGREES: RailStroke.FILLET_MAX_TURN_DEGREES,
      FILLET_MAX_TANGENT_SHARE: RailStroke.FILLET_MAX_TANGENT_SHARE,
      FILLET_STEP_DEGREES: RailStroke.FILLET_STEP_DEGREES,
      STROKE_SIMPLIFY_TOLERANCE_PX: RailStroke.STROKE_SIMPLIFY_TOLERANCE_PX,
      MITER_LIMIT: RailStroke.MITER_LIMIT,
    },
    profiles,
    projections,
    cases,
    slices,
    familyPartitions,
    clipsToComplement,
  };
}
