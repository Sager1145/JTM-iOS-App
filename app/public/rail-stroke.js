/*
 * rail-stroke.js — the continuous screen-space stroke of one railway part.
 *
 * WHY THIS FILE EXISTS. A railway that shares a corridor with another is drawn
 * beside it in a screen-space lane: a fixed number of pixels off the surveyed
 * centreline, the same number at every zoom. The first implementation handed
 * that offset to the renderer as a per-feature constant (MapLibre's
 * `line-offset`, one MKPolyline per lane on iOS) and CUT the railway into a
 * new feature wherever its lane changed — quarter-lane steps down a ramp, so
 * a line that moved three lanes became a dozen abutting pieces. Every piece
 * boundary was a place the stroke could come apart: two round caps that did
 * not quite coincide, a casing drawn twice, a seam that opened as the camera
 * moved. The reader saw a railway in fragments.
 *
 * This module draws the railway as ONE polyline instead. The lane profile is
 * a continuous function of the distance along the part — the reviewed lane
 * plateaus seen through a smoothing kernel, so every change is an S-curve —
 * and the offset is baked into the vertices themselves,
 * in projected pixel space at the zoom the map is currently at. Because the
 * geometry already carries its offset, the renderer's own offset is zero, one
 * part is one feature, and nothing about panning can break it. Zooming
 * changes how many pixels a metre is, so the caller rebuilds the stroke when
 * the zoom has moved far enough for the lane gap to drift (the same rule the
 * iOS renderer has always applied to its lane geometry).
 *
 * The same pass rounds the corners. A polyline handed to a renderer as a
 * chain of straight edges turns on a vertex; a railway does not, and neither
 * does a transit map worth reading. Every interior bend sharper than a few
 * degrees is replaced by a curve tangent to both edges, of a radius that is a
 * screen-space token (RAILWAY_STYLE.strokeCornerRadiusPx) and never larger
 * than the two edges can carry — so a station-spaced tram corner and a
 * mainline curve both round by the same visual rule, and a hairpin reversal,
 * which is a real switchback, is left exactly as surveyed.
 *
 * Station anchors are protected twice over: the vertex a platform sits on is
 * never trimmed by a fillet, and the platform's own screen position is the
 * offset of that very vertex, so a station bead stays on its stroke at every
 * lane and every zoom.
 *
 * Everything here works in an abstract 2-D pixel space handed in by the
 * caller: the web app projects to Web-Mercator world pixels at the current
 * zoom, iOS to map points per screen point. The maths is deliberately free of
 * anything platform-specific so that the Swift port (RailCore
 * ContinuousStroke) can be checked against this file's answers on the same
 * fixtures. Keep it that way.
 */
(function (root, factory) {
  "use strict";

  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.RailStroke = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  // ── the lane profile ─────────────────────────────────────────────────────
  // A lane change is a drift, not a step: the lane profile is smoothed over
  // this half-width (in metres, or the pixel floor the caller adds when the
  // zoom makes this under a pixel), so the sideways travel between two lanes
  // is a shallow S-curve whose slope never exceeds one lane per this many
  // metres. See laneAt().
  const LANE_RAMP_HALF_WIDTH_METRES = 300;
  // A stretch shorter than the sampling the lane rows were measured at is not
  // evidence of a lane; it is absorbed into its longer neighbour.
  const LANE_PLATEAU_MIN_METRES = 60;
  // ── the joint between two parts of one line ──────────────────────────────
  // A line the display pass cut into parts at a reversal or a retrace is still
  // ONE railway, and the two pieces meet at one surveyed vertex. Each piece is
  // offset by its OWN rows, and at a shared vertex the two answers have to be
  // the same answer or the reader sees the line come apart there — measured on
  // the shipped US package at 18.9 px (mta-…-city-terminal-zone, lane −3.5) and
  // 2.7 px (amtrak-ethan-allen-express, lane −0.5), because the two pieces
  // approach the joint from opposite directions and the right-hand normal
  // therefore points opposite ways.
  //
  // A `Join` closes it. The neighbour's terminal lane is carried in as a
  // plateau that extends past this part's own end (this far, in metres — far
  // enough that no kernel can see its far side), so BOTH pieces evaluate the
  // step at the joint as the same half-way value; and the pair of tangents at
  // the joint is the SAME pair for both pieces, so the bisector normal, its
  // mitre scale and therefore the offset vertex are identical on both sides.
  // The two strokes then meet at one point, exactly, at every zoom and every
  // lane. See `laneProfile` and `offsetPolyline`.
  const LANE_JOIN_EXTENT_METRES = 1e7;

  // ── corridor follows ─────────────────────────────────────────────────────
  // Over a reviewed stretch a line is drawn from another part's alignment —
  // the canonical stroke of the corridor they share — and only then offset
  // into its own lane. Every lane of a bundle then comes off ONE centreline,
  // which is what keeps two strokes from weaving across each other by the
  // width of a survey. The substitution is blended in and out with the same
  // triangular kernel as a lane change, so the stroke drifts onto the
  // corridor and off it again with continuous tangent. Vertices of the
  // canonical alignment are added over the stretch so its shape is kept
  // whatever the follower's own sampling was.
  //
  // A follow is `{from, to, canonFrom, canonTo, points, measures}`: the
  // follower's measures in metres, the canonical part's measures in metres
  // (reversed when the two are digitised against each other), the canonical
  // part's vertices in the SAME pixel space as the follower's, and the
  // cumulative metres along the canonical part at each of those vertices.
  //
  // A follow may NOT reach a joint. `canonFrom`/`canonTo` are a LINEAR
  // correspondence between two measure rulers, reviewed and stored to a tenth
  // of a metre, and the two alignments are rarely the same length over the
  // stretch — so the measure a follower's vertex maps to on the canonical is
  // right to a few metres, no better. In the middle of a stretch that slack
  // slides a vertex a metre or two ALONG a corridor the follower is coincident
  // with, which is invisible. At the vertex two parts of one line SHARE it is
  // fatal: the neighbour has its own correspondence, or none at all, and the
  // two answers cannot agree — the shipped US/CA packages separated
  // mta-…-city-terminal-zone by 9.5 px at Jamaica (the two alignments are
  // coincident to 0.0 m there; the whole gap is 8.6 m of along-track slack in
  // `canonTo`) and ttc-509 by 37.3 px at Exhibition Loop (where the follow
  // over-reaches by 270 m onto a loop track ttc-511 does not share). So each
  // follow's WEIGHT is held back one blend width from a joint — the
  // correspondence itself is untouched — and the shared vertex is drawn where
  // the survey put it, which is the one answer both parts can reach. See
  // substituteFollows() and the `Join` note above.
  const FOLLOW_BLEND_METRES = 300;

  // ── seam jogs ────────────────────────────────────────────────────────────
  // A survey seam that was welded sideways — one alignment's endpoint
  // snapped onto the next alignment's junction — leaves a Z in the line: two
  // opposite bends of tens of degrees within a few tens of metres, with the
  // heading the same on both sides and the track a few tens of metres over.
  // No railway turns like that. The Z is redrawn as a taper: the lateral
  // shift is spread over TAPER metres either side with a smoothstep blend
  // between the incoming and outgoing alignments, so the stroke drifts
  // across instead of stepping. Real geometry is protected by the shape
  // test — a street tram's S-bend between blocks is right angles, a
  // switchback is a reversal, a curve is one bend — and by the anchors:
  // a platform is never moved and never crossed by a taper.
  const JOG_MIN_TURN_DEGREES = 25;
  const JOG_MAX_TURN_DEGREES = 100;
  const JOG_MAX_RUN_METRES = 60;
  const JOG_MAX_NET_TURN_DEGREES = 15;
  const JOG_MIN_LATERAL_METRES = 8;
  const JOG_TAPER_METRES = 150;
  const JOG_MIN_TAPER_METRES = 40;
  const JOG_TAPER_SAMPLES = 8;

  // ── the corners ──────────────────────────────────────────────────────────
  // Below this deflection the round join already draws the corner.
  const FILLET_MIN_TURN_DEGREES = 6;
  // Above this the vertex is a reversal — a switchback, a terminal
  // turnback — and rounding it would draw a curve the railway does not have.
  const FILLET_MAX_TURN_DEGREES = 150;
  // A fillet may borrow at most this share of each edge it sits on, so two
  // fillets on one edge can never cross each other.
  //
  // That cap is also how the radius used to collapse. Where a survey leaves
  // two vertices a hundredth of a pixel apart — a welded duplicate, or a real
  // curve sampled every 20 m and drawn at a regional zoom — 0.45 of the
  // shorter edge is a hundredth of a pixel too, and the corner the reader sees
  // is a bare kink whatever radius was asked for. Measured over every US and
  // CA part at z10/13/15/17: 8.4 % of rounded corners were capped by this
  // share and 3.7 % came out under one stroke width, the sharpest at
  // 0.0023 px. The fix is not a bigger share — two fillets would cross — but
  // to stop treating such a pair as two corners: see `filletPolyline`, which
  // rounds a RUN of vertices as one corner when no single one of them can
  // reach the floor on its own.
  const FILLET_MAX_TANGENT_SHARE = 0.45;
  // Curve sampling: one vertex per this many degrees of turn.
  const FILLET_STEP_DEGREES = 12;
  // Offsetting a vertex along its bisector scales the offset by 1/cos(θ/2).
  // Past this factor the corner is sharp enough that a mitre would spike;
  // the offset is clamped and the fillet pass rounds what is left.
  const MITER_LIMIT = 2.5;
  // Two vertices closer than this, in pixels, are one vertex.
  const DEGENERATE_EDGE_PX = 1e-6;

  // ── pre-fillet simplification ───────────────────────────────────────────
  // How far the DRAWN line may leave the surveyed one, in pixels. The same
  // number railmap-style.js gives its geojson sources as
  // SEGMENT_SIMPLIFY_TOLERANCE_PX and RailStyle.swift declares as
  // `simplifyTolerance` — one epsilon, three places that must agree
  // (ios/verify.sh pins all three against each other textually).
  //
  // It is spent HERE, on the straight polyline, and never again on the
  // rounded one. Decimating a stroke AFTER its corners are rounded removes
  // every fillet whose sagitta r(1 − cos(T/2)) falls under the tolerance —
  // at r = 3.6 px that is every corner under about 21 degrees of turn,
  // rounded and then immediately redrawn as the chord it was drawn to
  // replace. Simplifying FIRST also feeds the fillet: the sub-pixel edges a
  // regional zoom leaves behind are what starved `cornerOf`'s tangent clamp
  // of the radius it was promising. Both renderers therefore hand the
  // rounded output to their rasteriser untouched (geojson `tolerance: 0` on
  // the web, epsilon 0 in RailMapView).
  const STROKE_SIMPLIFY_TOLERANCE_PX = 0.0625;

  // ── family-collapse partition ───────────────────────────────────────────
  // A piece of a `familyPartition`/`clipRangesToComplement` result shorter
  // than this, in METRES, is boundary noise (two windows that snapped onto
  // the same station measure, a range clipped exactly onto a window edge)
  // rather than evidence of a piece either renderer should draw.
  const FAMILY_PARTITION_EPSILON_METRES = 1e-6;

  const WORLD_PX_AT_ZOOM_0 = 512;

  // ── projection helpers (web mercator, 512-px tiles, y grows south) ──────
  function worldSize(zoom) {
    return WORLD_PX_AT_ZOOM_0 * Math.pow(2, zoom);
  }

  function project(lonLat, zoom) {
    const size = worldSize(zoom);
    const lat = Math.max(-85.051129, Math.min(85.051129, lonLat[1]));
    const sin = Math.sin((lat * Math.PI) / 180);
    return [
      ((lonLat[0] + 180) / 360) * size,
      (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math.PI)) * size,
    ];
  }

  function unproject(point, zoom) {
    const size = worldSize(zoom);
    const lon = (point[0] / size) * 360 - 180;
    const n = Math.PI - (2 * Math.PI * point[1]) / size;
    const lat = (180 / Math.PI) * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)));
    return [lon, lat];
  }

  // ── lane profile ─────────────────────────────────────────────────────────
  // `rows` are `{from, to, lane}` in metres along the part; `total` is the
  // part's length in metres. The profile is the list of plateaus the rows
  // describe, with the centreline filling every gap and stretches too short
  // to be evidence absorbed into their neighbours. The FIRST plateau extends
  // back past the start of the part and the LAST extends past its end, so the
  // smoothing below never bends a stroke towards the centreline at a
  // terminal it approaches in a lane.
  //
  // `joinStart` / `joinEnd`, when given, are the lane the NEIGHBOURING part of
  // the same line holds at the vertex this part shares with it. Each is added
  // as a plateau reaching LANE_JOIN_EXTENT_METRES beyond this part's own end,
  // so the terminal step is evaluated by the kernel rather than held flat —
  // and because `kernelCumulative(0, width) = 1/2` for every width, both parts
  // read exactly (own + neighbour) / 2 at the joint whatever zoom either of
  // them was built at. When the two agree the plateaus coalesce and the answer
  // is the flat terminal lane this file has always produced.
  function laneProfile(rows, total, joinStart, joinEnd) {
    if (!(total > 0)) return [];
    const plateaus = [];
    let cursor = 0;
    // Ties broken by input order explicitly, so both ports agree whatever
    // their sort's stability guarantees.
    const sorted = (rows || [])
      .map((row, index) => [row, index])
      .sort((a, b) => a[0].from - b[0].from || a[1] - b[1])
      .map(([row]) => row);
    for (const row of sorted) {
      const from = Math.max(cursor, Math.min(row.from, total));
      const to = Math.max(from, Math.min(row.to, total));
      if (from > cursor) plateaus.push({ from: cursor, to: from, lane: 0 });
      if (to > from) plateaus.push({ from, to, lane: row.lane });
      cursor = to;
    }
    if (cursor < total) plateaus.push({ from: cursor, to: total, lane: 0 });
    if (joinStart != null)
      plateaus.unshift({ from: -LANE_JOIN_EXTENT_METRES, to: 0, lane: joinStart });
    if (joinEnd != null)
      plateaus.push({ from: total, to: total + LANE_JOIN_EXTENT_METRES, lane: joinEnd });
    return coalesceLanePlateaus(plateaus);
  }

  // Absorb every stretch too short to be evidence into its longer neighbour,
  // shortest first, then join whatever now agrees.
  function coalesceLanePlateaus(plateaus) {
    const held = plateaus.slice();
    for (;;) {
      if (held.length < 2) break;
      let at = -1;
      for (let index = 0; index < held.length; index += 1) {
        const span = held[index].to - held[index].from;
        if (span >= LANE_PLATEAU_MIN_METRES) continue;
        if (at < 0 || span < held[at].to - held[at].from) at = index;
      }
      if (at < 0) break;
      const previous = held[at - 1];
      const next = held[at + 1];
      const intoPrevious =
        previous && (!next || previous.to - previous.from >= next.to - next.from);
      if (intoPrevious) previous.to = held[at].to;
      else next.from = held[at].from;
      held.splice(at, 1);
    }
    const out = [];
    for (const plateau of held) {
      const previous = out[out.length - 1];
      if (previous && previous.lane === plateau.lane) previous.to = plateau.to;
      else out.push({ from: plateau.from, to: plateau.to, lane: plateau.lane });
    }
    return out;
  }

  // The lane at one measure: the plateau step function seen through a
  // triangular kernel of half-width `width` — the step convolved with a box
  // twice — which is the cheapest smoothing that leaves NO corner anywhere
  // in the profile: the lateral slope is bounded by (lane change) / width,
  // the drift into and out of every plateau is an S-curve with continuous
  // tangent, and a plateau shorter than the kernel is crossed rather than
  // held, so two changes close together read as one drift instead of a
  // jog. The kernel is evaluated in closed form against each plateau.
  //
  // `width` is in metres; the caller derives it from the metre ramp and the
  // pixel floor, so at a regional zoom the drift is still a drift.
  function kernelCumulative(x, width) {
    if (x <= -width) return 0;
    if (x >= width) return 1;
    if (x <= 0) {
      const t = x + width;
      return (t * t) / (2 * width * width);
    }
    const t = width - x;
    return 1 - (t * t) / (2 * width * width);
  }

  function laneAt(profile, measure, width) {
    if (!profile.length) return 0;
    if (!(width > 0)) {
      for (const plateau of profile)
        if (measure <= plateau.to) return plateau.lane;
      return profile[profile.length - 1].lane;
    }
    let lane = 0;
    const last = profile.length - 1;
    for (let index = 0; index <= last; index += 1) {
      const plateau = profile[index];
      if (!plateau.lane) continue;
      const start = index === 0 ? 1 : kernelCumulative(measure - plateau.from, width);
      const end = index === last ? 0 : kernelCumulative(measure - plateau.to, width);
      lane += plateau.lane * (start - end);
    }
    return lane;
  }

  // Whether any stretch of the profile leaves the centreline.
  function profileIsFlat(profile) {
    return profile.every((plateau) => !plateau.lane);
  }

  // Survey vertices describe the alignment, not its lane profile. A long
  // straight edge may contain an entire lane excursion with neither end in
  // that lane. Sample the triangular-kernel ramps before offsetting, retaining
  // every original vertex and its anchor mapping. For each half of a ramp,
  // linear interpolation of the quadratic kernel has error
  // |lane delta * gap| / (8 * subdivisions²). Overlapping ramps share an
  // error budget so their combined displacement remains sub-pixel.
  function sampleLaneRamps(points, measures, profile, width, gap) {
    const identity = points.map((_, index) => index);
    if (
      points.length < 2 ||
      profile.length < 2 ||
      !Number.isFinite(width) ||
      !(width > 0) ||
      !Number.isFinite(gap)
    )
      return { points, measures, map: identity };
    const first = measures[0];
    const last = measures[measures.length - 1];
    const boundaries = [];
    for (let index = 1; index < profile.length; index += 1) {
      if (profile[index].from + width > first && profile[index].from - width < last)
        boundaries.push(index);
    }
    let start = 0;
    let overlap = 1;
    for (let end = 0; end < boundaries.length; end += 1) {
      while (
        profile[boundaries[end]].from - profile[boundaries[start]].from > 2 * width
      )
        start += 1;
      overlap = Math.max(overlap, end - start + 1);
    }
    const tolerance = STROKE_SIMPLIFY_TOLERANCE_PX / overlap;
    const samples = [];
    for (const index of boundaries) {
      const delta = Math.abs((profile[index].lane - profile[index - 1].lane) * gap);
      if (!(delta > 0) || !Number.isFinite(delta)) continue;
      const subdivisions = Math.max(2, Math.ceil(Math.sqrt(delta / (8 * tolerance))));
      for (let step = -subdivisions; step <= subdivisions; step += 1) {
        const measure = profile[index].from + (width * step) / subdivisions;
        if (measure > first && measure < last) samples.push(measure);
      }
    }
    if (!samples.length) return { points, measures, map: identity };
    samples.sort((a, b) => a - b);
    const out = [];
    const outMeasures = [];
    const map = [];
    let cursor = 0;
    for (let index = 0; index < points.length; index += 1) {
      if (index > 0) {
        const lo = measures[index - 1];
        const hi = measures[index];
        while (cursor < samples.length && samples[cursor] < hi) {
          const measure = samples[cursor];
          cursor += 1;
          if (!(measure > lo) || !(measure > (outMeasures[outMeasures.length - 1] ?? -Infinity)))
            continue;
          const fraction = (measure - lo) / (hi - lo);
          const a = points[index - 1];
          const b = points[index];
          out.push([
            a[0] + (b[0] - a[0]) * fraction,
            a[1] + (b[1] - a[1]) * fraction,
          ]);
          outMeasures.push(measure);
        }
      }
      map.push(out.length);
      out.push(points[index]);
      outMeasures.push(measures[index]);
    }
    return { points: out, measures: outMeasures, map };
  }

  // The lane a part holds at its own two ends, which is what a neighbouring
  // part needs for its `Join`. Read off the part's own rows so both sides of
  // a joint compute it the same way from the same package.
  function terminalLanes(rows, total) {
    const profile = laneProfile(rows, total);
    if (!profile.length) return { start: 0, end: 0 };
    return { start: profile[0].lane, end: profile[profile.length - 1].lane };
  }

  // ── the stroke ───────────────────────────────────────────────────────────
  // `points` are `[x, y]` in pixel space. `anchors` lists the indices of
  // vertices that are station platforms. Returns
  //   { points: [[x, y]], anchors: [[x, y]] }
  // where `anchors[i]` is the offset position of `points[anchors[i]]`.
  function dedupe(points, measures, anchors) {
    const kept = [];
    const keptMeasures = [];
    const map = new Array(points.length);
    for (let index = 0; index < points.length; index += 1) {
      const point = points[index];
      const previous = kept[kept.length - 1];
      if (
        previous &&
        Math.abs(previous[0] - point[0]) <= DEGENERATE_EDGE_PX &&
        Math.abs(previous[1] - point[1]) <= DEGENERATE_EDGE_PX
      ) {
        map[index] = kept.length - 1;
        continue;
      }
      map[index] = kept.length;
      kept.push([point[0], point[1]]);
      keptMeasures.push(measures[index]);
    }
    const anchorSet = new Set();
    for (const index of anchors || [])
      if (index >= 0 && index < points.length) anchorSet.add(map[index]);
    return { points: kept, measures: keptMeasures, anchorMap: map, anchorSet };
  }

  function cumulativeLengths(points) {
    const out = new Array(points.length);
    out[0] = 0;
    for (let index = 1; index < points.length; index += 1)
      out[index] =
        out[index - 1] +
        Math.hypot(points[index][0] - points[index - 1][0], points[index][1] - points[index - 1][1]);
    return out;
  }

  function smoothstep(t) {
    const u = t <= 0 ? 0 : t >= 1 ? 1 : t;
    return u * u * (3 - 2 * u);
  }

  // Signed turn at an interior vertex, radians, positive anticlockwise in
  // the y-down space (which is clockwise on the screen — the sign only has
  // to be consistent between the two bends of a jog).
  function turnAt(points, index) {
    const a = points[index - 1];
    const b = points[index];
    const c = points[index + 1];
    const ax = b[0] - a[0];
    const ay = b[1] - a[1];
    const bx = c[0] - b[0];
    const by = c[1] - b[1];
    return Math.atan2(ax * by - ay * bx, ax * bx + ay * by);
  }

  // The point at measure `s` along a polyline, or beyond its ends along the
  // end edge's own direction — the incoming alignment continued straight.
  function pointAlong(points, cumulative, s, low, high) {
    if (s <= cumulative[low]) {
      const a = points[low];
      const b = points[low + 1];
      const length = cumulative[low + 1] - cumulative[low] || 1;
      const t = (s - cumulative[low]) / length;
      return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
    }
    if (s >= cumulative[high]) {
      const a = points[high - 1];
      const b = points[high];
      const length = cumulative[high] - cumulative[high - 1] || 1;
      const t = (s - cumulative[high]) / length;
      return [b[0] + (b[0] - a[0]) * t, b[1] + (b[1] - a[1]) * t];
    }
    let index = low + 1;
    while (index < high && cumulative[index] < s) index += 1;
    const a = points[index - 1];
    const b = points[index];
    const length = cumulative[index] - cumulative[index - 1] || 1;
    const t = (s - cumulative[index - 1]) / length;
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
  }

  // Draw the follower from its canonical alignments over its follow
  // stretches. Returns the new polyline and, for each ORIGINAL vertex that
  // survives, its new index (-1 where it did not).
  // Measures are METRES along the line — the ruler the rows were measured
  // with — never pixels scaled by one global factor: a transcontinental
  // part crosses ten per cent of Mercator scale between its ends, and a
  // metre-to-pixel ratio taken over the whole of it puts a measure kilometres
  // from where it belongs.
  function substituteFollows(points, measures, anchorSet, follows, jointStart, jointEnd) {
    const count = points.length;
    const identity = { points, measures, map: points.map((_, index) => index) };
    if (!follows?.length || count < 2) return identity;
    const cumulative = measures;
    const first = cumulative[0];
    const total = cumulative[count - 1];
    const blend = FOLLOW_BLEND_METRES;
    // Where this part's end is a JOINT — the vertex it shares with the next
    // part of the same line — no follow may weigh on it. See the
    // FOLLOW_BLEND_METRES note.
    const weightFloor = jointStart ? first + blend : -Infinity;
    const weightCeiling = jointEnd ? total - blend : Infinity;
    // A follower is drawn from the canonical's own stroke, not its raw
    // survey: a seam jog on the canonical is tapered on the canonical's own
    // pass, and every follower must draw from that tapered shape, or the jog
    // reappears untapered on each of them. Cached per distinct canonical
    // array so N follows onto one canonical taper it once.
    const taperedCanonicals = new Map();
    const taperCanonical = (canon, canonCumulative) => {
      if (taperedCanonicals.has(canon)) return taperedCanonicals.get(canon);
      const canonPxTotal = cumulativeLengths(canon)[canon.length - 1];
      const canonMetresTotal = canonCumulative[canonCumulative.length - 1] - canonCumulative[0];
      const metresPerPx =
        canonPxTotal > 0 && canonMetresTotal > 0 ? canonMetresTotal / canonPxTotal : 0;
      const tapered = taperJogs(canon, canonCumulative, new Set(), metresPerPx);
      const result = { points: tapered.points, measures: tapered.measures };
      taperedCanonicals.set(canon, result);
      return result;
    };
    // Each follow with the canonical's own metre measures; an unusable
    // follow is dropped.
    const prepared = [];
    for (const follow of follows) {
      const rawCanon = follow.points;
      if (!Array.isArray(rawCanon) || rawCanon.length < 2) continue;
      if (!(follow.to > follow.from)) continue;
      const rawCanonCumulative =
        Array.isArray(follow.measures) && follow.measures.length === rawCanon.length
          ? follow.measures
          : null;
      if (!rawCanonCumulative) continue;
      const rawCanonTotal = rawCanonCumulative[rawCanonCumulative.length - 1];
      if (!(rawCanonTotal > 0)) continue;
      // The stretch the follow WEIGHS over, held back from a joint. The
      // correspondence below (`from`/`to` against `canonFrom`/`canonTo`) keeps
      // its reviewed bounds: holding the weight back moves where the
      // substitution applies, never which canonical measure a vertex maps to.
      const weightFrom = Math.max(follow.from, weightFloor);
      const weightTo = Math.min(follow.to, weightCeiling);
      if (!(weightTo > weightFrom)) continue;
      const { points: canon, measures: canonCumulative } = taperCanonical(rawCanon, rawCanonCumulative);
      const canonTotal = canonCumulative[canonCumulative.length - 1];
      prepared.push({
        from: follow.from,
        to: follow.to,
        weightFrom,
        weightTo,
        canonFrom: follow.canonFrom,
        canonTo: follow.canonTo,
        canon,
        canonCumulative,
        canonTotalPx: canonTotal,
      });
    }
    if (!prepared.length) return identity;
    prepared.forEach((follow, index) => {
      follow.order = index;
    });
    prepared.sort((a, b) => a.from - b.from || a.order - b.order);
    // The weight of every canonical alignment at a measure: the
    // kernel-smoothed indicator of each stretch. Where two stretches meet —
    // one canonical part handing over to the next — both are partly
    // weighted, and the stroke cross-fades between the two alignments
    // instead of jumping from one to the other; the weights are normalised
    // so the own alignment never gets a negative share.
    // A follow that begins at the part's own start (or ends at its end) is
    // whole from that end: the kernel would otherwise weight the terminal
    // vertex by half and leave the platform bead between two alignments. A
    // JOINT is the exception, and holding the weight back one blend width is
    // what makes it one: the held-back bound can no longer reach either test,
    // so the kernel runs a full ramp from zero AT the shared vertex.
    const weightsAt = (s) => {
      const held = [];
      let sum = 0;
      for (const follow of prepared) {
        const rise =
          follow.weightFrom <= first + DEGENERATE_EDGE_PX
            ? 1
            : kernelCumulative(s - follow.weightFrom, blend);
        const fall =
          follow.weightTo >= total - DEGENERATE_EDGE_PX
            ? 0
            : kernelCumulative(s - follow.weightTo, blend);
        const w = rise - fall;
        if (w > 0) {
          held.push({ w, follow });
          sum += w;
        }
      }
      if (sum > 1) for (const entry of held) entry.w /= sum;
      return held;
    };
    const canonPoint = (follow, s) => {
      const span = follow.to - follow.from;
      const t = span > 0 ? (s - follow.from) / span : 0;
      const sc = follow.canonFrom + (follow.canonTo - follow.canonFrom) * t;
      const clamped = Math.max(0, Math.min(follow.canonTotalPx, sc));
      return pointAlong(follow.canon, follow.canonCumulative, clamped, 0, follow.canon.length - 1);
    };
    // Sample measures: every own vertex, plus every canonical vertex that
    // maps inside a stretch, so the corridor's shape survives.
    const extra = [];
    for (const follow of prepared) {
      const low = Math.min(follow.canonFrom, follow.canonTo);
      const high = Math.max(follow.canonFrom, follow.canonTo);
      const span = follow.canonTo - follow.canonFrom;
      if (!span) continue;
      for (let index = 0; index < follow.canon.length; index += 1) {
        const sc = follow.canonCumulative[index];
        if (sc <= low || sc >= high) continue;
        const s = follow.from + ((sc - follow.canonFrom) / span) * (follow.to - follow.from);
        if (s > 0 && s < total) extra.push(s);
      }
    }
    extra.sort((a, b) => a - b);
    const out = [];
    const outMeasures = [];
    const map = new Array(count).fill(-1);
    let extraAt = 0;
    const emit = (s, own, index) => {
      const held = weightsAt(s);
      if (!held.length) {
        if (own) {
          map[index] = out.length;
          out.push(own);
          outMeasures.push(s);
        }
        return;
      }
      const base = own || pointAlong(points, cumulative, s, 0, count - 1);
      let x = base[0];
      let y = base[1];
      for (const entry of held) {
        const target = canonPoint(entry.follow, s);
        x += (target[0] - base[0]) * entry.w;
        y += (target[1] - base[1]) * entry.w;
      }
      if (own) map[index] = out.length;
      out.push([x, y]);
      outMeasures.push(s);
    };
    for (let index = 0; index < count; index += 1) {
      const s = cumulative[index];
      while (extraAt < extra.length && extra[extraAt] < s - DEGENERATE_EDGE_PX) {
        emit(extra[extraAt], null, -1);
        extraAt += 1;
      }
      while (extraAt < extra.length && extra[extraAt] <= s + DEGENERATE_EDGE_PX) extraAt += 1;
      emit(s, points[index], index);
    }
    return { points: out, measures: outMeasures, map };
  }

  // Redraw every seam jog as a taper. Returns the new polyline and, for
  // each ORIGINAL vertex that survives, its new index (-1 where it did not).
  function taperJogs(points, measures, anchorSet, metresPerPx) {
    const count = points.length;
    const identity = { points, measures, map: points.map((_, index) => index) };
    if (count < 4 || !(metresPerPx > 0)) return identity;
    const toPx = 1 / metresPerPx;
    const minTurn = (JOG_MIN_TURN_DEGREES * Math.PI) / 180;
    const maxTurn = (JOG_MAX_TURN_DEGREES * Math.PI) / 180;
    const maxNet = (JOG_MAX_NET_TURN_DEGREES * Math.PI) / 180;
    const maxRun = JOG_MAX_RUN_METRES * toPx;
    const minLateral = JOG_MIN_LATERAL_METRES * toPx;
    const taper = JOG_TAPER_METRES * toPx;
    const minTaper = JOG_MIN_TAPER_METRES * toPx;
    const cumulative = cumulativeLengths(points);
    const turns = new Array(count).fill(0);
    for (let index = 1; index + 1 < count; index += 1) turns[index] = turnAt(points, index);
    const anchorsSorted = [...anchorSet].sort((a, b) => a - b);
    const windows = [];
    let lastEnd = 0;
    for (let i = 1; i + 1 < count; i += 1) {
      const first = turns[i];
      if (Math.abs(first) < minTurn || Math.abs(first) > maxTurn) continue;
      let found = null;
      let net = first;
      for (let j = i + 1; j + 1 < count; j += 1) {
        if (cumulative[j] - cumulative[i] > maxRun) break;
        const second = turns[j];
        net += second;
        if (
          Math.abs(second) >= minTurn &&
          Math.abs(second) <= maxTurn &&
          Math.sign(second) !== Math.sign(first)
        ) {
          if (Math.abs(net) <= maxNet) found = j;
          break;
        }
        if (Math.abs(second) >= minTurn) break;
      }
      if (found == null) continue;
      const j = found;
      // Lateral shift: how far the far bend sits off the incoming line.
      const a0 = points[i - 1];
      const a1 = points[i];
      const ex = a1[0] - a0[0];
      const ey = a1[1] - a0[1];
      const el = Math.hypot(ex, ey) || 1;
      const px = points[j][0] - a1[0];
      const py = points[j][1] - a1[1];
      const lateral = Math.abs(ex * py - ey * px) / el;
      if (lateral < minLateral) continue;
      // No platform inside the jog itself.
      if (anchorsSorted.some((index) => index >= i && index <= j)) continue;
      // The taper window, held back by the nearest platform on each side and
      // by the previous window.
      let a = i - 1;
      while (a > lastEnd && cumulative[i] - cumulative[a - 1] <= taper) a -= 1;
      // Never back over the previous window: two seams a few hundred metres
      // apart each get their own taper, meeting at the vertex between them.
      if (a < lastEnd) a = lastEnd;
      const anchorBefore = anchorsSorted.filter((index) => index < i).pop();
      if (anchorBefore != null && anchorBefore > a) a = anchorBefore;
      let b = j + 1;
      while (b + 1 < count && cumulative[b + 1] - cumulative[j] <= taper) b += 1;
      const anchorAfter = anchorsSorted.find((index) => index > j);
      if (anchorAfter != null && anchorAfter < b) b = anchorAfter;
      if (cumulative[i] - cumulative[a] < minTaper || cumulative[b] - cumulative[j] < minTaper)
        continue;
      windows.push({ a, b, i, j });
      lastEnd = b;
      i = b - 1;
    }
    if (!windows.length) return identity;
    const out = [];
    const outMeasures = [];
    const map = new Array(count).fill(-1);
    let cursor = 0;
    for (const window of windows) {
      for (let index = cursor; index <= window.a; index += 1) {
        map[index] = out.length;
        out.push(points[index]);
        outMeasures.push(measures[index]);
      }
      const measureStart = measures[window.a];
      const measureEnd = measures[window.b];
      const start = cumulative[window.a];
      const end = cumulative[window.b];
      const span = end - start;
      const sampleMeasures = new Set();
      for (let index = window.a + 1; index < window.b; index += 1)
        sampleMeasures.add(cumulative[index]);
      for (let sample = 1; sample < JOG_TAPER_SAMPLES; sample += 1)
        sampleMeasures.add(start + (span * sample) / JOG_TAPER_SAMPLES);
      const ordered = [...sampleMeasures].filter((s) => s > start && s < end).sort((x, y) => x - y);
      for (const s of ordered) {
        const w = smoothstep((s - start) / span);
        const from = pointAlong(points, cumulative, s, window.a, window.i);
        const to = pointAlong(points, cumulative, s, window.j, window.b);
        out.push([from[0] + (to[0] - from[0]) * w, from[1] + (to[1] - from[1]) * w]);
        outMeasures.push(measureStart + (measureEnd - measureStart) * ((s - start) / span));
      }
      cursor = window.b;
    }
    for (let index = cursor; index < count; index += 1) {
      map[index] = out.length;
      out.push(points[index]);
      outMeasures.push(measures[index]);
    }
    return { points: out, measures: outMeasures, map };
  }

  // Offset every vertex along its bisector normal by its own lane distance.
  // The normal is the right-hand one of the digitised direction in a y-down
  // space, which is the side MapLibre's positive `line-offset` and the iOS
  // renderer's (-dy, dx) both mean by "positive lane".
  //
  // `joinStart` / `joinEnd` supply the MISSING tangent at a terminal vertex a
  // part shares with the neighbouring part of the same line: the pair
  // (incoming, outgoing) at that vertex, computed from the two parts' raw
  // pixels so both of them derive the same pair. With it the terminal vertex
  // is mitred like an interior one instead of taking the one-sided normal, and
  // the neighbour — which sees the identical pair — lands on the identical
  // point. Without it (no neighbour) the one-sided normal is used, as before.
  function offsetPolyline(points, distanceAt, joinStart, joinEnd, stableSegments) {
    if (stableSegments && points.length > 2)
      return offsetAlongStableSegments(points, distanceAt, joinStart, joinEnd);
    const count = points.length;
    const out = new Array(count);
    for (let index = 0; index < count; index += 1) {
      const point = points[index];
      const d = distanceAt(index);
      if (!d) {
        out[index] = [point[0], point[1]];
        continue;
      }
      let nx = 0;
      let ny = 0;
      let scale = 1;
      const join = index === 0 ? joinStart : index === count - 1 ? joinEnd : null;
      const before = index > 0 ? points[index - 1] : null;
      const after = index + 1 < count ? points[index + 1] : null;
      let t0 = null;
      let t1 = null;
      if (join) {
        // Both tangents from the joint, so the neighbouring part — which
        // computes the same pair — offsets this vertex to the same place.
        t0 = [join.incoming[0], join.incoming[1]];
        t1 = [join.outgoing[0], join.outgoing[1]];
      } else {
        if (before) {
          const dx = point[0] - before[0];
          const dy = point[1] - before[1];
          const length = Math.hypot(dx, dy) || 1;
          t0 = [dx / length, dy / length];
        }
        if (after) {
          const dx = after[0] - point[0];
          const dy = after[1] - point[1];
          const length = Math.hypot(dx, dy) || 1;
          t1 = [dx / length, dy / length];
        }
      }
      if (t0 && t1) {
        const tangentDot = Math.max(-1, Math.min(1, t0[0] * t1[0] + t0[1] * t1[1]));
        // At a shared join near a reversal the bisector mitre points far down
        // the joint and its clamp still creates an artificial terminal tip.
        // Both parts carry the same incoming tangent, so its one-sided normal
        // is also the one stable answer they can share.
        if (join && tangentDot <= Math.cos((150 * Math.PI) / 180)) {
          nx = -t0[1];
          ny = t0[0];
          out[index] = [point[0] + nx * d, point[1] + ny * d];
          continue;
        }
        // Bisector of the two right-hand normals, scaled so the offset edge
        // stays parallel to both edges (a mitre), clamped at the limit.
        const bx = -t0[1] - t1[1];
        const by = t0[0] + t1[0];
        const length = Math.hypot(bx, by);
        if (length > 1e-9) {
          nx = bx / length;
          ny = by / length;
          // cos(θ/2) where θ is the turn: half the bisector's length.
          const cosHalf = Math.max(1e-6, length / 2);
          scale = Math.min(MITER_LIMIT, 1 / cosHalf);
        } else {
          // Exact reversal: no bisector. Use the incoming normal.
          nx = -t0[1];
          ny = t0[0];
        }
      } else {
        const t = t0 || t1 || [1, 0];
        nx = -t[1];
        ny = t[0];
      }
      out[index] = [point[0] + nx * d * scale, point[1] + ny * d * scale];
    }
    return out;
  }

  // Follow substitution and lane-ramp sampling can place a straight-edge
  // sample immediately beside a genuine bend. Giving that sample its own
  // perpendicular normal makes the bend's mitre overshoot it; fold cleanup
  // then deletes both vertices and can erase an entire surveyed curve.
  // Derive offset directions from significant alignment vertices and
  // interpolate their mitre vectors along each edge. Every input coordinate,
  // measure, anchor and ramp sample is still emitted; only tangent support is
  // simplified, within the existing sub-pixel budget.
  function offsetAlongStableSegments(points, distanceAt, joinStart, joinEnd) {
    const keep = new Array(points.length).fill(false);
    keep[0] = true;
    keep[points.length - 1] = true;
    simplifySpan(
      points,
      0,
      points.length - 1,
      STROKE_SIMPLIFY_TOLERANCE_PX * STROKE_SIMPLIFY_TOLERANCE_PX,
      keep,
    );
    const support = points.map((_, index) => index).filter((index) => keep[index]);
    const skeleton = support.map((index) => points[index]);
    const lengths = cumulativeLengths(points);
    const distances = constrainedInnerBendDistances(
      points,
      support,
      lengths,
      points.map((_, index) => distanceAt(index)),
      !!joinStart,
      !!joinEnd,
    );
    const displaced = offsetPolyline(skeleton, () => 1, joinStart, joinEnd, false);
    const vertices = offsetPolyline(
      skeleton,
      (index) => distances[support[index]],
      joinStart,
      joinEnd,
      false,
    );
    const vectors = displaced.map((point, index) => [
      point[0] - skeleton[index][0],
      point[1] - skeleton[index][1],
    ]);
    let edge = 0;
    return points.map((point, index) => {
      while (edge + 1 < support.length - 1 && index > support[edge + 1]) edge += 1;
      const spanStart = support[edge];
      const spanEnd = support[edge + 1];
      // Preserve shared terminal joins bit-for-bit; rebuilding them from a
      // unit vector would add a rounding step.
      if (index === spanStart) return vertices[edge];
      if (index === spanEnd) return vertices[edge + 1];
      const length = lengths[spanEnd] - lengths[spanStart];
      const t = length > 0 ? (lengths[index] - lengths[spanStart]) / length : 0;
      const a = vectors[edge];
      const b = vectors[edge + 1];
      const distance = distances[index];
      return [
        point[0] + (a[0] + (b[0] - a[0]) * t) * distance,
        point[1] + (a[1] + (b[1] - a[1]) * t) * distance,
      ];
    });
  }

  // Inside tightly sampled bends, a full-width offset can pass through the
  // opposite leg. Bound its mitre's tangent trim by the available surveyed
  // edges, then taper the constraint along both approaches. The soft bound
  // remains monotonic in lane distance, so inner lanes retain their order.
  function constrainedInnerBendDistances(points, support, lengths, distances, preserveStart, preserveEnd) {
    if (support.length <= 2) return distances;
    const skeleton = support.map((index) => points[index]);
    const positive = new Array(points.length).fill(Infinity);
    const negative = new Array(points.length).fill(Infinity);
    // Match the native compound-bend constraint: recover one offset pixel
    // per twenty source pixels so the taper cannot cross a return approach.
    const maximumRecovery = 0.05;
    const recovery = new Array(points.length).fill(maximumRecovery);
    let constrained = false;
    for (let index = 1; index + 1 < support.length; index += 1) {
      const turn = turnAt(skeleton, index);
      // Several moderate turns can form a tight reversal together; checking
      // only individual hairpin apices misses that overlap.
      if (!(Math.abs(turn) > 1e-6)) continue;
      const a = skeleton[index - 1];
      const b = skeleton[index];
      const c = skeleton[index + 1];
      const available = Math.min(
        Math.hypot(b[0] - a[0], b[1] - a[1]),
        Math.hypot(c[0] - b[0], c[1] - b[1]),
      );
      const cap = Math.max(0, (0.45 * available) / Math.tan(Math.abs(turn) / 2));
      (turn > 0 ? positive : negative)[support[index]] = cap;
      // A near-reversal's legs open slowly. Restoring the full offset faster
      // than that opening crosses the opposite leg even with a bounded apex.
      const rate = Math.min(maximumRecovery, 0.5 / Math.tan(Math.abs(turn) / 2));
      if (rate < maximumRecovery) {
        for (let edge = support[index - 1] + 1; edge <= support[index + 1]; edge += 1)
          recovery[edge] = Math.min(recovery[edge], rate);
      }
      constrained = true;
    }
    if (!constrained) return distances;
    const spread = (caps) => {
      for (let index = 1; index < caps.length; index += 1)
        caps[index] = Math.min(
          caps[index],
          caps[index - 1] + (lengths[index] - lengths[index - 1]) * recovery[index],
        );
      for (let index = caps.length - 2; index >= 0; index -= 1)
        caps[index] = Math.min(
          caps[index],
          caps[index + 1] +
            (lengths[index + 1] - lengths[index]) * recovery[index + 1],
        );
    };
    spread(positive);
    spread(negative);
    return distances.map((distance, index) => {
      if ((index === 0 && preserveStart) || (index + 1 === distances.length && preserveEnd)) return distance;
      const magnitude = Math.abs(distance);
      const cap = distance > 0 ? positive[index] : negative[index];
      if (!(magnitude > cap * 0.95)) return distance;
      const margin = cap * 0.05;
      const limited = cap - (margin * margin) / (magnitude - cap * 0.9);
      return distance < 0 ? -limited : limited;
    });
  }

  // An offset polyline folds back on itself wherever the offset is larger
  // than the local radius of the bend — at a regional zoom, where the
  // surveyed vertices sit a fraction of a pixel apart, a two-pixel lane
  // offset does that at every tight curve, and the fold draws as a spike.
  // A fold is a vertex the offset turned into a reversal that the surveyed
  // line did not have; those are dropped, in passes, until none remain.
  // A reversal the survey DOES have (a switchback) is kept. A platform's
  // vertex may go — its bead is placed from the offset before this pass, so
  // the dot still lands where its vertex was — which is what keeps a fold at
  // a platform from surviving as a spike. Returns the new polyline and each
  // old index's new index.
  const FOLD_TURN_DEGREES = 150;

  function removeOffsetFolds(offset, original, preserveBends, anchors) {
    const count = offset.length;
    // A surveyed hairpin can distribute its reversal across several vertices
    // (Hakone's apex is 133 degrees). Protect such acute source bends before
    // neighbouring offset folds can consume the apex.
    const foldTurn = ((preserveBends ? 120 : FOLD_TURN_DEGREES) * Math.PI) / 180;
    const reversal = new Array(count).fill(false);
    for (let index = 1; index + 1 < count; index += 1)
      reversal[index] = Math.abs(turnAt(original, index)) > foldTurn;
    if (preserveBends) {
      for (const index of anchors || []) if (index >= 0 && index < count) reversal[index] = true;
      return removeOffsetFoldsSequentially(offset, original, reversal);
    }
    return removeFolds(offset, reversal);
  }

  // Nearby real bends can overlap on the inside of a lane even with stable
  // tangents. Remove the weaker surveyed turn first, then re-evaluate its
  // neighbours so the dominant bend survives. Linked indices make deletion
  // and neighbour updates constant-time. Anchors and reversals are protected.
  function removeOffsetFoldsSequentially(points, original, protectedVertices) {
    const count = points.length;
    if (count < 3) return { points, map: points.map((_, index) => index) };
    const threshold = (FOLD_TURN_DEGREES * Math.PI) / 180;
    const previous = points.map((_, index) => index - 1);
    const next = points.map((_, index) => (index + 1 < count ? index + 1 : -1));
    const alive = new Array(count).fill(true);
    const importance = points.map((_, index) =>
      index > 0 && index + 1 < count ? Math.abs(turnAt(original, index)) : 0,
    );
    const folded = (index) => {
      if (
        !(index > 0 && index + 1 < count) ||
        !alive[index] ||
        protectedVertices[index]
      )
        return false;
      const a = points[previous[index]];
      const b = points[index];
      const c = points[next[index]];
      const ax = b[0] - a[0];
      const ay = b[1] - a[1];
      const bx = c[0] - b[0];
      const by = c[1] - b[1];
      return Math.abs(Math.atan2(ax * by - ay * bx, ax * bx + ay * by)) > threshold;
    };
    const pending = Array.from({ length: count - 2 }, (_, index) => index + 1);
    let cursor = 0;
    while (cursor < pending.length) {
      const index = pending[cursor];
      cursor += 1;
      if (!folded(index)) continue;
      let victim = index;
      for (const neighbour of [previous[index], next[index]]) {
        if (folded(neighbour) && importance[neighbour] < importance[victim]) victim = neighbour;
      }
      const before = previous[victim];
      const after = next[victim];
      alive[victim] = false;
      next[before] = after;
      previous[after] = before;
      pending.push(before, after);
    }
    const kept = [];
    const map = new Array(count).fill(-1);
    for (let index = 0; index < count; index += 1) {
      if (!alive[index]) continue;
      map[index] = kept.length;
      kept.push(points[index]);
    }
    return { points: kept, map };
  }

  // The same pass over a polyline whose surveyed reversals are already
  // known per vertex — a corridor substitution's output, where every own
  // vertex carries the survey's verdict and every inserted one carries none.
  function removeFolds(offset, reversal) {
    const count = offset.length;
    const foldTurn = (FOLD_TURN_DEGREES * Math.PI) / 180;
    let kept = offset.map((_, index) => index);
    for (let pass = 0; pass < 8; pass += 1) {
      const next = [];
      let dropped = 0;
      for (let at = 0; at < kept.length; at += 1) {
        const index = kept[at];
        if (at > 0 && at + 1 < kept.length && !reversal[index]) {
          const a = offset[kept[at - 1]];
          const b = offset[index];
          const c = offset[kept[at + 1]];
          const ax = b[0] - a[0];
          const ay = b[1] - a[1];
          const bx = c[0] - b[0];
          const by = c[1] - b[1];
          if (Math.abs(Math.atan2(ax * by - ay * bx, ax * bx + ay * by)) > foldTurn) {
            dropped += 1;
            continue;
          }
        }
        next.push(index);
      }
      kept = next;
      if (!dropped) break;
    }
    const map = new Array(count).fill(-1);
    kept.forEach((index, at) => {
      map[index] = at;
    });
    return { points: kept.map((index) => offset[index]), map };
  }

  // Round every interior corner that is neither a station anchor nor a
  // reversal. Each rounded corner becomes a quadratic curve tangent to both
  // edges; the tangent length is the circular fillet's, capped by the edges.
  // `measures` (aligned with `points`) is carried along: the tangent start
  // and end get the measure that far from the vertex's own measure, along
  // each edge, and every interior curve sample is the linear interpolation
  // between those two in the curve parameter `u`.
  //
  // A CORNER IS A RUN, NOT ALWAYS A VERTEX. `radius` is what the corner is
  // rounded to when the two edges can carry it; `floor` is what it is rounded
  // to at worst. Where consecutive vertices sit closer together than the pen
  // is wide — a welded survey duplicate, a real curve sampled every 20 m and
  // drawn at a regional zoom — no single one of them has an edge long enough
  // to carry even the floor, and rounding each in isolation draws the bare
  // kink this file exists to remove. So the run is rounded AS ONE CORNER:
  // the arc is tangent to the edge arriving at the run and to the edge
  // leaving it, about their intersection, and the run's own vertices are
  // replaced by it.
  //
  // The merge is deliberately narrow, because a corner cut across real
  // geometry is worse than a kink:
  //   * a station anchor is never inside a run and never moves — it is a
  //     platform, and its bead is placed on it;
  //   * a surveyed reversal (turn > FILLET_MAX_TURN_DEGREES) is never inside
  //     a run and stays exactly as surveyed — a switchback is not a corner;
  //   * a run grows toward the RADIUS it is promising, not the floor it
  //     would settle for — it keeps absorbing edges only while a longer run
  //     could still carry more of `radius` (bounded, as any single-vertex
  //     corner is, by FILLET_MAX_TANGENT_SHARE of the run's own outer
  //     edges), so it may span at most `radius` of arc length;
  //   * and the arc is rejected outright unless every vertex it replaces
  //     ends up within `floor` of it. Nothing moves further than the radius
  //     the corner is being given.
  // With `floor` 0 no run is ever formed and every corner is exactly the
  // single-vertex fillet this function has always drawn.
  function filletPolyline(points, radius, floorRadius, anchorSet, measures, enforceMinimumRadius) {
    if (enforceMinimumRadius) radius = Math.max(radius, floorRadius);
    const count = points.length;
    if (!(radius > 0) || count < 3) return { points, measures };
    const minTurn = (FILLET_MIN_TURN_DEGREES * Math.PI) / 180;
    const maxTurn = (FILLET_MAX_TURN_DEGREES * Math.PI) / 180;
    const step = (FILLET_STEP_DEGREES * Math.PI) / 180;
    const floor = floorRadius > 0 ? Math.min(floorRadius, radius) : 0;
    // Which interior vertices may not be swallowed by a run, and how sharply
    // each one turns.
    const turns = new Array(count).fill(0);
    const hard = new Array(count).fill(false);
    for (let index = 1; index + 1 < count; index += 1) {
      const ax = points[index][0] - points[index - 1][0];
      const ay = points[index][1] - points[index - 1][1];
      const bx = points[index + 1][0] - points[index][0];
      const by = points[index + 1][1] - points[index][1];
      const la = Math.hypot(ax, ay);
      const lb = Math.hypot(bx, by);
      if (la <= DEGENERATE_EDGE_PX || lb <= DEGENERATE_EDGE_PX) {
        hard[index] = true;
        continue;
      }
      const dot = Math.max(-1, Math.min(1, (ax * bx + ay * by) / (la * lb)));
      turns[index] = Math.acos(dot);
      if (turns[index] > maxTurn) hard[index] = true;
    }
    for (const index of anchorSet)
      if (index > 0 && index + 1 < count) hard[index] = true;
    const cumulative = cumulativeLengths(points);
    const out = [points[0]];
    const outMeasures = [measures[0]];
    // Every vertex this function emits goes through here, and an emission
    // that repeats the previous one EXACTLY is dropped.
    //
    // Corners are cut apart, not glued: the guard clamp above can shorten a
    // corner's tangent to exactly `back - guardOffset`, which puts its
    // `start` on the identical coordinate the previous corner's `end`
    // already occupies. That is a harmless coincidence — the line is
    // unchanged either way — but it is a zero-length edge, which is the one
    // thing `everyStrokeIsWellFormed` refuses. Only bit-equal points are
    // dropped, never merely near ones: a "close enough" test is a
    // simplification, and this pass is the one place the stroke must not be
    // simplified (see STROKE_SIMPLIFY_TOLERANCE_PX).
    const emit = (point, measure) => {
      const last = out[out.length - 1];
      if (last[0] === point[0] && last[1] === point[1]) return;
      out.push(point);
      outMeasures.push(measure);
    };
    // Where the previous corner left the polyline: the edge it ended on (by
    // its start vertex) and how far along that edge. A corner never starts
    // before it, so two corners can never cross however the runs fell.
    let guardEdge = -1;
    let guardOffset = 0;
    // The corner made of the run `first…last`, or null when that run cannot
    // be rounded at all.
    const cornerOf = (first, last) => {
      const before = points[first - 1];
      const after = points[last + 1];
      const ax = points[first][0] - before[0];
      const ay = points[first][1] - before[1];
      const la = Math.hypot(ax, ay);
      if (la <= DEGENERATE_EDGE_PX) return null;
      const t0x = ax / la;
      const t0y = ay / la;
      const bx = after[0] - points[last][0];
      const by = after[1] - points[last][1];
      const lb = Math.hypot(bx, by);
      if (lb <= DEGENERATE_EDGE_PX) return null;
      const t1x = bx / lb;
      const t1y = by / lb;
      const dot = Math.max(-1, Math.min(1, t0x * t1x + t0y * t1y));
      const turn = Math.acos(dot);
      if (turn < minTurn || turn > maxTurn) return null;
      // The corner's apex: where the two tangent lines meet, given as its
      // offset from the run's first vertex along the incoming tangent and
      // from its last along the outgoing one. For a run of one both are
      // exactly zero and the apex is the vertex itself, so a single corner
      // stays bit-for-bit the fillet this function has always drawn.
      let apex = points[first];
      let apexBack = 0;
      let apexForward = 0;
      if (last > first) {
        const cross = t0x * t1y - t0y * t1x;
        if (!(Math.abs(cross) > DEGENERATE_EDGE_PX)) return null;
        const rx = after[0] - points[first][0];
        const ry = after[1] - points[first][1];
        apexBack = (rx * t1y - ry * t1x) / cross;
        apex = [points[first][0] + t0x * apexBack, points[first][1] + t0y * apexBack];
        apexForward =
          (apex[0] - points[last][0]) * t1x + (apex[1] - points[last][1]) * t1y;
      }
      const back = la + apexBack;
      const forward = lb - apexForward;
      if (!(back > 0) || !(forward > 0)) return null;
      const half = Math.tan(turn / 2);
      let tangent = Math.min(
        radius * half,
        FILLET_MAX_TANGENT_SHARE * back,
        FILLET_MAX_TANGENT_SHARE * forward,
      );
      if (guardEdge === first - 1 && back - tangent < guardOffset)
        tangent = back - guardOffset;
      if (!(tangent > DEGENERATE_EDGE_PX)) return null;
      // A merged run's intersection can lie beyond either original outer
      // edge. Reject extrapolated starts or ends in strict geometry mode.
      if (enforceMinimumRadius) {
        const startOffset = apexBack - tangent;
        const endOffset = apexForward + tangent;
        if (startOffset < -la || startOffset > 0 || endOffset < 0 || endOffset > lb)
          return null;
      }
      const start = [apex[0] - t0x * tangent, apex[1] - t0y * tangent];
      const end = [apex[0] + t1x * tangent, apex[1] + t1y * tangent];
      // A TRUE circular arc, sampled at uniform ANGLE steps — the same
      // construction `anchorCornerOf` below already uses, and for the same
      // reason. This used to be a quadratic Bézier sampled uniformly in u,
      // and a Bézier does not rotate its tangent uniformly with u: it turns
      // slowly at the ends and fast in the middle, so the middle facet of a
      // 90-degree corner reached 14.3 degrees, of a 120-degree corner 19.7,
      // and of a 150-degree one 29.9 — two and a half times the
      // FILLET_STEP_DEGREES the sample count was chosen to honour, and
      // plainly visible as a flat spot at the apex of every wide corner.
      // The arc turns by exactly turn / samples between neighbours, so
      // FILLET_STEP_DEGREES means what it says at every deflection.
      //
      // The radius is `tangent / half` — the same number reported as
      // `achieved` — and the centre sits on the corner's bisector, one
      // radius off the incoming edge on the side the corner turns toward.
      // Solved RELATIVE to the apex, never in absolute (web-mercator, ~1e7)
      // pixel coordinates: the arc is a few pixels across, and subtracting
      // nearly-equal huge numbers to find its centre is ill conditioned.
      // The two endpoints are pushed VERBATIM, so the join with the straight
      // segments either side stays exact whatever the trigonometry rounds to.
      const arcRadius = tangent / half;
      const arcCross = t0x * t1y - t0y * t1x;
      const turnSign = arcCross >= 0 ? 1 : -1;
      const centreX = -t0x * tangent - turnSign * t0y * arcRadius;
      const centreY = -t0y * tangent + turnSign * t0x * arcRadius;
      const a0 = Math.atan2(-t0y * tangent - centreY, -t0x * tangent - centreX);
      const samples = Math.max(2, Math.ceil(turn / step));
      const curve = [start];
      for (let sample = 1; sample < samples; sample += 1) {
        const angle = a0 + turnSign * turn * (sample / samples);
        curve.push([
          apex[0] + centreX + arcRadius * Math.cos(angle),
          apex[1] + centreY + arcRadius * Math.sin(angle),
        ]);
      }
      curve.push(end);
      // Nothing a run swallows may end up further than the floor from the
      // arc that replaced it.
      if (last > first) {
        for (let index = first; index <= last; index += 1) {
          if (distanceToPolyline(points[index], curve) > floor) return null;
        }
      }
      const dStart = apexBack - tangent;
      const dEnd = apexForward + tangent;
      return {
        last,
        curve,
        achieved: tangent / half,
        endOffset: dEnd,
        mStart:
          measures[first] + (dStart * (measures[first] - measures[first - 1])) / la,
        mEnd: measures[last] + (dEnd * (measures[last + 1] - measures[last])) / lb,
      };
    };
    // A station platform's vertex must not turn sharply into its dot
    // (rules §10.9), but it also must not move: the anchor's bead is read
    // from this exact coordinate before this function ever runs (see
    // buildStroke). So a lone anchor corner is not CUT AWAY like an
    // ordinary fillet — it is replaced by a circular arc that passes
    // THROUGH the vertex: three points on one circle, the tangent points
    // T1/T2 on the incoming and outgoing edges and the vertex itself
    // between them. The tangent length reuses the ordinary corner's rule.
    // T1, vertex and T2 form an isosceles triangle (two sides the tangent
    // length, apex angle π − turn at the vertex), so the circumradius has
    // the closed form tangent / (2·sin(turn / 2)) — but the centre and the
    // sweep direction are still solved generally, the same way for every
    // turn from FILLET_MIN_TURN to FILLET_MAX_TURN.
    const anchorCornerOf = (index) => {
      const before = points[index - 1];
      const after = points[index + 1];
      const ax = points[index][0] - before[0];
      const ay = points[index][1] - before[1];
      const la = Math.hypot(ax, ay);
      if (la <= DEGENERATE_EDGE_PX) return null;
      const t0x = ax / la;
      const t0y = ay / la;
      const bx = after[0] - points[index][0];
      const by = after[1] - points[index][1];
      const lb = Math.hypot(bx, by);
      if (lb <= DEGENERATE_EDGE_PX) return null;
      const t1x = bx / lb;
      const t1y = by / lb;
      const dot = Math.max(-1, Math.min(1, t0x * t1x + t0y * t1y));
      const turn = Math.acos(dot);
      if (turn < minTurn || turn > maxTurn) return null;
      const half = Math.tan(turn / 2);
      let tangent = Math.min(
        radius * half,
        FILLET_MAX_TANGENT_SHARE * la,
        FILLET_MAX_TANGENT_SHARE * lb,
      );
      if (guardEdge === index - 1 && la - tangent < guardOffset) tangent = la - guardOffset;
      if (!(tangent > DEGENERATE_EDGE_PX)) return null;
      // tangent <= FILLET_MAX_TANGENT_SHARE * la (0.45 * la) and likewise for
      // lb by construction above, and the guardEdge clamp above only ever
      // shrinks tangent further — so la >= 2*tangent and lb >= 2*tangent
      // always hold; neither edge can be shorter than twice what the arc
      // borrows from it.
      const vertex = points[index];
      const t1Point = [vertex[0] - t0x * tangent, vertex[1] - t0y * tangent];
      const t2Point = [vertex[0] + t1x * tangent, vertex[1] + t1y * tangent];
      // Circumcircle of t1Point, vertex, t2Point, solved relative to the
      // vertex rather than in absolute (web-mercator, ~1e7) coordinates: the
      // three points are only `tangent` (a few pixels) apart, so solving in
      // absolute space subtracts nearly-equal huge numbers and is ill
      // conditioned. Translating the vertex to the origin first keeps the
      // arithmetic well behaved at any zoom or tile offset; the centre is
      // translated back to absolute space afterwards.
      const p1x = -t0x * tangent;
      const p1y = -t0y * tangent;
      const p2x = 0;
      const p2y = 0;
      const p3x = t1x * tangent;
      const p3y = t1y * tangent;
      const d = 2 * (p1x * (p2y - p3y) + p2x * (p3y - p1y) + p3x * (p1y - p2y));
      if (!(Math.abs(d) > 0)) return null;
      const sq1 = p1x * p1x + p1y * p1y;
      const sq2 = p2x * p2x + p2y * p2y;
      const sq3 = p3x * p3x + p3y * p3y;
      const cxRel = (sq1 * (p2y - p3y) + sq2 * (p3y - p1y) + sq3 * (p1y - p2y)) / d;
      const cyRel = (sq1 * (p3x - p2x) + sq2 * (p1x - p3x) + sq3 * (p2x - p1x)) / d;
      const cx = vertex[0] + cxRel;
      const cy = vertex[1] + cyRel;
      const arcRadius = Math.hypot(p2x - cxRel, p2y - cyRel);
      const a1 = Math.atan2(p1y - cyRel, p1x - cxRel);
      const aV = Math.atan2(p2y - cyRel, p2x - cxRel);
      const a2 = Math.atan2(p3y - cyRel, p3x - cxRel);
      const angleDiff = (from, to) => {
        let delta = to - from;
        while (delta <= -Math.PI) delta += 2 * Math.PI;
        while (delta > Math.PI) delta -= 2 * Math.PI;
        return delta;
      };
      const short = angleDiff(a1, a2);
      const toApex = angleDiff(a1, aV);
      const sameSign = (short >= 0 && toApex >= 0) || (short <= 0 && toApex <= 0);
      const sweep =
        sameSign && Math.abs(toApex) <= Math.abs(short)
          ? short
          : short - Math.sign(short || 1) * 2 * Math.PI;
      // An anchor arc always uses an EVEN sample count, so the forced apex
      // sample below lands at index samples/2 exactly — the true analytic
      // midpoint (u = 0.5) of the arc (V is equidistant from T1 and T2 along
      // it, the triangle being isosceles), not an approximation of it. An odd
      // count would put samples/2 between two samples and the bead would stop
      // sitting on the drawn line.
      //
      // Sized by |sweep|, NOT by `turn`. The two are the same only while the
      // arc takes the minor way round; a corner sharp enough to send the
      // apex outside the minor arc takes the REFLEX one (see `sweep` above),
      // and sizing 2·ceil(turn / 2·step) samples for a sweep of 360° − turn
      // spends them at the wrong rate: the shipped 120-degree anchor case
      // sweeps 240° over the 10 samples 120° asked for and drew 24-degree
      // facets, twice what FILLET_STEP_DEGREES promises. Half-steps of the
      // sweep keep the count even and the promise true at every deflection.
      const samples = 2 * Math.max(1, Math.ceil(Math.abs(sweep) / (2 * step)));
      const curve = [t1Point];
      for (let sample = 1; sample < samples; sample += 1) {
        const u = sample / samples;
        const angle = a1 + sweep * u;
        curve.push([cx + arcRadius * Math.cos(angle), cy + arcRadius * Math.sin(angle)]);
      }
      curve.push(t2Point);
      // The apex sample is forced to the vertex exactly — the bead (the
      // same coordinate, read in buildStroke before this function ever
      // runs) must sit ON the drawn line to the bit, not merely near it.
      // Plain integer arithmetic (not a ratio of trig results, which can
      // differ between JS's and Swift's atan2 by float noise) so both
      // ports pick the identical index.
      const apexIndex = samples / 2;
      curve[apexIndex] = [vertex[0], vertex[1]];
      return {
        last: index,
        curve,
        achieved: tangent / half,
        endOffset: tangent,
        mStart: measures[index] - (tangent * (measures[index] - measures[index - 1])) / la,
        mEnd: measures[index] + (tangent * (measures[index + 1] - measures[index])) / lb,
      };
    };
    let index = 1;
    while (index + 1 < count) {
      if (!enforceMinimumRadius && anchorSet.has(index)) {
        const arc = anchorCornerOf(index);
        if (arc) {
          for (let sample = 0; sample < arc.curve.length; sample += 1) {
            const u = sample / (arc.curve.length - 1);
            emit(arc.curve[sample], arc.mStart + (arc.mEnd - arc.mStart) * u);
          }
          guardEdge = arc.last;
          guardOffset = arc.endOffset;
          index += 1;
          continue;
        }
      }
      if (hard[index] || turns[index] < minTurn) {
        emit(points[index], measures[index]);
        index += 1;
        continue;
      }
      // Grow the run toward the promised radius, not the floor — the floor
      // only gates whether merging is attempted at all (0 disables it, run
      // stays a single vertex, exactly as before). Stop as soon as a
      // candidate reaches `radius`, the next vertex is off limits (a
      // station anchor, a reversal, or the part's own end), or the run has
      // already grown past `radius` of arc length — beyond that its own
      // outer edges (capped by FILLET_MAX_TANGENT_SHARE) cannot feed the
      // fillet any further, so growing more only risks cutting across real
      // geometry for no gain. Keep the best corner any candidate managed.
      //
      // "Reaches `radius`" is asked with a DEGENERATE_EDGE_PX allowance, not
      // bit-exactly: `achieved` is `tangent / half` where `tangent` was
      // itself `Math.min(radius * half, …)`, and dividing back out does not
      // always return exactly `radius` — the multiply-then-divide round trip
      // can land a couple of ULPs short. `half` is `Math.tan` of a turn this
      // port and rail-stroke.js's do not compute through identical library
      // code, so the two can even disagree on which side of exact `radius`
      // that round trip lands on. Without the allowance, one port stops the
      // run at this vertex while the other — reading the same `achieved` as
      // "not quite there yet" — keeps absorbing the next one, so a single
      // vertex ends up rounded on one side and merged into a two-vertex run
      // on the other. An allowance many orders below any real geometric
      // radius removes the tie without weakening what "reaches" means.
      let best = null;
      let last = index;
      for (;;) {
        const corner = cornerOf(index, last);
        if (corner && (!best || corner.achieved > best.achieved)) best = corner;
        if (best && best.achieved >= radius - DEGENERATE_EDGE_PX) break;
        if (!(floor > 0)) break;
        if (last + 1 >= count - 1 || hard[last + 1]) break;
        if (cumulative[last + 1] - cumulative[index] > radius) break;
        last += 1;
      }
      if (!best || (enforceMinimumRadius && best.achieved < floor - DEGENERATE_EDGE_PX)) {
        emit(points[index], measures[index]);
        index += 1;
        continue;
      }
      for (let sample = 0; sample < best.curve.length; sample += 1) {
        const u = sample / (best.curve.length - 1);
        emit(best.curve[sample], best.mStart + (best.mEnd - best.mStart) * u);
      }
      guardEdge = best.last;
      guardOffset = best.endOffset;
      index = best.last + 1;
    }
    emit(points[count - 1], measures[measures.length - 1]);
    return { points: out, measures: outMeasures };
  }

  // The distance from a point to a polyline, in the same pixel space.
  function distanceToPolyline(point, polyline) {
    let best = Infinity;
    for (let index = 0; index + 1 < polyline.length; index += 1) {
      const a = polyline[index];
      const b = polyline[index + 1];
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const square = dx * dx + dy * dy;
      let t = square > 0 ? ((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / square : 0;
      t = Math.max(0, Math.min(1, t));
      const held = Math.hypot(point[0] - a[0] - dx * t, point[1] - a[1] - dy * t);
      if (held < best) best = held;
    }
    return best;
  }

  // The squared distance from `point` to the SEGMENT a→b, in pixel space.
  // Clamped to the segment (not the infinite line) so a vertex beyond either
  // end of a span cannot be judged near it.
  function segmentDistanceSq(point, a, b) {
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const square = dx * dx + dy * dy;
    let t = square > 0 ? ((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / square : 0;
    t = Math.max(0, Math.min(1, t));
    const ex = point[0] - a[0] - dx * t;
    const ey = point[1] - a[1] - dy * t;
    return ex * ex + ey * ey;
  }

  // Douglas–Peucker over one span, marking the vertices it keeps. An explicit
  // stack rather than recursion (a transcontinental part is 40 000 vertices)
  // and a strict `>` against the squared tolerance, with the FIRST vertex to
  // reach a new maximum winning a tie — the Swift port does exactly the same,
  // so both languages keep the identical vertex set.
  function simplifySpan(points, lo, hi, toleranceSq, keep) {
    const stack = [[lo, hi]];
    while (stack.length) {
      const span = stack.pop();
      const first = span[0];
      const last = span[1];
      if (last <= first + 1) continue;
      let bestIndex = -1;
      let bestSq = toleranceSq;
      for (let index = first + 1; index < last; index += 1) {
        const held = segmentDistanceSq(points[index], points[first], points[last]);
        if (held > bestSq) {
          bestSq = held;
          bestIndex = index;
        }
      }
      if (bestIndex < 0) continue;
      keep[bestIndex] = true;
      stack.push([first, bestIndex]);
      stack.push([bestIndex, last]);
    }
  }

  // Decimate the stroke to `tolerance` pixels BEFORE its corners are rounded,
  // carrying the measures and the anchor set across.
  //
  // Three kinds of vertex are never dropped: the two ends (they are the
  // part's own extent, and a joint's neighbour is welded to them), and every
  // station anchor — an anchor is where `filletPolyline` draws an arc THROUGH
  // the vertex rather than cutting it away, and the bead read from it in
  // buildStroke must land on the drawn line. Each stretch between two forced
  // vertices is decimated on its own, so a kept vertex can never let a span
  // reach across one.
  function simplifyForFillet(points, measures, anchorSet, tolerance) {
    const count = points.length;
    if (!(tolerance > 0) || count < 3)
      return { points, measures, anchors: anchorSet };
    const keep = new Array(count).fill(false);
    keep[0] = true;
    keep[count - 1] = true;
    for (const index of anchorSet)
      if (index > 0 && index + 1 < count) keep[index] = true;
    const toleranceSq = tolerance * tolerance;
    let spanStart = 0;
    for (let index = 1; index < count; index += 1) {
      if (!keep[index]) continue;
      simplifySpan(points, spanStart, index, toleranceSq, keep);
      spanStart = index;
    }
    const outPoints = [];
    const outMeasures = [];
    const anchors = new Set();
    for (let index = 0; index < count; index += 1) {
      if (!keep[index]) continue;
      if (anchorSet.has(index)) anchors.add(outPoints.length);
      outPoints.push(points[index]);
      outMeasures.push(measures[index]);
    }
    if (outPoints.length === count) return { points, measures, anchors: anchorSet };
    return { points: outPoints, measures: outMeasures, anchors };
  }

  // The nearest point on `polyline` to `target`, restricted to the segments
  // whose measure range overlaps [mLo, mHi]. Used to project a fold-dropped
  // anchor onto the FINAL emitted (post-fillet) line rather than the raw
  // pre-fillet edge: a fillet at either endpoint of that edge trims it, so
  // searching the whole edge's original span would still land on ink the
  // fillet has since replaced. Restricting by measure (rather than
  // searching the whole line) also keeps this from snapping to an
  // unrelated, nearer part of a line that loops back on itself. Returns
  // null only if `polyline` has fewer than two points.
  function nearestOnMeasureSpan(target, polyline, measures, mLo, mHi) {
    const lo = Math.min(mLo, mHi);
    const hi = Math.max(mLo, mHi);
    let best = null;
    let bestDistSq = Infinity;
    for (let index = 0; index + 1 < polyline.length; index += 1) {
      if (measures[index + 1] < lo || measures[index] > hi) continue;
      const a = polyline[index];
      const b = polyline[index + 1];
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const square = dx * dx + dy * dy;
      let t = square > 0 ? ((target[0] - a[0]) * dx + (target[1] - a[1]) * dy) / square : 0;
      t = Math.max(0, Math.min(1, t));
      const px = a[0] + dx * t;
      const py = a[1] + dy * t;
      const distX = target[0] - px;
      const distY = target[1] - py;
      const distSq = distX * distX + distY * distY;
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        best = [px, py];
      }
    }
    return best;
  }

  /**
   * Build the drawn stroke of one part.
   *
   * @param {number[][]} points   vertices in pixel space
   * @param {object} options
   *   measures     cumulative METRES along the part at every vertex — the
   *                ruler the rows are measured with. Optional; without it
   *                the pixel length is scaled by totalMetres, which is only
   *                right for a part short enough to sit at one latitude.
   *   rows         lane rows `{from, to, lane}` in METRES along the part
   *   totalMetres  the part's length in metres
   *   laneGapPx    pixel distance between neighbouring lane centres
   *   minRampPx    the smoothing half-width is at least this many pixels,
   *                whatever the zoom makes of the metre ramp
   *   cornerRadiusPx  fillet radius in pixels (0 disables rounding)
   *   minCornerRadiusPx  minimum requested screen-space radius. Adjacent
   *                vertices may be merged to fit it. With
   *                enforceMinimumCornerRadius, arcs that cannot meet it are
   *                omitted; otherwise it remains a best-effort target.
   *   enforceMinimumCornerRadius  use stable offset tangents, sample lane
   *                ramps, preserve surveyed bends and anchors during fold
   *                cleanup, and enforce minCornerRadiusPx on emitted arcs.
   *                false preserves the historical fixture geometry.
   *   anchors      indices of station-platform vertices
   *   follows      corridor follows, see substituteFollows()
   *   joinStart / joinEnd  the joint with the neighbouring part of the same
   *                line at this part's first / last vertex, when the two
   *                share it: `{lane, incoming: [x, y], outgoing: [x, y]}` —
   *                the neighbour's terminal lane and the pair of unit
   *                directions at the joint, which BOTH parts derive from the
   *                same two raw edges so that both offset the shared vertex
   *                to the same point. Their PRESENCE also holds every
   *                corridor follow back one blend width from that vertex, so
   *                no borrowed alignment can move it. See laneProfile(),
   *                offsetPolyline() and substituteFollows().
   */
  function buildStroke(points, options) {
    const opts = options || {};
    if (!Array.isArray(points) || points.length < 2) {
      const copy = (points || []).map((p) => [p[0], p[1]]);
      const only = copy[copy.length - 1] || [0, 0];
      const measures =
        Array.isArray(opts.measures) && opts.measures.length === copy.length
          ? opts.measures.slice()
          : copy.map(() => 0);
      const lastMeasure = measures.length ? measures[measures.length - 1] : 0;
      return {
        points: copy,
        anchors: (opts.anchors || []).map(() => [only[0], only[1]]),
        measures,
        anchorMeasures: (opts.anchors || []).map(() => lastMeasure),
      };
    }
    const givenMeasures =
      Array.isArray(opts.measures) && opts.measures.length === points.length
        ? opts.measures
        : null;
    const rawCumulative = givenMeasures ? null : cumulativeLengths(points);
    const rawTotalPx = rawCumulative ? rawCumulative[rawCumulative.length - 1] : 0;
    const fallbackScale =
      rawTotalPx > 0 && opts.totalMetres > 0 ? opts.totalMetres / rawTotalPx : 0;
    const inputMeasures = givenMeasures || rawCumulative.map((px) => px * fallbackScale);
    const { points: clean, measures: cleanMeasures, anchorMap, anchorSet } = dedupe(
      points,
      inputMeasures,
      opts.anchors,
    );
    const anchorMeasures = (opts.anchors || []).map((index) => {
      const at = anchorMap[index];
      return at == null ? cleanMeasures[cleanMeasures.length - 1] : cleanMeasures[at];
    });
    if (clean.length < 2) {
      const only = clean[0] || points[0];
      const m = cleanMeasures[0];
      return {
        points: [only, only],
        anchors: (opts.anchors || []).map(() => [only[0], only[1]]),
        measures: [m, m],
        anchorMeasures,
      };
    }
    const gap = Number(opts.laneGapPx) || 0;
    const enforceMinimumCornerRadius = !!opts.enforceMinimumCornerRadius;
    const rows = opts.rows || [];
    const cleanCumulative = cumulativeLengths(clean);
    const cleanTotalPx = cleanCumulative[cleanCumulative.length - 1];
    const totalMetres = cleanMeasures[cleanMeasures.length - 1] - cleanMeasures[0];
    // The one global ratio still used: for the pixel floors of the taper
    // windows and the lane ramp, where a tenth either way is nothing.
    const metresPerPx = cleanTotalPx > 0 && totalMetres > 0 ? totalMetres / cleanTotalPx : 0;
    const substituted = substituteFollows(
      clean,
      cleanMeasures,
      anchorSet,
      opts.follows,
      !!opts.joinStart,
      !!opts.joinEnd,
    );
    // A substitution can fold where two alignments hand over; a fold is a
    // reversal the survey did not have, and goes the way an offset fold does.
    let followed = substituted;
    if (substituted.points !== clean) {
      const cleanReversal = clean.map(
        (_, index) =>
          index > 0 && index + 1 < clean.length &&
          Math.abs(turnAt(clean, index)) > (FOLD_TURN_DEGREES * Math.PI) / 180,
      );
      // A platform's vertex is kept whatever the fold pass thinks of it: its
      // bead is read from this polyline, so dropping it would send the bead
      // to the fallback at the end of the line.
      const reversal = new Array(substituted.points.length).fill(false);
      substituted.map.forEach((at, index) => {
        if (at >= 0) reversal[at] = cleanReversal[index] || anchorSet.has(index);
      });
      const unfolded = removeFolds(substituted.points, reversal);
      followed = {
        points: unfolded.points,
        measures: unfolded.map.map((at, index) => [at, index]).filter(([at]) => at >= 0)
          .sort((a, b) => a[0] - b[0]).map(([, index]) => substituted.measures[index]),
        map: substituted.map.map((at) => (at < 0 ? -1 : unfolded.map[at])),
      };
    }
    const followedAnchors = new Set();
    for (const index of anchorSet) if (followed.map[index] >= 0) followedAnchors.add(followed.map[index]);
    const taperedStep = taperJogs(followed.points, followed.measures, followedAnchors, metresPerPx);
    // Compose the two index maps so an original vertex resolves through both.
    let tapered = {
      points: taperedStep.points,
      measures: taperedStep.measures,
      map: followed.map.map((at) => (at < 0 ? -1 : taperedStep.map[at])),
    };
    const joinStart = opts.joinStart || null;
    const joinEnd = opts.joinEnd || null;
    const joinLaneStart = joinStart ? joinStart.lane : null;
    const joinLaneEnd = joinEnd ? joinEnd.lane : null;
    const profile = laneProfile(rows, totalMetres, joinLaneStart, joinLaneEnd);
    const width = Math.max(
      LANE_RAMP_HALF_WIDTH_METRES,
      (Number(opts.minRampPx) || 0) * metresPerPx,
    );
    if (enforceMinimumCornerRadius && gap && totalMetres > 0) {
      const sampled = sampleLaneRamps(
        tapered.points,
        tapered.measures,
        profile,
        width,
        gap,
      );
      tapered = {
        points: sampled.points,
        measures: sampled.measures,
        map: tapered.map.map((at) => (at < 0 ? -1 : sampled.map[at])),
      };
    }
    const base = tapered.points;
    const taperedAnchors = new Set();
    for (const index of anchorSet) if (tapered.map[index] >= 0) taperedAnchors.add(tapered.map[index]);
    let offset = base;
    // A neighbour's lane at the joint is as much a reason to leave the
    // centreline as a row of this part's own is: without it the two parts
    // meet at a step.
    const laned =
      rows.some((row) => row.lane) || !!joinLaneStart || !!joinLaneEnd;
    if (gap && laned && totalMetres > 0) {
      if (!profileIsFlat(profile))
        offset = offsetPolyline(
          base,
          (index) => laneAt(profile, tapered.measures[index], width) * gap,
          joinStart,
          joinEnd,
          enforceMinimumCornerRadius,
        );
    }
    const cleaned =
      offset === base
        ? { points: base, map: base.map((_, index) => index) }
        : removeOffsetFolds(
            offset,
            base,
            enforceMinimumCornerRadius,
            taperedAnchors,
          );
    // Measures follow the kept vertices, in order — the same map-driven
    // carry used above for the corridor fold pass.
    const cleanedMeasures = cleaned.map
      .map((at, index) => [at, index])
      .filter(([at]) => at >= 0)
      .sort((a, b) => a[0] - b[0])
      .map(([, index]) => tapered.measures[index]);
    const finalAnchors = new Set();
    for (const index of taperedAnchors) if (cleaned.map[index] >= 0) finalAnchors.add(cleaned.map[index]);
    // Computed BEFORE the anchor beads below so a fold-dropped anchor can be
    // projected onto the line actually drawn, not the pre-fillet edge (see
    // nearestOnMeasureSpan). A SURVIVING anchor needs no such lookup: it
    // forces a hard vertex in filletPolyline, so its own position passes
    // through unchanged either way — cleaned.points[resolved] already is
    // the emitted point.
    // Decimated BEFORE the corners are rounded, and never after — see
    // STROKE_SIMPLIFY_TOLERANCE_PX. Both the anchor set and the measures are
    // carried across; the anchors, the two ends, and nothing else, are forced
    // to survive.
    const drawn = simplifyForFillet(
      cleaned.points,
      cleanedMeasures,
      finalAnchors,
      STROKE_SIMPLIFY_TOLERANCE_PX,
    );
    const filleted = filletPolyline(
      drawn.points,
      Number(opts.cornerRadiusPx) || 0,
      Number(opts.minCornerRadiusPx) || 0,
      drawn.anchors,
      drawn.measures,
      enforceMinimumCornerRadius,
    );
    const anchors = (opts.anchors || []).map((index) => {
      const at = anchorMap[index];
      const moved = at == null ? -1 : tapered.map[at];
      if (moved < 0) {
        const point = offset[offset.length - 1];
        return [point[0], point[1]];
      }
      const resolved = cleaned.map[moved];
      if (resolved >= 0) {
        const point = cleaned.points[resolved];
        return [point[0], point[1]];
      }
      // Fold removal dropped this vertex: the bead goes on the surviving
      // edge that replaced it, nearest the offset position it was reading
      // from — not the vertex the fold pass threw away — and projected onto
      // the FINAL emitted (post-fillet) line: a fillet at either endpoint
      // of that edge trims it, so projecting onto the pre-fillet edge can
      // land off the drawn ink whenever cornerRadiusPx > 0.
      let prev = moved;
      while (prev > 0 && cleaned.map[prev] < 0) prev -= 1;
      let next = moved;
      while (next < cleaned.map.length - 1 && cleaned.map[next] < 0) next += 1;
      const aIndex = cleaned.map[prev];
      const bIndex = cleaned.map[next];
      const target = offset[moved];
      const projected = nearestOnMeasureSpan(
        target,
        filleted.points,
        filleted.measures,
        cleanedMeasures[aIndex],
        cleanedMeasures[bIndex],
      );
      if (projected) return projected;
      const a = cleaned.points[aIndex];
      const b = cleaned.points[bIndex];
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const square = dx * dx + dy * dy;
      let t = square > 0 ? ((target[0] - a[0]) * dx + (target[1] - a[1]) * dy) / square : 0;
      t = Math.max(0, Math.min(1, t));
      return [a[0] + dx * t, a[1] + dy * t];
    });
    // A fillet at a vertex whose neighbour edge is tiny can overshoot its
    // predecessor by float noise; clamp so the measures stay non-decreasing.
    const finalMeasures = filleted.measures.slice();
    for (let index = 1; index < finalMeasures.length; index += 1)
      if (finalMeasures[index] < finalMeasures[index - 1]) finalMeasures[index] = finalMeasures[index - 1];
    return { points: filleted.points, anchors, measures: finalMeasures, anchorMeasures };
  }

  // Partition a part's measure range at its family-collapse windows: BASE
  // pieces (this line's own colour) cover the complement of every
  // tenant ∪ landlord window; a FAMILY piece covers each landlord window.
  // Reproduces railmap.js's `_applyContinuousStrokes` family-window branch
  // and RailCore's `ContinuousStroke.familyPartition` (iOS,
  // `RailMapView.swift`'s `continuousStrokeBuild`) — the two are checked
  // answer-identical to 1e-9 m over `port-fixtures/family-windows.json`, so
  // a change here must be mirrored there.
  //
  // `tenantWindows`/`landlordWindows` are `{from, to, groupId}` triples,
  // reviewed non-overlapping WITHIN each list (`familyWindowsByRegion`'s own
  // contract) but not necessarily against each other before clamping — a
  // window with `from > to` is normalised first. `options.measureStart` /
  // `options.measureEnd` are the STROKE's own measure range (`stroke.
  // measures[0]`/`stroke.measures[last]`), not `[0, totalMetres]`: a joint's
  // extension or a follow's own vertices can leave the built stroke short of
  // the part's nominal total, and clamping to the wrong bound there would
  // manufacture a sliver of base colour past the geometry that actually
  // exists. Both default to `[0, totalMetres]` when omitted, matching the
  // fixture's own pinned cases (built straight off `part.totalMetres`).
  //
  // Both output arrays are sorted by `from`; a piece below
  // FAMILY_PARTITION_EPSILON_METRES is dropped from EITHER array — a window
  // that clamped to nothing, or a base gap between two windows that meet
  // exactly, leaves no piece rather than a zero-length one. `family` holds
  // one piece per surviving landlord window (never merged with a neighbour,
  // even a contiguous one), each still carrying its own `groupId` so the
  // caller can look up that group's colour.
  function familyPartition(totalMetres, tenantWindows, landlordWindows, options) {
    const measureStart = options && options.measureStart != null ? options.measureStart : 0;
    const measureEnd = options && options.measureEnd != null ? options.measureEnd : totalMetres;
    const clamp = (v) => Math.max(measureStart, Math.min(measureEnd, v));
    const normalise = (isLandlord) => (window) => ({
      from: clamp(Math.min(window.from, window.to)),
      to: clamp(Math.max(window.from, window.to)),
      groupId: window.groupId,
      isLandlord,
    });
    const excluded = [
      ...(tenantWindows || []).map(normalise(false)),
      ...(landlordWindows || []).map(normalise(true)),
    ].sort((a, b) => a.from - b.from);
    const base = [];
    const family = [];
    let cursor = measureStart;
    for (const window of excluded) {
      if (window.to - window.from <= FAMILY_PARTITION_EPSILON_METRES) continue;
      if (window.from - cursor > FAMILY_PARTITION_EPSILON_METRES)
        base.push({ from: cursor, to: window.from });
      if (window.isLandlord) family.push({ from: window.from, to: window.to, groupId: window.groupId });
      cursor = Math.max(cursor, window.to);
    }
    if (measureEnd - cursor > FAMILY_PARTITION_EPSILON_METRES) base.push({ from: cursor, to: measureEnd });
    return { base, family };
  }

  // Clip `ranges` (`{from, to}` pairs, any order) to the complement of
  // `tenantWindows` — the stretch(es) of each range NOT covered by any
  // tenant window. Used for a withheld span (rail-network.js `part.
  // withheld`): a span straddling a tenant window's edge is drawn only on
  // the piece(s) that are still this line's own track — the piece inside
  // the tenant window is the sibling landlord's own stroke to draw, not
  // this line's (see the withheld-clip note in railmap.js and
  // RailMapView.swift's `continuousStrokeBuild`).
  //
  // A reversed range (`from > to`) is normalised first; tenant windows are
  // sorted by `from` before clipping. Output is sorted by `from`, with any
  // piece below FAMILY_PARTITION_EPSILON_METRES dropped — the same
  // tolerance `familyPartition` drops a piece at.
  function clipRangesToComplement(ranges, tenantWindows) {
    const windows = (tenantWindows || [])
      .map((window) => ({ from: Math.min(window.from, window.to), to: Math.max(window.from, window.to) }))
      .sort((a, b) => a.from - b.from);
    const out = [];
    for (const raw of ranges || []) {
      const rangeFrom = Math.min(raw.from, raw.to);
      const rangeTo = Math.max(raw.from, raw.to);
      let cursor = rangeFrom;
      for (const window of windows) {
        const from = Math.max(window.from, rangeFrom);
        const to = Math.min(window.to, rangeTo);
        if (to <= from) continue;
        if (from > cursor) out.push({ from: cursor, to: from });
        cursor = Math.max(cursor, to);
      }
      if (rangeTo > cursor) out.push({ from: cursor, to: rangeTo });
    }
    return out
      .filter((range) => range.to - range.from > FAMILY_PARTITION_EPSILON_METRES)
      .sort((a, b) => a.from - b.from);
  }

  // The polyline between two metre measures of a `buildStroke` result, in
  // the same pixel space. Both endpoints are interpolated exactly inside
  // their containing interval; every intermediate vertex is included; the
  // measures are clamped to the stroke's own range; the order is reversed
  // when `from > to`. `measures` must be non-decreasing (as `buildStroke`
  // returns it) and the same length as `points`.
  function sliceStroke(points, measures, from, to) {
    const count = Array.isArray(points) ? points.length : 0;
    if (count < 2 || !Array.isArray(measures) || measures.length !== count) return [];
    const lo = measures[0];
    const hi = measures[count - 1];
    const clamp = (v) => Math.max(lo, Math.min(hi, v));
    const a = clamp(from);
    const b = clamp(to);
    const lowM = Math.min(a, b);
    const highM = Math.max(a, b);
    if (!(highM - lowM >= 1e-9)) return [];
    // Rightmost index whose measure is ≤ the target, clamped to count-2 so
    // the returned index always starts a valid segment.
    const locate = (m) => {
      let low = 0;
      let high = count - 1;
      while (low < high) {
        const mid = Math.ceil((low + high) / 2);
        if (measures[mid] <= m) low = mid;
        else high = mid - 1;
      }
      return Math.min(low, count - 2);
    };
    const pointAt = (index, m) => {
      const denom = measures[index + 1] - measures[index];
      const t = denom > 0 ? (m - measures[index]) / denom : 0;
      const p0 = points[index];
      const p1 = points[index + 1];
      return [p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t];
    };
    const iLow = locate(lowM);
    const iHigh = locate(highM);
    const out = [pointAt(iLow, lowM)];
    for (let index = iLow + 1; index <= iHigh; index += 1)
      if (measures[index] < highM) out.push(points[index]);
    out.push(pointAt(iHigh, highM));
    if (out.length < 2) return [];
    if (from > to) out.reverse();
    return out;
  }

  return Object.freeze({
    LANE_RAMP_HALF_WIDTH_METRES,
    LANE_PLATEAU_MIN_METRES,
    LANE_JOIN_EXTENT_METRES,
    FOLLOW_BLEND_METRES,
    JOG_MIN_TURN_DEGREES,
    JOG_MAX_TURN_DEGREES,
    JOG_MAX_RUN_METRES,
    JOG_MAX_NET_TURN_DEGREES,
    JOG_MIN_LATERAL_METRES,
    JOG_TAPER_METRES,
    JOG_MIN_TAPER_METRES,
    JOG_TAPER_SAMPLES,
    FOLD_TURN_DEGREES,
    FILLET_MIN_TURN_DEGREES,
    FILLET_MAX_TURN_DEGREES,
    FILLET_MAX_TANGENT_SHARE,
    FILLET_STEP_DEGREES,
    STROKE_SIMPLIFY_TOLERANCE_PX,
    MITER_LIMIT,
    worldSize,
    project,
    unproject,
    laneProfile,
    laneAt,
    profileIsFlat,
    terminalLanes,
    buildStroke,
    sliceStroke,
    FAMILY_PARTITION_EPSILON_METRES,
    familyPartition,
    clipRangesToComplement,
  });
});
