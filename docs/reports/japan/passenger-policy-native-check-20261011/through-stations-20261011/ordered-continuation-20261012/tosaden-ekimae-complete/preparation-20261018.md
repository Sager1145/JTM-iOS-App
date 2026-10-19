# Queue 64: jp-とさでん交通-駅前線

Read-only source/receipt preparation, 2026-10-18. Current package 2025.5.2; 4 stations / 3 intervals; 高知駅前→はりまや橋. Canonical identity comes from unique lineID first appearance in the scoped queue, ordinal starts 2.

Legacy plan: 3/3 exact current source/display/station-ID interval identities. Completed captures: 4; matching identity + recorded receipt file presence/byte counts: 4/6; missing/unusable legacy views: 2. No image verdict follows from receipts.

Missing intervals: [1]. One existing-schema request prepared, not run: `missing-native-request-20261018.json`; scratch copy `/private/tmp/jtm-tosaden-ekimae-missing-request.json`.

| Interval | Stations | Legacy slot | Completed usable / planned | Missing |
|---|---|---:|---:|---:|
| 0 | 高知駅前→高知橋 | 265 | 2/2 | 0 |
| 1 | 高知橋→蓮池町通 | 266 | 0/2 | 2 |
| 2 | 蓮池町通→はりまや橋 | 267 | 2/2 | 0 |

## Actual current stations

0: 高知駅前 (009098), 1: 高知橋 (009107), 2: 蓮池町通 (009111), 3: はりまや橋 (009117)

## Limits

- Availability + exact own source/display/station-ID comparison only; no PNGs visually reviewed in this preparation.
- Recorded byte counts checked; no content hashes recomputed. No native/app/build/tests or production changes.
- Whole-line dependency recorded verbatim, not recomputed; named-plan relevant own interval geometry/station IDs compared directly.
- Request includes only intervals with missing/unusable old evidence; interval-level request may also capture already completed viewpoints within a partially completed interval.
