import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { readFileSync } from "node:fs";

function setup() {
  const context = vm.createContext({
    document: { readyState: "loading", addEventListener() {} },
    localStorage: { getItem() { return null; } },
  });
  context.window = context;
  context.AppCore = { normalizeStationName: (s) => s.trim() };
  context.RailNetwork = { DEFAULT_LINE_COLOR: "#888" };
  context.RailOperatorBranding = {
    companyLabel: (s) => s, companyFor: (s) => s,
    logoForLine: () => null, logoNeedsDarkMatte: () => false,
  };
  for (const file of ["i18n-strings.js", "i18n.js", "railmap-popup.js"])
    vm.runInContext(readFileSync(new URL("../public/" + file, import.meta.url), "utf8"), context);
  return context;
}
function network() {
  const stations = [
    { stationId: "one:code", stationGroupId: "code", lineId: "one", name: "原名", lon: 121, lat: 25 },
    { stationId: "two:code", stationGroupId: "code", lineId: "two", name: "原名" },
    { stationId: "branch:code", stationGroupId: "code", lineId: "branch", name: "原名" },
  ];
  return {
    stationById: new Map(stations.map((s) => [s.stationId, s])),
    groupMembers: new Map([["code", stations]]),
    lineById: new Map([
      ["one", { lineId: "one", name: "Line A", operator: "Rail A", country: "tw" }],
      ["two", { lineId: "two", name: "Line B", operator: "Rail B" }],
      ["branch", { lineId: "branch", name: "Line A", operator: "Rail A" }],
    ]),
  };
}
test("clicked details show complete curated names with labels despite disabled readings", () => {
  const c = setup();
  c.I18N.setStationReadings({ country: "TW", byCode: { code: {
    zh_Hant: "原名", zh_Hans: "原名简", ja: "駅名", en: "Official Name",
    kana: "かな", katakana: "カナ", romaji: "Roma", ignored: "Never shown",
  } } });
  c.I18N.setNameReadings({ kana: false, romaji: false, zh: false });
  const popup = c.RailMapPopup;
  const compact = popup.buildPopupModel(network(), "one:code");
  assert.equal(compact.details, undefined);
  assert.equal(compact.readings.length, 0);
  const detailed = popup.buildPopupModel(network(), "one:code", null, { detailed: true });
  assert.equal(detailed.details.names.length, 7);
  assert.equal(detailed.lines.length, 2);
  const html = popup.stationPopupHtml(detailed, { detailed: true });
  for (const text of ["繁體中文", "简体中文", "日本語", "English", "かな", "カタカナ", "Rōmaji", "Official Name", "Line A", "Line B", "Rail A", "Rail B", "25.000000, 121.000000", "code"])
    assert.ok(html.includes(text), text);
  assert.ok(!html.includes("Never shown"));
  assert.ok(!popup.stationPopupHtml(compact).includes("rp-station-details"));
});
test("exact station code wins over same-name fallback, absent translations stay absent", () => {
  const c = setup();
  c.I18N.setStationReadings({ byCode: { code: { en: "Correct", ja: "", kana: "  " } }, byName: { 原名: { en: "Wrong" } } });
  assert.equal(JSON.stringify(c.I18N.stationNames("原名", "code")), JSON.stringify([{ kind: "en", text: "Correct" }]));
  assert.equal(c.I18N.stationNames("Missing", "missing").length, 0);
});
test("all name and station detail values are escaped", () => {
  const c = setup();
  const bad = '<img src=x onerror="alert(1)">&';
  c.I18N.setStationReadings({ byCode: { code: { en: bad } } });
  const n = network();
  n.stationById.get("one:code").name = bad;
  n.lineById.get("one").operator = bad;
  const model = c.RailMapPopup.buildPopupModel(n, "one:code", null, { detailed: true });
  model.details.validFrom = bad;
  const html = c.RailMapPopup.stationPopupHtml(model, { detailed: true });
  assert.ok(!html.includes(bad));
  assert.ok(html.includes("&lt;img src=x onerror=&quot;alert(1)&quot;&gt;&amp;"));
});

test("station clicks open a persistent closeable detail popup and suppress compact hover", () => {
  const c = setup();
  c.RailMapStyle = { STATIONS_LAYER: "stations" };
  c.RailMap = {};
  vm.runInContext(readFileSync(new URL("../public/railmap-interactions.js", import.meta.url), "utf8"), c);
  c.I18N.setStationReadings({ byCode: { code: { en: "Name" } } });
  let popup;
  c.maplibregl = { Popup: class {
    constructor(options) { this.options = options; popup = this; }
    setLngLat(value) { this.coordinate = value; return this; }
    setHTML(html) { this.html = html; return this; }
    addTo() { return this; }
    isOpen() { return true; }
  } };
  const manager = c.RailMap;
  manager._network = network();
  manager._map = {
    getLayer() { return true; }, getLayoutProperty() { return "visible"; },
    queryRenderedFeatures() { return [{ properties: { stationId: "one:code", lineId: "one" }, geometry: { coordinates: [121, 25] } }]; },
  };
  assert.equal(manager._openStationDetails({ x: 10, y: 20 }), true);
  assert.equal(popup.options.closeButton, true);
  assert.equal(popup.options.closeOnClick, false);
  assert.ok(popup.html.includes("rp-station-details"));
  manager._map.queryRenderedFeatures = () => { throw new Error("detail popup must suppress hover query"); };
  manager._maybeStationPopup({ x: 20, y: 30 });
});

test("standalone station details have readable labels and do not duplicate enabled readings", () => {
  const c = setup();
  c.I18N.setStationReadings({ byCode: { code: { kana: "かな" } } });
  c.I18N.setNameReadings({ kana: true });
  const model = c.RailMapPopup.buildPopupModel(network(), "one:code", null, { detailed: true });
  const html = c.RailMapPopup.stationPopupHtml(model, { detailed: true });
  assert.ok(!html.includes('class="rp-popup-roma"'));
  c.I18N = null;
  const standalone = c.RailMapPopup.stationPopupHtml(model, { detailed: true });
  assert.ok(standalone.includes("Station names"));
  assert.ok(standalone.includes("Station information"));
  assert.ok(standalone.includes("Lines"));
  assert.ok(!standalone.includes("popup.names"));
});

test("map clicks preserve ride selection priority and open network stations before background handling", () => {
  // Exercise the registered click body with its hit resolver supplied by the map harness.
  const source = readFileSync(new URL("../public/railmap-interactions.js", import.meta.url), "utf8");
  const start = source.indexOf('map.on("click", (e) => {');
  const end = source.indexOf('\n      });', start) + '\n      });'.length;
  let selected = 0, stationOpened = 0, background = 0, callback;
  const manager = {
    _handlers: { onClick() { selected++; }, onBackgroundClick() { background++; } },
    _openStationDetails() { stationOpened++; return true; },
  };
  const context = vm.createContext({
    map: { on(event, cb) { callback = cb; } }, self: manager,
    queryAt: () => ({ kind: "route", sticky: true, record: { id: "ride" } }),
    currentStickyTids: () => [], coarsePointer: { matches: false },
  });
  vm.runInContext(source.slice(start, end), context);
  callback({ point: {}, lngLat: { lng: 121, lat: 25 } });
  assert.equal(selected, 1);
  assert.equal(stationOpened, 0);
  context.queryAt = () => null;
  callback({ point: {}, lngLat: { lng: 121, lat: 25 } });
  assert.equal(stationOpened, 1);
  assert.equal(background, 0);
});

function loadStopPopups(c, net) {
  c.RailMap = { _network: net };
  c.STOP_TYPES = ["origin", "stop", "destination"];
  c.stationGroupCode = (feature) => feature.properties.n02_group_code || null;
  c.stationCodeFieldLabel = () => "StationUID";
  c.stationCodeSystem = () => "TDX";
  c.trainTypeCompanyLabel = () => "Express Company";
  c.getTrainDate = () => "2026-10-01";
  c.dateLabel = (s) => s;
  vm.runInContext(readFileSync(new URL("../public/app-ui-utils.js", import.meta.url), "utf8"), c);
}

test("clicked ridden stations include complete network names and lines while retaining train metadata", () => {
  const c = setup();
  c.I18N.setStationReadings({ country: "TW", byCode: { code: {
    zh_Hant: "原名", zh_Hans: "原名简", en: "Official Stop", ja: "駅名",
  } } });
  c.I18N.setNameReadings({ kana: false, romaji: false, zh: false });
  loadStopPopups(c, network());
  const feature = { type: "Feature", geometry: { type: "Point", coordinates: [121, 25] },
    properties: { name: "原名", n02_station_code: "code", n02_group_code: "code", arrival: "10:15", departure: "10:20", stop_type: "stop", source: "survey" } };
  const html = c.buildStopPopup(feature, { id: "ride-123", number: "Express 42", region: "tw" });
  for (const value of ["Official Stop", "English", "駅名", "Line A", "Line B", "Rail A", "Rail B", "10:15", "10:20", "Express 42", "ride-123", "survey"])
    assert.ok(html.includes(value), value);
  assert.ok(html.includes("rp-stop-details"));
  const hover = c.buildStationLinesPopup(feature.properties, {});
  assert.ok(!hover.includes("rp-station-details"));
  assert.ok(!hover.includes("Official Stop"));
});

test("unresolved ridden stops retain known names, coordinates and recorded line data without guessing lines", () => {
  const c = setup();
  c.I18N.setStationReadings({ country: "TW", byCode: { missing: { en: 'Known <Stop>', zh_Hant: "原名" } } });
  loadStopPopups(c, null);
  const feature = { geometry: { type: "Point", coordinates: [121, 25] }, properties: {
    name: "原名", n02_station_code: "missing", line_name: "Recorded Line", operator: "Recorded Operator", stop_type: "stop",
  } };
  const html = c.buildStopPopup(feature, { id: "manual-ride", region: "tw" });
  for (const value of ["Known &lt;Stop&gt;", "English", "25.000000, 121.000000", "missing", "Recorded Line", "Recorded Operator", "manual-ride"])
    assert.ok(html.includes(value), value);
  assert.ok(!html.includes("Line A"));
  assert.ok(!html.includes("Known <Stop>"));
  assert.equal(c.buildStationLinesPopup(feature.properties, {}), null);
});

test("detailed station names use exact composite identity before group or same-name fallback", () => {
  const c = setup();
  c.I18N.setStationReadings({ country: "HK", byCode: {
    "one:code": { en: "First official station" },
    "two:code": { en: "Second official station" },
  }, byName: { 原名: { en: "Ambiguous fallback" } } });
  const n = network();
  for (const [id, expected] of [["one:code", "First official station"], ["two:code", "Second official station"]]) {
    const model = c.RailMapPopup.buildPopupModel(n, id, null, { detailed: true });
    assert.equal(model.details.names[0].text, expected);
    assert.ok(!c.RailMapPopup.stationPopupHtml(model, { detailed: true }).includes("Ambiguous fallback"));
  }
  c.I18N.setStationReadings({ byCode: { code: { romaji: "Group reading" } },
    byName: { 原名: { romaji: "Wrong name fallback" } } });
  assert.equal(c.I18N.stationNames("原名", "one:code", "code")[0].text, "Group reading");
});
