// Tests for splitLegacyServiceCaption (app-store-ops.js) and its use inside
// normalizeImportedTrain. Loaded via the same classic-script-family sandbox
// scripts/build/port-fixtures/import.mjs uses, since app-store-ops.js is a
// classic script sharing one global lexical scope with its siblings.

import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";

import {
  evaluateAppScripts,
  makeSandbox,
} from "../scripts/lib/app-family-sandbox.mjs";

const context = makeSandbox({
  userAgent: "service-caption-test",
  fetchErrorMessage: "fetch is not available in the test sandbox",
});
context.console = { log() {}, warn() {}, error() {}, info() {}, debug() {} };
evaluateAppScripts(context);
const run = (expr) => vm.runInContext(expr, context);
run("stationCandidatesIndex = new Map();");

function split(caption) {
  context.__caption = caption;
  // The vm context is a different realm, so plain objects it returns are not
  // `assert.deepEqual`-reference-equal to this realm's object literals even
  // when their contents match; round-trip through JSON to compare structure.
  return JSON.parse(
    JSON.stringify(run("splitLegacyServiceCaption(__caption)")),
  );
}

const stops = () => [
  { name: "A", n02_station_code: null, arrival: null, departure: "07:00", stop_type: "origin", ride_segment: true },
  { name: "B", n02_station_code: null, arrival: "07:08", departure: null, stop_type: "destination", ride_segment: false },
];

test("splits native (latin) (number) captions", () => {
  assert.deepEqual(
    split("根室本線 普通 (Nemuro Main Line Local) (5625D)"),
    { primary: "根室本線 普通 (5625D)", latinName: "Nemuro Main Line Local" },
  );
  assert.deepEqual(
    split("はるか38号 (Haruka 38) (1038M)"),
    { primary: "はるか38号 (1038M)", latinName: "Haruka 38" },
  );
  assert.deepEqual(
    split("こだま号 (Kodama) (846A)"),
    { primary: "こだま号 (846A)", latinName: "Kodama" },
  );
  assert.deepEqual(
    split("おおぞら３号 (Ōzora 3) (4003D)"),
    { primary: "おおぞら３号 (4003D)", latinName: "Ōzora 3" },
  );
  assert.deepEqual(
    split("  KTX 산천 (KTX-Sancheon) (101)  "),
    { primary: "KTX 산천 (101)", latinName: "KTX-Sancheon" },
  );
});

test("leaves captions whole that do not match the shape", () => {
  const wholeCases = [
    "のぞみ1号 (1A)",
    "自強(3000) 125次（嘉義→高雄）",
    "台灣高鐵 161次（南港→台北）",
    "東鐵綫 官方路線示例",
    "경북선 공식 노선 예시",
    "はやぶさ (こまち) (5B)",
    "Amtrak Cascades (Seattle) (503)",
    "ひかり () (500A)",
    "ひかり (Hikari) ()",
    "",
  ];
  for (const caption of wholeCases) {
    assert.deepEqual(
      split(caption),
      { primary: caption, latinName: null },
      `expected ${JSON.stringify(caption)} to stay whole`,
    );
  }
});

test("normalizeImportedTrain splits a legacy caption into number/number_en", () => {
  context.__train = {
    id: "t1",
    number: "はるか38号 (Haruka 38) (1038M)",
    origin: "A",
    destination: "B",
    stops: stops(),
  };
  const normalized = run("normalizeImportedTrain(__train)");
  assert.equal(normalized.number, "はるか38号 (1038M)");
  assert.equal(normalized.number_en, "Haruka 38");
});

test("normalizeImportedTrain keeps an explicit number_en and leaves number alone", () => {
  context.__train = {
    id: "t2",
    number: "はるか38号 (Haruka 38) (1038M)",
    number_en: "X",
    origin: "A",
    destination: "B",
    stops: stops(),
  };
  const normalized = run("normalizeImportedTrain(__train)");
  assert.equal(normalized.number, "はるか38号 (Haruka 38) (1038M)");
  assert.equal(normalized.number_en, "X");
});

test("normalizeImportedTrain still rejects an unknown key", () => {
  context.__train = {
    id: "t3",
    number: "9M",
    nickname: "nope",
    origin: "A",
    destination: "B",
    stops: stops(),
  };
  assert.throws(() => run("normalizeImportedTrain(__train)"));
});
