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
 *
 * This script also emits `partsByRegion`: one row per web display part
 * (rail-network.js's displayPartsForLine, the function that decides how many
 * strokes a branching/retracing line comes apart into), for every region.
 * build-display-network.py's own chain builder used to re-derive its own
 * splitting rules from the raw compact-v1 intervals — a second implementation
 * that silently disagreed with displayPartsForLine's part count for any line
 * with a branch, a retrace, or a reversal, dropping that line's lane/follow
 * rows past the last chain it managed to build. `partsByRegion` closes that
 * gap by naming, for a part that reduces to one plain run of whole raw
 * intervals with no branch/retrace/reversal cut inside it, exactly which
 * intervals: `[lineId, partIndex, firstIntervalIndex, lastIntervalIndex,
 * vertexCount, totalMetres]`. Python can then decode and concatenate those
 * intervals itself (it already owns that decoder) and knows its chain is
 * the web's part, because the two are built from the same interval range.
 *
 * A part that is NOT a plain run — an extraSegments row, a branch's lead-in
 * copied off a neighbouring part's own tail, a loop's wrap seam, anything
 * displayPartsForLine had to reconstruct rather than just concatenate — has
 * no faithful interval range to give. Its row carries `firstIntervalIndex =
 * lastIntervalIndex = -1`, a 7th element `kind` naming why (`"extra-segment"`,
 * `"loop"`, `"complex"`), and an 8th element: the part's own final vertex
 * coordinates, copied straight out of displayPartsForLine's return value.
 * Python builds that one chain directly from the copy instead of trying to
 * re-derive it, so every web part still gets exactly one native chain,
 * whatever shape it is — the "smallest faithful encoding" here is per-part,
 * not per-line: most parts are a five-integer interval range, a minority
 * carry their own geometry, and only a genuinely absent or stale
 * partsByRegion (schema drift, a checkout mid-migration) makes Python fall
 * back to its own from-scratch interval splitter for a line, logged when it
 * does. Either way, a fail-closed guard — not a silent drop — is what
 * catches the two ever disagreeing about how many parts a line has: see
 * `partRowsForLine` below and `app/public/rail/README.md`.
 *
 * Every row also carries a 9th element: the part's WITHHELD SPANS — the
 * alignment-gate-blocked stretches both renderers draw dashed and dimmed —
 * as `[[fromMetres, toMetres], ...]` on that part's own measure space, or
 * `[]` when the gate blocked nothing this part draws. A plain row pads
 * slots 6 and 7 with nulls to reach it.
 *
 * These are not re-derived either: they are `coordinates.withheld`, which
 * rail-network.js's `withheldSpansForPart` measured with `partMeasures` on
 * the part's FINAL vertices — after grooming and station-approach rebuilding
 * — and which survives into `network.segments.features` because
 * `geometryForParts` puts the displayParts arrays themselves into the
 * feature geometry. Python used to re-derive these too, and for a plain row
 * it did so by accumulating RAW interval lengths, which are measured before
 * grooming shortens the geometry: on the shipped packages that left the dash
 * edges of eight parts off the web's by up to 647 m (us|amtrak-silver-meteor
 * part 0). Reading the web's own answer closes that by construction, and
 * closes it for both row kinds at once — the embedded path already agreed
 * with the web to 0.0 m, because it measures the same final vertices.
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
// One reviewed render-group policy per PROFILE, not one per world. North
// America and Japan disagree about what identity even is: the NA networks
// brand by operator + published route colour, and Japan brands by operator +
// official line name, because several Japanese operators paint every line
// they own one single hex (小田急電鉄, 阪神電気鉄道, 京浜急行電鉄 — and 京王電鉄
// paints six). Keeping the two policies in two files means neither review can
// silently acquire the other's default; each file names the regions it
// governs in its own `scope`.
const RENDER_GROUPS = path.join(RAIL_DIR, "na-render-groups.json");
const JP_RENDER_GROUPS = path.join(RAIL_DIR, "jp-render-groups.json");
const DISPLAY_LOOPS = path.join(RAIL_DIR, "display-loops.json");
const DISPLAY_RELEASES = path.join(RAIL_DIR, "display-releases.json");
const DISPLAY_HUBS = path.join(RAIL_DIR, "display-hubs.json");
const REGIONS = ["jp", "tw", "hk", "mo", "kr", "us", "ca"];

const SAMPLE_METRES = 25;
const NEAR_METRES = 45;
const MIN_RUN_METRES = 3000;
// MIN_RUN_METRES exists to keep a brief CROSSING from qualifying as a real
// parallel corridor — noise, not evidence. It is the wrong gate for a run
// that is not near a neighbour but ON it: two railways measured within
// COINCIDENT_METRES of each other (see rankingLateral) that `followAllowed`
// forbids from following one another are, for however long that lasts, the
// same physical track digitised twice. Dropping that run for being short
// does not make the two railways separate again — it puts both strokes back
// on lane 0 with zero screen offset for exactly the stretch where they need
// one most. The independent jp lane-pass review found 168 such pairs,
// several of them literally invisible (both lanes 0) over runs of a
// kilometre or more. COINCIDENT_MIN_RUN_METRES is the floor for THAT run
// only, matched to the review's own sweep threshold for "long enough to be
// real" rather than to MIN_RUN_METRES's much larger "long enough to not be
// a crossing" bar.
const COINCIDENT_MIN_RUN_METRES = 500;
const BRIDGE_METRES = 12000;
const STATION_SNAP_METRES = 2000;
const CELL_DEGREES = 0.00055;
// Family-window edges (deriveFamilyWindows) snap much tighter than a lane
// run's STATION_SNAP_METRES above: a lane run is choosing where a screen
// offset may safely start, but a family window is choosing where one
// family member stops drawing its own stroke and another starts drawing
// the shared one, and that handoff has to land ON the junction station, not
// a couple of blocks short of it — a visible seam either way. 60 m is a
// platform's length, not a corridor's.
const FAMILY_WINDOW_STATION_SNAP_METRES = 60;
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
// Below this a stroke that merely crosses another for a block or two would
// otherwise qualify as "following" it. A branch and the trunk it is a
// published subset of are exempt from this one (see `isKin`): a short-turn
// streetcar variant can be shorter than this whole window, and it shares its
// trunk's track for its entire length by definition, not by measurement.
const FOLLOW_MIN_RUN_METRES = 1000;
// Nobody is excluded from the corridor pass. Amtrak and VIA share their whole
// eastern network with commuter operators, and drawing them on the commuter
// centreline hid one railway under the other wherever they run together.
const EXCLUDED_OFFSET_OPERATORS = new Set();

// How far beyond a hub window a member is probed to see whether its own
// geometry has actually left the trunk's alignment yet. Long enough that a
// platform throat's own curvature does not read as a departure, short enough
// that the probe still lands inside the same physical junction the hub names.
const HUB_LOOKOUT_METRES = 600;
// A probe reads as "diverged" only once it clears ordinary corridor noise —
// well beyond FOLLOW_MAX_MEDIAN_METRES (25 m), so two tracks a survey's
// width apart inside the throat are never mistaken for a branch splitting.
const HUB_DIVERGE_METRES = 40;
// How close a candidate's OWN geometry has to come to the trunk's own
// alignment, somewhere in the hub window, to count as a genuine hub member —
// as opposed to merely passing within the hub's (much larger) radius of its
// centre point. Downtown terminals cluster close together (Chicago's Union
// Station, LaSalle Street Station and Millennium Station are all under 2 km
// apart; the Loop is under 1 km from Union), so a hub radius wide enough to
// span one terminal's own approach throat is routinely wide enough to also
// touch a neighbouring, physically unrelated terminal's throat or an
// elevated line several streets over. Membership is decided by nearness to
// the TRACK, not nearness to the STATION POINT.
const HUB_MEMBER_METRES = 60;

// `na-render-groups.json` renamed its colour/identity map from `groups` to
// `families` in the jtm-na-render-groups-v2 schema (adds `networkId` and
// `mode` per family, and a structured `colorSource` citation). Both readers
// accept `families`; `groups` is read for one release with a deprecation
// warning so a checkout mid-migration does not fail closed.
let warnedDeprecatedGroups = false;
function renderGroupFamilies(renderGroups) {
  if (renderGroups.families) return renderGroups.families;
  if (renderGroups.groups) {
    if (!warnedDeprecatedGroups) {
      console.warn(
        "na-render-groups.json: reading deprecated `groups` — rename to `families` " +
          "(jtm-na-render-groups-v2). `groups` support will be removed in a future release.",
      );
      warnedDeprecatedGroups = true;
    }
    return renderGroups.groups;
  }
  return {};
}

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
//
// Japan takes the OTHER branch below (`policy.profile === "route-preserving"`,
// jp-render-groups.json). There the default may not be operator + colour at
// all: 小田急電鉄, 阪神電気鉄道 and 京浜急行電鉄 each paint EVERY line they own one
// single hex, and 京王電鉄 paints six, so the North American default would
// collapse a whole operator's network onto one stroke. The Japan key is
// operator + the line's own official (N02) name — the identity
// japan_parallel_rail_rendering_rules.md gives a DisplayLine, "the public map
// name", and the identity rules.md §5.2 calls route-preserving. It is exactly
// the package lineId with its geometry-part suffixes stripped, so the -2/-3
// branch-service splits and the -p1/-p2 disjoint-geometry pieces of ONE
// railway share one key, and two different published lines never do.
function displayClassKey(line, renderGroups) {
  const explicit = renderGroups?.byLineId?.[line?.id || line?.lineId];
  if (explicit) return `group\0${explicit}`;
  if (renderGroups?.policy?.profile === "route-preserving") {
    // `operator` is the line row's own display name and `name` its official
    // line name; both are the strings the package build derived the lineId
    // from. Kept in their own case (Japanese has none) — lower-casing an
    // ASCII operator like "Osaka Metro" here would only make this key
    // disagree with the render-group ids the reviewed file already names.
    const operator = String(line?.operator || "").trim();
    const name = String(line?.name || "").trim();
    if (!operator || !name) return `unknown\0${line?.id || line?.lineId || ""}`;
    return `group\0${operator}:${name}`;
  }
  const operator = String(line?.operator || "").trim().toLocaleLowerCase("en-US");
  const color = String(line?.color || "").trim().toLocaleLowerCase("en-US");
  // A missing operator is not evidence that two records belong to one company.
  // Keep such records distinct rather than silently merging unrelated railways.
  if (!operator) return `unknown\0${line?.id || line?.lineId || ""}`;
  return `${operator}\0${color}`;
}

// The lineId of the railway a geometry-part row belongs to: the package build
// splits one N02 railway into several line rows — `-2`/`-3`/`-4`/`-5` for the
// branch services it cuts at surveyed junctions, `-p1`/`-p2` for disjoint
// geometry pieces of one line — and those rows are parts of one railway, not
// separate published lines. North America records the same relationship in an
// explicit `branchOf` field; the Japanese package has none (measured: 0 of 652
// jp lines carry `branchOf`), and encodes it in the id suffix instead. Both
// spellings feed `isKin` below.
function baseLineId(lineId) {
  let id = String(lineId || "");
  for (;;) {
    const stripped = id.replace(/-(?:\d+|p\d+)$/, "");
    if (stripped === id) return id;
    id = stripped;
  }
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

// A part's withheld spans, at the 0.1 m build-display-network.py already
// writes them to disk at. Rounding here rather than shipping raw doubles
// keeps the row a diffable integer-ish pair, and 0.1 m is four orders of
// magnitude below the dash period these spans are drawn with.
function roundedSpans(spans) {
  return spans.map((span) => [
    Number(span[0].toFixed(1)),
    Number(span[1].toFixed(1)),
  ]);
}

// The same spans on a part that has just been reversed to the canonical
// winding. Every measure along a part mirrors when the part is walked from
// the other end — `[from, to]` becomes `[total - to, total - from]` — and
// the runs come back in the opposite order, so the list is reversed to stay
// ascending. This is the one place the row can disagree with
// rail-network.js on purpose: the web derives its own, unreversed parts and
// never reads `partsByRegion`, so a reversed part's spans must be stated in
// the direction the native builder will actually walk it.
function mirroredSpans(spans, totalMetres) {
  return spans
    .map((span) => [totalMetres - span[1], totalMetres - span[0]])
    .reverse();
}

// A part's own station measures, nearest-vertex-snapped onto its cumulative
// ruler. Shared by the lane-run snapping pass below (STATION_SNAP_METRES)
// and deriveFamilyWindows (FAMILY_WINDOW_STATION_SNAP_METRES) — both are
// "where is the junction station on THIS part's own ruler" questions, just
// with different snap tolerances for different purposes.
function stationMeasuresForPart(part, metric) {
  return (part.stationPoints || [])
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

// Point and unit tangent at an arbitrary measure along a part's own raw
// coordinates, on the same ruler as `cumulativeMeasures`/`pointAt`. Used by
// the hub pass to probe a member's geometry at exact metre offsets that do
// not necessarily land on one of `samplesFor`'s fixed 25 m samples.
function pointAndTangent(coordinates, cumulative, measure) {
  const found = pointAt(coordinates, cumulative, measure);
  const a = coordinates[found.index];
  const b = coordinates[Math.min(found.index + 1, coordinates.length - 1)];
  const lat = ((a[1] + b[1]) / 2) * (Math.PI / 180);
  const dx = (b[0] - a[0]) * Math.cos(lat);
  const dy = b[1] - a[1];
  const norm = Math.hypot(dx, dy) || 1;
  return { point: found.point, tangent: [dx / norm, dy / norm] };
}

// Coordinate key matching rail-network.js's own `coordinateKey` (no
// rounding). Station anchor coordinates are reused verbatim by
// `decodeIntervals` and are the one thing grooming (trimFoldedEnds /
// smoothMicroKinks in rail-network.js, both documented never to touch a
// platform anchor) never alters — so an exact string match of a part's own
// vertex against a station's [lon, lat] is proof that vertex IS that
// station's platform, not a coincidence of two unrelated points landing on
// the same float.
function anchorKey(point) {
  return `${point[0]},${point[1]}`;
}

// How many of a line's display parts are extraSegmentParts (rail-network.js)
// rather than chain/branch parts. extraSegmentParts is always appended AFTER
// the whole chain, so the trailing `extraSegmentPartCount` entries of a
// line's part list are exactly its extraSegments rows, in order — deterministic,
// no matching required. Mirrors extraSegmentParts's own filter exactly: a row
// with no geometry is recorded but never drawn, and both endpoints must
// resolve to a real station.
function extraSegmentPartCount(compactLine) {
  const rows = compactLine.extraSegments;
  if (!Array.isArray(rows)) return 0;
  const stations = compactLine.stations || [];
  let count = 0;
  for (const row of rows) {
    if (!row || !Array.isArray(row.geometry) || row.geometry.length < 2) continue;
    if (!stations[row.from] || !stations[row.to]) continue;
    count += 1;
  }
  return count;
}

// A part's own length may only ever come in SHORTER than the raw intervals
// it was built from (grooming removes redundant vertices, it never adds
// track), so the tolerance here only needs to absorb legitimate smoothing —
// generous enough for real corridors, tight enough that a branch's lead-in
// (which adds real, copied track) still trips it.
const ANCHOR_LENGTH_SLACK_METRES = 40;
const ANCHOR_LENGTH_SLACK_RATIO = 0.03;
const ANCHOR_LENGTH_OVERAGE_METRES = 1;

// The `partsByRegion` rows for one line: `[lineId, partIndex,
// firstIntervalIndex, lastIntervalIndex, vertexCount, totalMetres, null,
// null, withheldSpans]` for a part that reduces to one plain run of whole
// raw intervals, or `[lineId, partIndex, -1, -1, vertexCount, totalMetres,
// kind, coordinates, withheldSpans]` otherwise. See the file header for the
// rationale and app/public/rail/README.md for the on-disk shape.
//
// `displayPartsForLine`'s outer loop visits raw intervals 0..N-1 strictly in
// order and, absent a branch/retrace/reversal cut, only ever APPENDS a whole
// interval to the part it is building — a cut always closes the part and
// opens a new one from copied/reversed geometry instead (see the long
// comment above `displayPartsForLine` in rail-network.js). So a "plain" part
// is exactly one whose vertex chain runs, start to end with no vertices
// spilling past either end, between two station anchors whose station
// indices are found in strictly ascending order along the part — that shape
// cannot arise any other way. The length check below is the second gate: it
// catches a lead-in that touches two real, correctly-ordered anchors while
// still smuggling in extra track copied from a neighbouring part.
//
// `loopWinding` (present only for the continuous-stroke regions — see
// `CONTINUOUS_STROKE_REGIONS` below) normalises the direction a closed line's
// part is digitised in. rules.md §7.8 and the Japan policy's §6.5 both require
// a ring to have ONE fixed orientation that every consumer agrees on, because
// a lane index is only meaningful relative to a direction of travel: a ring
// digitised clockwise and the same ring digitised anticlockwise put "the
// outer track" on opposite sides of the stroke. Nothing in the package
// guarantees that direction — N02 hands each closed railway whichever way its
// source happened to be drawn — so the sign of the shoelace area is checked
// here and the part reversed when it is negative, making anticlockwise (in
// lon/lat, so "positive area") the canonical winding for every ring.
function partRowsForLine(compactLine, partsForLine, displayOverride, loopWinding) {
  const lineId = compactLine.id;
  // A reviewed shared corridor (shared-corridors.json) can merge station
  // coordinates and replace interval geometry for the DISPLAY pass — the
  // same `displayOverride` buildNetworkFromCompactPackage feeds
  // displayPartsForLine to build the very parts in `partsForLine`. Matching
  // station anchors against the line's own unmerged `stations` here would
  // silently fail to find them (the merged coordinate the part actually
  // carries is a different float), understating what is plain. Using the
  // same override keeps this function looking at exactly what
  // displayPartsForLine looked at.
  const stations = displayOverride?.stations || compactLine.stations || [];
  const stationKeyToIndex = new Map();
  const ambiguousStationKeys = new Set();
  stations.forEach((row, index) => {
    const key = anchorKey([row[2], row[3]]);
    if (stationKeyToIndex.has(key)) ambiguousStationKeys.add(key);
    else stationKeyToIndex.set(key, index);
  });
  const rawIntervals =
    displayOverride?.intervals ||
    RailNetwork.decodeIntervals({ ...compactLine, stations });
  const rawIntervalLength = rawIntervals.map((interval) => {
    let total = 0;
    for (let index = 1; index < interval.length; index += 1)
      total += distanceMeters(interval[index - 1], interval[index]);
    return total;
  });
  const extraCount = extraSegmentPartCount(compactLine);
  const trunkCount = partsForLine.length - extraCount;
  const isLoop = Boolean(compactLine.isLoop);
  const rows = [];
  partsForLine.forEach((coordinates, partIndex) => {
    const vertexCount = coordinates.length;
    const cumulative = cumulativeMeasures(coordinates);
    const rawTotalMetres = cumulative[cumulative.length - 1] || 0;
    const totalMetres = Number(rawTotalMetres.toFixed(1));
    // Slot 8, on every row shape: the alignment-gate-blocked stretches of
    // THIS part, exactly as rail-network.js measured them on these same
    // final vertices (`withheldSpansForPart`, reached here because
    // `geometryForParts` hands the displayParts arrays themselves to the
    // feature geometry, expando and all). Absent on a part the gate blocked
    // nothing on, and on every part of every per-lane region — those split
    // on a block instead of bridging it, so they never tag a vertex. See
    // the file header for why this is read rather than re-derived.
    let partWithheld = (coordinates.withheld || []).map((span) => span.slice());
    // A fallback row carries the part's own final vertex coordinates as an
    // 8th element — the one thing that IS guaranteed correct for a part with
    // no faithful interval range, since it is exactly what
    // displayPartsForLine produced, copied rather than re-derived. Python
    // still measures the chain on its own ruler from these vertices (it
    // does not trust `totalMetres` as authoritative), so "measured on the
    // chain's own ruler" still holds for these parts too; what it gives up
    // is decoding compact-v1 geometry itself for this one part, which — for
    // a branch lead-in built by copying and reversing another part's own
    // tail, or a retrace that only contributes part of an interval — is not
    // something raw interval geometry can reconstruct regardless.
    const fallback = (kind) => {
      rows.push([
        lineId, partIndex, -1, -1, vertexCount, totalMetres, kind, coordinates,
        roundedSpans(partWithheld),
      ]);
    };
    // extraSegmentParts is always the trailing `extraCount` entries.
    if (partIndex >= trunkCount) {
      fallback("extra-segment");
      return;
    }
    // A closed line's interval count equals its station count (the last
    // interval wraps the final station back to the first), which makes the
    // plain station-index arithmetic below ambiguous at the seam. Rare
    // enough (see loop line counts in the region packages) to fall back
    // wholesale rather than special-case.
    if (isLoop) {
      // Signed (shoelace) area of the ring in degrees^2. Sign only — the
      // magnitude is meaningless at this latitude scaling and never used.
      //
      // Only a part that CLOSES is normalised. `isLoop` is a property of the
      // railway, not of the part: displayPartsForLine cuts a closed line
      // wherever it retraces itself, so a loop with a stem (山万's
      // ユーカリが丘線) arrives here as two OPEN parts, and the shoelace sign of
      // an open chain is not a ring orientation — it is the sign of whatever
      // area the chain happens to enclose against the straight line back to
      // its own start, which flips on a chain that is barely bent at all.
      // Reversing those would also mirror the measures of the follow rows the
      // two parts take against each other where they share the stem.
      const closes =
        coordinates.length > 2 &&
        coordinates[0][0] === coordinates[coordinates.length - 1][0] &&
        coordinates[0][1] === coordinates[coordinates.length - 1][1];
      if (loopWinding && closes) {
        let twiceArea = 0;
        for (let index = 0; index < coordinates.length; index += 1) {
          const a = coordinates[index];
          const b = coordinates[(index + 1) % coordinates.length];
          twiceArea += a[0] * b[1] - b[0] * a[1];
        }
        if (twiceArea < 0) {
          coordinates = coordinates.slice().reverse();
          partWithheld = mirroredSpans(partWithheld, rawTotalMetres);
          loopWinding.reversed.push(`${lineId}#${partIndex}`);
        }
      }
      fallback("loop");
      return;
    }
    const matches = [];
    coordinates.forEach((point, vertexIndex) => {
      const key = anchorKey(point);
      if (ambiguousStationKeys.has(key)) return;
      const stationIndex = stationKeyToIndex.get(key);
      if (stationIndex == null) return;
      matches.push({ vertexIndex, stationIndex });
    });
    if (matches.length < 2) {
      fallback("complex");
      return;
    }
    const first = matches[0];
    const last = matches[matches.length - 1];
    // The matched anchors must bound the WHOLE part — vertices before the
    // first anchor or after the last would be a lead-in or a dangling
    // excursion, material a plain interval run never has.
    if (first.vertexIndex !== 0 || last.vertexIndex !== vertexCount - 1) {
      fallback("complex");
      return;
    }
    let ascending = true;
    for (let index = 1; index < matches.length; index += 1)
      if (matches[index].stationIndex <= matches[index - 1].stationIndex) ascending = false;
    if (!ascending) {
      fallback("complex");
      return;
    }
    const firstIntervalIndex = first.stationIndex;
    const lastIntervalIndex = last.stationIndex - 1;
    if (
      firstIntervalIndex < 0 ||
      lastIntervalIndex < firstIntervalIndex ||
      lastIntervalIndex >= rawIntervalLength.length
    ) {
      fallback("complex");
      return;
    }
    let rawSum = 0;
    for (let index = firstIntervalIndex; index <= lastIntervalIndex; index += 1)
      rawSum += rawIntervalLength[index];
    const slack = Math.max(ANCHOR_LENGTH_SLACK_METRES, rawSum * ANCHOR_LENGTH_SLACK_RATIO);
    if (totalMetres > rawSum + ANCHOR_LENGTH_OVERAGE_METRES || totalMetres < rawSum - slack) {
      fallback("complex");
      return;
    }
    // Slots 6 and 7 (`kind`, `coordinates`) are a fallback row's alone, and
    // are padded here rather than dropped so slot 8 means the same thing on
    // every row shape — a reader can ask one question ("is there a slot 8?")
    // instead of two.
    rows.push([
      lineId, partIndex, firstIntervalIndex, lastIntervalIndex, vertexCount, totalMetres,
      null, null, roundedSpans(partWithheld),
    ]);
  });
  return rows;
}

// The web's actual per-part coordinate lists, in partIndex order, for every
// line the network built a display feature for. `geometryForParts` (the
// function that produces the geometry these features carry) emits a
// MultiLineString whose `coordinates` array IS the `displayParts` array
// verbatim — one LineString per part, index-aligned — so round-tripping a
// feature through `coordinatesForFeature` recovers the true, final part list
// with no re-derivation of any kind.
function extractDisplayPartsByLine(network) {
  const byLine = new Map();
  for (const feature of network.segments.features || []) {
    const lineId = feature?.properties?.lineId;
    if (!lineId) continue;
    const held = byLine.get(lineId) || [];
    held.push(...coordinatesForFeature(feature));
    byLine.set(lineId, held);
  }
  return byLine;
}

// Every claim display-loops.json makes about a package is checkable against
// that package, so it is checked rather than trusted: a seam station that is
// not on the line, a `closed-line` entry for a line the package does not mark
// `isLoop`, or a `composite-ring` whose two halves do not actually meet at
// both named seams would each be a silent lie about topology — precisely the
// kind of thing a reviewed table exists to prevent, not to introduce.
function validateReviewedLoops(region, pkg, loops) {
  if (!loops.length) return;
  const lineById = new Map(pkg.lines.map((line) => [line.id, line]));
  const problems = [];
  for (const loop of loops) {
    const lineIds = loop.lineIds || [];
    if (!lineIds.length) problems.push(`${loop.id}: names no lineIds`);
    const lines = [];
    for (const lineId of lineIds) {
      const line = lineById.get(lineId);
      if (!line) problems.push(`${loop.id}: ${lineId} is not a line in ${region}-2025.json`);
      else lines.push(line);
    }
    const stationCodesFor = (line) => new Set(line.stations.map((row) => row[0]));
    if (loop.kind === "closed-line") {
      for (const line of lines)
        if (!line.isLoop)
          problems.push(
            `${loop.id}: declared closed-line but ${line.id} has no isLoop in the package`,
          );
      if (loop.seamStationCode)
        for (const line of lines) {
          if (!stationCodesFor(line).has(loop.seamStationCode))
            problems.push(
              `${loop.id}: seam station ${loop.seamStationCode} ` +
                `(${loop.seamStationName || "?"}) is not on ${line.id}`,
            );
          // Being somewhere on the line is not being the seam: the closed
          // part wraps its LAST vertex back onto its FIRST, so the one
          // station the ring is actually seamed at is stations[0] — the jp
          // package stores a closed line open, with the wrap as its final
          // interval (jp-osaka-loop: stations[0] = 桜ノ宮, and the 19th
          // interval wraps 京橋 back to it; a declared seam of 大阪, which is
          // merely a station midway round, passed this check for a release
          // while being the wrong station entirely). See D3.
          else if (line.stations[0]?.[0] !== loop.seamStationCode)
            problems.push(
              `${loop.id}: seam station ${loop.seamStationCode} ` +
                `(${loop.seamStationName || "?"}) is on ${line.id} but is not its ` +
                `stations[0] (${line.stations[0][0]}/${line.stations[0][1]}) — the closed ` +
                `part's own wrap seam, not merely a station somewhere on the ring`,
            );
        }
      if (loop.canonicalWinding !== "positive-signed-area")
        problems.push(
          `${loop.id}: closed-line entries must declare canonicalWinding ` +
            `"positive-signed-area" — that is the winding partRowsForLine enforces`,
        );
    } else if (loop.kind === "composite-ring") {
      if (lines.length < 2)
        problems.push(`${loop.id}: a composite ring needs at least two member lines`);
      for (const code of loop.seamStationCodes || [])
        for (const line of lines)
          if (!stationCodesFor(line).has(code))
            problems.push(`${loop.id}: seam station ${code} is not on ${line.id}`);
      if ((loop.seamStationCodes || []).length !== 2)
        problems.push(`${loop.id}: a composite ring is seamed at exactly two stations`);
    } else if (loop.kind === "not-a-ring" || loop.kind === "lasso") {
      for (const line of lines)
        if (line.isLoop)
          problems.push(
            `${loop.id}: declared ${loop.kind} but ${line.id} carries isLoop in the package`,
          );
    } else {
      problems.push(`${loop.id}: unknown loop kind "${loop.kind}"`);
    }
  }
  if (problems.length)
    throw new Error(
      `display-loops.json disagrees with ${region}-2025.json:\n  ${problems.join("\n  ")}`,
    );
}

function computePartsByRegionRows(pkg, network, reviewedSharedCorridors, loopWinding) {
  const displayPartsByLine = extractDisplayPartsByLine(network);
  const displayOverrides = RailNetwork.reviewedSharedCorridorOverrides(
    pkg,
    reviewedSharedCorridors,
  );
  // `network.segments.features` (what `extractDisplayPartsByLine` reads)
  // carries a feature for every line, including one with a serviceStatus
  // split — but a split line takes the legacy multi-feature branch in
  // rail-network.js (`continuous = !serviceSplit && displayContinuousStroke`)
  // and is never pushed into `strokeModel.lines`, because a dash rhythm for
  // the suspended stretch cannot be expressed on the single continuous
  // stroke that branch draws. `partsByRegion` exists so build-display-
  // network.py's chains match what the web engine actually draws — a row
  // for a line the engine builds as several plain (non-strokeModel)
  // features would tell Python to expect a chain nothing on the web side
  // ever renders that way.
  //
  // This ONLY matters for a line `drawsContinuousStroke` would otherwise
  // draw as strokeModel: tw/hk/mo/kr's per-lane regions never populate
  // strokeModel for ANY line (a structurally different rendering mode, not
  // an exception), so testing bare strokeModel membership here would wipe
  // partsByRegion for every one of their lines. Replicate the line-feature
  // builder's own `continuous` test instead, so only the serviceStatus-split
  // exception is caught. Report the skipped lines so a change to
  // serviceSplitForLine's own list is visible here too, not just as a
  // silent partsByRegion shrink. See D7.
  //
  // These are also the ONLY lines build-display-network.py may draw through
  // its non-continuous (per-lane) path instead of a continuous chain for a
  // continuous-stroke region: `excluded` below is emitted as this region's
  // `strokeExcludedByRegion` row set, one `[lineId, reason]` pair per line,
  // with `reason` the line's own package `serviceStatus` (e.g.
  // "substitute_bus", "partial_service_suspended") so Python can log why
  // without guessing at a naming convention (a whole-line exclusion need not
  // start with "partial_" — 美祢線 is a whole-line bus substitution recorded
  // as bare "substitute_bus").
  const skipped = [];
  const rows = [];
  for (const compactLine of pkg.lines) {
    const partsForLine = displayPartsByLine.get(compactLine.id) || [];
    if (!partsForLine.length) continue;
    if (RailNetwork.drawsContinuousStroke(compactLine, pkg)) {
      const line = network.lineById.get(compactLine.id);
      const serviceSplit = line && RailNetwork.serviceSplitForLine(line, compactLine);
      if (serviceSplit) {
        skipped.push([compactLine.id, String(compactLine.serviceStatus || "service-split")]);
        continue;
      }
    }
    rows.push(
      ...partRowsForLine(
        compactLine,
        partsForLine,
        displayOverrides.get(compactLine.id),
        loopWinding,
      ),
    );
  }
  if (skipped.length)
    console.warn(
      `partsByRegion: ${skipped.length} line(s) have display geometry but never enter ` +
        `strokeModel (serviceStatus split, legacy multi-feature branch) — no partsByRegion ` +
        `row emitted for them:\n  ${skipped.map(([id, reason]) => `${id} (${reason})`).join("\n  ")}`,
    );
  rows.sort((a, b) => a[0].localeCompare(b[0]) || a[1] - b[1]);
  skipped.sort((a, b) => a[0].localeCompare(b[0]));
  return { rows, excluded: skipped };
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

// ---------------------------------------------------------------------------
// Convergence hubs (display-hubs.json)
//
// The general pass above ranks lanes per DISPLAY CLASS, over a window at
// least MIN_RUN_METRES long, and may flatten a class onto one lane wherever
// DOMINANT_LANE_SHARE lets it. Both rules are right for a corridor and both
// are wrong for a hub: the convergence itself is shorter than MIN_RUN_METRES
// by construction, and a hub routinely bundles several parts of the SAME
// display class that the general pass never even compares — same-class
// parts are deliberately excluded from being neighbours above (a line must
// never fight its own repeated geometry for a lane), which also means two
// branches of one operator converging on one platform throat are never
// measured against each other and both default to lane 0.
//
// This pass runs once follows are final. For every hub it collects every
// part whose OWN geometry passes inside the hub's radius — the canonical
// line together with every follower, since a follower's real geometry stays
// within FOLLOW_MAX_MEDIAN_METRES of what it follows and so is normally
// inside the same radius too — then groups those parts by RENDER KEY
// (displayClassKey: the same identity the general pass above draws as one
// stroke) rather than by line. A hub is a place several corridors CROSS or
// MERGE, and what a reader sees there is one stroke per render key, not one
// per timetable line — five Amtrak services sharing #318cba are one bundled
// Amtrak lane through a throat exactly as they are one lane on the open
// corridor either side of it. Each class is ordered by branch-block (which
// side its members' own geometry departs to beyond the hub — majority vote
// across the class's members, a tie kept at "continue"), assigned ONE evenly
// spaced half-integer slot centred on zero (the same i-(n-1)/2 scheme the
// measured-lateral rank above already uses), and every member line of that
// class is written that same slot.
// The longest sub-interval of [from, to] that does NOT overlap any range
// already claimed by an earlier hub on this same part. Two named hubs can sit
// close enough (chicago-union and chicago-loop are under 1 km apart, and each
// has a multi-kilometre radius) that one part's geometry legitimately falls
// inside both radii; without this a part would get two independent, possibly
// overlapping, forced windows. Hubs therefore claim ground in the order they
// appear in display-hubs.json, first come first served, which is also why
// the more specific/major throat should usually be listed first.
function longestUnclaimed(from, to, claimedRanges) {
  if (!claimedRanges || !claimedRanges.length) return { from, to };
  const cuts = claimedRanges
    .filter((range) => range.to > from && range.from < to)
    .sort((a, b) => a.from - b.from);
  let cursor = from;
  let best = null;
  const consider = (a, b) => {
    if (b - a > 0 && (!best || b - a > best.to - best.from)) best = { from: a, to: b };
  };
  for (const range of cuts) {
    consider(cursor, Math.min(range.from, to));
    cursor = Math.max(cursor, range.to);
  }
  consider(cursor, to);
  return best;
}

function computeHubOverrides(parts, metrics, follows, hubs, grid) {
  const hubRowsByPart = new Map(); // partKey -> [{from, to, lane}]
  const report = [];
  if (!hubs || !hubs.length) return { hubRowsByPart, report };
  const partsByKey = new Map(parts.map((part) => [partKey(part), part]));
  const claimedByPart = new Map(); // partKey -> [{from, to}], across all hubs so far

  for (const hub of hubs) {
    // 1. Every part's own hub window: the contiguous stretch (in that part's
    // own metres) where its raw digitised geometry sits inside the radius,
    // trimmed back to whatever ground an earlier hub has not already claimed.
    const windows = new Map();
    for (const part of parts) {
      const metric = metrics.get(partKey(part));
      if (!metric) continue;
      let from = null;
      let to = null;
      for (const sample of metric.samples) {
        if (distanceMeters(sample.point, hub.centre) > hub.radiusMetres) continue;
        if (from == null) from = sample.measure;
        to = sample.measure;
      }
      if (from == null) continue;
      const window = longestUnclaimed(from, to, claimedByPart.get(partKey(part)));
      if (window) windows.set(partKey(part), window);
    }
    const memberKeys = [...windows.keys()];
    if (memberKeys.length < 2) continue; // nothing to separate at this hub

    // 2. Pick the reference/trunk part: whichever hub member the most other
    // members' follow rows name as canonical, over a range that actually
    // overlaps this hub's window. Ties go to the longest presence in the
    // hub, then to lineId, so the pick is reproducible run to run.
    const followCount = new Map();
    for (const row of follows) {
      const canonKey = `${row[4]}#${row[5]}`;
      const window = windows.get(canonKey);
      if (!window) continue;
      const lo = Math.min(row[6], row[7]);
      const hi = Math.max(row[6], row[7]);
      if (hi < window.from || lo > window.to) continue;
      followCount.set(canonKey, (followCount.get(canonKey) || 0) + 1);
    }
    // A declared trunk (display-hubs.json `trunkLineId`) wins outright over
    // both the follow-count auto-pick and a laneOrder-implied trunk: the
    // auto-pick is "whichever member the most followers name as canonical",
    // which is a fine default but is wrong wherever the hub's own busiest
    // corridor is not the one carrying the most FOLLOW rows (chicago-loop's
    // auto-pick lands on amtrak-hiawatha-service, not the CTA structure the
    // hub is actually named for). Falls through to the existing pickers when
    // the named line is not itself a member here (radius test failed it).
    let trunkKey = null;
    if (hub.trunkLineId) {
      trunkKey = memberKeys.find((key) => key.startsWith(`${hub.trunkLineId}#`)) || null;
    }
    if (!trunkKey && hub.laneOrder && hub.laneOrder.length) {
      for (const lineId of hub.laneOrder) {
        const found = memberKeys.find((key) => key.startsWith(`${lineId}#`));
        if (found) {
          trunkKey = found;
          break;
        }
      }
    }
    if (!trunkKey) {
      let best = null;
      for (const key of memberKeys) {
        const count = followCount.get(key) || 0;
        const window = windows.get(key);
        const span = window.to - window.from;
        if (
          !best ||
          count > best.count ||
          (count === best.count && span > best.span) ||
          (count === best.count && span === best.span && key < best.key)
        )
          best = { key, count, span };
      }
      trunkKey = best.key;
    }
    const trunkMetric = metrics.get(trunkKey);
    const trunkWindow = windows.get(trunkKey);

    // The slots below are ordered and measured entirely in the TRUNK's own
    // frame — every `side`/`measuredLateral` comes from probing a member's
    // real geometry against the trunk's own tangent, so the ordering itself
    // is unaffected by which way any member happens to be digitised. But a
    // member that FOLLOWS the trunk (`follows`, resolved to its root
    // canonical earlier) is rendered from the trunk's alignment, offset
    // using the trunk's own tangent — the same "canonical frame" the general
    // pass's cross-class collision fix above has to correct for. Writing the
    // hub's slot straight into that member's own-frame `lane` field is only
    // correct when the two frames agree; where the follow runs against the
    // trunk's direction they are mirror images, and the slot has to be
    // negated before it is written, or a member the hub placed firmly on one
    // side renders on the other and can land back on top of whichever
    // member the hub placed there instead.
    const reversedAgainstTrunk = (key, window) => {
      if (key === trunkKey) return false;
      const [lineId, partIndexRaw] = key.split("#");
      const partIndex = Number(partIndexRaw);
      const mid = (window.from + window.to) / 2;
      const row = follows.find(
        (candidate) =>
          candidate[0] === lineId &&
          candidate[1] === partIndex &&
          `${candidate[4]}#${candidate[5]}` === trunkKey &&
          candidate[2] <= mid &&
          candidate[3] >= mid,
      );
      return row ? row[7] < row[6] : false;
    };

    // Nearest trunk sample to an arbitrary point, searched only around the
    // measures that matter — the hub window plus the lookout either side —
    // so a probe never has to scan a transcontinental line's full profile.
    // Returns both the trunk-relative lateral (signed, for divergence) and
    // the plain gap (for the near-trunk membership test below).
    const nearestTrunkSample = (point, aroundLo, aroundHi) => {
      const loIndex = Math.max(0, Math.floor(aroundLo / SAMPLE_METRES) - 4);
      const hiIndex = Math.min(
        trunkMetric.samples.length - 1,
        Math.ceil(aroundHi / SAMPLE_METRES) + 4,
      );
      let bestSample = null;
      let bestGap = Infinity;
      for (let index = loIndex; index <= hiIndex; index += 1) {
        const sample = trunkMetric.samples[index];
        if (!sample) continue;
        const gap = distanceMeters(sample.point, point);
        if (gap < bestGap) {
          bestGap = gap;
          bestSample = sample;
        }
      }
      return { sample: bestSample, gap: bestGap };
    };
    const probeAgainstTrunk = (point, aroundLo, aroundHi) => {
      const { sample } = nearestTrunkSample(point, aroundLo, aroundHi);
      return sample ? lateralMetres(sample, point) : 0;
    };

    // 2.5. Drop any candidate whose own geometry never actually comes near
    // the trunk's alignment anywhere in the hub window — it merely shares
    // the hub's big radius around the centre point, not the corridor. The
    // trunk itself always passes. Uses the same spatial grid the general
    // pass builds its neighbour search on (CELL_DEGREES ~= 61 m, comfortably
    // bigger than HUB_MEMBER_METRES), so this is a bucket lookup rather than
    // a scan of the trunk's own samples for every candidate sample.
    for (const key of memberKeys.slice()) {
      if (key === trunkKey) continue;
      const metric = metrics.get(key);
      const window = windows.get(key);
      let near = false;
      for (const sample of metric.samples) {
        if (sample.measure < window.from || sample.measure > window.to) continue;
        const [cx, cy] = cell(sample.point);
        outer: for (let dx = -1; dx <= 1; dx += 1)
          for (let dy = -1; dy <= 1; dy += 1)
            for (const other of grid.get(`${cx + dx}|${cy + dy}`) || []) {
              if (partKey(other.part) !== trunkKey) continue;
              if (distanceMeters(sample.point, other.point) <= HUB_MEMBER_METRES) {
                near = true;
                break outer;
              }
            }
        if (near) break;
      }
      if (!near) {
        windows.delete(key);
        memberKeys.splice(memberKeys.indexOf(key), 1);
      }
    }
    if (memberKeys.length < 2) continue; // the trunk was alone after all

    // 3. Classify every member: which side its OWN geometry departs to
    // beyond the hub (left, continue, right), and its measured lateral
    // against the trunk at the start of its own window, used only as a
    // tie-break within a side.
    const entries = memberKeys.map((key) => {
      const part = partsByKey.get(key);
      const metric = metrics.get(key);
      const window = windows.get(key);
      if (key === trunkKey) return { key, part, side: 0, measuredLateral: 0, window };
      const startPoint = pointAndTangent(part.coordinates, metric.cumulative, window.from).point;
      const measuredLateral = probeAgainstTrunk(
        startPoint,
        trunkWindow.from - HUB_LOOKOUT_METRES,
        trunkWindow.to + HUB_LOOKOUT_METRES,
      );
      let side = 0;
      const forwardMeasure = Math.min(metric.total, window.to + HUB_LOOKOUT_METRES);
      if (forwardMeasure > window.to + 1) {
        const point = pointAndTangent(part.coordinates, metric.cumulative, forwardMeasure).point;
        const lateral = probeAgainstTrunk(
          point,
          trunkWindow.from - HUB_LOOKOUT_METRES,
          trunkWindow.to + HUB_LOOKOUT_METRES * 2,
        );
        if (Math.abs(lateral) >= HUB_DIVERGE_METRES) side = Math.sign(lateral);
      }
      if (!side) {
        const backwardMeasure = Math.max(0, window.from - HUB_LOOKOUT_METRES);
        if (backwardMeasure < window.from - 1) {
          const point = pointAndTangent(part.coordinates, metric.cumulative, backwardMeasure).point;
          const lateral = probeAgainstTrunk(
            point,
            trunkWindow.from - HUB_LOOKOUT_METRES * 2,
            trunkWindow.to + HUB_LOOKOUT_METRES,
          );
          if (Math.abs(lateral) >= HUB_DIVERGE_METRES) side = Math.sign(lateral);
        }
      }
      return { key, part, side, measuredLateral, window };
    });

    // 4. Group members by RENDER KEY — displayClassKey, the same identity the
    // general pass above draws as one stroke — not by line. Chicago Union's
    // five Amtrak services (one operator, one published colour) are one
    // render key and get ONE slot between them; metra-sws, metra-bnsf,
    // metra-hc and cta-blue-line each publish their own colour and so are
    // four more, separate, render keys.
    const classGroups = [];
    {
      const byClassKey = new Map();
      for (const entry of entries) {
        const classKey = entry.part.displayClass;
        let group = byClassKey.get(classKey);
        if (!group) {
          group = { classKey, members: [] };
          byClassKey.set(classKey, group);
          classGroups.push(group);
        }
        group.members.push(entry);
      }
      for (const group of classGroups) {
        // The side a CLASS departs to is the majority of its own members'
        // sides — one line of a multi-branch class diverging early does not
        // move the whole class's block, and a tie (as likely for a class
        // whose members split evenly left/right, or that never diverges at
        // all) is kept at "continue", the same default a single member gets.
        const counts = new Map();
        for (const member of group.members)
          counts.set(member.side, (counts.get(member.side) || 0) + 1);
        let bestCount = -1;
        let bestSides = [];
        for (const [side, count] of counts) {
          if (count > bestCount) {
            bestCount = count;
            bestSides = [side];
          } else if (count === bestCount) bestSides.push(side);
        }
        group.side = bestSides.length === 1 ? bestSides[0] : 0;
        group.measuredLateral =
          group.members.reduce((sum, member) => sum + member.measuredLateral, 0) /
          group.members.length;
      }
    }

    // 5. Order the CLASSES: manual laneOrder first — entries may name either
    // a class key directly or a lineId, resolved to whichever class that
    // line belongs to here — then branch-block, left before continue before
    // right, ties by the class's mean measured lateral, final tie by the
    // class key itself so the order is reproducible.
    let orderedClasses;
    if (hub.laneOrder && hub.laneOrder.length) {
      const byClassKey = new Map(classGroups.map((group) => [group.classKey, group]));
      const classKeyByLineId = new Map(
        entries.map((entry) => [entry.part.lineId, entry.part.displayClass]),
      );
      const named = [];
      const namedKeys = new Set();
      // A named line display-hubs.json expects to seat here that never made
      // it into `classGroups` — either its own geometry never entered the
      // hub radius at all (step 1's `windows`), or it entered but step 2.5
      // dropped it for never actually nearing the trunk's own alignment
      // (HUB_MEMBER_METRES) — is not a class the general pass quietly
      // handles instead: under `laneOrderOnly` that line is left on
      // whatever lane the general pass gave it, with no seam, no follow, and
      // no report entry naming the gap. A reviewed `unbundled` entry is the
      // only thing that may excuse a named line from seating; anything else
      // is the exact silent drop D5 found (中央線/総武線 at 東京), so it fails
      // the build instead.
      const unbundledReasons = new Map(
        (hub.unbundled || []).map((entry) => [entry.lineId, entry.reason]),
      );
      const unexplainedDrops = [];
      for (const item of hub.laneOrder) {
        const group = byClassKey.get(item) || byClassKey.get(classKeyByLineId.get(item));
        if (group) {
          if (!namedKeys.has(group.classKey)) {
            named.push(group);
            namedKeys.add(group.classKey);
          }
          continue;
        }
        if (!unbundledReasons.has(item)) unexplainedDrops.push(item);
      }
      if (unexplainedDrops.length)
        throw new Error(
          `display-hubs.json hub ${hub.id}: laneOrder names ${unexplainedDrops.join(", ")} but ` +
            `laneOrderOnly could not seat ${unexplainedDrops.length === 1 ? "it" : "them"} (no ` +
            `geometry in the hub radius, or never within HUB_MEMBER_METRES of the trunk). Either ` +
            `remove from laneOrder or record it under this hub's "unbundled" array with a reason.`,
        );
      const rest = classGroups
        .filter((group) => !namedKeys.has(group.classKey))
        .sort(
          (a, b) =>
            a.side - b.side ||
            a.measuredLateral - b.measuredLateral ||
            a.classKey.localeCompare(b.classKey),
        );
      // `laneOrderOnly` bundles ONLY the classes the review named and leaves
      // every other class inside the radius on the lane the general pass gave
      // it. A hub slot is `index - (n-1)/2`, so a hub that bundles n classes
      // spends |slot| up to (n-1)/2 — and the iOS renderer refuses |lane| > 8,
      // i.e. 17 classes. Tokyo Station's own throat sits inside a radius that
      // also contains a dozen unrelated railways passing through Marunouchi
      // and Yaesu on their own alignments; sweeping those into the bundle
      // would both blow the slot budget and claim a convergence that is not
      // there. rules.md §9.8 asks for exactly this shape of override — a
      // reviewed data-layer object, not a renderer special case.
      orderedClasses = hub.laneOrderOnly ? named : [...named, ...rest];
      if (hub.laneOrderOnly && orderedClasses.length < 2) continue;
    } else {
      orderedClasses = classGroups
        .slice()
        .sort(
          (a, b) =>
            a.side - b.side ||
            a.measuredLateral - b.measuredLateral ||
            a.classKey.localeCompare(b.classKey),
        );
    }

    // 6. Slots: i - (n-1)/2, centred on zero, one per CLASS. Every member
    // line of a class is written that same slot — a class with several
    // members still comes apart into one row per PART (each part keeps its
    // own window, since two lines of a class need not converge/diverge at
    // the same metre), but every one of those rows carries the class's one
    // slot, so the class remains one drawn stroke through the hub exactly as
    // it is one drawn stroke either side of it.
    const n = orderedClasses.length;
    const memberReport = [];
    const classReport = [];
    orderedClasses.forEach((group, index) => {
      const slot = index - (n - 1) / 2;
      classReport.push({
        classKey: group.classKey,
        slot,
        side: group.side,
        lineIds: [...new Set(group.members.map((member) => member.part.lineId))],
      });
      for (const entry of group.members) {
        const lane = reversedAgainstTrunk(entry.key, entry.window) ? -slot : slot;
        const held = hubRowsByPart.get(entry.key) || [];
        held.push({ from: entry.window.from, to: entry.window.to, lane });
        hubRowsByPart.set(entry.key, held);
        const claimed = claimedByPart.get(entry.key) || [];
        claimed.push({ from: entry.window.from, to: entry.window.to });
        claimedByPart.set(entry.key, claimed);
        memberReport.push({
          lineId: entry.part.lineId,
          partIndex: entry.part.partIndex,
          classKey: group.classKey,
          slot,
          side: entry.side,
          from: Number(entry.window.from.toFixed(1)),
          to: Number(entry.window.to.toFixed(1)),
        });
      }
    });
    report.push({ hubId: hub.id, name: hub.name, trunkKey, members: memberReport, classes: classReport });
  }
  return { hubRowsByPart, report };
}

// The lane a partKey held over a given measure window before the hub pass —
// "none" when the general pass never assigned that stretch a row at all, the
// same silent lane-0 default the renderer already applies. Used only for the
// per-hub report; never written to the emitted rows.
function priorLaneFor(priorRows, lineId, partIndex, from, to) {
  const midpoint = (from + to) / 2;
  const row = priorRows.find(
    (candidate) =>
      candidate[0] === lineId &&
      candidate[1] === partIndex &&
      candidate[2] <= midpoint &&
      candidate[3] >= midpoint,
  );
  return row ? row[4] : null;
}

// Splice the hub pass's forced rows into the final row list: trim whatever
// the general pass produced for a hub member back to the hub window's edges
// (splitting a plateau in two if the window falls in the middle of it, or
// simply dropping a stretch too short to be evidence, i.e. the collapsed
// class's own dominant lane over the rest of the part) and insert the hub's
// own row in its place. A part the hub pass never touches is returned
// byte-identical — this is the guard the task asks for.
function applyHubOverrides(rows, hubRowsByPart) {
  if (!hubRowsByPart.size) return rows;
  const byPart = new Map();
  for (const row of rows) {
    const key = `${row[0]}#${row[1]}`;
    if (!byPart.has(key)) byPart.set(key, []);
    byPart.get(key).push(row);
  }
  const touched = new Set(hubRowsByPart.keys());
  const out = [];
  for (const row of rows) {
    const key = `${row[0]}#${row[1]}`;
    if (!touched.has(key)) out.push(row);
  }
  for (const key of touched) {
    const [lineId, partIndexRaw] = key.split("#");
    const partIndex = Number(partIndexRaw);
    const overrides = hubRowsByPart
      .get(key)
      .slice()
      .sort((a, b) => a.from - b.from);
    let pieces = (byPart.get(key) || []).map((row) => ({ from: row[2], to: row[3], lane: row[4] }));
    for (const override of overrides) {
      const next = [];
      for (const piece of pieces) {
        if (override.to <= piece.from || override.from >= piece.to) {
          next.push(piece);
          continue;
        }
        if (override.from > piece.from) next.push({ from: piece.from, to: override.from, lane: piece.lane });
        if (override.to < piece.to) next.push({ from: override.to, to: piece.to, lane: piece.lane });
      }
      pieces = next;
    }
    pieces.push(...overrides);
    pieces.sort((a, b) => a.from - b.from);
    for (const piece of pieces)
      if (piece.to - piece.from > 0.05)
        out.push([lineId, partIndex, Number(piece.from.toFixed(1)), Number(piece.to.toFixed(1)), piece.lane]);
  }
  out.sort((a, b) => a[0].localeCompare(b[0]) || a[1] - b[1] || a[2] - b[2]);
  const merged = [];
  for (const row of out) {
    const previous = merged[merged.length - 1];
    if (
      previous &&
      previous[0] === row[0] &&
      previous[1] === row[1] &&
      previous[4] === row[4] &&
      row[2] <= previous[3] + SAMPLE_METRES
    )
      previous[3] = Math.max(previous[3], row[3]);
    else merged.push(row.slice());
  }
  return merged;
}

// A follower's own row is measured and offset in ITS OWN digitisation frame
// (see the "shared frame was tried and could not be defined" note above the
// lane-state pass): a class ranks its neighbours using its own tangent, and
// offsetting from its own geometry with that same tangent cancels out
// whichever way it happens to be digitised. A FOLLOW breaks that symmetry —
// the renderer substitutes the CANONICAL part's geometry before applying the
// offset, so the tangent actually doing the offsetting is the canonical's,
// not the follower's. Where the two run the same way (`canonTo > canonFrom`)
// the two tangents agree and the follower's own-frame lane is already the
// render-frame value. Where a follow runs AGAINST the canonical direction
// the tangents are mirror images, and the render-frame value is
// `-lane` — two followers whose own-frame lanes look distinct (say -0.5 and
// 0.5) can be the SAME slot once drawn from the canonical's alignment, and
// two that look identical can be genuinely apart. Comparing raw own-frame
// lanes, as a neighbour scan restricted to real geometric proximity does,
// misses exactly this: two branches of one canonical bundle that diverge
// long before they would ever appear as each other's geometric neighbour
// still end up drawn from the same alignment, at the same pixel offset, the
// moment both follow it.
//
// This pass runs once every follow has been resolved to its root canonical
// (see the re-pointing loop above). For every canonical part, it converts
// each follower's own-frame lane to the render-frame `slot` above, and looks
// for two DIFFERENT display classes whose slots collide over a real run —
// the same deadband a lane must hold before it counts as evidence elsewhere
// in this file. Same-class followers are left alone: two parts of one class
// sharing a slot is the single stroke that class is supposed to draw, not a
// collision. Classes are settled longest-canonical-footprint first, so an
// established corridor keeps its slot and whatever crosses it for a shorter
// stretch gives way, moving outward by half a lane at a time until it clears
// every class already holding that ground. A canonical with no cross-class
// collision anywhere returns no override at all, so every part it or its
// followers touch stays byte-identical.
const CROSS_CLASS_COLLISION_MIN_OVERLAP_METRES = 50;
// A half-lane step left two strokes 1.35 px apart at the render-frame gap
// this pass is meant to clear — still overlapping, not the "clear map the
// eye needs to read two railways as two" that RAILWAY_STYLE.parallelGapPx
// documents. A full lane step is what actually separates them.
const CROSS_CLASS_COLLISION_STEP = 1.0;

// Plain ordinal comparison, not `String.prototype.localeCompare` — a
// locale-dependent collator (Turkish "i", ligatures, accent folding) can
// order two class/line ids differently on different machines running this
// build, and the tie-break exists ONLY to make placement order
// reproducible, not to alphabetise for a reader.
function compareStrings(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

// The pieces of `rows` (each `[lineId, partIndex, from, to, lane]`, i.e. the
// `mergedRows` shape) that fall inside `[from, to]`, clipped to it, with
// every uncovered stretch filled at lane 0 (the centreline — what a part
// draws wherever no row names a lane) — so the returned list always spans
// the whole window with no gap, in order. Mirrors `lanePlateaus`' own
// gap-filling rule, just restricted to one sub-window instead of a part's
// whole length.
function windowPieces(rows, from, to) {
  const relevant = (rows || [])
    .filter((row) => row[3] > from && row[2] < to)
    .map((row) => ({ from: Math.max(row[2], from), to: Math.min(row[3], to), lane: row[4] }))
    .sort((a, b) => a.from - b.from);
  const pieces = [];
  let cursor = from;
  for (const row of relevant) {
    if (row.from > cursor) pieces.push({ from: cursor, to: row.from, lane: 0 });
    pieces.push(row);
    cursor = Math.max(cursor, row.to);
  }
  if (cursor < to) pieces.push({ from: cursor, to, lane: 0 });
  return pieces;
}

function resolveCrossClassFollowCollisions(mergedRows, follows, parts) {
  const classByLine = new Map(parts.map((part) => [part.lineId, part.displayClass]));
  const rowsByPart = new Map();
  for (const row of mergedRows) {
    const key = `${row[0]}#${row[1]}`;
    if (!rowsByPart.has(key)) rowsByPart.set(key, []);
    rowsByPart.get(key).push(row);
  }
  const laneAt = (key, measure) => {
    for (const row of rowsByPart.get(key) || [])
      if (measure >= row[2] && measure <= row[3]) return row[4];
    return 0;
  };
  const byCanon = new Map();
  for (const row of follows) {
    const [id, partIndex, from, to, canonId, canonPart, canonFrom, canonTo] = row;
    const key = `${canonId}#${canonPart}`;
    if (!byCanon.has(key)) byCanon.set(key, []);
    byCanon.get(key).push({ id, partIndex, from, to, canonFrom, canonTo });
  }

  const overridesByPart = new Map(); // partKey -> [{from, to, lane}]
  for (const [canonKey, list] of byCanon) {
    const entries = list.map((entry) => {
      const key = `${entry.id}#${entry.partIndex}`;
      const reversed = entry.canonTo < entry.canonFrom;
      const lane = laneAt(key, (entry.from + entry.to) / 2);
      return {
        ...entry,
        key,
        reversed,
        lane,
        slot: reversed ? -lane : lane,
        lo: Math.min(entry.canonFrom, entry.canonTo),
        hi: Math.max(entry.canonFrom, entry.canonTo),
        cls: classByLine.get(entry.id) ?? `unknown\0${entry.id}`,
      };
    });
    // Longest canonical footprint first; ties broken by class, then line,
    // then part, so the outcome is reproducible run to run.
    entries.sort(
      (a, b) =>
        b.hi - b.lo - (a.hi - a.lo) ||
        compareStrings(a.cls, b.cls) ||
        compareStrings(a.id, b.id) ||
        a.partIndex - b.partIndex,
    );
    // The canonical part is itself a participant, not just the alignment
    // followers are measured against: it draws its own class at its own
    // lane over the whole span any follower here attaches to, and a
    // follower that lands on that same slot is exactly as much a collision
    // as landing on another follower's slot. Seeded into `placed` BEFORE
    // any follower is resolved, so the very first follower already sees it.
    const [canonId, canonPartRaw] = canonKey.split("#");
    const canonPartIndex = Number(canonPartRaw);
    const canonLo = Math.min(...entries.map((entry) => entry.lo));
    const canonHi = Math.max(...entries.map((entry) => entry.hi));
    const canonLane = laneAt(canonKey, (canonLo + canonHi) / 2);
    const placed = [
      {
        id: canonId,
        partIndex: canonPartIndex,
        key: canonKey,
        reversed: false,
        lane: canonLane,
        slot: canonLane,
        lo: canonLo,
        hi: canonHi,
        cls: classByLine.get(canonId) ?? `unknown\0${canonId}`,
      },
    ];
    for (const entry of entries) {
      const conflicts = (slot) =>
        placed.some(
          (other) =>
            other.cls !== entry.cls &&
            Math.abs(other.slot - slot) < 1e-9 &&
            Math.min(other.hi, entry.hi) - Math.max(other.lo, entry.lo) >
              CROSS_CLASS_COLLISION_MIN_OVERLAP_METRES,
        );
      let slot = entry.slot;
      let attempt = 0;
      while (conflicts(slot) && attempt < 200) {
        attempt += 1;
        const magnitude = Math.ceil(attempt / 2) * CROSS_CLASS_COLLISION_STEP;
        slot = entry.slot + (attempt % 2 ? magnitude : -magnitude);
      }
      if (attempt >= 200 && conflicts(slot))
        process.stderr.write(
          `WARNING: ${entry.id}#${entry.partIndex} [${entry.from}, ${entry.to}]m: ` +
            `no clear cross-class slot found after 200 attempts around ` +
            `render-frame ${entry.slot}; keeping slot ${slot}, which still ` +
            `conflicts with another class over this stretch\n`,
        );
      if (slot !== entry.slot) {
        // The shift the collision search just resolved, in LANE space
        // rather than render-frame slot space (the two differ by sign when
        // this follower runs against its canonical). Applied to every one
        // of the follower's OWN existing rows over this window — instead of
        // replacing them with one flat row — so a follower whose own lane
        // already ramps across the window keeps ramping, just moved over.
        const laneDelta = entry.reversed ? -(slot - entry.slot) : (slot - entry.slot);
        const pieces = windowPieces(rowsByPart.get(entry.key), entry.from, entry.to);
        const held = overridesByPart.get(entry.key) || [];
        for (const piece of pieces) {
          if (piece.to - piece.from <= 0) continue;
          held.push({
            from: piece.from,
            to: piece.to,
            lane: Math.round((piece.lane + laneDelta) * 2) / 2,
          });
        }
        overridesByPart.set(entry.key, held);
      }
      placed.push({ ...entry, slot });
    }
  }
  return overridesByPart;
}

// Mirrors build-north-america-rail-package.py's `display_colours`: hold the
// hue exactly, only ever raise the saturation, and move along lightness
// until the colour clears the dark-theme floor — the same rule the package
// build already uses to turn one operator-published hex into a light- and
// dark-theme pair, so a render group's colour that has no reviewed
// `colorDark` of its own gets one derived the same way every other line's
// does, not an unrelated ad hoc rule.
const NA_RENDER_GROUP_DARK_THEME_MIN_L = 0.42;
const NA_RENDER_GROUP_MIN_SATURATION = 0.42;

function parseHexColor(hex) {
  const match = /^#?([0-9a-fA-F]{6})$/.exec(String(hex ?? "").trim());
  if (!match) return null;
  const n = Number.parseInt(match[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function rgbToHsl([r, g, b]) {
  const rn = r / 255;
  const gn = g / 255;
  const bn = b / 255;
  const hi = Math.max(rn, gn, bn);
  const lo = Math.min(rn, gn, bn);
  const light = (hi + lo) / 2;
  const span = hi - lo;
  if (span === 0) return [0, 0, light];
  const sat = span / (1 - Math.abs(2 * light - 1));
  let hue;
  if (hi === rn) hue = ((gn - bn) / span) % 6;
  else if (hi === gn) hue = (bn - rn) / span + 2;
  else hue = (rn - gn) / span + 4;
  hue *= 60;
  if (hue < 0) hue += 360;
  return [hue, sat, light];
}

function hslToRgb(hue, sat, light) {
  const c = (1 - Math.abs(2 * light - 1)) * sat;
  const x = c * (1 - Math.abs(((hue / 60) % 2) - 1));
  const m = light - c / 2;
  const table = [
    [c, x, 0],
    [x, c, 0],
    [0, c, x],
    [0, x, c],
    [x, 0, c],
    [c, 0, x],
  ];
  const [r, g, b] = table[Math.floor(hue / 60) % 6];
  const toByte = (v) => Math.max(0, Math.min(255, Math.round((v + m) * 255)));
  return [toByte(r), toByte(g), toByte(b)];
}

function rgbToHex([r, g, b]) {
  return `#${[r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")}`;
}

function deriveColorDark(color) {
  const rgb = parseHexColor(color);
  if (!rgb) return color;
  const [hue, sat, light] = rgbToHsl(rgb);
  const satOut = sat > 0.04 ? Math.max(sat, NA_RENDER_GROUP_MIN_SATURATION) : sat;
  return rgbToHex(hslToRgb(hue, satOut, Math.max(light, NA_RENDER_GROUP_DARK_THEME_MIN_L)));
}

// `colorByRegion[region][lineId] = { color, colorDark }` for every line whose
// render group (na-render-groups.json `byLineId` -> `groups`) defines a
// colour — an operator-collapse group like `lirr` that draws its whole
// railroad in one colour rather than each branch's own GTFS hex. A line with
// no group, or whose group defines no colour (MBTA commuter rail's colour is
// already uniform, so its group carries one for documentation but every
// member already matches it), is absent here — both clients keep the
// package's own colour for those.
function deriveColorByRegion(pkg, renderGroups) {
  const families = renderGroupFamilies(renderGroups);
  const out = {};
  for (const line of pkg.lines || []) {
    const groupId = renderGroups.byLineId?.[line.id];
    if (!groupId) continue;
    const group = families[groupId];
    if (!group?.color) continue;
    out[line.id] = {
      color: group.color,
      colorDark: group.colorDark || deriveColorDark(group.color),
    };
  }
  return out;
}

// `renderGroupByRegion[region][lineId] = groupId` for EVERY line this
// region's package carries that na-render-groups.json's `byLineId` names —
// not only the groups that also define a colour (deriveColorByRegion above
// is a strict subset of this). This is the identity question, not the
// paint question: rail-network.js's railwayIdentityFor reads it to answer
// "how many railways call at this platform group?", and a group with no
// colour override (most of them — a render group is usually reviewed
// because several service names share one operator's track, not because it
// needs a colour) still has to collapse its members into one railway for
// the interchange pass, or every one of its branches paints a false
// interchange ring at the platform they all share.
function deriveRenderGroupByRegion(pkg, renderGroups) {
  const out = {};
  for (const line of pkg.lines || []) {
    const groupId = renderGroups.byLineId?.[line.id];
    if (!groupId) continue;
    out[line.id] = groupId;
  }
  return out;
}

// Family windows: where a follow row's follower and leader belong to the
// same render-group family (na-render-groups.json `byLineId`), the family
// keeps its whole-railroad colour everywhere, but the corridor only needs
// ONE drawn stroke over the stretch they actually share — same corridor +
// same RenderKey is one lane (rules.md §2, §5, §9.5). A follow row already
// says exactly which stretch that is: the follower's own window (drawn from
// the leader's alignment, so it would coincide pixel-for-pixel with the
// leader's own stroke there) becomes a TENANT window (role 1: this line's
// own stroke is not emitted here), and the corresponding stretch on the
// leader's own part becomes a LANDLORD window (role 0: the leader draws the
// family stroke here, in the family's colour).
//
// `follows` rows are `[followerId, followerPart, from, to, leaderId,
// leaderPart, canonFrom, canonTo]`, already re-pointed at each row's true
// root canonical by the pass above this call — see that pass's own comment.
// `metrics` is the `partKey -> {cumulative, samples, total}` map built at
// the top of deriveNorthAmericanRows, reused here only to snap window edges
// onto real station measures on each part's own ruler.
function deriveFamilyWindows(parts, follows, renderGroups, metrics) {
  const groups = renderGroupFamilies(renderGroups);
  const byLineId = renderGroups.byLineId || {};
  const partByKey = new Map(parts.map((part) => [partKey(part), part]));

  const tenantWindowsByPart = new Map();
  const landlordWindowsByPart = new Map();
  const pushWindow = (map, key, window) => {
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(window);
  };

  // Snap both edges onto the nearest station measure, within
  // FAMILY_WINDOW_STATION_SNAP_METRES, so the handoff between the family
  // stroke and the line's own stroke lands at the junction station rather
  // than an arbitrary point along open track. Read by the follow loop
  // below on the LEADER's own ruler only (see the comment there) — never
  // called on a follower's ruler directly, so the two sides of one handoff
  // can never snap onto two different physical points.
  const stationMeasuresCache = new Map();
  const snapMeasure = (key, measure) => {
    if (!stationMeasuresCache.has(key)) {
      const part = partByKey.get(key);
      const metric = metrics.get(key);
      stationMeasuresCache.set(
        key,
        part && metric ? stationMeasuresForPart(part, metric) : [],
      );
    }
    const stations = stationMeasuresCache.get(key);
    let best = measure;
    let bestGap = FAMILY_WINDOW_STATION_SNAP_METRES;
    for (const station of stations) {
      const gap = Math.abs(station - measure);
      if (gap <= bestGap) {
        best = station;
        bestGap = gap;
      }
    }
    return best;
  };

  for (const row of follows) {
    const [followerId, followerPart, from, to, leaderId, leaderPart, canonFrom, canonTo] = row;
    const groupId = byLineId[followerId];
    if (!groupId || byLineId[leaderId] !== groupId) continue;
    // Snap on ONE ruler only — the leader's — then map that snapped edge
    // through THIS ROW's own linear correspondence ([from, to] <-> [canonFrom,
    // canonTo], the same affine relationship a follow draws the follower's
    // stroke from) onto the follower's ruler for the tenant edge. Snapping
    // each side independently onto its OWN nearest station (the previous
    // behaviour) can choose two DIFFERENT physical points when the leader
    // and follower alignments don't share identical station spacing —  the
    // follower's resumed base stroke and the leader's family stroke would
    // then hand off a few metres apart, leaving a sliver of the wrong
    // colour. Mapping through the row's own correspondence instead of
    // snapping the follower edge directly guarantees the two sides are the
    // SAME physical point, because that correspondence is exactly what the
    // follower's own stroke was built from in the first place.
    const leaderKey = `${leaderId}#${leaderPart}`;
    const followerKey = `${followerId}#${followerPart}`;
    const leaderTotal = metrics.get(leaderKey)?.total;
    const followerTotal = metrics.get(followerKey)?.total;
    const clampTo = (measure, total) =>
      total == null ? measure : Math.max(0, Math.min(total, measure));
    const snappedCanonFrom = clampTo(snapMeasure(leaderKey, canonFrom), leaderTotal);
    const snappedCanonTo = clampTo(snapMeasure(leaderKey, canonTo), leaderTotal);
    const canonSpan = canonTo - canonFrom;
    const followerAt = (canonMeasure) =>
      canonSpan === 0 ? from : from + ((canonMeasure - canonFrom) / canonSpan) * (to - from);
    // The leader-ruler snap can nudge an edge to a station just OUTSIDE
    // this row's own [canonFrom, canonTo] span (still within
    // FAMILY_WINDOW_STATION_SNAP_METRES of it), and mapping that through
    // the row's own correspondence extrapolates slightly past the
    // follower's own [from, to] — occasionally past the follower part's
    // own [0, total] entirely. Clamp to the follower's own valid measure
    // range: a window can never start before its own part's 0 or end past
    // its own total, whatever a nearby leader station suggested.
    const snappedFrom = clampTo(followerAt(snappedCanonFrom), followerTotal);
    const snappedTo = clampTo(followerAt(snappedCanonTo), followerTotal);
    pushWindow(tenantWindowsByPart, followerKey, {
      from: Math.min(snappedFrom, snappedTo),
      to: Math.max(snappedFrom, snappedTo),
      groupId,
    });
    pushWindow(landlordWindowsByPart, leaderKey, {
      from: Math.min(snappedCanonFrom, snappedCanonTo),
      to: Math.max(snappedCanonFrom, snappedCanonTo),
      groupId,
    });
  }

  // Merge windows separated by no more than SAMPLE_METRES, not only ones
  // that already touch or overlap exactly: the geometry these windows are
  // measured against is itself sampled at SAMPLE_METRES resolution (see
  // `samplesFor`), so two windows that are really one continuous stretch
  // can still land a sample-width apart after snapping. Used for BOTH
  // landlord and tenant windows below — a family corridor and the tenant
  // stretch that hands off to it are equally subject to this sampling
  // noise.
  const unionWindows = (list) => {
    const sorted = [...list].sort((a, b) => a.from - b.from);
    const out = [];
    for (const window of sorted) {
      const previous = out[out.length - 1];
      if (previous && window.from - previous.to <= SAMPLE_METRES)
        previous.to = Math.max(previous.to, window.to);
      else out.push({ ...window });
    }
    return out;
  };

  // Union overlapping-or-adjacent windows per (lineId, partIndex, groupId).
  // For landlord windows: two different tenants can each name the same
  // trunk stretch as their canonical window (e.g. two LIRR branches both
  // follow the Jamaica–City Terminal Zone trunk), and that trunk still
  // draws ONE family stroke, not two overlapping ones. For tenant windows:
  // a follower whose path re-joins the same leader after a short gap (or
  // whose own follow rows were split across more than one sample) should
  // resume its own stroke ONCE, not flicker back on for a sliver between
  // two near-adjacent tenant windows.
  const unionByGroup = (byPart) => {
    const out = new Map();
    for (const [key, list] of byPart) {
      const byGroup = new Map();
      for (const window of list) {
        if (!byGroup.has(window.groupId)) byGroup.set(window.groupId, []);
        byGroup.get(window.groupId).push(window);
      }
      const merged = [];
      for (const [groupId, windows] of byGroup) {
        for (const window of unionWindows(windows)) merged.push({ ...window, groupId });
      }
      out.set(key, merged);
    }
    return out;
  };
  const landlordUnionedByPart = unionByGroup(landlordWindowsByPart);
  const tenantUnionedByPart = unionByGroup(tenantWindowsByPart);

  // Subtract tenant windows from landlord windows OF THE SAME LINE+PART: a
  // trunk line can itself be a tenant of an upstream trunk over part of its
  // own length (the re-pointing pass above already walked every follow back
  // to its true root, so this only fires for a genuine second junction, not
  // an unresolved intermediary) — the stretch where it is a tenant is not
  // also a landlord stretch.
  const subtractWindows = (landlordList, tenantList) => {
    let result = landlordList.map((window) => ({ ...window }));
    for (const tenant of tenantList) {
      const next = [];
      for (const window of result) {
        if (tenant.to <= window.from || tenant.from >= window.to) {
          next.push(window);
          continue;
        }
        if (tenant.from > window.from) next.push({ ...window, to: tenant.from });
        if (tenant.to < window.to) next.push({ ...window, from: tenant.to });
      }
      result = next;
    }
    return result.filter((window) => window.to > window.from);
  };

  const landlordFinalByPart = new Map();
  for (const [key, list] of landlordUnionedByPart) {
    const tenantHere = tenantUnionedByPart.get(key) || [];
    landlordFinalByPart.set(key, subtractWindows(list, tenantHere));
  }

  const rowsByRegionKey = [];
  const emit = (key, windows, role) => {
    const [lineId, partIndexStr] = key.split("#");
    const partIndex = Number(partIndexStr);
    // Windows arrive here already snapped (on the leader's ruler, mapped
    // through each follow row's own correspondence — see the loop above)
    // and already unioned across a sample-width gap (`unionWindows`), so
    // this pass only needs to drop anything a union or subtract left
    // zero-length and merge whatever still touches after that.
    const prepared = windows
      .filter((window) => window.to > window.from)
      .sort((a, b) => a.from - b.from);
    const merged = [];
    for (const window of prepared) {
      const previous = merged[merged.length - 1];
      if (previous && window.from - previous.to <= SAMPLE_METRES && previous.groupId === window.groupId) {
        previous.to = Math.max(previous.to, window.to);
      } else merged.push({ ...window });
    }
    for (const window of merged) {
      const group = groups[window.groupId];
      if (!group?.color) {
        throw new Error(
          `family window for ${lineId}#${partIndex} [${window.from}, ${window.to}] ` +
            `names render group "${window.groupId}", which has no groups[].color in ` +
            `na-render-groups.json — add a reviewed colour (or fix the group members' ` +
            `disagreeing hexes) before this window can be drawn.`,
        );
      }
      rowsByRegionKey.push([
        lineId,
        partIndex,
        Number(window.from.toFixed(1)),
        Number(window.to.toFixed(1)),
        role,
        window.groupId,
      ]);
    }
  };

  const allPartKeys = new Set([...tenantUnionedByPart.keys(), ...landlordFinalByPart.keys()]);
  for (const key of allPartKeys) {
    emit(key, tenantUnionedByPart.get(key) || [], 1);
    emit(key, landlordFinalByPart.get(key) || [], 0);
  }

  rowsByRegionKey.sort((a, b) =>
    a[0].localeCompare(b[0]) || a[1] - b[1] || a[2] - b[2] || a[4] - b[4]);
  return rowsByRegionKey;
}

// Renamed from `deriveNorthAmericanRows`: nothing in it was ever North
// American except the reviewed policy files it reads and the regions it was
// called for. The measurement passes — corridor sampling, lane ranking,
// follow runs, family windows, convergence hubs — are geometry, and the
// facts that differ between one country's railways and another's now all
// arrive through the render-group policy (`renderGroups.policy.profile`) and
// the reviewed corridor seeds, not through the code path.
function deriveDisplayRows(
  region,
  pkg,
  reviewedSharedCorridors,
  renderGroups,
  releasesByRegion,
  hubs,
  loopWinding,
) {
  // The reviewed cross-line landlord seeds for THIS region, expanded from the
  // class-level pairs the review records (one entry names every geometry-part
  // row on each side) down to the lineId pairs the follow pass compares.
  const landlordsByTenantLine = new Map();
  const seedSpansByPair = new Map();
  const knownLineIds = new Set(pkg.lines.map((line) => line.id));
  const seedProblems = [];
  const seenDirected = new Set();
  for (const seed of reviewedSharedCorridors?.displayLandlords || []) {
    if ((seed.region || "us") !== region) continue;
    const tenants = seed.tenantLineIds?.length ? seed.tenantLineIds : [seed.tenantLineId];
    const landlords = seed.landlordLineIds?.length
      ? seed.landlordLineIds
      : [seed.landlordLineId];
    const label = `${seed.tenantLineId} -> ${seed.landlordLineId}`;
    // Validated, not trusted. A seed is the ONLY thing that can make two
    // different railways share an alignment under the route-preserving
    // profile, so a typo in one is not a no-op — it silently withholds the
    // follow the review meant to grant, and the pair falls back to a lane
    // that looks plausible. All four checks below are cheap and total.
    for (const lineId of [...tenants, ...landlords])
      if (!knownLineIds.has(lineId))
        seedProblems.push(`${label}: ${lineId} is not a line in ${region}-2025.json`);
    if (!seed.spans?.length) seedProblems.push(`${label}: names no spans`);
    if (!seed.evidence?.length) seedProblems.push(`${label}: carries no evidence`);
    for (const tenant of tenants) {
      for (const landlord of landlords) {
        if (tenant === landlord) continue;
        // A pair that is seeded in BOTH directions is not evidence about who
        // owns the track — it is two reviews contradicting each other, and
        // whichever one this loop happened to read second would silently win.
        if (seenDirected.has(`${landlord}\u0000${tenant}`))
          seedProblems.push(
            `${label}: ${tenant} and ${landlord} are each seeded as the other's landlord. ` +
              `Record the pair under displayLandlordPolicy.unresolved instead.`,
          );
        seenDirected.add(`${tenant}\u0000${landlord}`);
      }
    }
    for (const tenant of tenants) {
      if (!landlordsByTenantLine.has(tenant)) landlordsByTenantLine.set(tenant, new Set());
      for (const landlord of landlords) {
        if (landlord === tenant) continue;
        landlordsByTenantLine.get(tenant).add(landlord);
        // Record which spans license THIS tenant/landlord pair — see the
        // resolution pass below, right after `parts`/`metrics` exist. A seed
        // is pair-scoped, not line-scoped: 山陽線 rides 山陽新幹線's alignment
        // only 福山附近, not the other 16+ km the unrestricted grant used to
        // hand it (D2).
        const pairKey = `${tenant} ${landlord}`;
        if (!seedSpansByPair.has(pairKey)) seedSpansByPair.set(pairKey, []);
        seedSpansByPair.get(pairKey).push(...(seed.spans || []));
      }
    }
  }
  if (seedProblems.length)
    throw new Error(
      `shared-corridors.json displayLandlords, region ${region}:\n  ${seedProblems.join("\n  ")}`,
    );
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
  const displayPartsByLine = extractDisplayPartsByLine(network);
  const { rows: partsByRegionRows, excluded: partsExcluded } = computePartsByRegionRows(
    pkg,
    network,
    reviewedSharedCorridors,
    loopWinding,
  );
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
        // Authoritative, not inferred: which line this one is a published
        // short-turn/branch variant of, straight from the compact package.
        // Used only to let a branch follow the trunk it is a subset of over
        // a run shorter than FOLLOW_MIN_RUN_METRES would otherwise allow —
        // see isKin below.
        branchOf: compactLine.branchOf || null,
        // A reviewed, hand-curated fact from the package build (Metra
        // Electric owns the physical track at Kensington; NICTD's South
        // Shore trains ride it under trackage rights) — see `isLandlordFor`
        // below. Present on exactly south-shore-line-lakeshore and
        // south-shore-line-monon today, both naming metra-me.
        // Every landlord this line is a reviewed tenant of. Two sources, one
        // meaning: the NA packages carry a single `sharedTrackCanonicalLineId`
        // on the line row itself (south-shore-line-lakeshore and
        // south-shore-line-monon both name metra-me), and shared-corridors.json
        // carries `displayLandlords`, the reviewed cross-line seeds the Japan
        // profile needs — where one tenant can genuinely have several
        // landlords over different spans (いわて銀河鉄道線 rides both 東北線 and
        // 山田線 into 盛岡), which one field cannot express.
        sharedTrackCanonicalLineIds: [
          ...new Set(
            [
              compactLine.sharedTrackCanonicalLineId || null,
              ...(landlordsByTenantLine.get(line.lineId) || []),
            ].filter(Boolean),
          ),
        ],
        displayClass: displayClassKey(compactLine, renderGroups),
        kind: String(compactLine.kind || ""),
        geometrySource: String(compactLine.geometrySource || ""),
        partIndex,
        coordinates,
        stationPoints,
        withheld: blockedIntervals.length > 0,
        // `excludedLineIds` (shared-corridors.json's reviewed policy) still
        // names metra-me, south-shore-line-lakeshore and south-shore-line-monon,
        // with the recorded reason that "synthetic screen offsets ended at
        // the [Kensington] interlocking and rendered false stubs and branch
        // jumps." That is a complaint about the LANE mechanism specifically
        // ("screen offsets"), but this flag used to gate both lane rows and
        // follow rows for a line at once, so it also blocked the one thing
        // that fixes exactly this complaint: a FOLLOW row draws a tenant
        // from the landlord's own alignment instead of offsetting the
        // tenant's own independently-digitised geometry. Measured with the
        // exclusion lifted (and `sharedTrackCanonicalLineId` forcing the
        // landlord's direction below — the generic provenance heuristic
        // ranks a NARN source over metra-me's own non-standard source label
        // and would otherwise get Kensington backwards), the three lines
        // resolve to one clean relationship with no change anywhere else in
        // either package: both South Shore variants follow metra-me's own
        // centreline for the ~23 km they actually share with it into
        // Kensington, then each keeps its own lane past the interlocking
        // where the physical corridor splits. The reviewed policy stays on
        // record in shared-corridors.json as evidence of why these three
        // were once special-cased; it no longer suppresses rows.
        emitsRows: !EXCLUDED_OFFSET_OPERATORS.has(operator),
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

  // Resolve each seed's station-name `spans` to a metre window on the
  // TENANT's own ruler, per part — the thing a seed is supposed to license,
  // instead of the pair-scoped `spans` being checked for non-emptiness and
  // then never read (D2). A span is either "A—B" (a named range) or a single
  // "NAME" / "NAME附近" (a junction/vicinity, given a fixed buffer either
  // side). Matched by station NAME against the tenant compact line's own
  // `stations` rows, then snapped onto the part's ruler the same way
  // `stationMeasuresForPart` snaps a station point (nearest vertex, <= 200 m).
  // A pair whose seed spans do not resolve to any window on any tenant part
  // grants NOTHING — fail closed, logged, rather than the unrestricted grant
  // this replaces.
  const SEED_VICINITY_BUFFER_METRES = 5000;
  const SEED_RANGE_BUFFER_METRES = 2000;
  const seedWindowsByPair = new Map(); // "tenantLineId landlordLineId" -> [{partKey, from, to}]
  const seedResolutionWarnings = [];
  const nearestMeasureForPoint = (part, metric, point) => {
    let best = Infinity;
    let measure = null;
    part.coordinates.forEach((candidate, index) => {
      const gap = distanceMeters(point, candidate);
      if (gap < best) {
        best = gap;
        measure = metric.cumulative[index];
      }
    });
    return best <= 200 ? measure : null;
  };
  for (const [pairKey, spans] of seedSpansByPair) {
    const [tenant, landlord] = pairKey.split(" ");
    const compactLine = compactLineById.get(tenant);
    const nameToPoint = new Map(
      (compactLine?.stations || []).map((row) => [row[1], [row[2], row[3]]]),
    );
    const tenantParts = parts.filter((part) => part.lineId === tenant);
    const windows = [];
    for (const span of spans) {
      const names = span.includes("—")
        ? span.split("—").map((name) => name.replace(/附近$/, ""))
        : [span.replace(/附近$/, "")];
      const isVicinity = !span.includes("—");
      const buffer = isVicinity ? SEED_VICINITY_BUFFER_METRES : SEED_RANGE_BUFFER_METRES;
      let resolvedAny = false;
      for (const part of tenantParts) {
        const metric = metrics.get(partKey(part));
        const measures = names
          .map((name) => {
            const point = nameToPoint.get(name);
            return point ? nearestMeasureForPoint(part, metric, point) : null;
          })
          .filter((value) => value != null);
        if (!measures.length) continue;
        resolvedAny = true;
        windows.push({
          partKey: partKey(part),
          from: Math.max(0, Math.min(...measures) - buffer),
          to: Math.min(metric.total, Math.max(...measures) + buffer),
        });
      }
      if (!resolvedAny)
        seedResolutionWarnings.push(
          `${pairKey.replace(" ", " -> ")}: span "${span}" did not resolve to any station ` +
            `on ${tenant}'s own geometry — no window granted for it`,
        );
    }
    seedWindowsByPair.set(pairKey, windows);
  }
  if (seedResolutionWarnings.length)
    console.warn(
      `shared-corridors.json displayLandlords, region ${region}: ${seedResolutionWarnings.length} ` +
        `span(s) did not resolve:\n  ${seedResolutionWarnings.join("\n  ")}`,
    );
  const withinSeedWindow = (part, landlordLineId, measure) => {
    const windows = seedWindowsByPair.get(`${part.lineId} ${landlordLineId}`);
    if (!windows) return false;
    return windows.some(
      (window) => window.partKey === partKey(part) && measure >= window.from && measure <= window.to,
    );
  };

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
    "funicular", "commuter", "highspeed", "regional", "intercity", "heritage"];
  // The North American packages label a line's mode with the vocabulary
  // KIND_PRIORITY is written in. The Japanese package labels it with N02's
  // own operator classes instead, so every jp line would otherwise fall off
  // the end of KIND_PRIORITY (rank = length, all equal) and into one single
  // rail family — which would let a subway be drawn from a mainline's
  // alignment, the exact thing the family split exists to prevent. Mapped,
  // not renamed: the package keeps its own vocabulary and this is the one
  // place the two are reconciled.
  //   jr_conventional / third_sector -> the JR and successor mainlines and
  //     the third-sector companies that inherited them: heavy rail, ranked
  //     like a regional railway.
  //   private -> 私鉄, the big private commuter railways (小田急, 京王, 阪急…),
  //     which publish their own centrelines and own their own track.
  //   shinkansen / maglev -> `highspeed`: a dedicated, separately surveyed
  //     right of way that happens to share structure with the conventional
  //     lines at a handful of stations (東京, 新大阪). Heavy rail, ranked
  //     after `commuter` and before `regional`, because where a Shinkansen
  //     viaduct and a conventional line are co-linear the Shinkansen owns
  //     the structure.
  const KIND_ALIASES = new Map([
    ["jr_conventional", "regional"],
    ["third_sector", "regional"],
    ["private", "commuter"],
    ["shinkansen", "highspeed"],
    ["maglev", "highspeed"],
    ["subway", "metro"],
    ["tram", "streetcar"],
    ["monorail", "monorail"],
    ["agt", "people-mover"],
    ["funicular", "funicular"],
  ]);
  const normalisedKind = (kind) => KIND_ALIASES.get(kind) || kind;
  // A follow never crosses the mode line: an elevated metro beside a
  // mainline is NEAR_PARALLEL, two rights of way a survey's width apart,
  // and neither is drawn from the other's alignment. Only railways of one
  // family — the heavy-rail services that really do share track, or the
  // urban modes that really do share street and structure — can follow.
  const HEAVY_RAIL = new Set(["commuter", "highspeed", "regional", "intercity", "heritage"]);
  const railFamily = (kind) => (HEAVY_RAIL.has(normalisedKind(kind)) ? "heavy" : "urban");
  // `n02` is 国土交通省 国土数値情報's national railway survey — the same tier of
  // evidence as a state DOT's own GIS, and the source EVERY Japanese line's
  // geometry is cut from (jp-2025.json geometrySource.sections:
  // "data/rail-sections.json (N02-25)"). Ranked 0 with the other surveyed
  // sources rather than left to fall through to 3, where it would have tied
  // with an unlabelled source and handed the canonical direction to whichever
  // line sorted first.
  const sourcePriority = (source) => {
    if (/^(orwn|official|operator|caltrans|massgis|n02)/.test(source)) return 0;
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
          KIND_PRIORITY.indexOf(normalisedKind(part.kind)) < 0
            ? KIND_PRIORITY.length
            : KIND_PRIORITY.indexOf(normalisedKind(part.kind)),
          sourcePriority(part.geometrySource),
          -metrics.get(partKey(part)).total,
        ],
      }))
      .sort((a, b) => firstDifference(a.order, b.order) || a.key.localeCompare(b.key))
      .map((entry, index) => [entry.key, index]),
  );
  // A branch shares its trunk's track by definition — that is what makes it
  // a branch rather than a separate line — so two lines related by the
  // package's own `branchOf` (parent-child, or two children of the same
  // parent) are kin. FOLLOW_MIN_RUN_METRES exists to stop two UNRELATED
  // lines that merely cross paths for a block or two from reading as a
  // shared corridor; it has nothing to say about a branch whose own total
  // length is shorter than that window, which is common for a short-turn
  // streetcar variant or a stub. Kin runs skip that length gate below.
  const branchOfByLine = new Map(parts.map((part) => [part.lineId, part.branchOf]));
  // Japan spells the same relationship in the id rather than in a field: the
  // package build has no `branchOf` on any of its 652 lines, and instead emits
  // one railway's geometry parts as `<id>-2`, `<id>-3`, `<id>-p1` … So two
  // lines that reduce to the same `baseLineId` are kin for exactly the same
  // reason a `branchOf` pair is — they are two parts of one railway, sharing
  // track by definition rather than by measurement.
  const routePreserving = renderGroups?.policy?.profile === "route-preserving";
  const isKin = (lineA, lineB) => {
    if (lineA === lineB) return true;
    // Only under the route-preserving profile. Elsewhere a trailing number is
    // a ROUTE number, not a geometry-part suffix — cincinnati-metro-100 and
    // hk-mtr-lr-705/706 would otherwise become kin with anything sharing
    // their stem, and kinship waives FOLLOW_MIN_RUN_METRES.
    if (routePreserving && baseLineId(lineA) === baseLineId(lineB)) return true;
    const a = branchOfByLine.get(lineA);
    const b = branchOfByLine.get(lineB);
    return a === lineB || b === lineA || (!!a && !!b && a === b);
  };
  // A reviewed landlord (south-shore-line-lakeshore and
  // south-shore-line-monon both name metra-me today) records which line
  // physically owns a shared corridor when that is a documented fact rather
  // than something inferable from the generic provenance order below — the
  // Metra Electric District owns the Kensington trackage that NICTD's South
  // Shore Line rides under trackage rights, but METRA-ME's own geometry
  // source label does not match the "surveyed/official" pattern that order
  // rewards, so left alone it would rank the tenant ahead of the landlord.
  // Used only to compare one subject line against one candidate part: the
  // named landlord always outranks its tenant here, and a landlord can never
  // be made to follow its own tenant, whatever the generic order says.
  const landlordByLine = new Map(
    parts.map((part) => [part.lineId, new Set(part.sharedTrackCanonicalLineIds)]),
  );
  const isTenantOf = (tenantLineId, landlordLineId) =>
    Boolean(landlordByLine.get(tenantLineId)?.has(landlordLineId));
  const candidateRank = (subjectLineId, candidateKey, candidateLineId) => {
    if (isTenantOf(subjectLineId, candidateLineId)) return -Infinity;
    if (isTenantOf(candidateLineId, subjectLineId)) return Infinity;
    return partRank.get(candidateKey) ?? Infinity;
  };
  // WHO MAY FOLLOW WHOM.
  //
  // In North America a follow is discovered purely by measurement: any two
  // parts of one rail family that run inside FOLLOW_MAX_MEDIAN_METRES of each
  // other for FOLLOW_MIN_RUN_METRES are, in that data, the same physical
  // corridor, and drawing the tenant from the landlord's alignment is what
  // stops two independently digitised strokes weaving across each other.
  //
  // Japan cannot be discovered that way, and the audit says so in numbers.
  // japan_line_by_line_audit/02 separates 342 spans of 坐标精确重合 (exact
  // coordinate coincidence — median lateral 0.0 m, the same physical track
  // digitised twice) from 245 spans of 真实几何平行 (genuinely parallel,
  // independent centrelines on their own roadbeds: 新幹線 beside JR beside
  // 私鉄 through 京都—大阪). 35 of those 245 sit closer than
  // FOLLOW_MAX_MEDIAN_METRES and every one of them is longer than
  // FOLLOW_MIN_RUN_METRES, so measurement alone would draw 35 independent
  // railways off a neighbour's centreline — the Japan policy's §5 "genuinely
  // separate geometry: keep the real position" case, turned into the wrong
  // one. Under the route-preserving profile a follow therefore needs a REASON
  // as well as a measurement, and there are exactly three:
  //   * the two parts are the same railway's own geometry parts (`isKin`, the
  //     -2/-3/-p1 rows), or belong to one render group;
  //   * the pair is a reviewed landlord seed in shared-corridors.json
  //     (`displayLandlords`), measured coincident and adjudicated by hand;
  //   * nothing else.
  // A pair that is merely near stays near: it keeps its own centreline and
  // takes a parallel LANE, which is what both rule sets ask for.
  const classByLine = new Map(parts.map((part) => [part.lineId, part.displayClass]));
  const followAllowed = (subjectLineId, candidateLineId) => {
    if (!routePreserving) return true;
    if (isKin(subjectLineId, candidateLineId)) return true;
    if (classByLine.get(subjectLineId) === classByLine.get(candidateLineId)) return true;
    return (
      isTenantOf(subjectLineId, candidateLineId) ||
      isTenantOf(candidateLineId, subjectLineId)
    );
  };
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
      for (const [key, lateral] of laterals) {
        const candidateLineId = neighbours[index].partnerParts.get(key)?.lineId;
        if (
          Math.abs(lateral) <= FOLLOW_MAX_MEDIAN_METRES &&
          candidateRank(part.lineId, key, candidateLineId) < selfRank &&
          followAllowed(part.lineId, candidateLineId) &&
          // A reviewed landlord seed is a hand-adjudicated fact about the
          // physical track and outranks the mode heuristic: Tokyo's through
          // services really do run a 私鉄 train onto a 地下鉄's own track.
          (partFamily.get(key) === railFamily(part.kind) ||
            isTenantOf(part.lineId, candidateLineId)) &&
          // But a seed is pair-scoped by its own `spans` (D2): where
          // shared-corridors.json records spans for this exact tenant/
          // landlord pair, the grant only holds inside the resolved window —
          // 山陽線 rides 山陽新幹線 at 福山附近, not for the next 16 km past it —
          // and this restriction applies whichever disjunct above happened
          // to grant eligibility (both 山陽線 and 山陽新幹線 are `heavy` rail,
          // so the mode heuristic alone would otherwise wave the seed's own
          // scoping through). A pair with NO seed-span entry here is the NA
          // single-field `sharedTrackCanonicalLineId` case (South Shore
          // Line/Metra), which carries no spans and keeps its existing
          // unrestricted grant.
          (!seedSpansByPair.has(`${part.lineId} ${candidateLineId}`) ||
            withinSeedWindow(part, candidateLineId, sample.measure))
        )
          eligible.add(key);
      }
      const previous = followRuns[followRuns.length - 1];
      let chosen = null;
      if (previous && previous.partKey && eligible.has(previous.partKey))
        chosen = previous.partKey;
      else
        for (const key of eligible) {
          const rank = candidateRank(part.lineId, key, neighbours[index].partnerParts.get(key)?.lineId);
          const chosenRank = chosen
            ? candidateRank(part.lineId, chosen, neighbours[index].partnerParts.get(chosen)?.lineId)
            : Infinity;
          if (!chosen || rank < chosenRank) chosen = key;
        }
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
      if (!run.partKey) continue;
      const minRun = isKin(part.lineId, run.lineId) ? 0 : FOLLOW_MIN_RUN_METRES;
      if (run.to - run.from < minRun) continue;
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

    // Two adjacent nonzero-lane plateaus of OPPOSITE sign with no lane-0 run
    // between them is a flip with nothing to ramp across: the renderer's own
    // jog taper (rail-stroke.js LANE_RAMP_HALF_WIDTH_METRES) smooths a
    // transition INTO a hub or junction override, not a bare sign change the
    // general pass handed it mid-corridor with no hub involved (hub windows
    // are spliced in afterward, by applyHubOverrides, not part of `runs`
    // here). Left alone this renders as a zero-length jump from one side of
    // the corridor straight to the other. Merge the two plateaus onto
    // whichever carried more length instead — see D4.
    for (let index = 1; index < runs.length; ) {
      const before = runs[index - 1];
      const current = runs[index];
      if (before.lane && current.lane && Math.sign(before.lane) !== Math.sign(current.lane)) {
        if (current.to - current.from > before.to - before.from) {
          current.from = before.from;
          runs.splice(index - 1, 1);
        } else {
          before.to = current.to;
          runs.splice(index, 1);
        }
        if (index > 1) index -= 1;
      } else {
        index += 1;
      }
    }

    for (let index = 1; index < runs.length - 1; ) {
      const before = runs[index - 1];
      const gap = runs[index];
      const after = runs[index + 1];
      if (!gap.lane && before.lane === after.lane && gap.to - gap.from < BRIDGE_METRES) {
        before.to = after.to;
        runs.splice(index, 2);
      } else index += 1;
    }

    const stationMeasures = stationMeasuresForPart(part, metric);

    // True if some sample in [from, to] has a DIFFERENT-class neighbour
    // within COINCIDENT_METRES — the same track, not merely a nearby one —
    // that `followAllowed` refuses to let this part follow. Such a run needs
    // MIN_RUN_METRES's much larger "not just a crossing" bar relaxed to
    // COINCIDENT_MIN_RUN_METRES: dropping it for being short does not
    // separate the two railways again, it puts both back on lane 0 with no
    // offset at all for exactly the stretch that needs one. See D1.
    const isCoincidentBlockedRun = (from, to) => {
      for (let index = 0; index < metric.samples.length; index += 1) {
        const measure = metric.samples[index].measure;
        if (measure < from) continue;
        if (measure > to) break;
        for (const [key, lateral] of smoothedPartLaterals[index]) {
          if (Math.abs(lateral) > COINCIDENT_METRES) continue;
          const candidateLineId = neighbours[index].partnerParts.get(key)?.lineId;
          if (candidateLineId && !followAllowed(part.lineId, candidateLineId)) return true;
        }
      }
      return false;
    };

    let previousEnd = 0;
    const partRows = [];
    for (const run of runs) {
      if (!run.lane) continue;
      const minRun = isCoincidentBlockedRun(run.from, run.to)
        ? COINCIDENT_MIN_RUN_METRES
        : MIN_RUN_METRES;
      if (run.to - run.from < minRun) continue;
      let from = run.from;
      let to = run.to;
      const before = stationMeasures.filter((measure) => measure <= from).at(-1);
      const after = stationMeasures.find((measure) => measure >= to);
      if (before != null && from - before <= STATION_SNAP_METRES) from = before;
      if (after != null && after - to <= STATION_SNAP_METRES) to = after;
      from = Math.max(previousEnd, from);
      previousEnd = to;
      if (to - from < minRun) continue;
      partRows.push([from, to, run.lane]);
    }

    // Station snapping and the previousEnd clamp above can pull two
    // surviving nonzero-lane rows directly together at a shared boundary
    // even where the pre-snap `runs` pass (see above) did not consider them
    // adjacent — the short lane-0 stretch between them was real at the
    // `runs` stage but gets erased once both edges snap onto the same
    // station measure. Re-check for the D4 sign flip here, on what is
    // actually about to be emitted, for the same reason: a zero-length jump
    // from one side of the corridor to the other with nothing to ramp
    // across.
    for (let index = 1; index < partRows.length; ) {
      const before = partRows[index - 1];
      const current = partRows[index];
      if (
        before[2] &&
        current[2] &&
        Math.sign(before[2]) !== Math.sign(current[2]) &&
        current[0] - before[1] <= STATION_SNAP_METRES
      ) {
        if (current[1] - current[0] > before[1] - before[0]) {
          current[0] = before[0];
          partRows.splice(index - 1, 1);
        } else {
          before[1] = current[1];
          partRows.splice(index, 1);
        }
        if (index > 1) index -= 1;
      } else {
        index += 1;
      }
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
  // A canonical that is itself a follower over the same stretch is only an
  // intermediary: the renderers substitute one hop, from the canonical's RAW
  // alignment, so a tenant of a tenant would still weave against the real
  // corridor. Re-point such rows at the canonical's own canonical, mapping the
  // measures through the intermediary's row, and repeat until stable.
  const byFollower = new Map();
  for (const row of follows) {
    const key = `${row[0]}#${row[1]}`;
    if (!byFollower.has(key)) byFollower.set(key, []);
    byFollower.get(key).push(row);
  }
  // Fixed point, not a fixed count: a chain of intermediaries (A follows B
  // follows C follows D…) needs one pass per hop before every row names its
  // true root, and a fixed pass count silently stops re-pointing partway
  // through a chain longer than it anticipated, leaving a tenant of a
  // tenant pointed at an intermediary instead of the real corridor. Bounded
  // at REPOINT_MAX_PASSES passes — generous for any chain this data could
  // plausibly contain — and throws rather than silently truncating if that
  // bound is somehow not enough, so a genuine non-convergence (e.g. a follow
  // cycle) fails the build instead of shipping a wrong intermediary.
  const REPOINT_MAX_PASSES = 16;
  let repointPass = 0;
  for (; repointPass < REPOINT_MAX_PASSES; repointPass += 1) {
    let changed = 0;
    for (const row of follows) {
      const [, , from, to, canonId, canonPart, canonFrom, canonTo] = row;
      const low = Math.min(canonFrom, canonTo);
      const high = Math.max(canonFrom, canonTo);
      const upstream = (byFollower.get(`${canonId}#${canonPart}`) || []).find(
        (candidate) => candidate[2] <= low + SAMPLE_METRES && candidate[3] >= high - SAMPLE_METRES,
      );
      if (!upstream) continue;
      const [, , uFrom, uTo, uCanonId, uCanonPart, uCanonFrom, uCanonTo] = upstream;
      if (uCanonId === row[0] && uCanonPart === row[1]) continue;
      const map = (measure) =>
        uCanonFrom + ((measure - uFrom) / (uTo - uFrom)) * (uCanonTo - uCanonFrom);
      row[4] = uCanonId;
      row[5] = uCanonPart;
      row[6] = Number(map(canonFrom).toFixed(1));
      row[7] = Number(map(canonTo).toFixed(1));
      changed += 1;
    }
    if (!changed) break;
  }
  if (repointPass >= REPOINT_MAX_PASSES)
    throw new Error(
      `follow re-pointing did not converge within ${REPOINT_MAX_PASSES} passes — ` +
        `a follow chain is either longer than this bound anticipated or contains a ` +
        `cycle; raise REPOINT_MAX_PASSES only after confirming it is the former.`,
    );
  follows.sort((a, b) =>
    a[0].localeCompare(b[0]) || a[1] - b[1] || a[2] - b[2]);

  // Family windows: derived from the fully re-pointed follow chain, same as
  // the collision pass just below — see deriveFamilyWindows above.
  const familyWindows = deriveFamilyWindows(parts, follows, renderGroups, metrics);

  // Canonical-frame collision pass: run against the fully re-pointed follow
  // chain (every follow now names its root canonical), before hubs get their
  // turn. See resolveCrossClassFollowCollisions above.
  const crossClassOverrides = resolveCrossClassFollowCollisions(merged, follows, parts);
  const collisionResolvedRows = applyHubOverrides(merged, crossClassOverrides);

  // Convergence hubs: run last, against the final follow chain, so the
  // reference part it picks for each hub is the true root rather than an
  // intermediary a later resolution pass would have re-pointed anyway.
  const { hubRowsByPart, report: hubReport } = computeHubOverrides(parts, metrics, follows, hubs, grid);
  for (const hub of hubReport)
    for (const member of hub.members)
      member.previousLane = priorLaneFor(collisionResolvedRows, member.lineId, member.partIndex, member.from, member.to);
  const finalRows = applyHubOverrides(collisionResolvedRows, hubRowsByPart);

  return {
    rows: finalRows,
    follows,
    hubReport,
    parts: partsByRegionRows,
    partsExcluded,
    familyWindows,
  };
}

const reviewed = fs.existsSync(SHARED_CORRIDORS)
  ? JSON.parse(fs.readFileSync(SHARED_CORRIDORS, "utf8"))
  : { corridors: [] };
// Recorded here for the output's audit trail only — see the long comment in
// deriveNorthAmericanRows on why this reviewed policy no longer gates row
// generation for the lines it names.
const excludedLineIds = new Set(
  reviewed.displayLanePolicy?.excludedLineIds || [],
);
// The reviewed render-group policy. Its absence is a broken checkout, not a
// default to fall back on: without it the colour rule silently regains the
// power to decide identity, and four unrelated MTA railways become one lane.
const RENDER_GROUP_FORMATS = new Set([
  "jtm-na-render-groups-v2",
  "jtm-na-render-groups-v1",
  // Same v2 document schema (scope / policy / evidence / byLineId /
  // families-with-networkId-and-mode), different reviewed policy: see
  // jp-render-groups.json's own `policy.why`. Held in its own file, and named
  // in its own format string, so neither review can inherit the other's
  // default by accident.
  "jtm-jp-render-groups-v2",
]);
const RENDER_GROUP_POLICIES = [RENDER_GROUPS, JP_RENDER_GROUPS];
const renderGroupsByRegion = new Map();
for (const policyPath of RENDER_GROUP_POLICIES) {
  if (!fs.existsSync(policyPath))
    throw new Error(`missing reviewed render-group policy: ${policyPath}`);
  const doc = JSON.parse(fs.readFileSync(policyPath, "utf8"));
  if (!RENDER_GROUP_FORMATS.has(doc.format))
    throw new Error(`unexpected render-group policy format: ${doc.format}`);
  if (!Array.isArray(doc.scope) || !doc.scope.length)
    throw new Error(`${path.basename(policyPath)}: policy names no regions in \`scope\``);
  for (const region of doc.scope) {
    if (renderGroupsByRegion.has(region))
      throw new Error(
        `two render-group policies claim region "${region}" in their \`scope\`: ` +
          `${path.basename(policyPath)} and an earlier one. One region, one reviewed policy.`,
      );
    renderGroupsByRegion.set(region, doc);
  }
}
// The North American policy stays the one named in this file's own output
// metadata and in the family/colour validation message below; both are read
// by a reader looking at a us/ca row.
const renderGroups = JSON.parse(fs.readFileSync(RENDER_GROUPS, "utf8"));
// Every render group `byLineId` names must have a `families` entry, and that
// entry must carry a colour — deriveFamilyWindows below needs it for every
// landlord window, and a family present only as an identity (no colour) is
// exactly the "members disagree and nobody reviewed a colour" case this
// exists to catch before it reaches a fail-closed throw mid-derivation for
// one region while another region's build already succeeded. Checked once,
// over every family, so one missing entry is reported with its full member
// list rather than stopping at the first offender.
for (const doc of new Set(renderGroupsByRegion.values())) {
  const families = renderGroupFamilies(doc);
  const membersByGroup = new Map();
  for (const [lineId, groupId] of Object.entries(doc.byLineId || {})) {
    if (!membersByGroup.has(groupId)) membersByGroup.set(groupId, []);
    membersByGroup.get(groupId).push(lineId);
  }
  const problems = [];
  for (const [groupId, members] of membersByGroup) {
    const group = families[groupId];
    if (!group)
      problems.push(`"${groupId}" has no families[] entry (members: ${members.join(", ")})`);
    else if (!group.color)
      problems.push(`"${groupId}" has a families[] entry but no color (members: ${members.join(", ")})`);
  }
  if (problems.length)
    throw new Error(
      `${doc.format}: every byLineId render group needs a families[] entry with a ` +
        `reviewed colour before family windows can be derived. Do not invent a colour — ` +
        `if the family's members disagree on their published hex, that disagreement itself ` +
        `is the thing to review and record. Offending groups:\n  ${problems.join("\n  ")}`,
    );
}
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
// The reviewed convergence-hub table. Absence is not an error — a checkout
// mid-migration, or a non-NA region build, still produces valid output — but
// a present file must be the expected format so a schema drift fails loudly
// instead of silently emitting zero hub overrides.
let hubsDoc = { hubs: [] };
if (fs.existsSync(DISPLAY_HUBS)) {
  hubsDoc = JSON.parse(fs.readFileSync(DISPLAY_HUBS, "utf8"));
  if (hubsDoc.format !== "jtm-display-hubs-v1")
    throw new Error(`unexpected display-hubs format: ${hubsDoc.format}`);
}

// The reviewed loop table. The winding half of the loop contract is enforced
// in partRowsForLine (every `loop` part is emitted anticlockwise); this file
// carries the half that cannot be measured — the seam station and what the
// canonical direction is called — plus the rings this package does NOT store
// as one closed line. Validated here rather than trusted, because every claim
// in it is checkable against the package it describes.
let loopsDoc = { loops: [] };
if (fs.existsSync(DISPLAY_LOOPS)) {
  loopsDoc = JSON.parse(fs.readFileSync(DISPLAY_LOOPS, "utf8"));
  if (loopsDoc.format !== "jtm-display-loops-v1")
    throw new Error(`unexpected display-loops format: ${loopsDoc.format}`);
}

// Regions drawn as ONE continuous stroke per part, with the lane offset baked
// into the geometry by rail-stroke.js. Must stay in step with
// rail-network.js's `CONTINUOUS_STROKE_COUNTRIES` and
// build-display-network.py's `CONTINUOUS_STROKE_REGIONS`: those two decide
// what the renderers draw, and this one decides what is measured for them.
// It is also the gate on the loop-winding normalisation, because reversing a
// part changes the direction the native builder walks it in and only these
// regions read `partsByRegion` at all — the per-lane regions keep their
// geometry byte for byte until their own lane tables are re-reviewed.
const CONTINUOUS_STROKE_REGIONS = new Set(["us", "ca", "jp"]);

const byRegion = {};
const followsByRegion = {};
const familyWindowsByRegion = {};
const hubReportByRegion = {};
const partsByRegion = {};
// `strokeExcludedByRegion[region] = [[lineId, reason], ...]`: the lines a
// continuous-stroke region's own web engine (rail-network.js,
// `drawsContinuousStroke && !serviceSplitForLine`) declines to build into a
// strokeModel chain — today, a serviceStatus split (partial or whole-line
// bus substitution / suspension) — with no `partsByRegion` rows to draw
// from. This is the single source of truth build-display-network.py reads
// to decide which continuous-region lines it may draw through its
// non-continuous (per-lane) path instead of a continuous chain: any other
// line missing partsByRegion rows is a real gap and fails the build. See
// `computePartsByRegionRows` above and app/public/rail/README.md.
const strokeExcludedByRegion = {};
const colorByRegion = {};
const renderGroupByRegion = {};
const loopsByRegion = {};
const reversedLoopParts = {};
for (const region of REGIONS) {
  const pkg = JSON.parse(fs.readFileSync(path.join(RAIL_DIR, `${region}-2025.json`), "utf8"));
  const hubsForRegion = (hubsDoc.hubs || []).filter(
    (hub) => (hub.region || "us") === region,
  );
  const loopsForRegion = (loopsDoc.loops || []).filter(
    (loop) => (loop.region || "us") === region,
  );
  validateReviewedLoops(region, pkg, loopsForRegion);
  if (loopsForRegion.length) loopsByRegion[region] = loopsForRegion;
  const loopWinding = CONTINUOUS_STROKE_REGIONS.has(region) ? { reversed: [] } : null;
  const renderGroupsForRegion = renderGroupsByRegion.get(region) || {
    byLineId: {},
    families: {},
  };
  const derived = CONTINUOUS_STROKE_REGIONS.has(region)
    ? deriveDisplayRows(
        region,
        pkg,
        reviewed,
        renderGroupsForRegion,
        releasesByRegion,
        hubsForRegion,
        loopWinding,
      )
    : { rows: pkg.lanes || [], follows: [], hubReport: [] };
  // A region that derives its own rows no longer reads the package's own
  // `lanes[]`. Said out loud, because those rows are still IN the package —
  // jp-2025.json still carries the 233 hand rows this build retired — and a
  // reader comparing the two files should know which one the renderers see.
  if (CONTINUOUS_STROKE_REGIONS.has(region) && (pkg.lanes || []).length)
    process.stdout.write(
      `${region}: ${pkg.lanes.length} hand lane rows in ${region}-2025.json are NOT read ` +
        `(rows derived); tw/hk/mo/kr still pass their package rows through unchanged\n`,
    );
  if (loopWinding?.reversed.length) reversedLoopParts[region] = loopWinding.reversed;
  byRegion[region] = derived.rows;
  if (derived.follows.length) followsByRegion[region] = derived.follows;
  if (derived.familyWindows?.length) familyWindowsByRegion[region] = derived.familyWindows;
  if (derived.hubReport?.length) hubReportByRegion[region] = derived.hubReport;
  if (CONTINUOUS_STROKE_REGIONS.has(region)) {
    const colors = deriveColorByRegion(pkg, renderGroupsForRegion);
    if (Object.keys(colors).length) colorByRegion[region] = colors;
    const groupsForLine = deriveRenderGroupByRegion(pkg, renderGroupsForRegion);
    if (Object.keys(groupsForLine).length) renderGroupByRegion[region] = groupsForLine;
  }
  // `partsByRegion` is cheap outside North America too — no lane-derivation
  // sampling pass, just one displayPartsForLine per line via
  // buildNetworkFromCompactPackage — and useful as a schema, even though
  // build-display-network.py only reads it for the continuous-stroke regions
  // (us/ca) today.
  let partsRows = derived.parts;
  let partsExcluded = derived.partsExcluded;
  if (!partsRows) {
    const network = RailNetwork.buildNetworkFromCompactPackage(
      pkg,
      reviewed,
      { format: "jtm-display-lanes-v1", byRegion: {}, releasedIntervalsByRegion: releasesByRegion },
    );
    ({ rows: partsRows, excluded: partsExcluded } = computePartsByRegionRows(
      pkg,
      network,
      reviewed,
      loopWinding,
    ));
  }
  if (partsExcluded?.length) strokeExcludedByRegion[region] = partsExcluded;
  // A reversed loop part is walked the other way round by the native builder
  // than by rail-network.js, which derives its own display parts and never
  // reads `partsByRegion`. That difference is invisible for a plain stroke —
  // a ring is the same ink either way round — but a lane row or a follow row
  // is a pair of MEASURES along the part, and those mirror. So a part may
  // only be reversed while it carries neither.
  for (const key of loopWinding?.reversed || []) {
    const [lineId, partIndexRaw] = key.split("#");
    const partIndex = Number(partIndexRaw);
    const laneRow = (derived.rows || []).find(
      (row) => row[0] === lineId && row[1] === partIndex,
    );
    const followRow = (derived.follows || []).find(
      (row) =>
        (row[0] === lineId && row[1] === partIndex) ||
        (row[4] === lineId && row[5] === partIndex),
    );
    if (laneRow || followRow)
      throw new Error(
        `${region}: loop part ${key} was reversed to the canonical winding but carries ` +
          `${laneRow ? "a lane row" : "a follow row"}. Measures along a reversed part ` +
          `mirror, and rail-network.js derives its own (unreversed) parts for the web, so ` +
          `the two renderers would disagree about which end of the ring the row applies to. ` +
          `Either give this ring a reviewed seam and orientation both sides can build from, ` +
          `or leave its winding alone.`,
      );
  }
  partsByRegion[region] = partsRows;
  const familyWindows = derived.familyWindows || [];
  const tenantWindowCount = familyWindows.filter((row) => row[4] === 1).length;
  const landlordWindowCount = familyWindows.filter((row) => row[4] === 0).length;
  process.stdout.write(
    `${region}: ${derived.rows.length} lane stretches, ${derived.follows.length} follow runs, ` +
      `${partsRows.length} part rows (${partsRows.filter((row) => row[2] >= 0).length} plain, ` +
      `${partsRows.filter((row) => (row[8] || []).length).length} with withheld spans), ` +
      `${familyWindows.length} family windows (${tenantWindowCount} tenant, ${landlordWindowCount} landlord)\n`,
  );
}

// Per-hub report: member lineIds, their assigned slot, their lane before the
// hub pass (or "none"), and the metre window the slot applies over.
for (const [region, hubs] of Object.entries(hubReportByRegion)) {
  for (const hub of hubs) {
    process.stdout.write(`\n-- hub ${hub.hubId} (${region}, ${hub.name}) --\n`);
    process.stdout.write(`   trunk: ${hub.trunkKey}\n`);
    process.stdout.write(`   ${hub.classes.length} render-key classes:\n`);
    for (const group of hub.classes) {
      const side = group.side < 0 ? "left" : group.side > 0 ? "right" : "continue";
      process.stdout.write(
        `     slot=${group.slot}  side=${side}  ${group.lineIds.join(", ")}\n`,
      );
    }
    for (const member of hub.members) {
      const side = member.side < 0 ? "left" : member.side > 0 ? "right" : "continue";
      process.stdout.write(
        `   ${member.lineId}#${member.partIndex}  slot=${member.slot}  ` +
          `previous=${member.previousLane == null ? "none" : member.previousLane}  ` +
          `window=[${member.from}, ${member.to}]m  side=${side}\n`,
      );
    }
  }
}

fs.writeFileSync(OUTPUT, `${JSON.stringify({
  format: "jtm-display-lanes-v1",
  northAmericaGrouping: ["operator", "color"],
  northAmericaRenderGroups: "na-render-groups.json",
  northAmericaRenderGroupsReviewedAt: renderGroups.reviewedAt,
  // Every region's reviewed render-group policy, by the profile it applies:
  // `operator + colour` for North America, `operator + official line name`
  // for Japan. The two `northAmerica*` keys above are the same statement for
  // us/ca only, kept for readers already reading them.
  renderGroupPolicyByRegion: Object.fromEntries(
    [...renderGroupsByRegion].map(([region, doc]) => [
      region,
      {
        format: doc.format,
        profile: doc.policy?.profile || null,
        renderGroupId: doc.policy?.renderGroupId || null,
        reviewedAt: doc.reviewedAt || null,
      },
    ]),
  ),
  excludedOperators: [...EXCLUDED_OFFSET_OPERATORS],
  excludedLineIds: [...excludedLineIds].sort(),
  reviewedSharedCorridors: "shared-corridors.json",
  // The reviewed loop table (display-loops.json), per region: seam station,
  // canonical winding and orientation for the rings, plus the rings this
  // package does not store as one closed line. See `validateReviewedLoops`.
  loopsByRegion,
  // `[lineId#partIndex]` of every `loop` part whose geometry was reversed to
  // the canonical (positive-area) winding on the way into `partsByRegion`.
  reversedLoopParts,
  byRegion,
  // `[lineId, partIndex, fromMetres, toMetres, canonicalLineId,
  //   canonicalPartIndex, canonicalFromMetres, canonicalToMetres]`: over this
  // stretch the line is drawn from the canonical part's alignment (measured
  // along that part, reversed when the two are digitised against each
  // other), then offset into its own lane. See FOLLOW_MAX_MEDIAN_METRES.
  followsByRegion,
  // `[lineId, partIndex, fromMetres, toMetres, role, groupId]`, on the
  // part's own metre ruler (same 111320 m/deg equirectangular measure as
  // every other row here), edges snapped to the nearest station measure
  // within FAMILY_WINDOW_STATION_SNAP_METRES. `role` 0 = landlord: this
  // line draws the shared family stroke over this window, in
  // `groups[groupId].color`/`colorDark`. `role` 1 = tenant: this line's own
  // stroke is NOT emitted over this window (its lane offset and ride
  // slicing still exist for rides/playback) — the landlord's stroke stands
  // for it. Derived from followsByRegion rows whose follower and leader
  // share one na-render-groups.json render group; see deriveFamilyWindows
  // above and app/public/rail/README.md.
  familyWindowsByRegion,
  // `[lineId, partIndex, firstIntervalIndex, lastIntervalIndex, vertexCount,
  //   totalMetres]` — or `[lineId, partIndex, -1, -1, vertexCount,
  //   totalMetres, kind, coordinates]` when the part is not a plain run of
  //   whole raw intervals — one row per web display part
  //   (displayPartsForLine), in partIndex order, for every region. See the
  //   file header and `partRowsForLine` above for the encoding, and
  //   app/public/rail/README.md for how build-display-network.py consumes
  //   it.
  partsByRegion,
  // `strokeExcludedByRegion[region] = [[lineId, reason], ...]` — the lines a
  // continuous-stroke region's own `partsByRegion` above has no rows for
  // because rail-network.js's web engine declines to build them into a
  // strokeModel chain (serviceStatus split; `reason` is the line's own
  // package `serviceStatus`). build-display-network.py draws exactly these
  // lines through its non-continuous per-lane path instead of a continuous
  // chain, and fails the build on any OTHER continuous-region line missing
  // partsByRegion rows. See `computePartsByRegionRows` above.
  strokeExcludedByRegion,
  // `[lineId, intervalIndex]` pairs released from the alignment gate for
  // display only, with their evidence in display-releases.json.
  releasedIntervalsByRegion: releasesByRegion,
  // `colorByRegion[region][lineId] = { color, colorDark }` for every line
  // whose na-render-groups.json render group defines a colour — see
  // deriveColorByRegion above and app/public/rail/README.md.
  colorByRegion,
  // `renderGroupByRegion[region][lineId] = groupId` for EVERY line named in
  // na-render-groups.json's `byLineId`, coloured or not — see
  // deriveRenderGroupByRegion above and app/public/rail/README.md.
  // rail-network.js's railwayIdentityFor reads this to collapse a render
  // group's members onto one railway identity, so LIRR's 11 branches (one
  // render group, no colour override needed beyond MTA blue) count as ONE
  // railway at a shared platform instead of painting a false interchange
  // ring there.
  renderGroupByRegion,
  // display-hubs.json's own convergence-hub audit trail, one entry per
  // region that had at least one hub with 2+ surviving members: which part
  // seated at which slot/side, and the class-level summary printed to the
  // console during the build. Previously computed and printed but never
  // written — a reader auditing why a hub bundled the way it did had no way
  // to see it without re-running the build locally. See computeHubOverrides
  // and app/public/rail/README.md.
  hubReportByRegion,
})}\n`);
