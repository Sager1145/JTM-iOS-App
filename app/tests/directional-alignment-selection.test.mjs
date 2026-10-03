import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const RailNetwork = require("../public/rail-network.js");
const full = JSON.parse(fs.readFileSync(new URL("../public/rail/jp-2025.json", import.meta.url)));
const registry = JSON.parse(fs.readFileSync(new URL("../scripts/railway/jp-directional-alignment-overrides.json", import.meta.url)));
const codeFor = (lineId, from, to) => `${lineId}@${[from, to].sort().join(":")}`;

// Solver evidence can contain an illegal traversal; construct that evidence
// directly from survey intervals without using the direction-validating API.
function surveyedGeometry(network, properties) {
  let current = properties.from_n02_station_code;
  const parts = [];
  for (const code of properties.section_codes) {
    const interval = network.sectionByCode.get(code);
    const forward = current === interval.fromCode;
    const path = forward ? interval.coordinates : interval.coordinates.slice().reverse();
    const previous = parts.at(-1);
    if (previous && previous.at(-1)[0] === path[0][0] && previous.at(-1)[1] === path[0][1])
      previous.push(...path.slice(1));
    else parts.push(path.slice());
    current = forward ? interval.toCode : interval.fromCode;
  }
  return parts.length === 1 ? { type: "LineString", coordinates: parts[0] }
    : { type: "MultiLineString", coordinates: parts };
}

function featureFor(network, line, reverse = false, coded = false) {
  const stations = reverse ? line.stations.slice().reverse() : line.stations;
  const sectionCodes = stations.slice(0, -1).map((station, index) =>
    codeFor(line.id, station[0], stations[index + 1][0]));
  const properties = {
    from_n02_station_code: stations[0][0], to_n02_station_code: stations.at(-1)[0],
    required_line_names: [line.name], required_operator_names: [line.operator],
  };
  const geometry = surveyedGeometry(network, { ...properties, section_codes: sectionCodes });
  if (coded) properties.section_codes = sectionCodes;
  return { type: "Feature", properties, geometry };
}

for (const family of registry.families) {
  const pkg = { ...full, lines: full.lines.filter((line) =>
    line.id === family.baseLineID || line.alignmentOf === family.baseLineID) };
  const network = RailNetwork.buildNetworkFromCompactPackage(pkg);
  const base = pkg.lines.find((line) => line.id === family.baseLineID);
  for (const assignment of family.pairs) {
    const pair = pkg.lines.find((line) => line.id === assignment.lineID);
    const permittedForward = pair.stationOrderDirection === pair.alignmentDirection;
    test(`${pair.id}: surveyed pair uses its official station-order orientation`, () => {
      const valid = RailNetwork.canonicalizeRouteFeature(network, featureFor(network, pair, !permittedForward));
      assert.ok(valid);
      assert.deepEqual(valid.properties.display_line_ids, [pair.id]);
      const invalidRaw = RailNetwork.canonicalizeRouteFeature(network, featureFor(network, pair, permittedForward));
      assert.ok(invalidRaw, "an inferred forbidden run has a permitted family alternative");
      assert.equal(invalidRaw.properties.display_route_direction_corrected, true);
      assert.ok(!invalidRaw.properties.display_line_ids.includes(pair.id));
      assert.equal(RailNetwork.sourceGeometryForIntervals(network,
        featureFor(network, pair, permittedForward, true).properties), null);
      assert.equal(RailNetwork.canonicalizeRouteFeature(network,
        featureFor(network, pair, permittedForward, true)), null,
      "an explicit forbidden physical choice must not be replaced silently");
    });
    if (assignment.mainAlignmentDirection === "up" || assignment.mainAlignmentDirection === "down") {
      test(`${pair.id}: a main-line hop spanning the window selects the permitted track`, () => {
        const indexes = assignment.stationCodes.map((code) => base.stations.findIndex((station) => station[0] === code));
        const low = Math.min(...indexes), high = Math.max(...indexes);
        assert.ok(low >= 0);
        const fromIndex = Math.max(0, low - 1), toIndex = Math.min(base.stations.length - 1, high + 1);
        const forward = base.stationOrderDirection === pair.alignmentDirection;
        const from = base.stations[forward ? fromIndex : toIndex];
        const to = base.stations[forward ? toIndex : fromIndex];
        const raw = { type: "Feature", properties: {
          from_n02_station_code: from[0], to_n02_station_code: to[0],
          required_line_names: [base.name], required_operator_names: [base.operator],
        }, geometry: { type: "LineString", coordinates: [from.slice(2, 4), to.slice(2, 4)] } };
        const matched = RailNetwork.canonicalizeRouteFeature(network, raw);
        assert.ok(matched);
        assert.equal(matched.properties.display_route_direction_corrected, true);
        assert.ok(matched.properties.display_line_ids.includes(pair.id));
        const chosenSource = RailNetwork.sourceGeometryForIntervals(network, matched.properties);
        const chosenParts = chosenSource.type === "LineString" ? [chosenSource.coordinates] : chosenSource.coordinates;
        const displayParts = matched.geometry.type === "LineString" ? [matched.geometry.coordinates] : matched.geometry.coordinates;
        assert.deepEqual(displayParts[0][0], chosenParts[0][0]);
        assert.deepEqual(displayParts.at(-1).at(-1), chosenParts.at(-1).at(-1),
          "station identity selects the permitted track's own platform anchor");
        const order = base.stations.slice(fromIndex, toIndex + 1);
        if (!forward) order.reverse();
        const baseCodes = order.slice(0, -1).map((station, index) =>
          codeFor(base.id, station[0], order[index + 1][0]));
        const surveyedMain = {
          ...raw,
          geometry: surveyedGeometry(network, {
            ...raw.properties, section_codes: baseCodes,
          }),
        };
        const correctedMain = RailNetwork.canonicalizeRouteFeature(network, surveyedMain);
        assert.ok(correctedMain);
        assert.equal(correctedMain.properties.display_route_direction_corrected, true);
        assert.ok(correctedMain.properties.display_line_ids.includes(pair.id),
          "a legacy path on the forbidden main track uses its permitted paired track");
      });
    }
  }
}

test("Port Island one-way branch validates traversal before station-order labels", () => {
  const line = full.lines.find((line) => line.id === registry.lineOverrides[0].lineID);
  const network = RailNetwork.buildNetworkFromCompactPackage({ ...full, lines: [line] });
  assert.equal(line.permittedTraversal, "forward");
  assert.ok(RailNetwork.canonicalizeRouteFeature(network, featureFor(network, line, false, true)));
  assert.equal(RailNetwork.canonicalizeRouteFeature(network, featureFor(network, line, true, true)), null);
});

test("unassigned paired alignments remain permissive in both directions", () => {
  for (const assignment of registry.unassignedPairs) {
    const pair = full.lines.find((line) => line.id === assignment.lineID);
    const network = RailNetwork.buildNetworkFromCompactPackage({ ...full, lines: [pair] });
    for (const interval of network.sectionByCode.values())
      assert.deepEqual(RailNetwork.intervalDirections(network, interval), { forward: true, reverse: true });
  }
});
