import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";

import {
  evaluateAppScripts,
  makeSandbox,
} from "../scripts/lib/app-family-sandbox.mjs";

const context = makeSandbox({
  userAgent: "train-vehicle-type-test",
  fetchErrorMessage: "fetch is not available in the test sandbox",
});
context.console = { log() {}, warn() {}, error() {}, info() {}, debug() {} };
evaluateAppScripts(context);
const run = (expression) => vm.runInContext(expression, context);
run("stationCandidatesIndex = new Map();");

function train(vehicleType) {
  return {
    id: "vehicle_01",
    date: "2026-09-22",
    number: "のぞみ1号",
    train_type: "新幹線",
    ...(vehicleType === undefined ? {} : { vehicle_type: vehicleType }),
    company: "JR東海",
    origin: "東京",
    destination: "新大阪",
    stops: [
      {
        name: "東京",
        n02_station_code: null,
        platform_number: null,
        arrival: null,
        departure: "06:00",
        stop_type: "origin",
        ride_segment: true,
      },
      {
        name: "新大阪",
        n02_station_code: null,
        platform_number: null,
        arrival: "08:27",
        departure: null,
        stop_type: "destination",
        ride_segment: true,
      },
    ],
  };
}

function canonicalRoundTrip(value) {
  context.__train = value;
  return JSON.parse(
    run("JSON.stringify(normalizeExportTrain(normalizeImportedTrain(__train)))"),
  );
}

test("vehicle_type remains distinct and survives canonical import/export", () => {
  const result = canonicalRoundTrip(train("  N700S  "));
  assert.equal(result.train_type, "新幹線");
  assert.equal(result.vehicle_type, "N700S");

  context.__train = result;
  assert.doesNotThrow(() =>
    run("validateTrain(__train, 0, new Set())"),
  );
});

test("an absent vehicle_type remains absent from canonical output", () => {
  const result = canonicalRoundTrip(train(undefined));
  assert.equal(Object.hasOwn(result, "vehicle_type"), false);
});

test("vehicle_type must be a string when present", () => {
  context.__train = canonicalRoundTrip(train("N700S"));
  context.__train.vehicle_type = 700;
  assert.throws(
    () => run("validateTrain(__train, 0, new Set())"),
    /vehicle_type must be a string when present/,
  );
});
