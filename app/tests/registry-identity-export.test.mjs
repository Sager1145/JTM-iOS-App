import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";

import {
  evaluateAppScripts,
  makeSandbox,
} from "../scripts/lib/app-family-sandbox.mjs";

const OPERATOR_PATTERN = "^op:(jp|tw|hk|mo|kr|cn):[1-9][0-9]*$";
const STATION_PATTERN = "^st:(jp|tw|hk|mo|kr|cn):[1-9][0-9]*$";

function load() {
  const context = makeSandbox();
  evaluateAppScripts(context);
  vm.runInContext("stationCandidatesIndex = new Map();", context);
  return context;
}

function stop(name, code, when, extra = {}) {
  const origin = name === "東京";
  return {
    name,
    n02_station_code: code,
    platform_number: null,
    arrival: origin ? null : when,
    departure: origin ? when : null,
    stop_type: origin ? "origin" : "destination",
    ride_segment: true,
    ...extra,
  };
}

function ride(extra = {}, stops = [stop("東京", "003700", "06:00"), stop("新大阪", "116021", "08:27")]) {
  return {
    id: "ride1",
    number: "1",
    company: "JR東海",
    origin: "東京",
    destination: "新大阪",
    region: "jp",
    stops,
    ...extra,
  };
}

function roundTrip(context, train) {
  context.train = train;
  const text = vm.runInContext(`JSON.stringify({
    imported: normalizeImportedTrain(train),
    exported: normalizeExportTrain(normalizeImportedTrain(train)),
  })`, context);
  return JSON.parse(text);
}

function rejection(context, train) {
  context.train = train;
  return vm.runInContext(`(() => {
    try {
      validateTrain(normalizeExportTrain(normalizeImportedTrain(train)), 0, new Set());
      return null;
    } catch (error) {
      return error.message;
    }
  })()`, context);
}

test("operator_id and station_id keep Swift key order through import and export", () => {
  const context = load();
  const train = ride({ operator_id: "op:jp:4" }, [
    stop("東京", "003700", "06:00", { station_id: "st:jp:1" }),
    stop("新大阪", "116021", "08:27", { station_id: "st:jp:2" }),
  ]);
  const { imported, exported } = roundTrip(context, train);
  for (const shaped of [imported, exported]) {
    const keys = Object.keys(shaped);
    assert.equal(keys[keys.indexOf("company") + 1], "operator_id");
    assert.equal(keys[keys.indexOf("operator_id") + 1], "origin");
    assert.equal(shaped.operator_id, "op:jp:4");
    assert.equal(shaped.company, "JR東海");
    const stopKeys = Object.keys(shaped.stops[0]);
    assert.equal(stopKeys[stopKeys.indexOf("n02_station_code") + 1], "station_id");
    assert.equal(stopKeys[stopKeys.indexOf("station_id") + 1], "platform_number");
    assert.deepEqual(shaped.stops.map((row) => row.station_id), ["st:jp:1", "st:jp:2"]);
    assert.equal(shaped.stops[0].n02_station_code, "003700");
  }
  const encoded = JSON.stringify(exported);
  assert.ok(encoded.includes('"company":"JR東海","operator_id":"op:jp:4","origin"'));
  assert.ok(encoded.includes('"n02_station_code":"003700","station_id":"st:jp:1","platform_number"'));
  assert.equal(rejection(context, train), null);
});

test("null registry ids are omitted and non-strings are rejected like Swift", () => {
  const context = load();
  const absent = roundTrip(context, ride({ operator_id: null }, [
    stop("東京", "003700", "06:00", { station_id: null }),
    stop("新大阪", "116021", "08:27"),
  ]));
  assert.equal(Object.hasOwn(absent.exported, "operator_id"), false);
  assert.equal(Object.hasOwn(absent.exported.stops[0], "station_id"), false);
  assert.equal(Object.hasOwn(absent.imported, "operator_id"), false);

  const numeric = ride({ operator_id: 4 });
  assert.equal(
    rejection(context, numeric),
    `Train 1: operator_id must match ${OPERATOR_PATTERN}.`,
  );
  const badStation = ride({}, [
    stop("東京", "003700", "06:00", { station_id: 4 }),
    stop("新大阪", "116021", "08:27"),
  ]);
  assert.equal(
    rejection(context, badStation),
    `Train 1 stop 1: station_id must match ${STATION_PATTERN}.`,
  );
  const emptyStation = ride({}, [
    stop("東京", "003700", "06:00", { station_id: "" }),
    stop("新大阪", "116021", "08:27"),
  ]);
  assert.equal(
    rejection(context, emptyStation),
    `Train 1 stop 1: station_id must match ${STATION_PATTERN}.`,
  );
  const badOperator = ride({ operator_id: "op:jp:0" });
  assert.equal(
    rejection(context, badOperator),
    `Train 1: operator_id must match ${OPERATOR_PATTERN}.`,
  );
  const wrongRegion = ride({ operator_id: "op:tw:1", region: "jp" });
  assert.equal(
    rejection(context, wrongRegion),
    "Train 1: operator_id region must equal the train region.",
  );

  const joint = ride({ operator_ids: ["op:jp:1", "op:jp:2"] });
  const shaped = roundTrip(context, joint);
  for (const copy of [shaped.imported, shaped.exported]) {
    const keys = Object.keys(copy);
    assert.equal(keys[keys.indexOf("company") + 1], "operator_ids");
    assert.equal(keys[keys.indexOf("operator_ids") + 1], "origin");
    assert.deepEqual(copy.operator_ids, ["op:jp:1", "op:jp:2"]);
    assert.equal(Object.hasOwn(copy, "operator_id"), false);
  }
  const both = roundTrip(context, ride({ operator_id: "op:jp:4", operator_ids: ["op:jp:1"] }));
  for (const copy of [both.imported, both.exported]) {
    const keys = Object.keys(copy);
    assert.equal(keys[keys.indexOf("operator_id") + 1], "operator_ids");
    assert.equal(keys[keys.indexOf("operator_ids") + 1], "origin");
  }
  assert.equal(rejection(context, joint), null);
  const omitted = roundTrip(context, ride({ operator_ids: [] }));
  assert.equal(Object.hasOwn(omitted.exported, "operator_ids"), false);
  assert.equal(Object.hasOwn(omitted.imported, "operator_ids"), false);
  assert.equal(
    rejection(context, ride({ operator_ids: "op:jp:1" })),
    "Train 1: operator_ids must be an array of operator ids.",
  );
  assert.equal(
    rejection(context, ride({ operator_ids: ["op:jp:0"] })),
    `Train 1: operator_ids[0] must match ${OPERATOR_PATTERN}.`,
  );
});
