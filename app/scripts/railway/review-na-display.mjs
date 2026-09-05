#!/usr/bin/env node
/*
 * Line-by-line display review of the North American packages.
 *
 * One row per published `us`/`ca` line, measured from what the two clients
 * actually draw — the continuous-stroke model rail-network.js builds and the
 * strokes rail-stroke.js makes of it at two zooms — beside the package's own
 * alignment evidence. Nothing here is a verdict on the railway; it is the
 * ledger a reviewer walks, line by line, with the numbers that decide where
 * to look. Writes `na-2025-display-review.json` and `.md` next to the
 * packages.
 *
 *   node app/scripts/railway/review-na-display.mjs [--osm results.json]
 */
"use strict";

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const APP_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const RAIL_DIR = path.join(APP_DIR, "public", "rail");
const RailNetwork = require(path.join(APP_DIR, "public", "rail-network.js"));
const RailStroke = require(path.join(APP_DIR, "public", "rail-stroke.js"));

const LIMIT_BY_KIND = {
  streetcar: 20, tram: 20, metro: 25, lightrail: 25, monorail: 25,
  "people-mover": 25, funicular: 25, commuter: 30, regional: 35,
  intercity: 50, heritage: 50,
};
const ZOOMS = [13, 16];
const RAIL_WIDTH_PX = 1.5;
const LANE_GAP_PX = 1.2;
const CORNER_RADIUS_PX = 3.6;

function readJson(name) {
  return JSON.parse(fs.readFileSync(path.join(RAIL_DIR, name), "utf8"));
}

function railwayScaleAt(zoom) {
  return Math.min(1, Math.max(1 / 3, Math.pow(Math.SQRT2, zoom - 7)));
}

function distanceMeters(a, b) {
  const lat = ((a[1] + b[1]) / 2) * (Math.PI / 180);
  return Math.hypot((b[0] - a[0]) * 111320 * Math.cos(lat), (b[1] - a[1]) * 111320);
}

function turnDegrees(a, b, c) {
  const ax = b[0] - a[0];
  const ay = b[1] - a[1];
  const bx = c[0] - b[0];
  const by = c[1] - b[1];
  return (Math.atan2(ax * by - ay * bx, ax * bx + ay * by) * 180) / Math.PI;
}

// Seam jogs in the canonical display part, the shape rail-stroke.js tapers.
function countJogs(coordinates) {
  let jogs = 0;
  const turns = [];
  for (let i = 1; i + 1 < coordinates.length; i += 1)
    turns.push(turnDegrees(coordinates[i - 1], coordinates[i], coordinates[i + 1]));
  for (let i = 1; i + 1 < coordinates.length; i += 1) {
    const first = turns[i - 1];
    if (Math.abs(first) < 25 || Math.abs(first) > 100) continue;
    let run = 0;
    for (let j = i + 1; j + 1 < coordinates.length; j += 1) {
      run += distanceMeters(coordinates[j - 1], coordinates[j]);
      if (run > 60) break;
      const second = turns[j - 1];
      if (Math.abs(second) >= 25 && Math.sign(second) !== Math.sign(first)) {
        let net = 0;
        for (let k = i; k <= j; k += 1) net += turns[k - 1];
        if (Math.abs(net) <= 15) {
          // The lateral shift, on the engine's own rule: under 8 m it is a
          // platform bump on street track, not a seam.
          const a0 = coordinates[i - 1];
          const a1 = coordinates[i];
          const lat = (a1[1] * Math.PI) / 180;
          const ex = (a1[0] - a0[0]) * Math.cos(lat);
          const ey = a1[1] - a0[1];
          const el = Math.hypot(ex, ey) || 1;
          const px = (coordinates[j][0] - a1[0]) * Math.cos(lat);
          const py = coordinates[j][1] - a1[1];
          const lateral = (Math.abs(ex * py - ey * px) / el) * 111320;
          if (lateral >= 8) {
            jogs += 1;
            i = j;
          }
        }
        break;
      }
    }
  }
  return jogs;
}

function reversals(points) {
  let count = 0;
  for (let i = 1; i + 1 < points.length; i += 1)
    if (Math.abs(turnDegrees(points[i - 1], points[i], points[i + 1])) > 150) count += 1;
  return count;
}

function reviewRegion(region, reviewed, lanes, osmByKey) {
  const pkg = readJson(`${region}-2025.json`);
  const network = RailNetwork.buildNetworkFromCompactPackage(pkg, reviewed, lanes);
  const comparison = pkg.geometrySource?.officialGeometryComparison?.byLine || {};
  const partsByLine = new Map(network.strokeModel.lines.map((line) => [line.lineId, line.parts]));
  const followedBy = new Map();
  for (const line of network.strokeModel.lines)
    for (const part of line.parts)
      for (const follow of part.follows || [])
        followedBy.set(follow.canonLineId, (followedBy.get(follow.canonLineId) || 0) + 1);
  const released = new Set(
    (lanes.releasedIntervalsByRegion?.[region] || []).map(([id, index]) => `${id}#${index}`),
  );
  const rows = [];
  for (const compact of pkg.lines) {
    const model = network.strokeModel.lines.find((line) => line.lineId === compact.id);
    const parts = partsByLine.get(compact.id) || [];
    const blocked = comparison[compact.id]?.displayBlockedIntervals || [];
    const stillWithheld = blocked.filter((index) => !released.has(`${compact.id}#${index}`));
    const releasedHere = blocked.filter((index) => released.has(`${compact.id}#${index}`));
    const laneRows = parts.flatMap((part) => part.rows);
    const follows = parts.flatMap((part) => part.follows || []);
    const anchors = parts.reduce((sum, part) => sum + part.anchors.length, 0);
    const jogs = parts.reduce((sum, part) => sum + countJogs(part.coordinates), 0);
    const rawReversals = parts.reduce((sum, part) => sum + reversals(part.coordinates), 0);
    const strokes = {};
    for (const zoom of ZOOMS) {
      const scale = railwayScaleAt(zoom);
      let vertices = 0;
      let extraReversals = 0;
      let residualJogs = 0;
      for (const part of parts) {
        const px = part.coordinates.map((point) => RailStroke.project(point, zoom));
        const followsPx = (part.follows || [])
          .map((follow) => {
            const canon = partsByLine.get(follow.canonLineId)?.[follow.canonPartIndex];
            return canon
              ? {
                  from: follow.from, to: follow.to, canonFrom: follow.canonFrom, canonTo: follow.canonTo,
                  points: canon.coordinates.map((point) => RailStroke.project(point, zoom)),
                  measures: canon.measures,
                }
              : null;
          })
          .filter(Boolean);
        const stroke = RailStroke.buildStroke(px, {
          measures: part.measures, rows: part.rows, totalMetres: part.totalMetres,
          laneGapPx: (RAIL_WIDTH_PX + LANE_GAP_PX) * scale, minRampPx: 24,
          cornerRadiusPx: CORNER_RADIUS_PX * scale, anchors: part.anchors, follows: followsPx,
        });
        vertices += stroke.points.length;
        extraReversals += Math.max(0, reversals(stroke.points) - reversals(part.coordinates));
        residualJogs += countJogs(stroke.points.map((point) => RailStroke.unproject(point, zoom)));
      }
      strokes[`z${zoom}`] = { vertices, extraReversals, residualJogs };
    }
    const limit = LIMIT_BY_KIND[compact.kind] ?? 50;
    const osm = blocked.map((index) => osmByKey.get(`${compact.id}#${index}`)).filter(Boolean);
    const flags = [];
    if (stillWithheld.length) flags.push(`withheld:${stillWithheld.join(",")}`);
    // Several display parts with nothing withheld are the branch machinery's
    // real branches (displayPartsForLine); informational.
    if (parts.length > 1 && !blocked.length) flags.push(`branch-parts:${parts.length}`);
    for (const verdict of osm) if (verdict.verdict === "B") flags.push(`osm-confirms-defect:${verdict.index}`);
    if (jogs) flags.push(`seam-jogs:${jogs}`);
    if (strokes.z16.residualJogs) flags.push(`residual-jogs@z16:${strokes.z16.residualJogs}`);
    if (strokes.z13.extraReversals || strokes.z16.extraReversals)
      flags.push(`stroke-spikes:${strokes.z13.extraReversals}/${strokes.z16.extraReversals}`);
    if (anchors < compact.stations.length - stillWithheld.length * 0)
      if (anchors < compact.stations.length) flags.push(`beads-off-stroke:${compact.stations.length - anchors}`);
    const maxDeviation = comparison[compact.id]?.maxDeviationMeters;
    // The package kept a provenance-verified operator centreline visible
    // and recorded the lower-authority reference's disagreement as a
    // warning (na-2025.acceptance.md); the flag repeats that warning.
    if (maxDeviation != null && maxDeviation > limit && !blocked.length)
      flags.push(`reference-warning:${maxDeviation}m>${limit}m`);
    if (!comparison[compact.id]) flags.push("no-reference-comparison");
    rows.push({
      region, lineId: compact.id, name: compact.name, operator: compact.operator,
      kind: compact.kind, geometrySource: compact.geometrySource, lengthKm: compact.lengthKm,
      stations: compact.stations.length, intervals: compact.segments.length,
      displayParts: parts.length, strokeFeatures: model ? 1 : 0,
      referenceMaxDeviationM: maxDeviation ?? null,
      referenceAgreedWith: comparison[compact.id]?.agreedWith ?? null,
      limitM: limit, withheldByGate: blocked, releasedByReview: releasedHere,
      stillWithheld, osmVerdicts: osm.map((row) => `${row.index}:${row.verdict}`),
      laneRows: laneRows.length, lanes: [...new Set(laneRows.map((row) => row.lane))].sort((a, b) => a - b),
      follows: follows.length, followedBy: followedBy.get(compact.id) || 0,
      stationBeadsOnStroke: anchors, seamJogs: jogs, surveyedReversals: rawReversals,
      strokes, flags,
    });
  }
  return rows;
}

function markdown(rows) {
  const lines = [];
  lines.push("# North America display review — line by line");
  lines.push("");
  lines.push(`Generated ${new Date().toISOString().slice(0, 10)} by \`app/scripts/railway/review-na-display.mjs\` from the continuous-stroke model both clients draw (rail-network.js + rail-stroke.js). One row per published line; the flags are where a reviewer looks, not verdicts.`);
  lines.push("");
  const flagged = rows.filter((row) => row.flags.length);
  lines.push(`Lines: ${rows.length}. One continuous stroke feature each: ${rows.filter((r) => r.strokeFeatures === 1).length}. Flagged: ${flagged.length}.`);
  lines.push("");
  const counts = new Map();
  for (const row of rows) for (const flag of row.flags) {
    const key = flag.split(":")[0];
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  lines.push("Flag key: `withheld` — intervals still absent after the reviewed OSM releases; `osm-confirms-defect` — an interval measured against OSM and found wrong (kept withheld); `seam-jogs` — survey seams the engine redraws as tapers (raw count → residual at z16, which should be 0); `stroke-spikes` — reversals the drawn stroke has that the survey does not (should be 0/0); `reference-warning` — the package kept a provenance-verified centreline over a disagreeing lower-authority reference; `branch-parts` — a line drawn as several real branch strokes.");
  lines.push("");
  lines.push("| flag | lines |");
  lines.push("| --- | ---: |");
  for (const [key, count] of [...counts].sort((a, b) => b[1] - a[1])) lines.push(`| ${key} | ${count} |`);
  lines.push("");
  lines.push("| region | line | kind | km | parts | ref max m / limit | withheld → released | lanes | follows / followed by | jogs (raw → z16) | spikes z13/z16 | beads | flags |");
  lines.push("| --- | --- | --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- |");
  for (const row of rows) {
    lines.push(
      `| ${row.region} | \`${row.lineId}\` ${row.name} | ${row.kind} | ${row.lengthKm} | ${row.displayParts} | ${row.referenceMaxDeviationM ?? "–"} / ${row.limitM} | ${row.withheldByGate.length ? `${row.withheldByGate.join(",")} → ${row.releasedByReview.join(",") || "none"}` : "–"} | ${row.lanes.join(" ") || "0"} | ${row.follows} / ${row.followedBy} | ${row.seamJogs} → ${row.strokes.z16.residualJogs} | ${row.strokes.z13.extraReversals}/${row.strokes.z16.extraReversals} | ${row.stationBeadsOnStroke}/${row.stations} | ${row.flags.join(" ") || "OK"} |`,
    );
  }
  return `${lines.join("\n")}\n`;
}

// OSM verdicts: the reviewed release table is the durable record (released
// A/C rows, measured-and-kept-withheld B rows); a raw measurement run can be
// handed in with --osm to override it.
const osmArg = process.argv.indexOf("--osm");
const osmByKey = new Map();
if (fs.existsSync(path.join(RAIL_DIR, "display-releases.json"))) {
  const releases = readJson("display-releases.json");
  for (const row of [...(releases.releases || []), ...(releases.withheldAfterMeasurement || [])])
    osmByKey.set(`${row.lineId}#${row.interval}`, { ...row, index: row.interval });
}
if (osmArg >= 0 && process.argv[osmArg + 1] && fs.existsSync(process.argv[osmArg + 1]))
  for (const row of JSON.parse(fs.readFileSync(process.argv[osmArg + 1], "utf8")))
    osmByKey.set(`${row.lineId}#${row.index}`, row);
const reviewed = readJson("shared-corridors.json");
const lanes = readJson("display-lanes.json");
const rows = [...reviewRegion("us", reviewed, lanes, osmByKey), ...reviewRegion("ca", reviewed, lanes, osmByKey)];
fs.writeFileSync(
  path.join(RAIL_DIR, "na-2025-display-review.json"),
  `${JSON.stringify({ format: "jtm-na-display-review-v1", generatedAt: new Date().toISOString(), rows }, null, 1)}\n`,
);
fs.writeFileSync(path.join(RAIL_DIR, "na-2025-display-review.md"), markdown(rows));
const flagged = rows.filter((row) => row.flags.length);
process.stdout.write(`${rows.length} lines reviewed, ${flagged.length} flagged\n`);
