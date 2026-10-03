import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {precomputedRouteCoversSections, precomputeScopeCountries, currentPrecomputeSourceHashes, assertCurrentPrecomputeSourceHashes, assertPrecomputedTrainMatches} from "../scripts/build/precompute-train-parts.mjs";

test("changed solver inputs invalidate every country's precomputed attestation", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "jtm-source-hashes-"));
  try {
    for (const country of ["jp", "tw", "hk", "mo", "kr"]) {
      const suffix = country === "jp" ? "" : `-${country}`;
      const names = ["matched-routes.json", "matched-stops.json", ...precomputeScopeCountries(country).flatMap((region) => {
        const suffix = region === "jp" ? "" : `-${region}`;
        return [`${region}-2025.json`, `rail-sections${suffix}.json`, `stations${suffix}.json`];
      })];
      for (const name of names) fs.writeFileSync(path.join(directory, name), "{}");
      const options = {country, dataDir: directory, railDir: directory};
      const initial = currentPrecomputeSourceHashes(options);
      assert.doesNotThrow(() => assertCurrentPrecomputeSourceHashes(initial, initial));
      assert.throws(() => assertCurrentPrecomputeSourceHashes(null, initial), /full regeneration/);
      for (const name of names) {
        fs.writeFileSync(path.join(directory, name), '{"changed":true}');
        assert.throws(() => assertCurrentPrecomputeSourceHashes(initial, currentPrecomputeSourceHashes(options)), /full regeneration/);
        fs.writeFileSync(path.join(directory, name), "{}");
      }
      fs.writeFileSync(path.join(directory, `rail-history${suffix}.json`), "{}");
      assert.throws(() => assertCurrentPrecomputeSourceHashes(initial, currentPrecomputeSourceHashes(options)), /full regeneration/);
    }
  } finally { fs.rmSync(directory, {recursive: true, force: true}); }
});


test("finalize rejects edited or reordered source trains", () => {
  const train = {id: "sample", date: "2026-09-30", stops: [{name: "A"}, {name: "B"}]};
  assert.doesNotThrow(() => assertPrecomputedTrainMatches(structuredClone(train), train, "part-000"));
  for (const changed of [{...train, id: "other"}, {...train, date: "2026-10-01"},
                         {...train, stops: [{name: "A"}, {name: "C"}]}]) {
    assert.throws(() => assertPrecomputedTrainMatches(train, changed, "part-000"), /train changed/);
  }
});


test("offline samples reject skipped or reordered explicit journey sections", () => {
  const sections = [
    {from_n02_station_code: "US-A", to_n02_station_code: "US-B"},
    {from_n02_station_code: "US-B", to_n02_station_code: "CA-C"},
    {from_n02_station_code: "CA-C", to_n02_station_code: "CA-D"},
  ];
  const features = sections.map((properties) => ({properties}));
  assert.equal(precomputedRouteCoversSections(sections, features), true);
  assert.equal(precomputedRouteCoversSections(sections, features.slice(0, 2)), false);
  assert.equal(precomputedRouteCoversSections(sections, [features[0], features[2]]), false);
  assert.equal(precomputedRouteCoversSections(sections, features.slice().reverse()), false);
  assert.equal(precomputedRouteCoversSections([{}], features), false);
});
