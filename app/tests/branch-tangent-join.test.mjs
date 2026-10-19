import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';

const Stroke = createRequire(import.meta.url)('../public/rail-stroke.js');

test('branch tangent inheritance is independent of digitisation direction', () => {
  const main = [[-200, 0], [0, 0], [200, 0]];
  const departure = [[0, 0], [100, 10], [200, 30]];
  for (const branch of [departure, departure.map(([x,y]) => [-x,y])]) {
    for (const atEnd of [false, true]) {
      const points = atEnd ? [...branch].reverse() : branch;
      const forward = Stroke.tangentJoin(points, main, atEnd, 0);
      const reversed = Stroke.tangentJoin(points, [...main].reverse(), atEnd, 0);
      assert.ok(forward && reversed, 'both survey orientations must inherit the same tangent');
      assert.deepEqual(forward.mainTangent, reversed.mainTangent);
      const delta = atEnd
        ? [points.at(-1)[0] - points.at(-2)[0], points.at(-1)[1] - points.at(-2)[1]]
        : [points[1][0] - points[0][0], points[1][1] - points[0][1]];
      assert.ok(delta[0] * forward.mainTangent[0] + delta[1] * forward.mainTangent[1] > 0);
    }
  }
});

test('tangent inheritance still requires an exact interior vertex and a shallow departure', () => {
  const main = [[-200,0],[0,0],[200,0]];
  assert.equal(Stroke.tangentJoin([[0,0],[100,100]], main, false, 0), null);
  assert.equal(Stroke.tangentJoin([[0,0.001],[100,10]], main, false, 0), null);
  assert.equal(Stroke.tangentJoin([[200,0],[300,10]], main, false, 0), null);
});

test('a confirmed endpoint junction opts in and meets its physical zero-lane switch', () => {
  const departure = [[0,0],[100,10],[200,30]];
  const main = [[-200,0],[0,0]];
  for (const atEnd of [false,true]) for (const reverseMain of [false,true]) {
    const points = atEnd ? [...departure].reverse() : departure;
    const chain = reverseMain ? [...main].reverse() : main;
    assert.equal(Stroke.tangentJoin(points,chain,atEnd,2,0),null,'coincidence alone must not enable endpoint inheritance');
    const join = Stroke.tangentJoin(points,chain,atEnd,2,0,true);
    assert.ok(join,'a confirmed shallow endpoint junction must inherit its tangent');
    assert.equal(join.mainChain,chain,'retain the source track for bounded blending');
    const stroke = Stroke.buildStroke(points,{measures:[0,200,400],rows:[{from:0,to:400,lane:2}],
      totalMetres:400,laneGapPx:10,minRampPx:24,cornerRadiusPx:3.6,
      [atEnd ? 'joinEnd' : 'joinStart']:join});
    const endpoint = atEnd ? stroke.points.at(-1) : stroke.points[0];
    assert.ok(Math.hypot(...endpoint)<1e-9,'all junction ink must land at the physical switch');
  }
  assert.equal(Stroke.tangentJoin([[0,0],[100,100]],main,false,0,0,true),null);
  assert.equal(Stroke.tangentJoin([[0,0.001],[100,10]],main,false,0,0,true),null);
});

test('branch endpoint inherits the drawn main lane in its own travel direction', () => {
  const main = [[-200,0],[0,0],[200,0]], branch = [[0,0],[100,10],[200,30]];
  const ownLane = -1;
  for (const reversed of [false,true]) {
    const chain = reversed ? [...main].reverse() : main;
    const join = Stroke.tangentJoin(branch, chain, false, ownLane, reversed ? -2 : 2);
    const stroke = Stroke.buildStroke(branch, {measures:[0,200,400], rows:[{from:0,to:400,lane:ownLane}],
      totalMetres:400, laneGapPx:10, cornerRadiusPx:0, joinStart:join});
    assert.ok(Math.abs(stroke.points[0][1]-20)<1e-10, 'endpoint must reach main ink, rather than average unrelated own/main lanes');
  }
});

test('branch endpoint target survives a nearby lane change and the pixel ramp floor', () => {
  for (const pixelScale of [1,0.02]) for (const atEnd of [false,true]) {
    const points = [[0,0],[100*pixelScale,0],[1000*pixelScale,0]];
    const endpoint = atEnd ? points.at(-1) : points[0];
    const main = [[endpoint[0]-2000,0],endpoint,[endpoint[0]+2000,0]];
    const rows = atEnd ? [{from:900,to:1000,lane:-1}] : [{from:0,to:100,lane:-1}];
    const join = Stroke.tangentJoin(points,main,atEnd,-1,2);
    const stroke = Stroke.buildStroke(points,{measures:[0,100,1000],rows,totalMetres:1000,
      laneGapPx:10,minRampPx:24,cornerRadiusPx:0,[atEnd ? 'joinEnd' : 'joinStart']:join});
    assert.ok(Math.abs((atEnd ? stroke.points.at(-1) : stroke.points[0])[1]-20)<1e-9);
  }
});

test('both branch targets survive overlapping ramps and a coalesced short plateau', () => {
  for (const total of [40,100]) {
    const points = [[0,0],[total/2,0],[total,0]];
    const joinStart = Stroke.tangentJoin(points,[[-100,0],[0,0],[100,0]],false,0,2);
    const joinEnd = Stroke.tangentJoin(points,[[total-100,0],[total,0],[total+100,0]],true,0,-1);
    const stroke = Stroke.buildStroke(points,{measures:[0,total/2,total],rows:[],totalMetres:total,
      laneGapPx:10,cornerRadiusPx:0,joinStart,joinEnd});
    assert.ok(Math.abs(stroke.points[0][1]-20)<1e-9);
    assert.ok(Math.abs(stroke.points.at(-1)[1]+10)<1e-9);
  }
});

test('web production rebuild joins independent branch parts to the main ink', () => {
  for (const reverse of [false,true]) {
    const context = vm.createContext({console, URL, location:{href:'https://example.test/'},
      RailMapBasemap:{}, RailNetwork:{DEFAULT_LINE_COLOR:'#123456'}, RailMapGeometry:{}, RailStroke:Stroke});
    context.window = context;
    for (const filename of ['railmap-style.js','railmap.js'])
      vm.runInContext(fs.readFileSync(new URL(`../public/${filename}`,import.meta.url),'utf8'),context);
    const main = [[138.995,35],[139,35],[139.005,35]];
    const branch = [[139,35],[139.001,35.0001],[139.002,35.0003]];
    const part = (coordinates,lane) => ({coordinates,measures:[0,500,1000],totalMetres:1000,
      rows:[{from:0,to:1000,lane}],anchors:[0,2],follows:[],tenantWindows:[],familyWindows:[],bbox:[138,34,140,36]});
    const branchPart = part(branch,-1), mainPart = part(reverse ? [...main].reverse() : main,reverse ? -2 : 2);
    context.RailMap._network = {
      lineById:new Map(['jp-branch','jp-main'].map(id => [id,{country:'jp',operator:'test'}])),
      strokeModel:{lines:[{lineId:'jp-branch',featureIndex:0,parts:[branchPart]},
        {lineId:'jp-main',featureIndex:1,parts:[mainPart]}],stations:[]},
      segments:{features:[{geometry:{}},{geometry:{}}]},stations:{features:[]},
    };
    context.RailMap._map = {getZoom:()=>17,getBounds:()=>({getWest:()=>138,getEast:()=>140,getSouth:()=>34,getNorth:()=>36})};
    context.RailMap._applyContinuousStrokes(true);
    const endpoint = branchPart.strokePx.points[0];
    const y = mainPart.strokePx.points[0][1];
    assert.ok(Math.abs(endpoint[1]-y)<1e-6,'branch endpoint must land on the offset main stroke');
    assert.ok(endpoint[0]>Math.min(...mainPart.strokePx.points.map(point=>point[0])) &&
      endpoint[0]<Math.max(...mainPart.strokePx.points.map(point=>point[0])));
  }
});

 test('web branch inherits the main ramp affected by a reviewed adjacent part', () => {
  const context = vm.createContext({console, URL, location:{href:'https://example.test/'},
    RailMapBasemap:{}, RailNetwork:{DEFAULT_LINE_COLOR:'#123456'}, RailMapGeometry:{}, RailStroke:Stroke});
  context.window = context;
  for (const filename of ['railmap-style.js','railmap.js'])
    vm.runInContext(fs.readFileSync(new URL(`../public/${filename}`,import.meta.url),'utf8'),context);
  const make = (coordinates, measures, lane) => ({coordinates,measures,totalMetres:measures.at(-1),
    rows:[{from:0,to:measures.at(-1),lane}],anchors:coordinates.map((_,i)=>i),follows:[],
    tenantWindows:[],familyWindows:[],bbox:[138,34,140,36]});
  const before = make([[138.98,35],[138.99,35]],[0,1000],-2);
  const main = make([[138.99,35],[139,35],[139.01,35]],[0,100,1000],2);
  const branch = make([[139,35],[139.001,35.0001],[139.002,35.0003]],[0,100,400],-1);
  context.RailMap._network = {
    lineById:new Map(['jp-branch','jp-main'].map(id=>[id,{country:'jp',operator:'test'}])),
    strokeModel:{lines:[{lineId:'jp-branch',featureIndex:0,parts:[branch]},
      {lineId:'jp-main',featureIndex:1,parts:[before,main]}],stations:[]},
    segments:{features:[{geometry:{}},{geometry:{}}]},stations:{features:[]},
  };
  context.RailMap._map = {getZoom:()=>17,getBounds:()=>({getWest:()=>138,getEast:()=>140,getSouth:()=>34,getNorth:()=>36})};
  context.RailMap._applyContinuousStrokes(true);
  const endpoint = branch.strokePx.points[0];
  const vertex = main.strokePx.points.reduce((a,b)=>Math.abs(a[0]-endpoint[0])<Math.abs(b[0]-endpoint[0])?a:b);
  assert.ok(Math.abs(endpoint[1]-vertex[1])<1e-6, 'inherit the drawn main profile including its adjacent boundary ramp');
});

test('production three-way physical forks meet at one switch without a sharp main mitre', () => {
 const context=vm.createContext({console,URL,location:{href:'https://example.test/'},RailMapBasemap:{},RailNetwork:{DEFAULT_LINE_COLOR:'#123456'},RailMapGeometry:{},RailStroke:Stroke});context.window=context;
 for(const name of ['railmap-style.js','railmap.js'])vm.runInContext(fs.readFileSync(new URL(`../public/${name}`,import.meta.url),'utf8'),context);
 const make=(coordinates,lane)=>({coordinates,measures:[0,100,400],totalMetres:400,rows:[{from:0,to:400,lane}],anchors:[0,2],follows:[],tenantWindows:[],familyWindows:[],bbox:[138,34,140,36],joinPrevious:false});
 const parts=[make([[139,35],[139.001,35.0001],[139.004,35.0003]],1),
   make([[139.004,34.9997],[139.001,34.9999],[139,35]],-2),
   make([[139,35],[139.001,34.9998],[139.004,34.9992]],-1)];
 context.RailMap._network={lineById:new Map([['jp-fork',{country:'jp',operator:'test'}]]),strokeModel:{lines:[{lineId:'jp-fork',featureIndex:0,parts}],stations:[]},segments:{features:[{geometry:{}}]},stations:{features:[]}};
 context.RailMap._map={getZoom:()=>17,getBounds:()=>({getWest:()=>138,getEast:()=>140,getSouth:()=>34,getNorth:()=>36})};
 context.RailMap._applyContinuousStrokes(true);
 const vertices=[parts[0].strokePx.points[0],parts[1].strokePx.points.at(-1),parts[2].strokePx.points[0]];
 for(const vertex of vertices.slice(1))assert.ok(Math.hypot(vertex[0]-vertices[0][0],vertex[1]-vertices[0][1])<1e-6,'all three offset parts meet at the surveyed switch');
});
