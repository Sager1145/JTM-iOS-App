# Queue 77: jp-一般社団法人札幌市交通事業振興公社-都心線

Read-only source/receipt preparation, 2026-10-19. Current package 2025.5.2; 3 stations / 2 intervals; 西4丁目→すすきの. Canonical identity comes from unique lineID first appearance in the scoped queue, ordinal starts 2.

Legacy plan: 2/2 exact current source/display/station-ID interval identities. Completed captures: 2; matching identity + recorded receipt file presence/byte counts: 2/4; missing/unusable legacy views: 2. No image verdict follows from receipts.

Missing intervals: [1]. One existing-schema request prepared, not run: `missing-native-request-20261019.json`; scratch copy `/private/tmp/jtm-sapporo-toshin-missing-request.json`.

| Interval | Stations | Legacy slot | Completed usable / planned | Missing |
|---|---|---:|---:|---:|
| 0 | 西4丁目→狸小路 | 413 | 2/2 | 0 |
| 1 | 狸小路→すすきの | 414 | 0/2 | 2 |

## Actual current stations

0: 西4丁目 (000235), 1: 狸小路 (000242), 2: すすきの (000251)

## Limits

- Availability + exact own source/display/station-ID comparison only; no PNGs visually reviewed in this preparation.
- Recorded byte counts checked; no content hashes recomputed. No native/app/build/tests or production changes.
- Whole-line dependency recorded verbatim, not recomputed; named-plan relevant own interval geometry/station IDs compared directly.
- Request includes only intervals with missing/unusable old evidence; interval-level request may also capture already completed viewpoints within a partially completed interval.

## Canonical input and rendering boundary

Order source is `ios/refactor-parallel/alignment-passenger-local-recheck-20261010.json`, unique `lineID` first appearance with ordinal = unique index + 2. Only ordinals 76–78 were selected. Current decoded compact source/display geometry and own station IDs were compared with actual immutable plans named by captured receipts. None of these current own records has a line-level display interval/station override. Receipt files were checked only for presence and recorded byte count; no hashes recomputed. Historical contracts are isolated zero-lane z17 (`fixed-z17-v2`, 1024×768), not Main composition or current network acceptance. Original PNGs viewed in this preparation: **0**.

## Existing Sapporo archive: present, not counted as identity-verified

Two original captured #1 pairs also exist under `/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/sapporo-complete-native-before/toshin/000414/{000000,000001}`. All 14 receipt-listed files exist with matching recorded byte counts. Their state/view metadata reference `identity-plan-a4f9c4e1338262555fbca0836c0771ba106b74418fce59982aa6a65ce014a140.json`; that actual immutable plan is unavailable in the original Library and this archived scope. They are retained historical evidence, but not added to the named-plan-verified count by assuming another plan has equivalent inputs. Therefore the scoped missing/unproven request remains only #1 狸小路→すすきの, two viewpoints. It has been prepared, not run. Restoring that exact named plan could resolve this evidence gap without recapture.
