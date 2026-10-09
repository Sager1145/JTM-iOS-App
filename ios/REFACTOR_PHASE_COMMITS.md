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

Status: validated locally for independent commit/push; hosted CI execution pending.

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
