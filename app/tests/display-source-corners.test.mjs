import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';
const require=createRequire(import.meta.url), Network=require('../public/rail-network.js'),Stroke=require('../public/rail-stroke.js');
const points=[[139,35],[139.001,35.0001],[139.002,35.0002],[139.003,35.0003],[139.004,35.00015],[139.0042,35.00015],[139.005,35.0004],[139.006,35.0008]];
function fixture(){return {id:'jp-source-corners',name:'fixture',operator:'test',stations:[['a','A',...points[0]],['b','B',...points.at(-1)]],segments:[[4,0,points]],displayIntervalCoordinates:{0:points},displayInterpolation:{contract:'display-source-corners-v1',spans:[{intervalIndex:0,sourceEdgeIndex:3,endpoints:points.slice(3,5)}]}};}
function network(line,lanes=null){return Network.buildNetworkFromCompactPackage({format:'compact-v1',country:'jp',lines:[line]},null,lanes);}
const expected={edgeIndex:3,witnesses:points.slice(2,6),mode:'source-corners-v1'};
test('source-corner declaration binds exact raw/fullpart witnesses and never changes coordinates',()=>{
 const line=fixture(),before=structuredClone(line),part=network(line).strokeModel.lines[0].parts[0];
 assert.deepEqual(part.literalSpans,[expected]);assert.deepEqual(part.coordinates,points);assert.deepEqual(line,before);
 for(const alter of [l=>l.displayInterpolation.spans.push(l.displayInterpolation.spans[0]),l=>l.displayInterpolation.spans[0].endpoints=[[0,0],points[4]],l=>l.stations.push(['inside','inside',...points[2]])]) {
   const changed=fixture();alter(changed);assert.deepEqual(Network.displayLiteralSpansForLine(changed,[points]),[[]]);
 }
 assert.deepEqual(Network.displayLiteralSpansForLine(line,Network.displayPartsForLine(line,[points])),[[]]);
 const lanes=extra=>({format:'jtm-display-lanes-v1',...extra});
 for(const declarations of [
   {byRegion:{jp:[[line.id,0,0,10000,1]]}},
   {followsByRegion:{jp:[['offscreen',0,0,100,line.id,0,0,100]]}},
   {familyWindowsByRegion:{jp:[[line.id,0,100,1000,0,'family']]}},
 ]) assert.equal(network(line,lanes(declarations)).strokeModel.lines[0].parts[0].literalSpans,undefined);
});
test('mode survives projection and separates same-geometry renderer cache entries',()=>{
 const calls=[],context=vm.createContext({console,RailMapBasemap:{},RailMapGeometry:{},RailNetwork:Network,RailStroke:{...Stroke,buildStroke:(px,opts)=>{calls.push(opts);return Stroke.buildStroke(px,opts);}}});context.window=context;
 for(const file of ['railmap-style.js','railmap.js']) vm.runInContext(fs.readFileSync(new URL(`../public/${file}`,import.meta.url),'utf8'),context);
 const n=network(fixture()), map=context.RailMap;map._network=n;map._map={getZoom:()=>18,getBounds:()=>({getWest:()=>138,getEast:()=>141,getSouth:()=>34,getNorth:()=>36})};
 map._applyContinuousStrokes(false);assert.equal(calls.length,1);assert.equal(calls[0].literalSpans[0].mode,'source-corners-v1');
 const part=n.strokeModel.lines[0].parts[0];part.literalSpans=[{edgeIndex:3,witnesses:points.slice(2,6)}];
 map._applyContinuousStrokes(false);assert.equal(calls.length,2,'mode-only changes invalidate same-zoom entry');
 part.literalSpans=[expected];map._applyContinuousStrokes(false);assert.equal(calls.length,2,'exact corner entry remains separately reusable');
});

test('declared branch endpoints protect the source footprint even when their parts are absent',()=>{
 for(const key of ['displayBranchLeadIns','displayReversalBranches'])
   for(const witness of points.slice(2,6))
     for(const branch of [[witness,[140,36]],[[140,36],witness]]) {
       const line=fixture();line[key]=[branch];
       assert.deepEqual(Network.displayLiteralSpansForLine(line,[points]),[[]],`${key} endpoint must not depend on branch residency`);
       line.displayInterpolation.contract='display-literal-spans-v1';
       assert.deepEqual(Network.displayLiteralSpansForLine(line,[points]),[{edgeIndex:3,witnesses:points.slice(2,6)}].map(s=>[s]),'legacy direct resolver behavior remains unchanged');
     }
});
