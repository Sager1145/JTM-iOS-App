import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const net=createRequire(import.meta.url)('../../../public/rail-network.js');
const authority=JSON.parse(fs.readFileSync(new URL('../../../../railway-evidence/local/proposals/keihan-main-hashimoto-otani-20261020/bounded-visible-track-candidate-v2.json',import.meta.url)));
const target=new URL('../repair-keihan-hashimoto-otani-display.mjs',import.meta.url);
const impl=await import(target);
const input=()=>({lines:[structuredClone(authority.baselineLine),{id:'unrelated',keep:['existing']}],geometrySource:{manualOverrides:{unrelated:{keep:true}}}});
const digest=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');

test('Hashimoto and Iwashimizu dots follow manually selected own north strokes while both outer approaches stay exact',()=>{
 const before=input(),result=impl.repairPackage(before,authority),line=result.lines[0];
 assert.deepEqual(line.displayStationCoordinates?.['006356'],[135.68428569080731,34.88207001200255]);
 assert.deepEqual(line.displayStationCoordinates?.['006351'],[135.70000511045072,34.88466139931174]);
 const source=net.decodeIntervals(before.lines[0]);
 assert.deepEqual(line.displayIntervalCoordinates[23].slice(0,25),source[23].slice(0,25));
 assert.deepEqual(line.displayIntervalCoordinates[25].slice(-55),source[25].slice(10));
 assert.deepEqual(line.stations,before.lines[0].stations);assert.deepEqual(line.segments,before.lines[0].segments);assert.deepEqual(net.decodeIntervals(line),source);
 assert.deepEqual(line,authority.candidateLine);assert.equal(digest(line),'d15eb240db8c183c7b55925f5a11a283935b5147cbb87081c417544b3b514a58');
 const parts=net.displayPartsForLine(line)[0],old=net.displayPartsForLine(before.lines[0])[0];assert.equal(parts.length,838);assert.deepEqual(parts.slice(0,502),old.slice(0,502));assert.deepEqual(parts.slice(-264),old.slice(-264));
 assert.deepEqual(result.lines[1],before.lines[1]);assert.deepEqual(result.geometrySource.manualOverrides.unrelated,{keep:true});assert.deepEqual(impl.repairPackage(result,authority),result);
});

test('correct affected receipt scope advances to capture proof; missing proof, stale own hash and false acceptance stay rejected',()=>{
 const line=impl.repairPackage(input(),authority).lines[0];
 assert.throws(()=>impl.validateCandidateReview(null,line),/receipt required/);
 const receipt={format:'jtm-keihan-hashimoto-otani-candidate-review-v1',status:'bounded-candidate-reviewed',lineID:authority.lineID,stationIDs:['006356','006351'],intervalIndices:[23,24,25],wholeLineAccepted:false,MainCertified:false,reviewedOwnLineSha256:digest(line),captures:[]};
 assert.throws(()=>impl.validateCandidateReview(receipt,line),/scoped reviewed captures required/);
 assert.throws(()=>impl.validateCandidateReview({...receipt,reviewedOwnLineSha256:'stale'},line),/reviewed own line changed/);
 const v1=JSON.parse(fs.readFileSync(new URL('../../../../railway-evidence/local/proposals/keihan-main-hashimoto-otani-20261020/bounded-visible-track-candidate.json',import.meta.url)));
 assert.throws(()=>impl.validateCandidateReview({...receipt,reviewedOwnLineSha256:digest(v1.candidateLine)},line),/reviewed own line changed/);
 assert.throws(()=>impl.validateCandidateReview({...receipt,intervalIndices:[2,3,4,5]},line),/review scope changed/);
 assert.throws(()=>impl.validateCandidateReview({...receipt,MainCertified:true},line),/review scope changed/);
});

test('actual JS fallback refreshes own ruler while known excluded Kyoto report and every foreign field stay exact',()=>{
 const baseline=JSON.parse(fs.readFileSync(new URL('../../../../railway-evidence/local/proposals/keihan-main-hashimoto-otani-20261020/baseline-native-references.json',import.meta.url)));
 const other=['unrelated',0,0,1,2,20,null,null,[]],lanes={...structuredClone(baseline),byRegion:{jp:[['unrelated',0,0,10,0.5]]},followsByRegion:{jp:[]},keep:{value:42}};
 lanes.partsByRegion.jp.push(other);lanes.partsByRegion.tw=[other];const before=structuredClone(lanes);
 const pkg=impl.repairPackage(input(),authority),result=impl.repairParts(pkg,lanes,authority),row=result.partsByRegion.jp[0];
 assert.deepEqual(row.slice(1,7),[0,-1,-1,838,49262.1,'complex']);assert.deepEqual(row[7],net.displayPartsForLine(pkg.lines[0])[0]);
 assert.deepEqual(result.hubReportByRegion,before.hubReportByRegion);assert.deepEqual(result.partsByRegion.jp[1],other);assert.deepEqual(result.partsByRegion.tw,before.partsByRegion.tw);
 for(const k of Object.keys(lanes).filter(k=>k!=='partsByRegion'))assert.deepEqual(result[k],lanes[k]);assert.deepEqual(lanes,before);assert.deepEqual(impl.repairParts(pkg,result,authority),result);
 const bad=structuredClone(lanes);bad.partsByRegion.jp[0][4]++;assert.throws(()=>impl.repairParts(pkg,bad,authority),/stale\/foreign own native row/);
 const foreign=structuredClone(lanes);foreign.followsByRegion.jp.push(['unrelated',0,0,1,authority.lineID,0,0,1]);assert.throws(()=>impl.repairParts(pkg,foreign,authority),/own native reference requires review/);
 const hub=structuredClone(lanes);hub.hubReportByRegion.jp[0].members.find(m=>m.lineId===authority.lineID).excluded='active';assert.throws(()=>impl.repairParts(pkg,hub,authority),/own hub report changed/);
});

test('stale physical source, wrong manual control/projection and changed protected endpoints cannot extend authority',()=>{
 const stale=input();stale.lines[0].segments[0][0]+=.001;assert.throws(()=>impl.repairPackage(stale,authority),/current own source changed/);
 const wrong=structuredClone(authority);wrong.supportAuthority[0].pixel[0]++;assert.throws(()=>impl.repairPackage(input(),wrong),/own-track pixel authority changed/);
 const projected=structuredClone(authority);projected.supportAuthority[0].coordinate[1]+=.00001;assert.throws(()=>impl.repairPackage(input(),projected),/support projection changed/);
 const outer=structuredClone(authority);outer.candidateLine.displayIntervalCoordinates[23][24][0]+=.00001;assert.throws(()=>impl.repairPackage(input(),outer),/candidate exceeds bounded authority/);
 const suffix=structuredClone(authority);suffix.candidateLine.displayIntervalCoordinates[25].at(-1)[0]+=.00001;assert.throws(()=>impl.repairPackage(input(),suffix),/candidate exceeds bounded authority/);
 const baseline=structuredClone(authority);baseline.baselineLine.stations[24][2]+=.0001;assert.throws(()=>impl.repairPackage(input(),baseline),/baseline changed/);
});

// Distances use actual station snapshot map-point scale, not nearest vertices.
function witnessDistancePixels(s,line){
 const q=JSON.parse(fs.readFileSync(s.viewJSON)).snapshotProjection,world=2**28;
 const xy=([longitude,latitude])=>[(longitude+180)/360*world/q.mapPointsPerPointX,(1-Math.asinh(Math.tan(latitude*Math.PI/180))/Math.PI)/2*world/q.mapPointsPerPointY];
 const p=xy(s.coordinate);let best=Infinity;
 for(const part of net.displayPartsForLine(line))for(let j=1;j<part.length;j++){
  const a=xy(part[j-1]),b=xy(part[j]),dx=b[0]-a[0],dy=b[1]-a[1],den=dx*dx+dy*dy;
  const t=den?Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/den)):0;
  best=Math.min(best,Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy));
 }return best;
}
test('refined station curves remove the rejected sparse candidate chord departures at literal witnesses',()=>{
 const v1=JSON.parse(fs.readFileSync(new URL('../../../../railway-evidence/local/proposals/keihan-main-hashimoto-otani-20261020/bounded-visible-track-candidate.json',import.meta.url)));
 const line=impl.repairPackage(input(),authority).lines[0];
 assert.deepEqual([23,24,25].map(i=>line.displayIntervalCoordinates[i].length),[45,26,65]);
 for(const id of ['hash-refine-0','hash-refine-1','iwa-refine-0','iwa-refine-1','iwa-refine-3','iwa-refine-8','iwa-refine-9']){
  const s=authority.supportAuthority.find(s=>s.id===id);
  assert(witnessDistancePixels(s,v1.candidateLine)>10, id+' must expose rejected sparse chord');
  assert(witnessDistancePixels(s,line)<1,id+' refined own curve must reach actual witness');
 }
 assert.throws(()=>impl.repairPackage(input(),v1),/own-track pixel authority changed/);
});
