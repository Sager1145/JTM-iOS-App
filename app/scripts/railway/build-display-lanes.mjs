#!/usr/bin/env node
/*
 * Build the derived screen-space lane table consumed by both map clients.
 *
 * Existing compact packages already carry reviewed lane rows for jp/tw/hk/mo/kr.
 * North America was added after that pipeline was retired, so this script derives
 * its rows from the same display strokes the clients draw. North American lanes
 * represent render groups, not individual timetable services: a line gets its own
 * lane when the reviewed policy in `na-render-groups.json` puts it in its own
 * group, and shares the centreline with everything in the same group. This keeps
 * Amtrak/VIA service names together without collapsing separately branded urban
 * lines such as CTA or RTD routes.
 */
"use strict";

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const APP_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const RailNetwork = require(path.join(APP_DIR, "public", "rail-network.js"));
const RAIL_DIR = path.join(APP_DIR, "public", "rail");
const OUTPUT = path.join(RAIL_DIR, "display-lanes.json");
const SHARED_CORRIDORS = path.join(RAIL_DIR, "shared-corridors.json");
const RENDER_GROUPS = path.join(RAIL_DIR, "na-render-groups.json");
const DISPLAY_RELEASES = path.join(RAIL_DIR, "display-releases.json");
const REGIONS = ["jp", "tw", "hk", "mo", "kr", "us", "ca"];

const SAMPLE_METRES = 25;
const NEAR_METRES = 45;
const MIN_RUN_METRES = 3000;
const BRIDGE_METRES = 12000;
const STATION_SNAP_METRES = 2000;
const CELL_DEGREES = 0.00055;
// A lane must hold for this far before it is allowed to become the line's lane.
// Partners join and leave a corridor constantly; without a window this wide,
// every branch that touched the bundle for a kilometre pushed the line across
// it and back, and the reader saw a stroke that weaves rather than a railway.
const SMOOTH_WINDOW_METRES = 1500;
// One lane for the WHOLE stroke wherever the corridor evidence allows it: a
// line that keeps a single lane end to end is ONE feature, and one feature is
// the only shape a renderer cannot break into pieces. A line is collapsed onto
// its busiest lane when that lane already holds this share of everything it
// spends in a corridor; the stretches it then rides slightly off-centre are
// the ones where nothing runs beside it to be off-centre from.
const DOMINANT_LANE_SHARE = 0.6;
// A stroke this close to a higher-ranked partner over a whole run is not
// beside it, it is ON the same tracks: two digitisations of one corridor
// that weave across each other by the width of a survey. Offsetting each
// from its own weaving alignment draws the weave twice; drawing both from
// the higher-ranked stroke's alignment draws the corridor once. Such runs
// are written as FOLLOW rows and the renderers substitute the canonical
// geometry before offsetting (rail-stroke.js `follows`). The median lateral
// is measured over the smoothed run, so a single crossing cannot qualify a
// pair, and a separate right of way 30 m over stays separate.
const FOLLOW_MAX_MEDIAN_METRES = 25;
const FOLLOW_MIN_RUN_METRES = 1000;
// Nobody is excluded from the corridor pass. Amtrak and VIA share their whole
// eastern network with commuter operators, and drawing them on the commuter
// centreline hid one railway under the other wherever they run together.
const EXCLUDED_OFFSET_OPERATORS = new Set();

// The render group a line belongs to, from the reviewed policy in
// `na-render-groups.json` rather than from anything the renderer can guess.
// Two lines that resolve to the same group are one drawn stroke; two that do
// not are held apart in parallel screen lanes.
//
// The default is operator plus the operator's OWN published route colour,
// because that is the branding grouping every audited North American network
// actually uses — MTA's trunk families, Amtrak's one intercity blue, MBTA's
// one commuter magenta all fall out of it unchanged. What the default may not
// do is decide identity: where two different railways publish the same hex,
// the policy's `byLineId` names their groups instead, so a shared colour never
// merges them.
//
// `kind` is deliberately absent. It is a mode attribute, not an identity: one
// railway carries `lightrail` on its reserved track and `streetcar` where it
// runs in the street, and keying on it split seven railways from their own
// branch parts — the Green Line rode the Kenmore–Government Center trunk as
// two parallel green strokes, one for D and one for B/C/E.
function displayClassKey(line, renderGroups) {
  const explicit = renderGroups?.byLineId?.[line?.id || line?.lineId];
  if (explicit) return `group\0${explicit}`;
  const operator = String(line?.operator || "").trim().toLocaleLowerCase("en-US");
  const color = String(line?.color || "").trim().toLocaleLowerCase("en-US");
  // A missing operator is not evidence that two records belong to one company.
  // Keep such records distinct rather than silently merging unrelated railways.
  if (!operator) return `unknown\0${line?.id || line?.lineId || ""}`;
  return `${operator}\0${color}`;
}

// rail-network.js's equirectangular metre, to the digit: 111320 on BOTH axes.
// A row is a pair of measures along a stroke that the renderer re-measures for
// itself, so the two rulers have to be the same ruler. They were not — 110540
// on the north axis reads a north-south line 0.7% short, which on the Barrie
// line left the last 340 metres outside every row and the renderer ramped the
// stroke back to the centreline to cross them.
function distanceMeters(a, b) {
  const lat = ((a[1] + b[1]) / 2) * (Math.PI / 180);
  return Math.hypot(
    (b[0] - a[0]) * 111320 * Math.cos(lat),
    (b[1] - a[1]) * 111320,
  );
}

function cumulativeMeasures(points) {
  const out = [0];
  for (let index = 1; index < points.length; index += 1)
    out.push(out[index - 1] + distanceMeters(points[index - 1], points[index]));
  return out;
}

function pointAt(points, cumulative, measure) {
  if (measure <= 0) return { point: points[0], index: 0 };
  const last = cumulative.length - 1;
  if (measure >= cumulative[last]) return { point: points[last], index: last - 1 };
  let index = 1;
  while (index < last && cumulative[index] < measure) index += 1;
  const span = cumulative[index] - cumulative[index - 1];
  const ratio = span > 0 ? (measure - cumulative[index - 1]) / span : 0;
  const a = points[index - 1];
  const b = points[index];
  return {
    point: [a[0] + (b[0] - a[0]) * ratio, a[1] + (b[1] - a[1]) * ratio],
    index: index - 1,
  };
}

function samplesFor(part) {
  const cumulative = cumulativeMeasures(part.coordinates);
  const total = cumulative[cumulative.length - 1];
  const samples = [];
  for (let measure = 0; measure < total; measure += SAMPLE_METRES) {
    const found = pointAt(part.coordinates, cumulative, measure);
    const a = part.coordinates[found.index];
    const b = part.coordinates[Math.min(found.index + 1, part.coordinates.length - 1)];
    const lat = ((a[1] + b[1]) / 2) * (Math.PI / 180);
    const dx = (b[0] - a[0]) * Math.cos(lat);
    const dy = b[1] - a[1];
    const norm = Math.hypot(dx, dy) || 1;
    samples.push({
      part,
      point: found.point,
      measure,
      tangent: [dx / norm, dy / norm],
    });
  }
  if (!samples.length || samples[samples.length - 1].measure !== total) {
    const found = pointAt(part.coordinates, cumulative, total);
    const a = part.coordinates[found.index];
    const b = part.coordinates[Math.min(found.index + 1, part.coordinates.length - 1)];
    const lat = ((a[1] + b[1]) / 2) * (Math.PI / 180);
    const dx = (b[0] - a[0]) * Math.cos(lat);
    const dy = b[1] - a[1];
    const norm = Math.hypot(dx, dy) || 1;
    samples.push({ part, point: found.point, measure: total, tangent: [dx / norm, dy / norm] });
  }
  return { cumulative, total, samples };
}

// Where `point` lies ACROSS the line at `sample`, signed positive to the RIGHT
// of the direction the geometry was digitised in — the side MapLibre calls a
// positive line-offset and the iOS renderer bakes with the right-hand normal.
// Tangents are unit vectors in the same longitude-corrected degree space these
// samples were measured in, so one scale converts the cross product to metres.
function lateralMetres(sample, point) {
  const lat = (sample.point[1] * Math.PI) / 180;
  const east = (point[0] - sample.point[0]) * Math.cos(lat);
  const north = point[1] - sample.point[1];
  return (sample.tangent[1] * east - sample.tangent[0] * north) * 110540;
}

// Two strokes the corridor ledger has reconciled onto one alignment weave
// across each other every few hundred metres. Below this separation their
// order is not evidence of anything, so it is not allowed to decide one.
const COINCIDENT_METRES = 15;
// A nominal side, small enough that any measured side outranks it.
const COINCIDENT_TIE_METRES = 1e-6;

// The side a partner is ranked on. Outside the deadband the measured side is
// the answer. Inside it the strokes are on top of one another and the measure
// is noise, so the name order decides — but only between strokes drawn the
// same way round. Two strokes digitised against each other must BOTH rank the
// other to their own right: each then takes the lane on its own left, and
// their own left is the corridor's two opposite sides.
function rankingLateral(metres, selfKey, otherKey, along) {
  if (Math.abs(metres) >= COINCIDENT_METRES) return metres;
  if (along < 0) return COINCIDENT_TIE_METRES;
  return selfKey < otherKey ? COINCIDENT_TIE_METRES : -COINCIDENT_TIE_METRES;
}

// The side each partner keeps over a WHOLE shared run, held constant for every
// sample of that run. Averaging before the ranking is what makes a rank
// stable, and averaging over the run rather than over a window is what makes
// it constant: two strokes that cross each other forty times down a corridor
// have one answer to which side each is on, so the ranking gets one answer and
// the line does not weave across the bundle chasing individual crossings.
// A partner that drops out of range for less than the smoothing window has not
// left the corridor — its run continues on the far side of the gap.
function smoothedNeighbourLaterals(neighbours) {
  const gap = Math.max(1, Math.round(SMOOTH_WINDOW_METRES / SAMPLE_METRES));
  const out = neighbours.map(() => new Map());
  const open = new Map();
  const close = (key, run) => {
    const mean = run.sum / run.count;
    for (const index of run.at) out[index].set(key, mean);
  };
  neighbours.forEach((held, index) => {
    for (const [key, lateral] of held.laterals) {
      let run = open.get(key);
      if (run && index - run.last > gap) {
        close(key, run);
        run = null;
      }
      if (!run) open.set(key, (run = { sum: 0, count: 0, at: [], last: index }));
      run.sum += lateral;
      run.count += 1;
      run.at.push(index);
      run.last = index;
    }
  });
  for (const [key, run] of open) close(key, run);
  return out;
}

// Lexicographic order over two equal-length tie-break keys.
function firstDifference(a, b) {
  for (let index = 0; index < a.length; index += 1)
    if (a[index] !== b[index]) return a[index] - b[index];
  return 0;
}

// The lane a stretch spends most of its length in, over a window wide enough
// that a partner passing through cannot move the line. Ties keep the lane the
// sample already had, then the one nearest the centreline, so the filter can
// only ever settle — it never flips a stretch back and forth on its own.
function smoothedLaneStates(states) {
  const span = Math.max(1, Math.round(SMOOTH_WINDOW_METRES / SAMPLE_METRES));
  const tally = new Map();
  const add = (lane, delta) => {
    const held = (tally.get(lane) || 0) + delta;
    if (held > 0) tally.set(lane, held);
    else tally.delete(lane);
  };
  for (let index = 0; index <= Math.min(span, states.length - 1); index += 1)
    add(states[index].lane, 1);
  return states.map((state, index) => {
    if (index) {
      const leaving = index - span - 1;
      if (leaving >= 0) add(states[leaving].lane, -1);
      const arriving = index + span;
      if (arriving < states.length) add(states[arriving].lane, 1);
    }
    const preference = (lane) => [
      lane === state.lane ? 0 : 1,
      Math.abs(lane),
      lane,
    ];
    let best = null;
    for (const [lane, count] of tally) {
      if (!best) {
        best = { lane, count };
        continue;
      }
      if (count < best.count) continue;
      if (count > best.count || firstDifference(preference(lane), preference(best.lane)) < 0)
        best = { lane, count };
    }
    return { lane: best ? best.lane : state.lane, measure: state.measure };
  });
}

function cell(point) {
  return [Math.floor(point[0] / CELL_DEGREES), Math.floor(point[1] / CELL_DEGREES)];
}

function partKey(part) {
  return `${part.lineId}#${part.partIndex}`;
}

function coordinatesForFeature(feature) {
  if (!feature?.geometry) return [];
  if (feature.geometry.type === "LineString") return [feature.geometry.coordinates];
  if (feature.geometry.type === "MultiLineString") return feature.geometry.coordinates;
  return [];
}

function deriveNorthAmericanRows(pkg, reviewedSharedCorridors, excludedLineIds, renderGroups, releasesByRegion) {
  // Measure lanes on the reviewed DISPLAY centreline, not on the independent
  // source strokes that the corridor ledger has just reconciled. Otherwise a
  // noisy pair can be close enough to trigger a lane but still weave across
  // each other underneath that offset. The alignment releases are applied
  // here too, so a part is measured over exactly the geometry the renderers
  // will draw — a row measured from a chain that starts at the second
  // station lands a station's worth of metres from where it belongs once
  // the first interval is back.
  const network = RailNetwork.buildNetworkFromCompactPackage(
    { ...pkg, lanes: undefined },
    reviewedSharedCorridors,
    { format: "jtm-display-lanes-v1", byRegion: {}, releasedIntervalsByRegion: releasesByRegion },
  );
  const comparisonByLine =
    pkg.geometrySource?.officialGeometryComparison?.byLine || {};
  const compactLineById = new Map(pkg.lines.map((line) => [line.id, line]));
  const displayPartsByLine = new Map();
  for (const feature of network.segments.features || []) {
    const lineId = feature?.properties?.lineId;
    if (!lineId) continue;
    const held = displayPartsByLine.get(lineId) || [];
    held.push(...coordinatesForFeature(feature));
    displayPartsByLine.set(lineId, held);
  }
  const parts = [];
  for (const line of network.lineById.values()) {
    const compactLine = compactLineById.get(line.lineId);
    if (!compactLine) continue;
    const operator = String(compactLine.operator || "")
      .trim()
      .toLocaleLowerCase("en-US");
    const blockedIntervals =
      comparisonByLine[line.lineId]?.displayBlockedIntervals || [];
    // A withheld interval splits the display parts on BOTH clients at the
    // same place (rail-network.js flushes the part there; the native builder
    // starts a new chain), so rows measured per part stay valid on each side
    // of the gap and never bridge it. A blocked line therefore takes lanes
    // and follows like any other; only the reviewed exclusions stay out.
    const stationPoints = (line.stationOrder || [])
      .map((id) => network.stationById.get(id))
      .filter(Boolean)
      .map((station) => [station.lon, station.lat]);
    // A line with a withheld interval remains a useful passive centreline for
    // its reviewed partner. It never receives an offset row itself, so the
    // alignment gate stays fail-closed, while the safe partner can still move
    // into a visible parallel lane (South Shore is the motivating case).
    (displayPartsByLine.get(line.lineId) || []).forEach((coordinates, partIndex) => {
      if (coordinates.length < 2) return;
      parts.push({
        lineId: line.lineId,
        displayClass: displayClassKey(compactLine, renderGroups),
        kind: String(compactLine.kind || ""),
        geometrySource: String(compactLine.geometrySource || ""),
        partIndex,
        coordinates,
        stationPoints,
        withheld: blockedIntervals.length > 0,
        emitsRows:
          !EXCLUDED_OFFSET_OPERATORS.has(operator) &&
          !excludedLineIds.has(line.lineId),
      });
    });
  }

  const metrics = new Map();
  const grid = new Map();
  for (const part of parts) {
    const metric = samplesFor(part);
    metrics.set(partKey(part), metric);
    for (const sample of metric.samples) {
      const [x, y] = cell(sample.point);
      const key = `${x}|${y}`;
      if (!grid.has(key)) grid.set(key, []);
      grid.get(key).push(sample);
    }
  }

  const rows = [];
  const follows = [];
  const measured = [];
  // Who is canonical where two strokes share one corridor. The tenant is
  // drawn from the landlord's alignment: the operator whose own railway it
  // is — a metro or commuter operator publishing its own centreline — over
  // an intercity service that merely runs across it from a GTFS shape; then
  // the surveyed source over the coarser one; then the longer part. The
  // order is a fact about the data's provenance, not about the map, and it
  // is deterministic by construction.
  const KIND_PRIORITY = ["metro", "lightrail", "streetcar", "monorail", "people-mover",
    "funicular", "commuter", "regional", "intercity", "heritage"];
  // A follow never crosses the mode line: an elevated metro beside a
  // mainline is NEAR_PARALLEL, two rights of way a survey's width apart,
  // and neither is drawn from the other's alignment. Only railways of one
  // family — the heavy-rail services that really do share track, or the
  // urban modes that really do share street and structure — can follow.
  const HEAVY_RAIL = new Set(["commuter", "regional", "intercity", "heritage"]);
  const railFamily = (kind) => (HEAVY_RAIL.has(kind) ? "heavy" : "urban");
  const sourcePriority = (source) => {
    if (/^(orwn|official|operator|caltrans|massgis)/.test(source)) return 0;
    if (source === "narn") return 1;
    if (source === "gtfs-shape") return 2;
    return 3;
  };
  const partFamily = new Map(parts.map((part) => [partKey(part), railFamily(part.kind)]));
  const partRank = new Map(
    parts
      .map((part) => ({
        key: partKey(part),
        order: [
          KIND_PRIORITY.indexOf(part.kind) < 0 ? KIND_PRIORITY.length : KIND_PRIORITY.indexOf(part.kind),
          sourcePriority(part.geometrySource),
          -metrics.get(partKey(part)).total,
        ],
      }))
      .sort((a, b) => firstDifference(a.order, b.order) || a.key.localeCompare(b.key))
      .map((entry, index) => [entry.key, index]),
  );
  // Which display classes are ever found running beside which. A class may
  // only be flattened onto one lane if that lane is still free of everyone it
  // shares a corridor with — flattening two of them onto the same lane would
  // hide one under the other, which is the thing lanes exist to prevent.
  const adjacency = new Map();
  for (const part of parts) {
    if (!part.emitsRows) continue;
    const metric = metrics.get(partKey(part));
    // Who runs beside this part, and where across it, at every sample. The
    // ranking is a second pass because a lateral read at one sample is not
    // usable evidence: two strokes the corridor ledger has reconciled weave
    // over each other every few hundred metres, and a rank taken off a single
    // crossing throws the line to the far side of the bundle and back.
    const neighbours = metric.samples.map((sample) => {
      const [cx, cy] = cell(sample.point);
      const partners = new Map();
      const partnerParts = new Map();
      for (let dx = -1; dx <= 1; dx += 1)
        for (let dy = -1; dy <= 1; dy += 1)
          for (const other of grid.get(`${cx + dx}|${cy + dy}`) || []) {
            if (other.part === part) continue;
            const gap = distanceMeters(sample.point, other.point);
            if (gap > NEAR_METRES) continue;
            const otherKey = partKey(other.part);
            const nearest = partnerParts.get(otherKey);
            if (!nearest || gap < nearest.gap)
              partnerParts.set(otherKey, {
                partKey: otherKey,
                lineId: other.part.lineId,
                partIndex: other.part.partIndex,
                measure: other.measure,
                lateral: lateralMetres(sample, other.point),
                gap,
              });
            if (other.part.displayClass === part.displayClass) continue;
            const held = partners.get(other.part.displayClass);
            if (!held || gap < held.gap)
              partners.set(other.part.displayClass, { ...other, gap });
          }
      // Measured in the part's OWN direction, which is the one frame that
      // cannot turn round between one sample and the next — the smoothing pass
      // below averages these, and an average is only meaningful while the
      // frame holds still. The corridor's shared frame is chosen at ranking
      // time and these are turned into it there.
      const laterals = new Map();
      const along = new Map();
      const partLaterals = new Map(
        [...partnerParts].map(([key, held]) => [key, held.lateral]),
      );
      for (const other of partners.values()) {
        laterals.set(
          other.part.displayClass,
          lateralMetres(sample, other.point),
        );
        along.set(
          other.part.displayClass,
          sample.tangent[0] * other.tangent[0] +
            sample.tangent[1] * other.tangent[1] >=
            0
            ? 1
            : -1,
        );
      }
      for (const key of laterals.keys()) {
        const held = adjacency.get(part.displayClass) || new Set();
        held.add(key);
        adjacency.set(part.displayClass, held);
      }
      return { laterals: partLaterals, along, partnerParts, classLaterals: laterals };
    });
    // The class-keyed laterals drive the lanes; the part-keyed ones drive
    // the follows. Both are smoothed over whole runs.
    const smoothedPartLaterals = smoothedNeighbourLaterals(neighbours);
    neighbours.forEach((held) => {
      held.laterals = held.classLaterals;
    });

    const smoothedLaterals = smoothedNeighbourLaterals(neighbours);

    // Follow runs: at each sample, the best-ranked partner PART whose
    // smoothed lateral is within the snap distance and that outranks this
    // part — kept while it stays eligible, so a run does not hop between two
    // partners that are both in range.
    const selfRank = partRank.get(partKey(part)) ?? Infinity;
    const followRuns = [];
    metric.samples.forEach((sample, index) => {
      const laterals = smoothedPartLaterals[index];
      const eligible = new Set();
      for (const [key, lateral] of laterals)
        if (
          Math.abs(lateral) <= FOLLOW_MAX_MEDIAN_METRES &&
          (partRank.get(key) ?? Infinity) < selfRank &&
          partFamily.get(key) === railFamily(part.kind)
        )
          eligible.add(key);
      const previous = followRuns[followRuns.length - 1];
      let chosen = null;
      if (previous && previous.partKey && eligible.has(previous.partKey))
        chosen = previous.partKey;
      else
        for (const key of eligible)
          if (!chosen || (partRank.get(key) ?? Infinity) < (partRank.get(chosen) ?? Infinity))
            chosen = key;
      const partner = chosen ? neighbours[index].partnerParts.get(chosen) : null;
      if (previous && previous.partKey === (chosen ?? null)) {
        previous.to = sample.measure;
        if (partner) previous.canonTo = partner.measure;
        return;
      }
      followRuns.push({
        partKey: chosen ?? null,
        lineId: partner?.lineId,
        partIndex: partner?.partIndex,
        from: sample.measure,
        to: sample.measure,
        canonFrom: partner?.measure,
        canonTo: partner?.measure,
      });
    });
    for (const run of followRuns) {
      if (!run.partKey || run.to - run.from < FOLLOW_MIN_RUN_METRES) continue;
      follows.push([
        part.lineId,
        part.partIndex,
        Number(run.from.toFixed(1)),
        Number(run.to.toFixed(1)),
        run.lineId,
        run.partIndex,
        Number(run.canonFrom.toFixed(1)),
        Number(run.canonTo.toFixed(1)),
      ]);
    }
    const states = metric.samples.map((sample, index) => {
      const laterals = smoothedLaterals[index];
      if (!laterals.size) return { lane: 0, measure: sample.measure };
      // Every member ranks the corridor in its OWN direction, and no shared
      // frame is needed for them to agree. Two strokes running together read
      // each other's side as exact opposites when they are digitised the same
      // way and as the same side when they are digitised against each other —
      // which is precisely the pair of answers that puts them on opposite
      // sides of the corridor once each applies its own line-offset. A shared
      // frame was tried and could not be defined: a corridor pointing due east
      // has no north to canonicalise against, and a display class that covers
      // several strokes has no one direction to lend.
      const ranked = [
        { key: part.displayClass, lateral: 0 },
        ...[...laterals].map(([key, lateral]) => ({
          key,
          lateral: rankingLateral(
            lateral,
            part.displayClass,
            key,
            neighbours[index].along.get(key),
          ),
        })),
      ].sort((a, b) => a.lateral - b.lateral || a.key.localeCompare(b.key));
      const rank = ranked.findIndex((member) => member.key === part.displayClass);
      return { lane: rank - (ranked.length - 1) / 2, measure: sample.measure };
    });

    const runs = [];
    for (const state of smoothedLaneStates(states)) {
      const previous = runs[runs.length - 1];
      if (previous && previous.lane === state.lane) previous.to = state.measure;
      else runs.push({ lane: state.lane, from: previous ? previous.to : 0, to: state.measure });
    }
    if (runs.length) runs[runs.length - 1].to = metric.total;

    for (let index = 1; index < runs.length - 1; ) {
      const before = runs[index - 1];
      const gap = runs[index];
      const after = runs[index + 1];
      if (!gap.lane && before.lane === after.lane && gap.to - gap.from < BRIDGE_METRES) {
        before.to = after.to;
        runs.splice(index, 2);
      } else index += 1;
    }

    const stationMeasures = (part.stationPoints || [])
      .map((station) => {
        let best = Infinity;
        let measure = 0;
        part.coordinates.forEach((point, index) => {
          const gap = distanceMeters(station, point);
          if (gap < best) {
            best = gap;
            measure = metric.cumulative[index];
          }
        });
        return best <= 200 ? measure : null;
      })
      .filter((value) => value != null)
      .sort((a, b) => a - b);

    let previousEnd = 0;
    const partRows = [];
    for (const run of runs) {
      if (!run.lane || run.to - run.from < MIN_RUN_METRES) continue;
      let from = run.from;
      let to = run.to;
      const before = stationMeasures.filter((measure) => measure <= from).at(-1);
      const after = stationMeasures.find((measure) => measure >= to);
      if (before != null && from - before <= STATION_SNAP_METRES) from = before;
      if (after != null && after - to <= STATION_SNAP_METRES) to = after;
      from = Math.max(previousEnd, from);
      previousEnd = to;
      if (to - from < MIN_RUN_METRES) continue;
      partRows.push([from, to, run.lane]);
    }

    measured.push({ part, total: metric.total, partRows });
  }

  // One lane for a whole DISPLAY CLASS wherever the corridors it runs in agree
  // on one. Two decisions come out of this at once, and they are the same
  // decision: a part with a single lane is a single drawn feature, and a single
  // drawn feature cannot come apart; and every stroke of one class holds the
  // same lane, so the four services New York paints orange stay one orange
  // line down Sixth Avenue instead of fanning into four. The lane a class keeps
  // past the end of its corridors costs it a couple of pixels against its
  // surveyed position — over stretches where nothing runs beside it to be
  // measured against — and buys back every seam a second lane would open.
  const byClass = new Map();
  for (const held of measured) {
    const bucket = byClass.get(held.part.displayClass) || [];
    bucket.push(held);
    byClass.set(held.part.displayClass, bucket);
  }
  // Longest first, so where two classes want the same lane the one with more
  // corridor behind it keeps it and the other keeps its measured stretches.
  const flattened = new Map();
  const ordered = [...byClass].map(([displayClass, bucket]) => {
    const lengthByLane = new Map();
    for (const held of bucket)
      for (const [from, to, lane] of held.partRows)
        lengthByLane.set(lane, (lengthByLane.get(lane) || 0) + (to - from));
    const lanedLength = [...lengthByLane.values()].reduce(
      (sum, held) => sum + held,
      0,
    );
    const dominant = [...lengthByLane.entries()].sort(
      (a, b) => b[1] - a[1] || Math.abs(a[0]) - Math.abs(b[0]) || a[0] - b[0],
    )[0];
    return { displayClass, bucket, dominant, lanedLength };
  });
  ordered.sort(
    (a, b) => b.lanedLength - a.lanedLength ||
      a.displayClass.localeCompare(b.displayClass),
  );
  for (const { displayClass, bucket, dominant, lanedLength } of ordered) {
    const taken = [...(adjacency.get(displayClass) || [])].some(
      (other) => flattened.get(other) === dominant?.[0],
    );
    const collapsed =
      !!dominant &&
      !taken &&
      dominant[1] >= DOMINANT_LANE_SHARE * lanedLength;
    if (collapsed) flattened.set(displayClass, dominant[0]);
    for (const held of bucket) {
      if (collapsed) {
        rows.push([
          held.part.lineId,
          held.part.partIndex,
          0,
          Number(held.total.toFixed(1)),
          dominant[0],
        ]);
        continue;
      }
      for (const [from, to, lane] of held.partRows)
        rows.push([
          held.part.lineId,
          held.part.partIndex,
          Number(from.toFixed(1)),
          Number(to.toFixed(1)),
          lane,
        ]);
    }
  }
  rows.sort((a, b) =>
    a[0].localeCompare(b[0]) || a[1] - b[1] || a[2] - b[2] || a[3] - b[3]);
  const merged = [];
  for (const row of rows) {
    const previous = merged[merged.length - 1];
    if (
      previous &&
      previous[0] === row[0] &&
      previous[1] === row[1] &&
      previous[4] === row[4] &&
      row[2] <= previous[3] + SAMPLE_METRES
    ) previous[3] = Math.max(previous[3], row[3]);
    else merged.push(row.slice());
  }
  follows.sort((a, b) =>
    a[0].localeCompare(b[0]) || a[1] - b[1] || a[2] - b[2]);
  return { rows: merged, follows };
}

const reviewed = fs.existsSync(SHARED_CORRIDORS)
  ? JSON.parse(fs.readFileSync(SHARED_CORRIDORS, "utf8"))
  : { corridors: [] };
const excludedLineIds = new Set(
  reviewed.displayLanePolicy?.excludedLineIds || [],
);
// The reviewed render-group policy. Its absence is a broken checkout, not a
// default to fall back on: without it the colour rule silently regains the
// power to decide identity, and four unrelated MTA railways become one lane.
if (!fs.existsSync(RENDER_GROUPS))
  throw new Error(`missing reviewed render-group policy: ${RENDER_GROUPS}`);
const renderGroups = JSON.parse(fs.readFileSync(RENDER_GROUPS, "utf8"));
if (renderGroups.format !== "jtm-na-render-groups-v1")
  throw new Error(`unexpected render-group policy format: ${renderGroups.format}`);
// The reviewed alignment releases (make-display-releases.py): intervals the
// package gate withheld that were measured again against OpenStreetMap and
// found consistent. Copied here so both renderers read one artefact.
const releasesByRegion = {};
if (fs.existsSync(DISPLAY_RELEASES)) {
  const releases = JSON.parse(fs.readFileSync(DISPLAY_RELEASES, "utf8"));
  if (releases.format !== "jtm-display-releases-v1")
    throw new Error(`unexpected display-releases format: ${releases.format}`);
  for (const row of releases.releases || []) {
    if (!["A", "C"].includes(row.verdict)) continue;
    (releasesByRegion[row.region] ||= []).push([row.lineId, row.interval]);
  }
}
const byRegion = {};
const followsByRegion = {};
for (const region of REGIONS) {
  const pkg = JSON.parse(fs.readFileSync(path.join(RAIL_DIR, `${region}-2025.json`), "utf8"));
  const derived = region === "us" || region === "ca"
    ? deriveNorthAmericanRows(pkg, reviewed, excludedLineIds, renderGroups, releasesByRegion)
    : { rows: pkg.lanes || [], follows: [] };
  byRegion[region] = derived.rows;
  if (derived.follows.length) followsByRegion[region] = derived.follows;
  process.stdout.write(
    `${region}: ${derived.rows.length} lane stretches, ${derived.follows.length} follow runs\n`,
  );
}

fs.writeFileSync(OUTPUT, `${JSON.stringify({
  format: "jtm-display-lanes-v1",
  northAmericaGrouping: ["operator", "color"],
  northAmericaRenderGroups: "na-render-groups.json",
  northAmericaRenderGroupsReviewedAt: renderGroups.reviewedAt,
  excludedOperators: [...EXCLUDED_OFFSET_OPERATORS],
  excludedLineIds: [...excludedLineIds].sort(),
  reviewedSharedCorridors: "shared-corridors.json",
  byRegion,
  // `[lineId, partIndex, fromMetres, toMetres, canonicalLineId,
  //   canonicalPartIndex, canonicalFromMetres, canonicalToMetres]`: over this
  // stretch the line is drawn from the canonical part's alignment (measured
  // along that part, reversed when the two are digitised against each
  // other), then offset into its own lane. See FOLLOW_MAX_MEDIAN_METRES.
  followsByRegion,
  // `[lineId, intervalIndex]` pairs released from the alignment gate for
  // display only, with their evidence in display-releases.json.
  releasedIntervalsByRegion: releasesByRegion,
})}\n`);
