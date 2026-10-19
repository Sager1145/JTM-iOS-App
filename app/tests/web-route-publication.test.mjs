import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import {makeSandbox,evaluateAppScripts} from '../scripts/lib/app-family-sandbox.mjs';

function setup() {
  const c=makeSandbox();evaluateAppScripts(c);
  vm.runInContext(`importInProgress=true;activeCountry='jp';
    AppDatasets.installRailSections({type:'FeatureCollection',features:[{geometry:{type:'LineString',coordinates:[[139,35],[139.01,35]]}}]});
    AppDatasets.installStations({type:'FeatureCollection',features:[]});
    AppDatasets.installPhysicalRailJunctions({format:'jtm-physical-rail-junctions-v1',junctions:[]});
    matchedRoutesGeoJson={type:'FeatureCollection',features:[]};
    const train={id:'t',date:'2026-10-11',stops:[{name:'A',ride_segment:true},{name:'B',ride_segment:true}],route_sections:[{from:'A',to:'B'}]};
    const context=buildTrainRouteSolveContext(train);
    const legacy={type:'Feature',geometry:{type:'LineString',coordinates:[[139,35],[139.01,35]]},properties:{train_id:'t',route_id:'old-primary',segment_index:0,from:'A',to:'B',is_primary:true,geometry_role:'single_primary_segment',route_template_key:routeKeyDigest(getTrainRouteTemplateKey(train)),route_solver_version:'25'}};
  `,c);
  return c;
}

test('a current negative physical solve cannot redraw legacy train or template matches',()=>{
  const c=setup();vm.runInContext(`matchedRoutesGeoJson.features=[legacy];RouteService.seedNegative(context.cacheKey)`,c);
  assert.equal(vm.runInContext(`getMatchedRouteFeatures(train).length`,c),0);
});
test('an obsolete matched route without current solve provenance stays hidden during a cold solve',()=>{
  const c=setup();vm.runInContext(`matchedRoutesGeoJson.features=[legacy]`,c);
  assert.equal(vm.runInContext(`getMatchedRouteFeatures(train).length`,c),0);
});
test('fallback geometry from an actual current solve remains usable only for its applicable context',async()=>{
  const c=setup();
  c.__stations={type:'FeatureCollection',features:['A','B'].map((name,index)=>({type:'Feature',geometry:{type:'Point',coordinates:[139+index*.01,35]},properties:{station_name:name,n02_station_code:'00000'+(index+1),line_name:'L',operator:'Operator',railway_class_code:'12',institution_type_code:'4'}}))};
  c.__sections={type:'FeatureCollection',features:[{type:'Feature',geometry:{type:'LineString',coordinates:[[139,35],[139.01,35]]},properties:{line_name:'L',operator:'Operator',railway_class_code:'12',institution_type_code:'4'}}]};
  vm.runInContext(`AppDatasets.installRailSections(__sections);AppDatasets.installStations(__stations);`,c);
  await vm.runInContext(`buildStationIndexesSliced(__stations)`,c);
  await vm.runInContext(`RouteService.warmTrain(train)`,c);
  vm.runInContext(`runtimeRouteCache.clear()`,c);
  assert.equal(vm.runInContext(`getMatchedRouteFeatures(train).length`,c),1);
  assert.equal(vm.runInContext(`getMatchedRouteFeatures({...train,date:'2026-10-12'}).length`,c),0);
  vm.runInContext(`const priorRoutes=matchedRoutesGeoJson.features.slice();
    __stations.features[0].properties.valid_to='2026-10-01';
    railContentHashCache=null;
    RouteService.seed(context.cacheKey,priorRoutes);`,c);
  assert.equal(vm.runInContext(`RouteService.fallbackFeaturesForTrain(train,priorRoutes).length`,c),0,
    'a station retirement correction must reject previously applicable solved geometry');
  assert.equal(vm.runInContext(`prepareTrainRouteSolve(train).done`,c),false);
  assert.equal(vm.runInContext(`RouteService.has(context.cacheKey)`,c),false);
});
test('adjacent legs sharing one recorded station retain an unsurveyed endpoint gap',()=>{
  const c=setup();c.__features=[
    {type:'Feature',properties:{segment_index:0,to_n02_station_code:'000001',preserve_ordered_geometry:true},geometry:{type:'LineString',coordinates:[[139,35],[139.001,35]]}},
    {type:'Feature',properties:{segment_index:1,from_n02_station_code:'000001',preserve_ordered_geometry:true},geometry:{type:'LineString',coordinates:[[139.002,35],[139.003,35]]}},
  ];
  const before=JSON.stringify(c.__features);
  assert.equal(JSON.stringify(vm.runInContext(`dedupeSameTrainRouteFeatures(__features)`,c)),before);
});

test('offline precompute never promotes retained legacy geometry after a current negative physical solve',async()=>{
  const c=setup(),emitted=[];
  const train={id:'t',number:'Train',origin:'A',destination:'B',date:'2026-10-11',route_sections:[{from:'A',to:'B'}],stops:[{name:'A',stop_type:'origin',ride_segment:true,n02_station_code:null},{name:'B',stop_type:'destination',ride_segment:true,n02_station_code:null}]};
  c.__host={country:'jp',historyOverlays:{},physicalJunctions:{format:'jtm-physical-rail-junctions-v1',junctions:[]},railSections:{type:'FeatureCollection',features:[]},stations:{type:'FeatureCollection',features:[]},matchedStops:{type:'FeatureCollection',features:[]},matchedRoutes:{type:'FeatureCollection',features:[vm.runInContext(`legacy`,c)]},trainStoreText:JSON.stringify({schema_version:'1.3',trains:[train]}),onTrainSolved:record=>emitted.push(record)};
  await vm.runInContext(`PrecomputeAdapter.solveStore(__host)`,c);
  assert.equal(emitted.length,1);assert.equal(emitted[0].route.unsolvable,true);
  assert.equal(emitted[0].route.features,undefined);
});

test('same rail geometry with changed physical identity or service validity rotates the cache namespace',()=>{
  const base={operator:'Operator',line_name:'L',railway_class_code:'12',institution_type_code:'4',level:'0',track_id:'main'};
  function hash(properties) {
    const c=setup();
    c.__sections={type:'FeatureCollection',features:[{type:'Feature',geometry:{type:'LineString',coordinates:[[139,35],[139.01,35]]},properties}]};
    return vm.runInContext(`AppDatasets.installRailSections(__sections);getRailContentHash()`,c);
  }
  const initial=hash(base);
  for(const [key,value] of Object.entries({operator:'Other',line_name:'Other Line',railway_class_code:'11',institution_type_code:'3',level:'1',track_id:'other',valid_from:'2020-01-01',valid_to:'2025-01-01',service_validity:['2020-01-01','2025-01-01'],infrastructure_validity:['2020-01-01','2025-01-01']})) {
    assert.notEqual(hash({...base,[key]:value}),initial,`${key} changes an actual graph dependency`);
  }
});

test('raw current-version positive seeds cannot bypass source provenance on consumption',()=>{
  const c=setup();
  vm.runInContext(`const seeded={...legacy,properties:{...legacy.properties,route_solver_version:String(ROUTE_SOLVER_CACHE_VERSION),route_solve_digest:routeKeyDigest(context.cacheKey),rail_content_hash:'prior-source'}};RouteService.seed(context.cacheKey,[seeded]);`,c);
  assert.equal(vm.runInContext(`prepareTrainRouteSolve(train).done`,c),false);
  assert.equal(vm.runInContext(`RouteService.has(context.cacheKey)`,c),false);
});

test('station solver metadata corrections rotate the namespace while equivalent source spellings do not',()=>{
  const base={station_name:'A',n02_station_code:'000001',n02_group_code:'G',line_name:'L',operator:'Operator',institution_type_code:'4'};
  function hash(properties) {
    const c=setup();
    c.__stations={type:'FeatureCollection',features:[{type:'Feature',geometry:{type:'Point',coordinates:[139,35]},properties}]};
    return vm.runInContext(`AppDatasets.installStations(__stations);getRailContentHash()`,c);
  }
  const initial=hash(base);
  assert.equal(hash({...base,display_note:'not a solver input'}),initial);
  assert.equal(hash({N02_005:'A',N02_005c:'000001',N02_005g:'G',N02_003:'L',N02_004:'Operator',N02_002:'4'}),initial);
  for(const [key,value] of Object.entries({station_name:'Other',n02_station_code:'000002',n02_group_code:'Other',line_name:'Other Line',operator:'Other',institution_type_code:'3',valid_from:'2020-01-01',valid_to:'2025-01-01',service_validity:['2020-01-01','2025-01-01'],infrastructure_validity:['2020-01-01','2025-01-01']})) {
    assert.notEqual(hash({...base,[key]:value}),initial,`${key} changes a station solver dependency`);
  }
});

test('a positive seed waits for source readiness without drawing or losing its pending entry',()=>{
  const c=setup();
  vm.runInContext(`AppDatasets.installRailSections(null);RouteService.seed(context.cacheKey,[legacy]);`,c);
  assert.equal(vm.runInContext(`prepareTrainRouteSolve(train).done`,c),false);
  assert.equal(vm.runInContext(`RouteService.has(context.cacheKey)`,c),true);
});
