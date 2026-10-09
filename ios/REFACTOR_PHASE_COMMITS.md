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

## Phase 17: public Release readiness and honest memory gate

Status: independently validated public route proof; whole-App memory gate failed.

Exposes the real map route-load state through a localized accessibility container,
retaining native MapKit and annotation accessibility. The Release XCTest opens
both exact committed JP Sonic44/TW airport MRT journeys, requires each public
"Route generated" state, and reaches ready All-regions statistics. It expands
the real public panel before seeking lazy list cells. No DEBUG route confirmations,
synthetic geometry or test-only readiness surface is used.

Adds the reviewed two-record fixture and a reusable fresh-process Release sampler.
The sampler uses an explicit dedicated simulator, validates matching Release
products, records actual physical footprint/peak and source hashes, limits sample
retention, and returns nonzero unless settled median strictly falls and peak
median does not increase. Public success alone cannot satisfy this gate.

Validation: frozen phase-12 pair has six public route/Stats passes. Latest c88c5269
Main with these exact public changes independently builds Release arm64/x86_64
and passes the public test in 77.876s. Native source boundaries (280 sources),
seven ownership checks and permanent typography bounds pass. New XCTest has zero
configured SwiftLint findings and passes pinned scoped SwiftFormat; sampler parses,
CLI help and actual Release-product validation pass.

The phase-12 production pair uses base 21c60b79, differing only in RiddenRouteStore
(a48cb27b before, bounded/carried-input implementation after) with common readiness
changes, exact Main resources and the same real fixture. Three alternating fresh
process/container trials yield median settled footprint 492,343,136 -> 577,867,424 B
(+17.37%, FAIL) and median peak 1,532,563,128 -> 1,261,276,688 B (-17.70%). Other owned
validation ran on this host; this observed failed gate is retained and cannot be
reported as whole-App memory acceptance. No rollout claim is inferred from peak
reduction. Receipts: `real-route-app-memory-v4.json`,
`real-route-memory-comparison-inputs.json`, `release-proof-main-result.json`,
`release-proof-main-build.log`, `release-proof-main-boundaries.log`.

Follow-up evidence: isolated committed-Main historical browser boundary audit
passes all its assertions in 718.057s (719.977s runner), peak physical footprint
1,938,131,584 B under the owned 2 GiB guard. The earlier full-package 2,286,816,064 B
stop remains unresolved. Frame-leading public-convert M candidate collects native
raster screenshots but fails alignment: sampled maxima 3-4 device px; frame gap
347.675ms exceeds 150ms. Candidate remains scratch-only, never default/shipped.
Receipts: `history-boundary-focused-run-summary.json`,
`history-boundary-focused-memory-summary.json`, `map-frame-lead-pixels.log`.

## Phase 18: graph materialization ownership and verified Release pair

Status: scoped graph equivalence/memory and dual-region Release acceptance pass.

Graph construction drops the completed local-id/stamp buffers, removes the
intermediate slot dictionary, builds final reserved dictionaries directly, then
releases all staging arrays and local final-dictionary aliases before physical
junction augmentation. Native graph cache observers still receive one final
assignment. Selected feature order, surveyed coordinates, ordered edges/grid,
metadata, UTF8 identity and physical junction evidence remain unchanged.

Validation: scratch original/candidate oracle compares complete real Tokyo graphs
under physicalRailway and coordinateParity, plus canonical UTF8, repeated/reordered
features, coincident ties, duplicate edges and self-loop cases (15.625s PASS).
Existing compiled graph/physical topology suites: 21 tests / two suites PASS
38.047s. Cache-policy suite: three PASS. Release arm64/x86_64 App test build PASS.
Three alternating fresh host processes, same 23,028 JP sections/3,752 selected
features/40,238 nodes/80,506 edges: settled median 263,423,008 -> 261,440,592 B
(-0.75%), peak 263,603,232 -> 261,637,200 B (-0.75%). This is a Tokyo builder
workload, not an App percentage. Builder-time median 0.348796 -> 0.388026s
(+11.25%); full launch/render/build-time goals remain unaccepted and a less
hash-intensive materializer is being evaluated.

The committed Release sampler's first runtime attempt exposes an installation
lifecycle issue: Xcode replaces the bundle path while preserving seeded data;
all public assertions pass but no PID samples match the prelaunch path. It fails
rather than reporting zero memory. The sampler now resolves the registered
owned bundle path while sampling and retains the one-PID check.

With other owned builds/experiments stopped, three alternating fresh Release
containers/processes pass all public route/Stats assertions and sampling.
Baseline is the frozen pre-phase-12 RiddenRouteStore build; candidate is latest
Main App plus this graph materializer. The comparison includes delivered route,
date/readiness code and this graph change; it does not isolate cache-count alone.
Exact committed JP/TW fixture and Main resources are common. Settled median
418,910,024 -> 416,632,456 B (-0.54%); peak median 1,521,208,992 -> 1,210,404,320 B
(-20.43%). All six builds retain one fixed binary SHA per side; gate PASS.
Earlier Phase 17 failed measurements remain recorded. This acceptance is only
for the stated two-region scenario, not all regions or confirmed zero leaks.

Receipts: `graph-builder-equivalence.log`, `graph-builder-focused.log`,
`graph-builder-cache-policy.log`, `graph-builder-memory-result.json`,
`graph-builder-main-release.log`, `graph-builder-release-app-memory.json`
(first sampler failure), `graph-builder-release-app-memory-v2.json` (PASS).

## Remaining delivery phases

- Recover the large historical graph's memory acceptance without changing physical
  connectivity, surveyed geometry, expected routes or mileage assertions.
- Complete whole-App memory acceptance for the delivered cache/lifecycle changes;
  retain the Phase 17 settled-footprint failure while reducing allocator ownership.
- Add coverage export/reporting and version-pinned advisory lint/format CI, then
  meet and enforce the original coverage/quality goals using complete evidence.
- Complete remaining UI/platform, launch/render/stall/build/leak measurements.
- Finish responsibility/directory migration where needed, and resolve the map
  full-viewport dimming requirement under the public API/performance constraints.
- Close the complete regression matrix and release acceptance.

The roadmap is not complete. Existing full-suite/data failures and the historical
national graph's 2 GiB operational test stop remain recorded, not waived.

## Phase 19: reconcile the original roadmap and regression matrix

Status: documentation reconciliation delivered; full refactor acceptance remains open.

The original FULL_CODEBASE_REFACTOR_PLAN and REFACTOR_FEATURE_MATRIX now lead
with the exact pushed phase-18 production baseline and a target/evidence/open-gate
comparison. Historical observations remain historical. The 18 delivered phases
are tied to the original S0-S6/M plan rather than treated as a new roadmap.
Dual-region Release memory acceptance is separated from full-device/region/leak
acceptance, the prior full-suite 2 GiB stop and settled-footprint failure remain
visible, and builder CPU regression is explicit. Full Main18 instrumented package
build passes (106.54s); exact 1,437-function/169-suite inventory is now executing
serially in fresh processes with all arguments, existing benchmark opt-ins and
an owned 2 GiB guard. This phase does not claim that pending run passed.

Validation: documentation-only candidates contain exactly the new leading
sections and this receipt; existing CLI edits and staged logo deletions are
preserved. Source/metric identities checked against the phase ledger and build/
inventory receipts. Remaining Domain/global coverage, quality thresholds, full
UI/platform/performance/leak matrix, stable directory ownership and M are open.

## Phase 20: make original complexity and length limits visible in CI

Status: calibrated advisory metric reporting delivered; original quality goals
are not yet met or enforced for new code.

The pinned existing SwiftLint configuration now includes cyclomatic_complexity
and function_body_length, with requested warning limits15 and60. Case statements
are included; no legacy exclusions, suppressions or autocorrection are added.
Calibration with SwiftLint0.65.1 proves16/61 warn and15/60 do not. Existing CI
uses this configuration and preserves complete reports and actual tool statuses.
Usual<=10/<=40 remains a review target, not an inferred passing gate.

Validation: exact committed280 production files, no individual exclusions, yield
165 requested-limit findings (56 complexity,109 body length) across60 files.
A second advisory10/40 inventory yields336 findings across87 files. Combined
existing/new rule run yields167 findings (the above165 plus2 production casts),
actual strict exit2. The production-scoped existing advisory pipeline preserves
that nonzero status, pinned tool identities and format findings, returning0 as
documented advisory behavior. No production source is reformatted or refactored
by this reporting phase. Legacy debt is visible, not waived or marked clean.

Receipts: quality-complexity/{inventory.json,run-receipt.json,recommendation.md},
quality-limits-delivery/{receipt.json,lint.json,pipeline/summary.json}. Remaining
work is bounded responsibility extraction with equivalent behavior and lower
footprint, followed by baseline-aware enforcement of new/modified-function debt
and the full coverage/platform/performance/M matrix.

## Phase 21: migrate the console walk to the delivered share composer

Status: complete ConsoleSweep public flow passes after adapting its obsolete
share-menu navigation to the delivered composer.

Frozen Main19 full UI regression exposes the old mapShareOption/
statisticsShareOption menu lookup, which no longer exists after Phase14. The
console walk now opens the public composer, explicitly selects and verifies
both light/dark appearance values, waits for export readiness, verifies an
actual preview image, closes preview and composer, then runs every original
map/control/data/settings/journey/editor/search step. Existing CLI navigation
changes informed the migration; both original appearance passes and image/
dismissal assertions remain. No production behavior or fixture is changed.

Validation: independent exact Main19 production + this one test candidate
build-for-testing PASS; full ConsoleSweep test PASS (185.990s runner), one
owned App PID,129 successful physical samples, reported peak367,954,872B,
no2GiB guard breach. Current five-rule pinned SwiftLint reports zero findings;
scoped pinned SwiftFormat passes. Initial Main19 failure remains in the full
UI matrix; this dedicated corrected receipt closes only that failed flow.
Other UI classes continue independently, with exact outcomes recorded.

Receipts: console-composer-{candidate.json,build.log,validation.json,
validation.log,validation.xcresult,lint.json,format.log}. This is UI regression
verification, not A/B footprint or zero-leak acceptance. Unrelated CLI source
and staged deletions remain preserved. Full refactor acceptance is still open.

## Phase 22: normalize group names in the input binding

Status: both original JourneyGroup UI regressions pass with all assertions
unchanged. Normalize newline removal and the existing 12-character bound in
the synchronous TextField binding, together with the selected draft group.
Remove the recursive onChange writeback; add no task, retained view state,
UIKit wrapper or alternate group ownership.

Main19 full matrix reproduced a 14-character visible field despite the
12-character contract. The isolated candidate now passes draft editing,
reselection and returning from stop editing (65.423s), plus the original
12-character field assertion, save, relaunch and statistics group selection
(52.714s). Dedicated Debug build-for-testing PASS; current five-rule pinned
SwiftLint zero findings and scoped SwiftFormat PASS. External physical guard
records 84 samples across three expected relaunch PIDs, peak361,007,960B,
no2GiB breach. This correctness check does not claim comparative RAM savings
or full-platform acceptance. Grok prepared the bounded binding edit; Codex
reviewed the exact diff and ran the unchanged UI tests.

Receipts: group-name-input-{candidate.json,build.log,validation.json,
validation.log,validation.xcresult,lint.json,format.log}. Existing CLI changes
and staged logo deletions remain preserved. Separately, the full Main19 UI
matrix stopped at a real2GiB map-layer-toggle peak2,553,958,912B; its
30pass/7fail/4existing-skip/1interrupted/94unstarted results remain open,
with ConsoleSweep and group-name failures closed only by dedicated proofs.

## Phase 23: prove five real regions through public route details

Status: Release public proof PASS148.377s. Commit a separately reviewed
five-record fixture (JP/TW/HK/MO/KR) and a test that retains every dual-region
map/annotation/global-route/detail-generated/statistics-ready assertion,
checking each of the five IDs. JP Sonic44 and Taiwan Airport MRT are unchanged
from the two-record fixture; HK-SAMPLE-EAL-LOW, MO-SAMPLE-MLM-TAIPA and
KR-SAMPLE-GYEONGBUKSEON are exact original records from committed
app/data/train-store-{hk,mo,kr}.json. No synthetic stations, forced route
confirmation, geometry or readiness fields are added. Fixture SHA256:
ccfcdb2a60eeed675648dedf01f2472d1f00d9dbcae2485737c87a083a801961.

Validation: all280 frozen production Swift files match Main21 at preparation
(the later Main22 change is group input only); Release dual-architecture
build-for-testing PASS. On the owned simulator, the new exact test reports
every real route generated and All regions statistics ready, exit0,106
actual physical samples, one App PID40162, peak1,188,285,896B, no2GiB stop.
Current five-rule SwiftLint zero findings and scoped SwiftFormat PASS.
This run occurred with other owned work active: correctness/budget evidence
only, not paired stable-footprint, launch/stall or leak acceptance.

The external runner must seed the matching committed fixture per method:
testTwoRealRegionsCompleteRoutesAndStatistics uses the two-region fixture;
testFiveRealRegionsCompleteRoutesAndStatistics uses this five-region fixture.
Earlier synthetic five-region/Stats-only evidence is not accepted for route
proof. Original dual-region test remains unchanged; unrelated live CLI test
changes and staging remain preserved. Receipts: release-five-real-{candidate,
build,validation,lint,format} artifacts. Full acceptance remains open.

## Phase 24: gate new lint debt without suppressing legacy findings

Status: baseline-aware pinned five-rule SwiftLint gate delivered. Advisory
full lint/format reports remain visible; CI now also rejects new findings,
increased metric reasons and changed warning declarations. Compare exact
root-relative source identities and unchanged lines through the full function
declaration (including multiline parameters/return/default closures), so
unrelated line shifts retain the same legacy warning. Deleted debt does not
pay for a new warning elsewhere; duplicates remain individually counted.
Complete ios Swift inventory, pinned0.65.1/version/real lint exit/report
consistency are required. No per-file suppression or reduced source list.

Validation: nine meaningful parser/comparison tests PASS, existing30 coverage
parser tests PASS; workflow YAML parsed. Independent review found a multiline
parameter identity gap; fixed and covered by multiline/default-closure/string
brace regressions before delivery. Actual pinned lint/format runs on frozen
Main21/Main22 and Main22/Main23 each contain507Swift files and270 findings,
all270 inherited, zero new, both comparisons PASS. A separate actual pinned
force_cast fixture produces one new finding and gate exit1 as expected.
Production's167finding baseline (165complexity/length+2casts) remains visible
as reported in Phase20;270 here includes tests. This gate does not claim
global complexity<=15/body<=60, usual10/40, full coverage or RAM acceptance.

CI archives the event's base SHA (parent for manual dispatch) with full history,
runs both snapshots using the same current pinned configuration, preserves
all reports on failure, and keeps formatting advisory. Receipts:
quality-debt-{base,candidate,main23}/, quality-debt-*-comparison.json,
quality-debt-calibration-{baseline,candidate,rejection.json}. No App runtime
source or concurrent CLI staging is changed by this tooling phase.

## Phase 25: align the pending-service test with its real catalogue name

Status: the original through-service candidate/pending/save/reopen UI case
passes134.813s. Change only its stale literal to the exact committed
asakusa-keisei-keikyu catalogue name 京成本線・都営浅草線・京急空港線直通.
The former failure was the service picker lookup before route-candidate
assertions, not a physical route failure. All physical endpoint/candidate
selection, pending confirmation, no invented visits, through-service label,
persistence and reopened endpoint assertions remain unchanged.

Validation: isolated current Main22 production Debug build PASS; exact tested
second-case body equals the delivered body. The complete two-case run has
159samples/threeexpectedPIDs, peak395,004,856B and no2GiB breach, but exits65
because the separate physical-autofill Undo case stillfails. That failure
and the attempted bounded scrolling helper remain unaccepted; this commit
includes neither the failed helper nor speculative Undo product changes.
Receipts: autofill-ui-{candidate,build,validation} artifacts retain both
outcomes. This closes only the stale catalogue-name regression; full UI,
Undo and comparative memory acceptance remain open.

## Phase 26: capture Undo after editor-derived direction settles

Status: both original committed autofill UI tests PASS. Scratch DEBUG evidence
proves Undo already exists internally but snapshot equality becomes false:
direction=nil→down is the only changed Train field, including while the
route action is mounted. The normal draft onChange infers that direction
after the old snapshot. Call the existing refreshAutoDirection immediately
before snapshot capture; retain its authored-direction/official-direction
rules and the exact equality guard protecting later user edits. Add no
retained state or new diagnostic surface to production.

Validation: independently built exact Main25 + this two-line change, Debug
arm64 build-for-testing PASS. Original physical-fill/intermediate-stop/Undo
restoration test PASS47.730s with the original navigation helper; original
through-service candidate/pending/save/reopen test PASS134.434s, exit0.
137actual physical samples across3expected launch/relaunch PIDs,
peak394021816B, no2GiB breach. Full507-file pinned lint/format evidence
retains270legacy findings, zero new debt; formatting PASS. This is not paired
RAM or leak acceptance. Failed scrolling and diagnostic attempts remain
in autofill-ui and autofill-undo-diagnostic receipts; neither is shipped.

Receipts: autofill-undo-fix-{candidate,build,validation,new-debt} artifacts and
quality reports. Unrelated live RideEditor CLI changes are preserved by
applying only the snapshot insertion; an isolated Git index commits the
validated Main candidate rather than the rest of that dirty file. Full
platform/memory acceptance remains open.


## Phase27 — original roadmap / matrix reconciliation through Main26

Reconcile accepted phases20–26 into the original S0–S6/M plan and feature
matrix, preserving historical CLI text and every original acceptance target.
Main26 push and origin identity verified; pinned quality CI37942955301 SUCCESS.
Record the new-debt gate separately from167 legacy production findings,
dedicated UI fixes separately from137-test current matrix, five real regions
correctness separately from pairedRAM/leaks, and the completed674-inspection
census separately from still-running169-suite/fullcoverage acceptance.

Preserve failed sparse-junction/one-frame candidates and Main26 DEBUG guard
peak2205766504B without shipping them or attributing transient allocations
solely from nearby graph events. M remains unaccepted; exact-reference
control has confounded measured stroke width. Remaining quiet performance,
responsibility directories and platform gates stay open. Documentation only;
no production source, test assertion, fixture, resource or memory gate change.

Validation: receipts and committed source/test identities checked against
Main26; links resolve to original plan/ledger. Original cached two logo
deletions and all unrelated CLI working changes are preserved.


## Phase28 — preserve sampling through actual null exit snapshots

Apple footprint emitted processes:[null] and owned-PID auxiliary:null while
processes exited during the full-package runner. The Release sampler now
treats those snapshots as unavailable, never as zero or a valid sample.
Ignore null entries beside an actual owned process; still reject wrong or
duplicate PIDs and malformed actual metrics. Positive finite physical current
and peak values remain required, including peaks above the budget.

Validation: nine focused regression tests PASS with real recorded metric
values, null exit forms, mixed actual/null records, wrong/duplicate PID,
invalid current/peak and stale failed-command output. Existing registered
bundle refresh, single-PID trial, original public JP/TW proof, five final
valid samples and 2GiB stop are unchanged. No app source, fixture, XCTest
assertion or memory threshold changes; no comparative RAM claim in this phase.
The in-progress Edge layout candidate and both its passing and guard-stopped
map runs remain separate unaccepted evidence until paired validation.


## Phase29 — statistics line coverage presentation responsibility

Extract the existing category eligibility, raw-operator grouping, localized
numeric order, row identity, company label and unrounded mileage percentage
from StatisticsView into stateless RailPresentation. Caller keeps scoped
statistics/loading ownership; no new tasks, caches or retained input copies.
The same compactMap/sorted policy and all six category masks remain intact.
Register only this source in the ownership manifest; preserve concurrent CLI
responsibility wording and all unrelated dirty files/staged logo deletions.

Validation on exact Main28 + this seam, without compact Edge: 5 focused test
functions / 8 cases PASS, including real port fixture; mechanically extracted
old policy matches sequence, every field and Double bits across all six masks.
Debug arm64 App build PASS; ownership281 PASS; pinned509-file quality retains
270 existing findings, zero new debt, format PASS. Original statistics calendar
62.311s and rhythm/year51.235s PASS. IntegratedSharing failed129.222s waiting
for exported preview; exact original Main28 baseline also failed, exit65,
90 samples / one PID / peak1446088520B. Preserve both failures: no sharing
assertions or timeout changes, no claim of export closure or measured RAM gain.
Focused validation initially imported a shadowing old RailPresentation module;
retain that failed build. Corrected Core-only link directory compiled the real
new helper/tests against byte-identical Main28 Core; 5/8 passed with coverage
instrumentation. No full Domain/global coverage inference.

Current open evidence: Main28 sampler nine regressions and CI37950156025 pass.
Original Main18 Core byte-identical to Main28: first63 registered suites pass,
suite64 original25-test RailHistoryPackageTests stopped at2204289640B; no169-suite
or full coverage success. Compact Edge candidate stride824→184 and original
history25 PASS peak686917168B, but Release3+3 settled median438587016→517606616
(+18.016858%, FAIL), peak1201524168→673287240(-43.963904%); not adopted.
Same candidate Debug map guard peak2344833608B remains failed. Other owned
validation overlapped paired run, so no quiet CPU/latency acceptance either.

Remaining Main26 UI24 runs completed:63pass13fail11skip/87; source507 Swift
identical to Main28. Full137-test/39-class and earlier failures remain open.
One five-region input failure came from method identifier trailing parentheses
selecting two-region fixture; preserve failure. Correct committed five-region
fixture rerun original test PASS112samples/onePID/peak1249725920B. No product
assertion/fixture/threshold weakened. Original roadmap and matrix reflect these
limits rather than accumulate local successes into global acceptance.

Local receipts: statistics-line-coverage-main28-{candidate,tests,ui-validation,
quality,new-debt}, sharing-main28-baseline-validation, compact-edge-release-
paired-memory, history-compact-edge-main27-suite64, package-main18-isolated-
coverage-v9, platform-main26-ui-remaining-results and five-region recovery.
Temporary receipts are execution attachments; this committed summary is durable.
Full memory, platforms, global coverage, directory migration and M remain open.


## Phase30 — protect the physical-footprint sampler in CI

Run all nine existing Phase28 snapshot regressions in the pinned quality CI
before tool download and App/module work. This keeps actual process-exit nulls
unavailable rather than zero, preserves positive over-budget values and rejects
wrong/duplicate PIDs, malformed metrics and stale failed-command output.
Validation: exact discovery command nine PASS,0.018s; YAML adds only that command,
no fixture, App, process ownership, final-sample rule or 2GiB threshold changes.
Supplemental Phase29 LLVM export reports new helper57/57 lines,10/10 functions,
27/30 regions90%; only StatisticsLineCoverage, not module/Domain/global/App
coverage. Original full-package memory failure and unsettled Edge candidate
remain open. Unrelated CLI changes and staged logo deletions preserved.


## Phase31 — settle selected route inputs before enabling share export

The original Japan/2026-07-03 export failed intermittently because preview
rendering completed with two of its three selected routes. A later arrival
changed loadKey while the enabled Export tap was being synthesized; the button
action never entered. DEBUG event-order samples preserved2pass1fail; a component
trace proves fixed scope/date/three train IDs/storeGeneration3, selected rides
2→3 and only ridesKey changed while the global store remained loading. A passing
component trace identifies the arrival mechanism; it does not replace the
previous failed event-order and original baseline receipts.

Read existing completedInputs and active resolutionTickets for current selected
country/date/year/group/ridden records before narrowing Japanese area membership
by geometry. Include readiness in loadKey so terminal no-ride completion can
restart render even when vertices do not change. Keep existing terminal batch
failure eligible for unknown-distance presentation; never mark failures as
completed, so explicit retry still resolves unfinished inputs. Unrelated dates,
countries and active tickets do not delay export. Controller generation/key,
view ticket, cancellation, single permit and noncooperative buffer ownership
remain unchanged. No new retained arrays, dictionaries, caches, tasks or graph
owners; no change to physical proof, pending, mileage or geometry.

Validation: exact final Main30+candidate Debugarm64 Appbuild PASS;281 ownership
PASS;509-file quality270inherited/zero new debt, format PASS;13 actual-query tiny
input checks and58 production controller/view lifecycle checks PASS. Original
IntegratedSharing assertion/90s timeout/navigation unchanged: three SERIAL
samples PASS39.964, 39.534, 40.387s, 87 actual samples, peak1249971968B,
expected distinct fresh-process identities and no2GiB breach. Original
ConsoleSweep testWalkEverySurface PASS177.878s, 129
samples, peak335448992B. Correctness/latency here is not quiet paired
RAM/leak acceptance. First helper candidate passed its UI sample but was rejected
for terminal-failure liveness; failed layout v1/v2 both retain lost-text input
failure and are not shipped. A mistaken same-device parallel validation was
stopped using verified owned runner/child PIDs; those two receipts are invalid,
preserved separately, and never counted among these serial samples.

Main30 pinned quality CI37957246063 SUCCESS; Phase29 quality/parity jobs were
cancelled by its newer push, not recorded as PASS. Full refactor/memory/coverage,
layout, platforms and M remain open. Public VM-only Instruments diagnostic uses
a separate owned device and original Main26 baseline; none of that diagnostic
or rejected compact Edge is included in this commit. Temporary execution
receipts: share-selected-route-readiness-v2-* and sharing-export-probe-*.


## Phase32 — preserve the native verifier executable mode

Phase31's isolated index accidentally recorded ios/verify.sh as100644 instead
of its original100755. Restore only that executable bit; exact committed
script blob unchanged. Preserve the live CLI script bytes and staged logo
deletions. Source/content checks and original UI remain Phase31's evidence;
this correction adds no App or memory behavior. Verify prior/current tree
modes, executable live script and unchanged blob, plus bash syntax.


## Phase33 — compact optional physical junction payload on graph edges

Keep public PhysicalJunctionEdge as a value and store the uncommon optional
payload in a private immutable Sendable box. Copied Edge values share only
immutable payload storage; setting or clearing the payload creates or releases
that edge's box. Equality compares complete values, and the internal initializer
retains prior argument order/defaults. Nil payloads allocate no box. Edge stride
824→184 bytes; payload stride640 unchanged. No graph references/cycles, cache
policy, physical topology, surveyed geometry, date validity, pending or mileage
changes. This reduces storage per ordinary edge without truncating rail data.

Unchanged strict frozen Main27 Release JP Sonic44 + TW airport MRT protocol:
three fresh-process pairs in predefined alternating order, exact public routes
then ready All-regions Stats, five final actual footprint samples per trial,
2GiB guard. All six PASS. Settled medians415501960→412798192B (-0.650723%);
peak medians1193889224→674319408B (-43.519098%). Before settled samples
410980000/415501960/416337544; after412798192/414797064/411880688. The small
settled effect and mixed individual-pair direction remain visible. Before
binary ae44603fa9b672acee707734e8d78d822378ff3a25a73c8c042d1d66584b31b6;
after8088045f8a4360e91326cad7a8e7676d99e10c86de0c9e07802581eb20794c43.
Graph candidate d78122bd71b9c43472041e5b59e45a407b248fd03efe3faf67aa8569f8fc9c3f;
fixture5de394f3c5be1fe469faf7910cb227bc02b17f04dc8f3af3f46bd320433fb3f7.
The earlier overlapping-run comparison settled+18.016858% FAIL is preserved,
not replaced or pooled. The controlled repeat ran after all own builds/UI/traces
ended, except a brief public VM XML export/stream parse near trial1; no claim of
globally idle host or CPU/latency improvement. No threshold or trial exclusions.

Prior exact candidate:77 focused topology/value/compiled tests PASS; original
all25 RailHistoryPackageTests PASS, peak686917168B, versus original baseline
suite64 guard2204289640B. Rebased exact Main32 integration: both simulator
architectures Release App/test build PASS; current focused physical/value/Stats
tests PASS (compact-edge-main32-focused.log and additional-focused.log);
281 production ownership PASS;510 Swift files270 inherited/zero new lint debt,
format PASS. Original same two-region public Release correctness sample PASS,
peak683232352B, 66 samples,
one verified PID25251. Package measured source versus Main32
differs only by added stateless presentation StatisticsLineCoverage.swift; Core
identical to measured candidate. Current integration is not a paired comparison.

Independent value/lifetime review found no actionable defect. Full-map Debug
regional toggles still failed2344833608B on this candidate (an earlier same
binary run passed1065373392B); original baseline also failed2365068280B under
VM-only diagnostics. These distinct Debug/observer runs establish neither
paired map improvement nor regression. Whole-map2GiB failure, original global/
Domain coverage, five-region paired performance, leaks, launch/firstmap/stalls,
platform/layout and M gates remain OPEN; full refactor is not complete.
Receipts are local compact-edge-release-serialized-memory*, compact-edge-main32*,
history-compact-edge-main27-suite64 and earlier failed comparisons.


## Phase34 — isolate initial selected-journey camera intent in regression test

The selected-journey layout/statistics regression requested Haruka autofocus
and a delayed DEBUG New York camera override in the same launch. Omit only that
contradictory override in this one case. The launch helper accepts an optional
camera while retaining the same default New York value for every other call.
All original assertion bodies, timeout values, fixture, production focus logic
and six other test bodies remain byte-identical; structural proof reverses the
single camera:nil argument to recover the exact original failed test body.
This establishes a coherent initial intent, not a proven production race fix;
the earlier1fail6pass sample remains historical evidence.

Current accepted Main33 Debug candidate build PASS. All7 camera tests PASS
(39.556/15.539/27.983/12.365/15.230/13.579/20.369s), original public route/focus/
region/endpoint and layout/statistics assertions unchanged.100 actual footprint
samples, seven expected fresh App PIDs, peak800935272B, no2GiB breach.
510-file pinned quality270 inherited/zero new lint debt and format PASS. Test
launch preparation changes no production state, memory owners or physical proof.
Main33 pinned quality CI37963499759 SUCCESS; full package inventory1445functions/
171suites is running on fresh Main33 instrumentation, not yet full coverage PASS.
Full-map memory, layout/platform/M and original performance goals remain open.
Local receipts: camera-intent-main33-*, candidate structural-proof.json;
Main33 complete package work is package-main33-isolated-coverage*.


## Phase35 — keep resident sheet detents stable while the keyboard opens

The root GeometryReader previously contracted from approximately778 to484
points when Search took the keyboard. Medium and the selected height detent
changed with it; the native field then lost focus during a compact feedback
sample before any characters arrived. Keep this presenter's bottom keyboard
safe area independent of its window metrics. Presented content retains its
own system keyboard behavior. Preserve the genuine drag stream and existing
150ms predecessor filter; no notification observers, timers, caches or probe
logging enter production.

The viewport uses its logical compact stage and full tab clearance while
remaining mounted, disables only at Compact, and reserves13points above the
measured glass obstruction to satisfy the original12point fractional gap.
The earlier viewport-only candidate and diagnostic logging passes remain
rejected; low-impact native OSLog captured the actual failure. Keyboard will
hide preceded compact acceptance, so the chronology does not attribute the
initial dismissal solely to the disabled gate.

Validation: normal Main34+candidate Debug binary, three predefined serial
original All clearance/compact Search/repeated drag runs: all9 checks PASS.
Original shared-date/25:10 next-day navigation, add-stop cancel and typed
line/date editing all PASS; original shared-date case repeated once PASS.
Dedicated iPad original wide compact reopening/Search, title toggle and
header gesture checks PASS. Original test bodies, assertions, deadlines,
fixture, Dynamic Type and orientation constraints are unchanged. Debug and
arm64+x86_64 Release build-for-testing PASS.510 Swift files retain270 inherited
lint findings with zero new findings; format PASS.

These are bounded correctness/budget observations, not paired performance,
global memory, leak or full platform acceptance. Phase33's scoped strict
settled/peak reductions remain scoped. Full171suite/1445function fresh
coverage, whole-map2GiB failures, route stress final-batch identity, remaining
layout/platform/M and original launch/first-map/stall/build goals stay open.
Grok's bounded RouteStress extraction reached its turn limit without a full
result; Sol review established that actual stress fixtures have no explicit
pending records and missing raw sections normalize, so no count assertion is
relaxed and no geometry is fabricated. CLI dirty code/data and original staged
logo deletions are preserved separately from the frozen accepted source.
Local receipts: workspace-stable-keyboard-main34-*,
layout-oslog-focus-trace-main32-analysis.json; failed/disabled probe receipts
remain available. No complete-refactor claim.
