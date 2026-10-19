# Route stress testing

> Historical record retained during the 2026-10-10 documentation cleanup. Dates, measurements and unresolved findings below apply to the recorded inputs. Old execution commands are not current instructions; follow [the current verification policy](../../../ios/VERIFICATION.md).

Run the reproducible 10,000-journey core workload:

```sh
python3 ios/tools/run-route-stress.py --count 10000 --jobs 2
```

The runner generates varied and dense/colliding fixtures, imports five 2,000-record parts, and runs the seven stress tests against symlinked production RailCore sources in a scoped Swift package. It saves fixtures, command logs and a machine-readable `summary.json` under `outputs/route-stress-runner/runs/`. This is a focused stress suite; simulator tests and the full regression suite run separately.

## Verified run: 2026-10-03

The runner completed successfully at `outputs/route-stress-runner/runs/20261003T183657.296317Z/summary.json`: **7 tests passed in 95.266 seconds**, with a fresh Release build. It generated 10,000 varied and 10,000 dense/colliding records. The varied workload spans five regions, 39 dates, 232 source itineraries and 88 region-qualified line names.

| Operation | Journeys | Seconds |
| --- | ---: | ---: |
| Mixed JSON import | 10,000 | 10.923 |
| Canonical export, validation and reopen | 10,000 | 20.432 |
| Five sequential part imports, export and reopen | 10,000 | 30.255 |
| Dense collision import, export and reopen | 10,000 | 29.567 |
| Repeated-ID rapid append | 10,000 | 1.790 |

Cache invalidation, late-failure rollback/retry and suffix allocation/copy tests also passed. These are observed timings, not performance guarantees or before/after speedup measurements. Export tests compare complete canonical models because existing export rules normalize missing route sections; stop identities, clocks and metadata remain independently checked.

**Simulator rendering and rapid-highlight runtime verification remain pending.** A successful app/test build does not establish a passing UI run.

## Manual fixture generation

Generate reproducible synthetic journeys from the application's existing source itineraries:

```sh
python3 ios/tools/generate-route-stress-data.py \
  --count 10000 --part-size 2000 --output-dir outputs/route-stress-20261003
```

The generator preserves source dates, stop times, station codes and route sections. It changes record IDs and attaches explicit regions. These are load-test repetitions, not independent timetable or historical-route verification. The manifest records country/region distribution, dates, source itineraries, stop/section counts and byte sizes. `--scenario dense` concentrates each region on an existing busy date; `--id-mode colliding` intentionally exercises import renaming. Import split parts in **append** mode. The app's file reader limit remains 64 MiB per file.

The core stress suite exercises real import validation, progressive event order, canonical JSON export/reimport, unique identity allocation, duplicate-ID bursts, external replacement, failed-row isolation and late rollback. It reports wall-clock durations without using hardware-dependent timing thresholds:

```sh
JTM_STRESS_TRAIN_COUNT=10000 \
JTM_STRESS_STORE_PATH=outputs/route-stress-20261003/stress-all.json \
swift test --package-path ios/RailKit --configuration release \
  --scratch-path outputs/route-stress-20261003-build --filter RouteStoreStressTests
```

Without `JTM_STRESS_STORE_PATH`, the suite generates its own deterministic source copies. The regular test workload has at least 2,100 journeys; duplicate-ID testing always performs at least 10,000 additions. The path override validates the generator's actual artifact through the production importer.

`RouteStressTests` runs the production iOS store and MapKit renderer through a DEBUG-only opt-in harness. It exercises rapid record addition, multi-country/date selection bursts, and app export/reimport. The harness operates in memory. Its render probe checks installed overlays/renderers and the final submitted selection; display-link gaps measure main-run-loop delivery, not GPU presentation. A passing overlay check does not independently prove every pixel is geographically correct.

Coordinate a serial slot on the existing standard simulator through the integration workflow and retain the `.xcresult` attachments. Do not create a fleet, erase the device, or overwrite user journey data. Simulator results are not device memory or frame-rate guarantees. Do not run multiple performance suites against the same simulator at once.

## Scalability changes

- Import identity tracking mutates its cached Set directly only after validation succeeds. A per-base suffix cursor avoids scanning all earlier duplicate suffixes again. External array mutations invalidate both caches; failed validation leaves IDs available.
- Rapid edits cancel superseded date-grouping tasks. The tasks yield before starting and check cancellation between phases and while collecting buckets; generation checks still prevent stale publication.
- App JSON export normalizes and serializes one journey at a time, retaining the output string instead of a second complete train array and dynamic JSON tree. Existing byte-for-byte export and persistence regression checks cover format preservation.

```sh
xcodebuild -project ios/RailMap.xcodeproj -scheme RailMap \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  -derivedDataPath outputs/route-stress-20261003-xcode \
  -resultBundlePath outputs/route-stress-20261003-results.xcresult \
  -only-testing:RailMapUITests/RouteStressTests test
```

Defaults are 1,000 imports, 100 rapid additions and 60 selection requests spaced 25 ms apart. To override through `xcodebuild`, use `TEST_RUNNER_RAILMAP_STRESS_COUNT`, `TEST_RUNNER_RAILMAP_STRESS_ADDITIONS`, and `TEST_RUNNER_RAILMAP_STRESS_SWITCHES` in its environment (or the corresponding unprefixed keys in the `.xctestrun` test environment). The UI samples cover Japan, Taiwan, Hong Kong, Macao and South Korea; the core generator uses the same five supported regions. Retired North America archives are never test inputs.

If Xcode cannot discover a simulator that `simctl` can operate, build for `generic/platform=iOS Simulator` with `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`, install an isolated test-bundle copy of that debug app during the coordinated simulator slot, and launch the same harness directly:

```sh
SIMCTL_CHILD_RAILMAP_UI_TEST_STRESS=1 \
SIMCTL_CHILD_RAILMAP_STRESS_AUTORUN=1 \
SIMCTL_CHILD_RAILMAP_UI_TEST_TAB=all \
SIMCTL_CHILD_RAILMAP_UI_TEST_STATS_REGION=all \
SIMCTL_CHILD_RAILMAP_UI_TEST_STAGE=compact \
SIMCTL_CHILD_RAILMAP_UI_TEST_CAMERA=37,138,24 \
xcrun simctl launch <SIMULATOR-UDID> <ISOLATED-TEST-BUNDLE-ID> \
  -AppleLanguages '(en)' -AppleLocale en_US \
  -map-follows-selected-date NO -auto-focus-zoom NO
```

This uses the same real app operations and map probes, without XCTest discovery. Read `Library/Caches/route-stress-result.json` below the container returned by `xcrun simctl get_app_container <SIMULATOR-UDID> <ISOLATED-TEST-BUNDLE-ID> data`. An intermediate report has `complete: false`; only a final `complete: true, passed: true` establishes success. It records timeouts and the last map state on failure. Scale direct runs with `SIMCTL_CHILD_RAILMAP_STRESS_COUNT`, `SIMCTL_CHILD_RAILMAP_STRESS_ADDITIONS`, and `SIMCTL_CHILD_RAILMAP_STRESS_SWITCHES`.
