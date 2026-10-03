# Route stress testing

Generate reproducible synthetic journeys from the application's existing source itineraries:

```sh
python3 ios/tools/generate-route-stress-data.py \
  --count 10000 --part-size 2000 --output-dir /tmp/jtm-route-stress
```

The generator preserves source dates, stop times, station codes and route sections. It changes record IDs and attaches explicit regions. These are load-test repetitions, not independent timetable or historical-route verification. The manifest records country/region distribution, dates, source itineraries, stop/section counts and byte sizes. `--scenario dense` concentrates each region on an existing busy date; `--id-mode colliding` intentionally exercises import renaming. Import split parts in **append** mode. The app's file reader limit remains 64 MiB per file.

The core stress suite exercises real import validation, progressive event order, canonical JSON export/reimport, unique identity allocation, duplicate-ID bursts, external replacement, failed-row isolation and late rollback. It reports wall-clock durations without using hardware-dependent timing thresholds:

```sh
JTM_STRESS_TRAIN_COUNT=10000 \
JTM_STRESS_STORE_PATH=/tmp/jtm-route-stress/stress-all.json \
swift test --package-path ios/RailKit --configuration release \
  --scratch-path /tmp/jtm-route-stress-build --filter RouteStoreStressTests
```

Without `JTM_STRESS_STORE_PATH`, the suite generates its own deterministic source copies. The regular test workload has at least 2,100 journeys; duplicate-ID testing always performs at least 10,000 additions. The path override validates the generator's actual artifact through the production importer.

`RouteStressTests` runs the production iOS store and MapKit renderer through a DEBUG-only opt-in harness. It exercises rapid record addition, multi-country/date selection bursts, and app export/reimport. The harness operates in memory. Its render probe checks installed overlays/renderers and the final submitted selection; display-link gaps measure main-run-loop delivery, not GPU presentation. A passing overlay check does not independently prove every pixel is geographically correct.

Run on a dedicated simulator and retain the `.xcresult` attachments. Simulator results are not device memory or frame-rate guarantees. Do not run multiple performance suites against the same simulator at once.

## Scalability changes

- Import identity tracking mutates its cached Set directly only after validation succeeds. A per-base suffix cursor avoids scanning all earlier duplicate suffixes again. External array mutations invalidate both caches; failed validation leaves IDs available.
- Rapid edits cancel superseded date-grouping tasks. The tasks yield before starting and check cancellation between phases and while collecting buckets; generation checks still prevent stale publication.
- App JSON export normalizes and serializes one journey at a time, retaining the output string instead of a second complete train array and dynamic JSON tree. Existing byte-for-byte export and persistence regression checks cover format preservation.

```sh
xcodebuild -project ios/RailMap.xcodeproj -scheme RailMap \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  -derivedDataPath /tmp/jtm-route-stress-xcode \
  -resultBundlePath /tmp/jtm-route-stress-results.xcresult \
  -only-testing:RailMapUITests/RouteStressTests test
```

Defaults are 1,000 imports, 100 rapid additions and 60 selection requests spaced 25 ms apart. To override through `xcodebuild`, use `TEST_RUNNER_RAILMAP_STRESS_COUNT`, `TEST_RUNNER_RAILMAP_STRESS_ADDITIONS`, and `TEST_RUNNER_RAILMAP_STRESS_SWITCHES` in its environment (or the corresponding unprefixed keys in the `.xctestrun` test environment). The UI samples cover Japan, Taiwan, Hong Kong, Macao and South Korea; the core generator additionally covers Canada and the United States.

If Xcode cannot discover a simulator that `simctl` can operate, build for `generic/platform=iOS Simulator` with `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`, install that debug app on an isolated simulator, and launch the same harness directly:

```sh
SIMCTL_CHILD_RAILMAP_UI_TEST_STRESS=1 \
SIMCTL_CHILD_RAILMAP_STRESS_AUTORUN=1 \
SIMCTL_CHILD_RAILMAP_UI_TEST_TAB=all \
SIMCTL_CHILD_RAILMAP_UI_TEST_STATS_REGION=all \
SIMCTL_CHILD_RAILMAP_UI_TEST_STAGE=compact \
SIMCTL_CHILD_RAILMAP_UI_TEST_CAMERA=37,138,24 \
xcrun simctl launch <SIMULATOR-UDID> com.JRM.RailMap \
  -AppleLanguages '(en)' -AppleLocale en_US \
  -map-follows-selected-date NO -auto-focus-zoom NO
```

This uses the same real app operations and map probes, without XCTest discovery. Read `Library/Caches/route-stress-result.json` below the container returned by `xcrun simctl get_app_container <SIMULATOR-UDID> com.JRM.RailMap data`. An intermediate report has `complete: false`; only a final `complete: true, passed: true` establishes success. It records timeouts and the last map state on failure. Scale direct runs with `SIMCTL_CHILD_RAILMAP_STRESS_COUNT`, `SIMCTL_CHILD_RAILMAP_STRESS_ADDITIONS`, and `SIMCTL_CHILD_RAILMAP_STRESS_SWITCHES`.
