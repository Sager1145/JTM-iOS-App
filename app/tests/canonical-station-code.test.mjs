import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";

import {
  evaluateAppScripts,
  makeSandbox,
} from "../scripts/lib/app-family-sandbox.mjs";

// ADR 0010: legacy HK/MO platform codes map to `{OPERATOR}-{STOP}`.
function loadCanonical() {
  const context = makeSandbox();
  evaluateAppScripts(context);
  return vm.runInContext("canonicalStationCode", context);
}

test("canonicalStationCode maps legacy HK/MO shapes and passes others through", () => {
  const canonical = loadCanonical();
  assert.equal(canonical("AEL-MTR-HOK"), "MTR-HOK");
  assert.equal(canonical("TKL-POA-MTR-NOP"), "MTR-NOP");
  assert.equal(canonical("EAL-LOW-MTR-ADM"), "MTR-ADM");
  assert.equal(canonical("LR-505-LR-100"), "LR-100");
  assert.equal(canonical("LR-614P-LR-1"), "LR-1");
  assert.equal(canonical("TRAM-NP-65E"), "TRAM-65E");
  assert.equal(canonical("TRAM-HV-105"), "TRAM-105");
  assert.equal(canonical("MLM-TAIPA-MLM-BARRA"), "MLM-BARRA");
  assert.equal(canonical("KLRT-NETWORK-C1"), "KLRT-C1");
  assert.equal(canonical("KLRT-NETWORK-C21A"), "KLRT-C21A");
  for (const code of ["MTR-ADM", "LR-100", "TRAM-105", "MLM-BARRA", "003700",
    "TRA-0920", "TRTC-R22", "KLRT-C1", "KR-GYEONGBUSEON-SEOUL", "", null, undefined]) {
    assert.equal(canonical(code), code);
  }
});

test("stop and feature code readers return the canonical code", () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const stopStationCode = vm.runInContext("stopStationCode", context);
  const stationCode = vm.runInContext("stationCode", context);
  assert.equal(stopStationCode({ n02_station_code: "ISL-MTR-ADM" }), "MTR-ADM");
  assert.equal(stopStationCode({ N02_005c: "003700" }), "003700");
  assert.equal(stopStationCode({}), null);
  assert.equal(stationCode({ properties: { n02_station_code: "TRAM-HV-105" } }), "TRAM-105");
});

test("canonicalStopShape writes the canonical station code", () => {
  const context = makeSandbox();
  evaluateAppScripts(context);
  const canonicalStopShape = vm.runInContext("canonicalStopShape", context);
  const stop = canonicalStopShape({ name: "金鐘", n02_station_code: "EAL-LOW-MTR-ADM" });
  assert.equal(stop.n02_station_code, "MTR-ADM");
  assert.equal(canonicalStopShape({ name: "x" }).n02_station_code, null);
});
