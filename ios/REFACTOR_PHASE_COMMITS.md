# Refactor phase delivery ledger

User instruction: complete the refactor and commit/push each validated phase to `main`.
Only the phase's reviewed files enter its commit; unrelated staged work remains intact.

## Phase 1: deterministic iOS resource packaging

Status: committed and pushed as `e2821000`.

`copy-rail-packages.sh` moves generated timestamps and build timings from bundled
manifest/report JSON into build diagnostics. Geometry, content hashes and input
identity remain unchanged. The existing App decoder does not consume these fields.
The railway generator and user datasets are unchanged by this phase.

Validation on the frozen data snapshot: clean and incremental outputs match all
1,086 files byte for byte; baseline, candidate and final Release bundles match
those hashes. Latest integrated Release builds and the public statistics workflow
pass. These receipts describe the frozen snapshot, not every possible dataset.
Local receipts: `outputs/refactor-20261009-resume/resource-clean-incremental-final.json`,
`release-bundle-resource-identity.json`, `release-final-resource-identity.json`.

## Phase 2: bounded route graph ownership and native history inputs

Status: committed and pushed as `ed707bef`.

Includes the compiled-section builder prerequisite, one shared bounded graph slot,
and eviction of oversized compiler memos. Default `.standard` behavior remains
available; bounded ownership never truncates graph geometry or routing edges.
Native historical tests now use the same physical policy and reviewed junction
registry as the App, avoiding unused passenger-transfer graph allocation. The
legacy browser audit retains its separate augmentation and assertions.

Validation: clean-main snapshot with only the five intended phase files builds
and passes 25 compiler/cache/physical-topology tests in four suites. Coded Donan
endpoint/date/mileage assertions pass (20.494s), sampled peak 1,254,196,856 bytes.
Ten expanded native history tests pass (39.357s), sampled peak 1,097,877,112 bytes.
These figures describe the selected host tests; full-suite acceptance is separate.
Earlier guarded nationwide runs over 2 GiB remain recorded as failures. The
fixed-workload compiler-memo comparison retains identical route output and lowers
resident footprint by 70.064%; it is not a whole-App measurement.
Receipts: `graph-phase-head-test.log`, `validity-production-graph.log`, and
`history-native-production-graph.log` under the local receipt directory above.

## Phase 3: coverage export and honest changed-line reporting

Status: committed and pushed as `da2ab0f1`.

Adds sequential LCOV export for existing per-target SwiftPM test binaries and a
reporter that unions repeated instrumented lines, maps candidate diff lines, and
fails missing changed-source coverage. Reports retain executable/profile hashes,
commands, errors, excluded non-executable lines and explicit scoped limitations.
No test selection is silently treated as full Domain or UI coverage.

Validation: 30 small parser/exporter tests pass. Real instrumented Application
run passes 35 tests in five suites. All three matching test executables export
successfully. Application-only result: 445/464 executable lines (95.9052%);
49/49 changed executable lines (100%), no unmapped changed files. Frozen
candidate diff is against original `14d2946`; this run includes uncommitted
Application validation changes and does not claim they have been delivered.
The supplied 70%/75% scoped reporting thresholds pass; full Core/App coverage
and the roadmap's final gates still require their complete instrumented suites.
Receipts: `application-coverage-test.log`, `application-coverage-export/manifest.json`,
`application-coverage-candidate.diff`, `application-coverage.json`.

## Phase 4: pinned advisory quality and scoped coverage CI

Status: committed and pushed as `e80194eb`; hosted quality and scoped coverage CI passed (run `37912326608`).

Pins official SwiftLint 0.65.1 and SwiftFormat 0.63.1 portable release binaries;
checks their actual versions before running readonly checks. JSON retains real
command/version statuses. The initial rules are deliberately advisory; this does
not establish the original complexity/length/no-new-warning release gate.
CI runs all coverage-tool tests, exports instrumented Application-only coverage,
and preserves report/error/input-identity artifacts. No full Domain/UI coverage
is inferred, and test/export/mapping failures remain CI failures.

Validation: shell syntax and workflow YAML parse pass; stub success, tool failure,
missing binary/version mismatch and readonly-source cases pass. Actual pinned
binaries over current iOS source: formatting passes, lint exits 2 with 33 findings
(27 force_try, six force_cast), preserved in the local advisory report. No source
is rewritten. Application coverage commands were exercised on the isolated local
snapshot in Phase 3; the hosted workflow itself has not yet been observed.

Expanded package regression after Phase 2 is still not accepted: its owned runner
was stopped at sampled 2,327,481,248 bytes. The complete 23-test native history
suite separately passes (53.379s), peak 1,113,163,432 bytes. Keep legacy browser
and remaining package allocation diagnosis open; assertions remain unchanged.

## Phase 5: isolated physical route validation use case

Status: committed and pushed as `0a0cd554`.

Moves ordered snapshot route-proof and historical-availability rules into
RailApplication. Failed, cancelled, incomplete or mismatched resolver responses
cannot confirm a draft or prove historical closure; cancellation propagates.
Pending drafts are confirmed only in the local probe copy, with no mutation of
caller data. Platform adoption is delivered separately with its UI integration.

Validation: clean-main package plus only this helper/test passes 35 Application
tests in five suites. Cases cover order, missing drafts, undated availability,
wrong reply count, ordinary failures and cancellation before/after ignored work.
Phase 3's real coverage maps every changed executable helper line. Ownership
adds only the helper's RailApplication entry; concurrent CLI mappings stay local.
Receipt: `application-phase-head-test.log`.

## Phase 6: display-network ownership and serialized route admission

Status: committed and pushed as `32baee07`.

Display networks share one completed country/combined-scope retention slot and
one unused layout seed. Builds coalesce and use an independent single permit;
old cache ownership releases before replacement allocation. Publication happens
before admission transfers, preventing late waiters from restoring stale cache
ownership. Active callers keep their immutable result. Production route solves
share one global permit until the complete operation exits, including cancellation.

Validation: clean-main plus exactly DisplayNetworkCache and RouteSolveLimiter
builds the Release Simulator App successfully for arm64 and x86_64. Production
actor harness passes coalescing, independent cancellation, single build admission,
release-before-build, seed consumption, scope ordering, active-result survival,
and failed-build retry. Previous host payload comparison measured 32.58% lower
resident cache footprint; full production workflow acceptance remains separate.
Receipts: `cache-phase-head-build.log` and the production actor harness command.
No simulator or external CLI process was stopped during this phase.

## Phase 7: statistics index lifetime and merge allocation

Status: committed and pushed as `15662ea1`.

One completed index slot covers country, merged and scoped results. Independent
build admission includes display augmentation, and N02 denominator counts travel
with country results. Scoped clipping releases full-country cache ownership before
another country is fetched. Merge reserves final buffers and inserts first-wins
keys directly instead of allocating an offset dictionary for every component.
Caller order, duplicate countries, historical variants and mileage totals remain.
Includes the existing area-scope types/grid required by the index API, with one
ownership mapping; the unfinished area UI and unrelated CLI data stay local.

Validation: independent clean-main Release App build for both Simulator architectures
passes. Actual actor harness passes seven lifetime/ordering/failure scenarios.
Previous 781 merge-scope comparisons match every result against the original merge.
Release five-country statistics A/B protocol (three alternating fresh launches
per version, identical frozen inputs except index source): median stable footprint
327,453,600 to 239,454,968 bytes (26.8736% lower), median peak 376,441,784 to
311,413,616 bytes (17.2744% lower). That pair used the earlier frozen complete
App snapshot; it does not establish launch, rendering or leak goals for this commit.
The latest compiler-memo Release build and public statistics flow passed separately.
Receipts: `edge-phase-head-build.log`, `release-merge-allocation/`.

## Phase 8: endpoint availability before graph allocation

Status: committed as `9b894f29`; existing historical data issue remains.

Extracts the existing endpoint normalization, code/name expansion, institution
filter and date availability into one shared preparation function. On-demand
queries with absent or unavailable endpoints now return before graph allocation;
viable endpoints retain the same physical solve and fallback behavior.

Validation: clean-main plus the source/test passes 22 preflight and physical
routing tests in two suites, including zero build callbacks for unavailable
endpoints and named/code-only viable paths. A broader dated suite reported three
Donan assertions on the frozen ongoing-CLI data snapshot. Restoring the main
solver and rerunning the same case reproduces exactly those three assertions;
this phase does not resolve that pending data/source compatibility issue.
Complete native history on the full ongoing-CLI source snapshot passed separately
in Phase 2. Do not infer clean-main full-suite acceptance from that result.
Receipts: `endpoint-phase-focused-test.log`, `endpoint-phase-head-test.log`,
`endpoint-phase-baseline-donan.log` (baseline/candidate both exit 1 for that case).

## Phase 9: production-sized endpoint census cache ownership

Status: committed and pushed as `ece1eddf`; functional registry failure remains.

Real-data endpoint/census helpers use the production bounded graph policy rather
than retaining every region/corridor/full graph. Inputs, comparisons, route
assertions and reviewed-junction rejection checks remain unchanged.

Validation: the guarded 201-ride census completes (836.368s), peak 1,413,089,176
bytes versus the prior runner stopped at 2,327,481,248 bytes. It reports one
functional issue: the direct public graph builder rejects five historical
registry entries (Naoetsu, two Goryokaku entries, Aomori and Tsubata). That check
calls `RouteGraph.build` directly and does not use the changed graph-store policy.
The memory acceptance does not turn this functional failure into a PASS; the
census remains unresolved. The same graph-policy ownership/geometry invariants
are covered by Phase 2's cache equivalence tests. Full-suite status is separate.
Receipts: `census-bounded.log`, `census-bounded-summary.json`,
`package-native-production-graph-summary.json`.

## Phase 10: map label and selected-station responsibility extraction

Status: committed and pushed as `4cb6bdc6`.

Moves the collision grid unchanged into its own source and isolates selected
station snapshot tasks/cache lifetime from the map coordinator. Teardown clears
snapshots; request tickets reject noncooperative completions after country,
selection or mount changes. Existing camera, annotation refresh and geometry
behavior stay in the coordinator. The nested preparation cleanup is explicitly
MainActor-isolated. Concurrent CLI annotation/restyle instrumentation is excluded.

Validation: actual collision grid passes explicit boundary/padding/reservation
cases and 600 oracle comparisons. The actual snapshot controller passes cache,
coalescing, country change, cleared selection, replaced mount, teardown, stale
completion and exactly-once callback checks. The clean-main Release App build passes for arm64 and x86_64 using HEAD plus
only these map sources; full platform/performance acceptance remains separate.
Receipts: `map-phase-label-grid.log`, `map-phase-selected-snapshot.log`,
`map-phase-head-build.log`.

The remaining package regression was stopped at 2,431,373,008 bytes (exit 143;
owned-runner memory guard exit 2). A process-lifetime Sonic national graph and
other static fixture owners remain live across suites. The last buffered catalog
line does not identify the allocating test. Localization/Presentation missing
fixture paths and StoreOperations byte mismatches are also recorded. This is
not a completed suite. The serialized share lifecycle's 46 checks pass and the
App builds, but the public export test fails during preview invalidation; its
source-key/lifecycle cause is being traced before delivery.

## Phase 11: scoped native Sonic route-constraint fixtures

Status: committed and pushed as `a48cb27b`.

The Sonic constraint suite now uses the application's on-demand physical graph,
reviewed junctions and bounded graph policy. Each solve owns its fixture through
completion; no national graph remains a static process owner. The suite is
serialized even when the runner permits other parameter cases in parallel.
Original train context, full source sections/stations and all four assertions
are unchanged. Passenger-transfer augmentation is removed from this native test.

Validation: independent clean-main Core plus only this test passes all four
cases in 15.062s. Frozen ongoing-CLI Core/data A/B also passes all four in both
versions: original static graph 41.428s / sampled peak 1,979,468,152 bytes;
candidate 14.817s / sampled peak 762,938,760 bytes (61.46% lower). This is one
controlled test-process pair, not whole-App memory or launch acceptance.
Receipts: `sonic-phase-head.log`, `sonic-original-baseline*`,
`sonic-native-production*`. No source geometry or physical evidence was changed.

Sharing diagnostic runs pass twice (actual PNG, preview and dismissal). The
trace also records late publication of ride 144 after ride 143: the current
composer hashes all rides although its statistics/rendered cards use selected
scope/date members. A focused input-key fix and regression are in progress;
the earlier public failure remains evidence, not waived by the later passes.

## Phase 12: bounded solver-input and batch graph lifetimes

Status: committed and pushed as `57f0f926`.

Reduces completed immutable solver inputs from two scopes to one and admits
JSON decodes through an independent one-at-a-time permit. Same-scope callers
share work; cancellation stays local, and late waiters cannot reinsert an old
completed owner. Old cache ownership drops before replacement decode. Batch
graphs use the bounded 100,000-node policy and release after their scope.
A carried preferred graph travels with its original immutable inputs through
both solver passes, preventing another decode after an earlier scope evicts it.
Route order, routing bodies, history/geometry inputs and keys are preserved.
Concurrent CLI worker changes and platform date-validation adoption are excluded.

Validation: clean-main Release App build passes arm64 and x86_64. The actual
candidate cache/invalidation harness passes ten groups; controlled production
batch/solver-plumbing fixtures pass three ownership/order scenarios on candidate
and working sources. The integrated ongoing-CLI App builds; public sharing with
the scoped-key fix passes. Scope/date validation separately passes 22 cases.
These fixtures prove owner bounds and behavior, not measured whole-App savings.
The existing statistics Release A/B and graph memory receipts do not substitute
for the remaining real solved-route App comparison or complete release goals.
Receipts: `input-phase-head-build.log`, `input-phase-caches-candidate.log`,
`input-phase-plumbing-candidate.log`, `scoped-share-public.log`.

## Phase 13: bounded native service-pattern graph retention

Status: committed and pushed as `c706f15b`.

Adds only the production bounded graph policy to the service-pattern physical
fixture's reviewed-registry graph store. Source inputs, dates, route constraints,
all route assertions and acceptance ledger output stay unchanged.

Validation: three named end-date/identity/retired-branch tests pass on both
snapshots. Ongoing-CLI Core/data: 98.258s, sampled peak 1,220,200,176 bytes.
Clean-main Core: 77.632s, sampled peak 1,178,912,520 bytes. Both owned 2 GiB guards
and runners exit zero. This covers these three tests, not every service-pattern
parameter, complete package acceptance or a before/after App memory result.
Receipts: `service-pattern-native-bounded*`, `service-pattern-clean-main*`.

## Phase 14: sharing export ownership and scoped render identity

Status: committed and pushed as `21c60b79`.

Adopts the CLI share composer and its necessary statistics-card rendering inputs
as a reviewable, independently built integration. Sharing now opens a composer
with card/layout, scope, ratio, size and map controls. Main's region menu and
Passport behavior are preserved; unrelated CLI area-menu, map and editor changes
are excluded. Retires the old poster request controller and its superseded gate.

Full-resolution user and DEBUG exports share one FIFO permit through raster and
PNG completion. Invalidation immediately drops partial pixels and queued work,
without releasing a noncooperative active writer's permit. DEBUG writes directly
to its destination with one PNG encode. Input identity includes only rendered
scope/date/year/group/ridden geometry; unrelated late ride publication no longer
invalidates a current export. Preview size remains bounded independently of
full-resolution output. Statistics tasks cancel with their composer owner.

Validation: the actual extracted controller/view harness passes 57 checks on
working and independent-main candidate sources. Source ownership (280 sources),
seven boundary-checker regressions and permanent typography bounds pass. Clean
main Debug build-for-testing and Release App arm64/x86_64 build pass. Public
Japan/date export, image preview and dismissal pass in 46.865s, without diagnostic
instrumentation. Release retains two pre-existing ServicePatternPicker actor
warnings (one per architecture); this phase does not claim zero whole-App warnings.
The earlier public sharing failure remains recorded; a later diagnostic trace
identified the global-vs-scoped input-key mismatch fixed here. Harness ownership
bounds and this flow do not establish whole-App peak memory or full sharing/UI
matrix acceptance. Receipts: `share-phase-main-ui.log` / xcresult,
`share-phase-main-release.log`, `share-phase-main-controller.log`,
`share-phase-main-boundaries.log`, `share-phase-main-delivery.json`.

## Phase 15: platform dated route proof and pending drafts

Status: committed and pushed as `592b8b9c`.

Connects NewTrip's immutable corridor snapshot to the existing Application
physical validation use case. Draft construction is shared by probing and saving;
only a matching dated physical proof marks a saved corridor confirmed. Unproven
candidates stay pending and no unproven distance is presented as solved mileage.
A train-number/day change invalidates prior proof. Historical validation retains
a dated-valid route even when today's undated route is unavailable, and hides
only the opposite proven date mismatch with localized explanation.

Batch availability uses Main's physical solver with no publication/cache writes.
Each scope owns one graph and its original immutable inputs for both independent
snapshots, then releases before the next scope. Original caller order and local
cancellation are preserved. The new portable 22-case availability harness and
existing carried-input lifetime harness are registered in native verification.
CLI worker, timetable, history-format and selection changes remain excluded.

Validation: actual candidate availability passes 22 controlled cases; production
input/graph plumbing passes three ownership/order scenarios. Boundary inventory
280, seven checker tests and permanent typography bounds pass. Main Debug App
build and public empty/disabled save, multiple corridor choice, and no-number
save flows pass (19.789s, 67.583s, 36.138s). Release arm64/x86_64 passes separately.
An initial build exposed the CLI-only history identityPeriods API; that loop is
removed, preserving Main-supported section/station/retirement/junction opening
bounds. The initial failed receipt remains. These public flows do not substitute
for the remaining historical-date device matrix or complete release acceptance.
Receipts: `date-phase-main-build.log` (initial failure),
`date-phase-main-build-fixed.log`, `date-phase-main-release.log`,
`date-phase-main-ui.log` / xcresult, `date-phase-main-availability.log`,
`date-phase-main-plumbing.log`, `date-phase-main-boundaries.log`.

## Phase 16: immutable operator constant isolation

Status: independently validated for this main delivery.

Declares the timetable picker's immutable Sendable operator-name Set nonisolated,
matching its nonisolated filtering caller. Contents and matching behavior do not
change. The concurrent CLI file is exactly this one-line change and is adopted
without other CLI implementation changes.

Validation: independent current-main Release App builds for arm64 and x86_64;
both former ServicePatternPicker actor-isolation warnings disappear. No App
source warning appears; Xcode's AppIntents metadata-not-needed warning remains.
Receipt: `quality-constant-main-release.log`.

The coherent committed-main full package attempt is incomplete: its owned 2 GiB
guard stopped at 2,286,816,064 bytes after 48 XCTest tests, a complete 336-test
SwiftTesting target run, and the full 551.456s junction census passed. No captured
assertion failure appeared. A prior stack confirmed the legacy historical browser
boundary audit; buffered output cannot identify the exact final allocating test.
This remains an open memory failure, not full-package acceptance. Receipts:
`main-regression-results.json`, `main-regression-memory-summary.json`.

## Remaining delivery phases

- Recover the large historical graph's memory acceptance without changing physical
  connectivity, surveyed geometry, expected routes or mileage assertions.
- Integrate validated statistics/route/display cache and lifecycle changes as
  independently buildable commits; include and verify required prerequisites.
- Add coverage export/reporting and version-pinned advisory lint/format CI, then
  meet and enforce the original coverage/quality goals using complete evidence.
- Complete remaining UI/platform, launch/render/stall/build/leak measurements.
- Finish responsibility/directory migration where needed, and resolve the map
  full-viewport dimming requirement under the public API/performance constraints.
- Close the complete regression matrix and release acceptance.

The roadmap is not complete. Existing full-suite/data failures and the historical
national graph's 2 GiB operational test stop remain recorded, not waived.
