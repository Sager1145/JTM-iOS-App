#!/usr/bin/env node
// =========================================================================
//  audit-station-readings.mjs — does the station-name table still cover the
//  networks the app draws, and the journeys it ships?
//
//      node ios/tools/audit-station-readings.mjs [--check] [jp tw hk mo kr]
//
//  The table is `app/data/station-readings*.json`, one per region. Two kinds
//  of table live under that one name and they fail differently, so they are
//  measured differently:
//
//    * **Taiwan, Hong Kong, Macao, Korea** — the table holds the station's
//      official NAME in each of the four interface languages, and the app
//      REPLACES the package's spelling with it. A station missing from the
//      table is a station that keeps its recorded name in every language, so
//      a missing row is a defect and `--check` fails on it.
//    * **Japan** — the table holds kana, romaji and Chinese READINGS, which
//      annotate the name rather than replace it. It has always covered a
//      subset; a station missing from it simply carries no reading. Reported,
//      never fatal.
//
//  Three lookups can answer, and which one does is worth seeing rather than
//  just how many hit: the network's own composite station id
//  (`tw-alsr-alishan:tw-official-…`, what a map label passes), the operator's
//  code (`TYMC-A13`, what a journey's stop carries), and the by-NAME fallback
//  — deliberately incomplete, because a name that names two stations is left
//  out of it rather than resolved by a coin toss.
// =========================================================================

import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const require = createRequire(import.meta.url);
// The ONE station-name key rule, from its owner — never a copy of it. A copy
// that drifted would make this tool report coverage the app does not have.
const { normalizeStationName } = require(path.join(ROOT, "app", "shared", "app-core.js"));

const REGIONS = [
  { code: "jp", localizesNames: false, readings: "station-readings.json", store: "train-store.json" },
  { code: "tw", localizesNames: true, readings: "station-readings-tw.json", store: "train-store-tw.json" },
  { code: "hk", localizesNames: true, readings: "station-readings-hk.json", store: "train-store-hk.json" },
  { code: "mo", localizesNames: true, readings: "station-readings-mo.json", store: "train-store-mo.json" },
  { code: "kr", localizesNames: true, readings: "station-readings-kr.json", store: "train-store-kr.json" },
];

// What `I18N.stationName` reads for a localized-name region, and what
// `nameReadingsTyped` reads for Japan. Ordered as the interface offers them.
const FIELDS = {
  localized: ["zh_Hant", "zh_Hans", "ja", "en"],
  readings: ["kana", "romaji", "zh_Hant", "zh_Hans"],
};

const args = process.argv.slice(2);
const check = args.includes("--check");
const wanted = args.filter((a) => !a.startsWith("--"));
const regions = wanted.length
  ? REGIONS.filter((r) => wanted.includes(r.code))
  : REGIONS;

const read = (...parts) => JSON.parse(readFileSync(path.join(ROOT, ...parts), "utf8"));
const pct = (n, total) => (total === 0 ? "—" : `${((n / total) * 100).toFixed(1)}%`);

let failed = false;

for (const region of regions) {
  const pkg = read("app", "public", "rail", `${region.code}-2025.json`);
  const table = read("app", "data", region.readings);
  const byCode = table.byCode || {};
  const byName = new Map(
    Object.entries(table.byName || {}).map(([key, row]) => [normalizeStationName(key), row]),
  );
  const fields = region.localizesNames ? FIELDS.localized : FIELDS.readings;

  // ---- the networks the app draws -------------------------------------
  const hits = { composite: 0, operator: 0, name: 0, none: 0 };
  const empty = Object.fromEntries(fields.map((f) => [f, 0]));
  const uncovered = new Map(); // station id -> name
  let slots = 0;

  for (const line of pkg.lines) {
    for (const station of line.stations) {
      const [id, name] = station;
      slots += 1;
      let row = byCode[`${line.id}:${id}`];
      if (row) hits.composite += 1;
      else if ((row = byCode[id])) hits.operator += 1;
      else if ((row = byName.get(normalizeStationName(name)))) hits.name += 1;
      else {
        hits.none += 1;
        uncovered.set(id, name);
      }
      for (const field of fields) if (!row || !row[field]) empty[field] += 1;
    }
  }

  console.log(`\n=== ${region.code.toUpperCase()}  ${region.readings}`);
  console.log(
    `  package ${pkg.version}: ${pkg.lines.length} lines, ${slots} station slots` +
      `  (table: ${Object.keys(byCode).length} by code, ${byName.size} by name)`,
  );
  console.log(
    `  resolved by  network id ${hits.composite}  ·  operator code ${hits.operator}` +
      `  ·  name only ${hits.name}  ·  NO ENTRY ${hits.none} (${pct(hits.none, slots)})`,
  );
  const kind = region.localizesNames ? "name missing for" : "reading missing for";
  console.log(
    `  ${kind}: ` +
      fields.map((f) => `${f} ${empty[f]} (${pct(empty[f], slots)})`).join("  ·  "),
  );
  if (uncovered.size) {
    const sample = [...uncovered].slice(0, 8).map(([id, name]) => `${name} [${id}]`);
    console.log(`  ${uncovered.size} distinct stations with no row, e.g. ${sample.join(", ")}`);
  }

  // ---- the journeys the app ships --------------------------------------
  // A stop carries the OPERATOR's code, which is the key a journey surface
  // looks the table up by. Its coverage is a different question from the
  // network's and is the one every ride list, detail card and playback
  // caption depends on.
  let stops = 0;
  let stopHits = 0;
  const missingStops = new Map();
  try {
    const store = read("app", "data", region.store);
    for (const train of store.trains || store) {
      for (const stop of train.stops || []) {
        stops += 1;
        const code = stop.n02_station_code;
        if ((code && byCode[code]) || byName.has(normalizeStationName(stop.name))) stopHits += 1;
        else missingStops.set(code || stop.name, stop.name);
      }
    }
  } catch {
    stops = -1; // no committed store for this region
  }
  if (stops >= 0) {
    console.log(
      `  shipped journeys: ${stopHits}/${stops} stops resolve (${pct(stopHits, stops || 1)})` +
        (missingStops.size
          ? `, missing e.g. ${[...missingStops].slice(0, 5).map(([c, n]) => `${n} [${c}]`).join(", ")}`
          : ""),
    );
  }

  // A region whose table REPLACES names must have a row for every station it
  // draws, or that station reads in its own language whatever the interface
  // is set to. Japan's table annotates and has always been partial.
  if (check && region.localizesNames && hits.none > 0) {
    console.log(`  FAIL: ${hits.none} station slots have no row in a table that names stations.`);
    failed = true;
  }
}

console.log("");
if (check && failed) process.exit(1);
