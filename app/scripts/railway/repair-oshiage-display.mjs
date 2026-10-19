#!/usr/bin/env node
// Replay the reviewed Oshiage display alignment; physical intervals stay intact.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const RailNetwork = require('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const MAIN = 'jp-東武鉄道-伊勢崎線';
export const BRANCH = `${MAIN}-2`;
export const METRO = 'jp-東京地下鉄-11号線半蔵門線';
// Figures 4/103/104 locate the platform centre at the Kitajukken River
// crossing. This cut is the river-bank midpoint on the existing N02 rail
// segment, not a new survey or a snap to the neighbouring surface railway.
export const OSHIAGE = [139.81345102105016, 35.70970842655579];
const POLICY = 'oshiage-platform-display';
export const KEISEI = 'jp-京成電鉄-押上線';
export const ASAKUSA = 'jp-東京都-1号線浅草線';
export const B1_OSHIAGE = [139.8125322, 35.7104587];
const B1_NORTHEAST_END = [139.8135142, 35.7109793];
const B1_POLICY = 'oshiage-b1-passenger-display';

// The labelled Apple Asakusa black rail is exposed at the west-to-NE
// entry curve and across the river. These manually picked supports use
// the matching native AX map corners, not a POI or the B3 station point.
const B1_VISIBLE = [
  [139.8096042,35.7088578], [139.8097436,35.7088691],
  [139.8098830,35.7088861], [139.8099876,35.7089145],
  [139.8100921,35.7089542], [139.8101967,35.7090052],
  [139.8103187,35.7090761], [139.8104406,35.7091555],
  [139.8106022,35.7092724], [139.8108704,35.7094681],
  [139.8111143,35.7096467], [139.8113163,35.7098055],
  [139.8114940,35.7099615],
];

function repairB1(pkg) {
  const keisei = pkg.lines.find(line => line.id === KEISEI);
  const asakusa = pkg.lines.find(line => line.id === ASAKUSA);
  if (!keisei && !asakusa) return; // scoped B3-only callers
  if (!keisei || !asakusa) throw new Error('Missing Oshiage B1 through member');
  const paths = [asakusa, keisei].map(line => RailNetwork.decodeIntervals(line).at(-1));
  if (JSON.stringify(paths[0].at(-5)) !== JSON.stringify([139.80937,35.70887]) ||
      JSON.stringify(paths[1].at(-2)) !== JSON.stringify([139.81324,35.71072]))
    throw new Error('Oshiage B1 source supports changed; review again');
  const sx = 111320 * Math.cos(B1_OSHIAGE[1] * Math.PI / 180);
  const local = point => [(point[0] - B1_OSHIAGE[0]) * sx, (point[1] - B1_OSHIAGE[1]) * 111320];
  const world = point => [B1_OSHIAGE[0] + point[0] / sx, B1_OSHIAGE[1] + point[1] / 111320];
  const unit = (from, to) => {
    const a = local(from), b = local(to), d = b.map((v, i) => v - a[i]);
    return d.map(v => v / Math.hypot(...d));
  };
  // The NE pair exposes the complete platform-body end; the top of the
  // central screenshot is only a viewport cut, not a station end.
  const tangent = unit(B1_OSHIAGE, B1_NORTHEAST_END);
  // Only the hidden short entry-to-platform connection is reconstructed.
  // Its two measured-visible/source directions and the central B1 ray
  // constrain it; no generic 120 m through-station alignment is applied.
  const connect = (from, to, incoming, outgoing) => {
    const a = local(from), b = local(to), distance = Math.hypot(b[0] - a[0], b[1] - a[1]);
    const control = Math.min(20, distance / 3);
    const c = a.map((v, i) => v + incoming[i] * control);
    const d = b.map((v, i) => v - outgoing[i] * control);
    const steps = Math.ceil(distance / 5);
    return Array.from({ length: steps + 1 }, (_, i) => {
      if (i === 0) return from.slice();
      if (i === steps) return to.slice();
      const t = i / steps, s = 1 - t;
      return world(a.map((v, j) => s ** 3 * v + 3 * s ** 2 * t * c[j] +
        3 * s * t ** 2 * d[j] + t ** 3 * b[j]));
    });
  };
  const southRay = world(tangent.map(v => -20 * v)), northRay = world(tangent.map(v => 20 * v));
  const south = [...paths[0].slice(0, -4), ...B1_VISIBLE];
  south.push(...connect(south.at(-1), southRay, unit(south.at(-2), south.at(-1)), tangent).slice(1),
    world(tangent.map(v => -10 * v)), B1_OSHIAGE.slice());
  const north = paths[1].slice(0, -2);
  north.push(...connect(north.at(-1), B1_NORTHEAST_END, unit(north.at(-2), north.at(-1)), tangent.map(v => -v)).slice(1),
    northRay,
    world(tangent.map(v => 10 * v)), B1_OSHIAGE.slice());
  for (const [line, points] of [[asakusa, south], [keisei, north]]) {
    line.displayIntervalCoordinates = { ...line.displayIntervalCoordinates, [line.segments.length - 1]: points };
    line.displayStationCoordinates = { ...line.displayStationCoordinates, '003526': B1_OSHIAGE.slice() };
    line.stationLaneByCode = { ...line.stationLaneByCode, '003526': 0 };
    if ([ASAKUSA, KEISEI].includes(line.stationCircleOwnerByCode?.['003526']))
      delete line.stationCircleOwnerByCode['003526'];
  }
  pkg.geometrySource.manualOverrides[B1_POLICY] = {
    reviewedAt: '2026-10-11', crs: 'WGS84',
    script: 'app/scripts/railway/repair-oshiage-display.mjs',
    evidence: ['https://www.keisei.co.jp/keisei/tetudou/accessj/assets/pdf/sta_oshiage.pdf',
      'https://metroarchive.jp/ebook_hanzomon_oshiage/data/58/477/j4atY5.jpg'],
    positionEvidence: 'Native Apple Maps labelled Asakusa exposed entry/cross-river rail; matching AX corners, B1 platform-body centre and separate B3 group. Local b1-display-reference.json and existing evidence-index.md record pixels, cameras and uncertainty. Keisei schematic printed2021-03-31 identifies B1 islands but does not supply surveyed coordinates.',
    transformation: 'Display only: trace visible passenger entry bend and cross-river supports; use complete SW/NE B1 platform-body faces to select central point (the central screenshot is cropped); replace the old SE-edge station-interior support with the NE body centre, connect obscured throats locally and retain opposing20m platform rays; preserve physical intervals/mileage, supports outside the reviewed station window and both company marks. No freight, yard fan, per-platform tracks, global smoothing or B3 merge. Hidden centreline is representative, not an underground track survey.',
  };
}

// Figure 103 and the reviewed native north approach identify this one
// coarse N02 elbow as a continuous passenger arc, not a switch or reversal.
// Reconstruct only its display arc between the existing incoming/outgoing
// rays. The 3 m envelope is a display reconstruction bound, NOT a measured
// track radius. The separately reviewed Hikifune source notch is removed
// only after this arc has been built on its original source indices.
function reviewedNorthArc(points, index) {
  const apex = points[index], longitudeScale = 111320 * Math.cos(apex[1] * Math.PI / 180);
  const local = p => [(p[0] - apex[0]) * longitudeScale, (p[1] - apex[1]) * 111320];
  const before = local(points[index - 1]), after = local(points[index + 1]);
  const back = Math.hypot(...before), forward = Math.hypot(...after);
  const incoming = before.map(v => -v / back), outgoing = after.map(v => v / forward);
  const turn = Math.acos(incoming[0] * outgoing[0] + incoming[1] * outgoing[1]);
  if (!(turn > 30 * Math.PI / 180 && turn < 35 * Math.PI / 180))
    throw new Error('Oshiage north arc supports changed; review again');
  const radius = Math.min(3 / (1 / Math.cos(turn / 2) - 1),
    0.8 * Math.min(back, forward) / Math.tan(turn / 2));
  const trim = radius * Math.tan(turn / 2);
  const start = incoming.map(v => -v * trim), end = outgoing.map(v => v * trim);
  const sign = Math.sign(incoming[0] * outgoing[1] - incoming[1] * outgoing[0]);
  const centre = [start[0] - sign * incoming[1] * radius, start[1] + sign * incoming[0] * radius];
  const startAngle = Math.atan2(start[1] - centre[1], start[0] - centre[0]);
  // Include the arc midpoint, where the apex-to-arc envelope is measured.
  const count = 2 * Math.ceil(turn / (4 * Math.PI / 180));
  const arc = Array.from({ length: count + 1 }, (_, i) => {
    const angle = startAngle + sign * turn * i / count;
    const p = i === 0 ? start : i === count ? end :
      [centre[0] + radius * Math.cos(angle), centre[1] + radius * Math.sin(angle)];
    return [apex[0] + p[0] / longitudeScale, apex[1] + p[1] / 111320];
  });
  return [...points.slice(0, index), ...arc, ...points.slice(index + 1)];
}

export function repairPackage(pkg) {
  const branch = pkg.lines.find(line => line.id === BRANCH);
  const metro = pkg.lines.find(line => line.id === METRO);
  if (!branch || !metro) throw new Error('Missing Oshiage line');
  const branchPath = RailNetwork.decodeIntervals(branch)[0];
  const last = metro.segments.length - 1;
  const metroPath = RailNetwork.decodeIntervals(metro)[last];
  // Both passenger approaches meet inside their original straight source
  // segment. Keep upstream supports except the separately reviewed coarse
  // arc elbow and Hikifune source notch below; never send the north approach
  // south past the common point and then reverse it back north.
  const boundary = branchPath.findIndex(p => p[0] === 139.81336 && p[1] === 35.71012);
  if (boundary < 0 || metroPath.at(-1)[1] !== 35.70847)
    throw new Error('Oshiage survey changed; review the override again');
  const terminalSupport = points => {
    const last = points.at(-1);
    const distance = Math.hypot((last[0] - OSHIAGE[0]) * 111320 * Math.cos(OSHIAGE[1] * Math.PI / 180),
      (last[1] - OSHIAGE[1]) * 111320);
    const fraction = Math.min(20, distance / 2) / distance;
    // Subdivide the same surveyed straight segment. A second collinear
    // support keeps finite smoothing samples on the reviewed terminal ray.
    return [...points, last.map((value, i) => OSHIAGE[i] + (value - OSHIAGE[i]) * fraction), OSHIAGE.slice()];
  };
  const branchApproach = reviewedNorthArc(terminalSupport(branchPath.slice(0, boundary + 1)), boundary);
  // This crosswise B→C segment is original N02 geometry, not a new alias.
  // Explicit Oshiage passenger-route ways identify B inside the own pair
  // and C west of both. Remove C only from display; keep A/B/D and every
  // southern arc/terminal control. OSM's KSJ2 ancestry is not a survey.
  const hikifuneSourceControls = [
    [139.816637, 35.718314], [139.81658, 35.71726],
    [139.81651, 35.71726], [139.81643, 35.71575],
  ];
  if (JSON.stringify(branchPath.slice(0, 4)) !== JSON.stringify(hikifuneSourceControls) ||
      JSON.stringify(branchApproach.slice(0, 4)) !== JSON.stringify(hikifuneSourceControls))
    throw new Error('Hikifune own-branch source controls changed; review the display notch again');
  branchApproach.splice(2, 1);
  const metroApproach = terminalSupport([...metroPath.slice(0, -1), [139.81359, 35.70908]]);
  branch.displayIntervalCoordinates = {
    ...branch.displayIntervalCoordinates,
    0: branchApproach,
  };
  metro.displayIntervalCoordinates = {
    ...metro.displayIntervalCoordinates,
    [last]: metroApproach,
  };
  for (const line of [branch, metro])
    line.displayStationCoordinates = { ...line.displayStationCoordinates, '003526': OSHIAGE };
  metro.stationLaneByCode = { ...metro.stationLaneByCode, '003526': 0 };
  branch.stationCircleOwnerByCode = {
    ...branch.stationCircleOwnerByCode, '003479': MAIN,
  };
  if (branch.stationCircleOwnerByCode['003526'] === METRO)
    delete branch.stationCircleOwnerByCode['003526'];
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides[POLICY] = {
    reviewedAt: '2026-10-11', crs: 'WGS84',
    script: 'app/scripts/railway/repair-oshiage-display.mjs',
    source: 'N02-25 passenger segment [139.81359,35.70908]–[139.81336,35.71012]; representative centre cut at georeferenced river crossing from engineering figures 4/103/104',
    evidence: [
      'https://www.tobu.co.jp/railway/guide/station/info/1120.html',
      'https://www.tokyometro.jp/station/oshiage/yardmap/index_print.html',
      'https://metroarchive.jp/content/ebook_hanzomon_oshiage.html/',
      'https://metroarchive.jp/ebook_hanzomon_oshiage/data/58/477/j4atY5.jpg',
      'https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/16/58220/25800.pbf',
      'https://www.tobu.co.jp/cms-img/stations/insidemap/1104_image01.gif',
      'https://www.openstreetmap.org/way/61754727',
      'https://www.openstreetmap.org/way/155874950',
    ],
    transformation: 'Display only: common representative point at the source-bound river crossing; retain both company marks; trim the north approach and extend the south approach without reversal or synthetic Bezier; replace the reviewed 32-degree coarse north elbow with a tangent circular display arc deviating no more than 3m from the original two-ray centreline, with apex-to-arc distance at most 3m and at most 2-degree sampling steps; separately delete only the original N02 Hikifune crosswise control [139.81651,35.71726], retaining station A, own-band B, next guard D and every later display control; preserve all physical geometry/mileage, other passenger supports and the 20m terminal rays; no freight, yard or platform-fan lines added, no trunk follow/tenant suppression or screen lane',
    positionEvidence: 'Engineering history 2004-03-05, pp292/441/450; river-bank midpoint is a representative central landmark, not a precise modern physical-platform survey. See through-stations-20261011/oshiage/central-cut-reference.json; exact underground Apple black-track residual remains unmeasured.',
    hikifuneSourceNotch: {
      reviewedAt: '2026-10-18',
      report: 'docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/tobu-isesaki2-complete/own-branch-research-20261018.md',
      sourceControls: hikifuneSourceControls,
      removedDisplayIndex: 2,
      ownPassengerRouteIDs: [11065585, 11065584],
      ownWayIDs: [61754727, 155874950],
      attribution: '© OpenStreetMap contributors, ODbL 1.0',
      limits: 'Tobu schematic and explicit own Oshiage passenger memberships identify the inner pair; OSM KSJ2 ancestry is not an independent track survey. B is between the mapped own pair and C is west of both. No station/platform-centre move, neighboring surface-rail snap or whole-approach alignment claim. Parent native candidate confirmation is separate from this source review.',
    },
  };
  repairB1(pkg);
  return pkg;
}

// Called after both full lane derivation and --refresh-parts, so a rebuild
// cannot reinstate the measured-but-wrong branch/trunk handoff.
export function repairLanes(pkg, lanes) {
  if (!pkg.geometrySource?.manualOverrides?.[POLICY]) return lanes;
  if (pkg.geometrySource.manualOverrides[B1_POLICY]) {
    // Re-anchor the existing zero-lane terminal windows after the local
    // display length changes. Their slot stays zero; no company is shifted.
    for (const id of [KEISEI, ASAKUSA]) {
      const part = lanes.partsByRegion.jp.filter(row => row[0] === id).at(-1);
      if (!part) throw new Error(`Missing B1 display part: ${id}`);
      const rows = lanes.byRegion.jp.filter(row => row[0] === id && row[1] === part[1]);
      const pin = rows.at(-1);
      if (!pin || pin[4] !== 0) throw new Error(`B1 terminal lane policy changed: ${id}`);
      pin[2] = Math.max(0, part[5] - 300);
      pin[3] = part[5];
    }
  }
  const pair = new Set([MAIN, BRANCH]);
  lanes.byRegion.jp = lanes.byRegion.jp.filter(row => row[0] !== BRANCH);
  lanes.followsByRegion.jp = lanes.followsByRegion.jp.filter(row =>
    !(pair.has(row[0]) && pair.has(row[4])));
  lanes.familyWindowsByRegion.jp = lanes.familyWindowsByRegion.jp.filter(row =>
    !(pair.has(row[0]) && row[5] === '東武鉄道:伊勢崎線'));
  // Keep the shared platform on lane zero after a fresh corridor derivation.
  const terminal = lanes.partsByRegion.jp.filter(row => row[0] === METRO).at(-1);
  const end = terminal[5], start = Math.max(0, end - 300), part = terminal[1];
  const rows = [];
  let terminalIndex;
  for (const row of lanes.byRegion.jp) {
    if (row[0] !== METRO || row[1] !== part || row[3] <= start) {
      rows.push(row);
      continue;
    }
    if (row[2] < start) rows.push([...row.slice(0, 3), start, row[4]]);
    terminalIndex ??= rows.length;
  }
  rows.splice(terminalIndex ?? rows.length, 0, [METRO, part, start, end, 0]);
  lanes.byRegion.jp = rows;
  return lanes;
}

async function main() {
  const args = process.argv.slice(2);
  const outputIndex = args.indexOf('--output-dir');
  const outputDirectory = outputIndex >= 0 ? args[outputIndex + 1] : null;
  if (outputIndex >= 0 && (!outputDirectory || args.length !== 2 || outputIndex !== 0))
    throw new Error('Use --output-dir <directory> to stage both existing Oshiage outputs');
  if (outputIndex < 0 && args.some(arg => arg !== '--check'))
    throw new Error('Expected --check or --output-dir <directory>');
  const { partRowsForLine } = await import('./build-display-lanes.mjs');
  const packagePath = path.join(ROOT, 'public/rail/jp-2025.json');
  const lanesPath = path.join(ROOT, 'public/rail/display-lanes.json');
  const before = fs.readFileSync(packagePath, 'utf8');
  const beforeLanes = fs.readFileSync(lanesPath, 'utf8');
  const pkg = repairPackage(JSON.parse(before));
  const lanes = JSON.parse(beforeLanes);
  for (const id of [BRANCH, METRO, KEISEI, ASAKUSA]) {
    const line = pkg.lines.find(line => line.id === id);
    const parts = RailNetwork.displayPartsForLine(line);
    const rows = partRowsForLine(line, parts, null, null);
    const old = lanes.partsByRegion.jp;
    const first = old.findIndex(row => row[0] === id);
    if (first < 0) throw new Error(`Missing display part: ${id}`);
    old.splice(first, old.filter(row => row[0] === id).length, ...rows);
  }
  repairLanes(pkg, lanes);
  const after = JSON.stringify(pkg);
  const afterLanes = `${JSON.stringify(lanes)}\n`;
  if (args.includes('--check')) {
    if (before.trimEnd() !== after || beforeLanes !== afterLanes)
      throw new Error('Oshiage display override is not applied');
    console.log('Oshiage display override is current');
  } else if (outputDirectory) {
    const directory = path.resolve(outputDirectory);
    if (directory === path.dirname(packagePath))
      throw new Error('Candidate output directory must differ from the production rail directory');
    fs.mkdirSync(directory, { recursive: true });
    fs.writeFileSync(path.join(directory, 'jp-2025.json'), after);
    fs.writeFileSync(path.join(directory, 'display-lanes.json'), afterLanes);
    console.log(`Staged Oshiage candidate package and lane parts in ${directory}`);
  } else {
    if (before.trimEnd() !== after) fs.writeFileSync(packagePath, after);
    if (beforeLanes !== afterLanes) fs.writeFileSync(lanesPath, afterLanes);
    console.log('Applied Oshiage display alignment and branch junction');
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main().catch(error => { console.error(error); process.exitCode = 1; });
