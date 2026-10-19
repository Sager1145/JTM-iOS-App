import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { makeSandbox, evaluateAppScripts } from "../scripts/lib/app-family-sandbox.mjs";

const surveyed = [[139, 35], [139.01, 35.001], [139.02, 35]];
async function resolve(origin, disconnected = false) {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const feature = (coordinates) => ({ type: "Feature", geometry: { type: "LineString", coordinates },
    properties: { N02_003: "Rail", N02_004: "Operator", N02_001: "12", N02_002: "4" } });
  context.__sections = { type: "FeatureCollection", features: disconnected
    ? [feature(surveyed.slice(0, 2)), feature([[139.015, 35], surveyed[2]])]
    : [feature(surveyed)] };
  context.__stations = { type: "FeatureCollection", features: ["A", "B"].map((code, index) => ({
    type: "Feature", geometry: { type: "Point", coordinates: surveyed[index * 2] },
    properties: { station_name: code, n02_station_code: code, line_name: "Rail", operator: "Operator",
      railway_class_code: "12", institution_type_code: "4" } })) };
  context.__train = { id: "admission", date: "2026-10-01", region: "jp", company: "Operator",
    train_type: "local", stops: [{ name: "A", n02_station_code: "A" }, { name: "B", n02_station_code: "B" }],
    route_sections: [{ from: "A", to: "B", from_n02_station_code: "A", to_n02_station_code: "B",
      line_names: ["Rail"], operator_names: ["Operator"], section_codes: ["missing@A:B"],
      ...(origin ? { section_codes_origin: origin } : {}) }] };
  await vm.runInContext("AppDatasets.installStations(__stations); buildStationIndexesSliced(__stations)", context);
  vm.runInContext(`AppDatasets.installRailSections(__sections);
    AppDatasets.installPhysicalRailJunctions({format:"jtm-physical-rail-junctions-v1",junctions:[]});
    importInProgress = true;`, context);
  return JSON.parse(vm.runInContext(`JSON.stringify((() => {
    const generated = [], warnings = [];
    solveTrainRouteSection(__train, __train.route_sections[0], 0, ["4"], generated, warnings);
    return { generated, warnings };
  })())`, context));
}

for (const origin of ["corridorPreference", "packageInference"]) {
  test(`failed ${origin} intervals retain surveyed physical fallback`, async () => {
    const result = await resolve(origin);
    assert.equal(result.generated.length, 1);
    assert.equal(result.warnings.length, 0);
    assert.deepEqual(result.generated[0].geometry.coordinates, surveyed);
  });
}
test("failed authored intervals cannot be replaced by the available railway", async () => {
  const result = await resolve(null);
  assert.equal(result.generated.length, 0);
  assert.equal(result.warnings.length, 1);
});
test("inferred interval fallback cannot draw a chord across disconnected surveyed rails", async () => {
  const result = await resolve("packageInference", true);
  assert.equal(result.generated.length, 0);
  assert.equal(result.warnings.length, 1);
});
