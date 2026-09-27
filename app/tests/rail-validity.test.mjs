import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

import {
  evaluateAppScripts,
  makeSandbox,
  readOrderedAppScripts,
} from "../scripts/lib/app-family-sandbox.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));

// ADR 0011 / docs/rail-history.md: half-open validity, ride-date filtering in
// the route solver, and the history overlay loader.
let shared = null;
function load() {
  if (shared) return shared;
  const context = makeSandbox();
  evaluateAppScripts(context);
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

test("loadRailHistoryOverlay validates schema, dates, ids, and bbox", () => {
  const { run } = load();
  const loadOverlay = run("loadRailHistoryOverlay");
  assert.throws(() => loadOverlay({ schema_version: "2", revision: "r" }));
  assert.throws(() =>
    loadOverlay({
      schema_version: 1,
      revision: "r",
      sections: [],
      stations: [],
      retirements: [],
    }),
  );
  assert.throws(() => loadOverlay({ schema_version: "1" }));
  assert.throws(() => loadOverlay(null));
  const feature = (id, dates = { valid_to: "2020-02-29" }) => ({
    properties: { history_id: id, ...dates },
  });
  const retirement = (id, dates = { valid_to: "2020-02-29" }) => ({
    history_id: id,
    ...dates,
    match: { bbox: [130, 30, 140, 40] },
  });
  assert.throws(() =>
    loadOverlay({
      schema_version: "1",
      revision: "r",
      sections: [feature("null-bound", { valid_to: null })],
      stations: [],
      retirements: [],
    }),
    /cannot be null/,
  );
  assert.throws(() =>
    loadOverlay({
      schema_version: "1",
      revision: "r",
      sections: [feature("section", { valid_to: "2019-02-29" })],
      stations: [],
      retirements: [],
    }),
  );
  assert.throws(() =>
    loadOverlay({
      schema_version: "1",
      revision: "r",
      sections: [],
      stations: [feature("station", { valid_from: "2020-03-01", valid_to: "2020-03-01" })],
      retirements: [],
    }),
  );
  assert.throws(() =>
    loadOverlay({
      schema_version: "1",
      revision: "r",
      sections: [feature("blank-bound", { valid_to: "" })],
      stations: [],
      retirements: [],
    }),
  );
  assert.throws(() =>
    loadOverlay({
      schema_version: "1",
      revision: "r",
      sections: [],
      stations: [feature("duplicate"), feature("duplicate")],
      retirements: [],
    }),
  );
  assert.throws(() =>
    loadOverlay({
      schema_version: "1",
      revision: "r",
      sections: [feature("collision")],
      stations: [],
      retirements: [retirement("collision")],
    }),
  );
  assert.throws(() =>
    loadOverlay({
      schema_version: "1",
      revision: "r",
      sections: [],
      stations: [],
      retirements: [{
        ...retirement("bad-bbox"),
        match: { bbox: [140, 30, 130, Number.POSITIVE_INFINITY] },
      }],
    }),
  );
  loadOverlay({
    schema_version: "1",
    revision: "2026-09-23.1",
    sections: [feature("shared"), feature("shared")],
    stations: [feature("station")],
    retirements: [retirement("retirement")],
  });
  assert.equal(run("getRailHistoryRevision()"), "2026-09-23.1");
});

test("the shipped Japan history overlay passes the runtime validator", () => {
  const loadOverlay = load().run("loadRailHistoryOverlay");
  const overlay = JSON.parse(
    fs.readFileSync(path.join(HERE, "..", "data", "rail-history.json"), "utf8"),
  );
  assert.doesNotThrow(() => loadOverlay(overlay, "jp"));
});

test("the history module loads before boot and route graph modules", () => {
  const scripts = readOrderedAppScripts();
  const historyIndex = scripts.indexOf("app-rail-history.js");
  assert.ok(historyIndex >= 0, "app-rail-history.js is in index.html");
  assert.ok(historyIndex < scripts.indexOf("app.js"));
  assert.ok(historyIndex < scripts.indexOf("app-route-graph.js"));
});

test("the shipped Japan overlay matches and applies to current solver datasets", () => {
  const applyRailHistory = load().run("applyRailHistory");
  const read = (name) => JSON.parse(
    fs.readFileSync(path.join(HERE, "..", "data", name), "utf8"),
  );
  const overlay = read("rail-history.json");
  const sections = read("rail-sections.json");
  const stations = read("stations.json");
  const report = applyRailHistory(overlay, sections, stations);
  assert.deepEqual([...report.unmatchedRetirements], []);
  assert.equal(report.sectionsAdded, overlay.sections.length);
  assert.equal(report.stationsAdded, overlay.stations.length);
  assert.equal(
    Object.keys(report.retirementsApplied).length,
    overlay.retirements.length,
  );
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

test("applyRailHistory stamps matched features and rejects unmatched retirements atomically", () => {
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
    ],
  };
  const report = applyRailHistory(overlay, sections, stations);
  assert.equal(report.sectionsAdded, 1);
  assert.equal(report.stationsAdded, 0);
  assert.deepEqual({ ...report.retirementsApplied }, { "jp.rumoi.fukagawa-ishikarinumata": 3 });
  assert.deepEqual([...report.unmatchedRetirements], []);
  assert.equal(inside.properties.valid_to, "2026-04-01");
  assert.equal(onEdge.properties.valid_to, "2026-04-01");
  assert.equal(station.properties.valid_to, "2026-04-01");
  assert.equal(straddles.properties.valid_to, undefined);
  assert.equal(otherLine.properties.valid_to, undefined);
  assert.equal(otherOperator.properties.valid_to, undefined);
  assert.equal(sections.features.length, 6);

  const untouched = section("留萌線", "北海道旅客鉄道", [[141.8, 43.8], [141.9, 43.9]]);
  assert.throws(
    () => applyRailHistory({
      sections: [section("added", "operator", [[0, 0], [1, 1]])],
      retirements: [{
        history_id: "jp.nowhere",
        match: { line_name: "存在しない線", operator: "北海道旅客鉄道", bbox: [0, 0, 1, 1] },
        valid_to: "2020-01-01",
      }],
    }, [untouched], []),
    /unmatched retirements jp\.nowhere/,
  );
  assert.equal(untouched.properties.valid_to, undefined);
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

test("colocated retired and current memberships keep a current transfer", () => {
  const { run } = load();
  const buildGraph = run("buildRouteGraphFromFeatures");
  const addConnectors = run("addStationTransferConnectorEdges");
  const section = (lineName, coordinates) => ({
    type: "Feature",
    properties: { N02_002: "1", N02_001: "11", N02_003: lineName, N02_004: "O" },
    geometry: { type: "LineString", coordinates },
  });
  const station = (coord, bounds) => ({
    type: "Feature",
    properties: { station_name: "S", n02_group_code: "G1", ...bounds },
    geometry: { type: "Point", coordinates: coord },
  });
  const retired = station([135.0, 35.0], { valid_to: "2020-01-01" });
  const current = station([135.0, 35.0], { valid_from: "2020-01-01" });
  const other = station([135.001, 35.001], {});
  for (const shared of [[retired, current], [current, retired]]) {
    const graph = buildGraph([
      section("L1", [[135.0, 35.0], [135.02, 35.0]]),
      section("L2", [[135.001, 35.001], [135.001, 35.02]]),
    ]);
    addConnectors(graph, [...shared, other]);
    const connectors = [...graph.adjacency.values()]
      .flat()
      .filter((edge) => edge.is_station_connector);
    const currentEdges = connectors.filter((edge) => (edge.valid_to ?? null) !== "2020-01-01");
    assert.ok(currentEdges.length > 0, "current∩current connector");
    for (const edge of currentEdges) assert.notEqual(edge.valid_to, "2020-01-01");
    assert.ok(connectors.some((edge) => edge.valid_to === "2020-01-01"));
  }
});

function priorIsoDay(iso) {
  const date = new Date(`${iso}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() - 1);
  return date.toISOString().slice(0, 10);
}

test("published overlay intervals and relocations are half-open", () => {
  const isRailValid = load().run("isRailValid");
  const overlay = JSON.parse(
    fs.readFileSync(path.join(HERE, "..", "data", "rail-history.json"), "utf8"),
  );
  const events = JSON.parse(
    fs.readFileSync(
      path.join(HERE, "..", "scripts", "railway", "jp-rail-history-events.json"),
      "utf8",
    ),
  ).events.filter((event) => event.kind === "relocation");
  assert.ok(events.length > 0, "relocation events");

  const check = (from, to, label) => {
    if (from) {
      assert.equal(isRailValid(from, to ?? null, from), true, `${label} valid_from`);
      assert.equal(
        isRailValid(from, to ?? null, priorIsoDay(from)),
        false,
        `${label} day before valid_from`,
      );
    }
    if (to) {
      assert.equal(isRailValid(from ?? null, to, priorIsoDay(to)), true, `${label} day before valid_to`);
      assert.equal(isRailValid(from ?? null, to, to), false, `${label} valid_to`);
    }
  };
  const dated = (entries, kind) => {
    entries.forEach((entry, index) => {
      const source = kind === "retirements" ? entry : entry.properties;
      const from = source?.valid_from;
      const to = source?.valid_to;
      if (!from && !to) return;
      check(from, to, `${kind}[${index}]`);
    });
  };
  dated(overlay.sections, "sections");
  dated(overlay.stations, "stations");
  dated(overlay.retirements, "retirements");

  for (const event of events) {
    const retirementId = event.id.replace(".old-", ".new-");
    const old = [...overlay.sections, ...overlay.stations].filter((feature) => {
      const properties = feature.properties || {};
      return properties.history_id === event.id && properties.valid_to === event.valid_to;
    });
    assert.ok(old.length > 0, `${event.id} old bounds`);
    for (const feature of old) {
      const properties = feature.properties;
      assert.equal(
        isRailValid(properties.valid_from ?? null, properties.valid_to, priorIsoDay(event.valid_to)),
        true,
        event.id,
      );
      assert.equal(
        isRailValid(properties.valid_from ?? null, properties.valid_to, event.valid_to),
        false,
        event.id,
      );
    }
    const retirement = overlay.retirements.find((entry) => entry.history_id === retirementId);
    assert.ok(retirement, event.id);
    assert.equal(retirement.valid_from, event.valid_to, event.id);
    assert.equal(isRailValid(event.valid_to, null, priorIsoDay(event.valid_to)), false, event.id);
    assert.equal(isRailValid(event.valid_to, null, event.valid_to), true, event.id);
  }
});

test("a syntax-broken overlay string never becomes history revision none", () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const run = (expr) => vm.runInContext(expr, context);
  assert.equal(run("getRailHistoryRevision('jp')"), null);
  assert.throws(() => JSON.parse("{"));
  assert.throws(() => run('JSON.parse("{")'));
  assert.throws(() => {
    const overlay = JSON.parse("{");
    run("loadRailHistoryOverlay")(overlay, "jp");
  });
  assert.equal(run("getRailHistoryRevision('jp')"), null);
  assert.notEqual(run("getRailHistoryRevision('jp')"), "none");
});

test("buildTrainRouteSolveContext keys on ride date and history revision", () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const build = vm.runInContext("buildTrainRouteSolveContext", context);
  const get = vm.runInContext("getTrainRouteSolveContext", context);
  const train = (date) => ({
    id: "t1",
    date,
    stops: [{ station: "東京" }, { station: "品川" }],
    route_sections: [{ from: "東京", to: "品川" }],
  });
  const dated = build(train("2019-12-31"));
  assert.ok(dated, "context");
  assert.ok(dated.cacheKey.endsWith("|date:2019-12-31|history:jp:none"), dated.cacheKey);
  const undated = build(train(null));
  assert.ok(undated.cacheKey.endsWith("|date:none|history:jp:none"), undated.cacheKey);
  assert.deepEqual({ ...dated.historyRevisions }, { jp: "none" });
  const serialized = get(train("2019-12-31"));
  assert.equal(serialized.solver_version, "22");
  assert.equal(serialized.ride_date, "2019-12-31");
  assert.equal(
    serialized.route_cache_digest,
    vm.runInContext(`routeKeyDigest(${JSON.stringify(dated.cacheKey)})`, context),
  );
  assert.deepEqual({ ...serialized.history_revisions }, { jp: "none" });
  const slashDated = get(train(" 2019/12/31 "));
  assert.equal(slashDated.ride_date, "2019-12-31");
  assert.match(slashDated.route_cache_digest, /^[a-z0-9]+$/);
});

test("history provenance follows the regions each train actually touches", () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const run = (source) => vm.runInContext(source, context);
  run(`loadRailHistoryOverlay({
    schema_version: "1", revision: "ca-r1",
    sections: [], stations: [], retirements: []
  }, "ca")`);
  run(`loadRailHistoryOverlay({
    schema_version: "1", revision: "us-r2",
    sections: [], stations: [], retirements: []
  }, "us")`);
  const regionsFor = run("railHistoryRegionsForTrain");
  const revisionsFor = run("getRailHistoryRevisionsForRegions");
  const canonicalFor = run("canonicalRailHistoryRevisionsForRegions");
  const caCode = "CA-VIA-VIA-RAIL-CANADA-119-CA-OFFICIAL-TORONTO";
  const usCode = "US-AMTRAK-AMTRAK-NYP-US-OFFICIAL-NEW-YORK";
  assert.deepEqual([...regionsFor({ region: "ca", stops: [{ n02_station_code: caCode }] })], ["ca"]);
  const crossing = regionsFor({
    region: "ca",
    stops: [{ n02_station_code: caCode }, { n02_station_code: usCode }],
  });
  assert.deepEqual([...crossing], ["ca", "us"]);
  assert.deepEqual({ ...revisionsFor(crossing) }, { ca: "ca-r1", us: "us-r2" });
  assert.equal(canonicalFor(crossing), "ca:ca-r1|us:us-r2");
  assert.deepEqual([...regionsFor({ stops: [] })], ["jp"]);
});

test("an existing history section's solver validity strings are unchanged", () => {
  const { run } = load();
  const boundsOf = run("railServiceBounds");
  const buildGraph = run("buildRouteGraphFromFeatures");
  const overlay = JSON.parse(
    fs.readFileSync(path.join(HERE, "..", "data", "rail-history.json"), "utf8"),
  );
  const feature = overlay.sections.find(
    (entry) => entry.properties?.history_id === "jp.jrh.rumoi.rumoi-mashike",
  );
  assert.ok(feature, "rumoi section");
  assert.equal(feature.properties.valid_from, undefined);
  assert.equal(feature.properties.valid_to, "2016-12-05");
  const bounds = boundsOf(feature.properties);
  assert.deepEqual(
    { valid_from: bounds.valid_from, valid_to: bounds.valid_to },
    { valid_from: null, valid_to: "2016-12-05" },
  );
  // Digest input is these two strings, not a domain encoding.
  assert.equal(`${bounds.valid_from ?? ""}|${bounds.valid_to ?? ""}`, "|2016-12-05");
  const graph = buildGraph([feature]);
  const edges = [...graph.adjacency.values()].flat();
  assert.ok(edges.length > 0);
  for (const edge of edges) {
    assert.equal(edge.valid_from, null);
    assert.equal(edge.valid_to, "2016-12-05");
  }
  const withInfrastructure = {
    ...feature.properties,
    infrastructure_validity: [null, "2030-01-01"],
  };
  const unchanged = boundsOf(withInfrastructure);
  assert.equal(unchanged.valid_from, null);
  assert.equal(unchanged.valid_to, "2016-12-05");
  const serviceWins = boundsOf({
    valid_from: "2000-01-01",
    valid_to: "2020-01-01",
    service_validity: ["2010-01-01", "2011-01-01"],
    infrastructure_validity: ["2000-01-01", "2020-01-01"],
  });
  assert.equal(serviceWins.valid_from, "2010-01-01");
  assert.equal(serviceWins.valid_to, "2011-01-01");
  const onlyInfrastructure = boundsOf({
    infrastructure_validity: [null, "2019-11-01"],
  });
  assert.equal(onlyInfrastructure.valid_from, null);
  assert.equal(onlyInfrastructure.valid_to, "2019-11-01");
});

test("validators accept domain pairs and kinds and still reject corruption", () => {
  const loadOverlay = load().run("loadRailHistoryOverlay");
  const feature = (properties) => ({ properties });
  loadOverlay({
    schema_version: "1",
    revision: "r",
    sections: [feature({
      history_id: "svc",
      kind: "suspension",
      valid_to: "2023-12-27",
      service_validity: [null, "2019-11-01"],
      infrastructure_validity: [null, "2023-12-27"],
    })],
    stations: [feature({
      history_id: "infra-only",
      kind: "suspension",
      infrastructure_validity: [null, "2019-11-01"],
    })],
    retirements: [{
      history_id: "station-open",
      kind: "station_opening",
      valid_from: "2011-01-01",
      match: {
        line_name: "L",
        operator: "O",
        bbox: [0, 0, 1, 1],
        targets: ["stations"],
      },
    }],
  }, "xx");
  assert.throws(() => loadOverlay({ schema_version: "9", revision: "r" }));
  assert.throws(() => loadOverlay({
    schema_version: "1",
    revision: " ",
    sections: [],
    stations: [],
    retirements: [],
  }));
  assert.throws(() => loadOverlay({
    schema_version: "1",
    revision: "r",
    sections: [feature({ history_id: "x", valid_to: "2019-02-29" })],
    stations: [],
    retirements: [],
  }));
  assert.throws(() => loadOverlay({
    schema_version: "1",
    revision: "r",
    sections: [feature({ history_id: "x", valid_to: "2020-01-01", kind: "brt" })],
    stations: [],
    retirements: [],
  }));
  assert.throws(() => loadOverlay({
    schema_version: "1",
    revision: "r",
    sections: [feature({
      history_id: "x",
      service_validity: ["2020-01-01", "2019-01-01"],
    })],
    stations: [],
    retirements: [],
  }));
  assert.throws(() => loadOverlay({
    schema_version: "1",
    revision: "r",
    sections: [],
    stations: [feature({ history_id: "dup", valid_to: "2020-01-01" }), feature({ history_id: "dup", valid_to: "2020-01-01" })],
    retirements: [],
  }));
  assert.throws(() => loadOverlay({
    schema_version: "1",
    revision: "r",
    sections: [],
    stations: [],
    retirements: [{
      history_id: "bad-bbox",
      valid_to: "2020-01-01",
      match: { bbox: [2, 0, 1, 1] },
    }],
  }));
});

test("station-only retirement does not date the open line", () => {
  const apply = load().run("applyRailHistory");
  const line = section("L", "O", [[0.2, 0.2], [0.3, 0.2]]);
  const station = section("L", "O", [[0.2, 0.2], [0.21, 0.2]], false);
  const report = apply({
    schema_version: "1",
    revision: "r",
    sections: [],
    stations: [],
    retirements: [{
      history_id: "open.station",
      kind: "station_opening",
      valid_from: "2011-01-01",
      match: {
        line_name: "L",
        operator: "O",
        bbox: [0, 0, 1, 1],
        targets: ["stations"],
      },
    }],
  }, [line], [station]);
  assert.equal(line.properties.valid_from, undefined);
  assert.equal(station.properties.valid_from, "2011-01-01");
  assert.equal(report.retirementsApplied["open.station"], 1);
});

test("endpoint station candidates are filtered by ride date", () => {
  const filter = load().run("filterStationCandidatesByRideDate");
  const station = (name, validTo) => ({
    type: "Feature",
    properties: { station_name: name, ...(validTo ? { valid_to: validTo } : {}) },
    geometry: { type: "Point", coordinates: [141.6, 43.8] },
  });
  const features = [station("増毛", "2016-12-05"), station("留萌", null)];
  const names = (date) => filter(features, date).map((f) => f.properties.station_name);
  assert.deepEqual(names("2016-12-04"), ["増毛", "留萌"]);
  assert.deepEqual(names("2016-12-05"), ["留萌"]);
  assert.deepEqual(names(null), ["留萌"]);
});
