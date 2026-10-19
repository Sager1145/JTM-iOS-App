import assert from "node:assert/strict";
import { test } from "node:test";

import { identityFor } from "./export-registry-bundle.mjs";
import { searchFold } from "./search-fold.mjs";

test("searchFold matches the SearchFold rules used for operator identity", () => {
  assert.equal(searchFold("JR East"), "jreast");
  assert.equal(searchFold("JR-East"), searchFold("JR East"));
  assert.equal(searchFold("ＪＲ東日本"), searchFold("JR東日本"));
  assert.equal(searchFold("東日本旅客鉄道"), "东日本旅客铁道");
  assert.equal(searchFold("西日本旅客鐵道"), "西日本旅客铁道");
  assert.equal(searchFold("Café"), "cafe");
  assert.equal(searchFold("線 1 2"), "线1 2");
});

test("identityFor is unique or null", () => {
  const entries = [
    { code: "jp.jr-east", folded: new Set([searchFold("JR東日本"), searchFold("JR East")]) },
    { code: "jp.jr-west", folded: new Set([searchFold("JR西日本")]) },
    { code: "jp.other", folded: new Set([searchFold("JR East")]) },
  ];
  assert.equal(identityFor(["JR東日本", "JR東"], entries), "jp.jr-east");
  assert.equal(identityFor(["JR East"], entries), null);
  assert.equal(identityFor(["架空鉄道"], entries), null);
  assert.equal(identityFor([], entries), null);
});
