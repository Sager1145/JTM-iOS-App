import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import {makeSandbox,evaluateAppScripts} from '../scripts/lib/app-family-sandbox.mjs';

function setup() {
  const context=makeSandbox();evaluateAppScripts(context);
  vm.runInContext(`AppDatasets.installPhysicalRailJunctions({format:"jtm-physical-rail-junctions-v1",junctions:[]});`,context);
  vm.runInContext(`activeCountry='jp';map=null;trainStore={schema_version:'1.3',trains:[{id:'jp-old'}]};
    flushPersistence=async()=>{};loadActiveCountryStationReadings=async()=>{};
    renderAll=()=>{};RailMap.switchNetworkCountry=async()=>null;`,context);
  return context;
}

test('a failed incoming country fetch cannot leave outgoing trains writable in its namespace',async()=>{
  const context=setup();
  vm.runInContext(`reloadSolverDatasetsForCountrySwitch=async()=>{throw new Error('station HTTP 503')};`,context);
  await assert.rejects(vm.runInContext(`CountrySession.switchTo('tw')`,context),/station HTTP 503/);
  const state=JSON.parse(vm.runInContext(`JSON.stringify({country:activeCountry,trains:trainStore.trains,recovery:storeRecoveryMode,busy:countrySwitchInFlight})`,context));
  assert.equal(state.busy,false);
  assert.ok(state.country==='jp'||(state.trains.length===0&&state.recovery),'Outgoing trains must stay in JP or the incoming workspace must be empty and protected');
});

test('a streaming solve suspended across a country reset publishes no cache, persistence or matched geometry',async()=>{
  const context=setup();
  vm.runInContext(`matchedRoutesGeoJson={type:'FeatureCollection',features:[]};
    let resume;const pause=new Promise(resolve=>resume=resolve);let persistenceCalls=0;
    setRouteCacheStore({solved:()=>persistenceCalls++,unsolvable:()=>persistenceCalls++});
    prepareTrainRouteSolve=()=>({done:false,routeSections:[{},{}],templateKey:'jp-template',allowedCodes:[],cacheKey:'jp-key'});
    solveTrainRouteSection=(t,s,i,a,features)=>features.push({type:'Feature',geometry:{type:'LineString',coordinates:[[139+i*.01,35],[139+(i+1)*.01,35]]},properties:{segment_index:i}});
    reloadSolverDatasetsForCountrySwitch=async()=>{};loadActiveCountryStore=async()=>{};
    const solve=solveTrainRouteStreaming({id:'jp-old'},{yieldIfNeeded:()=>pause});`,context);
  await vm.runInContext(`CountrySession.switchTo('tw')`,context);
  vm.runInContext(`resume()`,context);await vm.runInContext(`solve`,context);
  assert.equal(vm.runInContext(`runtimeRouteCache.size`,context),0);
  assert.equal(vm.runInContext(`runtimeRouteNegativeCache.size`,context),0);
  assert.equal(vm.runInContext(`matchedRoutesGeoJson.features.length`,context),0);
  assert.equal(vm.runInContext(`persistenceCalls`,context),0);
});

test('a delayed readiness callback does not solve the outgoing train on the replacement dataset',async()=>{
  const context=setup();
  vm.runInContext(`let ready;ensureSolverReady=()=>new Promise(resolve=>ready=resolve);let sectionsSolved=0;
    prepareTrainRouteSolve=()=>({done:false,routeSections:[{}],templateKey:'jp-template',allowedCodes:[],cacheKey:'jp-key'});
    solveTrainRouteSection=()=>sectionsSolved++;
    const solve=RouteService.warmTrain({id:'jp-old'});RouteService.resetForCountry();activeCountry='tw';ready();`,context);
  await vm.runInContext(`solve`,context);
  assert.equal(vm.runInContext(`sectionsSolved`,context),0);
});

function deferred(){let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve}}
const stationCollection=(country,code)=>JSON.stringify({type:'FeatureCollection',features:[{type:'Feature',geometry:{type:'Point',coordinates:[139,35]},properties:{station_name:country,n02_station_code:code,country}}]});

test('a station download surviving a failed switch cannot overwrite the next successful country',async()=>{
  const c=setup(),held=deferred();
  c.fetch=url=>{const resource=String(url).split('/').at(-1).replace(/\.json$/, '');return Promise.resolve({ok:true,text:()=>resource==='stations-tw'?held.promise:Promise.resolve(resource==='stations'?stationCollection('jp','000001'):'{"type":"FeatureCollection","features":[]}')})};
  c.RailMap.switchNetworkCountry=country=>country==='tw'?Promise.reject(new Error('network preparation failed')):Promise.resolve(null);
  vm.runInContext(`loadActiveCountryRailHistory=async()=>{};loadActiveCountryStore=async()=>{};
    const actualReload=reloadSolverDatasetsForCountrySwitch;let outgoingReload;
    reloadSolverDatasetsForCountrySwitch=(...args)=>{const promise=actualReload(...args);if(activeCountry==='tw')outgoingReload=promise;return promise};`,c);
  await assert.rejects(vm.runInContext(`CountrySession.switchTo('tw')`,c),/network preparation failed/);
  await vm.runInContext(`CountrySession.switchTo('jp')`,c);
  held.resolve(stationCollection('tw','TW-old'));
  await vm.runInContext(`outgoingReload`,c);
  assert.equal(vm.runInContext(`stationsGeoJson.features[0].properties.country`,c),'jp');
  assert.equal(vm.runInContext(`stationNameByCode.get('000001')`,c),'jp');
  assert.equal(vm.runInContext(`stationNameByCode.has('TW-old')`,c),false);
});

test('an obsolete sliced station-index build cannot publish over the replacement indexes',async()=>{
  const c=setup(),held=deferred();let current=true,ticks=0;
  c.performance={now:()=>ticks+=20};c.yieldToEventLoop=()=>held.promise;c.__isCurrent=()=>current;
  c.__outgoing={features:Array.from({length:1024},(_,index)=>({properties:{station_name:'outgoing',n02_station_code:'TW-'+index}}))};
  const old=vm.runInContext(`buildStationIndexesSliced(__outgoing,{isCurrent:__isCurrent})`,c);
  current=false;c.__incoming=JSON.parse(stationCollection('jp','000001'));
  await vm.runInContext(`buildStationIndexesSliced(__incoming)`,c);
  held.resolve();await old;
  assert.equal(vm.runInContext(`stationNameByCode.get('000001')`,c),'jp');
  assert.equal(vm.runInContext(`stationNameByCode.has('TW-0')`,c),false);
});
