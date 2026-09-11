import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";

import {
  evaluateAppScripts,
  makeDummyElement,
  makeSandbox,
} from "../scripts/lib/app-family-sandbox.mjs";

function eventHarness() {
  const context = makeSandbox();
  const elements = new Map();
  const element = (id) => {
    if (elements.has(id)) return elements.get(id);
    const value = makeDummyElement();
    value.id = id;
    value.listeners = new Map();
    value.addEventListener = (type, listener) => {
      const listeners = value.listeners.get(type) || [];
      listeners.push(listener);
      value.listeners.set(type, listeners);
    };
    elements.set(id, value);
    return value;
  };
  context.document.getElementById = element;
  context.document.querySelector = (selector) => element(`query:${selector}`);
  context.document.querySelectorAll = () => [];
  evaluateAppScripts(context);
  vm.runInContext("bindEvents()", context);
  return {
    context,
    element,
    async dispatch(id, type = "click", event = {}) {
      const listeners = element(id).listeners.get(type) || [];
      assert.ok(listeners.length, `${id} has no ${type} listener`);
      return listeners.at(-1)(event);
    },
  };
}

test("local JSON open fits only after a completed replacement", async () => {
  const harness = eventHarness();
  const { context } = harness;
  const order = [];
  context.__cameraOrder = order;
  context.showSaveFilePicker = async () => null;
  vm.runInContext(
    `
      fitActiveCountryOverview = () => __cameraOrder.push("fit");
      flushServerStoreSave = async () => __cameraOrder.push("flush");
    `,
    context,
  );

  context.showOpenFilePicker = undefined;
  context.showSaveFilePicker = undefined;
  await harness.dispatch("open-local-json");
  assert.deepEqual(order, []);

  context.showSaveFilePicker = async () => null;
  context.showOpenFilePicker = async () => {
    const error = new Error("cancelled");
    error.name = "AbortError";
    throw error;
  };
  await harness.dispatch("open-local-json");
  assert.deepEqual(order, []);

  context.showOpenFilePicker = async () => [
    {
      getFile: async () => ({
        name: "broken.json",
        text: async () => "{}",
      }),
    },
  ];
  vm.runInContext(
    `replaceTrainStoreFromJsonText = async () => { throw new Error("invalid"); };`,
    context,
  );
  await harness.dispatch("open-local-json");
  assert.deepEqual(order, []);

  context.showOpenFilePicker = async () => [
    {
      getFile: async () => ({
        name: "journeys.json",
        text: async () => "{}",
      }),
    },
  ];
  vm.runInContext(
    `replaceTrainStoreFromJsonText = async () => __cameraOrder.push("replace");`,
    context,
  );
  vm.runInContext(
    `flushServerStoreSave = async () => {
      __cameraOrder.push("flush");
      throw new Error("save failed");
    };`,
    context,
  );
  await harness.dispatch("open-local-json");
  assert.deepEqual(order, ["replace", "flush"]);

  order.length = 0;
  vm.runInContext(
    `flushServerStoreSave = async () => __cameraOrder.push("flush");`,
    context,
  );
  await harness.dispatch("open-local-json");
  assert.deepEqual(order, ["replace", "flush", "fit"]);
});

test("append, dataset, and restore handlers do not fit failed replacements", async () => {
  const harness = eventHarness();
  const { context } = harness;
  const order = [];
  context.__cameraOrder = order;
  vm.runInContext(
    `
      fitActiveCountryOverview = () => __cameraOrder.push("fit");
      flushServerStoreSave = async () => __cameraOrder.push("flush");
      uiConfirm = async () => true;
      importCanonicalStoreAppendProgressive = async () => {
        throw new Error("append failed");
      };
      loadSampleData = async () => {
        throw new Error("dataset failed");
      };
      restoreUserStore = async () => false;
    `,
    context,
  );

  await harness.dispatch("apply-import-json");
  await harness.dispatch("load-sample-all");
  await harness.dispatch("restore-user-store");
  assert.deepEqual(order, []);

  vm.runInContext(
    `
      importCanonicalStoreAppendProgressive = async () => {
        __cameraOrder.push("append");
        return { count: 1, ids: ["one"] };
      };
    `,
    context,
  );
  await harness.dispatch("apply-import-json");
  assert.deepEqual(order, ["append", "flush", "fit"]);

  order.length = 0;
  vm.runInContext(
    `loadSampleData = async () => __cameraOrder.push("dataset");`,
    context,
  );
  await harness.dispatch("load-sample-all");
  assert.deepEqual(order, ["dataset", "fit"]);

  order.length = 0;
  vm.runInContext(
    `restoreUserStore = async () => (__cameraOrder.push("restore"), true);`,
    context,
  );
  await harness.dispatch("restore-user-store");
  assert.deepEqual(order, ["restore", "fit"]);
});

test("journey detail focus yields to user movement and playback", () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const order = [];
  const listeners = new Map();
  const addListener = (event, listener, once) => {
    const entries = listeners.get(event) || [];
    entries.push({ listener, once });
    listeners.set(event, entries);
  };
  context.__cameraOrder = order;
  context.__detailMap = {
    on(event, listener) {
      addListener(event, listener, false);
    },
    once(event, listener) {
      addListener(event, listener, true);
    },
    off(event, listener) {
      listeners.set(
        event,
        (listeners.get(event) || []).filter((entry) => entry.listener !== listener),
      );
    },
    emit(event, payload = {}) {
      const entries = [...(listeners.get(event) || [])];
      listeners.set(
        event,
        (listeners.get(event) || []).filter((entry) => !entry.once),
      );
      entries.forEach((entry) => entry.listener(payload));
    },
    listenerCount(event) {
      return (listeners.get(event) || []).length;
    },
    firstListener(event) {
      return (listeners.get(event) || [])[0]?.listener || null;
    },
  };
  vm.runInContext(
    `
      const detailTrain = { id: "detail" };
      map = __detailMap;
      focusZoomEnabled = true;
      sidebarVisible = true;
      sidebarPanelState = "docked";
      getTrain = (id) => id === "detail" ? detailTrain : null;
      sidebarUsesVerticalDrag = () => true;
      setActivePrimaryWorkspace = (name) => {
        activePrimaryWorkspace = name;
        __cameraOrder.push("workspace");
      };
      setSidebarPanelState = () => {
        sidebarPanelState = "half";
        __cameraOrder.push("panel");
        return 320;
      };
      selectTrain = (id, options) => {
        selectedTrainId = id;
        focusedTrainId = id;
        __cameraOrder.push(options.fit ? "select-fit" : "select");
      };
      fitTrainsBounds = () => __cameraOrder.push("fit");
      Playback.isActive = () => false;
      openJourneyDetail("missing");
      openJourneyDetail("detail");
    `,
    context,
  );

  assert.deepEqual(order, ["workspace", "panel", "select"]);
  assert.equal(context.__detailMap.listenerCount("mousedown"), 1);
  assert.equal(context.__detailMap.listenerCount("moveend"), 1);
  const staleSettled = context.__detailMap.firstListener("moveend");

  // MapLibre publishes the pointer event before a drag interrupts the running
  // ease. It owns the camera now, so all deferred listeners are removed before
  // the interrupted padding move's moveend.
  context.__detailMap.emit("mousedown", { originalEvent: {} });
  assert.equal(context.__detailMap.listenerCount("movestart"), 0);
  assert.equal(context.__detailMap.listenerCount("wheel"), 0);
  assert.equal(context.__detailMap.listenerCount("moveend"), 0);
  // MapLibre Evented copies its listener array before dispatch. A moveend
  // callback already present in that snapshot must still observe cancellation.
  staleSettled();
  context.__detailMap.emit("moveend");
  assert.deepEqual(order, ["workspace", "panel", "select"]);

  // Wheel zoom follows the same early-cancellation path.
  vm.runInContext(
    `
      sidebarPanelState = "docked";
      openJourneyDetail("detail");
    `,
    context,
  );
  context.__detailMap.emit("wheel", { originalEvent: {} });
  context.__detailMap.emit("moveend");
  assert.equal(order.includes("fit"), false);
  assert.equal(context.__detailMap.listenerCount("moveend"), 0);

  // Playback can take ownership even when its opening fit cannot start a map
  // move. The settle callback checks that state as a final guard and cleans up.
  vm.runInContext(
    `
      sidebarPanelState = "docked";
      Playback.isActive = () => true;
      openJourneyDetail("detail");
    `,
    context,
  );
  context.__detailMap.emit("moveend");
  assert.equal(context.__detailMap.listenerCount("movestart"), 0);
  assert.equal(context.__detailMap.listenerCount("moveend"), 0);
  assert.equal(order.includes("fit"), false);

  // Leaving Journey Detail invalidates the old request even though the same
  // record can remain selected across workspaces.
  vm.runInContext(
    `
      sidebarPanelState = "docked";
      Playback.isActive = () => false;
      openJourneyDetail("detail");
      activePrimaryWorkspace = "passport";
    `,
    context,
  );
  context.__detailMap.emit("moveend");
  assert.equal(order.includes("fit"), false);
  assert.equal(context.__detailMap.listenerCount("movestart"), 0);
  assert.equal(context.__detailMap.listenerCount("moveend"), 0);

  // With no new camera owner, the panel's own moveend performs one focus and
  // leaves no listeners behind.
  vm.runInContext(
    `
      sidebarPanelState = "docked";
      Playback.isActive = () => false;
      openJourneyDetail("detail");
    `,
    context,
  );
  context.__detailMap.emit("moveend");
  assert.equal(order.filter((entry) => entry === "fit").length, 1);
  assert.equal(context.__detailMap.listenerCount("movestart"), 0);
  assert.equal(context.__detailMap.listenerCount("moveend"), 0);
});

test("automatic focus stays still when the target is fully visible", () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const fits = [];
  context.__fits = fits;
  context.__fitMap = {
    getContainer: () => ({ clientWidth: 1000, clientHeight: 800 }),
    getPadding: () => ({ top: 0, right: 0, bottom: 120, left: 160 }),
    project: ([lng, lat]) => ({ x: 500 + lng * 10, y: 350 - lat * 10 }),
    cameraForBounds: () => ({ zoom: 10 }),
    fitBounds(bounds, options) {
      fits.push({ bounds, options });
    },
  };
  vm.runInContext(
    `
      map = __fitMap;
      getMatchedRouteFeatures = () => [{
        geometry: { type: "LineString", coordinates: [[-1, -1], [1, 1]] },
      }];
      fitTrainsBounds([{ id: "visible" }]);
      fitTrainBounds({ id: "visible" });
      getMatchedRouteFeatures = () => [{
        geometry: { type: "LineString", coordinates: [[99, 99], [100, 100]] },
      }];
      fitTrainsBounds([{ id: "outside" }]);
    `,
    context,
  );

  assert.equal(fits.length, 2);
  assert.equal(JSON.stringify(fits[0].bounds), JSON.stringify([
    [-1, -1],
    [1, 1],
  ]));
  assert.equal(JSON.stringify(fits[1].bounds), JSON.stringify([
    [99, 99],
    [100, 100],
  ]));
});

test("playback finale frames only trajectories that actually finished", async () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const fits = [];
  const frames = [];
  const handler = {
    isEnabled: () => true,
    enable() {},
    disable() {},
  };
  const map = {
    cameraForBounds: () => ({ zoom: 10 }),
    fitBounds(bounds, options) {
      fits.push({ bounds: structuredClone(bounds), options });
    },
    jumpTo() {},
    getCenter: () => ({ lng: 0, lat: 0 }),
    getZoom: () => 10,
    getContainer: () => ({ clientWidth: 1000, clientHeight: 700 }),
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
  ])
    map[name] = handler;
  context.__playbackMap = map;
  context.requestAnimationFrame = (callback) => {
    frames.push(callback);
    return frames.length;
  };
  context.cancelAnimationFrame = () => {};
  context.setTimeout = (callback) => {
    queueMicrotask(callback);
    return 1;
  };
  context.clearTimeout = () => {};
  vm.runInContext(
    `
      map = __playbackMap;
      REDUCED_MOTION_MEDIA.matches = true;
      trainStore = {
        schema_version: SCHEMA_VERSION,
        trains: [
          {
            id: "played",
            number: "P1",
            date: "2026-09-08",
            visible: true,
            stops: [
              { name: "A", stop_type: "origin", ride_segment: true },
              { name: "B", stop_type: "destination", ride_segment: false },
            ],
          },
          {
            id: "same-day-but-not-played",
            number: "X1",
            date: "2026-09-08",
            visible: true,
            stops: [
              { name: "Far A", stop_type: "origin", ride_segment: true },
              { name: "Far B", stop_type: "destination", ride_segment: false },
            ],
          },
        ],
      };
      selectedTrainId = "played";
      focusedTrainId = null;
      getTrainRouteTemplateKey = (train) => train.id;
      getMatchedRouteFeatures = (train) => [{
        type: "Feature",
        properties: { ride_segment: true, segment_index: 0 },
        geometry: {
          type: "LineString",
          coordinates: train.id === "played"
            ? [[0, 0], [0.01, 0]]
            : [[50, 50], [51, 51]],
        },
      }];
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
      Playback.setSpeed(4);
      Playback.start();
    `,
    context,
  );
  fits.length = 0; // discard the opening scope overview
  vm.runInContext("Playback.begin()", context);

  let now = performance.now();
  for (
    let guard = 0;
    guard < 100 && vm.runInContext("Playback.phase()", context) !== "ended";
    guard += 1
  ) {
    const frame = frames.shift();
    if (frame) frame((now += 100));
    await Promise.resolve();
  }

  assert.equal(vm.runInContext("Playback.phase()", context), "ended");
  assert.equal(fits.length, 1);
  assert.deepEqual(fits[0].bounds, [
    [0, 0],
    [0.01, 0],
  ]);
  assert.equal(fits[0].options.maxZoom, 13.5);
});
