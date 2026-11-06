# Regression guards (2026-11-06)

Run all of them: `bash ios/tools/run-regression-guards.sh` (see `ios/VERIFICATION.md`, "Regression guards").
Each entry: cause, symptom, guard, and the fix the guard prints. Baselines are shrink-only. Regenerate an
expectation only for a reviewed data change (`JTM_REGENERATE_EXPECTATIONS=1 swift test --package-path ios/RailKit --filter <Suite>`),
never to silence a code regression.

| # | Failure | Commit | Guard |
|---|---|---|---|
| 1 | CN junction rows broke all-region counts | 2535b4bee (3721 station-less CN rows) | per-region junction counts; `DataCountExpectations` for data counts |
| 2 | 箕面船場 / 稲荷町 / 11 class seams without a junction | 2535b4bee data + 8c332340b identity@coord graph keying | `RegressionGuardTopologyGaps` |
| 3 | Toyama and 6 more history stamp families lost | 2535b4bee (10-19 rebuild) | `RegressionGuardHistoryStamps` |
| 4 | 日豊線 立石 split: one-direction tracks | 2535b4bee 立石 resurvey + 8c332340b certifier | `RegressionGuardPairedTracks` |
| 5 | Stale fixtures, sample parts, historical-routes v25, count pins | 2535b4bee, 8c332340b, aa461bb74, 0ba072e38, 5365e3445 | `RegressionGuardArtifactRevisions` + stamps |
| 6 | Swift/JS key, operator-name, i18n, stroke drift | b575ef10c (route key from_st/to_st); operator names and i18n diverged earlier | parity suites in the guard set |
| 7 | Hard-corner sway | (stroke change) | stroke parity + deviation tests |
| 8 | `rideEditorVehicleType` UI id missing | (UI id rename) | `check-ui-test-identifiers.sh` |

Attributions come from this branch's investigation (see the commit messages on claude/railkit-test-failures-782ac7).

## 1. CN junction rows broke all-region counts
- Symptom: adding CN junction rows changed the all-region topology counts, so a pinned count failed far from the cause.
- Guard: junction tests count per region (`registry.junctions(for: "jp")`, separate jp and cn pins in `ShortLinkJunctionTests`), so a new region's rows cannot shift another region's counts. Data-dependent counts elsewhere (station-display, import) live in revision-checked `DataCountExpectations` files.
- Fix printed: "data changed: review key old to new and run `JTM_REGENERATE_EXPECTATIONS=1 swift test ... --filter <suite>`; commit the diff", or "code regression; do not regenerate" when the stamped inputs are unchanged.

## 2. 箕面船場 / 稲荷町 / 11 class seams with no junction
- Symptom: two lines of one operator meet at a station but the physical graph cannot cross between them.
- Guard: `RegressionGuardTopologyGaps` (tier 1 rules R1 row geometry, R2 through-service boundary, R3 row terminus; ratchet against `topology-gap-baseline.json`; registry `stationCode` check for `physical-rail-junctions.json`).
- Fix printed: "add a junction row to app/data/physical-rail-junctions.json (pattern: astram-kencho-class16-class24) or a reviewed mark to reviewed-unconnected-continuations.json", then delete the baseline entry. Regenerate: `JTM_REGENERATE_EXPECTATIONS=1 swift test --package-path ios/RailKit --filter RegressionGuardTopologyGaps` (reviewed data only).
- Baseline detail: `2026-11-06-junction-gaps.md`.

## 3. Toyama and 6 more history stamp families lost in the 10-19 rebuild
- Symptom: events (仙台空港線, 4号線, 中之島線, 門司港レトロ観光線, 東急新横浜線, 北海道新幹線, Toyama) lost or narrowed `retirements` stamps in `rail-history.json`; new features showed as old.
- Guard: `RegressionGuardHistoryStamps` (no-stamp, wrong dates, dead match, uncovered sections/stations, km mismatch; shrink-only baseline).
- Fix printed: "restore the stamp (see git log -S <id>) and bump revision; builder source: ..." (builder is in the website repo, so edit the data file here and report the builder). Regenerate baseline: `JTM_REGENERATE_EXPECTATIONS=1 swift test --package-path ios/RailKit --filter RegressionGuardHistoryStamps`.
- Detail: `2026-11-06-history-stamp-gaps.md`.

## 4. 日豊線 立石 split: one-direction tracks
- Symptom: a split line produced a paired track that carried only one direction, or a real branch was treated as a paired track.
- Guard: `RegressionGuardPairedTracks` (catalog validates against jp-2025 without dropping entries; every `paired_alignment` row is in the catalog; branches are in `notPairs`; up/down track preserved).
- Fix printed: the failing `#expect` names the paired line id and the rejection reason; edit `japan-paired-tracks.json` (add the pair or list the branch under `notPairs`). No regenerate command; this guard has no baseline.

## 5. Stale port fixtures / sample parts / historical-routes v25 / count pins
- Symptom: artifacts stayed from an older data or solver revision and failed later with an opaque diff.
- Guard: `RegressionGuardArtifactRevisions` re-hashes inputs against provenance stamps (samples, port fixtures, expectations; `legacyUnstampedFixtures` is shrink-only), plus `SamplePrecomputeProvenanceTests`.
- Fix printed: `key old to new` plus the regenerate command, e.g. `node app/scripts/build/build-port-fixtures.mjs --only=<name>.json` for fixtures, or the sample/expectation regenerate command from the stamp.

## 6. Swift/JS key, operator-name, i18n and stroke drift
- Symptom: the two implementations disagreed (route key, operator names built from the registry, i18n strings, stroke geometry).
- Guards (Swift suites in the one `swift test` run): `PlaybackParityTests`, `RouteGraphParityTests` (route key), `SamplePrecomputeProvenanceTests` (operator names / provenance), `LocalizationParityTests` (i18n), `ContinuousStrokeParityTests` (stroke), `TravelDirectionTests`, `DirectionalAlignmentSelectionTests`; plus `node app/scripts/build/build-port-fixtures.mjs --check --only=<f>.json` for 15 fast fixtures.
- Fix: mirror the Swift change in the JS reference (or the reverse), then `node app/scripts/build/build-port-fixtures.mjs --only=<name>.json`; the `--check` failure says which fixture moved.

## 7. Hard-corner sway
- Symptom: a stroke wobbled at sharp corners.
- Guard: `ContinuousStrokeParityTests` and the deviation tests in the same suite.
- Fix: correct the stroke code; regenerate `continuous-stroke.json` only if the new output is the reviewed intent.

## 8. `rideEditorVehicleType` UI id
- Symptom: a UI test referenced an accessibility id the app no longer had.
- Guard: `ios/tools/check-ui-test-identifiers.sh` (static, no simulator).
- Fix printed: the missing id and the file that references it; restore the id in `ios/RailMap` or update the test.

## Not covered
- The 56 junction gaps (4 R1, 52 R2) and the 10 history events (15 entries) held in the baselines: they are tolerated until fixed, then must be removed.
- Fixtures already red or slow, so excluded from the script: route-graph, route-station-candidates, route-section-solve, route-solver-core, import, station-join-smoothing (red); operator-branding, route-feature (red when the script was written); historical-routes (slow). `RailHistoryPackageTests` (~15 min) and `JunctionApproachTests` (~11 min) are also excluded.
- Website-repo builders (`~/Documents/GitHub/Japan-Train-Map`), including `build-jp-rail-history.py`.
- UI runtime behaviour: the identifier check is static; no layout, gesture or pixel check.
