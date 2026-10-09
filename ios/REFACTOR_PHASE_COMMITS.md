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

Status: memory/ownership validation complete; functional registry failure remains.

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
