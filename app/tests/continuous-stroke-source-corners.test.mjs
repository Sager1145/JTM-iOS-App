import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';
const {buildStroke} = createRequire(import.meta.url)('../public/rail-stroke.js');
// Actual Yamada i12-v4 raw62..72, complete DISPLAY part1998..2008.
// N/S0 (local4/5) are the two source turns; S1/local6 releases the low tangent.
const coordinates = [[141.87926811665955,39.631810221068676],[141.8796380566901,39.63198257268963],[141.88064230029045,39.63241183090143],[141.88093197886406,39.632488262131695],[141.88220370592762,39.632742771241496],[141.88461769404103,39.63238333847553],[141.88483227076222,39.63238333847553],[141.8857792256776,39.63257844481797],[141.88669606726353,39.632906239404996],[141.88692721113597,39.63299365029543],[141.88723675482936,39.63310838250123]];
const project = c => [2**26*(c[0]+180)/360,2**25*(1-Math.asinh(Math.tan(c[1]*Math.PI/180))/Math.PI)];
const points = coordinates.map(project);
const measures=[0];
for(let i=1;i<points.length;i++) measures.push(measures.at(-1)+Math.hypot(points[i][0]-points[i-1][0],points[i][1]-points[i-1][1])*0.45923414993959905);
const span={edgeIndex:4,witnesses:points.slice(3,7)};
const options={measures,anchors:[0,10],rows:[],cornerRadiusPx:3.6,minCornerRadiusPx:3,enforceMinimumCornerRadius:true};
function departure(result,lo,hi) {
 const a=points[lo], b=points[hi],dx=b[0]-a[0],dy=b[1]-a[1],length=Math.hypot(dx,dy);
 return Math.max(0,...result.points.flatMap((p,i)=>result.measures[i]>=measures[lo]&&result.measures[i]<=measures[hi] ? [-((p[1]-a[1])*dx-(p[0]-a[0])*dy)/length]:[]));
}
test('actual reviewed Y4 two-corner intent removes body and shoulder bows without making Q a third hard corner',()=>{
 const ordinary=buildStroke(points,options);
 assert.ok(departure(ordinary,4,5)>10,'fixture exposes actual ordinary northbow');
 const literal=buildStroke(points,{...options,literalSpans:[span]});
 assert.ok(departure(literal,3,4)>15,'literal-v1 has a different unacceptable shoulder');
 const result=buildStroke(points,{...options,literalSpans:[{...span,mode:'source-corners-v1'}]});
 assert.ok(departure(result,4,5)<1e-6,'reviewed N to S0 must retain the source chord');
 assert.ok(departure(result,3,4)<1e-6,'incoming P to N must retain the source shoulder');
 assert.deepEqual(result.appliedSourceCornerEdges,[4]);
 assert.equal('appliedLiteralSpanEdges' in result,false);
 assert.deepEqual(result.anchors,ordinary.anchors);
 assert.deepEqual(result.anchorMeasures,ordinary.anchorMeasures);
 // Ordinary release at Q remains curved. Q must not be promoted to a third corner.
 const released=result.points.filter((_,i)=>result.measures[i]>measures[6]&&result.measures[i]<measures[7]);
 assert.ok(released.length>2);
 const q=points[6],r=points[7];
 assert.ok(released.some(p=>Math.abs((p[0]-q[0])*(r[1]-q[1])-(p[1]-q[1])*(r[0]-q[0]))>1),
   "Q release retains ordinary noncollinear curvature rather than a forced hard chord");
});

test('invalid or conflicting source intent cannot change ordinary final geometry',()=>{
 const hint={...span,mode:'source-corners-v1'};
 for(const hints of [[{...hint,mode:'future'}],[{...hint,witnesses:points.slice(2,6)}],[hint,hint],[hint,span]])
   assert.deepEqual(buildStroke(points,{...options,literalSpans:hints}),buildStroke(points,options));
 for(const extra of [
   {anchors:[0,3,10]}, {shapeBoundaryMeasures:[measures[6]]},
   {curveCentreline:false}, {cornerRadiusPx:0},
   {rows:[{from:0,to:measures.at(-1),lane:1}],laneGapPx:0},
   {joinStart:{lane:1}}, {joinEnd:{targetLane:1}},
   {follows:[{points,measures,from:0,to:measures.at(-1),canonFrom:0,canonTo:measures.at(-1)}]},
 ]) assert.deepEqual(buildStroke(points,{...options,...extra,literalSpans:[hint]}),buildStroke(points,{...options,...extra}));
 const repeated=structuredClone(points);repeated[2]=repeated[3].slice();
 const altered={...hint,witnesses:repeated.slice(3,7)};
 assert.deepEqual(buildStroke(repeated,{...options,literalSpans:[altered]}),buildStroke(repeated,options));
});

test('real corners already above the generic threshold are admissible without hardening P/Q or making anchors',()=>{
 const p=[[0,0],[100,0],[200,5],[300,10],[300,110],[400,115],[500,125],[600,140]];
 const m=[0,100,200,300,400,500,600,700];
 const opts={measures:m,anchors:[0,7],cornerRadiusPx:3.6};
 const out=buildStroke(p,{...opts,literalSpans:[{edgeIndex:3,witnesses:p.slice(2,6),mode:'source-corners-v1'}]});
 assert.deepEqual(out.appliedSourceCornerEdges,[3]);
 assert.deepEqual(out.anchors,[p[0],p[7]]);
 for(const i of [3,4]) assert.deepEqual(out.points[out.measures.indexOf(m[i])],p[i]);
 assert.ok(out.points.some((point,i)=>out.measures[i]>500&&out.measures[i]<600),'Q retains ordinary curved release');
});
