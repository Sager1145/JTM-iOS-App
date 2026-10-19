import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { makeSandbox, evaluateAppScripts } from "../scripts/lib/app-family-sandbox.mjs";
import * as scopedLanes from '../scripts/railway/repair-shinagawa-display-lanes.mjs';
const { repairShinagawaLanes } = scopedLanes;

const require = createRequire(import.meta.url);
const RailNetwork = require("../public/rail-network.js");
const RailStroke = require("../public/rail-stroke.js");
const packagePath = new URL("../public/rail/jp-2025.json", import.meta.url);
const full = JSON.parse(fs.readFileSync(packagePath, "utf8"));
const jr = "jp-東日本旅客鉄道-";
const tokaido = "jp-東海旅客鉄道-東海道新幹線";
const ids = new Set([jr+"東海道線", jr+"東北線-2", jr+"総武線", jr+"総武線-3", jr+"東北新幹線", tokaido]);
const pkg = { ...full, lines: full.lines.filter((line) => ids.has(line.id)) };
const network = RailNetwork.buildNetworkFromCompactPackage(pkg);

test("Osaki production owner handoffs retain final lane positions and the shared representative ruler", () => {
  const inputLanes = JSON.parse(fs.readFileSync(new URL('../public/rail/display-lanes.json', import.meta.url)));
  const lanes = scopedLanes.repairOsakiLanes(inputLanes, full, full);
  const native = RailNetwork.buildNetworkFromCompactPackage(full, null, lanes);
  const part = id => native.strokeModel.lines.find(line => line.lineId === id).parts[0];
  const build = (id, zoom, follows = part(id).follows) => {
    const source = part(id);
    return RailStroke.buildStroke(source.coordinates.map(point => RailStroke.project(point, zoom)), {
      measures: source.measures, rows: source.rows, totalMetres: source.totalMetres,
      laneGapPx: 2.7, minRampPx: 24, cornerRadiusPx: 3.6, minCornerRadiusPx: 3,
      anchors: source.anchors, enforceMinimumCornerRadius: true,
      follows: follows.map(follow => ({ ...follow,
        points: part(follow.canonLineId).coordinates.map(point => RailStroke.project(point, zoom)),
        measures: part(follow.canonLineId).measures,
      })),
    });
  };
  const at = (stroke, metres) => metres === 0 ? stroke.points[0]
    : RailStroke.sliceStroke(stroke.points, stroke.measures, metres - .001, metres).at(-1);
  const gap = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  const base = jr+'大崎支線', pair = base+'-p1', yamanote = jr+'山手線', sobu = jr+'総武線-3';
  const stem = part(base).follows.find(follow => follow.canonLineId === yamanote);
  const baseTail = part(base).follows.find(follow => follow.canonLineId === sobu);
  const pairTail = part(pair).follows.find(follow => follow.canonLineId === sobu);
  for (const zoom of [16, 18, 19]) {
    const main = build(yamanote, zoom), branch = build(base, zoom), south = build(sobu, zoom);
    assert.ok(gap(at(main, stem.canonTo), at(branch, stem.to)) < .05,
      `z${zoom}: lane application must not reopen the shared station merge`);
    assert.ok(gap(at(branch, baseTail.from), at(south, baseTail.canonFrom)) < .05,
      `z${zoom}: visible branch must meet its own southern fork`);
    const direction = build(pair, zoom);
    const ownDirection = build(pair, zoom, part(pair).follows.filter(follow => follow.canonLineId !== base));
    assert.ok(gap(at(direction, pairTail.from), at(ownDirection, pairTail.from)) < .01,
      `z${zoom}: the representative fork must not shift during canonical handoff`);
    assert.ok(gap(at(direction, pairTail.from), at(south, pairTail.canonFrom)) < .05,
      `z${zoom}: ride/fallback stroke must meet the actual same-point canonical tail`);
    for (let metres = 0; metres <= part(pair).totalMetres; metres += 10) {
      assert.ok(gap(at(direction, metres), at(branch, metres)) < .05,
        `z${zoom}, ${metres}m: the shared direction must retain the representative between junctions`);
    }
  }
});

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

let osakiCandidate;
function replayOsaki() {
  if (osakiCandidate) return osakiCandidate;
  const script = fileURLToPath(new URL('../scripts/railway/repair-tokyo-platform-approaches.py', import.meta.url));
  osakiCandidate = JSON.parse(execFileSync('python3', ['-c', `
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('approaches', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
package = module.repair(json.loads(module.PACKAGE.read_text()))
ids = {'jp-東日本旅客鉄道-大崎支線', 'jp-東日本旅客鉄道-大崎支線-p1', 'jp-東日本旅客鉄道-山手線', 'jp-東日本旅客鉄道-総武線-3', 'jp-東京臨海高速鉄道-臨海副都心線'}
while True:
    owners = {owner for line in package['lines'] if line['id'] in ids for owner in line.get('stationCircleOwnerByCode', {}).values()}
    if owners <= ids: break
    ids.update(owners)
package['lines'] = [line for line in package['lines'] if line['id'] in ids]
print(json.dumps(package, ensure_ascii=False))
`, script], { encoding: 'utf8', maxBuffer: 2 * 1024 * 1024 }));
  return osakiCandidate;
}

test("Osaki local representative retains physical forks but has one continuous station/north owner", () => {
  const candidate = replayOsaki();
  const centre = candidate.lines.find(row => row.id === jr+'大崎支線').displayStationCoordinates['004135'];
  for (const id of [jr + "大崎支線", jr + "大崎支線-p1"]) {
    const line = candidate.lines.find(row => row.id === id);
    assert.ok(line);
    const parts = RailNetwork.displayPartsForLine(line);
    assert.equal(parts.length, 1, 'No capped northern display lead survives');
    assert.deepEqual(parts[0][0], centre);
    assert.deepEqual(line.segments, full.lines.find(row => row.id === id).segments);
    assert.ok(line.southernBranchTopology.northJunction);
    assert.deepEqual(line.stations.map(row => row[0]), ["004135", "004235"]);
    assert.equal(line.stationCircleOwnerByCode['004135'], jr+'山手線');
    assert.ok(!('northJunction' in line.southernBranchTopology.displayAliases));
    const shared = line.southernBranchTopology.displaySharedTail;
    const owner = candidate.lines.find(row => row.id === shared.canonicalLineId);
    assert.ok(RailNetwork.displayPartsForLine(owner).some(part =>
      part.some(point => JSON.stringify(point) === JSON.stringify(shared.fromCoordinate))));
  }
  const rinkai = candidate.lines.find(row => row.id === 'jp-東京臨海高速鉄道-臨海副都心線');
  assert.deepEqual(RailNetwork.displayPartsForLine(rinkai)[0][0], full.lines.find(row => row.id === rinkai.id).displayStationCoordinates['004135']);
  assert.ok(!rinkai.stationCircleOwnerByCode?.['004135']);
  assert.deepEqual(RailNetwork.displayPartsForLine(candidate.lines.find(row => row.id === jr+'山手線'))[0]
    .find(point => point[0] === 139.728245 && point[1] === 35.619945), centre);
});

test("Osaki scoped lanes consume canonical southern tails and suppress duplicate JR ink", () => {
  const candidate = replayOsaki();
  const lanes = JSON.parse(fs.readFileSync(new URL('../public/rail/display-lanes.json', import.meta.url)));
  const result = scopedLanes.repairOsakiLanes(lanes, full, candidate);
  const base = jr+'大崎支線', pair = base+'-p1', sobu = jr+'総武線-3';
  const follows = result.followsByRegion.jp;
  for (const id of [base, pair]) {
    const tail = follows.find(row => row[0] === id && row[1] === 0 && row[4] === sobu);
    assert.ok(tail, 'Each tail follows the Sobu owner directly, without recursive canonical lookup');
    const lane = result.byRegion.jp.find(row => row[0] === id && row[1] === 0 && row[2] <= tail[2] && row[3] >= tail[3]);
    assert.equal(lane[4], -0.5, 'The entire shared tail inherits the owner offset');
    assert.ok(result.familyWindowsByRegion.jp.some(row => row[0] === id && row[1] === 0 && row[4] === 1 && row[2] <= tail[2] && row[3] >= tail[3]));
  }
  assert.ok(result.familyWindowsByRegion.jp.some(row => row[0] === pair && row[1] === 0 && row[2] === 0 && row[4] === 1));
  assert.ok(!follows.some(row => row[0] === base && row[1] === 1 && row[4] === pair), 'Retire the electric-copy reverse lead-in follow');
  assert.deepEqual(scopedLanes.repairOsakiLanes(result, null, candidate), result);
  const scoped = RailNetwork.buildNetworkFromCompactPackage(candidate, null, result);
  const pairPart = scoped.strokeModel.lines.find(row => row.lineId === pair).parts[0];
  const withheld = pairPart.tenantWindows.slice().sort((a,b) => a.from-b.from);
  assert.equal(withheld[0].from, 0);
  assert.equal(withheld[0].to, withheld[1].from);
  for (let i=1;i<withheld.length;i++) assert.equal(withheld[i-1].to, withheld[i].from);
  assert.ok(withheld.at(-1).to >= pairPart.totalMetres-0.1);
  assert.ok(pairPart.follows.some(row => row.canonLineId === sobu));
  const osakiDots = scoped.stations.features.filter(row => row.properties.stationGroupId === '004135');
  assert.equal(osakiDots.filter(row => row.properties.lineId === base || row.properties.lineId === pair).length, 0);
  assert.equal(osakiDots.filter(row => row.properties.lineId === jr+'山手線').length, 1);
  const owner = scoped.strokeModel.lines.find(row => row.lineId === jr+'山手線').parts[0];
  for (const id of [base,pair]) {
    const part = scoped.strokeModel.lines.find(row => row.lineId === id).parts[0];
    const stem = part.follows.find(row => row.canonLineId === jr+'山手線');
    assert.ok(stem && stem.from === 0 && stem.canonFrom > stem.canonTo,
      'Station-to-south branch stem follows continuous owner in reverse');
    assert.ok(part.tenantWindows.some(w => w.from === 0 && w.to === stem.to));
    assert.ok(owner.familyWindows.some(w => w.from === stem.canonTo && w.to === stem.canonFrom));
    const merge = candidate.lines.find(row => row.id === id).southernBranchTopology.displayStationStem.toCoordinate;
    assert.ok(part.coordinates.some(point => JSON.stringify(point) === JSON.stringify(merge)));
    assert.ok(owner.coordinates.some(point => JSON.stringify(point) === JSON.stringify(merge)), 'The two visible south approaches meet on the existing north/station owner');
  }
  assert.ok(osakiDots.some(row => row.properties.lineId === 'jp-東京臨海高速鉄道-臨海副都心線'));
  const affected = new Set([base, pair, jr+'山手線', 'jp-東京臨海高速鉄道-臨海副都心線']);
  assert.deepEqual(result.partsByRegion.jp.filter(row => !affected.has(row[0])), lanes.partsByRegion.jp.filter(row => !affected.has(row[0])));
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

test("Shinagawa Sobu southern display follows the identified normal passenger pair", () => {
  const line = pkg.lines.find(row => row.id === jr+'総武線-3');
  const path = RailNetwork.displayPartsForLine(line)[0];
  // Independently identified GSI large-scale rail-pair centres, checked against
  // passenger/main OSM ways 211472447 and 853189598 -> 210181293. Restoring the
  // old source chain must fail: it diagonally crosses these normal tracks.
  // Four metres is a data-reference tolerance for the representative corridor,
  // not a claim that these cartographic sources survey a track to four metres.
  const checkpoints = [[139.739307845, 35.6265], [139.738940539, 35.62501],
    [139.737137543, 35.61901], [139.736573327, 35.61828]];
  for (const checkpoint of checkpoints) {
    const scaleX = 111320 * Math.cos(checkpoint[1] * Math.PI / 180);
    const local = point => [(point[0]-checkpoint[0])*scaleX, (point[1]-checkpoint[1])*111320];
    let nearest = Infinity;
    for (let i=1; i<path.length; i++) {
      const a = local(path[i-1]), b = local(path[i]);
      const dx=b[0]-a[0], dy=b[1]-a[1], length2=dx*dx+dy*dy;
      const t=length2 ? Math.max(0, Math.min(1, -(a[0]*dx+a[1]*dy)/length2)) : 0;
      nearest=Math.min(nearest, Math.hypot(a[0]+t*dx, a[1]+t*dy));
    }
    assert.ok(nearest < 4,
      `Normal passenger-pair centre ${checkpoint} is ${nearest.toFixed(2)} m from display`);
  }
});

test("Shinagawa display circle uses both normal passenger rails while physical identity stays fixed", () => {
  const line = pkg.lines.find(row => row.id === jr+'総武線-3');
  // Common-latitude interpolation of identified normal main ways1313812926
  // and853189600, not siding853189601 or a single-rail station snap.
  const up = 139.7395602837456, down = 139.7397458171083;
  const centre = [(up + down) / 2, 35.629035];
  assert.deepEqual(line.stations[2].slice(2, 4), [139.739427, 35.629035]);
  const displayCentre = line.displayStationCoordinates['004095'];
  assert.ok(Math.abs(displayCentre[0] - centre[0]) < 1e-12);
  assert.equal(displayCentre[1], centre[1]);
  assert.deepEqual(line.displayIntervalCoordinates['1'].at(-1), displayCentre);
  assert.deepEqual(line.displayIntervalCoordinates['2'][0], displayCentre);
  assert.equal(line.stationCircleOwnerByCode['004095'], undefined);
});

test("Tokyo Tohoku Shinkansen display ends on its retained platform support without moving physical station", () => {
  const line = pkg.lines.find(row => row.id === jr+'東北新幹線');
  const source = RailNetwork.decodeIntervals(line)[21];
  const physicalAnchor = [139.767579, 35.68113];
  const support = [139.7676701, 35.681109];
  assert.deepEqual(line.stations.at(-1).slice(2, 4), physicalAnchor);
  assert.deepEqual(source.at(-1), physicalAnchor);
  assert.deepEqual(source.at(-2), support);
  assert.deepEqual(line.displayStationCoordinates?.['003766'], support);
  assert.deepEqual(line.displayIntervalCoordinates?.['21'], source.slice(0, -1));
  const display = RailNetwork.displayPartsForLine(line)[0];
  assert.deepEqual(display.at(-1), support);
  assert.deepEqual(display.slice(-4), source.slice(-5, -1),
    'Only the old terminal centroid warp regenerates into its retained source supports');
  assert.equal(display.some(point => JSON.stringify(point) === JSON.stringify(physicalAnchor)), false);
  assert.notDeepEqual(support, pkg.lines.find(row => row.id === tokaido).stations.at(-1).slice(2, 4));
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

test("Sobu retains independent platform circles and source supports outside bounded Shinagawa approaches", () => {
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
  const shinagawa = tunnel.stations.find(row => row[0] === '004095').slice(2, 4);
  assert.deepEqual(shinagawa, [139.739427, 35.629035]);
  assert.notDeepEqual(shinagawa, surface.stations[6].slice(2, 4));
  const shinagawaDisplay = [139.73965305042694, 35.629035];
  assert.deepEqual(tunnel.displayStationCoordinates['004095'], shinagawaDisplay);
  assert.equal(tunnel.stationCircleOwnerByCode['004095'], undefined);
  assert.equal(tunnel.stationLaneByCode['004095'], 0);
  const shinagawaCircles = network.stations.features.filter(feature => feature.properties.stationGroupId === '004095');
  assert.ok(shinagawaCircles.some(row => row.properties.lineId === tunnel.id &&
    JSON.stringify(row.geometry.coordinates) === JSON.stringify(shinagawaDisplay)));
  assert.ok(shinagawaCircles.some(row => row.properties.lineId === surface.id));
  assert.ok(network.groupMembers.get('004095').some(row => row.lineId === tunnel.id));
  const northBoundary = [139.7396393, 35.6297092];
  const northIndex = source.findIndex(point => JSON.stringify(point) === JSON.stringify(northBoundary));
  const northDisplay = tunnel.displayIntervalCoordinates['1'];
  assert.deepEqual(northDisplay.slice(0, northIndex), source.slice(1, northIndex + 1),
    'Exact normal-up boundary and every retained northern source support survive');
  assert.deepEqual(northDisplay.at(-1), shinagawaDisplay);
  const southSource = RailNetwork.decodeIntervals(tunnel)[2];
  const southDisplay = tunnel.displayIntervalCoordinates['2'];
  assert.deepEqual(southDisplay[0], shinagawaDisplay);
  const southBoundary = [139.73205, 35.61655];
  const southIndex = southSource.findIndex(point => JSON.stringify(point) === JSON.stringify(southBoundary));
  assert.ok(southIndex > 0);
  let previous = -1;
  for (const point of southSource.slice(southIndex)) {
    const next = southDisplay.findIndex((candidate, index) => index > previous &&
      JSON.stringify(candidate) === JSON.stringify(point));
    assert.ok(next > previous, 'Every source support from the exact southern rejoin survives; fork projections may subdivide edges');
    previous = next;
  }
  assert.deepEqual(tunnel.displayIntervalCoordinates['0'], RailNetwork.decodeIntervals(tunnel)[0].slice(0, -1));
  const beyond = RailNetwork.displayPartsForLine(tunnel)[0];
  for (const junction of [southBoundary])
    assert.ok(beyond.some(point => JSON.stringify(point) === JSON.stringify(junction)));
  const shinkansen = RailNetwork.displayPartsForLine(pkg.lines.find((line) => line.id === tokaido))[0];
  const nearest = shinkansen.reduce((best, point) => Math.abs(point[1]-station[1]) < Math.abs(best[1]-station[1]) ? point : best);
  assert.ok(station[0] < nearest[0], "Shimbashi conventional circle stays west of Shinkansen");
});

test("Shinagawa derived lanes retain downstream rulers and a bounded zero pin; replay is idempotent", () => {
  const lanes = JSON.parse(fs.readFileSync(new URL('../public/rail/display-lanes.json', import.meta.url)));
  const tunnel = pkg.lines.find(line => line.id === jr+'総武線-3');
  const ownParts = lanes.partsByRegion.jp.filter(row => row[0] === tunnel.id);
  assert.equal(ownParts.length, 1);
  const delta = ownParts[0][5] - 24429.9; // retained pre-repair derived ruler
  const follows = lanes.followsByRegion.jp;
  assert.equal(follows.some(row => row[0] === tunnel.id && row[4] === jr+'東海道線' &&
    row[2] < 7875 && row[3] > 6675), false);
  const downstream = follows.filter(row => row[0] === jr+'東海道線-3' && row[4] === tunnel.id);
  assert.equal(downstream.length, 2);
  for (const [row, before] of downstream.map((row, index) => [row, index === 0 ? [16735.962491237788, 18400] : [20150, 23375]])) {
    assert.ok(Math.abs(row[6]-before[0]-delta) < 0.2);
    assert.ok(Math.abs(row[7]-before[1]-delta) < 0.2);
  }
  const rows = lanes.byRegion.jp.filter(row => row[0] === tunnel.id);
  const pin = rows.find(row => row[4] === 0 && Math.abs(row[3]-row[2]-600) < 0.2 && row[2] > 5000);
  assert.ok(pin, 'Shinagawa keeps only its reviewed 300 m pin on each side');
  assert.ok(rows.some(row => row[4] === -0.5 && row[3] === pin[2]));
  assert.ok(rows.some(row => row[4] === -0.5 && row[2] === pin[3] && Math.abs(row[3]-17250-delta) < 0.2));
  const tohokuPart = lanes.partsByRegion.jp.find(row => row[0] === jr+'東北新幹線');
  const terminalLane = lanes.byRegion.jp.find(row => row[0] === jr+'東北新幹線' && row[2] === 673750);
  assert.equal(terminalLane[3], tohokuPart[5]);
  assert.equal(terminalLane[4], -0.5);
  assert.equal(lanes.hubReportByRegion.jp.find(hub => hub.hubId === 'jp-tokyo').members.some(member =>
    member.lineId === jr+'東北新幹線' && member.excluded === 'separate-alignment'), false,
    'The old diagnostic was sampled on an obsolete centroid warp inside the rebuilt approach');
  assert.deepEqual(repairShinagawaLanes(lanes, null, full), lanes,
    'Replaying an already-current ruler requires no old package and must not shift it again');
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


test("circle ownership preserves another operator and a displaced representative platform", () => {
  const owner = structuredClone(pkg.lines.find(line => line.id === jr+"東海道線"));
  for (const [operator, delta] of [["Other passenger operator", 0], [owner.operator, 0.000001]]) {
    const alias = structuredClone(owner);
    alias.id = "jp-representative-alias";
    alias.operator = operator;
    alias.stationCircleOwnerByCode = { "003766": owner.id };
    alias.displayStationCoordinates = { ...alias.displayStationCoordinates,
      "003766": [owner.stations[0][2] + delta, owner.stations[0][3]] };
    const scoped = RailNetwork.buildNetworkFromCompactPackage({ ...pkg, lines: [owner, alias] });
    assert.equal(scoped.stations.features.filter(f => f.properties.stationGroupId === "003766").length, 2);
    assert.equal(scoped.groupMembers.get("003766").length, 2);
  }
});
