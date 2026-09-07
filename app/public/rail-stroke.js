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
  const FILLET_MAX_TANGENT_SHARE = 0.45;
  // Curve sampling: one vertex per this many degrees of turn.
  const FILLET_STEP_DEGREES = 12;
  // Offsetting a vertex along its bisector scales the offset by 1/cos(θ/2).
  // Past this factor the corner is sharp enough that a mitre would spike;
  // the offset is clamped and the fillet pass rounds what is left.
  const MITER_LIMIT = 2.5;
  // Two vertices closer than this, in pixels, are one vertex.
  const DEGENERATE_EDGE_PX = 1e-6;

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
  function laneProfile(rows, total) {
    if (!(total > 0)) return [];
    const plateaus = [];
    let cursor = 0;
    const sorted = (rows || []).slice().sort((a, b) => a.from - b.from);
    for (const row of sorted) {
      const from = Math.max(cursor, Math.min(row.from, total));
      const to = Math.max(from, Math.min(row.to, total));
      if (from > cursor) plateaus.push({ from: cursor, to: from, lane: 0 });
      if (to > from) plateaus.push({ from, to, lane: row.lane });
      cursor = to;
    }
    if (cursor < total) plateaus.push({ from: cursor, to: total, lane: 0 });
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
  function substituteFollows(points, measures, anchorSet, follows) {
    const count = points.length;
    const identity = { points, measures, map: points.map((_, index) => index) };
    if (!follows?.length || count < 2) return identity;
    const cumulative = measures;
    const total = cumulative[count - 1];
    const blend = FOLLOW_BLEND_METRES;
    // Each follow with the canonical's own metre measures; an unusable
    // follow is dropped.
    const prepared = [];
    for (const follow of follows) {
      const canon = follow.points;
      if (!Array.isArray(canon) || canon.length < 2) continue;
      if (!(follow.to > follow.from)) continue;
      const canonCumulative =
        Array.isArray(follow.measures) && follow.measures.length === canon.length
          ? follow.measures
          : null;
      if (!canonCumulative) continue;
      const canonTotal = canonCumulative[canonCumulative.length - 1];
      if (!(canonTotal > 0)) continue;
      prepared.push({
        from: follow.from,
        to: follow.to,
        canonFrom: follow.canonFrom,
        canonTo: follow.canonTo,
        canon,
        canonCumulative,
        canonTotalPx: canonTotal,
      });
    }
    if (!prepared.length) return identity;
    prepared.sort((a, b) => a.from - b.from);
    // The weight of every canonical alignment at a measure: the
    // kernel-smoothed indicator of each stretch. Where two stretches meet —
    // one canonical part handing over to the next — both are partly
    // weighted, and the stroke cross-fades between the two alignments
    // instead of jumping from one to the other; the weights are normalised
    // so the own alignment never gets a negative share.
    // A follow that begins at the part's own start (or ends at its end) is
    // whole from that end: the kernel would otherwise weight the terminal
    // vertex by half and leave the platform bead between two alignments.
    const first = cumulative[0];
    const weightsAt = (s) => {
      const held = [];
      let sum = 0;
      for (const follow of prepared) {
        const rise =
          follow.from <= first + DEGENERATE_EDGE_PX ? 1 : kernelCumulative(s - follow.from, blend);
        const fall =
          follow.to >= total - DEGENERATE_EDGE_PX ? 0 : kernelCumulative(s - follow.to, blend);
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
  function offsetPolyline(points, distanceAt) {
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
      const before = index > 0 ? points[index - 1] : null;
      const after = index + 1 < count ? points[index + 1] : null;
      let t0 = null;
      let t1 = null;
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
      if (t0 && t1) {
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

  function removeOffsetFolds(offset, original) {
    const count = offset.length;
    const foldTurn = (FOLD_TURN_DEGREES * Math.PI) / 180;
    const reversal = new Array(count).fill(false);
    for (let index = 1; index + 1 < count; index += 1)
      reversal[index] = Math.abs(turnAt(original, index)) > foldTurn;
    return removeFolds(offset, reversal);
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
  function filletPolyline(points, radius, anchorSet) {
    if (!(radius > 0) || points.length < 3) return points;
    const minTurn = (FILLET_MIN_TURN_DEGREES * Math.PI) / 180;
    const maxTurn = (FILLET_MAX_TURN_DEGREES * Math.PI) / 180;
    const step = (FILLET_STEP_DEGREES * Math.PI) / 180;
    const out = [points[0]];
    // The point the previous fillet ended at, if it ended on the edge that
    // starts at this vertex's predecessor — the share cap keeps it clear.
    for (let index = 1; index + 1 < points.length; index += 1) {
      const point = points[index];
      if (anchorSet.has(index)) {
        out.push(point);
        continue;
      }
      const before = points[index - 1];
      const after = points[index + 1];
      const ax = point[0] - before[0];
      const ay = point[1] - before[1];
      const bx = after[0] - point[0];
      const by = after[1] - point[1];
      const la = Math.hypot(ax, ay);
      const lb = Math.hypot(bx, by);
      if (la <= DEGENERATE_EDGE_PX || lb <= DEGENERATE_EDGE_PX) {
        out.push(point);
        continue;
      }
      const t0x = ax / la;
      const t0y = ay / la;
      const t1x = bx / lb;
      const t1y = by / lb;
      const dot = Math.max(-1, Math.min(1, t0x * t1x + t0y * t1y));
      const turn = Math.acos(dot);
      if (turn < minTurn || turn > maxTurn) {
        out.push(point);
        continue;
      }
      const tangent = Math.min(
        radius * Math.tan(turn / 2),
        FILLET_MAX_TANGENT_SHARE * Math.min(la, lb),
      );
      if (!(tangent > DEGENERATE_EDGE_PX)) {
        out.push(point);
        continue;
      }
      const start = [point[0] - t0x * tangent, point[1] - t0y * tangent];
      const end = [point[0] + t1x * tangent, point[1] + t1y * tangent];
      const samples = Math.max(2, Math.ceil(turn / step));
      out.push(start);
      for (let sample = 1; sample < samples; sample += 1) {
        const u = sample / samples;
        const v = 1 - u;
        out.push([
          v * v * start[0] + 2 * u * v * point[0] + u * u * end[0],
          v * v * start[1] + 2 * u * v * point[1] + u * u * end[1],
        ]);
      }
      out.push(end);
    }
    out.push(points[points.length - 1]);
    return out;
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
   *   anchors      indices of station-platform vertices
   *   follows      corridor follows, see substituteFollows()
   */
  function buildStroke(points, options) {
    const opts = options || {};
    if (!Array.isArray(points) || points.length < 2)
      return { points: (points || []).map((p) => [p[0], p[1]]), anchors: [] };
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
    if (clean.length < 2) {
      const only = clean[0] || points[0];
      return {
        points: [only, only],
        anchors: (opts.anchors || []).map(() => [only[0], only[1]]),
      };
    }
    const gap = Number(opts.laneGapPx) || 0;
    const rows = opts.rows || [];
    const cleanCumulative = cumulativeLengths(clean);
    const cleanTotalPx = cleanCumulative[cleanCumulative.length - 1];
    const totalMetres = cleanMeasures[cleanMeasures.length - 1] - cleanMeasures[0];
    // The one global ratio still used: for the pixel floors of the taper
    // windows and the lane ramp, where a tenth either way is nothing.
    const metresPerPx = cleanTotalPx > 0 && totalMetres > 0 ? totalMetres / cleanTotalPx : 0;
    const substituted = substituteFollows(clean, cleanMeasures, anchorSet, opts.follows);
    // A substitution can fold where two alignments hand over; a fold is a
    // reversal the survey did not have, and goes the way an offset fold does.
    let followed = substituted;
    if (substituted.points !== clean) {
      const cleanReversal = clean.map(
        (_, index) =>
          index > 0 && index + 1 < clean.length &&
          Math.abs(turnAt(clean, index)) > (FOLD_TURN_DEGREES * Math.PI) / 180,
      );
      const reversal = new Array(substituted.points.length).fill(false);
      substituted.map.forEach((at, index) => {
        if (at >= 0) reversal[at] = cleanReversal[index];
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
    const tapered = {
      points: taperedStep.points,
      measures: taperedStep.measures,
      map: followed.map.map((at) => (at < 0 ? -1 : taperedStep.map[at])),
    };
    const base = tapered.points;
    const taperedAnchors = new Set();
    for (const index of anchorSet) if (tapered.map[index] >= 0) taperedAnchors.add(tapered.map[index]);
    let offset = base;
    if (gap && rows.some((row) => row.lane) && totalMetres > 0) {
      const profile = laneProfile(rows, totalMetres);
      const width = Math.max(
        LANE_RAMP_HALF_WIDTH_METRES,
        (Number(opts.minRampPx) || 0) * metresPerPx,
      );
      if (!profileIsFlat(profile))
        offset = offsetPolyline(base, (index) =>
          laneAt(profile, tapered.measures[index], width) * gap,
        );
    }
    const cleaned =
      offset === base
        ? { points: base, map: base.map((_, index) => index) }
        : removeOffsetFolds(offset, base);
    const finalAnchors = new Set();
    for (const index of taperedAnchors) if (cleaned.map[index] >= 0) finalAnchors.add(cleaned.map[index]);
    const anchors = (opts.anchors || []).map((index) => {
      const at = anchorMap[index];
      const moved = at == null ? -1 : tapered.map[at];
      const point = moved < 0 ? offset[offset.length - 1] : offset[moved];
      return [point[0], point[1]];
    });
    const rounded = filletPolyline(cleaned.points, Number(opts.cornerRadiusPx) || 0, finalAnchors);
    return { points: rounded, anchors };
  }

  return Object.freeze({
    LANE_RAMP_HALF_WIDTH_METRES,
    LANE_PLATEAU_MIN_METRES,
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
    MITER_LIMIT,
    worldSize,
    project,
    unproject,
    laneProfile,
    laneAt,
    profileIsFlat,
    buildStroke,
  });
});
