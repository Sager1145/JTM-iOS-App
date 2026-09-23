import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

import {
  evaluateAppScripts,
  makeSandbox,
} from "../scripts/lib/app-family-sandbox.mjs";

// ADR 0011 / docs/rail-history.md: half-open validity, ride-date filtering in
// the route solver, and the history overlay loader.
const HERE = path.dirname(fileURLToPath(import.meta.url));
const HISTORY_SOURCE = fs.readFileSync(
  path.join(HERE, "..", "public", "app-rail-history.js"),
  "utf8",
);

let shared = null;
function load() {
  if (shared) return shared;
  const context = makeSandbox();
  evaluateAppScripts(context);
  // app-rail-history.js is not in index.html yet; replay it into the same
  // global scope the family shares.
  vm.runInContext(HISTORY_SOURCE, context, { filename: "app-rail-history.js" });
  shared = { context, run: (expr) => vm.runInContext(expr, context) };
  return shared;
}

test("isRailValid truth table", () => {
  const isRailValid = load().run("isRailValid");
  // Undated ride: only edges without valid_to.
  assert.equal(isRailValid(null, null, null), true);
  assert.equal(isRailValid("2000-01-01", null, null), true);
  assert.equal(isRailValid(null, "2016-12-05", null), false);
  assert.equal(isRailValid(null, "2016-12-05", ""), false);
  // Garbage dates are treated as undated.
  assert.equal(isRailValid(null, "2016-12-05", "2016/12/04"), false);
  assert.equal(isRailValid(null, "2016-12-05", "2016-12-4"), false);
  assert.equal(isRailValid(null, "2016-12-05", "yesterday"), false);
  assert.equal(isRailValid(null, "2016-12-05", 20161204), false);
  assert.equal(isRailValid(null, null, "garbage"), true);
  // Half-open: valid on valid_from, invalid on valid_to.
  assert.equal(isRailValid("2016-12-05", null, "2016-12-05"), true);
  assert.equal(isRailValid("2016-12-05", null, "2016-12-04"), false);
  assert.equal(isRailValid(null, "2016-12-05", "2016-12-05"), false);
  assert.equal(isRailValid(null, "2016-12-05", "2016-12-04"), true);
  assert.equal(isRailValid("2010-01-01", "2016-12-05", "2012-06-01"), true);
  assert.equal(isRailValid("2010-01-01", "2016-12-05", "2009-12-31"), false);
  assert.equal(isRailValid(null, null, "2026-09-23"), true);
});

test("loadRailHistoryOverlay validates schema and revision", () => {
  const { run } = load();
  const loadOverlay = run("loadRailHistoryOverlay");
  assert.throws(() => loadOverlay({ schema_version: "2", revision: "r" }));
  assert.throws(() => loadOverlay({ schema_version: "1" }));
  assert.throws(() => loadOverlay(null));
  loadOverlay({ schema_version: "1", revision: "2026-09-23.1" });
  assert.equal(run("getRailHistoryRevision()"), "2026-09-23.1");
});

function section(lineName, operator, coordinates, raw = true) {
  return {
    type: "Feature",
    properties: raw
      ? { N02_003: lineName, N02_004: operator }
      : { line_name: lineName, operator },
    geometry: { type: "LineString", coordinates },
  };
}

test("applyRailHistory stamps matched features and reports unmatched retirements", () => {
  const applyRailHistory = load().run("applyRailHistory");
  const inside = section("留萌線", "北海道旅客鉄道", [[141.8, 43.8], [141.9, 43.9]]);
  const onEdge = section("留萌線", "北海道旅客鉄道", [[141.7, 43.7], [142.0, 44.0]]);
  const straddles = section("留萌線", "北海道旅客鉄道", [[141.8, 43.8], [142.1, 43.9]]);
  const otherLine = section("函館線", "北海道旅客鉄道", [[141.8, 43.8], [141.9, 43.9]]);
  const otherOperator = section("留萌線", "別会社", [[141.8, 43.8], [141.9, 43.9]]);
  const station = section("留萌線", "北海道旅客鉄道", [[141.85, 43.85], [141.86, 43.85]], false);
  const sections = { type: "FeatureCollection", features: [inside, onEdge, straddles, otherLine, otherOperator] };
  const stations = [station];
  const overlay = {
    schema_version: "1",
    revision: "r1",
    sections: [section("留萌線", "北海道旅客鉄道", [[141.4, 43.8], [141.5, 43.8]])],
    stations: [],
    retirements: [
      {
        history_id: "jp.rumoi.fukagawa-ishikarinumata",
        match: { line_name: "留萌線", operator: "北海道旅客鉄道", bbox: [141.7, 43.7, 142.0, 44.0] },
        valid_to: "2026-04-01",
      },
      {
        history_id: "jp.nowhere",
        match: { line_name: "存在しない線", operator: "北海道旅客鉄道", bbox: [0, 0, 1, 1] },
        valid_to: "2020-01-01",
      },
    ],
  };
  const report = applyRailHistory(overlay, sections, stations);
  assert.equal(report.sectionsAdded, 1);
  assert.equal(report.stationsAdded, 0);
  assert.deepEqual({ ...report.retirementsApplied }, { "jp.rumoi.fukagawa-ishikarinumata": 3 });
  assert.deepEqual([...report.unmatchedRetirements], ["jp.nowhere"]);
  assert.equal(inside.properties.valid_to, "2026-04-01");
  assert.equal(onEdge.properties.valid_to, "2026-04-01");
  assert.equal(station.properties.valid_to, "2026-04-01");
  assert.equal(straddles.properties.valid_to, undefined);
  assert.equal(otherLine.properties.valid_to, undefined);
  assert.equal(otherOperator.properties.valid_to, undefined);
  assert.equal(sections.features.length, 6);
});

test("dijkstraFromCandidateSources skips edges invalid on the ride date", () => {
  const { run } = load();
  const dijkstra = run("dijkstraFromCandidateSources");
  const allowedCodes = run("getAllowedInstitutionTypeCodes({})");
  const edge = (to, length, validTo = null) => ({
    to,
    length,
    institution_type_code: "1",
    railway_class_code: "11",
    line_name: "L",
    operator: "O",
    valid_from: null,
    valid_to: validTo,
  });
  // A–B direct (short, retired 2016-12-05) vs A–C–B detour (long, current).
  const adjacency = new Map([
    ["A", [edge("B", 100, "2016-12-05"), edge("C", 300)]],
    ["B", [edge("A", 100, "2016-12-05"), edge("C", 300)]],
    ["C", [edge("A", 300), edge("B", 300)]],
  ]);
  const graph = { adjacency, nodes: new Map() };
  const solve = (date) => {
    const settled = dijkstra(graph, [{ key: "A", distance: 0 }], new Set(["B"]), { date }, allowedCodes);
    assert.equal(settled.length, 1);
    return [...settled[0].pathKeys];
  };
  assert.deepEqual(solve("2010-01-01"), ["A", "B"]);
  assert.deepEqual(solve("2016-12-05"), ["A", "C", "B"]);
  assert.deepEqual(solve(null), ["A", "C", "B"]);
});

test("isRailValid treats empty-string bounds as missing", () => {
  const isRailValid = load().run("isRailValid");
  assert.equal(isRailValid("", "", null), true);
  assert.equal(isRailValid("", "", "2019-12-31"), true);
  assert.equal(isRailValid(null, "", null), true);
  assert.equal(isRailValid("", "2020-01-01", null), false);
});

test("station transfer connectors carry the stations' valid_to", () => {
  const { run } = load();
  const buildGraph = run("buildRouteGraphFromFeatures");
  const addConnectors = run("addStationTransferConnectorEdges");
  const section = (lineName, coordinates) => ({
    type: "Feature",
    properties: { N02_002: "1", N02_001: "11", N02_003: lineName, N02_004: "O" },
    geometry: { type: "LineString", coordinates },
  });
  const station = (coord, validTo) => ({
    type: "Feature",
    properties: {
      station_name: "S",
      n02_group_code: "G1",
      ...(validTo ? { valid_to: validTo } : {}),
    },
    geometry: { type: "Point", coordinates: coord },
  });
  const connectors = (validTo) => {
    const graph = buildGraph([
      section("L1", [[135.0, 35.0], [135.02, 35.0]]),
      section("L2", [[135.001, 35.001], [135.001, 35.02]]),
    ]);
    addConnectors(graph, [station([135.0, 35.0], validTo), station([135.001, 35.001], null)]);
    return [...graph.adjacency.values()].flat().filter((edge) => edge.is_station_connector);
  };
  const dated = connectors("2020-01-01");
  assert.ok(dated.length > 0);
  for (const edge of dated) assert.equal(edge.valid_to, "2020-01-01");
  const undated = connectors(null);
  assert.ok(undated.length > 0);
  for (const edge of undated) assert.equal(edge.valid_to ?? null, null);
});

test("buildTrainRouteSolveContext keys on ride date and history revision", () => {
  // Fresh family without app-rail-history.js: no overlay revision.
  const context = makeSandbox();
  evaluateAppScripts(context);
  const build = vm.runInContext("buildTrainRouteSolveContext", context);
  const train = (date) => ({
    id: "t1",
    date,
    stops: [{ station: "東京" }, { station: "品川" }],
    route_sections: [{ from: "東京", to: "品川" }],
  });
  const dated = build(train("2019-12-31"));
  assert.ok(dated, "context");
  assert.ok(dated.cacheKey.endsWith("|date:2019-12-31|history:none"), dated.cacheKey);
  const undated = build(train(null));
  assert.ok(undated.cacheKey.endsWith("|date:none|history:none"), undated.cacheKey);
});
