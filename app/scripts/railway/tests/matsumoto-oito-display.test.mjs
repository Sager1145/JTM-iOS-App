import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { assertApplyAccepted, candidateGeoJSON, loadReviewedCandidate, repairPackage,
  repairParts, repairedNativeRow } from '../repair-matsumoto-oito-display.mjs';

const require=createRequire(import.meta.url), network=require('../../../public/rail-network.js');
const e=JSON.parse(fs.readFileSync(new URL('../matsumoto-oito-display-evidence.json',import.meta.url)));
const livePackage=JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json',import.meta.url)));
const liveLanes=JSON.parse(fs.readFileSync(new URL('../../../public/rail/display-lanes.json',import.meta.url)));
const registry=JSON.parse(fs.readFileSync(new URL('../../../data/physical-rail-junctions.json',import.meta.url)));
const hash=v=>crypto.createHash('sha256').update(JSON.stringify(v)).digest('hex');
const related=[e.lineID,e.related.shinonoiID,e.related.kamikochiID];

function packageFixture(){const lines=Array.from({length:livePackage.lines.length},(_,i)=>({id:`unrelated-${i}`}));for(const id of related){const i=livePackage.lines.findIndex(x=>x.id===id);lines[i]=structuredClone(livePackage.lines[i]);}return{format:'compact-v1',country:'jp',lines,geometrySource:{manualOverrides:{concurrent:{keep:true}}}};}
function laneFixture() {
  const candidate = loadReviewedCandidate(e);
  const row = structuredClone(liveLanes.partsByRegion.jp.find(item => item[0] === e.lineID));
  if (hash(row) === e.nativeReplay.candidateRowSha256) {
    row[4] = e.baseline.nativeSummary.pointCount;
    row[5] = e.baseline.nativeSummary.metres;
    row[7] = [
      ...row[7].slice(0, e.nativeReplay.commonPrefixPoints),
      ...candidate.sourceCoordinates.slice(e.candidate.retainedThroughIndex + 1)
    ];
  }
  assert.equal(hash(row), e.baseline.nativeRowSha256,
    'Fixture could not reconstruct the frozen baseline Oito native row');
  return {
    partsByRegion: { jp: [row, ['unrelated', 0, 1]] },
    byRegion: { jp: [...structuredClone(e.baseline.measuredReferences.byRegion),
      structuredClone(e.related.shinonoiLane), ['unrelated', 0, 0, 1, .5]] },
    followsByRegion: { jp: [['unrelated', 0, 0, 1, 'other', 0, 0, 1]] },
    familyWindowsByRegion: { jp: [] },
    chainBoundariesByRegion: { jp: [] },
    hubsByRegion: { jp: {} }
  };
}

test('frozen candidate retains the reviewed approach and replaces only the cross-platform J tail',()=>{const c=loadReviewedCandidate(e);assert.deepEqual(c.coordinates.slice(0,7),c.sourceCoordinates.slice(0,7));assert.deepEqual(c.sourceCoordinates.slice(7),[e.candidate.physicalJunction,[137.963844,36.231165]]);assert.deepEqual(c.coordinates.at(-1),e.candidate.displayAnchor);assert(c.directionEvidence.acuteAxisDifferenceDegrees<5);assert(!c.coordinates.some(p=>JSON.stringify(p)===JSON.stringify(e.candidate.physicalJunction)));});

test('repair owns only Oito interval 31 and station alias while physical topology and related lines stay exact',()=>{const before=packageFixture(),physical=network.decodeIntervals(before.lines[e.packageIndex]),shin=structuredClone(before.lines.find(x=>x.id===e.related.shinonoiID)),kami=structuredClone(before.lines.find(x=>x.id===e.related.kamikochiID));const after=repairPackage(before,e),line=after.lines[e.packageIndex];assert.deepEqual(Object.keys(line.displayIntervalCoordinates),['31']);assert.deepEqual(Object.keys(line.displayStationCoordinates),[e.stationID]);assert.deepEqual(network.decodeIntervals(line),physical);assert.deepEqual(after.lines.find(x=>x.id===e.related.shinonoiID),shin);assert.deepEqual(after.lines.find(x=>x.id===e.related.kamikochiID),kami);assert.deepEqual(after.geometrySource.manualOverrides.concurrent,{keep:true});assert.deepEqual(repairPackage(after,e),after);});

test('physical J still belongs only to Shinonoi and Oito and is not forced into the display endpoint',()=>{const j=registry.junctions.find(x=>x.id===e.related.junctionID);assert.deepEqual(j.lineIDs,[e.related.shinonoiID,e.lineID]);assert.deepEqual(j.from.coordinate,e.candidate.physicalJunction);assert.deepEqual(j.to.coordinate,e.candidate.physicalJunction);assert(!j.lineIDs.includes(e.related.kamikochiID));const line=repairPackage(packageFixture(),e).lines[e.packageIndex];assert.notDeepEqual(line.displayIntervalCoordinates[31].at(-1),j.to.coordinate);});

test('physical source neighbors preserve the legal south-to-Oito direction and require a Tazawa reversal', () => {
  const lines = packageFixture().lines;
  const oito = network.decodeIntervals(lines[e.packageIndex])[e.intervalIndex];
  const shinonoi = network.decodeIntervals(lines.find(line => line.id === e.related.shinonoiID));
  const junction = e.candidate.physicalJunction;
  const same = point => JSON.stringify(point) === JSON.stringify(junction);
  const oitoJunctionIndex = oito.findIndex(same);
  const shinonoiInterval = shinonoi.find(interval => interval.some(same));
  const shinonoiJunctionIndex = shinonoiInterval.findIndex(same);
  assert(oitoJunctionIndex > 0);
  assert(shinonoiJunctionIndex > 0 && shinonoiJunctionIndex < shinonoiInterval.length - 1);

  const northOito = oito[oitoJunctionIndex - 1];
  const southShinonoi = shinonoiInterval[shinonoiJunctionIndex - 1];
  const northTazawa = shinonoiInterval[shinonoiJunctionIndex + 1];
  const bearing = (from, to) => Math.atan2(
    (to[0] - from[0]) * Math.cos((from[1] + to[1]) * Math.PI / 360),
    to[1] - from[1]
  ) * 180 / Math.PI;
  const directionChange = (from, through, to) => {
    const difference = Math.abs(bearing(from, through) - bearing(through, to)) % 360;
    return Math.min(difference, 360 - difference);
  };

  assert(directionChange(southShinonoi, junction, northOito) < 30,
    'South Shinonoi to north Oito must remain a forward movement');
  assert(directionChange(northTazawa, junction, northOito) > 150,
    'Tazawa to north Oito must remain a Matsumoto station reversal');
});

test('owning helper changes only the final native sample and Oito full-part measure',()=>{const pkg=repairPackage(packageFixture(),e),before=laneFixture(),old=before.partsByRegion.jp[0],after=repairParts(pkg,before,e),row=after.partsByRegion.jp.find(x=>x[0]===e.lineID);assert.deepEqual(row,repairedNativeRow(pkg,e));assert.equal(hash(row),e.nativeReplay.candidateRowSha256);assert.deepEqual(row[7].slice(0,e.nativeReplay.commonPrefixPoints),old[7].slice(0,e.nativeReplay.commonPrefixPoints));assert.deepEqual(old[7].slice(e.nativeReplay.commonPrefixPoints),[e.candidate.physicalJunction,[137.963844,36.231165]]);assert.deepEqual(row[7].slice(e.nativeReplay.commonPrefixPoints),[e.candidate.displayAnchor]);assert.deepEqual(after.byRegion.jp.filter(x=>x[0]===e.lineID),e.nativeReplay.candidateMeasuredReferences.byRegion);assert.deepEqual(after.byRegion.jp.filter(x=>x[0]===e.related.shinonoiID),[e.related.shinonoiLane]);assert.deepEqual(after.followsByRegion,before.followsByRegion);assert.deepEqual(repairParts(pkg,after,e),after);});

test('feature, fail-closed guards, and explicit pending/accepted gates stay deterministic',()=>{const pkg=repairPackage(packageFixture(),e),f=candidateGeoJSON(pkg,e);assert.deepEqual([f.properties.referenceLineID,f.properties.referenceIntervalIndex],[e.lineID,31]);const p=packageFixture();p.lines[e.packageIndex].segments[31][0]+=.001;assert.throws(()=>repairPackage(p,e),/physical dependency/);const n=laneFixture();n.partsByRegion.jp[0][5]+=1;assert.throws(()=>repairParts(pkg,n,e),/native dependency/);const m=laneFixture();m.byRegion.jp[0][3]+=1;assert.throws(()=>repairParts(pkg,m,e),/measured reference/);const pending=structuredClone(e);pending.status='candidate-only';assert.throws(()=>assertApplyAccepted(pending),/accepted native and Main/);const accepted=structuredClone(e);accepted.status=accepted.policy.acceptanceGate;assert.doesNotThrow(()=>assertApplyAccepted(accepted));});
