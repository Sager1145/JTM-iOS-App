# Queue 70: jp-アルピコ交通-上高地線

Read-only source/receipt preparation, 2026-10-19. Current package 2025.5.2; 14 stations / 13 intervals; 松本→新島々. Canonical identity comes from unique lineID first appearance in the scoped queue, ordinal starts 2.

Legacy plan: 13/13 exact current source/display/station-ID interval identities. Completed unique captures: 56 (53 Library + 3 exact primary Matsumoto archive); matching identity + recorded receipt file presence/byte counts: 56/60; missing/unusable legacy views: 4. No image verdict follows from receipts.

Missing intervals: [1]. One existing-schema request prepared, not run: `missing-native-request-20261019.json`; scratch copy `/private/tmp/jtm-alpico-kamikochi-missing-request.json`.

| Interval | Stations | Legacy slot | Completed usable / planned | Missing |
|---|---|---:|---:|---:|
| 0 | 松本→西松本 | 333 | 3/3 | 0 |
| 1 | 西松本→渚 | 334 | 0/4 | 4 |
| 2 | 渚→信濃荒井 | 338 | 3/3 | 0 |
| 3 | 信濃荒井→大庭 | 339 | 4/4 | 0 |
| 4 | 大庭→下新 | 340 | 6/6 | 0 |
| 5 | 下新→北新・松本大学前 | 341 | 5/5 | 0 |
| 6 | 北新・松本大学前→新村 | 342 | 4/4 | 0 |
| 7 | 新村→三溝 | 343 | 5/5 | 0 |
| 8 | 三溝→森口 | 344 | 4/4 | 0 |
| 9 | 森口→下島 | 345 | 4/4 | 0 |
| 10 | 下島→波田 | 335 | 6/6 | 0 |
| 11 | 波田→渕東 | 336 | 6/6 | 0 |
| 12 | 渕東→新島々 | 337 | 6/6 | 0 |

## Actual current stations

0: 松本 (002506), 1: 西松本 (002512), 2: 渚 (002511), 3: 信濃荒井 (002510), 4: 大庭 (002513), 5: 下新 (002516), 6: 北新・松本大学前 (002523), 7: 新村 (002528), 8: 三溝 (002532), 9: 森口 (002538), 10: 下島 (002540), 11: 波田 (002545), 12: 渕東 (002546), 13: 新島々 (002555)

## Limits

- Availability + exact own source/display/station-ID comparison only; no PNGs visually reviewed in this preparation.
- Recorded byte counts checked; no content hashes recomputed. No native/app/build/tests or production changes.
- Whole-line dependency recorded verbatim, not recomputed; named-plan relevant own interval geometry/station IDs compared directly.
- Request includes only intervals with missing/unusable old evidence; interval-level request may also capture already completed viewpoints within a partially completed interval.

## Existing Matsumoto archive reuse

The Library alone has 53/60 usable viewpoints and missing #0/#1. The existing primary Matsumoto archive supplies the three unique #0 viewpoints: `/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/matsumoto-direction-review-20261013/primary-complete-native-before`. Every actual `capture-state.json` references immutable `identity-plan-d19b595e1638feac55dd0b4273e634d1f4893d671089fe6a91e8e01b53a6f4bd.json`; its own source/display IEEE bits and station IDs match current #0 exactly, and all recorded receipt file sizes agree. These three are counted once. Secondary/third copies are not added as geographic coverage. No PNG was reopened in this preparation. Therefore only #1 (西松本→渚, four views) is requested; #0 is not unnecessarily recaptured. Existing historical pixel reports remain separate evidence and are not newly granted acceptance here.

## Canonical order and rendering boundary

Order source: `ios/refactor-parallel/alignment-passenger-local-recheck-20261010.json`, unique `lineID` first appearance, ordinal = unique index + 2. Source/display comparisons use actual current decoded compact segment geometry and the named immutable plans referenced by each receipt. There are no line-level `displayIntervalCoordinates` or `displayStationCoordinates` overrides on these current own records. Recorded historical contracts are isolated zero-lane `inspector-centreline-v5-preserve-small-survey-curves;fixed-z17-v2` (1024×768). No current whole-line render dependency recomputation or Main composition claim is made. New original PNGs viewed in this preparation: **0**.
