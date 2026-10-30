import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';
const Network=createRequire(import.meta.url)('../public/rail-network.js');
const points=[[139,34.9996],[139.001,34.99985],[139.0023,34.99997],[139.0036,35],[139.0336,35],[139.0349,35.00005],[139.0362,35.00024],[139.0372,35.0005]];
function fixture() {return {id:'jp-literal-fixture',name:'fixture',operator:'test',stations:[['a','A',...points[0]],['b','B',...points.at(-1)]],segments:[[4,0,structuredClone(points)]],displayInterpolation:{contract:'display-literal-spans-v1',spans:[{intervalIndex:0,sourceEdgeIndex:3,endpoints:structuredClone(points.slice(3,5))}]}};}
function model(line,lanes=null,extra=[]) {return Network.buildNetworkFromCompactPackage({format:'compact-v1',country:'jp',lines:[line,...extra]},null,lanes).strokeModel.lines[0];}
test('a reviewed interior source span reaches the complete stroke model without changing coordinates',()=>{
 const line=fixture(), before=structuredClone(line), part=model(line).parts[0];
 assert.deepEqual(part.literalSpans,[{edgeIndex:3,witnesses:points.slice(2,6)}]);
 assert.deepEqual(part.coordinates,points);assert.deepEqual(line,before);
});
test('malformed optional declarations preserve the ordinary public model shape',()=>{
 const ordinary=fixture();delete ordinary.displayInterpolation;const baseline=model(ordinary);
 for(const hint of [null,'wrong',[],{contract:'future',spans:[]},{contract:'display-literal-spans-v1',spans:{}},{contract:'display-literal-spans-v1',spans:[null,2,{intervalIndex:'0',sourceEdgeIndex:3,endpoints:points.slice(3,5)}]}]) {
  const line=fixture();line.displayInterpolation=hint;assert.deepEqual(model(line),baseline);
 }
});
test('raw arity, source adjacency and pair ownership must survive unchanged',()=>{
 for(const mutate of [
  line=>line.segments[0][2][2].push(0),
  line=>line.displayInterpolation.spans[0].sourceEdgeIndex=2,
  line=>line.displayInterpolation.spans[0].endpoints[0].push(0),
  line=>line.segments[0][2].push(...points.slice(3,5)),
  line=>line.displayInterpolation.spans.push(structuredClone(line.displayInterpolation.spans[0])),
 ]) {const line=fixture();mutate(line);assert.deepEqual(Network.displayLiteralSpansForLine(line,[points]),[[]]);}
 const line=fixture();const altered=structuredClone(points);altered[2][1]+=0.00001;
 assert.deepEqual(Network.displayLiteralSpansForLine(line,[altered]),[[]]);
 assert.deepEqual(Network.displayLiteralSpansForLine(line,[points,[points[2],[140,36]]]),[[],[]]);
 line.stations.push(['inside','inside',...points[2]]);
 assert.deepEqual(Network.displayLiteralSpansForLine(line,[points]),[[]]);
});
test('incoming references outside the rendered model and active outgoing follows reject opt-in',()=>{
 const lanes=rows=>({format:'jtm-display-lanes-v1',followsByRegion:{jp:rows}});
 assert.equal(model(fixture(),lanes([['offscreen-follower',0,0,100,'jp-literal-fixture',0,0,100]])).parts[0].literalSpans,undefined);
 assert.equal(model(fixture(),lanes([['jp-literal-fixture',0,0,100,'other',0,0,100]])).parts[0].literalSpans,undefined);
 assert.equal(model(fixture(),lanes([['offscreen-follower',0,0,0,'jp-literal-fixture',0,0,0]])).parts[0].literalSpans,undefined);
});
test('renderer projects exact current witnesses and invalidates same-zoom caches on hint-only changes',()=>{
 const Stroke=createRequire(import.meta.url)('../public/rail-stroke.js');
 const calls=[];const context=vm.createContext({console,RailMapBasemap:{},RailMapGeometry:{},RailNetwork:Network,
  RailStroke:{...Stroke,buildStroke:(px,options)=>{calls.push({px,options});return Stroke.buildStroke(px,options);}}});
 context.window=context;
 for(const file of ['railmap-style.js','railmap.js'])vm.runInContext(fs.readFileSync(new URL(`../public/${file}`,import.meta.url),'utf8'),context);
 const network=Network.buildNetworkFromCompactPackage({format:'compact-v1',country:'jp',lines:[fixture()]});
 const map=context.RailMap;map._network=network;map._map={getZoom:()=>13,getBounds:()=>({getWest:()=>138,getEast:()=>141,getSouth:()=>34,getNorth:()=>36})};
 map._applyContinuousStrokes(false);
 assert.equal(calls.length,1);
 assert.deepEqual(JSON.parse(JSON.stringify(calls[0].options.literalSpans)),[{edgeIndex:3,witnesses:calls[0].px.slice(2,6)}]);
 assert.deepEqual(network.strokeModel.lines[0].parts[0]._strokeLRU[0].stroke.appliedLiteralSpanEdges,[3]);
 map._applyContinuousStrokes(false);assert.equal(calls.length,1,'unchanged constraint uses built stroke');
 const part=network.strokeModel.lines[0].parts[0];delete part.literalSpans;
 map._applyContinuousStrokes(false);assert.equal(calls.length,2,'removing only the hint rebuilds at the same zoom');
 part.literalSpans=[{edgeIndex:3,witnesses:points.slice(2,6)}];
 map._applyContinuousStrokes(false);assert.equal(calls.length,2,'restoring the original constraint reuses its own LRU entry');
});
test('decoded replacement geometry never inherits a raw declaration even with identical points',()=>{
 const line=fixture();const parts=Network.displayPartsForLine(line,[structuredClone(points)]);
 assert.deepEqual(Network.displayLiteralSpansForLine(line,parts),[[]]);
 const other=fixture();other.id='jp-corridor-other';
 const reviewed={format:'jtm-shared-corridors-v1',corridors:[{id:'same-path',evidence:[{type:'a'},{type:'b'}],intervals:[{stationCodes:['a','b'],lineIds:[line.id,other.id],canonicalLineId:other.id}]}]};
 const built=Network.buildNetworkFromCompactPackage({format:'compact-v1',country:'jp',lines:[line,other]},reviewed);
 assert.equal(built.strokeModel.lines[0].parts[0].literalSpans,undefined);
});
test('v1 rejects nonzero lane rows and overlapping ownership windows',()=>{
 const id=fixture().id;
 const lanes=extra=>({format:'jtm-display-lanes-v1',...extra});
 assert.ok(model(fixture(),lanes({byRegion:{jp:[[id,0,0,4000,0]]}})).parts[0].literalSpans);
 assert.equal(model(fixture(),lanes({byRegion:{jp:[[id,0,0,0,2]]}})).parts[0].literalSpans,undefined);
 assert.equal(model(fixture(),lanes({byRegion:{jp:[[id,0,0,4000,2]]}})).parts[0].literalSpans,undefined);
 for(const role of [0,1]) {
  assert.equal(model(fixture(),lanes({familyWindowsByRegion:{jp:[[id,0,100,3500,role,'family']]}})).parts[0].literalSpans,undefined);
  assert.ok(model(fixture(),lanes({familyWindowsByRegion:{jp:[[id,0,0,50,role,'family']]}})).parts[0].literalSpans);
 }
});
test('a remote zero-lane branch does not veto the local footprint, while withholding and service splits do',()=>{
 const line=fixture();line.displayBranchLeadIns=[[points[0],[138.999,34.999]]];
 const branchModel=model(line);assert.ok(branchModel.parts[0].literalSpans);assert.equal(branchModel.parts[1].literalSpans,undefined);
 const blocked=Network.buildNetworkFromCompactPackage({format:'compact-v1',country:'jp',lines:[fixture()],geometrySource:{officialGeometryComparison:{byLine:{[line.id]:{displayBlockedIntervals:[0]}}}}});
 assert.equal(blocked.strokeModel.lines[0].parts[0].literalSpans,undefined);
 const suspended=fixture();suspended.serviceSpans=[[0,1,1]];
 const split=Network.buildNetworkFromCompactPackage({format:'compact-v1',country:'jp',lines:[suspended]});
 assert.equal(split.strokeModel,null);
});
