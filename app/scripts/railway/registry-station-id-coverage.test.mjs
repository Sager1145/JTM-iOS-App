import assert from "node:assert/strict";
import test from "node:test";
import path from "node:path";
import {
  canonicalStationCode,
  classify,
  coverageByRegion,
  fileRegion,
  formatReport,
  listStoreFiles,
  normalizeCompany,
  repoRoot,
  resolveOperator,
  resolveStation,
} from "./registry-station-id-coverage.mjs";

const bundle = {
  region: "jp",
  stationCodes: { "003700": "st:jp:1", "MTR-ADM": "st:hk:7" },
  groupCodes: { GRP: ["st:jp:2", "st:jp:3"], ONE: ["st:jp:4"] },
  stationOperator: { "st:jp:2": "op:jp:1", "st:jp:3": "op:jp:2", "st:jp:4": "op:jp:1" },
  operators: {
    "op:jp:1": { names: ["JR East", "JR東日本"], label: "JR東日本", logo: null, identity: "jp.jr-east" },
    "op:jp:2": { names: ["JR東海", "JR東日本/JR東海"], label: "JR東海", logo: null, identity: null },
  },
};

test("canonical codes and taiwan company labels match the upgrade", () => {
  assert.equal(canonicalStationCode("EAL-LOW-MTR-ADM"), "MTR-ADM");
  assert.equal(canonicalStationCode("LR-505-LR-100"), "LR-100");
  assert.equal(canonicalStationCode("TRAM-HV-105"), "TRAM-105");
  assert.equal(canonicalStationCode("KLRT-NETWORK-C1"), "KLRT-C1");
  assert.equal(canonicalStationCode("003700"), "003700");
  assert.equal(normalizeCompany("  桃園大眾捷運股份有限公司  ", "tw"), "桃園捷運");
  assert.equal(normalizeCompany("JR東日本", "jp"), "JR東日本");
  assert.equal(fileRegion("train-store.json"), "jp");
  assert.equal(fileRegion("train-store-TW.json"), "tw");
  assert.equal(fileRegion("train-store-backup.json"), null);
});

test("station and operator resolution is fail-closed", () => {
  assert.deepEqual(resolveStation("003700", null, bundle), { kind: "unique", id: "st:jp:1" });
  assert.deepEqual(resolveStation("EAL-LOW-MTR-ADM", null, bundle), { kind: "unique", id: "st:hk:7" });
  assert.deepEqual(resolveStation("ONE", null, bundle), { kind: "unique", id: "st:jp:4" });
  assert.deepEqual(resolveStation("GRP", "op:jp:1", bundle), { kind: "unique", id: "st:jp:2" });
  assert.deepEqual(resolveStation("GRP", null, bundle), { kind: "ambiguous" });
  assert.deepEqual(resolveStation("GRP", "op:jp:9", bundle), { kind: "ambiguous" });
  assert.deepEqual(resolveStation("MISSING", "op:jp:1", bundle), { kind: "unresolvable" });
  assert.equal(resolveOperator(" JR東日本 ", bundle).kind, "unique");
  assert.equal(resolveOperator("JR東日本/JR東海", bundle).id, "op:jp:2");
  assert.equal(resolveOperator("JR東日本", bundle).id, "op:jp:1");
  assert.equal(resolveOperator("nobody", bundle).kind, "unknown");
  assert.equal(resolveOperator("   ", bundle).kind, "none");
  assert.equal(resolveOperator(null, bundle).kind, "none");
  const shared = {
    ...bundle,
    operators: {
      "op:jp:1": ["共用"],
      "op:jp:2": ["共用"],
    },
  };
  assert.equal(resolveOperator("共用", shared).kind, "multiple");
});

test("classify counts stops and keeps the most frequent unresolved tuples", () => {
  const trains = [
    {
      company: "JR東日本",
      stops: [
        { name: "東京", n02_station_code: "003700" },
        { name: "新宿", n02StationCode: "GRP" },
        { name: "無名" },
      ],
    },
    {
      company: " ",
      stops: [{ name: "欠", n02_station_code: "NOPE" }, { name: "欠", n02_station_code: "NOPE" }],
    },
    { company: "ghost", stops: [{ name: "謎", n02_station_code: "NOPE" }] },
    { company: "JR東日本/JR東海", stops: [] },
  ];
  const { stats, top } = classify(trains, bundle);
  assert.equal(stats.stops, 6);
  assert.equal(stats.withCode, 5);
  assert.equal(stats.unique, 2);
  assert.equal(stats.ambiguous, 0);
  assert.equal(stats.unresolvable, 3);
  assert.equal(stats.trainsWithCompany, 3);
  assert.equal(stats.operatorUnique, 2);
  assert.equal(stats.operatorMultiple, 0);
  assert.equal(stats.operatorUnknown, 1);
  assert.equal(top[0].count, 2);
  assert.equal(top[0].name, "欠");
  assert.equal(top[0].company, " ");
  assert.equal(top[1].code, "NOPE");

  const many = [];
  for (let index = 0; index < 21; index += 1) {
    many.push({ company: "ghost", stops: [{ name: `n${String(index).padStart(2, "0")}`, n02_station_code: "NOPE" }] });
  }
  many.push({ company: "ghost", stops: [{ name: "n00", n02_station_code: "NOPE" }] });
  const crowded = classify(many, bundle);
  assert.equal(crowded.top.length, 20);
  assert.equal(crowded.top[0].name, "n00");
  assert.equal(crowded.top[0].count, 2);
  assert.equal(crowded.top.some((row) => row.name === "n20"), false);
});

test("a train region overrides the file region", () => {
  const rows = coverageByRegion(
    [{ file: "train-store.json", document: { trains: [{ region: "tw", company: "台鐵", stops: [] }] } }],
    new Map([["tw", { region: "tw", operators: { "op:tw:1": { names: ["台鐵"] } }, stationCodes: {}, groupCodes: {} }]]),
  );
  assert.equal(rows.length, 1);
  assert.equal(rows[0].region, "tw");
  assert.equal(rows[0].stats.operatorUnique, 1);
});

test("committed stores match the named globs and the report is a table", () => {
  const dataDir = path.join(repoRoot(), "app", "data");
  const files = listStoreFiles(dataDir);
  const names = files.map((file) => path.basename(file)).sort();
  assert.deepEqual(names.filter((name) => !name.startsWith("train-store")), []);
  assert.ok(names.includes("train-store.json"));
  assert.equal(files.filter((file) => file.includes(`${path.sep}sample-data`)).length, 0);
  const markdown = formatReport({
    rows: [{
      region: "mo",
      bundleMissing: false,
      stats: {
        stops: 1, withCode: 1, unique: 0, ambiguous: 1, unresolvable: 0,
        trainsWithCompany: 1, operatorUnique: 0, operatorMultiple: 1, operatorUnknown: 0,
      },
      top: [{ count: 3, name: "媽閣", code: "MLM-BARRA", company: "澳門輕軌" }],
    }],
    storeFiles: ["train-store.json"],
    sampleFiles: [],
    command: "node scripts/railway/registry-station-id-coverage.mjs",
  });
  assert.match(markdown, /\| mo \| 1 \| 1 \| 0 \| 1 \| 0 \| 1 \| 0 \| 1 \| 0 \|/);
  assert.match(markdown, /\| 3 \| 媽閣 \| MLM-BARRA \| 澳門輕軌 \|/);
  assert.match(markdown, /Sample-data stores: 0/);
});
