# Python Tests 2 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## PY2-1 [P2] Isolate normalizer writes from the repository in the tests

Primary anchor: [ios/tools/tests/test_discovery_east_2026_source_pinned.py:21-27](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/tests/test_discovery_east_2026_source_pinned.py:21).
Related anchor: [ios/tools/tests/test_central_hida1_nanki1_current_n02_routes_20260930_source_pinned.py:106-111](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/tests/test_central_hida1_nanki1_current_n02_routes_20260930_source_pinned.py:106) and `:113-120`.

The discovery test's setUpClass launches normalize-reviewed-east-shiosai6-discovery.py with no alternate root. That script binds BASE to the repository canonical directory (:8), writes every discovery output through outputs (:159-205) and write_jsonl (:208-209). Setup therefore replaces the stored normalized trips, stops, calendar, names and evidence immediately before the assertions read them. A missing discovery trip/calendar output, or a wrong interior clock in the normalized output, is regenerated from the candidate before this test reads it; the test can pass while failing to detect the bad stored artifact it is presented as checking. It also changes the user's repository as a side effect of running a test.

The route-normalizer test similarly calls MODULE.normalize(BASE, ...) with the repository root. normalize performs real writes at normalize-reviewed-central-hida1-nanki1-current-n02-routes-20260930.py:294-300. The before/after assertion does not restore files when bytes differ, and the negative-case test changes only candidate_path to a temporary file while still using BASE. If a regression causes the altered candidate to be accepted, the assertion fails after the canonical outputs have been overwritten.

Exercise the writing normalizer using a temporary fixture root and inspect returned/generated artifacts there. If the discovery checks are intended to validate shipped stored outputs, read them directly without normalizing first. Keep independent source literals and the legitimate route-only station/date assertions.

## Oracle and seam assessment

The many source-pinned tests are primarily preservation checks across candidate -> normalized seed -> materialized daily trip or SQLite seams. Independent inline station/clock/platform literals in the Hida/Shinano/NEX/Hitachi/Tokiwa/Shonan/Fuji families are useful worked-example oracles. Checks for null clocks, selected-day exclusivity, calendar variants, midnight offsets, split train numbers and printed coupling ranges represent meaningful contracts, even when output data lives behind a filesystem seam.

Some tests obtain expected hashes, source URLs or stop matrices from the same production normalizer under test: Sonic batches 58-202, 35-41/Uwakai15-21, 27-33/Uwakai26-32, 16-22/51-57; Kinosaki1; Thunderbird1; Yakumo12. Their candidate-preservation checks can still fail and are not by-construction tautologies, but coordinated changes to production pins and their input candidates have no independent test oracle. This is a scope limitation; this audit does not claim an observed wrong source fact merely from that coupling. Other preservation tests use reviewed candidates as fixtures and pin only selected fields independently; they do not prove that every candidate value matches the external timetable, nor claim physical route solvability.

No external timetable content was fetched, no source hashes were recomputed, and runtime/pixel/performance behavior was not measured. Remaining factual source provenance is the reviewed repository evidence.
