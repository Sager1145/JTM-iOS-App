import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { evaluateAppScripts, makeSandbox } from "../scripts/lib/app-family-sandbox.mjs";

const context = makeSandbox({ userAgent: "route-editing-metadata-test" });
context.console = { log() {}, warn() {}, error() {}, info() {}, debug() {} };
evaluateAppScripts(context);
const run = (expression) => vm.runInContext(expression, context);
run("stationCandidatesIndex = new Map();");

const visitID = "00112233-4455-6677-8899-AABBCCDDEEFF";
function train(metadata) {
  return {
    id: "route-metadata", date: "2026-10-01", number: "1", train_type: "Local",
    company: "Example", origin: "A", destination: "B",
    stops: [
      { name: "A", departure: "06:00", stop_type: "origin", ride_segment: true,
        ...(metadata === undefined ? {} : { route_editing: metadata }) },
      { name: "B", arrival: "07:00", stop_type: "destination", ride_segment: true },
    ],
  };
}
function roundTrip(metadata) {
  context.__train = train(metadata);
  return JSON.parse(run("JSON.stringify(normalizeExportTrain(normalizeImportedTrain(__train)))"));
}

test("iOS visit identity and generated provenance survive web import/export", () => {
  const metadata = { visit_id: visitID, generated_by: "route-editor-v1" };
  const imported = roundTrip(metadata);
  assert.deepEqual(imported.stops[0].route_editing, metadata);
  context.__train = imported;
  run("validateTrain(__train, 0, new Set()); trainStore.trains = [__train];");
  const exported = JSON.parse(run("exportTrainStore()"));
  assert.deepEqual(exported.trains[0].stops[0].route_editing, metadata);
  context.__train = exported.trains[0];
  assert.deepEqual(JSON.parse(run("JSON.stringify(normalizeImportedTrain(__train))")).stops[0].route_editing, metadata);
});

test("legacy stops retain no route editing field and null optional values are omitted", () => {
  for (const metadata of [undefined, null])
    assert.equal(Object.hasOwn(roundTrip(metadata).stops[0], "route_editing"), false);
  assert.deepEqual(roundTrip({ visit_id: visitID, generated_by: null }).stops[0].route_editing,
    { visit_id: visitID });
  assert.deepEqual(roundTrip({ visit_id: visitID.toLowerCase(), future_field: true }).stops[0].route_editing,
    { visit_id: visitID.toLowerCase() });
});

test("malformed route editing identity or provenance is rejected", () => {
  for (const metadata of [{}, [], "invalid", { visit_id: "bad" },
    { visit_id: 42 }, { visit_id: visitID, generated_by: 42 }]) {
    assert.throws(() => roundTrip(metadata), /route_editing/);
  }
  context.__train = roundTrip(undefined);
  context.__train.stops[0].route_editing = { visit_id: "bad" };
  assert.throws(() => run("validateTrain(__train, 0, new Set())"), /valid visit_id/);
});
