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
];

const SYNTHETIC = [
  {
    note: "right angle on a station anchor: the anchor vertex is never rounded",
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
    note: "mitre limit: a 170° turn offsets by the clamped bisector",
    points: [[0, 0], [100, 0], [0, 17.6]],
    rows: [{ from: 0, to: 200, lane: 2 }],
    totalMetres: 200,
    laneGapPx: 2.7,
    minRampPx: 0,
    cornerRadiusPx: 0,
    anchors: [],
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
  ].map(({ rows, total }) => {
    const profile = RailStroke.laneProfile(rows, total);
    const samples = [0, 100, 900, 1000, 4800, 5000, 5050, 5200, 5500, 11900, 12000, 12100, 13000, 19999, 20000];
    return {
      rows,
      total,
      profile,
      samples: samples.map((measure) => ({
        measure,
        atWidth300: RailStroke.laneAt(profile, measure, 300),
        atWidth0: RailStroke.laneAt(profile, measure, 0),
      })),
    };
  });

  return {
    describes:
      "rail-stroke.js buildStroke / laneProfile / laneAt / project / unproject",
    contract:
      "One continuous polyline per part with the lane offset baked in through " +
      "a triangular-kernel lane profile and its corners rounded; station " +
      "anchors are the offset of their own vertex and are never trimmed. " +
      "Pixel space in, pixel space out; the projection is pinned separately.",
    constants: {
      LANE_RAMP_HALF_WIDTH_METRES: RailStroke.LANE_RAMP_HALF_WIDTH_METRES,
      LANE_PLATEAU_MIN_METRES: RailStroke.LANE_PLATEAU_MIN_METRES,
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
      MITER_LIMIT: RailStroke.MITER_LIMIT,
    },
    profiles,
    projections,
    cases,
  };
}
