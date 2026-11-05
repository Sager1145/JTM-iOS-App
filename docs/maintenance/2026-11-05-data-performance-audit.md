# Data-handling performance audit — 2026-11-05

Scope: bundled package and registry decoding and caching, the journey store,
derived workspace state, statistics, map overlays and tap indexes, and RailKit
routing internals. Method: four read-only code audits, then focused host
measurements (`swift test`, debug build, median of 5, `ContinuousClock`). The
host was under very heavy load from other sessions (load average about 500–700).
Read the numbers as proportions, not absolute device times. Every implemented
fix keeps its output identical.

## Implemented

| # | Change | Evidence |
|---|---|---|
| 1 | `JSNumber.string`: integral fast path for values below 2^53. It returns `String(Int(v))`, which is exactly JavaScript's output in that range. Grid-cell keys (`graphGridKey`, `nearbyNodes`, rail-section spatial index) are all integral. | 1M calls: **3639 → 300 ms**. Parity against the general algorithm over about 400k values (`InternalPerfParityTests`). |
| 2 | `Dates.sortByDateAndDeparture`: decorate-sort-undecorate. It computes `normalizeTrainDate`, `dateSortKey` and `departureMinutes` once per train instead of on every comparison. `ItineraryStore.regroup` runs this off main on every edit. | 2,000 trains: **866 → 60 ms**. Parity with the comparator sort, ties included. `DatesParityTests` and `PlaybackParityTests` pass. |
| 3 | `physical-rail-junctions.json` (about 10 MB) is decoded once per process (URL-keyed lock cache in `RiddenRouteStore`). Previously it was decoded on every `prepareSolverInputs` and on every first `latestValidFrom` per region. The latter is called on the main actor from `NewTripView.planRoute`. | One decode: **252 ms** host, now paid once per process. Failures are not cached. |
| 4 | `rail-history*.json`: one shared cached `RailHistoryOverlay` for `EdgeIndexCache` country builds and `loadJourneyAdmissionContext`. The admission context runs on every route repair or correction. | One load: **209 ms** host, now paid once per URL. The error mapping is unchanged. |
| 5 | `ItineraryStore.orderedJourneyGroups`: stored and refreshed from `didSet` of `store` and `state`, instead of a localized sort on every `body` read. | Chat-reviewed. Small at 200 rides, so not separately measured. |
| 6 | `PassportWorkspaceView.availableYears`: memoised in `WorkspaceDerived`, keyed by `ArrayGeneration` plus every other input. | Chat-reviewed, not measured: RailCoreTests cannot import RailPresentation. Before the change it ran a full `StatisticsMembership` slice on every body evaluation. |
| 7 | `RailMapCoordinator.draws`: returns early when no category is hidden. Before, it built the per-segment key string and `isRidden` on every segment during each of the three rebuild scans. | Pure short-circuit. Chat-reviewed. |
| 8 | `AppShell.statisticsLoadKey`: now uses `RiddenRouteStore.ridesKeyGeneration` instead of mapping every ride on every AppShell body. The generation bumps exactly when the ordered (id, geometryDigest) sequence changes, so the key keeps its old equality. | Chat-reviewed. |

Tried and reverted: a codes-only interval builder for `LocalJourneySearch`
(measured 114 vs 123 ms, no gain), and an access-stamp LRU in the route memos
(not measured, low value).

## Recommendations (not implemented)

Ranked by expected impact.

1. **EdgeIndexCache has a single slot, so its users thrash** (`EdgeIndexCache.swift:15`). In multi-country scope (全部) the Passport statistics `scoped(...)` load and `TraversedLineDetector`'s `index(country:)` evict each other. A merged miss then rebuilds every component country one after another, each about 1 s on the host, after a single ride edit. The single slot is a deliberate memory bound. Suggested fixes: have the detector use `CategoryIndexes.byCountry` or the statistics run's index, or keep a two-entry cache. Measure jp's resident index size first. `AppShell.swift:191` still claims "holds the indexes for the life of the process", which is no longer true.
2. **Statistics reload on every partial ride landing** (`AppShell` task id plus `MileageStatisticsStore.load`). This happens with the Stats tab open while rides are `.loading`. `fingerprint` and `slice` run synchronously on main, and the in-flight load is cancelled and restarted. Suggested fixes: debounce or gate while loading, and move `fingerprint` into the task (it is already `nonisolated static`).
3. **`LocalJourneySearch.search` rebuilds the national graph on every call.** It takes about 200 ms per search in debug, and up to 3 calls happen per planner or correction action. Suggested fix: cache `nodes/edges/outgoing` for one or two entries, keyed by package identity plus the permitted-line set, and apply `excludingStationCodes` during relaxation. The add-trip session owns these APIs, so coordinate with it.
4. **Map label passes re-run the whole `buildMarkers`.** That includes station grouping, `connectionsByPlace`, `ridesDigest` over every stop and `linesByStrokeID`, on each pinch quarter-step, pan settle and selection. Suggested fix: cache these by `ArrayGeneration` or the lines and rides generation.
5. **The tap index is invalidated on every rebuild** (`RailMapCoordinator.swift:1437`), so the next tap rebuilds `RideTapIndex` (about 180k vertices) inside the gesture. Suggested fix: key it on the frame, the stored-stroke set and the rides generation. The risk is moderate because the stroke-versus-fallback geometry depends on the build rect.
6. **Withheld-run polylines are recreated on every rebuild** (`:1527`), which defeats overlay identity reuse and forces a cross-fade. Suggested fix: cache them per frame key in `MapNetworkGeometryCache`.
7. **`DisplayNetworkCache` has a single package slot.** Alternating jp and another region re-decodes jp-2025.json (10.4 MB). The memory trade-off is the same as in item 1.
8. **A route-irrelevant edit re-resolves the ride** (`RiddenRouteStore` per-ride memo keyed on whole-`Train` equality). Suggested fix: key it on a route-relevant projection. This is risky: you must enumerate every field `drawnRide` copies.
9. **Every edit validates the whole store three times** (ItineraryStore, RideLibrary, RideStorage) and re-tags every train on main. Suggested fix: validate only the changed records.
10. **RailKit internals:**
    - The `RouteNetwork` stroke fallback projects onto every line and part. It uses string cache keys and recomputes `cos` per segment.
    - The main Dijkstra uses String keys.
    - Statistics have per-lookup allocations: the `edgeID` `[id]` array, `utf16LessOrEqual` arrays and `OrderedDictionary` read-modify-write copies.
    - Parity fixtures check these bit for bit.
11. **Playback does per-frame work.** `scheduleCameraRebuild` and `scheduleSettledPass` allocate tasks on every region callback during the chase, and `UIColor(railHex:)` is parsed every frame.

## Notes

- `FixtureParityTests` "group totals drive visibility" currently fails on 7 lines in this worktree. It exercises `Visibility.groupLengthByLineId`, which uses neither changed function. `build-port-fixtures.mjs --check` also cannot run here because `app/data/jp-history-sources/reviewed-station-renames-2019.json` is missing. Both point to existing fixture or data drift, not to these changes.
- Already good, so not re-proposed:
  - `WorkspaceDerived` generation memos
  - save coalescing and `ExportCache`
  - the per-ride digest route cache
  - `BundledRegistry.DecodeCache`
  - `DisplayNetworkCache` shared decodes
  - bounded route-graph LRUs
  - `MapDrawChanges` paint-only paths

## Sample load (follow-up, branch `claude/sample-load-perf`)

### Root cause

The suspicion that the precomputed parts were being rejected was not the
cause. A Time Profiler run of the cold new-year sample put **97 % of samples
in `RegistryIdentityUpgrade.uniqueStation`**. Every stop and section of every
ride passes through `BundledRegistry.upgradeIfReady` (called by
`canonicalRouteInput`, which `readCached` runs before it can even form the
cache digest). `uniqueStation` built a whole `RegistryIdentity(bundle:)` for
each lookup: every operator, station-name and needle map of the region's
registry. It then asked a question that only reads the bundle's forward code
tables (`stationCodes`, `groupCodes`, `stationOperator`).

Fix: `RegistryIdentity.stationID(forCode:operator:in:)`, an internal static
over the bundle alone. The instance method forwards to it, so every caller
gets the same answer from the same code. The per-region identity in
`BundledRegistry` is unchanged.

### Measurements

Shared iPhone 17 simulator, Debug build, bundle `com.JRM.RailMap.perf`, a
fresh `RAILMAP_UI_TEST_STORAGE_ID` store per run, and this bundle's route
cache emptied before each run. Recorded with xctrace Time Profiler plus
os_signpost. Times are seconds from launch. RSS is sampled every 0.5 s from
the host. Simulator CPU is the Mac's, so absolute times need a device check.
The proportions are robust.

| Sample | `route.cacheRead` before → after | Routes cached in the window, before → after | Peak RSS before → after |
|---|---|---|---|
| 日本 全部示例資料 (201 rides) | 116.5 s → **0.40 s** | 1 in 180 s → 71 in 120 s | 649 → 1382 MB |
| 跨年大回行程 (39 rides) | 32.8 s → **0.19 s** | 5 in 120 s → **39** (all) by ~30 s | 645 → 1393 MB |
| 東京特急大回行程 (16 rides) | 6.7 s → **0.19 s** | 16 by 69 s → 16 by ~25 s | 1224 → 1348 MB |

Peak RSS goes **up** after the fix. This is not a regression in kind: the
solver and the statistics edge index now actually run inside the window,
where before the app never got past the cache read. Both peaks are far over a
phone budget. That is the next section's work.

The precompute gate is not what blocks reuse. On a cache miss the order is
live physical solve first, then the bundled datasets only for rides the solver
explicitly rejected (`decodeUncached`). The dataset path also skips any ride
whose canonical sections carry physical `sectionCodes`, which timetable
enrichment adds to most JP rides. Both are deliberate: "a legacy N02
precompute can attest the journey, but cannot attest which of the closely
parallel platform tracks it rode". So the bundled `sample-data*` parts are a
last-resort fallback by design, and loosening the gate would trade correctness
for speed.

### What still costs time on the 201-ride sample (after the fix)

About 61 % of samples are in `RouteGraphStore.build`. The bounded cache policy
does not retain a country-sized full graph (`mayRetain`), so every ride whose
regional subgraph proves insufficient rebuilds the whole JP graph
(`fullGraph` 29 %, `addPhysicalJunctions` 30 %, `RailHistory.apply` 12 %).
This is a deliberate memory bound.

The right fix for sample loading is to bundle the samples' solved routes in
the app's own `RuntimeCache` format. Today the bundle carries only the JS
precompute, which the gate rightly distrusts. The seed would be keyed by the
same digest and `resourceRevision`, so it is ignored as soon as any input
changes and costs nothing in correctness. It needs a generator, either a
`swift run` tool over RailKit or a harvest of a simulator run's
`Caches/RailMap/Routes`, plus a copy step in `copy-rail-packages.sh`. Not done
here.

## Phone memory, one load path, Reload all (same branch)

Memory below is `phys_footprint` from `footprint`, the jetsam-relevant
number. Simulator RSS includes shared runtime pages and overstates it by
about 450 MB. Budget: about 300 MB steady with no multi-hundred-MB spikes.
Shared iPhone 17 sim, Debug build, fresh UUID store.

| Case | Peak | Steady after | Notes |
|---|---|---|---|
| Launch, empty store | 257 MB | 145 MB | before any route work |
| New Year loop, cold, before memory commit | 718 MB | 332 MB | 39/39 solved |
| New Year loop, cold, after `497024d50` | 672 MB | 332 MB | |
| Tokyo loop, cold, before memory commit | 729 MB | 332 MB | 16/16 solved |
| Tokyo loop, cold, after `497024d50` | 693 MB | 343 MB | |
| New Year loop, cold, single path `539cd7da3` | 683 MB | 278 MB | 39/39 solved on device |
| New Year loop, warm relaunch | 328 MB | 255 MB | all 39 from cache in under 1 s |
| Tokyo loop, cold, single path | 678 MB | 329 MB | 16/16 |
| Tokyo loop, warm relaunch | 320 MB | 242 MB | all 16 from cache in under 1 s |

- **Warm launches are within budget. A cold solve is not.** The spike is about
  +400 MB for about 3 s while the solver builds the country graph.
- In a heap snapshot at the spike, `[RouteGraph.Edge]` adjacency is 108 MB
  after compaction (166 MB before). The other big items are graph node `String`
  keys (about 106 MB), `[String]` (65 MB), a 50 MB `[String: NodeMeta]` and
  33 MB of `[String: Coordinate]`.
- The structural fix is interning node ids to `Int32` across `RouteGraph`,
  `CompiledSections` and the solver, under the existing node-for-node parity
  suites. It is **not done**: it is a routing refactor too large to do safely
  alongside this work.
- Steady state after the statistics edge index builds is about 340 MB.
  `EdgeIndex` holds `validFrom`, `validTo` and `historyId` as `[String?]`, each
  about 12.5 MB, plus a 63 MB `[EdgeKey: Int]`. Packing these needs a public
  API change: a recommendation, not done.
- The memory-warning release (`AppShell`) produced no measurable drop when
  `UISimulatedMemoryWarningNotification` and `com.apple.system.lowmemory` were
  posted with `notifyutil`. Delivery in the simulator is unconfirmed. Check it
  on a device with Xcode's *Simulate Memory Warning*.

### One load path for example and user trips (`539cd7da3`)

The sample-only fallback that searched the web app's precomputed route parts
is removed from the app. The bundle no longer carries
`sample-data*/` or `*-loop-data/`.

`app/data/sample-data*`, `*-loop-data` and `precompute-train-parts.mjs` stay,
because the website reads them. Removing them is website work.

The per-trip route cache was already content-keyed: it uses the route digest
(stations, sections and policy, solver version, history revision) plus the
resource revision. So an edit invalidates exactly that trip, and a
network/solver bump invalidates everything. The cache lives on disk in
`Caches/RailMap/Routes`, one file per trip, is read on demand, and is written
atomically.

### Reload all trips

The row is in Settings → About & diagnostics, with confirmation, `n of N`
progress and a Stop button, localised in en/ja/zh-Hans/zh-Hant.

How it runs:
- It clears the disk cache and the in-memory solve memos, then re-resolves
  the set the map was given, through the same `load`.
- It runs at `.utility` priority with the single solve permit (one worker).
- It yields between trips and backs off when `thermalState` is serious or
  critical.
- Map updates stay coalesced to one every 750 ms (`PartialRidePublication`)
  and go through the map's single 500-trip cap.

The review fixes are in: stop/restart races, a stale-set reload, a stuck
progress row, and trips left as "No route" after Stop.

Stop keeps what was solved and hands the rest to an ordinary `.utility` load
(cached routes replay, missing ones solve). Reload all always re-solves
everything, which is the explicit full rebuild. The ordinary load already
skips unchanged trips.

**Not measured.** The 288-trip budget runs (CPU, memory delta, frame rate,
hangs) and `ReloadAllUITests` did not complete. Another session's UI tests
held the shared simulator, and the perf app sat suspended in the background
(0 % CPU, no progress), so no numbers from that run are reported. The harness
is in place:
- `RAILMAP_UI_TEST_RELOAD_ALL=N`
- `RAILMAP_UI_TEST_RELOAD_ALL_STOP_MS`
- per-run times logged under subsystem `com.jtm.railmap`, category `harness`

### Derived products during a bulk load

Audit counts (P = partial publishes per load, about seconds / 0.75; C = the
number of countries in scope) and the change made:

| Product | Before | After |
|---|---|---|
| Statistics load (Stats tab open) | P runs, each cancelling the last | 1 at load end; 0 if the tab is not shown (`AppShell` key and guard on `isLoading`) |
| Statistics EdgeIndex builds | up to P×C (cancelled runs kept queuing) | per-country loops check cancellation |
| Line detector `publishSelected` | P | about 2 (start and final detect) |
| WorkspaceDerived `memberIDs` → stats, passport and years memos | P while visible | generation bumps only when the member set changes |
| Journey grouping, search | 1 per merge or import | unchanged (already once) |
| Map overlays | P, throttled | unchanged (intended progressive map) |
| Map tap index | lazy, 0 | unchanged |
| Share statistics | P while the composer is open | removed upstream: the composer was rebuilt on the UI-reorg branch |

Every builder now emits a signpost so its run count can be read from an
xctrace `os-signpost` export:
- `stats.load.request`
- `data.edgeIndex.build`, `data.edgeIndex.merge`
- `derived.lines.selected`, `derived.lines.detect`
- `derived.memberIDs`, `derived.statsScope`, `derived.passportScope`,
  `derived.availableYears`, `derived.scopedDates`, `derived.rideSummary`
- `derived.journeyGroups`, `derived.journeySearch`,
  `derived.categoryIndexes.load`
- `routes.partial.publish`

The measured after-counts are part of the unmeasured run above.
