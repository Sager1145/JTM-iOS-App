import assert from "node:assert/strict";
import fs from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";
import { createPrecomputeSourceGeometry } from "../scripts/build/precompute-train-parts.mjs";

const require = createRequire(import.meta.url);
const RailNetwork = require("../public/rail-network.js");
const packageData = RailNetwork.mergeCompactPackages([
  JSON.parse(fs.readFileSync(new URL("../public/rail/jp-2025.json", import.meta.url), "utf8")),
]);
const tunnel = "jp-東日本旅客鉄道-総武線-3";
const properties = {
  required_line_ids: [tunnel],
  section_codes: [`${tunnel}@003766:003872`, `${tunnel}@003872:004095`],
  from_n02_station_code: "003766",
  to_n02_station_code: "004095",
};

for (const initialIDs of [[], ["jp-東日本旅客鉄道-東海道線"]]) {
  test(`later inferred Tokyo intervals resolve from ${initialIDs.length ? "an unrelated authored subset" : "an empty authored store"}`, () => {
    let builds = 0;
    const sourceGeometry = createPrecomputeSourceGeometry({
      ...RailNetwork,
      buildNetworkFromCompactPackage(data) {
        builds++;
        return RailNetwork.buildNetworkFromCompactPackage(data);
      },
    }, () => packageData, initialIDs);
    const geometry = sourceGeometry(properties);
    assert.equal(geometry?.type, "LineString");
    assert.ok(geometry.coordinates.length > 2);
    assert.deepEqual(sourceGeometry(properties), geometry);
    assert.equal(builds, 1, "unchanged requests reuse the physical network");
    assert.equal(sourceGeometry({ ...properties, to_n02_station_code: "missing" }), null);
    assert.equal(sourceGeometry({ ...properties, required_line_ids: ["missing-line"] }), null);
    assert.equal(sourceGeometry({ ...properties, section_codes: ["missing-line@A:B"] }), null);
  });
}

test("a narrow Tokaido interval stays cached when the Sobu tunnel widens an empty authored store", () => {
  const initialIDs = [];
  const tokaido = "jp-東日本旅客鉄道-東海道線";
  const tokaidoRequest = {
    required_line_ids: [tokaido],
    section_codes: [`${tokaido}@003766:003795`],
    from_n02_station_code: "003766",
    to_n02_station_code: "003795",
  };
  let builds = 0;
  const sourceGeometry = createPrecomputeSourceGeometry({
    ...RailNetwork,
    buildNetworkFromCompactPackage(data) {
      builds++;
      return RailNetwork.buildNetworkFromCompactPackage(data);
    },
  }, () => packageData, initialIDs);
  const narrow = sourceGeometry(tokaidoRequest);
  assert.equal(narrow?.type, "LineString");
  assert.equal(narrow.coordinates.length, 11);
  assert.deepEqual(sourceGeometry(tokaidoRequest), narrow);
  assert.equal(builds, 1, "the first interval builds the included network once");
  const wide = sourceGeometry(properties);
  assert.equal(wide?.type, "LineString");
  assert.ok(wide.coordinates.length > 2);
  assert.equal(builds, 2, "the later tunnel request rebuilds with its owner lines");
  assert.deepEqual(sourceGeometry(tokaidoRequest), narrow);
  assert.deepEqual(sourceGeometry(properties), wide);
  assert.equal(builds, 2, "repeats reuse both cached geometries");
  assert.equal(sourceGeometry({ ...properties, to_n02_station_code: "missing" }), null);
  assert.equal(sourceGeometry({ ...properties, required_line_ids: ["missing-line"] }), null);
  assert.equal(sourceGeometry({ ...properties, section_codes: ["missing-line@A:B"] }), null);
});
