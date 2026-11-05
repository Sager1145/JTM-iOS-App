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
