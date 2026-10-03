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
  for (const country of ["jp", "tw", "hk", "mo", "kr"]) {
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
