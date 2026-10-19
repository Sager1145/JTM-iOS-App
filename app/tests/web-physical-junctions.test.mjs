import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import {makeSandbox,evaluateAppScripts} from '../scripts/lib/app-family-sandbox.mjs';

const identity=(line)=>({operatorName:'Operator',lineName:line,railwayClassCode:'12'});
const section=(line,points)=>({type:'Feature',geometry:{type:'LineString',coordinates:points},properties:{operator:'Operator',line_name:line,railway_class_code:'12',institution_type_code:'4'}});
function graph(sections,junctions=[],stations=[]) {
  const c=makeSandbox();evaluateAppScripts(c);c.__sections=sections;c.__junctions=junctions;c.__stations=stations;
  vm.runInContext(`const graph=buildRouteGraphFromFeatures(__sections,__junctions);`,c);
  return vm.runInContext(`graph`,c);
}
function pathExists(g,fromLine,toLine){
  const source=[...g.nodeMeta].find(([,m])=>m.line_names.has(fromLine))[0];
  const visited=new Set([source]),queue=[source];
  for(const key of queue){if(g.nodeMeta.get(key).line_names.has(toLine))return true;for(const edge of g.adjacency.get(key)||[])if(!visited.has(edge.to)){visited.add(edge.to);queue.push(edge.to)}}
  return false;
}
const station=(line,point)=>({geometry:{type:'Point',coordinates:point},properties:{station_name:'Shared',n02_station_code:line,n02_group_code:'passenger-group',operator:'Operator',line_name:line,railway_class_code:'12',institution_type_code:'4'}});
const reviewed=(from,to,kind='zeroLength')=>({id:'reviewed-link',region:'jp',kind,from:{identity:identity('A'),coordinate:from},to:{identity:identity('B'),coordinate:to},evidence:['https://operator.example/physical-junction'],validFrom:'2020-01-01',validTo:null});

test('coincident surveyed coordinates of different identities do not authorize a rail connection',()=>{
  const g=graph([section('A',[[139,35],[139.001,35]]),section('B',[[139.001,35],[139.002,35]])]);
  assert.equal(pathExists(g,'A','B'),false);
});
test('equal passenger station groups and nearby nodes do not authorize a rail connection',()=>{
  const g=graph([section('A',[[139,35],[139.001,35]]),section('B',[[139,35.0001],[139.001,35.0001]])],[],[station('A',[139,35]),station('B',[139,35.0001])]);
  assert.equal(pathExists(g,'A','B'),false);
});
test('a reviewed zero-length junction connects its exact surveyed identities and retains its validity',()=>{
  const point=[139.001,35];const g=graph([section('A',[[139,35],point]),section('B',[point,[139.002,35]])],[reviewed(point,point)]);
  assert.equal(pathExists(g,'A','B'),true);
  const edges=[...g.adjacency.values()].flat().filter(e=>e.physical_junction_id==='reviewed-link');
  assert.equal(edges.length,2);assert.equal(edges[0].valid_from,'2020-01-01');
});
test('a reviewed short link cannot attach to an unsurveyed endpoint',()=>{
  const g=graph([section('A',[[139,35],[139.001,35]]),section('B',[[139.001,35.0001],[139.002,35.0001]])],[reviewed([139.00101,35],[139.001,35.0001],'shortLink')]);
  assert.equal(pathExists(g,'A','B'),false);
});

test('a reviewed OSM connector follows its surveyed path between exact endpoints',()=>{
  const from=[139.001,35],to=[139.002,35];
  const link={...reviewed(from,to,'osmConnector'),path:[from,[139.0015,35.0001],to],
    source:{provider:'OpenStreetMap',license:'ODbL-1.0',ways:[1],retrieved:'2026-08-18',cache:'retained-survey'}};
  const g=graph([section('A',[[139,35],from]),section('B',[to,[139.003,35]])],[link]);
  assert.equal(pathExists(g,'A','B'),true);
  assert.ok([...g.nodes.values()].some(point=>point[0]===139.0015&&point[1]===35.0001));
  const tooFar={...link,path:[[139,35.01],to]};
  assert.equal(pathExists(graph([section('A',[[139,35],from]),section('B',[to,[139.003,35]])],[tooFar]),'A','B'),false);
});

test('a reviewed OSM track to a terminus keeps its last platform on its own track identity',()=>{
  const from=[139.001,35],to=[139.002,35];
  const track={...reviewed(from,to,'osmTrack'),to:{identity:identity('A'),coordinate:to},
    path:[from,to],terminus:{end:'to',station:'Terminus',stationCode:'A-terminal',coordinate:to},
    source:{provider:'OpenStreetMap',license:'ODbL-1.0',ways:[1],retrieved:'2026-08-18',cache:'retained-survey'}};
  const g=graph([section('A',[[139,35],from])],[track]);
  const terminal=[...g.nodes].find(([,point])=>point[0]===139.002)[0];
  assert.ok(g.nodeMeta.get(terminal).line_names.has('A'));
  assert.ok(g.adjacency.get(terminal).some(edge=>edge.line_name==='A'&&!edge.is_station_connector));
});

test('a reviewed junction preserves an explicitly evidenced historical identity copy at its surveyed vertex',()=>{
  const c=makeSandbox();evaluateAppScripts(c);const point=[139.001,35];
  c.__sections=[section('Old A',[[139,35],point]),section('B',[point,[139.002,35]])];
  c.__sections[0].properties.valid_to='2020-01-01';
  c.__junctions=[{...reviewed(point,point),validFrom:null}];
  c.__history={schema_version:'1',revision:'identity-copy',sections:[],stations:[],retirements:[],identity_periods:[{
    history_id:'a-before-2020',match:{line_name:'A',operator:'Operator',bbox:[138,34,140,36],targets:['sections']},
    source:'https://operator.example/rename',valid_to:'2020-01-01',as:{N02_003:'Old A',N02_004:'Operator',N02_001:'12'},
  }]};
  vm.runInContext(`loadRailHistoryOverlay(__history,'jp');const g=buildRouteGraphFromFeatures(__sections,__junctions);`,c);
  const g=vm.runInContext(`g`,c);assert.equal(pathExists(g,'Old A','B'),true);
  const edges=[...g.adjacency.values()].flat().filter(e=>e.physical_junction_id);
  assert.equal(edges.length,2);assert.equal(edges[0].valid_to,'2020-01-01');
});

test('a reviewed historical identity endpoint follows its official successor without extending an expired junction',()=>{
  const c=makeSandbox();evaluateAppScripts(c);const point=[139.001,35];
  c.__sections=[section('A',[[139,35],point]),section('B',[point,[139.002,35]])];
  c.__sections[0].properties.valid_from='2020-01-01';
  c.__junctions=[{...reviewed(point,point),from:{identity:identity('Old A'),coordinate:point},validFrom:null}];
  c.__history={schema_version:'1',revision:'identity-successor',sections:[],stations:[],retirements:[],identity_periods:[{
    history_id:'a-before-2020',match:{line_name:'A',operator:'Operator',bbox:[138,34,140,36],targets:['sections']},
    source:'https://operator.example/rename',valid_to:'2020-01-01',as:{N02_003:'Old A',N02_004:'Operator',N02_001:'12'},
  }]};
  vm.runInContext(`loadRailHistoryOverlay(__history,'jp');const g=buildRouteGraphFromFeatures(__sections,__junctions);`,c);
  assert.equal(pathExists(vm.runInContext(`g`,c),'A','B'),true);
  c.__junctions[0].validTo='2020-01-01';
  assert.equal(pathExists(vm.runInContext(`buildRouteGraphFromFeatures(__sections,__junctions)`,c),'A','B'),false);
});

const sourceSection=(line,points,ids)=>({...section(line,points),properties:{...section(line,points).properties,source_node_ids:[ids]}});
test('original source node IDs keep co-located nodes of one identity disconnected',()=>{
  const g=graph([sourceSection('A',[[139,35],[139.001,35]],['west','crossing-west']),
    sourceSection('A',[[139.001001,35],[139.002,35]],['crossing-east','east'])]);
  assert.equal(g.nodes.size,4);
  const west=[...g.nodes.keys()].find(key=>key.endsWith('@source-node:crossing-west'));
  const east=[...g.nodes.keys()].find(key=>key.endsWith('@source-node:crossing-east'));
  assert.notEqual(west,east);
  assert.equal(g.adjacency.get(west).some(edge=>edge.to===east),false);
  assert.equal(g.resolvePhysicalNode([139.001,35],identity('A')),null);
  assert.equal(g.ensurePhysicalNode([139.001,35],identity('A')),null);
});
test('a shared original source node joins sections only within the same track identity',()=>{
  const g=graph([sourceSection('A',[[139,35],[139.001,35]],['west','shared']),
    sourceSection('A',[[139.001,35],[139.002,35]],['shared','east']),
    sourceSection('B',[[139.001,35],[139.001,35.001]],['shared','other'])]);
  assert.equal(g.nodes.size,5);
  const shared=[...g.nodes.keys()].find(key=>key.endsWith('@source-node:shared')&&g.nodeMeta.get(key).line_names.has('A'));
  assert.equal(g.adjacency.get(shared).length,2);
  assert.equal(pathExists(g,'A','B'),false);
});
test('explicit malformed source node ID tables cannot fall back to coordinate welding',()=>{
  for(const ids of [null,[],[['only-one']],[[null,'b']],[[1,'b']],[['','b']],['not-a-line'],[['a','b'],['extra']]]){
    const feature=section('A',[[139,35],[139.001,35]]);feature.properties.source_node_ids=ids;
    assert.throws(()=>graph([feature]),/source_node_ids/);
  }
});
test('reviewed coordinate junctions resolve unique source nodes and reject ambiguous ones',()=>{
  const p=[139.001,35];
  const sections=[sourceSection('A',[[139,35],p],['a','shared-a']),sourceSection('B',[p,[139.002,35]],['shared-b','b'])];
  assert.equal(pathExists(graph(sections,[reviewed(p,p)]),'A','B'),true);
  sections.push(sourceSection('A',[p,[139.001,35.001]],['different-a','c']));
  assert.equal(pathExists(graph(sections,[reviewed(p,p)]),'A','B'),false);
});
test('source node topology is preserved by full and regional browser graphs',()=>{
  const c=makeSandbox();evaluateAppScripts(c);
  c.__sections=[sourceSection('A',[[139,35],[139.001,35]],['a','x']),sourceSection('A',[[139.001,35],[139.002,35]],['y','b'])];
  vm.runInContext('railSectionsGeoJson={type:"FeatureCollection",features:__sections};invalidateRouteGraphIndexes();',c);
  const full=vm.runInContext('getRuntimeRouteGraph()',c);
  const regional=vm.runInContext('getRegionalRouteGraph([138.9,34.9,139.1,35.1])',c);
  assert.deepEqual([...regional.nodes.keys()].sort(),[...full.nodes.keys()].sort());
  assert.equal(full.nodes.size,4);
});

function anchoredStationContext() {
  const c=makeSandbox();evaluateAppScripts(c);
  c.__sections=[
    {...sourceSection('Rail',[[139,35],[139.001,35]],['osm-node-6682022862','osm-node-2']),properties:{...section('Rail',[]).properties,track_id:'rail',source_node_ids:[['osm-node-6682022862','osm-node-2']]}},
    {...sourceSection('Metro',[[139,35.0001],[139.001,35.0001]],['osm-node-6682022862','osm-node-4']),properties:{...section('Metro',[]).properties,track_id:'metro',source_node_ids:[['osm-node-6682022862','osm-node-4']]}},
  ];
  c.__station={...station('Rail',[139,35.0001]),properties:{...station('Rail',[139,35.0001]).properties,line_id:'rail',source_anchor_node_id:6682022862}};
  vm.runInContext('const graph=buildRouteGraphFromFeatures(__sections,[]);',c);
  return c;
}

test('a recorded station anchor selects only its surveyed node and track beside a disconnected metro shortcut',()=>{
  const c=anchoredStationContext();
  const candidates=vm.runInContext('getStationCandidateGraphNodes(__station,graph)',c);
  assert.equal(candidates.length,1);
  assert.equal(candidates[0].key,'["Operator","Rail","12","","rail"]@source-node:osm-node-6682022862');
  assert.equal(pathExists(vm.runInContext('graph',c),'Rail','Metro'),false);
});

test('missing or invalid recorded anchors do not fall back to nearby rail or a cached anchor',()=>{
  const c=anchoredStationContext();
  assert.equal(vm.runInContext('getStationCandidateGraphNodes(__station,graph).length',c),1);
  for(const value of [999,null,'',false]) {
    c.__station.properties.source_anchor_node_id=value;
    assert.equal(vm.runInContext('getStationCandidateGraphNodes(__station,graph).length',c),0);
  }
  c.__station.properties.source_anchor_node_id=6682022862;
  delete c.__station.properties.line_id;
  assert.equal(vm.runInContext('getStationCandidateGraphNodes(__station,graph).length',c),0);
});

test('station records without recorded anchors retain legacy nearby candidates',()=>{
  const c=anchoredStationContext();delete c.__station.properties.source_anchor_node_id;
  const candidates=vm.runInContext('getStationCandidateGraphNodes(__station,graph)',c);
  assert.ok(candidates.some(candidate=>vm.runInContext('graph',c).nodeMeta.get(candidate.key).line_names.has('Metro')));
});

test('coded recorded anchors expand only through their code or explicit station group',async()=>{
  const c=anchoredStationContext();
  const official=c.__station;
  official.properties.n02_station_code='CN-12306-KMM';official.properties.n02_group_code='official-group';
  const sibling=structuredClone(official);sibling.properties.n02_station_code='sibling-code';sibling.properties.line_name='Branch';
  const metro=structuredClone(official);metro.properties.n02_station_code='metro-code';metro.properties.n02_group_code='metro-group';metro.properties.line_name='Metro';
  c.__stations={type:'FeatureCollection',features:[official,sibling,metro]};
  await vm.runInContext('buildStationIndexesSliced(__stations)',c);
  const candidates=vm.runInContext('resolveRouteEndpointStationCandidates({name:"Shared",n02_station_code:"CN-12306-KMM"},{},["4"],[])',c);
  assert.deepEqual(Array.from(candidates,feature=>feature.properties.n02_station_code),['CN-12306-KMM','sibling-code']);
});

test('only CN route cache contexts gain the source anchor and display identity policy revisions',()=>{
  const c=makeSandbox();evaluateAppScripts(c);
  c.__train={region:'cn',stops:[{name:'Start'},{name:'End'}],route_sections:[{from:'Start',to:'End'}]};
  for(const country of ['cn','CN']) {
    c.__train.region=country;
    const cn=vm.runInContext('buildTrainRouteSolveContext(__train).cacheKey',c);
    assert.ok(cn.endsWith('|source-anchor:1'));
    assert.ok(cn.endsWith('|source-display-identity:1|source-anchor:1'));
    const previousKey=cn.replace('|source-display-identity:1','');
    assert.notEqual(cn,previousKey,'a pre-display-identity CN route cache must miss');
  }
  for(const country of ['jp','tw','kr','hk','mo']) {
    c.__train.region=country;
    const key=vm.runInContext('buildTrainRouteSolveContext(__train).cacheKey',c);
    assert.equal(key.includes('|source-anchor:'),false);
    assert.equal(key.includes('|source-display-identity:'),false);
  }
});

test('a non-preferred anchored official code cannot gain a preferred metro namesake through fallback',async()=>{
  const c=anchoredStationContext();
  const official=c.__station;
  official.properties.n02_station_code='CN-12306-KMM';
  official.properties.n02_group_code='official-group';
  official.properties.institution_type_code='2';
  const metro=structuredClone(official);
  metro.properties.n02_station_code='metro-code';
  metro.properties.n02_group_code='metro-group';
  metro.properties.line_name='Metro';
  metro.properties.institution_type_code='3';
  c.__stations={type:'FeatureCollection',features:[official,metro]};
  await vm.runInContext('buildStationIndexesSliced(__stations)',c);
  const candidates=vm.runInContext('resolveRouteEndpointStationCandidates({name:"Shared",n02_station_code:"CN-12306-KMM"},{},["3"],[])',c);
  assert.deepEqual(Array.from(candidates,feature=>feature.properties.n02_station_code),['CN-12306-KMM']);
});
