import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { evaluateAppScripts, makeSandbox } from "../scripts/lib/app-family-sandbox.mjs";
const context = makeSandbox({userAgent: "region-store-test"});
context.console = {log() {}, warn() {}, error() {}, info() {}, debug() {}};
evaluateAppScripts(context);
const run = (expression) => vm.runInContext(expression, context);
run("stationCandidatesIndex = new Map();");

for (const country of ["jp", "tw", "hk", "mo", "kr", "us", "ca"]) {
  test(`${country} keeps its country and timetable fields through import/export`, () => {
    context.__train = {id: "region_01", date: "2026-09-30", number: "Service 1", region: country,
      number_en: "Service 1", vehicle_type: "Vehicle", train_type: "Express", company: "Operator",
      origin: "A", destination: "B", notes: "Published notes",
      stops: [{name: "A", departure: "07:00", platform_number: 0},
              {name: "B", arrival: "07:30", platform_number: null}]};
    const output = JSON.parse(run("JSON.stringify(normalizeExportTrain(normalizeImportedTrain(__train)))"));
    assert.equal(output.region, country);
    assert.equal(output.number_en, "Service 1");
    assert.equal(output.vehicle_type, "Vehicle");
    assert.equal(output.notes, "Published notes");
    assert.equal(output.stops[0].platform_number, 0);
    assert.equal(output.stops[1].platform_number, null);
    context.__train = output;
    assert.doesNotThrow(() => run("normalizeImportedTrain(__train)"));
  });
}

test("North American precompute manifests attest both countries in the shared scope", () => {
  for (const country of ["us", "ca"]) {
    context.__country = country;
    const result = JSON.parse(run("JSON.stringify(precomputeManifestSolverContext({country: __country, historyHashes: {}}))"));
    assert.deepEqual(result.history_revisions, {ca: "none", us: "none"});
  }
});
