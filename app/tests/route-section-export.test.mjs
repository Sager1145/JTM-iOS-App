import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { evaluateAppScripts, makeSandbox } from "../scripts/lib/app-family-sandbox.mjs";
const context = makeSandbox({ userAgent: "route-section-export-test" });
context.console = { log() {}, warn() {}, error() {}, info() {}, debug() {} };
evaluateAppScripts(context);
const run = (expression) => vm.runInContext(expression, context);
run("stationCandidatesIndex = new Map();");
const stop = (name, code = name) => ({ name, n02_station_code: code });
const section = (from, to, fromCode = from, toCode = to) => ({
  from, to, from_n02_station_code: fromCode, to_n02_station_code: toCode,
  line_ids: ["verified-line"], section_codes: ["verified-section"],
  line_names: ["Verified line"], operator_names: ["Verified operator"], number: "1M", name: "Portion",
});
function train(stops, route_sections) {
  return { id: "source_01", date: "2026-10-01", number: "Express 1", origin: stops[0].name,
    destination: stops.at(-1).name, stops, route_sections };
}
function exported(input) {
  context.__input = input;
  return JSON.parse(run("JSON.stringify(normalizeExportTrain(normalizeImportedTrain(__input)))"));
}
function pairs(sections) { return sections.map((s) => [s.from_n02_station_code, s.to_n02_station_code]); }
function assertFallback(stops, sections) {
  const output = exported(train(stops, sections));
  assert.deepEqual(pairs(output.route_sections), stops.slice(1).map((s, i) => [stops[i].n02_station_code, s.n02_station_code]));
  assert.equal(output.route_sections.length, stops.length - 1);
}

test("save and reopen keeps verified non-call boundaries without inventing stops", () => {
  const input = train([{ ...stop("A"), departure: "08:00" }, { ...stop("B"), arrival: "09:00" }], [section("A", "X"), section("X", "B")]);
  context.__input = input;
  run("trainStore = { schema_version: SCHEMA_VERSION, trains: [normalizeImportedTrain(__input)] };");
  const saved = JSON.parse(run("exportTrainStore()"));
  assert.deepEqual(pairs(saved.trains[0].route_sections), [["A", "X"], ["X", "B"]]);
  assert.deepEqual(saved.trains[0].stops.map((s) => s.name), ["A", "B"]);
  for (const s of saved.trains[0].route_sections) {
    assert.deepEqual(s.line_ids, ["verified-line"]);
    assert.deepEqual(s.section_codes, ["verified-section"]);
    assert.deepEqual(s.operator_names, ["Verified operator"]);
    assert.equal(s.number, "1M");
  }
  const reopened = exported(saved.trains[0]);
  assert.deepEqual(reopened, saved.trains[0]);
  assert.equal(reopened.stops[0].departure, "08:00");
  assert.equal(reopened.stops[1].arrival, "09:00");
});
test("ordinary aligned sections retain existing export shape", () => {
  const output = exported(train([stop("A"), stop("P"), stop("B")], [section("A", "P"), section("P", "B")]));
  assert.deepEqual(pairs(output.route_sections), [["A", "P"], ["P", "B"]]);
  assert.deepEqual(output.route_sections[0].line_ids, ["verified-line"]);
});
test("every intermediate recorded call requires an explicit boundary", () => assertFallback([stop("A"), stop("P"), stop("B")], [section("A", "X"), section("X", "B")]));
test("discontinuous chains fall back", () => assertFallback([stop("A"), stop("B")], [section("A", "X"), section("Y", "B")]));
test("incorrect starting endpoint falls back", () => assertFallback([stop("A"), stop("B")], [section("Q", "X"), section("X", "B")]));
test("incorrect final endpoint falls back", () => assertFallback([stop("A"), stop("B")], [section("A", "X"), section("X", "Q")]));
test("out-of-order recorded calls fall back", () => assertFallback([stop("A"), stop("P"), stop("Q"), stop("B")], [section("A", "Q"), section("Q", "P"), section("P", "B")]));
test("same name with conflicting boundary codes cannot connect a chain", () => assertFallback([stop("A"), stop("B")], [section("A", "X", "A", "X1"), section("X", "B", "X2", "B")]));
test("name-only source boundaries can survive save", () => {
  const output = exported(train([stop("A", null), stop("B", null)], [section("A", "X", null, null), section("X", "B", null, null)]));
  assert.equal(output.route_sections.length, 2);
  assert.deepEqual(output.route_sections.map((s) => [s.from, s.to]), [["A", "X"], ["X", "B"]]);
});
test("canonical station-code aliases match at source boundaries", () => {
  const output = exported(train([stop("A", "MTR-A"), stop("B", "MTR-B")], [section("A", "X", "TKL-A-MTR-A", "TKL-X-MTR-X"), section("X", "B", "MTR-X", "MTR-B")]));
  assert.deepEqual(pairs(output.route_sections), [["MTR-A", "MTR-X"], ["MTR-X", "MTR-B"]]);
});
test("repeated station visits consume separate boundaries", () => {
  const output = exported(train([stop("A"), stop("B"), stop("A"), stop("C")], [section("A", "X"), section("X", "B"), section("B", "A"), section("A", "C")]));
  assert.deepEqual(pairs(output.route_sections), [["A", "X"], ["X", "B"], ["B", "A"], ["A", "C"]]);
});
test("one visit cannot satisfy two repeated recorded calls", () => assertFallback([stop("A"), stop("P"), stop("P"), stop("B")], [section("A", "P"), section("P", "X"), section("X", "B")]));
test("final call may be passed at an earlier source boundary", () => {
  const output = exported(train([stop("A"), stop("B")], [section("A", "B"), section("B", "X"), section("X", "B")]));
  assert.deepEqual(pairs(output.route_sections), [["A", "B"], ["B", "X"], ["X", "B"]]);
});
test("later call may be passed before the next recorded call", () => {
  const output = exported(train([stop("A"), stop("B"), stop("C")], [section("A", "C"), section("C", "B"), section("B", "C")]));
  assert.deepEqual(pairs(output.route_sections), [["A", "C"], ["C", "B"], ["B", "C"]]);
});
test("final boundary cannot satisfy an intermediate repeated call", () => assertFallback([stop("A"), stop("B"), stop("B")], [section("A", "X"), section("X", "B")]));
