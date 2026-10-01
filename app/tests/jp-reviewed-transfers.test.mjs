import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

import {
  evaluateAppScripts,
  makeSandbox,
} from "../scripts/lib/app-family-sandbox.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(HERE, "..", "data");
const EVENTS_PATH = path.join(
  HERE,
  "..",
  "scripts",
  "railway",
  "jp-rail-history-events.json",
);

const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const properties = (feature) => feature?.properties || {};

let fixture = null;
function loadFixture() {
  if (fixture) return fixture;

  const context = makeSandbox();
  evaluateAppScripts(context);
  const run = (expression) => vm.runInContext(expression, context);
  const overlay = readJson(path.join(DATA_DIR, "rail-history.json"));
  const sections = readJson(path.join(DATA_DIR, "rail-sections.json"));
  const stations = readJson(path.join(DATA_DIR, "stations.json"));
  const originalSections = sections.features.slice();
  const originalStations = stations.features.slice();

  run("loadRailHistoryOverlay")(overlay, "jp");
  const report = run("applyRailHistory")(overlay, sections, stations);

  fixture = {
    overlay,
    sections,
    stations,
    originalSections,
    originalStations,
    events: readJson(EVENTS_PATH).temporal_events,
    report,
    railHistoryMatches: run("railHistoryMatches"),
    filterByDate: run("filterStationCandidatesByRideDate"),
  };
  return fixture;
}

function one(features, predicate, label) {
  const found = features.filter(predicate);
  assert.equal(found.length, 1, `${label}: expected exactly one feature`);
  return found[0];
}

test("IR Kanazawa keeps its 2015 membership while the shared JR membership lasts to 2024", () => {
  const { stations, filterByDate } = loadFixture();
  const currentIR = one(
    stations.features,
    (feature) => properties(feature).n02_station_code === "002093",
    "current IR Kanazawa 002093",
  );
  const oldJR = one(
    stations.features,
    (feature) => properties(feature).n02_station_code === "002092",
    "historical JR Kanazawa 002092",
  );

  assert.equal(properties(currentIR).station_name, "金沢");
  assert.equal(properties(currentIR).line_name, "IRいしかわ鉄道線");
  assert.equal(properties(currentIR).operator, "IRいしかわ鉄道");
  assert.equal(properties(currentIR).valid_from, "2015-03-14");

  assert.equal(properties(oldJR).station_name, "金沢");
  assert.equal(properties(oldJR).line_name, "北陸線");
  assert.equal(properties(oldJR).operator, "西日本旅客鉄道");
  assert.equal(properties(oldJR).valid_to, "2024-03-16");

  assert.equal(filterByDate([currentIR], "2015-03-13").length, 0);
  assert.equal(filterByDate([currentIR], "2015-03-14").length, 1);
  assert.equal(filterByDate([oldJR], "2024-03-15").length, 1);
  assert.equal(filterByDate([oldJR], "2024-03-16").length, 0);
});

test("the 2015 and 2024 IR selectors are disjoint and share one exact predecessor snapshot", () => {
  const {
    overlay,
    originalSections,
    originalStations,
    events,
    railHistoryMatches,
  } = loadFixture();
  const retirement = (id) =>
    one(overlay.retirements, (entry) => entry.history_id === id, id);
  const matched = (features, id) => {
    const entry = retirement(id);
    return features.filter((feature) => railHistoryMatches(feature, entry.match));
  };
  const disjoint = (left, right, label) => {
    const rightSet = new Set(right);
    assert.equal(
      left.some((feature) => rightSet.has(feature)),
      false,
      `${label}: selector matches overlap`,
    );
  };

  const sections2015 = matched(
    originalSections,
    "jp-id-ir-kurikara-kanazawa-transfer-2015.current.sections",
  );
  const sections2024 = matched(
    originalSections,
    "jp-id-ir-kanazawa-daishoji-transfer-2024.current.sections",
  );
  const stations2015 = matched(
    originalStations,
    "jp-id-ir-kurikara-kanazawa-transfer-2015.current.stations",
  );
  const stations2024 = matched(
    originalStations,
    "jp-id-ir-kanazawa-daishoji-transfer-2024.current.stations",
  );

  assert.ok(sections2015.length > 0, "2015 current sections matched");
  assert.ok(sections2024.length > 0, "2024 current sections matched");
  assert.ok(stations2015.length > 0, "2015 current stations matched");
  assert.ok(stations2024.length > 0, "2024 current stations matched");
  disjoint(sections2015, sections2024, "IR current sections");
  disjoint(stations2015, stations2024, "IR current stations");
  assert.equal(
    stations2015.some(
      (feature) => properties(feature).n02_station_code === "002093",
    ),
    true,
    "2015 selector owns current IR Kanazawa",
  );
  assert.equal(
    stations2024.some(
      (feature) => properties(feature).n02_station_code === "002093",
    ),
    false,
    "2024 selector must not redates current IR Kanazawa",
  );

  const predecessor = one(
    overlay.stations,
    (feature) =>
      properties(feature).station_name === "金沢" &&
      properties(feature).line_name === "北陸線" &&
      properties(feature).operator === "西日本旅客鉄道" &&
      properties(feature).n02_station_code === "002092",
    "shared JR Kanazawa predecessor",
  );
  assert.match(
    properties(predecessor).history_id,
    /^jp-id-ir-kanazawa-daishoji-transfer-2024\./,
  );

  const event2015 = one(
    events,
    (event) => event.id === "jp-id-ir-kurikara-kanazawa-transfer-2015",
    "2015 IR source event",
  );
  const sharedEvidence = one(
    event2015.shared_predecessor_stations,
    (entry) => entry.station === "金沢",
    "shared predecessor evidence",
  );
  assert.equal(sharedEvidence.source_event_id, "jp-id-ir-kanazawa-daishoji-transfer-2024");
  assert.equal(sharedEvidence.geometry_basis, "exact_n02_14_n02_23_station_geometry");
  assert.deepEqual(
    predecessor.geometry.coordinates,
    sharedEvidence.geometry_evidence.coordinates,
    "compiled predecessor must retain the reviewed exact snapshot geometry",
  );
});

test("later successor-line stations begin on their opening day and never leak into 2015 variants", () => {
  const { overlay, stations, filterByDate } = loadFixture();
  const openings = [
    { name: "テクノさかき", code: "002223", before: "1999-03-31", opening: "1999-04-01" },
    { name: "屋代高校前", code: "002132", before: "2001-03-21", opening: "2001-03-22" },
    { name: "信濃国分寺", code: "002303", before: "2002-03-28", opening: "2002-03-29" },
    { name: "千曲", code: "002173", before: "2009-03-13", opening: "2009-03-14" },
    { name: "青山", code: "000782", before: "2006-03-17", opening: "2006-03-18" },
    {
      name: "高岡やぶなみ",
      code: "001876",
      before: "2018-03-16",
      opening: "2018-03-17",
    },
    {
      name: "えちご押上ひすい海岸",
      code: "001663",
      before: "2021-03-12",
      opening: "2021-03-13",
    },
    {
      name: "新富山口",
      code: "001898",
      before: "2022-03-11",
      opening: "2022-03-12",
    },
  ];
  const transfer2015 = overlay.stations.filter((feature) =>
    /^jp-id-(?:ainokaze|echigo-hisui)-transfer-2015\./.test(
      properties(feature).history_id || "",
    ),
  );

  for (const opening of openings) {
    const station = one(
      stations.features,
      (feature) => properties(feature).n02_station_code === opening.code,
      `${opening.name} ${opening.code}`,
    );
    assert.equal(properties(station).station_name, opening.name);
    assert.equal(properties(station).valid_from, opening.opening);
    assert.equal(filterByDate([station], opening.before).length, 0, opening.name);
    assert.equal(filterByDate([station], opening.opening).length, 1, opening.name);
    assert.equal(
      transfer2015.some(
        (feature) => properties(feature).station_name === opening.name,
      ),
      false,
      `${opening.name} leaked into a 2015 historical variant`,
    );
  }
});

test("Myoko preserves both Wakinoda locations before the transfer and renames only on its day", () => {
  const { overlay, stations, filterByDate } = loadFixture();
  const eventId = "jp-id-echigo-myoko-transfer-2015";
  const predecessor = overlay.stations.filter((feature) =>
    properties(feature).history_id?.startsWith(eventId + ".") &&
      properties(feature).station_name === "脇野田",
  );
  assert.equal(predecessor.length, 2, "both surveyed Wakinoda locations are retained");
  const old = one(filterByDate(predecessor, "2014-10-18"), () => true, "old location");
  const relocated = one(filterByDate(predecessor, "2014-10-19"), () => true, "relocated location");
  assert.deepEqual(old.geometry.coordinates, [[138.24983, 37.08108], [138.24926, 37.0824]]);
  assert.deepEqual(relocated.geometry.coordinates, [[138.24858, 37.08084], [138.24756, 37.08185]]);
  assert.equal(properties(old).valid_to, "2014-10-19");
  assert.equal(properties(relocated).valid_from, "2014-10-19");
  assert.equal(filterByDate(predecessor, "2015-03-13").length, 1);
  assert.equal(filterByDate(predecessor, "2015-03-14").length, 0);
  assert.equal(predecessor.every((feature) => properties(feature).operator === "東日本旅客鉄道"), true);

  const successor = one(stations.features, (feature) =>
    properties(feature).n02_station_code === "001645", "current conventional-line Joetsu Myoko");
  assert.equal(properties(successor).station_name, "上越妙高");
  assert.equal(filterByDate([successor], "2015-03-13").length, 0);
  assert.equal(filterByDate([successor], "2015-03-14").length, 1);

  const shared = overlay.stations.filter((feature) =>
    properties(feature).station_name === "妙高高原" &&
      properties(feature).line_name === "信越線" &&
      properties(feature).operator === "東日本旅客鉄道",
  );
  assert.equal(shared.length, 1, "the shared JR boundary station is emitted once");
  assert.match(properties(shared[0]).history_id, /^jp-id-north-shinano-transfer-2015\./);
  const oldSections = overlay.sections.filter((feature) =>
    properties(feature).history_id?.startsWith(eventId + "."));
  assert.equal(overlay.stations.some((feature) =>
    properties(feature).history_id?.startsWith(eventId + ".") &&
      properties(feature).station_name === "直江津"), false,
    "the continuing JR boundary station must not be duplicated");
  const continuingJR = one(stations.features, (feature) =>
    properties(feature).n02_station_code === "001600", "continuing JR Naoetsu");
  assert.equal(filterByDate([continuingJR], "2015-03-13").length, 1);
  assert.equal(filterByDate([continuingJR], "2015-03-14").length, 1);
  assert.equal(oldSections.length, 38);
  for (const date of ["2014-10-18", "2014-10-19", "2015-03-13"]) {
    assert.equal(oldSections.filter((feature) => {
      const p = properties(feature);
      return (!p.valid_from || p.valid_from <= date) && (!p.valid_to || date < p.valid_to);
    }).length, 19, "one geometry period at " + date);
  }
});
