import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { createRequire } from "node:module";
import { makeSandbox, evaluateAppScripts } from "../scripts/lib/app-family-sandbox.mjs";

const require = createRequire(import.meta.url);
const RailNetwork = require("../public/rail-network.js");
const packagePath = new URL("../public/rail/jp-2025.json", import.meta.url);
const full = JSON.parse(fs.readFileSync(packagePath, "utf8"));
const jr = "jp-東日本旅客鉄道-";
const tokaido = "jp-東海旅客鉄道-東海道新幹線";
const ids = new Set([jr+"東海道線", jr+"東北線-2", jr+"総武線", jr+"総武線-3", jr+"東北新幹線", tokaido]);
const pkg = { ...full, lines: full.lines.filter((line) => ids.has(line.id)) };
const network = RailNetwork.buildNetworkFromCompactPackage(pkg);

test("Oedo cached source chord is replaced by its surveyed displayed curve", () => {
  const line = full.lines.find(row => row.id === "jp-東京都-12号線大江戸線-2");
  const local = RailNetwork.buildNetworkFromCompactPackage({ ...full, lines: [line] });
  const part = JSON.parse(fs.readFileSync(new URL("./fixtures/tokyo-oedo-cached-route.json", import.meta.url)));
  const feature = part.route.features[0];
  const source = structuredClone(feature.geometry.coordinates);
  const display = RailNetwork.canonicalizeRouteFeature(local, feature);
  assert.equal(source.length, 15);
  assert.equal(display.geometry.coordinates.length, 29);
  assert.ok(display.geometry.coordinates.some(point => point[0] === 139.74885 && point[1] === 35.65384));
  assert.deepEqual(feature.geometry.coordinates, source);
});

test("Osaki directional branches join the legacy N02 display while retaining source forks", () => {
  for (const id of [jr + "大崎支線", jr + "大崎支線-p1"]) {
    const line = full.lines.find(row => row.id === id);
    assert.ok(line);
    const parts = RailNetwork.displayPartsForLine(line);
    assert.equal(parts.length, 2);
    const aliases = line.southernBranchTopology.displayAliases;
    assert.deepEqual(parts[1][0], aliases.northJunction);
    assert.deepEqual(parts[1].at(-1), line.displayStationCoordinates['004135']);
    assert.deepEqual(parts[0][0], parts[1].at(-1));
    assert.deepEqual(line.stations.map(row => row[0]), ["004135", "004235"]);
    for (const [key, owner] of [['northJunction', '山手線'], ['southJunction', '総武線-3']])
      assert.ok(RailNetwork.displayPartsForLine(full.lines.find(row => row.id === jr+owner))
        .some(part => part.some(point => JSON.stringify(point) === JSON.stringify(aliases[key]))));
  }
});

test("main Tokyo JR complex elects four circles and retains every platform alias", () => {
  const circles = network.stations.features.filter((f) => f.properties.stationGroupId === "003766");
  assert.equal(circles.length, 4);
  assert.deepEqual(new Set(circles.map((f) => f.properties.lineId)),
    new Set([jr+"東海道線", jr+"総武線", jr+"東北新幹線", tokaido]));
  assert.equal(network.groupMembers.get("003766").length, 6);
  for (const alias of [jr+"東北線-2", jr+"総武線-3"])
    assert.ok(network.stationById.has(`${alias}:003766`));
});

test("Shinagawa Shinkansen departure advances north instead of folding south", () => {
  const line = pkg.lines.find((l) => l.id === tokaido);
  const intervals = RailNetwork.decodeIntervals(line);
  const [anchor, departure] = intervals[15];
  assert.deepEqual(anchor, line.stations[15].slice(2, 4));
  assert.ok(departure[1] > anchor[1]);
  const parts = RailNetwork.displayPartsForLine(line);
  const path = parts[0];
  const index = path.findIndex((p) => p[0] === anchor[0] && p[1] === anchor[1]);
  assert.ok(index > 0);
  assert.ok(path[index - 1][1] < anchor[1]);
  assert.ok(path[index + 1][1] > anchor[1]);
});

function nex(reverse = false) {
  const stations = pkg.lines.find((l) => l.id === jr+"総武線-3").stations;
  const codes = ["003766:003872", "003872:004095"].map((pair) => `${jr}総武線-3@${pair}`);
  // Supply the SURFACE graph endpoints deliberately: the physical codes must
  // select the underground platforms even though the neighbouring line is near.
  const surface = pkg.lines.find((l) => l.id === jr+"東海道線").stations;
  const points = [surface[0].slice(2, 4), surface[6].slice(2, 4)];
  if (reverse) { codes.reverse(); points.reverse(); }
  return {
    stations, codes,
    feature: { type: "Feature", properties: {
      required_line_names: ["東海道線"],
      required_line_ids: [jr+"総武線-3"], section_codes: codes,
    }, geometry: { type: "LineString", coordinates: points } },
  };
}

for (const reverse of [false, true]) {
  test(`NEX physical interval codes select Sobu via Shimbashi (${reverse ? "northbound" : "southbound"})`, () => {
    const { stations, feature } = nex(reverse);
    const result = RailNetwork.canonicalizeRouteFeature(network, feature);
    assert.ok(result);
    assert.deepEqual(result.properties.display_line_ids, [jr+"総武線-3"]);
    const coordinates = result.geometry.coordinates;
    const tunnel = pkg.lines.find((line) => line.id === jr+"総武線-3");
    const point = (index) => tunnel.displayStationCoordinates?.[stations[index][0]] || stations[index].slice(2, 4);
    assert.deepEqual(coordinates[0], point(reverse ? 2 : 0));
    assert.deepEqual(coordinates.at(-1), point(reverse ? 0 : 2));
    assert.ok(coordinates.some((p) => p[0] === point(1)[0] && p[1] === point(1)[1]));
  });
}

test("unknown or disconnected interval codes cannot fall back to a nearby railway", () => {
  const { feature } = nex();
  feature.properties.section_codes = [jr+"総武線-3@missing"];
  assert.equal(RailNetwork.canonicalizeRouteFeature(network, feature), null);
  feature.properties.section_codes = [`${jr}総武線-3@003766:003872`, `${tokaido}@003766:004095`];
  // This pair connects Shimbashi->Tokyo->Shinagawa, which contradicts the
  // requested Tokyo->Shinagawa hop. Do not reverse a leg just to make it fit.
  assert.equal(RailNetwork.canonicalizeRouteFeature(network, feature), null);
});

test("Sobu retains the underground Shimbashi and joins the conventional display at Shinagawa", () => {
  const surface = pkg.lines.find((line) => line.id === jr+"東海道線");
  const tunnel = pkg.lines.find((line) => line.id === jr+"総武線-3");
  const station = surface.stations.find((row) => row[0] === "003872").slice(2, 4);
  const circle = network.stations.features.filter((feature) => feature.properties.stationGroupId === "003872");
  assert.equal(circle.length, 2);
  assert.ok(circle.some(row => JSON.stringify(row.geometry.coordinates) === JSON.stringify(tunnel.displayStationCoordinates['003872'])));
  assert.equal(tunnel.stations.some((row) => row[1] === "有楽町"), false);
  const source = RailNetwork.decodeIntervals(tunnel)[1];
  const sourceFeature = RailNetwork.sourceGeometryForIntervals(network, {
    from_n02_station_code: "003872", to_n02_station_code: "004095",
    section_codes: [jr+"総武線-3@003872:004095"],
  });
  assert.deepEqual(sourceFeature.coordinates, source);
  assert.notDeepEqual(source[0], station);
  const display = RailNetwork.displayPartsForLine(tunnel)[0];
  assert.ok(display.some((point) => JSON.stringify(point) === JSON.stringify(tunnel.displayStationCoordinates['003872'])));
  assert.deepEqual(tunnel.displayStationCoordinates['004095'], surface.stations[6].slice(2, 4));
  assert.deepEqual(tunnel.displayIntervalCoordinates['0'], RailNetwork.decodeIntervals(tunnel)[0].slice(0, -1));
  const beyond = RailNetwork.displayPartsForLine(tunnel)[0];
  for (const junction of [[139.73762,35.62049], [139.7328,35.61677]])
    assert.ok(beyond.some(point => JSON.stringify(point) === JSON.stringify(junction)));
  const shinkansen = RailNetwork.displayPartsForLine(pkg.lines.find((line) => line.id === tokaido))[0];
  const nearest = shinkansen.reduce((best, point) => Math.abs(point[1]-station[1]) < Math.abs(best[1]-station[1]) ? point : best);
  assert.ok(station[0] < nearest[0], "Shimbashi conventional circle stays west of Shinkansen");
});

test("solver endpoint identities validate the complete coded interval chain", () => {
  const { feature } = nex();
  feature.properties.from_n02_station_code = "003766";
  feature.properties.to_n02_station_code = "004095";
  assert.ok(RailNetwork.canonicalizeRouteFeature(network, feature));
  feature.properties.to_n02_station_code = "003872";
  assert.equal(RailNetwork.canonicalizeRouteFeature(network, feature), null);
  feature.properties.to_n02_station_code = "004095";
  feature.properties.from_n02_station_code = "003872";
  assert.equal(RailNetwork.canonicalizeRouteFeature(network, feature), null);
});

test("ordinary and limited express physical choices solve without the legacy N02 line names", () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  context.RailMap.sourceRouteGeometry = (properties) =>
    RailNetwork.sourceGeometryForIntervals(network, properties);
  for (const trainType of ["local", "limitedExpress"]) {
    for (const reverse of [false, true]) {
      const { codes, stations } = nex(reverse);
      context.__train = { id: "physical-choice", train_type: trainType, stops: [] };
      context.__section = {
        from: reverse ? "品川" : "東京", to: reverse ? "東京" : "品川",
        from_n02_station_code: reverse ? "004095" : "003766",
        to_n02_station_code: reverse ? "003766" : "004095",
        line_ids: [jr+"総武線-3"], line_names: ["総武線"], section_codes: codes,
      };
      const result = vm.runInContext(`(() => {
        const generated = [], warnings = [];
        solveTrainRouteSection(__train, __section, 0, ["2"], generated, warnings);
        return { generated, warnings };
      })()`, context);
      assert.equal(result.warnings.length, 0);
      assert.equal(result.generated.length, 1);
      const feature = result.generated[0];
      assert.equal(feature.properties.source, "compact_package_physical_intervals");
      assert.deepEqual(Array.from(feature.geometry.coordinates[0]), stations[reverse ? 2 : 0].slice(2,4));
      assert.deepEqual(Array.from(feature.geometry.coordinates.at(-1)), stations[reverse ? 0 : 2].slice(2,4));
      context.__section.section_codes = ["missing"];
      assert.equal(vm.runInContext(`(() => {
        const generated = [];
        solveTrainRouteSection(__train, __section, 0, ["2"], generated, []);
        return generated.length;
      })()`, context), 0);
    }
  }
});
