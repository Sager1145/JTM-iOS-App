// Local display corridor and image transverse anchor; physical railway stays intact.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { latitudeAt, hasReviewedKeiyoNativeParts, partsForRetainedKeiyoStage } from './repair-keiyo-minami-passenger-centre.mjs';
import { projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const read = file => JSON.parse(fs.readFileSync(new URL(file, import.meta.url)));
export const shioEvidence = read('./keiyo-shio-transverse-display-evidence.json');
const shared = read('./keiyo-shared-corridor-evidence.json').western;
export const SHIO_STAGE = 'keiyo-shio-transverse-display';
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const find = (pkg,id) => pkg.lines.find(line => line.id === id);
export const westernApproachEvidence = read('./keiyo-display-curves-evidence.json').windows[1].passengerApproach;
// The same exact upstream window must survive both the older tail replay and
// the later Shio station replay. Its own passenger route selects the track.
export function westernPassengerApproach(points, approach = westernApproachEvidence, cache) {
  const route = approach.routeMembership, chainIDs = approach.chain.map(row => row[0]);
  assert(route.id === 14656632 && route.tags.route === 'train' &&
    route.tags.operator === '東日本旅客鉄道' && route.tags.to === '東京', 'Western approach passenger route changed');
  assert.deepEqual(chainIDs, route.selectedOrderedMembers.map(row => row.ref), 'Western approach route membership changed');
  assert(!chainIDs.some(id => approach.excludedEastArmWayIDs.includes(id)), 'Western approach selected the eastern arm');
  let track = [];
  for (const [id, reverse] of approach.chain) {
    const way = approach.ways.find(row => row.id === id), tags = way?.tags;
    assert(tags?.railway === 'rail' && tags.usage === 'main' && tags.name === 'JR京葉線' &&
      tags.operator === '東日本旅客鉄道' && !tags.service, 'Western approach passenger track identity changed');
    if (cache) {
      assert.equal(cache.fetchedAt, approach.source.fetchedAt, 'Western approach source cache changed');
      const actual = cache.elements.find(row => row.id === id);
      assert.deepEqual({ id: actual?.id, tags: actual?.tags,
        coordinates: actual?.geometry.map(point => [point.lon, point.lat]) }, way, 'Western approach passenger source changed');
    }
    const source = reverse ? way.coordinates.toReversed() : way.coordinates;
    assert(!track.length || equal(track.at(-1), source[0]), 'Western approach source chain has a seam');
    track.push(...source.slice(track.length ? 1 : 0));
  }
  const start = projectPointOntoPolyline(approach.baselineWindow[0], track);
  const end = projectPointOntoPolyline(approach.baselineWindow.at(-1), track);
  assert.deepEqual({ start, end }, approach.projections, 'Western approach boundary projection changed');
  assert(start.distanceM < 10 && end.distanceM < 1 && start.insertIndex < end.insertIndex,
    'Western approach boundary left its own track window');
  const replacement = [start.point, ...track.slice(start.insertIndex + 1, end.insertIndex + 1), end.point];
  assert.deepEqual(replacement, approach.candidateWindow, 'Western approach source slice changed');
  const before = points.flatMap((point, index) => equal(point, approach.before) ? [index] : []);
  const after = points.flatMap((point, index) => equal(point, approach.after) ? [index] : []);
  assert(before.length === 1 && after.length === 1 && before[0] < after[0], 'Western approach outer guards changed');
  const existing = points.slice(before[0] + 1, after[0]);
  assert(equal(existing, approach.baselineWindow) || equal(existing, replacement), 'Unreviewed western approach window');
  return [...points.slice(0, before[0] + 1), ...replacement, ...points.slice(after[0])];
}
export const hasShioStage = pkg => Boolean(pkg.geometrySource?.manualOverrides?.[SHIO_STAGE]);
const longitudeAt = (points,lat) => latitudeAt(points.map(point=>[point[1],point[0]]),lat);
const meanLongitude = (lat,e) => (longitudeAt(e.ways[0].coordinates,lat)+longitudeAt(e.ways[1].coordinates,lat))/2;
function verifyEvidence(e,cache) {
  assert.equal(e.format,'jtm-keiyo-shio-transverse-display-v1');
  assert.deepEqual(e.point,[139.9235689842168,35.66650455364835],'Unreviewed Shio transverse image point');
  assert.deepEqual(e.ways.map(row=>row.id),[1242538090,1242538092]);
  assert.deepEqual(e.fullCorrectionLatitudes,[35.66555,35.667547],'Shio correction must stay in reviewed image latitude coverage');
  if(cache) assert.equal(cache.fetchedAt,e.source.fetchedAt,'Shio source cache changed');
  for(const way of e.ways) {
    assert(way.tags.railway==='rail' && way.tags.usage==='main' && way.tags.name==='JR京葉線' && way.tags.operator==='東日本旅客鉄道' && !way.tags.service,'Shio passenger source identity changed');
    if(cache) {
      const actual=cache.elements.find(row=>row.id===way.id);
      assert.deepEqual({id:actual?.id,tags:actual?.tags,coordinates:actual?.geometry.map(point=>[point.lon,point.lat])},way,'Shio passenger survey changed');
    }
  }
}
function marker(e) {
  return {reviewedAt:e.reviewedAt,script:'app/scripts/railway/repair-keiyo-shio-transverse-display.mjs',evidence:'app/scripts/railway/keiyo-shio-transverse-display-evidence.json',source:e.source,stationID:e.stationID,point:e.point,ways:e.ways.map(row=>row.id),northBoundary:e.northBoundary,outboundBoundary:e.outboundBoundary,fullCorrectionLatitudes:e.fullCorrectionLatitudes,imageReferences:e.imageReferences,imageEvidence:e.imageEvidence,policy:e.policy,evidenceBoundary:e.evidenceBoundary};
}
// Common-latitude source means are a display representation. The image
// calibration residual is applied laterally; retained boundaries taper to zero.
function localApproach(original,boundary,side,e) {
  const station=e.point, lower=e.fullCorrectionLatitudes[0],upper=e.fullCorrectionLatitudes[1];
  const inside=lat=>side==='north'?lat>station[1] && lat<boundary[1]:lat<station[1] && lat>boundary[1];
  const latitudes=[...new Set([...original,...e.ways.flatMap(row=>row.coordinates)].map(row=>row[1]).filter(inside))].sort((a,b)=>b-a);
  const residual=station[0]-meanLongitude(station[1],e);
  const representative=lat=> {
    let weight=1;
    if(lat>upper) weight=(boundary[1]-lat)/(boundary[1]-upper);
    else if(lat<lower) weight=(lat-boundary[1])/(lower-boundary[1]);
    assert(weight>=0 && weight<=1,'Shio lateral correction left its reviewed window');
    const corrected=meanLongitude(lat,e)+residual;
    const lon=weight===1?corrected:longitudeAt(original,lat)*(1-weight)+corrected*weight;
    return [lon,lat];
  };
  const middle=latitudes.map(representative);
  return side==='north'?[boundary,...middle,station]:[station,...middle,boundary];
}
export function repairShioPackage(input,cache,e=shioEvidence) {
  verifyEvidence(e,cache);
  input=structuredClone(input);
  find(input,e.armID).displayIntervalCoordinates[0]=westernPassengerApproach(find(input,e.armID).displayIntervalCoordinates[0],undefined,cache);
  if(hasShioStage(input)) return repairShioPackage(retainedShioPackage(input,e),cache,e);
  const pkg=structuredClone(input),trunk=find(pkg,e.trunkID),arm=find(pkg,e.armID);
  const b={...e.baseline,armCoordinates:westernPassengerApproach(e.baseline.armCoordinates)};
  assert.equal(trunk.operator,arm.operator,'Shio passenger company changed');
  assert.deepEqual([trunk.segments[8],trunk.segments[9],arm.segments[0]],b.physicalSegments,'Shio physical source or mileage changed');
  for(const [i,line] of [trunk,arm].entries()) {
    assert.deepEqual(line.stations.find(row=>row[0]===e.stationID),b.stationRows[i],'Shio physical station changed');
    assert(!line.displayStationCoordinates?.[e.stationID],'Unreviewed Shio display station');
  }
  assert.deepEqual(arm.displayIntervalCoordinates[0],b.armCoordinates,'Unreviewed Shio arm display source');
  assert.deepEqual(trunk.displayIntervalCoordinates[8],b.trunkCoordinates,'Unreviewed Shio trunk display source');
  assert(!trunk.displayIntervalCoordinates[9],'Unreviewed Shio outbound display source');
  assert.deepEqual(network.decodeIntervals(trunk)[9],b.outboundCoordinates,'Shio outbound physical source changed');
  const northIndex=b.armCoordinates.findIndex(point=>equal(point,e.northBoundary));
  assert(northIndex>shared.armDisplayForkIndex,'Shio local entry must remain beyond the real fork');
  const northOriginal=b.armCoordinates.slice(northIndex),north=localApproach(northOriginal,e.northBoundary,'north',e);
  const outbound=e.outboundBoundary, next=b.outboundCoordinates[outbound.insertIndex+1];
  assert(next && outbound.point[1]<b.outboundCoordinates[outbound.insertIndex][1] && outbound.point[1]>next[1],'Shio outbound boundary edge changed');
  const southOriginal=[...b.outboundCoordinates.slice(0,outbound.insertIndex+1),outbound.point];
  const south=localApproach(southOriginal,outbound.point,'south',e);
  arm.displayIntervalCoordinates[0]=[...b.armCoordinates.slice(0,northIndex),...north];
  assert.deepEqual(arm.displayIntervalCoordinates[0][shared.armDisplayForkIndex],shared.fork,'Shio real fork changed');
  trunk.displayIntervalCoordinates[8]=[...b.trunkCoordinates.slice(0,shared.trunkDecodedForkIndex),...arm.displayIntervalCoordinates[0].slice(shared.armDisplayForkIndex)];
  trunk.displayIntervalCoordinates[9]=[...south,...b.outboundCoordinates.slice(outbound.insertIndex+1)];
  for(const line of [trunk,arm]) line.displayStationCoordinates={...line.displayStationCoordinates,[e.stationID]:structuredClone(e.point)};
  pkg.geometrySource.manualOverrides[SHIO_STAGE]=marker(e);
  return pkg;
}
export function retainedShioPackage(input,e=shioEvidence) {
  if(!hasShioStage(input)) return structuredClone(input);
  input=structuredClone(input);
  find(input,e.armID).displayIntervalCoordinates[0]=westernPassengerApproach(find(input,e.armID).displayIntervalCoordinates[0]);
  assert.deepEqual(input.geometrySource.manualOverrides[SHIO_STAGE],marker(e),'Shio provenance changed');
  const pkg=structuredClone(input),trunk=find(pkg,e.trunkID),arm=find(pkg,e.armID);
  trunk.displayIntervalCoordinates[8]=structuredClone(e.baseline.trunkCoordinates);
  delete trunk.displayIntervalCoordinates[9];
  arm.displayIntervalCoordinates[0]=westernPassengerApproach(e.baseline.armCoordinates);
  for(const line of [trunk,arm]) {
    delete line.displayStationCoordinates[e.stationID];
    if(!Object.keys(line.displayStationCoordinates).length) delete line.displayStationCoordinates;
  }
  delete pkg.geometrySource.manualOverrides[SHIO_STAGE];
  assert.deepEqual(repairShioPackage(pkg,undefined,e),input,'Unreviewed Shio retained display stage changed');
  return pkg;
}
export const hasShioNativeParts=(pkg,input)=>hasReviewedKeiyoNativeParts(pkg,input,[shioEvidence.trunkID,shioEvidence.armID]);
export function shioPartsForStage(pkg,input,final=true) {
  return partsForRetainedKeiyoStage(pkg,input,retainedShioPackage(pkg),final);
}
