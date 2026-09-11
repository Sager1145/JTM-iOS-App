#!/usr/bin/env node
/* Emit the real rail-network.js display inputs for audit-zoom-chords.swift. */
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const rail = path.join(repo, "app", "public", "rail");
const RailNetwork = require(path.join(repo, "app", "public", "rail-network.js"));
const region = process.argv[2];
if (!["jp", "tw", "hk", "mo", "kr", "us", "ca"].includes(region)) {
  console.error("usage: audit-zoom-chords.mjs <jp|tw|hk|mo|kr|us|ca>");
  process.exit(2);
}

const read = (name) => JSON.parse(fs.readFileSync(path.join(rail, name), "utf8"));
const pkg = read(`${region}-2025.json`);
const displayLanes = read("display-lanes.json");
const network = RailNetwork.buildNetworkFromCompactPackage(
  pkg,
  read("shared-corridors.json"),
  displayLanes,
);
const modelByPart = new Map();
for (const line of network.strokeModel?.lines || [])
  line.parts.forEach((part, partIndex) => modelByPart.set(`${line.lineId}#${partIndex}`, part));
function measuresFor(coordinates) {
  const measures = [0];
  for (let index = 1; index < coordinates.length; index += 1) {
    const a = coordinates[index - 1], b = coordinates[index];
    const lat = ((a[1] + b[1]) / 2) * Math.PI / 180;
    measures.push(measures.at(-1) + Math.hypot(
      (b[0] - a[0]) * 111320 * Math.cos(lat),
      (b[1] - a[1]) * 111320,
    ));
  }
  return measures;
}

const compactLineById = new Map(pkg.lines.map((line) => [line.id, line]));
const displayOverrides = RailNetwork.reviewedSharedCorridorOverrides(
  pkg,
  read("shared-corridors.json"),
);
function coordinatesForPartRow(row) {
  if (row?.[7]) return row[7];
  const compactLine = compactLineById.get(row?.[0]);
  if (!compactLine || row[2] < 0 || row[3] < row[2]) return null;
  const displayOverride = displayOverrides.get(compactLine.id);
  const decoded = displayOverride?.intervals || RailNetwork.decodeIntervals({
    ...compactLine,
    stations: displayOverride?.stations || compactLine.stations,
  });
  const intervals = decoded.slice(row[2], row[3] + 1);
  if (intervals.length !== row[3] - row[2] + 1 || intervals.some((held) => held.length < 2))
    return null;
  return intervals.flatMap((held, index) => index ? held.slice(1) : held);
}

const parts = [];
for (const line of network.strokeModel?.lines || []) {
  line.parts.forEach((part, partIndex) => {
    parts.push({
      lineId: line.lineId,
      partIndex,
      coordinates: part.coordinates,
      measures: part.measures,
      totalMetres: part.totalMetres,
      rows: part.rows,
      anchors: part.anchors,
      follows: (part.follows || []).map((follow) => {
        let canonical = modelByPart.get(`${follow.canonLineId}#${follow.canonPartIndex}`);
        // A service-split canonical line is an ordinary DrawnLine in native
        // and can still be followed even though the Web does not put it in
        // strokeModel. Resolve the same decoded display part from lineById.
        if (!canonical) {
          const coordinates = network.lineById.get(follow.canonLineId)?.parts?.[follow.canonPartIndex];
          if (coordinates) canonical = { coordinates, measures: measuresFor(coordinates) };
        }
        if (!canonical) {
          const row = (displayLanes.partsByRegion?.[region] || []).find(
            (held) => held[0] === follow.canonLineId && held[1] === follow.canonPartIndex,
          );
          const coordinates = coordinatesForPartRow(row);
          if (coordinates) canonical = { coordinates, measures: measuresFor(coordinates) };
        }
        if (!canonical) throw new Error(
          `${region} ${line.lineId}#${partIndex}: missing canonical ${follow.canonLineId}#${follow.canonPartIndex}`,
        );
        return {
          from: follow.from,
          to: follow.to,
          canonFrom: follow.canonFrom,
          canonTo: follow.canonTo,
          coordinates: canonical.coordinates,
          measures: canonical.measures,
        };
      }),
    });
  });
}

// Non-continuous regions reach MapKit through the production metre-space
// Douglas-Peucker pass. Continuous placeholders have empty geometry here.
const plain = [];
for (const feature of network.segments.features) {
  if (feature.properties?.continuous) continue;
  const geometry = feature.geometry;
  const lines = geometry?.type === "LineString"
    ? [geometry.coordinates]
    : geometry?.type === "MultiLineString" ? geometry.coordinates : [];
  lines.forEach((coordinates, partIndex) => {
    if (coordinates.length >= 2) plain.push({
      lineId: feature.properties.lineId,
      partIndex,
      lane: Number(feature.properties.lane || 0),
      coordinates,
    });
  });
}

const stationCount = pkg.lines.reduce((sum, line) => sum + line.stations.length, 0);
process.stdout.write(JSON.stringify({
  region,
  version: pkg.version,
  packageLineCount: pkg.lines.length,
  packageStationMembershipCount: stationCount,
  continuousPartCount: parts.length,
  plainPartCount: plain.length,
  parts,
  plain,
}));
