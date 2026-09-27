// Six dated Japan routes that require app/data/rail-history.json, plus the
// half-open validity transition at each route's event date, plus three pinned
// post-closure / post-relocation dates. The fixture child runs every input
// through both the browser RouteService and the offline PrecomputeAdapter and
// refuses to emit JSON unless their compact answers are identical.

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

export const name = "historical-routes.json";

const ROUTES = [
  {
    id: "yubari", from: "新夕張", to: "夕張", line_names: ["石勝線"], ride_date: "2018-06-01",
    pinned: [{ role: "unsolvable-2019-04-01", date: "2019-04-01" }],
  },
  {
    id: "mashike", from: "深川", to: "増毛", line_names: ["留萌線"], ride_date: "2015-06-01",
    pinned: [{ role: "unsolvable-2020-06-01", date: "2020-06-01" }],
  },
  { id: "takachiho", from: "延岡", to: "高千穂", line_names: ["高千穂線"], ride_date: "2004-06-01" },
  { id: "ofunato", from: "気仙沼", to: "盛", line_names: [], ride_date: "2019-06-01" },
  { id: "hidaka", from: "鵡川", to: "様似", line_names: ["日高線"], ride_date: "2020-06-01" },
  {
    id: "joban", from: "相馬", to: "亘理", line_names: ["常磐線"], ride_date: "2010-06-01",
    pinned: [{ role: "post-relocation-2020-06-01", date: "2020-06-01" }],
  },
];

const CHILD = `
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const appDir = process.env.HISTORICAL_ROUTES_APP_DIR;
const outFile = process.env.HISTORICAL_ROUTES_OUT;
const routes = JSON.parse(process.env.HISTORICAL_ROUTES_INPUTS);
const sandbox = await import(path.join(appDir, "scripts", "lib", "app-family-sandbox.mjs"));
const readJson = (file) => JSON.parse(fs.readFileSync(path.join(appDir, "data", file), "utf8"));
const overlay = readJson("rail-history.json");

function eventDate(route) {
  const bounds = [...overlay.sections, ...overlay.stations]
    .filter((feature) => {
      const properties = feature.properties || {};
      return route.line_names.includes(properties.line_name) ||
        properties.station_name === route.from || properties.station_name === route.to;
    })
    .map((feature) => feature.properties?.valid_to)
    .filter((date) => typeof date === "string" && date > route.ride_date)
    .sort();
  if (!bounds.length) throw new Error("No post-ride rail-history boundary for " + route.id);
  return bounds[0];
}

function priorDay(iso) {
  const date = new Date(iso + "T00:00:00Z");
  date.setUTCDate(date.getUTCDate() - 1);
  return date.toISOString().slice(0, 10);
}

function rawTrain(route, date, role) {
  const section = {
    from: route.from,
    to: route.to,
    from_n02_station_code: null,
    to_n02_station_code: null,
    line_names: route.line_names,
    operator_names: [],
  };
  return {
    id: "history-" + route.id + "-" + role,
    date,
    number: "History " + route.id,
    train_type: "",
    company: "",
    origin: route.from,
    destination: route.to,
    direction: "down",
    visible: true,
    style: { color: "#d9364f" },
    route_policy: {},
    route_sections: [section],
    stops: [
      { name: route.from, departure: "00:00", stop_type: "origin", ride_segment: true },
      { name: route.to, arrival: "01:00", stop_type: "destination", ride_segment: false },
    ],
  };
}

routes.forEach((route) => { route.event_date = eventDate(route); });
const entries = [];
for (const route of routes) {
  entries.push({ route, role: "historical", train: rawTrain(route, route.ride_date, "historical") });
  entries.push({ route, role: "before-event", train: rawTrain(route, priorDay(route.event_date), "before-event") });
  entries.push({ route, role: "at-event", train: rawTrain(route, route.event_date, "at-event") });
  for (const pin of route.pinned || []) {
    entries.push({ route, role: pin.role, train: rawTrain(route, pin.date, pin.role) });
  }
}

function freshContext() {
  const context = sandbox.makeSandbox({ userAgent: "node-historical-routes-fixture" });
  sandbox.evaluateAppScripts(context, sandbox.readOrderedAppScripts());
  context.console = { log() {}, warn() {}, error() {}, info() {} };
  return context;
}

function cloneData() {
  return {
    overlay: structuredClone(overlay),
    sections: readJson("rail-sections.json"),
    stations: readJson("stations.json"),
    matchedStops: readJson("matched-stops.json"),
    matchedRoutes: readJson("matched-routes.json"),
  };
}

function canonicalPath(features) {
  const geometryLines = (geometry) => {
    if (!geometry) return [];
    if (geometry.type === "LineString") return [geometry.coordinates || []];
    if (geometry.type === "MultiLineString") return geometry.coordinates || [];
    return [];
  };
  return (features || []).map((feature) =>
    geometryLines(feature.geometry).map((line) =>
      line.map((coordinate) =>
        Number(coordinate[0]).toFixed(5) + "," + Number(coordinate[1]).toFixed(5)
      ).join(";")
    ).join("|")
  ).join("\\n");
}

function compact(run, route, role, train) {
  const features = run.features || [];
  return {
    id: route.id + ":" + role,
    train,
    section: train.route_sections[0],
    solver_context: run.solver_context,
    outcome: run.unsolvable ? "unsolvable" : "solved",
    segment_count: features.length,
    path_digest: run.routeKeyDigest(canonicalPath(features)),
    physical_length_m: Math.round(features.reduce(
      (sum, feature) => sum + Number(feature.properties?.physical_length_m || 0), 0
    ) * 100) / 100,
  };
}

async function browserResults() {
  const context = freshContext();
  const data = cloneData();
  Object.assign(context, { __overlay: data.overlay, __sections: data.sections,
    __stations: data.stations, __matchedStops: data.matchedStops });
  await vm.runInContext(
    \`(async () => {
      activeCountry = "jp";
      loadRailHistoryOverlay(__overlay, "jp");
      applyLoadedRailHistoryToStations(__stations, "jp");
      applyLoadedRailHistoryToSections(__sections, __stations, "jp");
      AppDatasets.installRailSections(__sections);
      AppDatasets.installStations(__stations);
      AppDatasets.installMatchedData({
        matchedRoutes: { type: "FeatureCollection", features: [] },
        matchedStops: __matchedStops,
      });
      await buildStationIndexesSliced(stationsGeoJson);
    })()\`,
    context,
  );
  const answers = [];
  for (const entry of entries) {
    context.__train = structuredClone(entry.train);
    const answer = await vm.runInContext(
      \`(async () => {
        const id = appendImportedTrain(__train, null);
        const train = getTrain(id);
        const solver_context = getTrainRouteSolveContext(train);
        const features = await RouteService.warmTrain(train);
        const solve = buildTrainRouteSolveContext(train);
        return {
          solver_context,
          features,
          unsolvable: Boolean(solve && RouteService.isNegative(solve.cacheKey)),
        };
      })()\`,
      context,
    );
    answers.push(compact({ ...answer, routeKeyDigest: (value) =>
      vm.runInContext("routeKeyDigest(" + JSON.stringify(value) + ")", context) },
      entry.route, entry.role, entry.train));
  }
  return answers;
}

async function precomputeResults() {
  const context = freshContext();
  const data = cloneData();
  const solved = [];
  context.__host = {
    country: "jp",
    historyOverlays: { jp: data.overlay },
    railSections: data.sections,
    stations: data.stations,
    matchedStops: data.matchedStops,
    matchedRoutes: data.matchedRoutes,
    trainStoreText: JSON.stringify({ schema_version: "1.3", trains: entries.map((entry) => entry.train) }),
    onTrainSolved(value) { solved.push(JSON.parse(JSON.stringify(value))); },
  };
  await vm.runInContext("globalThis.PrecomputeAdapter.solveStore(__host)", context);
  return solved.map((value, index) => {
    const entry = entries[index];
    const route = value.route || {};
    context.__features = route.features || [];
    const consumedFeatures = vm.runInContext(
      "dedupeSameTrainRouteFeatures(__features)", context);
    return compact({
      solver_context: route.solver_context,
      features: consumedFeatures,
      unsolvable: route.unsolvable === true,
      routeKeyDigest: (input) => vm.runInContext(
        "routeKeyDigest(" + JSON.stringify(input) + ")", context),
    }, entry.route, entry.role, entry.train);
  });
}

const browser = await browserResults();
const precomputed = await precomputeResults();
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(precomputed)),
  JSON.parse(JSON.stringify(browser)),
  "browser and precompute historical route answers differ",
);

const byId = new Map(browser.map((entry) => [entry.id, entry]));
const cases = routes.map((route) => byId.get(route.id + ":historical"));
const eventBoundaries = routes.map((route) => ({
  id: route.id,
  event_date: route.event_date,
  before: byId.get(route.id + ":before-event"),
  at: byId.get(route.id + ":at-event"),
}));
const pinned = [];
for (const route of routes) {
  for (const pin of route.pinned || []) pinned.push(byId.get(route.id + ":" + pin.role));
}
fs.writeFileSync(outFile, JSON.stringify({ cases, eventBoundaries, pinned }));
`;

function runFixture(APP_DIR) {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "historical-routes-fixture-"));
  const childFile = path.join(scratch, "child.mjs");
  const outFile = path.join(scratch, "out.json");
  try {
    fs.writeFileSync(childFile, CHILD);
    execFileSync(process.execPath, [childFile], {
      env: {
        ...process.env,
        HISTORICAL_ROUTES_APP_DIR: APP_DIR,
        HISTORICAL_ROUTES_OUT: outFile,
        HISTORICAL_ROUTES_INPUTS: JSON.stringify(ROUTES),
      },
      stdio: ["ignore", "ignore", "inherit"],
    });
    return JSON.parse(fs.readFileSync(outFile, "utf8"));
  } finally {
    fs.rmSync(scratch, { recursive: true, force: true });
  }
}

const PINNED_OUTCOME = {
  "yubari:unsolvable-2019-04-01": "unsolvable",
  "mashike:unsolvable-2020-06-01": "unsolvable",
  "joban:post-relocation-2020-06-01": "solved",
};

export function build({ APP_DIR }) {
  const result = runFixture(APP_DIR);
  assert.equal(result.cases.length, ROUTES.length);
  assert.equal(result.eventBoundaries.length, ROUTES.length);
  assert.equal(result.pinned.length, Object.keys(PINNED_OUTCOME).length);
  for (const entry of result.pinned) {
    assert.equal(entry.outcome, PINNED_OUTCOME[entry.id], entry.id);
    assert.equal(typeof entry.segment_count, "number", entry.id);
    assert.equal(typeof entry.path_digest, "string", entry.id);
    assert.equal(typeof entry.solver_context?.history_revisions?.jp, "string", entry.id);
  }
  return {
    describes: "Six rail-history-dependent Japan routes, their automatic half-open event boundaries, and three pinned dates",
    contract:
      "Each answer was produced independently by the browser RouteService and Node PrecomputeAdapter, and generation failed unless the two answers were identical. path_digest is routeKeyDigest over features in segment order; each LineString coordinate is fixed to five decimals as lon,lat, coordinates are joined by semicolons, MultiLineString members by pipes, and features by newlines. segment_count is the emitted route feature count.",
    cases: result.cases,
    eventBoundaries: result.eventBoundaries,
    pinned: result.pinned,
  };
}
