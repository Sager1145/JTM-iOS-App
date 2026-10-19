import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { readFileSync } from "node:fs";

// Exercise the actual country resolver used by boot and country switches.
test("station naming loads the joined tables for every country scope", () => {
  const context = vm.createContext({ console, window: {}, performance });
  context.window = context;
  context.RailMapStyle = { RAILWAY_STYLE: { riddenWidthPx: 4 } };
  for (const file of ["../shared/app-core.js", "../public/app-config.js"])
    vm.runInContext(readFileSync(new URL(file, import.meta.url), "utf8"), context);
  for (const country of ["jp", "tw", "hk", "mo", "kr", "cn"]) {
    const resources = vm.runInContext(`stationReadingsApisForCountry("${country}")`, context);
    const expected = [country === "jp" ? "station-names" : `station-names-${country}`];
    assert.deepEqual(Array.from(resources), expected);
  }
});

test("shipped Japanese homonyms retain their own published readings and English", () => {
  const context = vm.createContext({
    document: { readyState: "loading", documentElement: {}, addEventListener() {}, querySelectorAll() { return []; }, getElementById() { return null; } },
    localStorage: { getItem() { return null; } },
  });
  context.window = context;
  for (const file of ["../shared/app-core.js", "../public/i18n-strings.js", "../public/i18n.js"])
    vm.runInContext(readFileSync(new URL(file, import.meta.url), "utf8"), context);
  const table = JSON.parse(readFileSync(new URL("../data/station-names.json", import.meta.url), "utf8"));
  context.I18N.setStationReadings(table);
  context.I18N.setNameReadings({ kana: true, romaji: true, zh: true });
  const rows = Object.entries(table.byCode).filter(([key, row]) => key.includes(":") && row.name === "上道");
  assert.ok(rows.length >= 2);
  assert.deepEqual(new Set(rows.map(([, row]) => row.kana)), new Set(["あがりみち", "じょうとう"]));
  for (const [key, row] of rows) {
    const names = Array.from(context.I18N.stationNames(row.name, key));
    assert.equal(names.find((n) => n.kind === "en").text, row.en);
    assert.equal(names.find((n) => n.kind === "kana").text, row.kana);
    assert.ok(context.I18N.nameReadingsList(row.name, key).includes(row.kana));
  }
  assert.equal(context.I18N.stationNames("上道", "missing-station").length, 0);
});

test("shipped Taiwan transfer platforms use line-specific English names", () => {
  const context = vm.createContext({
    document: { readyState: "loading", documentElement: {}, addEventListener() {}, querySelectorAll() { return []; }, getElementById() { return null; } },
    localStorage: { getItem() { return null; } },
  });
  context.window = context;
  for (const file of ["../shared/app-core.js", "../public/i18n-strings.js", "../public/i18n.js"])
    vm.runInContext(readFileSync(new URL(file, import.meta.url), "utf8"), context);
  const table = JSON.parse(readFileSync(new URL("../data/station-names-tw.json", import.meta.url), "utf8"));
  context.I18N.setStationReadings(table);
  context.I18N.setLang("en");
  const catalog = JSON.parse(readFileSync(new URL("../data/station-english.json", import.meta.url), "utf8"));
  const varying = Object.entries(catalog.byCountry.tw.byCode).find(([, row]) => row.enVariants.length > 1);
  assert.ok(varying);
  for (const member of varying[1].memberships)
    assert.equal(context.I18N.stationName(member.name, `${member.lineId}:${varying[0]}`), member.en);
});


test("China uses its localized station names and country strings", () => {
  const context = vm.createContext({
    document: { readyState: "loading", documentElement: {}, addEventListener() {}, querySelectorAll() { return []; }, getElementById() { return null; } },
    localStorage: { getItem() { return null; } },
  });
  context.window = context;
  for (const file of ["../shared/app-core.js", "../public/i18n-strings.js", "../public/i18n.js"])
    vm.runInContext(readFileSync(new URL(file, import.meta.url), "utf8"), context);
  context.I18N.setCountry("cn");
  context.I18N.setStationReadings({country:"CN", byCode:{"CN-12306-XJA": {
    name:"香港西九龙", zh_Hant:"香港西九龍", zh_Hans:"香港西九龙", en:"Hong Kong West Kowloon", ja:""}}, byName:{}});
  const cases = [
    ["zh-Hant", "香港西九龍", "中國", "高速鐵路"],
    ["zh-Hans", "香港西九龙", "中国", "高速铁路"],
    ["ja", "香港西九龍", "中国", "高速鉄道"],
    ["en", "Hong Kong West Kowloon", "China", "High speed rail"],
  ];
  for (const [lang, station, country, hsr] of cases) {
    context.I18N.setLang(lang);
    assert.equal(context.I18N.stationName("香港西九龙", "CN-12306-XJA"), station);
    assert.equal(context.I18N.t("country.cn"), country);
    assert.equal(context.I18N.tc("stat.hsr"), hsr);
  }
});
