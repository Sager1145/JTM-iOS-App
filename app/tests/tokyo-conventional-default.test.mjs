import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { createRequire } from "node:module";
import { makeSandbox, evaluateAppScripts } from "../scripts/lib/app-family-sandbox.mjs";

const require = createRequire(import.meta.url);
const RailNetwork = require("../public/rail-network.js");
const tunnel = "jp-東日本旅客鉄道-総武線-3";
const surface = "jp-東日本旅客鉄道-東海道線";
const full = JSON.parse(fs.readFileSync(new URL("../public/rail/jp-2025.json", import.meta.url), "utf8"));
const network = RailNetwork.buildNetworkFromCompactPackage({ ...full,
  lines: full.lines.filter((line) => [tunnel, surface, "jp-東日本旅客鉄道-総武線"].includes(line.id)) });
function setup(reverse = false) {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const visits = [{ name: "東京", n02_station_code: "003766", departure: "10:00" },
    { name: "品川", n02_station_code: "004095", arrival: "10:15" }];
  if (reverse) visits.reverse();
  context.__train = { id: "tokyo-default", region: "jp", train_type: "local", stops: visits,
    route_sections: [{ from: visits[0].name, to: visits[1].name, number: "1234M" }] };
  context.RailMap.sourceRouteGeometry = (properties) => RailNetwork.sourceGeometryForIntervals(network, properties);
  return context;
}
const infer = (context) => JSON.parse(vm.runInContext(
  "JSON.stringify(inferredTokyoConventionalSection(__train.route_sections[0], __train))", context));

for (const reverse of [false, true]) {
  test(`sparse no-Yurakucho default reaches the exact tunnel source and cache key (${reverse})`, () => {
    const context = setup(reverse);
    const before = JSON.stringify(context.__train);
    const section = infer(context);
    const codes = [`${tunnel}@003766:003872`, `${tunnel}@003872:004095`];
    assert.deepEqual(section.section_codes, reverse ? codes.reverse() : codes);
    assert.equal(section.number, "1234M");
    assert.equal(JSON.stringify(context.__train), before, "runtime inference preserves recorded visits and times");
    const result = vm.runInContext(`(() => {
      const generated = [], warnings = [];
      solveTrainRouteSection(__train, __train.route_sections[0], 0, ["2"], generated, warnings);
      return { generated, warnings, key: getTrainRouteTemplateKey(__train) };
    })()`, context);
    assert.equal(result.warnings.length, 0);
    assert.equal(result.generated.length, 1);
    assert.equal(result.generated[0].properties.source, "compact_package_physical_intervals");
    assert.ok(result.key.includes(section.section_codes.join(",")));
    const stations = full.lines.find((line) => line.id === tunnel).stations;
    assert.deepEqual(Array.from(result.generated[0].geometry.coordinates[0]), stations[reverse ? 2 : 0].slice(2,4));
    assert.deepEqual(Array.from(result.generated[0].geometry.coordinates.at(-1)), stations[reverse ? 0 : 2].slice(2,4));
  });
}

test("authored surface visits and explicit physical hints retain their route", () => {
  for (const mutate of [
    (t) => t.stops.splice(1, 0, { name: "有楽町", n02_station_code: "003795" }),
    (t) => t.stops.splice(1, 0, { name: "浜松町", n02_station_code: "003949" }),
    (t) => t.route_sections[0].section_codes = ["manual@a:b"],
    (t) => t.route_sections[0].line_ids = [surface],
    (t) => t.route_sections[0].line_names = ["東海道線"],
    (t) => t.train_type = "highSpeed",
    (t) => t.region = "tw",
    (t) => t.company = "東京メトロ",
  ]) {
    const context = setup();
    mutate(context.__train);
    assert.deepEqual(infer(context), context.__train.route_sections[0]);
  }
});

test("untouched automatic surface stop is not evidence, but editing it makes it evidence", () => {
  const context = setup();
  const stop = { name: "有楽町", n02_station_code: "003795", stop_type: "pass_through",
    route_editing: { generated_by: "railway-route:true:6:003795:有楽町" } };
  context.__train.stops.splice(1, 0, stop);
  assert.equal(infer(context).line_ids[0], tunnel);
  stop.departure = "10:03";
  assert.equal(infer(context).section_codes, undefined);
});
