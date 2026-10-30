import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { createRequire } from "node:module";
const Network = createRequire(import.meta.url)('../public/rail-network.js');

function loadRailMap() {
  const timers = new Map();
  const workers = [];
  let nextTimer = 1;
  const context = vm.createContext({
    console,
    URL,
    location: { href: "https://example.test/" },
    RailMapBasemap: {},
    RailNetwork: { ...Network },
    RailMapGeometry: {},
    Worker: class {
      constructor() { workers.push(this); }
      postMessage(message) { this.message = message; }
      terminate() {}
    },
    setTimeout(callback) {
      const id = nextTimer++;
      timers.set(id, callback);
      return id;
    },
    clearTimeout(id) { timers.delete(id); },
  });
  context.window = context;
  for (const filename of ["railmap-style.js", "railmap.js"]) {
    vm.runInContext(
      fs.readFileSync(new URL(`../public/${filename}`, import.meta.url), "utf8"),
      context,
      { filename },
    );
  }
  return { ...context, context, timers, workers };
}

test("country switch retires a queued stroke upload before the replacement loads", async () => {
  const { RailMap, RailMapStyle, timers, workers } = loadRailMap();
  const oldSegments = { type: "FeatureCollection", features: [{ id: "old-country" }] };
  const writes = [];
  RailMap._network = { strokeModel: {}, segments: oldSegments };
  RailMap._networkVisibleWanted = true;
  RailMap._map = {
    getSource: (id) => id === RailMapStyle.SEGMENTS_SOURCE
      ? { setData: (data) => writes.push(data) } : null,
    getLayer: () => false,
  };
  // Hide the layer while a zoom pass is queued, then load another country.
  // Hidden layers do not schedule a new pass that would replace the old timer.
  RailMap._scheduleStrokeRebuild();
  assert.equal(timers.size, 1);
  RailMap.setNetworkVisible(false);
  const replacement = { strokeModel: {}, segments: { type: "FeatureCollection", features: [] } };
  // A camera zoom after loading makes a deferred non-forced pass do real work.
  RailMap._applyContinuousStrokes = () => ({ anchorsChanged: false, withheldChanged: false });
  RailMap._applyRideStrokes = () => {};
  RailMap._ensureStationIcons = () => {};
  RailMap._pushRoutes = () => {};
  RailMap._pushPickFan = () => {};

  const switching = RailMap.switchNetworkCountry("tw", "tw.json");
  assert.equal(workers.length, 1);
  workers[0].onmessage({ data: { ok: true, network: replacement } });
  await switching;
  assert.equal(writes.includes(replacement.segments), true, "replacement loads through ensureNetwork");
  for (const callback of timers.values()) callback();
  assert.equal(writes.includes(oldSegments), false, "the retired country must never upload again");
  assert.equal(RailMap._strokeRebuildTimer, null);
  assert.equal(RailMap._network, replacement);
});

const datedLine = { id: 'dated', name: 'Dated', operator: 'Rail', country: 'jp', serviceStatus: 'substitute_bus',
  serviceSpans: [[0,1,2]], stations: [['a','A',139,35],['b','B',139.001,35]],
  segments: [[0.1,0,[[139,35],[139.001,35]]]] };
const datedHistory = { schema_version:'2', revision:'dated-history', features:['service_status_periods'],
  service_status_periods:[{ history_id:'dated.suspension', lineID:'dated', scope:'whole_line',
    station_membership_ids:['a','b'], valid_from:'2024-10-05', valid_to:null,
    serviceStatus:'substitute_bus', source:['https://example.test/official'] }] };
const datedContext = day => ({ era:'rideDate', today:'2026-10-26', rideDate:day, history:structuredClone(datedHistory),
  historyGeneration:1 });
const datedInputs = { pkg:{format:'compact-v1',country:'jp',lines:[datedLine]},reviewed:null,lanes:null };

test('date and history refresh preserve country source policy while real country switches update it', async () => {
  const { RailMap, RailMapStyle, workers } = loadRailMap();
  const network = { segments: { features: [] }, stations: { features: [] } };
  const context = datedContext('2024-10-04');
  const initial = RailMap.ensureNetwork('jp.json', context);
  workers.at(-1).onmessage({ data: { ok: true, network, inputs: datedInputs } });
  await initial;

  const sourceIDs = ['SEGMENTS_SOURCE', 'SEGMENTS_WITHHELD_SOURCE', 'TRAIN_ROUTES_SOURCE',
    'TRAIN_PICK_SOURCE', 'TRAIN_PICK_FAN_SOURCE', 'TRAIN_EXPAND_SOURCE', 'PLAYBACK_SOURCE'];
  const sources = new Map(sourceIDs.map(key => [RailMapStyle[key], {
    workerOptions: { geojsonVtOptions: { tolerance: 0 } },
    _pixelsToTileUnits: value => value,
    attribution: RailMapStyle.railAttributionForCountry('jp'), setData() {},
  }]));
  RailMap._map = { getSource: id => sources.get(id), getLayer: () => false };
  RailMap._applyContinuousStrokes = () => {};
  RailMap._applyRideStrokes = () => {};
  RailMap._ensureStationIcons = () => {};
  RailMap._pushRoutes = () => {};
  RailMap._pushPickFan = () => {};
  const segment = sources.get(RailMapStyle.SEGMENTS_SOURCE);
  const assertPolicy = country => {
    for (const source of sources.values())
      assert.equal(source.workerOptions.geojsonVtOptions.tolerance,
        RailMapStyle.strokeSourceTolerancePx(country), `${country} stroke source policy`);
    assert.equal(segment.attribution, RailMapStyle.railAttributionForCountry(country));
  };
  const finish = async request => {
    workers.at(-1).onmessage({ data: { ok: true, network, inputs: datedInputs } });
    await request;
  };

  const dateChanged = RailMap.ensureNetwork('jp.json', { ...context, rideDate: '2024-10-05' });
  assertPolicy('jp');
  assert(workers.at(-1).message.inputs, 'date refresh reuses parsed inputs');
  await finish(dateChanged);
  const historyChanged = RailMap.ensureNetwork('jp.json', { ...context,
    rideDate: '2024-10-05', historyGeneration: 2 });
  assertPolicy('jp');
  assert(workers.at(-1).message.inputs, 'history refresh reuses parsed inputs');
  await finish(historyChanged);

  const taiwan = RailMap.switchNetworkCountry('tw', 'tw.json');
  assertPolicy('tw');
  await finish(taiwan);
  const japan = RailMap.switchNetworkCountry('jp', 'jp.json', context);
  assertPolicy('jp');
  await finish(japan);
});

test('shared loadNetwork derives the explicit date from reusable immutable inputs', async () => {
  const input = structuredClone(datedInputs);
  const before = await Network.loadNetwork({ inputs:input, dateContext:datedContext('2024-10-04') });
  assert.equal(before.strokeModel?.lines.length,1);
  const after = await Network.loadNetwork({ inputs:input, dateContext:datedContext('2024-10-05') });
  assert.equal(after.segments.features.length,0);
  assert.deepEqual(input,datedInputs);
});

test('date/history replacement retires older worker results and keys the resolved regional day', async () => {
  const { RailMap,workers } = loadRailMap();
  const old = RailMap.ensureNetwork('jp.json',datedContext('2024-10-04'));
  const nextContext = datedContext('2024-10-05');
  const next = RailMap.ensureNetwork('jp.json',nextContext);
  assert.equal(workers.length,2);
  assert.equal(workers[1].message.dateContext.rideDate,'2024-10-05');
  const replacement = { segments:{features:[]},stations:{features:[]} };
  workers[1].onmessage({data:{ok:true,network:replacement,inputs:datedInputs}});
  assert.equal(await next,replacement);
  workers[0].onmessage({data:{ok:true,network:{old:true},inputs:datedInputs}});
  assert.equal(await old,null);
  assert.equal(RailMap._network,replacement);
  assert.equal(await RailMap.ensureNetwork('jp.json',nextContext),replacement);
  assert.equal(workers.length,2,'same snapshot reuses derived network');
  const nextDay = {...nextContext,today:'2026-10-27'};
  const changed = RailMap.ensureNetwork('jp.json',nextDay);
  assert.equal(workers.length,3);
  assert(workers[2].message.inputs,'date changes reuse parsed physical inputs');
  workers[2].onmessage({data:{ok:true,network:replacement,inputs:datedInputs}});
  await changed;
  const historyReplacement = {...nextDay,historyGeneration:2};
  const replaced = RailMap.ensureNetwork('jp.json',historyReplacement);
  assert.equal(workers.length,4,'actual history replacement invalidates even unchanged revision');
  workers[3].onmessage({data:{ok:true,network:replacement,inputs:datedInputs}});
  await replaced;
});

test('station opening hides only its managed own dot and label, retaining through rail geometry', () => {
  const other = {...datedLine,id:'other',name:'Other',operator:'Other Rail'};
  const pkg = {...datedInputs.pkg,lines:[datedLine,other]};
  const context = {...datedContext('2008-08-08'),stationMemberships:[{lineID:'dated',lineName:'Dated',operator:'Rail',
    stationGroupID:'a',validFrom:'2008-08-09',validTo:null,historyID:'opening',suspensionPeriodID:null,visible:false}]};
  const result = Network.buildNetworkFromCompactPackage(pkg,null,null,context);
  assert.equal(result.strokeModel.lines.filter(l=>l.lineId==='dated').length,1);
  assert.equal(result.segments.features.filter(f=>f.properties.lineId==='dated').length,1);
  assert.equal(result.stations.features.some(f=>f.properties.stationId==='dated:a'),false);
  assert.equal(result.stations.features.some(f=>f.properties.stationId==='other:a'),true);
  assert.equal(result.stationLabels.features.some(f=>f.properties.stationId==='dated:a'),false);
  assert.equal(result.stationById.has('dated:a'),true);
});

test('classic worker and main fallback agree on dated visibility and reject invalid contexts', async () => {
  const worker = async (dateContext) => {
    let posted;
    const scope = vm.createContext({console,postMessage:message=>{posted=message;}});
    scope.self = scope;
    scope.importScripts = (...urls) => urls.forEach(url => vm.runInContext(
      fs.readFileSync(new URL(`../public/${url.replace(/^\.\//,'').split('?')[0]}`,import.meta.url),'utf8'),scope));
    vm.runInContext(fs.readFileSync(new URL('../public/rail-network-worker.js',import.meta.url),'utf8'),scope);
    await scope.onmessage({data:{inputs:structuredClone(datedInputs),dateContext:structuredClone(dateContext)}});
    return posted;
  };
  const counts = network => [network.segments.features.length,network.stations.features.length,
    network.stationLabels.features.length,network.strokeModel?.lines.length || 0];
  const main = loadRailMap(); main.context.Worker = undefined;
  let reads = 0;
  main.context.RailNetwork.loadNetworkInputs = async () => {reads++;return structuredClone(datedInputs);};
  for (const day of ['2024-10-04','2024-10-05']) {
    const context = datedContext(day);
    const background = await worker(context);
    assert.equal(background.ok,true);
    const foreground = await main.RailMap.loadNetwork('jp.json',context);
    assert.deepEqual(counts(foreground),counts(background.network));
  }
  assert.equal(reads,1,'a date change does not re-read immutable package/layout inputs');
  const invalid = {...datedContext('2024-10-04'),today:'2024-02-30'};
  assert.equal((await worker(invalid)).ok,false);
  const warnings = [];
  main.context.console = {...console,warn:(...message)=>warnings.push(message)};
  assert.equal(await main.RailMap.loadNetwork('jp.json',invalid),null);
  assert.equal(warnings.length,1,'the invalid main-thread context is reported');
});

test('one pending context is deduplicated and caller mutation cannot relabel its result', async () => {
  const {RailMap,workers} = loadRailMap();
  const context = datedContext('2024-10-04');
  const first = RailMap.ensureNetwork('jp.json',context);
  const same = RailMap.ensureNetwork('jp.json',context);
  assert.equal(workers.length,1);
  assert.equal(first,same);
  context.rideDate = '2024-10-05';
  workers[0].onmessage({data:{ok:true,network:{date:'2024-10-04'},inputs:datedInputs}});
  await first;
  const next = RailMap.ensureNetwork('jp.json',context);
  assert.equal(workers.length,2,'mutating caller context still requires a new derivation');
  workers[1].onmessage({data:{ok:true,network:{date:'2024-10-05'},inputs:datedInputs}});
  await next;
});
