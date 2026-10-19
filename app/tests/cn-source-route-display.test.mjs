import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { createRequire } from "node:module";
import { makeSandbox, evaluateAppScripts } from "../scripts/lib/app-family-sandbox.mjs";

const RailNetwork = createRequire(import.meta.url)("../public/rail-network.js");
const sourceCoordinates = [[102.70, 25.04], [102.705, 25.041], [102.71, 25.04]];
const railIdentity = '["中国铁路","国铁测试线","11","","cn-test-rail"]';
const rail = {
  id: "cn-test-rail", name: "国铁测试线", operator: "中国铁路", railwayClassCode: "11",
  stations: [["start", "Start", 102.70, 25.04], ["end", "End", 102.71, 25.04]],
  segments: [[1.1, 0, sourceCoordinates]],
};
const metro = {
  id: "cn-test-metro", name: "地铁测试线", operator: "城市地铁", railwayClassCode: "12",
  stations: [["metro-start", "Start", 102.70, 25.0401], ["metro-end", "End", 102.71, 25.0401]],
  segments: [[1.0, 0, [[102.70, 25.0401], [102.71, 25.0401]]]],
};
const networkFor = (lines) => RailNetwork.buildNetworkFromCompactPackage({ format: "compact-v1", country: "cn", lines });
const sourceFeature = () => ({
  type: "Feature",
  properties: { source_physical_identity_keys: [railIdentity] },
  geometry: { type: "LineString", coordinates: structuredClone(sourceCoordinates) },
});

test("source-qualified national rail cannot be redrawn or labelled as a nearby metro", () => {
  const feature = sourceFeature();
  assert.equal(RailNetwork.canonicalizeRouteFeature(networkFor([metro]), feature), null);
  assert.deepEqual(feature.geometry.coordinates, sourceCoordinates);
});

test("a display line may canonicalize a source path with the same full physical identity", () => {
  const matched = RailNetwork.canonicalizeRouteFeature(networkFor([rail]), sourceFeature());
  assert.ok(matched);
  assert.deepEqual(matched.properties.display_line_ids, ["cn-test-rail"]);
});

test("matching a line ID alone cannot override a different surveyed identity", () => {
  for (const change of [{ operator: "城市地铁" }, { name: "地铁测试线" },
    { railwayClassCode: "12" }, { level: "1" }, { trackID: "other-track" }]) {
    assert.equal(RailNetwork.canonicalizeRouteFeature(networkFor([{ ...rail, ...change }]), sourceFeature()), null);
  }
});

test("every selected display line needs source identity evidence", () => {
  const feature = sourceFeature();
  feature.geometry = { type: "MultiLineString", coordinates: [sourceCoordinates, metro.segments[0][2]] };
  assert.equal(RailNetwork.canonicalizeRouteFeature(networkFor([rail, metro]), feature), null);
  feature.properties.source_physical_identity_keys = [];
  feature.geometry = { type: "LineString", coordinates: sourceCoordinates };
  assert.equal(RailNetwork.canonicalizeRouteFeature(networkFor([rail]), feature), null);
});

test("legacy routes without source-node provenance retain proximity matching", () => {
  const feature = sourceFeature();
  delete feature.properties.source_physical_identity_keys;
  const matched = RailNetwork.canonicalizeRouteFeature(networkFor([metro]), feature);
  assert.ok(matched);
  assert.deepEqual(matched.properties.display_line_ids, ["cn-test-metro"]);
});

test("the CN graph solver carries traversed source identities into display matching", async () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  context.__sections = [{
    type: "Feature", geometry: { type: "LineString", coordinates: sourceCoordinates },
    properties: { operator: "中国铁路", line_name: "国铁测试线", railway_class_code: "11",
      institution_type_code: "2", track_id: "cn-test-rail", region: "CN",
      source_node_ids: [["osm-node-1", "osm-node-2", "osm-node-3"]] },
  }];
  context.__stations = { type: "FeatureCollection", features: [0, 2].map((index) => ({
    type: "Feature", geometry: { type: "Point", coordinates: sourceCoordinates[index] },
    properties: { station_name: index === 0 ? "Start" : "End", n02_station_code: index === 0 ? "start" : "end",
      operator: "中国铁路", line_name: "国铁测试线", railway_class_code: "11", institution_type_code: "2",
      line_id: "cn-test-rail", source_anchor_node_id: index + 1 },
  })) };
  context.__train = { id: "source-test", region: "cn", date: "2026-10-18", stops: [],
    route_policy: { allowed_institution_type_codes: ["2"] } };
  context.__section = { from: "Start", to: "End", from_n02_station_code: "start", to_n02_station_code: "end" };
  await vm.runInContext("buildStationIndexesSliced(__stations)", context);
  const solved = vm.runInContext(`solveRouteSectionOnN02Graph(__section, 0, __train,
    buildRouteGraphFromFeatures(__sections, []), ["2"])`, context);
  assert.ok(solved);
  assert.deepEqual(Array.from(solved.properties.source_physical_identity_keys || []), [railIdentity]);
  assert.equal(RailNetwork.canonicalizeRouteFeature(networkFor([metro]), solved), null);
  assert.deepEqual(JSON.parse(JSON.stringify(solved.geometry.coordinates)), sourceCoordinates);
  context.__train.region = "jp";
  const legacy = vm.runInContext(`solveRouteSectionOnN02Graph(__section, 0, __train,
    buildRouteGraphFromFeatures(__sections, []), ["2"])`, context);
  assert.equal(legacy.properties.source_physical_identity_keys, undefined);
});
