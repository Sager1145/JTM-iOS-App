// Dated Japan routes that require app/data/rail-history.json, plus the
// half-open validity transition at each route's event date, plus pinned
// post-closure, post-relocation and retired-name dates. The fixture child runs every input
// through both the browser RouteService and the offline PrecomputeAdapter and
// refuses to emit JSON unless their compact answers are identical.

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

export const name = "historical-routes.json";

const currentStations = JSON.parse(fs.readFileSync(
  new URL("../../../data/stations.json", import.meta.url), "utf8")).features;
const temporalEvents = JSON.parse(fs.readFileSync(
  new URL("../../railway/jp-rail-history-events.json", import.meta.url), "utf8")).temporal_events;
const stationRenameEvents = JSON.parse(fs.readFileSync(
  new URL("../../../data/jp-history-sources/reviewed-station-renames-2019.json",
    import.meta.url), "utf8")).events;
assert.equal(stationRenameEvents.length, 5, "Five reviewed 2019 station renames");
const historicalStations = JSON.parse(fs.readFileSync(
  new URL("../../../data/rail-history.json", import.meta.url), "utf8")).stations;
function priorDay(iso) {
  const date = new Date(iso + "T00:00:00Z");
  date.setUTCDate(date.getUTCDate() - 1);
  return date.toISOString().slice(0, 10);
}
function openingStationCode(name, line, operator) {
  const codes = [...new Set(currentStations.filter(({ properties: p }) =>
    p.station_name.normalize("NFKC") === name.normalize("NFKC") &&
      p.line_name === line && p.operator === operator
  ).map(({ properties: p }) => p.n02_station_code).filter(Boolean))];
  assert.equal(codes.length, 1, "One surveyed station membership for " + line + ": " + name);
  return codes[0];
}
function transferStationCode(event, side, name) {
  if (side === "after") return openingStationCode(name, event.after.line, event.after.operator);
  // A junction can retain the predecessor membership after one side transfers.
  // Reuse it only when the source ledger explicitly reviews that shared station.
  const shared = event.shared_predecessor_stations?.find((entry) => entry.station === name);
  if (shared?.source === "current-package") {
    const code = openingStationCode(name, event.before.line, event.before.operator);
    assert.equal(code, shared.n02_station_code, "Reviewed continuing predecessor membership");
    return code;
  }
  const sourceId = shared?.source_event_id || event.id;
  const codes = [...new Set(historicalStations.filter(({ properties: p }) =>
    p.history_id?.startsWith(sourceId + ".") && p.station_name === name &&
      p.line_name === event.before.line && p.operator === event.before.operator
  ).map(({ properties: p }) => p.n02_station_code).filter(Boolean))];
  // A transfer endpoint can retain an active predecessor membership when the
  // old railway continues beyond the transferred interval (直江津 on JR's
  // 信越線 is one such junction). The history compiler correctly does not
  // duplicate that still-current station into the overlay, so fall back to
  // the uniquely surveyed current membership for the predecessor identity.
  if (!shared && codes.length === 0)
    return openingStationCode(name, event.before.line, event.before.operator);
  assert.equal(codes.length, 1, "One surveyed predecessor membership for " + event.id + ": " + name);
  if (shared) assert.equal(codes[0], shared.n02_station_code, "Reviewed shared predecessor station code");
  return codes[0];
}
const stationOpeningOrigins = {
  "jp.station-opening.1999.techno-sakaki": "西上田",
  "jp.station-opening.2001.yashiro-kokomae": "屋代",
  "jp.station-opening.2002.shinano-kokubunji": "大屋",
  "jp.station-opening.2009.chikuma": "戸倉",
  "jp.station-opening.2006.aoyama": "盛岡",
  "jp.station-opening.2021.echigo-oshiage-hisui-kaigan": "糸魚川",
  "jp.station-opening.2018.takaoka-yabunami": "高岡",
  "jp.station-opening.2022.shin-toyamaguchi": "富山",
};
const partialOpeningControls = {
  "jp.opening.nagoya-tsurumai-kamiotai": ["庄内通", "庄内緑地公園"],
  "jp.opening.rinkai-tennozu": ["国際展示場", "東京テレポート"],
  "jp.opening.rinkai-osaki": ["東京テレポート", "天王洲アイル"],
  "jp.opening.kyoto-tozai-rokujizo": ["小野", "醍醐"],
  "jp.opening.osaka-monorail-minami-ibaraki-kadomashi": ["宇野辺", "南茨木"],
};
const isolatedOpeningEvents = temporalEvents.filter((event) => event.kind === "opening" &&
  event.geometry?.selector?.scope === "isolated_current_segment");
const reviewedPartialOpenings = JSON.parse(fs.readFileSync(
  new URL("../../../data/jp-history-sources/reviewed-partial-opening-events.json",
    import.meta.url), "utf8")).events;
assert.deepEqual(isolatedOpeningEvents.map((event) => event.id).sort(),
  reviewedPartialOpenings.map((event) => event.id).sort(), "All reviewed isolated partial openings");

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
  { id: "ofunato", from: "気仙沼", to: "盛", line_names: ["大船渡線"], ride_date: "2010-06-01" },
  { id: "hidaka", from: "鵡川", to: "様似", line_names: ["日高線"], ride_date: "2014-06-01" },
  {
    id: "joban", from: "相馬", to: "亘理", line_names: ["常磐線"], ride_date: "2010-06-01",
    pinned: [{ role: "post-relocation-2020-06-01", date: "2020-06-01" }],
  },
  ...temporalEvents.filter((event) => event.kind === "opening" &&
      event.geometry.selector.scope === "whole_identity").map((event) => ({
      id: event.id.replace("jp.opening.", ""),
      from: event.segment.from_station,
      // MLIT's 支線接続点 is a track junction, not a passenger station.
      // Exercise that opening using the nearest real station on the branch.
      to: event.id === "jp.opening.toyama-station-connection"
        ? "電鉄富山駅・エスタ前" : event.segment.to_station,
      from_n02_station_code: openingStationCode(event.segment.from_station, event.line, event.operator),
      to_n02_station_code: event.id === "jp.opening.toyama-station-connection"
        ? openingStationCode("電鉄富山駅・エスタ前", "支線", event.operator)
        : openingStationCode(event.segment.to_station, event.line, event.operator),
      line_names: event.id === "jp.opening.toyama-station-connection"
        ? [event.line, "支線"] : [event.line], ride_date: event.service_periods[0][0],
      event_date: event.service_periods[0][0], opening: true, history_id: event.id,
    })),
  ...isolatedOpeningEvents.map((event) => {
    const currentIdentity = event.after || { line: event.line, operator: event.operator };
    return {
      id: event.id.replace("jp.opening.", ""),
      from: event.segment.from_station,
      to: event.segment.to_station,
      from_n02_station_code: openingStationCode(event.segment.from_station,
        currentIdentity.line, currentIdentity.operator),
      to_n02_station_code: openingStationCode(event.segment.to_station,
        currentIdentity.line, currentIdentity.operator),
      line_names: [event.line], operator_names: [event.operator],
      ride_date: event.service_periods[0][0], event_date: event.service_periods[0][0],
      opening: true, history_id: event.id,
    };
  }),
  ...isolatedOpeningEvents.map((event) => {
    const currentIdentity = event.after || { line: event.line, operator: event.operator };
    const acceptance = event.route_acceptance;
    const endpoints = partialOpeningControls[event.id] || (acceptance?.existing_from_station &&
      acceptance.control_to_station ? [acceptance.existing_from_station, acceptance.control_to_station] : null);
    assert(endpoints, "Shared-station control for " + event.id);
    return {
      id: event.id.replace("jp.opening.", "") + "-shared-control",
      from: endpoints[0], to: endpoints[1],
      from_n02_station_code: openingStationCode(endpoints[0],
        currentIdentity.line, currentIdentity.operator),
      to_n02_station_code: openingStationCode(endpoints[1],
        currentIdentity.line, currentIdentity.operator),
      line_names: [event.line], operator_names: [event.operator],
      ride_date: priorDay(event.service_periods[0][0]),
      event_date: event.service_periods[0][0], opening_control: true, history_id: event.id,
    };
  }),
  ...temporalEvents.filter((event) => event.kind === "operator_transfer" && event.segment)
    .flatMap((event) => ["before", "after"].map((side) => ({
      id: event.id.replaceAll(".", "-") + "-" + side,
      from: event.segment.from_station,
      to: event.segment.to_station,
      from_n02_station_code: transferStationCode(event, side, event.segment.from_station),
      to_n02_station_code: transferStationCode(event, side, event.segment.to_station),
      line_names: [event[side].line],
      operator_names: [event[side].operator],
      ride_date: side === "before" ? priorDay(event.date) : event.date,
      event_date: event.date, identity_side: side, history_id: event.id,
    }))),
  ...temporalEvents.filter((event) => stationOpeningOrigins[event.id]).map((event) => ({
    id: event.id.replaceAll(".", "-"),
    from: stationOpeningOrigins[event.id], to: event.after.station,
    from_n02_station_code: openingStationCode(stationOpeningOrigins[event.id],
      event.after.line, event.after.operator),
    to_n02_station_code: openingStationCode(event.after.station, event.after.line, event.after.operator),
    line_names: [event.after.line], operator_names: [event.after.operator],
    ride_date: event.service_periods[0][0], event_date: event.service_periods[0][0],
    opening: true, history_id: event.id,
  })),
  ...stationRenameEvents.flatMap((event) => ["before", "after"].map((side) => ({
    id: event.id.replaceAll(".", "-") + "-" + side + "-name",
    from: event.route_acceptance.from_station,
    to: event[side].station,
    from_n02_station_code: openingStationCode(event.route_acceptance.from_station,
      event.after.line, event.after.operator),
    // The renamed endpoint is deliberately name-resolved at the ride date.
    // Pinning its stable current code would bypass the old/new-name boundary.
    line_names: [event[side].line], operator_names: [event[side].operator],
    ride_date: side === "before" ? priorDay(event.date) : event.date,
    event_date: event.date, name_side: side, history_id: event.id,
    old_name: event.before.station, new_name: event.after.station,
  }))),
  {
    id: "myoko-wakinoda-relocation", from: "北新井", to: "脇野田",
    line_names: ["信越線"], operator_names: ["東日本旅客鉄道"],
    ride_date: "2014-10-18", event_date: "2014-10-19", relocation: true,
    history_id: "jp-id-echigo-myoko-transfer-2015",
    pinned: [{ role: "old-name-retired-2015-03-14", date: "2015-03-14" }],
  },
  {
    id: "myoko-joetsu-myoko-rename", from: "北新井", to: "上越妙高",
    line_names: ["妙高はねうまライン"], operator_names: ["えちごトキめき鉄道"],
    from_n02_station_code: openingStationCode("北新井", "妙高はねうまライン", "えちごトキめき鉄道"),
    to_n02_station_code: openingStationCode("上越妙高", "妙高はねうまライン", "えちごトキめき鉄道"),
    ride_date: "2015-03-14", event_date: "2015-03-14", opening: true,
    history_id: "jp-id-echigo-myoko-transfer-2015",
  },
  {
    id: "sassho-covid-service-end", from: "北海道医療大学", to: "新十津川",
    line_names: ["札沼線"], operator_names: ["北海道旅客鉄道"],
    ride_date: "2020-04-17", event_date: "2020-04-18", service_end: true,
    legal_closure_date: "2020-05-07",
    history_id: "jp.jrh.sassho.iryodaigaku-shintotsukawa",
    pinned: [{ role: "legal-closure-2020-05-07", date: "2020-05-07" }],
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
  if (route.service_end) {
    const entries = [...overlay.sections, ...overlay.stations].filter((feature) =>
      feature.properties.history_id.startsWith(route.history_id));
    assert(entries.length > 0 && entries.every((feature) =>
      feature.properties.service_validity?.[1] === route.event_date &&
        feature.properties.infrastructure_validity?.[1] === route.legal_closure_date &&
        feature.properties.valid_to === route.event_date),
    "Service end and legal closure must remain distinct: " + route.id);
    return route.event_date;
  }
  if (route.relocation) {
    assert(overlay.stations.some((feature) =>
      feature.properties.history_id.startsWith(route.history_id + ".") &&
        feature.properties.station_name === route.to &&
        feature.properties.valid_to === route.event_date),
      "Relocation boundary must come from the old surveyed station: " + route.id);
    return route.event_date;
  }
  if (route.name_side) {
    assert(overlay.stations.some((feature) =>
      feature.properties.history_id.startsWith(route.history_id + ".") &&
        feature.properties.station_name === route.old_name &&
        feature.properties.valid_to === route.event_date),
    "Rename boundary must have the old surveyed station: " + route.id);
    assert(overlay.retirements.some((entry) =>
      entry.history_id === route.history_id + ".current.stations" &&
        entry.valid_from === route.event_date),
    "Rename boundary must stamp the successor station: " + route.id);
    return route.event_date;
  }
  if (route.identity_side) {
    assert(overlay.sections.some((feature) =>
      feature.properties.history_id === route.history_id + ".sections" &&
        feature.properties.valid_to === route.event_date),
      "Transfer boundary must have compiled predecessor geometry: " + route.id);
    return route.event_date;
  }
  if (route.opening || route.opening_control) {
    const entries = overlay.retirements.filter((entry) =>
      entry.history_id.startsWith(route.history_id + "."));
    assert(entries.length > 0 && entries.every((entry) => entry.valid_from === route.event_date),
      "Opening boundary must come from compiled current-feature stamps: " + route.id);
    return route.event_date;
  }
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
    from_n02_station_code: route.from_n02_station_code || null,
    to_n02_station_code: route.to_n02_station_code || null,
    line_names: route.line_names,
    operator_names: route.operator_names || [],
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
    if (process.env.HISTORICAL_ROUTES_PROGRESS) {
      process.stderr.write("browser: " + entry.route.id + ":" + entry.role + "\\n");
    }
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
  // Detach VM-owned objects so compact answers cannot retain the browser's
  // national indexes while the independent precompute context is running.
  return JSON.parse(JSON.stringify(answers));
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
if (globalThis.gc) globalThis.gc();
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
    const result = { cases: [], eventBoundaries: [], pinned: [] };
    // Each dated graph retains a large national station/section index. Release
    // it between batches instead of retaining all opening eras in one child.
    for (let start = 0; start < ROUTES.length; start += 1) {
      execFileSync(process.execPath, ['--expose-gc', '--max-old-space-size=8192', childFile], {
      env: {
        ...process.env,
        HISTORICAL_ROUTES_APP_DIR: APP_DIR,
        HISTORICAL_ROUTES_OUT: outFile,
        HISTORICAL_ROUTES_INPUTS: JSON.stringify(ROUTES.slice(start, start + 1)),
      },
      stdio: ["ignore", "ignore", "inherit"],
      });
      const batch = JSON.parse(fs.readFileSync(outFile, "utf8"));
      for (const key of Object.keys(result)) result[key].push(...batch[key]);
    }
    return result;
  } finally {
    fs.rmSync(scratch, { recursive: true, force: true });
  }
}

const PINNED_OUTCOME = {
  "yubari:unsolvable-2019-04-01": "unsolvable",
  "mashike:unsolvable-2020-06-01": "unsolvable",
  "joban:post-relocation-2020-06-01": "solved",
  "myoko-wakinoda-relocation:old-name-retired-2015-03-14": "unsolvable",
  "sassho-covid-service-end:legal-closure-2020-05-07": "unsolvable",
};

export function build({ APP_DIR }) {
  const result = runFixture(APP_DIR);
  assert.equal(result.cases.length, ROUTES.length);
  assert.equal(result.eventBoundaries.length, ROUTES.length);
  assert.equal(result.pinned.length, Object.keys(PINNED_OUTCOME).length);
  for (const route of ROUTES.filter((route) => route.opening)) {
    const boundary = result.eventBoundaries.find((entry) => entry.id === route.id);
    assert.equal(boundary.before.outcome, "unsolvable", route.id + " before opening");
    assert.equal(boundary.at.outcome, "solved", route.id + " on opening");
  }
  for (const route of ROUTES.filter((route) => route.opening_control)) {
    const boundary = result.eventBoundaries.find((entry) => entry.id === route.id);
    assert.equal(boundary.before.outcome, "solved", route.id + " before opening");
    assert.equal(boundary.at.outcome, "solved", route.id + " on opening");
  }
  for (const route of ROUTES.filter((route) => route.name_side)) {
    const boundary = result.eventBoundaries.find((entry) => entry.id === route.id);
    assert.equal(boundary.before.outcome,
      route.name_side === "before" ? "solved" : "unsolvable", route.id + " before rename");
    assert.equal(boundary.at.outcome,
      route.name_side === "before" ? "unsolvable" : "solved", route.id + " on rename");
  }
  for (const route of ROUTES.filter((route) => route.identity_side)) {
    const boundary = result.eventBoundaries.find((entry) => entry.id === route.id);
    assert.equal(boundary.before.outcome,
      route.identity_side === "before" ? "solved" : "unsolvable", route.id + " before transfer");
    assert.equal(boundary.at.outcome,
      route.identity_side === "before" ? "unsolvable" : "solved", route.id + " on transfer");
  }
  for (const route of ROUTES.filter((route) => route.relocation)) {
    const boundary = result.eventBoundaries.find((entry) => entry.id === route.id);
    assert.equal(boundary.before.outcome, "solved", route.id + " before relocation");
    assert.equal(boundary.at.outcome, "solved", route.id + " after relocation");
    assert.notEqual(boundary.before.path_digest, boundary.at.path_digest,
      route.id + " must follow the changed surveyed alignment");
  }
  for (const route of ROUTES.filter((route) => route.service_end)) {
    const boundary = result.eventBoundaries.find((entry) => entry.id === route.id);
    assert.equal(boundary.before.outcome, "solved", route.id + " on final service day");
    assert.equal(boundary.at.outcome, "unsolvable", route.id + " after final service day");
  }
  for (const entry of result.pinned) {
    assert.equal(entry.outcome, PINNED_OUTCOME[entry.id], entry.id);
    assert.equal(typeof entry.segment_count, "number", entry.id);
    assert.equal(typeof entry.path_digest, "string", entry.id);
    assert.equal(typeof entry.solver_context?.history_revisions?.jp, "string", entry.id);
  }
  return {
    describes: "Rail-history-dependent Japan routes including reviewed openings, predecessor/successor transfers, surveyed station relocation and rename boundaries, and pinned historical dates",
    contract:
      "Each answer was produced independently by the browser RouteService and Node PrecomputeAdapter, and generation failed unless the two answers were identical. path_digest is routeKeyDigest over features in segment order; each LineString coordinate is fixed to five decimals as lon,lat, coordinates are joined by semicolons, MultiLineString members by pipes, and features by newlines. segment_count is the emitted route feature count.",
    cases: result.cases,
    eventBoundaries: result.eventBoundaries,
    pinned: result.pinned,
  };
}
