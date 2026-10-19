import assert from "node:assert/strict";
import { test } from "node:test";

import { applyHistoryOverrides } from "./registry-history-crosswalk.mjs";
import {
  REVIEWED_BY,
  buildHistoryOverrides,
  buildLineGroups,
  buildOperatorAliases,
  buildStationFacilities,
} from "./registry-reviewed-inputs.mjs";

const SOURCE = ["https://example.test/source"];

test("line groups keep one official line, split collisions, and drop non-railways", () => {
  const doc = buildLineGroups([
    {
      key: "dup",
      decision: "one-line",
      groups: [{ lp: ["lp:jp:2", "lp:jp:1"], officialName: "函館線", operator: "北海道旅客鉄道" }],
      sources: SOURCE,
      note: "一路線",
    },
    {
      key: "dup",
      decision: "one-line",
      groups: [{ lp: ["lp:jp:9"], officialName: "函館線", operator: "北海道旅客鉄道" }],
      sources: ["https://example.test/ignored"],
      note: "ignored duplicate",
    },
    {
      key: "through",
      decision: "not-a-railway",
      groups: [{ lp: ["lp:jp:3"], officialName: "東北線", operator: "東日本旅客鉄道" }],
      sources: SOURCE,
      note: "運行系統",
    },
    {
      key: "later",
      decision: "unverified",
      groups: [{ lp: ["lp:jp:4"], officialName: "総武線", operator: "東日本旅客鉄道" }],
      sources: SOURCE,
      note: "未確認",
    },
    {
      key: "split",
      decision: "split",
      groups: [
        { lp: ["lp:jp:249"], officialName: "本線", operator: "富山地方鉄道" },
        { lp: ["lp:jp:248"], officialName: "本線", operator: "富山地方鉄道" },
      ],
      sources: SOURCE,
      note: "鉄道と軌道",
    },
  ]);
  assert.equal(doc.schema, "jtm-line-crosswalk/1");
  assert.deepEqual(doc.groups.map((group) => group.slug), [
    "jr-hokkaido/hakodate",
    "toyama-chiho/main",
    "toyama-chiho/main-2",
  ]);
  assert.deepEqual(doc.groups[0].lp, ["lp:jp:1", "lp:jp:2"]);
  assert.equal(doc.groups[0].why, "一路線");
  assert.equal(doc.groups[0].source, SOURCE[0]);
  assert.deepEqual(doc.groups[0].sources, SOURCE);
  assert.equal(doc.groups[0].reviewedBy, REVIEWED_BY);
  assert.deepEqual(doc.groups[1].lp, ["lp:jp:248"]);
  assert.deepEqual(doc.groups[2].lp, ["lp:jp:249"]);
});

test("facilities resolve companies, skip mixed links, and link only stations outside one facility", () => {
  const index = {
    nameToOp: new Map([
      ["JR東日本", "op:jp:1"],
      ["京王電鉄", "op:jp:2"],
      ["東武鉄道", "op:jp:3"],
      ["曖昧", null],
    ]),
    derivToSt: new Map([
      ["cx:jp:2|op:jp:1", "st:jp:2"],
      ["cx:jp:2|op:jp:2", "st:jp:3"],
      ["cx:jp:1|op:jp:1", "st:jp:1"],
      ["cx:jp:4|op:jp:1", null],
      ["cx:jp:8|op:jp:1", "st:jp:8"],
      ["cx:jp:8|op:jp:3", "st:jp:9"],
    ]),
    stationsByCx: new Map([
      ["cx:jp:2", new Set(["st:jp:3", "st:jp:2", "st:jp:4"])],
      ["cx:jp:1", new Set(["st:jp:1", "st:jp:5"])],
      ["cx:jp:3", new Set(["st:jp:6", "st:jp:7"])],
      ["cx:jp:8", new Set(["st:jp:10", "st:jp:8", "st:jp:9"])],
    ]),
  };
  const built = buildStationFacilities([
    {
      cx: "cx:jp:2",
      name: "新宿",
      decision: "shared-facility",
      sharedBy: ["京王電鉄", "JR東日本"],
      manager: "JR東日本",
      transfer: "mixed",
      sources: SOURCE,
      note: "改札が分かれる",
    },
    {
      cx: "cx:jp:1",
      name: "東京",
      decision: "separate-stations",
      sharedBy: [],
      manager: null,
      transfer: "street",
      sources: SOURCE,
      note: "離れている",
    },
    {
      cx: "cx:jp:3",
      name: "未確認",
      decision: "unverified",
      sharedBy: ["JR東日本"],
      manager: "JR東日本",
      transfer: "gate",
      sources: SOURCE,
      note: "保留",
    },
    {
      cx: "cx:jp:9",
      name: "不明",
      decision: "boundary",
      sharedBy: ["無い会社", "JR東日本"],
      manager: "JR東日本",
      transfer: "gate",
      sources: SOURCE,
      note: "解決できない",
    },
    {
      cx: "cx:jp:4",
      name: "曖昧駅",
      decision: "shared-facility",
      sharedBy: ["曖昧", "JR東日本"],
      manager: "JR東日本",
      transfer: "gate",
      sources: SOURCE,
      note: "名前が二つ",
    },
    {
      cx: "cx:jp:8",
      name: "北千住",
      decision: "boundary",
      sharedBy: ["東武鉄道", "JR東日本"],
      manager: "東武鉄道",
      transfer: "gate",
      sources: SOURCE,
      note: "外側の駅だけ連絡",
    },
  ], index);
  assert.equal(built.doc.schema, "jtm-station-facilities/1");
  assert.equal(built.doc.facilities.length, 2);
  assert.equal(built.doc.facilities[0].kind, "shared");
  assert.deepEqual(built.doc.facilities[0].stations, ["st:jp:2", "st:jp:3"]);
  assert.equal(built.doc.facilities[0].manager, "op:jp:1");
  assert.equal(built.doc.facilities[0].reviewedBy, REVIEWED_BY);
  assert.equal(built.doc.facilities[1].kind, "boundary");
  assert.equal(built.doc.facilities[1].manager, "op:jp:3");
  assert.deepEqual(built.doc.links.map((link) => [link.a, link.b, link.kind, link.cx]), [
    ["st:jp:1", "st:jp:5", "street_transfer", "cx:jp:1"],
    ["st:jp:8", "st:jp:10", "gate_transfer", "cx:jp:8"],
    ["st:jp:9", "st:jp:10", "gate_transfer", "cx:jp:8"],
  ]);
  assert.equal(built.doc.links.some((link) => link.cx === "cx:jp:2"), false);
  assert.equal(built.doc.links.some((link) => link.a === "st:jp:8" && link.b === "st:jp:9"), false);
  assert.deepEqual(built.report["facility-transfer-mixed"].map((row) => row.cx), ["cx:jp:2"]);
  assert.deepEqual(built.report["facility-unresolved"].map((row) => row.cx), ["cx:jp:4", "cx:jp:9"]);
});

test("aliases keep a single operator and multiple stays a joint label", () => {
  const doc = buildOperatorAliases({
    companies: [
      { company: "都営地下鉄", decision: "alias", ops: ["op:jp:103"], sources: SOURCE, note: "東京都交通局" },
      { company: "JR九州/JR西日本", decision: "multiple", ops: ["op:jp:147", "op:jp:30"], sources: SOURCE, note: "併記" },
      { company: "謎", decision: "unknown", ops: ["op:jp:1"], sources: SOURCE, note: "不明" },
    ],
  });
  assert.equal(doc.schema, "jtm-operator-aliases/1");
  assert.deepEqual(doc.aliases, [{
    text: "都営地下鉄", op: "op:jp:103", sources: SOURCE, note: "東京都交通局", reviewedBy: REVIEWED_BY,
  }]);
  assert.deepEqual(doc.multiple[0].ops, ["op:jp:30", "op:jp:147"]);
  assert.equal(doc.multiple[0].text, "JR九州/JR西日本");
});

test("history overrides keep only dated strings from a fix", () => {
  const doc = buildHistoryOverrides({
    history: [
      {
        history_id: "keep",
        decision: "keep-unresolved",
        lp: ["lp:jp:1"],
        op: "op:jp:1",
        valid_from: "2001-01-01",
        valid_to: null,
        sources: SOURCE,
        note: "残す",
      },
      {
        history_id: "fix",
        decision: "fix",
        lp: ["lp:jp:9", "lp:jp:8"],
        op: "op:jp:6",
        valid_from: "2015-03-14",
        valid_to: null,
        sources: SOURCE,
        note: "移管",
      },
    ],
  });
  assert.equal(doc.overrides.length, 1);
  assert.equal("valid_to" in doc.overrides[0], false);
  assert.equal(doc.overrides[0].valid_from, "2015-03-14");
  assert.deepEqual(doc.overrides[0].lp, ["lp:jp:8", "lp:jp:9"]);
  assert.equal(doc.overrides[0].reviewedBy, REVIEWED_BY);
  const applied = applyHistoryOverrides({
    schema: "jtm-history-crosswalk/1",
    entries: [{
      history_id: "fix",
      kind: "identity_period",
      match: { line_name: "日本海ひすいライン", operator: "えちごトキめき鉄道", bbox: [1, 2, 3, 4] },
      valid_to: "2015-03-14",
      lp: ["lp:jp:8"],
      op: "op:jp:1",
      status: "multiple",
    }, {
      history_id: "keep",
      kind: "identity_period",
      match: { line_name: "線", operator: "社", bbox: [] },
      lp: [],
      op: null,
      status: "unmatched",
    }],
  }, doc);
  assert.equal(applied.reviewed, 1);
  assert.equal(applied.doc.entries[0].status, "reviewed");
  assert.equal(applied.doc.entries[0].valid_from, "2015-03-14");
  assert.equal(applied.doc.entries[0].valid_to, "2015-03-14");
  assert.equal(applied.doc.entries[0].op, "op:jp:6");
  assert.deepEqual(applied.doc.entries[0].lp, ["lp:jp:8", "lp:jp:9"]);
  assert.deepEqual(applied.doc.entries[0].match.bbox, [1, 2, 3, 4]);
  assert.equal(applied.doc.entries[1].status, "unmatched");
  assert.deepEqual(Object.keys(applied.doc.entries[0]), [
    "history_id", "kind", "match", "valid_from", "valid_to", "lp", "op", "status",
  ]);
});
