import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import vm from "node:vm";

function loadRailMap() {
  const timers = new Map();
  const workers = [];
  let nextTimer = 1;
  const context = vm.createContext({
    console,
    URL,
    location: { href: "https://example.test/" },
    RailMapBasemap: {},
    RailNetwork: { DEFAULT_LINE_COLOR: "#7c8a82" },
    RailMapGeometry: {},
    Worker: class {
      constructor() { workers.push(this); }
      postMessage() {}
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
  return { ...context, timers, workers };
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
