# Queue 63: jp-とさでん交通-桟橋線

Read-only source/receipt preparation, 2026-10-18. Current package 2025.5.2; 8 stations / 7 intervals; 桟橋通五丁目→はりまや橋. Canonical identity comes from unique lineID first appearance in the scoped queue, ordinal starts 2.

Legacy plan: 7/7 exact current source/display/station-ID interval identities. Completed captures: 10; matching identity + recorded receipt file presence/byte counts: 10/17; missing/unusable legacy views: 7. No image verdict follows from receipts.

Missing intervals: [0, 4, 6]. One existing-schema request prepared, not run: `missing-native-request-20261018.json`; scratch copy `/private/tmp/jtm-tosaden-sanbashi-missing-request.json`.

| Interval | Stations | Legacy slot | Completed usable / planned | Missing |
|---|---|---:|---:|---:|
| 0 | 桟橋通五丁目→桟橋車庫前 | 258 | 0/2 | 2 |
| 1 | 桟橋車庫前→桟橋通四丁目 | 259 | 3/3 | 0 |
| 2 | 桟橋通四丁目→桟橋通三丁目 | 260 | 2/2 | 0 |
| 3 | 桟橋通三丁目→桟橋通二丁目 | 261 | 2/2 | 0 |
| 4 | 桟橋通二丁目→桟橋通一丁目 | 262 | 0/2 | 2 |
| 5 | 桟橋通一丁目→梅の辻 | 263 | 3/3 | 0 |
| 6 | 梅の辻→はりまや橋 | 264 | 0/3 | 3 |

## Actual current stations

0: 桟橋通五丁目 (009201), 1: 桟橋車庫前 (009200), 2: 桟橋通四丁目 (009195), 3: 桟橋通三丁目 (009192), 4: 桟橋通二丁目 (009182), 5: 桟橋通一丁目 (009176), 6: 梅の辻 (009155), 7: はりまや橋 (009117)

## Limits

- Availability + exact own source/display/station-ID comparison only; no PNGs visually reviewed in this preparation.
- Recorded byte counts checked; no content hashes recomputed. No native/app/build/tests or production changes.
- Whole-line dependency recorded verbatim, not recomputed; named-plan relevant own interval geometry/station IDs compared directly.
- Request includes only intervals with missing/unusable old evidence; interval-level request may also capture already completed viewpoints within a partially completed interval.
