import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  assertCurrentPrecomputeSolverContext,
  currentPrecomputeSolverContext,
  deriveManifestSolverContext,
  readPrecomputeHistoryOverlay,
} from "../scripts/build/precompute-train-parts.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const EXAMPLE_HISTORY_HASH = "a".repeat(64);

function context(overrides = {}) {
  return {
    solver_version: "22",
    route_cache_digest: "abc123",
    ride_date: "2026-07-03",
    history_revisions: { jp: "2026-09-23.2" },
    history_hashes: { jp: EXAMPLE_HISTORY_HASH },
    ...overrides,
  };
}

test("manifest solver provenance is derived from consistent route parts", () => {
  assert.deepEqual(
    deriveManifestSolverContext([
      context(),
      context({ route_cache_digest: "different", ride_date: null }),
    ]),
    {
      solver_version: "22",
      history_revisions: { jp: "2026-09-23.2" },
      history_hashes: { jp: EXAMPLE_HISTORY_HASH },
    },
  );
});

test("manifest solver provenance rejects corrupt part contexts", () => {
  assert.throws(() => deriveManifestSolverContext([null]), /missing or invalid/);
  assert.throws(
    () => deriveManifestSolverContext([context({ route_cache_digest: "" })]),
    /route_cache_digest/,
  );
  assert.throws(
    () => deriveManifestSolverContext([context({ ride_date: "2026/07/03" })]),
    /ride_date/,
  );
  assert.throws(
    () => deriveManifestSolverContext([context({ history_revisions: { jp: "" } })]),
    /history_revisions/,
  );
  assert.throws(
    () => deriveManifestSolverContext([context({ history_hashes: {} })]),
    /history_hashes/,
  );
  assert.throws(
    () => deriveManifestSolverContext([context({ history_hashes: { jp: "not-sha256" } })]),
    /history_hashes/,
  );
});

test("manifest solver provenance rejects version and history mismatches", () => {
  assert.throws(
    () => deriveManifestSolverContext([context(), context({ solver_version: "23" })]),
    /disagrees/,
  );
  assert.throws(
    () =>
      deriveManifestSolverContext([
        context(),
        context({
          history_revisions: { jp: "2026-09-24.1" },
          history_hashes: { jp: "b".repeat(64) },
        }),
      ]),
    /disagrees/,
  );
  assert.throws(
    () => deriveManifestSolverContext([
      context(),
      context({ history_hashes: { jp: "b".repeat(64) } }),
    ]),
    /disagrees/,
  );
});

test("manifest provenance must match the current shipped solver and history overlay", () => {
  const current = currentPrecomputeSolverContext();
  const shippedOverlayPath = path.join(HERE, "..", "data", "rail-history.json");
  const shippedOverlayBytes = fs.readFileSync(shippedOverlayPath);
  const shippedOverlay = JSON.parse(shippedOverlayBytes.toString("utf8"));
  assert.deepEqual(current, {
    solver_version: "24",
    history_revisions: { jp: shippedOverlay.revision },
    history_hashes: {
      jp: createHash("sha256").update(shippedOverlayBytes).digest("hex"),
    },
  });
  assert.equal(assertCurrentPrecomputeSolverContext(current), current);
  assert.throws(
    () => assertCurrentPrecomputeSolverContext(
      { ...current, solver_version: "21" },
      current,
    ),
    /provenance is stale/,
  );
  assert.throws(
    () => assertCurrentPrecomputeSolverContext(
      { ...current, history_revisions: { jp: "2026-09-23.1" } },
      current,
    ),
    /provenance is stale/,
  );
  assert.throws(
    () => assertCurrentPrecomputeSolverContext({
      solver_version: current.solver_version,
      history_revisions: { jp: `${current.history_revisions.jp}-stale` },
    }),
    /provenance is stale/,
  );
});

test("a part route with no solver_context fails when the overlay revision is real", () => {
  const current = currentPrecomputeSolverContext();
  assert.notEqual(current.history_revisions.jp, "none");
  assert.throws(
    () => deriveManifestSolverContext([null]),
    /missing or invalid/,
  );
});

test("corrupt history overlay content fails the precompute load", () => {
  const base = {
    schema_version: "1",
    revision: "r",
    sections: [],
    stations: [],
    retirements: [],
  };
  assert.throws(() =>
    readPrecomputeHistoryOverlay(JSON.stringify({ ...base, schema_version: "2" })),
  );
  assert.throws(() =>
    readPrecomputeHistoryOverlay(JSON.stringify({ ...base, revision: " " })),
  );
  assert.throws(() =>
    readPrecomputeHistoryOverlay(JSON.stringify({
      ...base,
      sections: [{
        properties: { history_id: "x", valid_to: "2019-02-29" },
      }],
    })),
  );
  assert.throws(() =>
    readPrecomputeHistoryOverlay(JSON.stringify({
      ...base,
      retirements: [{
        history_id: "bad-bbox",
        valid_to: "2020-01-01",
        match: { line_name: "L", operator: "O", bbox: [140, 30, 130, 40] },
      }],
    })),
  );
  assert.throws(() => readPrecomputeHistoryOverlay("{"));
});

test("published sample manifest must carry the current overlay revision", () => {
  const manifest = JSON.parse(
    fs.readFileSync(path.join(HERE, "..", "data", "sample-data", "manifest.json"), "utf8"),
  );
  const current = currentPrecomputeSolverContext();
  const revision = manifest.solver_context?.history_revisions?.jp;
  assert.equal(
    revision,
    current.history_revisions.jp,
    "rerun `npm run precompute` from app/",
  );
  assert.deepEqual(
    manifest.solver_context?.history_hashes,
    current.history_hashes,
    "rerun `npm run precompute` from app/",
  );
});
