// Retained final display stage: local passenger centre, never physical topology.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { partRowsForLine, deriveFamilyWindows } from './build-display-lanes.mjs';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const read = file => JSON.parse(fs.readFileSync(new URL(file, import.meta.url)));
export const minamiEvidence = read('./keiyo-minami-passenger-centre-evidence.json');
const shared = read('./keiyo-shared-corridor-evidence.json');
export const MINAMI_STAGE = 'keiyo-minami-passenger-centre';
const ebigawaAlias = read('./keiyo-midcurve-evidence.json').seamRemoval;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const find = (pkg, id) => pkg.lines.find(line => line.id === id);
export const hasMinamiStage = pkg => Boolean(pkg.geometrySource?.manualOverrides?.[MINAMI_STAGE]);
// One exact display splice, shared by the authoritative midcurve replay and
// the later station-centre replay. Earlier raw N02 chains remain historical.
export function withoutEbigawaDisplayAlias(points) {
  const result = structuredClone(points), e = ebigawaAlias;
  for (const [before, after] of [[e.before, e.after], [e.after, e.before]]) {
    const index = result.findIndex((point, i) => same(point, e.alias) &&
      same(result[i - 1], before) && same(result[i + 1], after));
    if (index >= 0) { result.splice(index, 1); return result; }
  }
  return result;
}

export function latitudeAt(points, lon) {
  const vertices = points.filter(point => point[0] === lon);
  if (vertices.length) {
    assert.equal(vertices.length, 1, 'Passenger longitude has competing surveyed vertices');
    return vertices[0][1];
  }
  const edges = points.slice(1).map((b, i) => [points[i], b]).filter(([a, b]) => lon >= Math.min(a[0], b[0]) && lon <= Math.max(a[0], b[0]));
  assert(edges.length === 1, 'Passenger track longitude must identify one surveyed edge');
  const [a, b] = edges[0];
  return a[1] + (b[1] - a[1]) * (lon - a[0]) / (b[0] - a[0]);
}
export function representativeAt(lon, evidence = minamiEvidence) {
  const [north, , , south] = evidence.platformWays;
  return [lon, (latitudeAt(north.coordinates, lon) + latitudeAt(south.coordinates, lon)) / 2];
}
function verifyEvidence(evidence, cache) {
  assert.equal(evidence.format, 'jtm-keiyo-minami-passenger-centre-v1');
  assert.deepEqual(evidence.platformWays.map(row => [row.platform, row.id]), [[1,173053168],[2,1424469769],[3,1424469770],[4,173053163]]);
  if (cache) assert.equal(cache.fetchedAt, evidence.source.fetchedAt, 'Minami source cache changed');
  for (const way of evidence.platformWays) {
    assert.equal(way.tags.operator, '東日本旅客鉄道');
    assert.equal(way.tags.name, 'JR京葉線');
    assert.equal(way.tags.railway, 'rail');
    assert.equal(way.tags.layer, '1');
    // Inner service=siding tracks are identified passenger platform faces.
    assert.equal(way.tags.service, [2,3].includes(way.platform) ? 'siding' : undefined);
    if (cache) {
      const actual = cache.elements.find(row => row.id === way.id);
      assert.deepEqual(actual?.tags, way.tags, 'Minami passenger track identity changed');
      assert.deepEqual(actual.geometry.filter(point => point.lon > 139.992 && point.lon < 139.999).map(point => [point.lon,point.lat]), way.coordinates, 'Minami surveyed passenger supports changed');
    }
  }
  const longitudes = evidence.supportLongitudes;
  assert.deepEqual(longitudes, [...new Set(longitudes)].sort((a, b) => a - b), 'Minami centre supports must be sorted and unique');
  for (const way of [evidence.platformWays[0], evidence.platformWays[3]])
    for (const point of way.coordinates)
      if (point[0] >= longitudes[0] && point[0] <= longitudes.at(-1))
        assert(longitudes.includes(point[0]), 'Minami centre must retain both outer tracks source supports');
  const point = representativeAt(evidence.longitude, evidence);
  assert(point[1] < latitudeAt(evidence.platformWays[1].coordinates, point[0]) && point[1] > latitudeAt(evidence.platformWays[2].coordinates, point[0]), 'Representative must lie between identified inner passenger faces');
}
function marker(e) {
  return { reviewedAt: e.reviewedAt, script: 'app/scripts/railway/repair-keiyo-minami-passenger-centre.mjs', evidence: 'app/scripts/railway/keiyo-minami-passenger-centre-evidence.json', source: e.source, stationID:e.stationID, point:representativeAt(e.longitude,e), platformWays:e.platformWays.map(row => [row.platform,row.id]), identityReferences:e.identityReferences, policy:e.policy, evidenceBoundary:e.evidenceBoundary };
}
export function repairMinamiPackage(input, cache, evidence = minamiEvidence) {
  verifyEvidence(evidence, cache);
  input = structuredClone(input);
  for (const [id, interval] of [[evidence.armID, 0], [evidence.trunkID, 7]]) {
    const line = find(input, id);
    line.displayIntervalCoordinates[interval] = withoutEbigawaDisplayAlias(line.displayIntervalCoordinates[interval]);
  }
  if (hasMinamiStage(input)) {
    const baseline = retainedMinamiPackage(input, evidence);
    return repairMinamiPackage(baseline, cache, evidence);
  }
  const pkg = structuredClone(input), trunk = find(pkg,evidence.trunkID), arm = find(pkg,evidence.armID);
  const b = { ...evidence.baseline, armCoordinates: withoutEbigawaDisplayAlias(evidence.baseline.armCoordinates),
    trunkCoordinates: withoutEbigawaDisplayAlias(evidence.baseline.trunkCoordinates) };
  assert.deepEqual(trunk.segments[6],b.eastPhysicalSegment,'Minami physical east source changed');
  for (const [i,line] of [trunk,arm].entries()) {
    assert.deepEqual(line.stations.find(row=>row[0]===evidence.stationID),b.stationRows[i],'Minami physical station changed');
    assert(!line.displayStationCoordinates?.[evidence.stationID],'Unreviewed Minami display station');
  }
  assert.deepEqual(arm.displayIntervalCoordinates[0],b.armCoordinates,'Unreviewed Minami arm source');
  assert.deepEqual(trunk.displayIntervalCoordinates[7],b.trunkCoordinates,'Unreviewed Minami trunk source');
  assert(!trunk.displayIntervalCoordinates[6],'Unreviewed Minami east source');
  const point = representativeAt(evidence.longitude,evidence), centres=evidence.supportLongitudes.map(lon=>representativeAt(lon,evidence));
  const westIndex=b.armCoordinates.findIndex(row=>same(row,evidence.westBoundary));
  const eastIndex=b.eastCoordinates.findIndex(row=>same(row,evidence.eastBoundary));
  assert(westIndex>shared.armDisplayForkIndex && eastIndex>=0,'Minami local boundary missing');
  arm.displayIntervalCoordinates[0]=[...b.armCoordinates.slice(0,westIndex+1),...centres.filter(row=>row[0]<=point[0])];
  trunk.displayIntervalCoordinates[7]=[...arm.displayIntervalCoordinates[0].slice(shared.armDisplayForkIndex).toReversed(),...network.decodeIntervals(trunk)[7].slice(shared.trunkDecodedForkIndex+1)];
  trunk.displayIntervalCoordinates[6]=[...b.eastCoordinates.slice(0,eastIndex+1),...centres.filter(row=>row[0]>=point[0]).toReversed()];
  for(const line of [trunk,arm]) line.displayStationCoordinates={...line.displayStationCoordinates,[evidence.stationID]:point};
  pkg.geometrySource.manualOverrides[MINAMI_STAGE]=marker(evidence);
  return pkg;
}
export function retainedMinamiPackage(input, evidence = minamiEvidence) {
  if (!hasMinamiStage(input)) return structuredClone(input);
  input = structuredClone(input);
  for (const [id, interval] of [[evidence.armID, 0], [evidence.trunkID, 7]]) {
    const line = find(input, id);
    line.displayIntervalCoordinates[interval] = withoutEbigawaDisplayAlias(line.displayIntervalCoordinates[interval]);
  }
  assert.deepEqual(input.geometrySource.manualOverrides[MINAMI_STAGE],marker(evidence),'Minami provenance changed');
  const pkg=structuredClone(input),trunk=find(pkg,evidence.trunkID),arm=find(pkg,evidence.armID);
  trunk.displayIntervalCoordinates[7]=withoutEbigawaDisplayAlias(evidence.baseline.trunkCoordinates);
  delete trunk.displayIntervalCoordinates[6];
  arm.displayIntervalCoordinates[0]=withoutEbigawaDisplayAlias(evidence.baseline.armCoordinates);
  for(const line of [trunk,arm]) {
    delete line.displayStationCoordinates[evidence.stationID];
    if(!Object.keys(line.displayStationCoordinates).length) delete line.displayStationCoordinates;
  }
  delete pkg.geometrySource.manualOverrides[MINAMI_STAGE];
  assert.deepEqual(repairMinamiPackage(pkg,undefined,evidence),input,'Unreviewed Minami retained stage changed');
  return pkg;
}
const distance=(a,b)=>Math.hypot((b[0]-a[0])*111320*Math.cos((a[1]+b[1])*Math.PI/360),(b[1]-a[1])*111320);
function measuredRows(pkg,lanes) {
  const reviews=[shared];
  if(pkg.geometrySource.manualOverrides['keiyo-west-shared-corridor']) reviews.push(shared.western);
  const ids=new Set(reviews.flatMap(row=>[row.trunkID,row.armID]));
  const parts=[...ids].map(id=>{const line=find(pkg,id);const coordinates=network.displayPartsForLine(line);assert.equal(coordinates.length,1);return{lineId:id,partIndex:0,coordinates:coordinates[0],stationPoints:line.stations.map(row=>line.displayStationCoordinates?.[row[0]]||row.slice(2,4))};});
  const metrics=new Map(parts.map(part=>{const cumulative=[0];part.coordinates.slice(1).forEach((p,i)=>cumulative.push(cumulative.at(-1)+distance(part.coordinates[i],p)));return[part.lineId+'#0',{cumulative,total:cumulative.at(-1)}];}));
  const locate=(id,point)=>{const p=parts.find(row=>row.lineId===id);const i=p.coordinates.findIndex(row=>same(row,point));assert(i>=0,'Shared representative seam missing');return metrics.get(id+'#0').cumulative[i];};
  const follows=reviews.map(row=>{const point=find(pkg,row.armID).displayStationCoordinates?.[row.station[0]]||row.station.slice(1);return[row.armID,0,locate(row.armID,row.fork),locate(row.armID,point),row.trunkID,0,locate(row.trunkID,row.fork),locate(row.trunkID,point)];});
  const groups={byLineId:Object.fromEntries([...ids].map(id=>[id,shared.groupID])),families:{[shared.groupID]:{color:find(pkg,shared.trunkID).color}}};
  return{ids,parts:parts.flatMap(part=>partRowsForLine(find(pkg,part.lineId),[part.coordinates])),follows,windows:deriveFamilyWindows(parts,follows,groups,metrics,lanes.byRegion.jp)};
}
export function hasReviewedKeiyoNativeParts(pkg, input, changedIDs) {
  const current = measuredRows(pkg, input);
  return input.partsByRegion.jp.some(row => changedIDs.includes(row[0]) && same(row, current.parts.find(value => value[0] === row[0])));
}
export function hasMinamiNativeParts(pkg, input) {
  return hasReviewedKeiyoNativeParts(pkg, input, [shared.trunkID, shared.armID]);
}
// A replay may carry the exact retained rulers or exact final rulers. Every
// other measurement still fails closed before replacing any affected record.
export function minamiPartsForStage(pkg,input,final=true) {
  return partsForRetainedKeiyoStage(pkg,input,retainedMinamiPackage(pkg),final);
}
export function partsForRetainedKeiyoStage(pkg,input,retained,final=true) {
  const old=measuredRows(retained,input),current=measuredRows(pkg,input),ids=current.ids;
  const affected=(key,row)=>key==='followsByRegion'?ids.has(row[0])||ids.has(row[4]):ids.has(row[0]);
  for(const key of ['byRegion','loopsByRegion','chainBoundariesByRegion','strokeExcludedByRegion','releasedIntervalsByRegion'])
    assert(!(input[key]?.jp||[]).some(row=>[...ids].some(id=>JSON.stringify(row).includes(id))),'Minami unknown measured reference');
  assert(!(input.reversedLoopParts?.jp||[]).some(row=>ids.has(row.split('#')[0])),'Minami unknown loop reference');
  for(const hub of input.hubReportByRegion?.jp||[]) {
    if(![...ids].some(id=>JSON.stringify(hub).includes(id))) continue;
    assert(hub.hubId==='jp-tokyo' && hub.members?.filter(row=>ids.has(row.lineId)).length === 1 && ![...ids].some(id=>hub.trunkKey?.startsWith(id+'#') || JSON.stringify(hub.classes||[]).includes(id)) && hub.members?.filter(row=>ids.has(row.lineId)).every(row=>row.lineId===shared.trunkID && same(row,{lineId:shared.trunkID,partIndex:0,excluded:'crossing',previousLane:null})),'Minami unknown hub reference');
  }
  const output=structuredClone(input),target=final?current:old;
  for(const [key,name] of [['partsByRegion','parts'],['followsByRegion','follows'],['familyWindowsByRegion','windows']]) {
    const rows=input[key].jp.filter(row=>affected(key,row));
    assert(same(rows,old[name])||same(rows,current[name]),'Unreviewed Minami native ruler or ownership reference');
    if(key==='partsByRegion') output[key].jp=output[key].jp.map(row=>ids.has(row[0])?target.parts.find(value=>value[0]===row[0]):row);
    else output[key].jp=[...output[key].jp.filter(row=>!affected(key,row)),...target[name]];
  }
  return output;
}
