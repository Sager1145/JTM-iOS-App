import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(
  path.join(HERE, "..", "public", "app-datasets.js"),
  "utf8",
);
const routeServiceSource = fs.readFileSync(
  path.join(HERE, "..", "public", "app-route-service.js"),
  "utf8",
);

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

test("an outgoing country parse cannot overwrite a newer country dataset", async () => {
  let activeCountry = "jp";
  const downloads = { jp: deferred(), tw: deferred() };
  const context = vm.createContext({
    performance: { now: () => 0 },
    yieldToEventLoop: async () => {},
    railSectionsApisForCountry: (country) => [country],
    fetchText: (country) => downloads[country].promise,
    parseFeatureCollectionTextChunked: async (text) => ({
      type: "FeatureCollection",
      features: [{ source: text }],
    }),
  });
  Object.defineProperty(context, "activeCountry", { get: () => activeCountry });
  vm.runInContext(source, context, { filename: "app-datasets.js" });

  const oldLoad = vm.runInContext("ensureRailSectionsLoaded()", context);
  activeCountry = "tw";
  vm.runInContext("AppDatasets.clearRailSections()", context);
  const newLoad = vm.runInContext("ensureRailSectionsLoaded()", context);
  downloads.tw.resolve("tw-new");
  const current = await newLoad;
  downloads.jp.resolve("jp-old");
  const oldResult = await oldLoad;

  assert.equal(current.features[0].source, "tw-new");
  assert.equal(oldResult.features[0].source, "tw-new");
  assert.equal(
    vm.runInContext("railSectionsGeoJson.features[0].source", context),
    "tw-new",
  );
});

test("an outgoing country failure cannot clear the current load promise", async () => {
  let activeCountry = "jp";
  const downloads = { jp: deferred(), tw: deferred() };
  const context = vm.createContext({
    performance: { now: () => 0 },
    yieldToEventLoop: async () => {},
    railSectionsApisForCountry: (country) => [country],
    fetchText: (country) => downloads[country].promise,
    parseFeatureCollectionTextChunked: async (text) => ({
      type: "FeatureCollection",
      features: [{ source: text }],
    }),
  });
  Object.defineProperty(context, "activeCountry", { get: () => activeCountry });
  vm.runInContext(source, context, { filename: "app-datasets.js" });

  const oldLoad = vm.runInContext("ensureRailSectionsLoaded()", context);
  activeCountry = "tw";
  vm.runInContext("AppDatasets.clearRailSections()", context);
  const newLoad = vm.runInContext("ensureRailSectionsLoaded()", context);
  downloads.jp.reject(new Error("outgoing country failed"));
  downloads.tw.resolve("tw-new");

  const [oldResult, current] = await Promise.all([oldLoad, newLoad]);
  assert.equal(oldResult.features[0].source, "tw-new");
  assert.equal(current.features[0].source, "tw-new");
});

test("an old solver failure cannot clear a newer solver promise", async () => {
  const oldLoad = deferred();
  let calls = 0;
  const context = vm.createContext({
    ensureRailSectionsLoaded: () => {
      calls += 1;
      return calls === 1 ? oldLoad.promise : Promise.resolve();
    },
    warmRouteCacheFromIndexedDb: async () => {},
  });
  const readiness = routeServiceSource.match(
    /function ensureSolverReady\(\) \{[\s\S]*?\n\}\n\n\/\/ A render-time/,
  )[0].replace("\n\n// A render-time", "");
  vm.runInContext(
    "let solverReadyPromise = null; let routeServiceGeneration = 0;\n" +
      readiness,
    context,
  );

  const outgoing = vm.runInContext("ensureSolverReady()", context);
  vm.runInContext("solverReadyPromise = null", context);
  const current = vm.runInContext("ensureSolverReady()", context);
  oldLoad.reject(new Error("outgoing country failed"));
  await assert.rejects(outgoing, /outgoing country failed/);
  await current;

  assert.strictEqual(
    vm.runInContext("ensureSolverReady()", context),
    current,
  );
});
