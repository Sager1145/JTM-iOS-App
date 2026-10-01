# Timetable data handoff — 2026-09-30

This checkpoint preserves the integrated regional work and corrects eight independently verified missing `||` rows. Timetable data is frozen for integration reads. Full Python regression and the RailKit core gate passed. Nationwide completion remains blocked.

## Stable snapshot

- Canonical records: **40,005**.
- Templates: **882**; represented planned dated instances: **2,403**; passenger stop records: **8,520**.
- Services: **68**; source documents: **1,216**; trip relations: **88**.
- Independent symbols: **24** — 15 `レ`, 9 `||`; source verification covers three selected columns only.
- September 29 / September 30 instances: **25 / 769**.
- Database SHA-256: `af8568aa8b5ecadee80ec335891d9d0a7f7b0edb918b421bd7436088d07996f4`.
- Canonical source fingerprint: `9b67f9950604dc43eee861bbc48d0661ebb58033fac963f4775dda71b7a5a5d0`.
- Historical network revision: `2026-09-28.3`; content hash: `c6feed755ece7a664434592e0b910386493611e62b4d82b5e5aede98c3e99cb3`.
- Canonical and bundled service timetable SQLite are byte-identical. A separate temporary build is also byte-identical.

## Changes and independent comparison

The predecessor registered five already-reviewed batches in the unified rebuild: Azusa26/33/44, Inaho1/3 + Shirayuki2/4, Hyuga13/14/16, Ishizuchi3/5/7/9 and Yakumo13–16. Azusa44 is normalized before Fuji44, so both coupling directions can be created in the first build.

A separate GPT-6.1 Sol audit compared **18 dated trips and 213 passenger calls** against normalized materialization and SQLite, including all printed and blank clocks/platforms, exact-day calendars/versions, train numbers, endpoints and planned formation fields. No discrepancy was found. Its **288 core-row subtotal** means 18 trips + 213 stops + 18 formations + 18 versions + 18 calendars + 2 Yakumo15 platform overrides + 1 Azusa44 coupling relation; it excludes calendar exceptions, provenance/completeness rows and the reciprocal Fuji44 relation. Both coupling sections are 大月 → 八王子 → 立川 → 新宿; Fuji's unprinted through clocks remain unknown. The six focused batch/coupling test files passed **21 tests** against the preceding passenger-identical snapshot.

The current continuation source-checked all 16 existing symbol rows and found eight missing `||` branch rows. They now regenerate from reviewed candidates; Hokuto2's later `レ` positions shift to retain printed order. See [symbol source audit](train-timetable-symbol-source-audit-2026-09-30.md). Passenger stop counts, clock values, routes and date scope are unchanged. Swift runtime regression assertions now check both directions and separate symbols from passenger calls. Four redundant optional-unwrapping macros were removed from the report-backed lookup test; assertions remain intact.

## Verification

- `python3 ios/tools/rebuild-reviewed-train-timetable.py`: passed, exit 0.
- `python3 ios/tools/validate-train-timetable.py`: passed through unified rebuild, 40,005 records.
- `python3 ios/tools/verify-train-timetable-artifact.py`: passed, snapshot aligned, no integrity/foreign-key/snapshot errors.
- Separate `train_timetable.build_database` to a temporary file: passed, byte-identical hash above.
- `python3 ios/tools/audit-train-timetable-migration.py --check`: passed.
- `python3 ios/tools/build-train-service-station-refs.py --check`: passed, 3,512 station refs in 298 legacy patterns.
- `python3 ios/tools/test_jreast_trip_parser.py`: **3/3 passed**.
- Source-pinned Hokuto/Suzuran tests: **4/4 passed**, including new full symbol order assertion.
- Full `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s ios/tools/tests -v`: **1,005/1,005 passed**, 704.542 seconds. Log: `/private/tmp/jtm-resume-final-python-20260930.log`.
- Full `SCRATCH=/private/tmp/jtm-resume-final-railkit-20260930 CLANG_MODULE_CACHE_PATH=/private/tmp/jtm-resume-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/jtm-resume-module-cache ./ios/verify.sh --core`: **passed**, exit 0 and final `OK`. **926 Swift tests passed**: 315 in 29 presentation suites (0.839 seconds), 611 in 67 core suites (1,004.678 seconds). This includes the revised symbol assertions and the full 298 service-pattern argument set. Log: `/private/tmp/jtm-resume-final-core-gate-20260930.log`; full Swift output: `/private/tmp/jtm-resume-final-railkit-20260930.log`.
- The core gate also passed 35 production editor validation cases, 18 persistence harness checks, 10 subscription-auth cases and 9 production subscription-HTTP cases, warning checks and pure-target/display-source contracts. These checks do not build or run the iOS app; simulator acceptance remains with the UI owner.

Exact artifact and test-log hashes are retained in the [validation checkpoint](../app/data/train-service-history/audits/train-timetable-validation-checkpoint-20260930.json). Timetable writers and validation commands have finished; remaining integration work must preserve the frozen snapshot or rerun the affected checks.

The first fresh full-suite runs were intentionally stopped before correcting the confirmed missing source symbols. They are not counted as successful full validation. A throwing-call syntax error in the new Swift test was fixed before restarting the final core gate.

## Unfinished source gaps and integration limits

- **2,448 missing coverage cells**, plus **48 partial/blocked cells**. No operator's complete historical inventory is certified.
- **7,607 passenger route intervals unverified**. Only 275 line segments have identity evidence; zero have full dated temporal attestation. The route audit has not executed the solver.
- **1,114 historical alignment checks unverified**, zero aligned, zero reported errors; no timetable trip has a publishable verified route.
- **69 unresolved station references**, **2 unresolved sources**.
- Chronology checks cover **21,549 known clock cells** in 2,403 represented instances, with zero structural findings. **709 passenger calls have neither clock**; source truth remains unverified.
- Unknown vehicle series, capacities, actual dispatch, physical line/operator segments and unprinted clocks/platforms remain unknown. Standard/planned formation evidence is not actual operation evidence.
- Source URLs/date/column locators are retained, but the symbol audit did not retain raw original HTML/PDF/image files. Reproduction/processing permission gaps remain recorded in the source registry.

No commits, merges, pushes or automations were made by this continuation. Structural test success cannot satisfy the original nationwide completion gate. The final user-facing report remains owned by the report continuation: [verification report](train-timetable-verification-2026-09-29.md).
