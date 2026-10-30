#!/usr/bin/env node
// Bounded cartographic display repair; physical routing and mileage are unchanged.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {partRowsForLine} from './build-display-lanes.mjs';
import {assertAllowedCandidateDirectory, assertAllowedCandidateFile} from './local-evidence-path.mjs';
import {refreshDependencyReferences, applyPreparedWrites, DEPENDENCY_PATHS} from './repair-three-reversal-extents.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const APP = path.join(REPO, 'app'), EV = path.join(REPO, 'railway-evidence/local');
export const AUTHORITY_PATH = path.join(EV, 'proposals/daishi-kojimashinden-20261020/bounded-upper-track-candidate.json');
const LINE = 'jp-京浜急行電鉄-大師線', STATION = '004418', KEY = 'daishi-kojimashinden-display';
const net = createRequire(import.meta.url)('../../public/rail-network.js');
const read = p => JSON.parse(fs.readFileSync(p));
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => createHash('sha256').update(value).digest('hex');
const PIXELS = [[20,520.5],[100,551.5],[500,718],[580,747],[660,772],[740,795.5],[820,818.5],[980,850],[1047,864.5]];
const TARGET = [139.7471446220207,35.53493575339516];
const VIEW_PATH = path.join(EV, 'diagnostics/sessions/keikyu-daishi-seven-station-caps-bundle-20261020/alignment/captures/000005/000004/view.json');

function proposedLine(e) {
  assert.equal(e.lineID, LINE); assert.equal(e.stationID, STATION);
  assert.deepEqual(e.displayStationCoordinate, TARGET, 'Kojimashinden upper-track target changed; roof/intertrack target forbidden');
  assert.equal(e.retainedPhysicalPrefixCount, 7);
  const source = net.decodeIntervals(e.baselineLine);
  assert.equal(source.length, 6); assert.equal(source[5].length, 11);
  assert.deepEqual(source[5], e.baselineSourceInterval5, 'Kojimashinden physical baseline changed');
  assert.equal(e.baselineLine.stations.at(-1)[0], STATION);
  assert.equal(e.baselineLine.displayIntervalCoordinates, undefined);
  assert.equal(e.baselineLine.displayStationCoordinates, undefined);
  assert.deepEqual(e.supportAuthority.map(s => s.pixel), PIXELS, 'Kojimashinden own-track pixel authority changed');
  const v = read(VIEW_PATH), q = v.snapshotProjection, c = v.camera, world = 2 ** 28;
  assert.deepEqual([v.lineID,v.intervalIndex,v.fromStationID,v.toStationID,v.pointOrdinal], [LINE,5,'004407',STATION,4]);
  assert(q && q.displayScale === 1 && c.heading === 0 && c.pitch === 0, 'Kojimashinden actual projection missing');
  const cx = (c.longitude + 180) / 360 * world;
  const cy = (1 - Math.asinh(Math.tan(c.latitude * Math.PI / 180)) / Math.PI) / 2 * world;
  for (const s of e.supportAuthority) {
    assert.equal(s.viewPath, VIEW_PATH, 'Kojimashinden foreign support view');
    const x = cx + (s.pixel[0] - q.centerXPoints) * q.mapPointsPerPointX;
    const y = cy + (s.pixel[1] - q.centerYPoints) * q.mapPointsPerPointY;
    const coordinate = [x / world * 360 - 180, Math.atan(Math.sinh(Math.PI * (1 - 2*y/world))) * 180 / Math.PI];
    assert(s.coordinate.length === 2 && s.coordinate.every((n,i) => Number.isFinite(n) && Math.abs(n-coordinate[i]) < 1e-10), 'Kojimashinden support projection changed');
  }
  assert.deepEqual(e.supportAuthority.at(-1).coordinate, TARGET);
  const line = structuredClone(e.baselineLine);
  line.displayStationCoordinates = {[STATION]: [...TARGET]};
  line.displayIntervalCoordinates = {5: [...source[5].slice(0,7), ...e.supportAuthority.map(s => [...s.coordinate])]};
  assert(line.displayIntervalCoordinates[5].every((p,i,a) => i === 0 || p[0] > a[i-1][0]), 'Kojimashinden tail backtracks');
  assert.deepEqual(line, e.candidateLine, 'Kojimashinden candidate exceeds bounded authority');
  return line;
}

export function repairPackage(input, e = read(AUTHORITY_PATH)) {
  const line = proposedLine(e), rows = input.lines.filter(l => l.id === LINE);
  assert.equal(rows.length, 1, 'Kojimashinden own line missing/duplicated');
  assert(equal(rows[0], e.baselineLine) || equal(rows[0], line), 'Kojimashinden current own source changed');
  const result = structuredClone(input);
  result.lines = result.lines.map(l => l.id === LINE ? line : l);
  const provenance = {lineID: LINE, stationIDs: [STATION], intervalIndices: [5],
    evidence: path.relative(REPO, AUTHORITY_PATH), physicalTopologyChanged: false,
    status: 'bounded-upper-own-track-candidate; full-passenger-caps-imagery-registration-and-Main-open',
    wholeLineAccepted: false, MainCertified: false};
  result.geometrySource ??= {};
  result.geometrySource.manualOverrides ??= {};
  const previous = result.geometrySource.manualOverrides[KEY];
  assert(previous === undefined || equal(previous, provenance), 'Kojimashinden provenance changed');
  result.geometrySource.manualOverrides[KEY] = provenance;
  return result;
}

export function repairParts(pkg, input, e = read(AUTHORITY_PATH)) {
  const line = pkg.lines.find(l => l.id === LINE);
  assert.deepEqual(line, proposedLine(e));
  const baseline = [[LINE,0,0,5,48,4378.1,null,null,[]]];
  assert.deepEqual(partRowsForLine(e.baselineLine, net.displayPartsForLine(e.baselineLine), null, null), baseline, 'Kojimashinden native baseline drift');
  // With physical anchors retained, the alias/groomed path cannot be reconstructed
  // from physical intervals. Embed the actual JS display part as native fallback.
  const rows = partRowsForLine(line, net.displayPartsForLine(line), null, null);
  assert.equal(rows.length, 1);
  assert(Array.isArray(rows[0][7]), 'Kojimashinden native fallback missing');
  const own = input.partsByRegion?.jp?.filter(r => r[0] === LINE);
  assert(equal(own, baseline) || equal(own, rows), 'Kojimashinden stale/foreign own native row');
  // No own lanes/follows/family windows/maps exist in the inspected baseline.
  // Unknown newly introduced own references require review rather than guessing.
  for (const [key,value] of Object.entries(input)) if (key !== 'partsByRegion') {
    assert(!JSON.stringify(value)?.includes(LINE), 'Kojimashinden own native reference requires review: ' + key);
  }
  assert(!(input.excludedOperators || []).includes(line.operator), 'Kojimashinden operator excluded');
  const result = structuredClone(input);
  result.partsByRegion.jp = result.partsByRegion.jp.map(r => r[0] === LINE ? rows[0] : r);
  return result;
}

// The receipt records the root reviewer's decision, not automatic pixel acceptance.
// Hash only these four reviewed pairs and their metadata, never an evidence tree.
export function validateCandidateReview(receipt, line) {
  assert(receipt, 'Kojimashinden scoped candidate-review receipt required before --apply');
  assert.deepEqual([receipt.format,receipt.status,receipt.lineID,receipt.stationID,receipt.intervalIndices,
    receipt.wholeLineAccepted,receipt.MainCertified],
  ['jtm-daishi-kojimashinden-candidate-review-v1','bounded-candidate-reviewed',LINE,STATION,[5],false,false], 'Kojimashinden review scope changed');
  assert.equal(receipt.reviewedOwnLineSha256, sha(JSON.stringify(line)), 'Kojimashinden reviewed own line changed');
  assert.equal(receipt.captures?.length, 4, 'Kojimashinden four reviewed captures required');
  const snapshots = [], seen = new Set(), zooms = [];
  for (const capture of receipt.captures) {
    assertAllowedCandidateFile(capture.viewPath);
    const viewPath = fs.realpathSync(capture.viewPath);
    assert(viewPath.startsWith(path.join(EV,'diagnostics/sessions') + path.sep) && path.basename(viewPath) === 'view.json', 'Kojimashinden noncanonical reviewed view');
    const files = [['view.json','viewSha256'],['basemap.png','basemapSha256'],['smooth.png','smoothSha256']];
    for (const [file,key] of files) {
      const p = path.join(path.dirname(viewPath),file), before = fs.readFileSync(p);
      assert.equal(sha(before), capture[key], 'Kojimashinden reviewed capture bytes changed: ' + p);
      snapshots.push({path:p,before});
    }
    const v = JSON.parse(snapshots.at(-3).before), q = v.snapshotProjection;
    assert.deepEqual([v.lineID,v.intervalIndex,v.fromStationID,v.toStationID], [LINE,5,'004407',STATION], 'Kojimashinden reviewed view identity changed');
    const zoom = v.captureSettings.zoom;
    const identity = zoom + ':' + v.viewpointID;
    assert(!seen.has(identity), 'Kojimashinden duplicate reviewed capture'); seen.add(identity);
    assert(q && q.displayScale === 1 && v.camera.heading === 0 && v.camera.pitch === 0 &&
      Number.isFinite(q.mapPointsPerPointX) && q.mapPointsPerPointX > 0 &&
      Number.isFinite(q.mapPointsPerPointY) && q.mapPointsPerPointY > 0, 'Kojimashinden reviewed projection missing');
    assert(v.wholeLineRenderDependency, 'Kojimashinden reviewed render identity missing');
    zooms.push(zoom);
  }
  assert.deepEqual(zooms.sort((a,b) => a-b), [17,17,17,19], 'Kojimashinden reviewed zoom scope changed');
  return snapshots;
}

function canonicalFile(p) {
  assertAllowedCandidateFile(p);
  assert(fs.realpathSync(p).startsWith(EV + path.sep), 'Kojimashinden review receipt must use canonical evidence tree');
}

function main(args) {
  const candidate = args.length === 2 && args[0] === '--candidate-root' ? path.resolve(args[1]) : null;
  const apply = args[0] === '--apply';
  assert(candidate || apply, 'Use --candidate-root <canonical EV/candidates/dir> or --apply --candidate-review <receipt.json>');
  let receiptPath;
  if (apply) {
    assert(args.length === 3 && args[1] === '--candidate-review', 'Kojimashinden scoped candidate-review receipt required before --apply');
    receiptPath = path.resolve(args[2]); canonicalFile(receiptPath);
  } else {
    assertAllowedCandidateDirectory(candidate);
    assert(candidate.startsWith(path.join(EV,'candidates') + path.sep), 'Kojimashinden candidate must use canonical evidence tree');
    // Reject a lexical canonical path resolving through a symlink to scratch.
    let ancestor = candidate;
    while (!fs.existsSync(ancestor)) ancestor = path.dirname(ancestor);
    assert(fs.realpathSync(ancestor).startsWith(EV + path.sep), 'Kojimashinden candidate ancestor escaped canonical evidence tree');
  }
  const snapshot = p => ({path:p,before:fs.readFileSync(p)});
  const authority = snapshot(AUTHORITY_PATH), e = JSON.parse(authority.before);
  const paths = {package:'public/rail/jp-2025.json',lanes:'public/rail/display-lanes.json',...DEPENDENCY_PATHS};
  const inputs = Object.fromEntries(Object.entries(paths).map(([k,p]) => [k,snapshot(path.join(APP,p))]));
  const load = k => JSON.parse(inputs[k].before);
  const pkg = repairPackage(load('package'),e), lanes = repairParts(pkg,load('lanes'),e);
  const custody = [authority,snapshot(VIEW_PATH),snapshot(path.join(APP,'public/rail-network.js')),
    snapshot(path.join(APP,'scripts/railway/build-display-lanes.mjs')),
    snapshot(path.join(APP,'scripts/railway/repair-three-reversal-extents.mjs'))];
  if (apply) {
    const receipt = snapshot(receiptPath);
    custody.push(receipt,...validateCandidateReview(JSON.parse(receipt.before),pkg.lines.find(l => l.id === LINE)));
  }
  const deps = refreshDependencyReferences(pkg,Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(k => [k,load(k)])));
  const outputs = {package:JSON.stringify(pkg),lanes:JSON.stringify(lanes)+'\n',
    ...Object.fromEntries(Object.entries(deps).map(([k,v]) => [k,JSON.stringify(v,null,2)+'\n']))};
  let writes;
  if (candidate) {
    fs.mkdirSync(candidate,{recursive:true}); assertAllowedCandidateDirectory(candidate);
    writes = Object.entries(outputs).map(([k,after]) => {
      const p = path.join(candidate,path.basename(inputs[k].path));
      assert(!fs.existsSync(p) || !fs.lstatSync(p).isSymbolicLink(), 'Kojimashinden candidate output cannot be symlink');
      if (!fs.existsSync(p)) fs.writeFileSync(p,'',{flag:'wx'});
      return {...snapshot(p),after:Buffer.from(after)};
    });
  } else writes = Object.entries(outputs).map(([k,after]) => ({...inputs[k],after:Buffer.from(after)}));
  applyPreparedWrites(writes,[...Object.values(inputs),...custody,...(candidate ? writes : [])]);
  console.log(JSON.stringify({mode:candidate?'candidate':'applied',candidateRoot:candidate,lineID:LINE,
    nativeRows:lanes.partsByRegion.jp.filter(r => r[0] === LINE).map(r => r.slice(0,7)),
    fullPassengerCapsCertified:false,imageryRegistrationCertified:false,wholeLineAccepted:false,MainCertified:false}));
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
