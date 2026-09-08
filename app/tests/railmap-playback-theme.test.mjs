import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(HERE, "..", "public");
const surfaceColors = {
  light: {
    background: "rgb(255,255,255)",
    fade: "rgba(255,255,255,0.8)",
    casing: "rgb(255,255,255)",
    stationRing: "rgb(255,255,255)",
  },
  dark: {
    background: "rgb(20,20,20)",
    fade: "rgba(20,20,20,0.8)",
    casing: "rgb(7,8,10)",
    stationRing: "rgb(7,8,10)",
  },
};

function loadRailMap() {
  const context = vm.createContext({
    console,
    URL,
    location: { href: "https://example.test/" },
    performance: { now: () => 0 },
    RailMapBasemap: {
      MAP_SURFACE_COLORS: surfaceColors,
      BASEMAP_CROSSFADE_MS: 180,
      loadBasemap: async () => null,
      namespaceBasemap: (value) => value,
      opacityPropsForLayer: () => [],
      probeBasemapOrigin: async () => false,
    },
    RailNetwork: { DEFAULT_LINE_COLOR: "#7c8a82" },
    RailMapGeometry: {},
  });
  context.window = context;
  vm.runInContext(
    fs.readFileSync(path.join(PUBLIC, "railmap-style.js"), "utf8"),
    context,
    { filename: "railmap-style.js" },
  );
  vm.runInContext(
    fs.readFileSync(path.join(PUBLIC, "railmap.js"), "utf8"),
    context,
    { filename: "railmap.js" },
  );
  return context;
}

test("switching theme restamps an active playback layer stack in place", async () => {
  const context = loadRailMap();
  const { RailMap, RailMapStyle } = context;
  const playbackLayers = new Set([
    RailMapStyle.PLAYBACK_CASING_DONE_LAYER,
    RailMapStyle.PLAYBACK_CASING_HEAD_LAYER,
    RailMapStyle.PLAYBACK_STATION_LAYER,
    RailMapStyle.PLAYBACK_STATION_DONE_LAYER,
    RailMapStyle.PLAYBACK_STATION_LABEL_LAYER,
    RailMapStyle.PLAYBACK_HEAD_DOT_LAYER,
  ]);
  const paintWrites = [];
  const sourceWrites = [];
  const map = {
    getLayer: (id) => playbackLayers.has(id),
    getSource: () => ({ setData: (data) => sourceWrites.push(data) }),
    setFilter: () => {},
    setPaintProperty: (id, property, value) =>
      paintWrites.push({ id, property, value: JSON.parse(JSON.stringify(value)) }),
  };

  RailMap._map = map;
  RailMap._theme = "light";
  RailMap._basemapInstalledTheme = "dark";
  RailMap._basemapStack = { layerIds: [], sourceIds: [] };
  RailMap.setPlaybackTrail([], [[[139.7, 35.6], [139.8, 35.7]]], "#e44b3b");
  RailMap.setPlaybackStations([
    { coord: [139.7, 35.6], name: "東京", color: "#e44b3b" },
  ]);
  RailMap.setPlaybackStationIndex(0, 0);
  RailMap.setPlaybackProgress(0, 0.42);
  paintWrites.length = 0;
  const sourceWriteCount = sourceWrites.length;

  assert.equal(await RailMap.setBasemapTheme("dark", { animate: false }), true);
  assert.equal(sourceWrites.length, sourceWriteCount, "theme repaint must not rebuild sources");

  const paintValue = (id, property) =>
    paintWrites.find((entry) => entry.id === id && entry.property === property)?.value;
  assert.equal(
    paintValue(RailMapStyle.PLAYBACK_CASING_DONE_LAYER, "line-color"),
    surfaceColors.dark.casing,
  );
  assert.deepEqual(
    paintValue(RailMapStyle.PLAYBACK_CASING_HEAD_LAYER, "line-gradient"),
    JSON.parse(
      JSON.stringify(RailMapStyle.playbackTrailGradient(surfaceColors.dark.casing, 0.42)),
    ),
  );
  assert.equal(
    paintValue(RailMapStyle.PLAYBACK_STATION_LAYER, "circle-color"),
    surfaceColors.dark.stationRing,
  );
  assert.equal(
    paintValue(RailMapStyle.PLAYBACK_STATION_DONE_LAYER, "circle-stroke-color"),
    surfaceColors.dark.stationRing,
  );
  assert.equal(
    paintValue(RailMapStyle.PLAYBACK_HEAD_DOT_LAYER, "circle-stroke-color"),
    surfaceColors.dark.stationRing,
  );
  assert.deepEqual(
    paintValue(RailMapStyle.PLAYBACK_STATION_LABEL_LAYER, "text-color"),
    JSON.parse(JSON.stringify(RailMapStyle.playbackStationTextColor(0, "dark"))),
  );
  assert.equal(
    paintValue(RailMapStyle.PLAYBACK_STATION_LABEL_LAYER, "text-halo-color"),
    RailMapStyle.networkLabelHaloColor("dark"),
  );
});
