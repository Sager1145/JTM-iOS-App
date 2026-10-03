import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { createRequire } from "node:module";
import { makeSandbox, evaluateAppScripts } from "../scripts/lib/app-family-sandbox.mjs";

const require = createRequire(import.meta.url);
const RailNetwork = require("../public/rail-network.js");
const read = (relative) => JSON.parse(fs.readFileSync(new URL(relative, import.meta.url), "utf8"));
const trunkId = "jp-北海道旅客鉄道-函館線";
const branchId = `${trunkId}-2`;
const ids = new Set([trunkId, branchId, `${trunkId}-p1`]);
const fullPackage = read("../public/rail/jp-2025.json");
const pkg = { ...fullPackage, lines: fullPackage.lines.filter((line) => ids.has(line.id)) };
const network = RailNetwork.buildNetworkFromCompactPackage(pkg);
const stations = read("../data/stations.json");
const fullSections = read("../data/rail-sections.json");
const sections = {
  ...fullSections,
  features: fullSections.features.filter((feature) =>
    feature.properties.N02_003 === "函館線" &&
    feature.properties.N02_004 === "北海道旅客鉄道"),
};

async function legacySandbox(connectors = false) {
  const context = makeSandbox();
  evaluateAppScripts(context);
  context.__stations = stations;
  context.__sections = sections;
  await vm.runInContext(
    "AppDatasets.installStations(__stations); buildStationIndexesSliced(__stations)", context);
  vm.runInContext(`
    AppDatasets.installRailSections(__sections);
    globalThis.__graph = buildRouteGraphFromFeatures(__sections.features);
    importInProgress = true;
  `, context);
  context.RailMap.permitsStationConnectorNode = (stationCode, point) =>
    RailNetwork.permitsStationConnectorNode(network, stationCode, point);
  if (connectors) vm.runInContext("addStationTransferConnectorEdges(__graph)", context);
  context.RailMap.canonicalizeRouteFeature = (feature, options) =>
    RailNetwork.canonicalizeRouteFeature(network, feature, options);
  return context;
}

for (const [toCode, toName, connectors] of [["000455", "函館", false], ["000426", "大沼公園", false], ["000426", "大沼公園", true]]) {
  test(`legacy 鹿部→${toName}${connectors ? " with station connectors" : ""} keeps the solved route across Hakodate pieces`, async () => {
    const context = await legacySandbox(connectors);
    context.__section = {
      from: "鹿部", to: toName,
      from_n02_station_code: "000423", to_n02_station_code: toCode,
      line_names: ["函館線"], operator_names: ["北海道旅客鉄道"],
    };
    context.__train = {
      id: `hakodate-legacy-${toCode}`, date: "2026-09-30", company: "JR北海道",
      stops: [{ name: "鹿部", n02_station_code: "000423", ride_segment: true },
        { name: toName, n02_station_code: toCode, ride_segment: true }],
      route_sections: [context.__section],
      route_policy: {
        preferred_line_names: ["函館線"],
        preferred_operator_names: ["北海道旅客鉄道"],
        allowed_institution_type_codes: ["2"],
      },
    };
    const solved = vm.runInContext(
      'solveRouteSectionOnN02Graph(__section, 0, __train, __graph, ["2"])', context);
    assert.ok(solved, "the real N02 graph connects the branch and trunk");
    assert.ok(solved.geometry.coordinates.length > 100, "use a solved surveyed path, not endpoint chords");
    const matched = RailNetwork.canonicalizeRouteFeature(network, solved);
    assert.ok(matched, "the complete raw path identifies connected physical intervals");
    assert.equal(matched.properties.display_route_match, "solved-path-physical-intervals");
    assert.equal(matched.properties.display_line_ids[0], branchId);
    assert.equal(matched.properties.display_line_ids.at(-1), trunkId);
    if (toCode === "000426")
      assert.deepEqual(matched.properties.display_line_ids, [branchId, trunkId]);
    else {
      assert.equal(matched.properties.display_route_direction_corrected, true);
      assert.ok(!matched.properties.display_line_ids.includes(`${trunkId}-p1`),
        "the down-only 七飯→大沼 alignment cannot carry the reverse ride");
      const shinHakodate = pkg.lines[0].stations.find((station) => station[0] === "000429");
      assert.ok(matched.geometry.coordinates.some((point) =>
        point[0] === shinHakodate[2] && point[1] === shinHakodate[3]));
    }
    assert.equal(matched.properties.section_codes[0], `${branchId}@000423:000427`);
    assert.ok(matched.properties.physical_length_m > 0);
    assert.equal(matched.properties.physical_length_m, matched.properties.raw_physical_length_m);
    if (toCode === "000455") assert.ok(matched.properties.physical_length_m > solved.properties.physical_length_m,
      "correcting the reverse bypass also updates the selected source mileage");
    const destination = pkg.lines[0].stations.find((station) => station[0] === toCode);
    assert.deepEqual(matched.geometry.coordinates[0], pkg.lines[1].stations[6].slice(2, 4));
    assert.deepEqual(matched.geometry.coordinates.at(-1), destination.slice(2, 4));
    context.__solved = solved;
    vm.runInContext(`AppDatasets.installMatchedData({
      matchedRoutes: { type: "FeatureCollection", features: [__solved] },
      matchedStops: { type: "FeatureCollection", features: [] }
    })`, context);
    const displayed = vm.runInContext("getMatchedRouteFeatures(__train)", context);
    assert.equal(displayed.length, 1);
    assert.equal(displayed[0].properties.display_geometry_source, "all-railways-complete-line");
    assert.deepEqual(displayed[0].geometry, matched.geometry,
      "the display pipeline uses the dedicated physical interval match");
  });
}

function trunkBranchTrunk(reverse) {
  const trunk = pkg.lines.find((line) => line.id === trunkId);
  const branch = pkg.lines.find((line) => line.id === branchId);
  const intervalCode = (lineId, from, to) => `${lineId}@${[from, to].sort().join(":")}`;
  // 駒ヶ岳→森→砂原支線→大沼→大沼公園. The same trunk id occurs
  // twice, but the path never revisits a station; its chosen detour is explicit.
  const codes = [intervalCode(trunkId, "000424", "000420"),
    ...branch.stations.slice(0, -1).map((station, index) =>
      intervalCode(branchId, station[0], branch.stations[index + 1][0])),
    intervalCode(trunkId, "000427", "000426")];
  const from = trunk.stations.find((station) => station[0] === "000424").slice(2, 4);
  const to = trunk.stations.find((station) => station[0] === "000426").slice(2, 4);
  return {
    type: "Feature",
    properties: {
      required_line_ids: [trunkId, branchId], required_line_names: ["函館線"],
      from_n02_station_code: reverse ? "000426" : "000424",
      to_n02_station_code: reverse ? "000424" : "000426",
      section_codes: reverse ? codes.reverse() : codes,
    },
    geometry: { type: "LineString", coordinates: reverse ? [to, from] : [from, to] },
  };
}

test("explicit Hakodate trunk→branch→trunk joins shared stations in both directions", () => {
  const forward = RailNetwork.canonicalizeRouteFeature(network, trunkBranchTrunk(false));
  const backward = RailNetwork.canonicalizeRouteFeature(network, trunkBranchTrunk(true));
  assert.ok(forward);
  assert.ok(backward);
  assert.equal(forward.geometry.type, "LineString", "both station seams weld exactly");
  assert.equal(backward.geometry.type, "LineString");
  assert.deepEqual(forward.properties.display_line_ids, [trunkId, branchId]);
  const coordinates = forward.geometry.coordinates;
  for (const code of ["000420", "000423", "000427"]) {
    const station = pkg.lines.flatMap((line) => line.stations).find((station) => station[0] === code);
    assert.ok(coordinates.some((point) => point[0] === station[2] && point[1] === station[3]),
      `the chosen route preserves station ${station[1]}`);
  }
  assert.deepEqual(backward.geometry.coordinates, coordinates.slice().reverse(),
    "reversing the coded choice preserves every vertex and seam");
});

test("whole-path evidence retains a branch detour with both endpoints on the trunk", () => {
  for (const reverse of [false, true]) {
    const coded = trunkBranchTrunk(reverse);
    const geometry = RailNetwork.sourceGeometryForIntervals(network, coded.properties);
    const raw = { ...coded, properties: { ...coded.properties }, geometry };
    delete raw.properties.section_codes;
    const matched = RailNetwork.canonicalizeRouteFeature(network, raw);
    assert.ok(matched);
    assert.equal(matched.properties.display_route_match, "solved-path-physical-intervals");
    assert.deepEqual(matched.properties.section_codes, coded.properties.section_codes,
      "endpoint coincidence cannot replace the surveyed branch with the short trunk");
    assert.deepEqual(matched.geometry,
      RailNetwork.canonicalizeRouteFeature(network, coded).geometry);
  }
});

test("a two-point chord cannot invent a multi-row physical match", () => {
  const branch = pkg.lines.find((line) => line.id === branchId);
  const trunk = pkg.lines.find((line) => line.id === trunkId);
  const raw = {
    type: "Feature",
    properties: {
      from_n02_station_code: "000423", to_n02_station_code: "000426",
      required_line_names: ["函館線"], required_operator_names: ["北海道旅客鉄道"],
    },
    geometry: { type: "LineString", coordinates: [branch.stations[6].slice(2, 4), trunk.stations[7].slice(2, 4)] },
  };
  assert.equal(RailNetwork.matchRouteAcrossLineRows(network, raw), null);
  assert.equal(RailNetwork.canonicalizeRouteFeature(network, raw), null);
});

test("same-name rows touching geometrically require a shared station identity", () => {
  const coded = trunkBranchTrunk(false);
  const raw = {
    ...coded,
    properties: {
      from_n02_station_code: "000423", to_n02_station_code: "000426",
      required_line_names: ["函館線"], required_operator_names: ["北海道旅客鉄道"],
    },
    geometry: RailNetwork.sourceGeometryForIntervals(network, {
      from_n02_station_code: "000423", to_n02_station_code: "000426",
      section_codes: [`${branchId}@000423:000427`, `${trunkId}@000426:000427`],
    }),
  };
  const disconnectedPackage = structuredClone(pkg);
  const branch = disconnectedPackage.lines.find((line) => line.id === branchId);
  // Preserve every coordinate and name, but remove the reviewed 大沼 identity
  // connecting this branch endpoint to the trunk.
  branch.stations.at(-1)[0] = "detached-onuma";
  const disconnected = RailNetwork.buildNetworkFromCompactPackage(disconnectedPackage);
  assert.equal(RailNetwork.matchRouteAcrossLineRows(disconnected, raw), null);
  assert.equal(RailNetwork.canonicalizeRouteFeature(disconnected, raw), null);
});

test("an explicit reverse choice on the sourced down-only alignment is rejected", () => {
  const pair = pkg.lines.find((line) => line.id === `${trunkId}-p1`);
  const properties = {
    from_n02_station_code: "000427", to_n02_station_code: "000431",
    required_line_ids: [pair.id], section_codes: [`${pair.id}@000427:000431`],
  };
  const geometry = RailNetwork.sourceGeometryForIntervals(network, properties);
  assert.equal(RailNetwork.canonicalizeRouteFeature(network, { properties, geometry }), null,
    "explicit physical selections are validated, never silently replaced");
});

test("an ordinary single-row trunk interval retains its existing display fit", () => {
  const trunk = pkg.lines.find((line) => line.id === trunkId);
  const geometry = { type: "LineString", coordinates: RailNetwork.decodeIntervals(trunk)[7] };
  const feature = { properties: {
    from_n02_station_code: "000426", to_n02_station_code: "000425",
    required_line_names: ["函館線"], required_operator_names: ["北海道旅客鉄道"],
  }, geometry };
  const matched = RailNetwork.canonicalizeRouteFeature(network, feature);
  assert.ok(matched);
  assert.deepEqual(matched.properties.display_line_ids, [trunkId]);
  assert.deepEqual(matched.geometry.coordinates[0], trunk.stations[7].slice(2, 4));
  assert.deepEqual(matched.geometry.coordinates.at(-1), trunk.stations[8].slice(2, 4));
});

test("coded statistics walk surveyed parts without counting platform-gap bridges", () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const source = { type: "MultiLineString", coordinates: [
    [[140, 42], [140.001, 42]], [[141, 42], [141.001, 42]],
  ] };
  context.RailMap.sourceRouteGeometry = () => source;
  context.__statsFeatures = [{ properties: {
    ride_segment: true, section_codes: ["surveyed-interval"], from: "A", to: "B",
  }, geometry: { type: "LineString", coordinates: [[140, 42], [141.001, 42]] } }];
  const entry = vm.runInContext(`
    getMatchedRouteFeatures = () => __statsFeatures;
    collectTrainStatsEntry({ id: "surveyed-stats", date: "2026-09-30", stops: [] },
      { map: new Map(), km: [], mask: [] });
  `, context);
  const expected = vm.runInContext("statsEdgeKm(140,42,140.001,42)+statsEdgeKm(141,42,141.001,42)", context);
  assert.ok(Math.abs(entry.km - expected) < 1e-9);
  assert.equal(entry.spans.length, 2);
});
