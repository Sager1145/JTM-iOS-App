import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { IDBFactory } from "fake-indexeddb";
import { evaluateAppScripts, makeSandbox } from "../scripts/lib/app-family-sandbox.mjs";

function appContext() {
  const context = makeSandbox({ indexedDB: new IDBFactory() });
  context.console = { log() {}, warn() {}, error() {}, info() {}, debug() {} };
  evaluateAppScripts(context);
  return context;
}

const run = (context, source) => vm.runInContext(source, context);
const json = (context, expression) => JSON.parse(run(context, `JSON.stringify(${expression})`));

test("legacy day records restore canonical journeys without reviving unversioned geometry", async () => {
  const context = appContext();
  await run(context, `(async () => {
    const db = await openUserStoreDb();
    await new Promise((resolve, reject) => {
      const tx = db.transaction([USER_STORE_DATES_STORE, USER_STORE_META_STORE], "readwrite");
      tx.objectStore(USER_STORE_DATES_STORE).put({date:"2026-10-17",trains:[{id:"kept",date:"2026-10-17",notes:"user record"}],
        routes:[{cache_key:"solver:old",features:[{legacy:true}]}]}, "2026-10-17");
      tx.objectStore(USER_STORE_META_STORE).put({schema_version:SCHEMA_VERSION,dates:["2026-10-17"]},USER_STORE_META_KEY);
      tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);
    });
    db.close();
  })()`);
  const restored = await run(context, "readUserStoreAll()");
  assert.equal(restored.store.trains[0].notes, "user record");
  assert.equal(Object.hasOwn(restored, "routes"), false);
  assert.equal(run(context, "runtimeRouteCache.size"), 0);

  context.__restoredStore = restored.store;
  await run(context, "writeUserStoreChunks(__restoredStore)");
  assert.deepEqual(json(context, "[...userStoreWrittenChunks.values()].map(JSON.parse)"), [
    { date: "2026-10-17", trains: [{ id: "kept", date: "2026-10-17", notes: "user record" }] },
  ]);
});

test("saving sample records keeps positive and negative routes only in the versioned cache", async () => {
  const context = appContext();
  run(context, `railSectionsGeoJson={features:[]};stationsGeoJson={features:[]};
    trainStore={schema_version:SCHEMA_VERSION,trains:[{id:"positive",date:"2026-10-17"},{id:"negative",date:"2026-10-17"}]};
    buildTrainRouteSolveContext=train=>({cacheKey:"solver:"+ROUTE_SOLVER_CACHE_VERSION+"|"+train.id});
    RouteService.seed("solver:"+ROUTE_SOLVER_CACHE_VERSION+"|positive",[{type:"Feature",properties:{fixture:true}}]);
    RouteService.seedNegative("solver:"+ROUTE_SOLVER_CACHE_VERSION+"|negative");`);
  await run(context, "writeUserStoreChunks(trainStore,{force:true})");
  const restored = await run(context, "readUserStoreAll()");
  assert.equal(restored.store.trains.length, 2);
  assert.equal(json(context, "[...userStoreWrittenChunks.values()].map(JSON.parse)").some(record => "routes" in record), false);
  run(context, "RouteService.resetForCountry()");
  await run(context, "warmRouteCacheFromIndexedDb()");
  assert.equal(run(context, 'RouteService.has("solver:"+ROUTE_SOLVER_CACHE_VERSION+"|positive")'), true);
  assert.equal(run(context, 'RouteService.isNegative("solver:"+ROUTE_SOLVER_CACHE_VERSION+"|negative")'), true);
});

test("render and mutation paths do no export work; explicit export preserves recovery bytes", async () => {
  const context = appContext();
  const timers = [];
  context.setTimeout = callback => { timers.push(callback); return timers.length; };
  run(context, `let exportCalls=0;exportTrainStore=()=>{exportCalls++;return '{"current":true}'};
    renderDateButtons=renderTrainList=updateImportTarget=renderEditor=renderTrainLayers=
    renderPanelDockedSummary=renderNetworkWorkspace=renderPassportJourneyLog=scheduleMileageStats=()=>{};
    renderAll();applyMutationResult({exportJson:true});`);
  assert.equal(run(context, "exportCalls"), 0);
  assert.equal(timers.length, 0);
  assert.equal(run(context, "refreshExportTextarea()"), '{"current":true}');
  assert.equal(run(context, "exportCalls"), 1);
  context.__raw = "{ broken user's JSON\n";
  run(context, "enterStoreRecoveryMode({rawText:__raw})");
  assert.equal(run(context, "refreshExportTextarea()"), context.__raw);
  let downloaded;
  context.downloadText = (_name, text) => { downloaded = text; };
  await run(context, "writeLocalJsonFile()");
  assert.equal(downloaded, context.__raw);
  assert.equal(run(context, "exportCalls"), 1);
});

test("missing runtime configuration uses the deployed static file contract", () => {
  const context = vm.createContext({ window: {}, Date, Math });
  vm.runInContext(fs.readFileSync(new URL("../public/app-api.js", import.meta.url), "utf8"), context);
  assert.equal(run(context, "HAS_BACKEND"), false);
  assert.equal(run(context, 'apiResourceUrl("stations")'), "./api/stations.json");
});

function networkContext({ failPackage = false } = {}) {
  const calls = [];
  const messages = [];
  const context = vm.createContext({
    URL,
    location: { href: "https://example.test/project/" },
    console: { warn() {} },
    RailMapBasemap: {},
    RailMapGeometry: {},
    fetch: async url => {
      calls.push(String(url));
      const packageRequest = String(url).endsWith("jp-2025.json");
      return { ok: packageRequest && !failPackage, status: packageRequest ? 503 : 404,
        json: async () => ({ format: "compact-v1", country: "jp", lines: [] }) };
    },
  });
  context.window = context;
  context.self = context;
  const load = filename => vm.runInContext(fs.readFileSync(new URL(`../public/${filename}`, import.meta.url), "utf8"), context, { filename });
  context.importScripts = () => load("rail-network.js");
  context.postMessage = message => messages.push(message);
  return { context, calls, messages, load };
}

test("window and real classic worker adapters share package decoding and optional-file fallback", async () => {
  const main = networkContext();
  main.load("rail-network.js");
  main.load("railmap-style.js");
  main.load("railmap.js");
  const network = await run(main.context, 'RailMap.ensureNetwork("rail/jp-2025.json")');
  assert.ok(network);
  const worker = networkContext();
  worker.load("rail-network-worker.js");
  await worker.context.onmessage({ data: { packageUrls: ["https://example.test/project/rail/jp-2025.json"],
    reviewedUrl: "https://example.test/project/rail/shared-corridors.json",
    lanesUrl: "https://example.test/project/rail/display-lanes.json" } });
  assert.equal(worker.messages[0].ok, true);
  assert.deepEqual(worker.calls, main.calls);
  assert.equal(main.calls.length, 3, "one request per declared resource in either host");
  assert.equal(JSON.stringify(worker.messages[0].network), JSON.stringify(network));
});

test("shared decoder reports package HTTP failures through the worker envelope", async () => {
  const worker = networkContext({ failPackage: true });
  worker.load("rail-network-worker.js");
  await worker.context.onmessage({ data: { packageUrls: ["https://example.test/rail/jp-2025.json"] } });
  assert.equal(worker.messages[0].ok, false);
  assert.match(worker.messages[0].error, /HTTP 503/);
  assert.equal(worker.calls.length, 1);
});
