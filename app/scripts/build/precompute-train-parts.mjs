// Precompute per-train route geometry OFFLINE and emit the train store as
// per-train "part" files, so the browser (critically: iPhone Safari, which
// kills the tab on memory pressure) never has to build the 600k-node route
// graphs or run Dijkstra during the initial page load.
//
// How it stays byte-identical to the client: instead of reimplementing the
// solver, this script evaluates the REAL frontend scripts (the ordered
// app-*.js family listed in app/public/index.html) inside a Node `vm`
// context with just enough browser stubs, feeds it the same datasets the
// browser would fetch, appends each train through the same
// parseImportedCanonicalStore/appendImportedTrain normalization the boot path
// uses, and runs the same streaming route solve. The cached template features
// + cache key are then exported per train. At boot the frontend seeds
// runtimeRouteCache with each part's entry, so
// prepareTrainRouteSolve() is a pure cache hit and no graph is ever built.
//
// Output (all under app/data/sample-data/ — the published SAMPLE dataset):
//   manifest.json  { format, schema_version, total, parts: ["part-000", ...],
//                    dates: { "2026-07-03": ["part-000", ...], ... } }
//   part-NNN.json  { format, train: <raw train from train-store.json>,
//                    route: null | { cache_key, solver_context, features } |
//                                  { cache_key, solver_context, unsolvable: true } }
//
// Every train is its own file, and the manifest's `dates` map groups the part
// names by calendar day (trains without a date land under ""), so the static
// frontend can load a single random day's sample on boot and the full sample
// only on explicit request.
//
// Run:  node app/scripts/build/precompute-train-parts.mjs
// Alternate store/output:
//   PRECOMPUTE_STORE=data/special-samples/example.json
//   PRECOMPUTE_OUT_DIR=data/example-parts node scripts/build/precompute-train-parts.mjs
// (No dependencies; used by the GitHub Pages deploy workflow on every push.)

import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import {
  evaluateAppScripts,
  makeSandbox,
  readOrderedAppScripts,
} from "../lib/app-family-sandbox.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const APP_DIR = path.join(__dirname, "..", "..");
const DATA_DIR = path.join(APP_DIR, "data");
const STORE_PATH = process.env.PRECOMPUTE_STORE
  ? path.resolve(process.cwd(), process.env.PRECOMPUTE_STORE)
  : path.join(DATA_DIR, "train-store.json");
const OUT_DIR = process.env.PRECOMPUTE_OUT_DIR
  ? path.resolve(process.cwd(), process.env.PRECOMPUTE_OUT_DIR)
  : path.join(DATA_DIR, "sample-data");
// Which country's store is being precomputed. The solver datasets are
// per-country and MUST match the store: feeding Taiwanese stops to the
// Japanese network is precisely the cross-country solve the app refuses to do
// at runtime, and offline it would silently bake wrong-country geometry into
// the published parts. Japan stays the default so every existing invocation
// is unchanged.
const SUPPORTED_COUNTRIES = new Set(["jp", "tw", "hk", "mo", "kr"]);
const requestedCountry = process.env.PRECOMPUTE_COUNTRY || "jp";
const COUNTRY = SUPPORTED_COUNTRIES.has(requestedCountry)
  ? requestedCountry
  : "jp";
const suffix = COUNTRY === "jp" ? "" : `-${COUNTRY}`;
const RAIL_SECTIONS_FILE = `rail-sections${suffix}.json`;
const STATIONS_FILE = `stations${suffix}.json`;
const RAIL_HISTORY_FILE = `rail-history${suffix}.json`;

const readJson = (p) => JSON.parse(fs.readFileSync(p, "utf8"));

let validateRailHistoryOverlay = null;
function precomputeHistoryValidator() {
  if (validateRailHistoryOverlay) return validateRailHistoryOverlay;
  const source = fs.readFileSync(
    path.join(APP_DIR, "public", "app-rail-history.js"),
    "utf8",
  );
  const context = vm.createContext({ console });
  vm.runInContext(source, context);
  validateRailHistoryOverlay = context.validateRailHistoryOverlay;
  if (typeof validateRailHistoryOverlay !== "function") {
    throw new Error("app-rail-history.js did not publish validateRailHistoryOverlay");
  }
  return validateRailHistoryOverlay;
}

// The overlay main hands to PrecomputeAdapter. A corrupt file aborts the
// build here, before any train is solved.
export function readPrecomputeHistoryOverlay(text) {
  const json = JSON.parse(text);
  precomputeHistoryValidator()(json);
  return json;
}

// ---------------------------------------------------------------------------
// Driver — calls the frontend's named adapter. The VM remains the deployment-
// compatible classic-script runtime, but the build tool no longer reaches into
// arbitrary lexical bindings.
// ---------------------------------------------------------------------------
const DRIVER_SOURCE = `
globalThis.PrecomputeAdapter.solveStore(__host)
`;

export function deriveManifestSolverContext(contexts) {
  let manifestContext = null;
  for (let index = 0; index < contexts.length; index += 1) {
    const context = contexts[index];
    const label = `route solver context ${index}`;
    if (!context || typeof context !== "object" || Array.isArray(context))
      throw new Error(`${label} is missing or invalid`);
    if (typeof context.solver_version !== "string" || !context.solver_version.trim())
      throw new Error(`${label} has no solver_version`);
    if (
      typeof context.route_cache_digest !== "string" ||
      !context.route_cache_digest.trim()
    )
      throw new Error(`${label} has no route_cache_digest`);
    if (
      context.ride_date !== null &&
      (typeof context.ride_date !== "string" ||
        !/^\d{4}-\d{2}-\d{2}$/.test(context.ride_date))
    )
      throw new Error(`${label} has an invalid ride_date`);
    if (
      !context.history_revisions ||
      typeof context.history_revisions !== "object" ||
      Array.isArray(context.history_revisions)
    )
      throw new Error(`${label} has no history_revisions`);
    const historyEntries = Object.entries(context.history_revisions).sort(
      ([a], [b]) => a.localeCompare(b),
    );
    if (
      !historyEntries.length ||
      historyEntries.some(
        ([code, revision]) =>
          !code || typeof revision !== "string" || !revision.trim(),
      )
    )
      throw new Error(`${label} has invalid history_revisions`);
    const candidate = {
      solver_version: context.solver_version,
      history_revisions: Object.fromEntries(historyEntries),
    };
    if (!manifestContext) manifestContext = candidate;
    else if (JSON.stringify(manifestContext) !== JSON.stringify(candidate))
      throw new Error(`${label} disagrees with the manifest solver context`);
  }
  return manifestContext;
}

export function currentPrecomputeSolverContext({
  country = COUNTRY,
  dataDir = DATA_DIR,
  appConfigPath = path.join(APP_DIR, "public", "app-config.js"),
} = {}) {
  const configSource = fs.readFileSync(appConfigPath, "utf8");
  const versionMatch = configSource.match(
    /const\s+ROUTE_SOLVER_CACHE_VERSION\s*=\s*["']([^"']+)["']/,
  );
  if (!versionMatch)
    throw new Error("Cannot read ROUTE_SOLVER_CACHE_VERSION from app-config.js");
  const historySuffix = country === "jp" ? "" : `-${country}`;
  const historyPath = path.join(dataDir, `rail-history${historySuffix}.json`);
  const revision = fs.existsSync(historyPath)
    ? readJson(historyPath)?.revision
    : "none";
  if (typeof revision !== "string" || !revision.trim())
    throw new Error(`${path.basename(historyPath)} has no revision`);
  return {
    solver_version: versionMatch[1],
    history_revisions: { [country]: revision },
  };
}

export function assertCurrentPrecomputeSolverContext(
  actual,
  expected = currentPrecomputeSolverContext(),
) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Precomputed route provenance is stale: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
  return actual;
}

// Assemble manifest.json from already-emitted part files (used after sliced
// runs; see PRECOMPUTE_RANGE below). Validates that every train in the store
// has its part on disk, in order.
function finalizeManifestFromParts() {
  const store = JSON.parse(
    fs.readFileSync(STORE_PATH, "utf8"),
  );
  const partNames = [];
  const partsByDate = new Map();
  let solvedCount = 0;
  let unsolvableCount = 0;
  let noRouteCount = 0;
  const routeSolverContexts = [];
  for (let i = 0; i < store.trains.length; i += 1) {
    const name = `part-${String(i).padStart(3, "0")}`;
    const part = JSON.parse(
      fs.readFileSync(path.join(OUT_DIR, `${name}.json`), "utf8"),
    );
    partNames.push(name);
    const dateKey =
      part.train && typeof part.train.date === "string" ? part.train.date : "";
    if (!partsByDate.has(dateKey)) partsByDate.set(dateKey, []);
    partsByDate.get(dateKey).push(name);
    if (!part.route) noRouteCount += 1;
    else {
      routeSolverContexts.push(part.route.solver_context);
      if (part.route.unsolvable) unsolvableCount += 1;
      else solvedCount += 1;
    }
  }
  if (solvedCount === 0)
    throw new Error("No train solved — refusing to publish empty parts.");
  const solverContext = deriveManifestSolverContext(routeSolverContexts);
  assertCurrentPrecomputeSolverContext(solverContext);
  const manifest = {
    format: 1,
    schema_version: store.schema_version || "1.3",
    total: store.trains.length,
    solved: solvedCount,
    unsolvable: unsolvableCount,
    no_route: noRouteCount,
    solver_context: solverContext,
    parts: partNames,
    full: "sample-full",
    dates: Object.fromEntries(
      [...partsByDate.entries()].sort(([a], [b]) => a.localeCompare(b)),
    ),
  };
  fs.writeFileSync(
    path.join(OUT_DIR, "manifest.json"),
    JSON.stringify(manifest, null, 2),
  );
  // Keep one combined big JSON of the whole sample next to the chunks.
  fs.writeFileSync(
    path.join(OUT_DIR, "sample-full.json"),
    fs.readFileSync(STORE_PATH),
  );
  console.log(
    `Finalized manifest for ${store.trains.length} parts (${solvedCount} solved, ${unsolvableCount} unsolvable, ${noRouteCount} without route sections).`,
  );
}

// Move a fully written staging directory onto the published path. Two renames
// rather than one: the previous set stays complete and readable right up to
// the swap, and the only moment the published path does not exist is the gap
// between two renames instead of the length of a whole solve.
function publishStagedOutput(stagingDir) {
  const previousDir = `${OUT_DIR}.previous`;
  fs.rmSync(previousDir, { recursive: true, force: true });
  if (fs.existsSync(OUT_DIR)) fs.renameSync(OUT_DIR, previousDir);
  fs.renameSync(stagingDir, OUT_DIR);
  fs.rmSync(previousDir, { recursive: true, force: true });
}

async function main() {
  // Finalize-only mode: build the manifest from parts emitted by sliced runs.
  if (process.env.PRECOMPUTE_FINALIZE) {
    finalizeManifestFromParts();
    return;
  }

  const started = performance.now();
  console.log("Loading datasets...");
  console.log(`Country: ${COUNTRY} (${RAIL_SECTIONS_FILE}, ${STATIONS_FILE}).`);
  const railSections = readJson(path.join(DATA_DIR, RAIL_SECTIONS_FILE));
  const stations = readJson(path.join(DATA_DIR, STATIONS_FILE));
  const historyPath = path.join(DATA_DIR, RAIL_HISTORY_FILE);
  const historyOverlays = fs.existsSync(historyPath)
    ? { [COUNTRY]: readPrecomputeHistoryOverlay(fs.readFileSync(historyPath, "utf8")) }
    : {};
  const matchedStops = readJson(path.join(DATA_DIR, "matched-stops.json"));
  // Curated per-train geometry — the offline fallback for trains the solver
  // cannot route (see the unsolvable branch in the driver).
  const matchedRoutes = readJson(path.join(DATA_DIR, "matched-routes.json"));
  let trainStoreText = fs.readFileSync(
    STORE_PATH,
    "utf8",
  );

  // Optional slice mode: PRECOMPUTE_RANGE="start:end" (end-exclusive train
  // indexes) solves only that window and APPENDS its parts into OUT_DIR
  // without touching the rest. Useful for memory/time-boxed environments;
  // run PRECOMPUTE_FINALIZE=1 once afterwards to write the manifest. The
  // default (no env) behaviour — fresh dir, full store, manifest — is
  // unchanged, and is what CI uses.
  const rangeEnv = process.env.PRECOMPUTE_RANGE || "";
  let sliceStart = 0;
  if (rangeEnv) {
    const match = rangeEnv.match(/^(\d+):(\d+)$/);
    if (!match)
      throw new Error('PRECOMPUTE_RANGE must look like "0:20" (end-exclusive).');
    sliceStart = Number(match[1]);
    const sliceEnd = Number(match[2]);
    const full = JSON.parse(trainStoreText);
    trainStoreText = JSON.stringify({
      ...full,
      trains: full.trains.slice(sliceStart, sliceEnd),
    });
    console.log(
      `Slice mode: trains ${sliceStart}..${Math.min(sliceEnd, full.trains.length)} of ${full.trains.length}.`,
    );
  }

  const context = makeSandbox({
    userAgent: "node-precompute",
    fetchErrorMessage: "fetch is not available in the precompute sandbox",
  });
  const appScripts = readOrderedAppScripts();
  console.log(
    `Evaluating the app script family in sandbox (${appScripts.length} files)...`,
  );
  evaluateAppScripts(context, appScripts);

  // Publishing is a SWAP, not an in-place rewrite. Emptying the live
  // directory and then writing parts one at a time leaves it observably
  // half-published for the minutes a full solve takes — a fresh rail package
  // beside stale routes, or a sample directory holding a single part — and a
  // mid-run failure left it that way for good. Solve into a sibling staging
  // directory and move it into place only once the complete set (parts,
  // manifest, full store) is on disk. Slice mode is deliberately incremental
  // ACROSS processes, so it keeps appending into the live directory and
  // publishes when PRECOMPUTE_FINALIZE writes the manifest.
  const stagingDir = `${OUT_DIR}.staging`;
  const writeDir = rangeEnv ? OUT_DIR : stagingDir;
  if (!rangeEnv) fs.rmSync(stagingDir, { recursive: true, force: true });
  fs.mkdirSync(writeDir, { recursive: true });

  const partNames = [];
  // date string ("" for undated trains) -> part names for that day, in store order.
  const partsByDate = new Map();
  let solvedCount = 0;
  let unsolvableCount = 0;
  let noRouteCount = 0;
  const routeSolverContexts = [];

  context.__host = {
    country: COUNTRY,
    railSections,
    stations,
    matchedStops,
    matchedRoutes,
    historyOverlays,
    trainStoreText,
    onTrainSolved({ index, id, raw, route, featureCount, ms }) {
      const name = `part-${String(sliceStart + index).padStart(3, "0")}`;
      partNames.push(name);
      const dateKey = typeof raw.date === "string" ? raw.date : "";
      if (!partsByDate.has(dateKey)) partsByDate.set(dateKey, []);
      partsByDate.get(dateKey).push(name);
      if (!route) noRouteCount += 1;
      else {
        routeSolverContexts.push(route.solver_context);
        if (route.unsolvable) unsolvableCount += 1;
        else solvedCount += 1;
      }
      fs.writeFileSync(
        path.join(writeDir, `${name}.json`),
        JSON.stringify({ format: 1, train: raw, route }),
      );
      console.log(
        `  [${index + 1}] ${id}: ${
          route ? (route.unsolvable ? "UNSOLVABLE" : `${featureCount} feature(s)`) : "no route sections"
        } (${ms} ms)`,
      );
    },
  };

  console.log("Solving trains...");
  const summary = await vm.runInContext(DRIVER_SOURCE, context, {
    filename: "precompute-driver.js",
  });

  if (partNames.length !== summary.total) {
    throw new Error(
      `Emitted ${partNames.length} parts for ${summary.total} trains — aborting.`,
    );
  }

  const solverContext = deriveManifestSolverContext(routeSolverContexts);
  assertCurrentPrecomputeSolverContext(solverContext);
  if (JSON.stringify(solverContext) !== JSON.stringify(summary.solverContext)) {
    throw new Error(
      "Route parts disagree with the precompute adapter's manifest solver context.",
    );
  }

  if (!rangeEnv) {
    const manifest = {
      format: 1,
      schema_version: summary.schemaVersion || "1.3",
      total: summary.total,
      solved: solvedCount,
      unsolvable: unsolvableCount,
      no_route: noRouteCount,
      solver_context: solverContext,
      parts: partNames,
      full: "sample-full",
      dates: Object.fromEntries(
        [...partsByDate.entries()].sort(([a], [b]) => a.localeCompare(b)),
      ),
    };
    fs.writeFileSync(
      path.join(writeDir, "manifest.json"),
      JSON.stringify(manifest, null, 2),
    );
    // Alongside the per-train chunks, keep ONE combined file with the whole
    // sample store (no geometry — same shape a user would import/export), so
    // the complete sample also exists as a single big JSON.
    fs.writeFileSync(path.join(writeDir, "sample-full.json"), trainStoreText);
  }

  const bytes = partNames.reduce(
    (sum, name) => sum + fs.statSync(path.join(writeDir, `${name}.json`)).size,
    0,
  );
  // Guard BEFORE publishing, not after: an empty solve must leave the
  // currently published sample untouched rather than replace it and then
  // report the failure.
  if (solvedCount === 0) {
    throw new Error("No train solved — refusing to publish empty parts.");
  }
  if (!rangeEnv) publishStagedOutput(stagingDir);
  console.log(
    `\nDone in ${Math.round((performance.now() - started) / 1000)} s: ${summary.total} trains ` +
      `(${solvedCount} solved, ${unsolvableCount} unsolvable, ${noRouteCount} without route sections), ` +
      `${(bytes / 1024 / 1024).toFixed(1)} MB of parts in ${path.relative(process.cwd(), OUT_DIR)}.`,
  );
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main().catch((err) => {
    console.error("\nprecompute-train-parts FAILED:", err);
    // The published sample is intact (nothing is swapped in until the whole set
    // is written), so only the half-solved staging directory needs clearing.
    fs.rmSync(`${OUT_DIR}.staging`, { recursive: true, force: true });
    process.exit(1);
  });
}
