import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";

import {
  evaluateAppScripts,
  makeSandbox,
} from "../scripts/lib/app-family-sandbox.mjs";

function waitFor(probe, message) {
  return new Promise((resolve, reject) => {
    let attempts = 0;
    const poll = () => {
      const value = probe();
      if (value) {
        resolve(value);
        return;
      }
      attempts += 1;
      if (attempts > 200) {
        reject(new Error(message));
        return;
      }
      setImmediate(poll);
    };
    poll();
  });
}

// IndexedDB opens and cursor delivery are deliberately controlled separately:
// a real browser may finish opening the old country's DB, then deliver its
// cursor after CountrySession has already installed the new country.
function controlledIndexedDb() {
  const opens = [];
  const cursors = [];

  function makeDb(name, rows) {
    return {
      objectStoreNames: { contains: () => true },
      createObjectStore() {},
      close() {},
      transaction() {
        const request = {};
        const transaction = {
          objectStore: () => ({
            openCursor() {
              const control = {
                name,
                start() {
                  let index = 0;
                  const publish = () => {
                    if (index >= rows.length) {
                      request.result = null;
                      request.onsuccess?.();
                      queueMicrotask(() => transaction.oncomplete?.());
                      return;
                    }
                    const row = rows[index];
                    request.result = {
                      key: row.key,
                      value: row.value,
                      delete() {
                        row.deleted = true;
                      },
                      continue() {
                        index += 1;
                        queueMicrotask(publish);
                      },
                    };
                    request.onsuccess?.();
                  };
                  queueMicrotask(publish);
                },
              };
              cursors.push(control);
              return request;
            },
          }),
        };
        return transaction;
      },
    };
  }

  return {
    api: {
      open(name) {
        const request = {};
        opens.push({
          name,
          succeed(rows) {
            request.result = makeDb(name, rows);
            queueMicrotask(() => request.onsuccess?.());
          },
        });
        return request;
      },
    },
    opens,
    cursors,
  };
}

test("a delayed IndexedDB warm cannot repopulate the next country cache", async () => {
  const idb = controlledIndexedDb();
  const context = makeSandbox({ indexedDB: idb.api });
  evaluateAppScripts(context);

  vm.runInContext(
    `
      activeCountry = "jp";
      map = null;
      const installRaceDataset = (country) => {
        const x = country === "jp" ? 139 : 121;
        railSectionsGeoJson = {
          type: "FeatureCollection",
          features: [{ geometry: { type: "LineString", coordinates: [[x, 35], [x + 0.1, 35]] } }],
        };
        stationsGeoJson = { type: "FeatureCollection", features: [] };
      };
      installRaceDataset("jp");
      ensureRailSectionsLoaded = async () => railSectionsGeoJson;
      reloadSolverDatasetsForCountrySwitch = async () => installRaceDataset(activeCountry);
      loadActiveCountryStationReadings = async () => {};
      loadActiveCountryStore = async () => {};
      updateCountrySelect = () => {};
      updateDataSourceUi = () => {};
      renderAll = () => {};
      fitActiveCountryOverview = () => {};
      applyJapanMapConstraints = () => {};
      invalidateDeckRouteCaches = () => {};
      RailMap.switchNetworkCountry = async () => {};
    `,
    context,
  );

  const oldHash = vm.runInContext("getRailContentHash()", context);
  const version = vm.runInContext("ROUTE_SOLVER_CACHE_VERSION", context);
  const cacheKey = `solver:${version}|shared-stations`;
  const outgoingReady = vm.runInContext("RouteService.ensureReady()", context);
  const oldOpen = await waitFor(
    () => idb.opens[0],
    "outgoing route-cache DB was not opened",
  );
  assert.equal(oldOpen.name, "n02-route-geometry-cache");
  oldOpen.succeed([
    { key: `${oldHash}::${cacheKey}`, value: [{ country: "jp-old" }] },
  ]);
  const oldCursor = await waitFor(
    () => idb.cursors[0],
    "outgoing route-cache cursor was not created",
  );

  // The old cursor is still held here. Exercise the production coordinator,
  // including its route and persistence resets, before starting the new gate.
  await vm.runInContext("CountrySession.switchTo('tw')", context);
  const newHash = vm.runInContext("getRailContentHash()", context);
  assert.notEqual(newHash, oldHash);

  const currentReady = vm.runInContext("RouteService.ensureReady()", context);
  const newOpen = await waitFor(
    () => idb.opens[1],
    "current route-cache DB was not reopened",
  );
  assert.equal(newOpen.name, "n02-route-geometry-cache-tw");
  newOpen.succeed([
    { key: `${newHash}::${cacheKey}`, value: [{ country: "tw-current" }] },
  ]);
  const newCursor = await waitFor(
    () => idb.cursors[1],
    "current route-cache cursor was not created",
  );
  newCursor.start();
  await currentReady;
  assert.equal(
    vm.runInContext(`JSON.stringify(RouteService.get(${JSON.stringify(cacheKey)}))`, context),
    JSON.stringify([{ country: "tw-current" }]),
  );

  // Deliver the obsolete cursor only after the replacement cache is live.
  // The original caller still completes by joining the current readiness gate.
  oldCursor.start();
  await outgoingReady;
  assert.equal(
    vm.runInContext(`JSON.stringify(RouteService.get(${JSON.stringify(cacheKey)}))`, context),
    JSON.stringify([{ country: "tw-current" }]),
  );
  assert.deepEqual(
    idb.opens.map(({ name }) => name),
    ["n02-route-geometry-cache", "n02-route-geometry-cache-tw"],
  );
});

test("an IndexedDB open captured by the old country joins the reopened gate", async () => {
  const idb = controlledIndexedDb();
  const context = makeSandbox({ indexedDB: idb.api });
  evaluateAppScripts(context);
  vm.runInContext(
    `
      activeCountry = "jp";
      map = null;
      const installOpenRaceDataset = (country) => {
        const x = country === "jp" ? 139 : 121;
        railSectionsGeoJson = {
          type: "FeatureCollection",
          features: [{ geometry: { type: "LineString", coordinates: [[x, 35], [x + 0.1, 35]] } }],
        };
        stationsGeoJson = { type: "FeatureCollection", features: [] };
      };
      installOpenRaceDataset("jp");
      ensureRailSectionsLoaded = async () => railSectionsGeoJson;
      reloadSolverDatasetsForCountrySwitch = async () => installOpenRaceDataset(activeCountry);
      loadActiveCountryStationReadings = async () => {};
      loadActiveCountryStore = async () => {};
      updateCountrySelect = () => {};
      updateDataSourceUi = () => {};
      renderAll = () => {};
      fitActiveCountryOverview = () => {};
      applyJapanMapConstraints = () => {};
      invalidateDeckRouteCaches = () => {};
      RailMap.switchNetworkCountry = async () => {};
    `,
    context,
  );

  const oldHash = vm.runInContext("getRailContentHash()", context);
  const version = vm.runInContext("ROUTE_SOLVER_CACHE_VERSION", context);
  const cacheKey = `solver:${version}|same-route`;
  const outgoingReady = vm.runInContext("RouteService.ensureReady()", context);
  const oldOpen = await waitFor(
    () => idb.opens[0],
    "outgoing route-cache DB was not opened",
  );

  // Switch while indexedDB.open itself is unresolved. The replacement gate
  // must open the new country's DB without waiting for that obsolete request.
  await vm.runInContext("CountrySession.switchTo('tw')", context);
  const newHash = vm.runInContext("getRailContentHash()", context);
  const currentReady = vm.runInContext("RouteService.ensureReady()", context);
  const newOpen = await waitFor(
    () => idb.opens[1],
    "current route-cache DB was not reopened",
  );
  newOpen.succeed([
    { key: `${newHash}::${cacheKey}`, value: [{ country: "tw-current" }] },
  ]);
  const newCursor = await waitFor(
    () => idb.cursors[0],
    "current route-cache cursor was not created",
  );
  newCursor.start();
  await currentReady;

  oldOpen.succeed([
    { key: `${oldHash}::${cacheKey}`, value: [{ country: "jp-old" }] },
  ]);
  await new Promise((resolve) => setImmediate(resolve));
  // Starting a cursor here keeps the test deterministic against the buggy
  // implementation, which created one and would otherwise remain pending.
  idb.cursors.find(({ name }) => name === oldOpen.name)?.start();
  await outgoingReady;
  assert.equal(
    vm.runInContext(`JSON.stringify(RouteService.get(${JSON.stringify(cacheKey)}))`, context),
    JSON.stringify([{ country: "tw-current" }]),
  );
  assert.deepEqual(
    idb.opens.map(({ name }) => name),
    ["n02-route-geometry-cache", "n02-route-geometry-cache-tw"],
  );
});

function playbackHarness() {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const moveend = [];
  const handler = {
    enabled: true,
    isEnabled() {
      return this.enabled;
    },
    enable() {
      this.enabled = true;
    },
    disable() {
      this.enabled = false;
    },
  };
  const map = {
    easeTo() {},
    jumpTo() {},
    getCenter: () => ({ lng: 0, lat: 0 }),
    getZoom: () => 10,
    getContainer: () => ({ clientWidth: 1000, clientHeight: 700 }),
    once(event, listener) {
      assert.equal(event, "moveend");
      moveend.push(listener);
    },
  };
  for (const name of [
    "dragPan",
    "scrollZoom",
    "boxZoom",
    "dragRotate",
    "keyboard",
    "doubleClickZoom",
    "touchZoomRotate",
    "touchPitch",
  ]) map[name] = Object.create(handler);

  let rafRequests = 0;
  context.__raceMap = map;
  context.requestAnimationFrame = () => {
    rafRequests += 1;
    return rafRequests;
  };
  context.cancelAnimationFrame = () => {};
  vm.runInContext(
    `
      map = __raceMap;
      trainStore = {
        schema_version: SCHEMA_VERSION,
        trains: [{
          id: "race-train",
          number: "R1",
          date: "2026-09-07",
          origin: "A",
          destination: "B",
          visible: true,
          stops: [
            { name: "A", stop_type: "origin", ride_segment: true },
            { name: "B", stop_type: "destination", ride_segment: false },
          ],
        }],
      };
      selectedTrainId = "race-train";
      focusedTrainId = null;
      getTrainRouteTemplateKey = () => "race-template";
      getMatchedRouteFeatures = () => [{
        type: "Feature",
        properties: { ride_segment: true, segment_index: 0 },
        geometry: { type: "LineString", coordinates: [[0, 0], [0.01, 0]] },
      }];
      fitTrainsBounds = () => {};
      updateEndpointLabels = () => {};
      Object.assign(RailMap, {
        _rideStrokeGeneration: 0,
        setSelected() {},
        setPlaybackTrail() {},
        setPlaybackProgress() {},
        setPlaybackStations() {},
        setPlaybackStationIndex() {},
        setPlaybackHead() {},
        clearPlayback() {},
      });
    `,
    context,
  );

  return {
    context,
    emitMoveend() {
      const listeners = moveend.splice(0);
      listeners.forEach((listener) => listener());
    },
    rafRequests: () => rafRequests,
  };
}

test("an intro moveend cannot restart playback after pause, resume, or stop", () => {
  const harness = playbackHarness();
  const { context } = harness;
  const phase = () => vm.runInContext("Playback.phase()", context);
  const armIntro = () => {
    assert.equal(vm.runInContext("Playback.start()", context), true);
    vm.runInContext("Playback.begin()", context);
    assert.equal(phase(), "transitioning");
  };

  armIntro();
  vm.runInContext("Playback.pause()", context);
  assert.equal(phase(), "paused");
  harness.emitMoveend();
  assert.equal(phase(), "paused");
  assert.equal(harness.rafRequests(), 0);
  vm.runInContext("Playback.stop()", context);

  armIntro();
  vm.runInContext("Playback.pause(); Playback.resume()", context);
  assert.equal(phase(), "playing");
  const resumedClock = harness.rafRequests();
  assert.equal(resumedClock, 1);
  harness.emitMoveend();
  assert.equal(phase(), "playing");
  assert.equal(harness.rafRequests(), resumedClock);
  vm.runInContext("Playback.stop()", context);

  armIntro();
  vm.runInContext("Playback.pause(); Playback.stop()", context);
  const stoppedClock = harness.rafRequests();
  harness.emitMoveend();
  assert.equal(phase(), "idle");
  assert.equal(harness.rafRequests(), stoppedClock);
});
