import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import { createRequire } from "node:module";

const RailNetwork = createRequire(import.meta.url)("../public/rail-network.js");
const full = JSON.parse(fs.readFileSync(new URL("../public/rail/jp-2025.json", import.meta.url)));
const byId = new Map(full.lines.map((line) => [line.id, line]));
const codeFor = (line, from, to) => `${line.id}@${[from, to].sort().join(":")}`;
function window(line, from, to) {
  const first = line.stations.findIndex((station) => station[0] === from);
  const last = line.stations.findIndex((station) => station[0] === to);
  assert.ok(first >= 0 && last >= 0);
  const codes = [];
  for (let index = first; index !== last; index += first < last ? 1 : -1)
    codes.push(codeFor(line, line.stations[index][0], line.stations[index + (first < last ? 1 : -1)][0]));
  return codes;
}
function check(name, rows, from, to, codes, expectedType) {
  for (const reverse of [false, true]) test(`${name} ${reverse ? "reverse" : "forward"}`, () => {
    const lines = rows.map((id) => byId.get(id));
    const network = RailNetwork.buildNetworkFromCompactPackage({ ...full, lines });
    const properties = {
      from_n02_station_code: reverse ? to : from,
      to_n02_station_code: reverse ? from : to,
      // The raw solver may only name one half of a normalized railway family.
      required_line_names: [lines[0].name], required_operator_names: [lines[0].operator],
    };
    const chosenCodes = reverse ? codes.slice().reverse() : codes;
    const source = RailNetwork.sourceGeometryForIntervals(network, { ...properties, section_codes: chosenCodes });
    const parts = source.type === "LineString" ? [source.coordinates] : source.coordinates;
    const raw = { type: "Feature", properties, geometry: { type: "LineString", coordinates: parts.flat() } };
    const matched = RailNetwork.canonicalizeRouteFeature(network, raw);
    assert.ok(matched);
    assert.equal(matched.properties.display_route_match, "solved-path-physical-intervals");
    assert.deepEqual(matched.properties.section_codes, chosenCodes);
    assert.equal(matched.geometry.type, expectedType || source.type);
    const explicit = RailNetwork.canonicalizeRouteFeature(network,
      { ...raw, properties: { ...properties, section_codes: chosenCodes } });
    assert.deepEqual(matched.geometry, explicit.geometry);
  });
}

{
  const base = byId.get("jp-九州旅客鉄道-長崎線"), branch = byId.get("jp-九州旅客鉄道-長崎線-2");
  const junction = base.stations.findIndex((station) => station[0] === branch.stations[0][0]);
  const from = base.stations[junction - 1][0], to = base.stations.at(-1)[0];
  check("Nagasaki old route rejoins the trunk", [base.id, branch.id], from, to,
    [...window(base, from, branch.stations[0][0]), ...window(branch, branch.stations[0][0], branch.stations.at(-1)[0]),
      ...window(base, branch.stations.at(-1)[0], to)]);
}
{
  const base = byId.get("jp-東日本旅客鉄道-中央線"), branch = byId.get("jp-東日本旅客鉄道-中央線-2");
  const from = base.stations[1][0], to = base.stations[3][0];
  check("Chuo Tatsuno route preserves the chosen detour", [base.id, branch.id], from, to,
    [...window(base, from, branch.stations[0][0]), ...window(branch, branch.stations[0][0], branch.stations.at(-1)[0]),
      ...window(base, branch.stations.at(-1)[0], to)]);
}
{
  const base = byId.get("jp-東日本旅客鉄道-東北線"), branch = byId.get("jp-東日本旅客鉄道-東北線-5");
  const junction = base.stations.findIndex((station) => station[0] === branch.stations[0][0]);
  const from = branch.stations[1][0], to = base.stations[junction + 1][0];
  check("Saikyo Omiya retains the surveyed platform gap", [base.id, branch.id], from, to,
    [...window(branch, from, branch.stations[0][0]), ...window(base, branch.stations[0][0], to)], "MultiLineString");
}
{
  const west = byId.get("jp-名古屋市-2号線名城線"), east = byId.get("jp-名古屋市-4号線名城線");
  for (const junction of [0, -1]) {
    const westAnchor = junction === 0 ? 0 : west.stations.length - 1;
    const eastAnchor = junction === 0 ? 0 : east.stations.length - 1;
    const from = west.stations[westAnchor === 0 ? 1 : westAnchor - 1][0];
    const to = east.stations[eastAnchor === 0 ? 1 : eastAnchor - 1][0];
    check(`Meijo normalized family joins at ${west.stations[westAnchor][1]}`, [west.id, east.id], from, to,
      [...window(west, from, west.stations[westAnchor][0]), ...window(east, east.stations[eastAnchor][0], to)]);
  }
}
