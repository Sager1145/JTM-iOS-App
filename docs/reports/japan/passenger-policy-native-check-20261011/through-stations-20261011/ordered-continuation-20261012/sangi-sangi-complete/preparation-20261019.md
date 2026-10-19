# Queue 80: jp-三岐鉄道-三岐線

Source/receipt-only preparation, 2026-10-19. Current package `2025.5.2`; 15 stations / 14 intervals, 近鉄富田 → 西藤原. Canonical first-appearance lineID ordering starts at ordinal 2 in `ios/refactor-parallel/alignment-passenger-local-recheck-20261010.json`. This task stops after #81.

Actual Library immutable named-plan comparisons: **14/14 current source/display/station-ID interval identities match**. Completed captured receipts with matching named input and all recorded file sizes: **82/98 pairs**. Missing/unusable planned pairs: **16**. No line-level display interval or display-station overrides exist on this current own record.

Only missing interval indices `[2, 5, 13]` are in `/private/tmp/jtm-sangi-sangi-missing-request.json`. This existing-schema request is prepared **only in /private/tmp and not run**; it does not include complete intervals.

| Interval | Own stations | Legacy slot | Named-plan-verified usable / old planned | Missing/unusable old views |
|---|---|---:|---:|---:|
| #0 | 近鉄富田 → 大矢知 | 440 | 9/9 | 0 |
| #1 | 大矢知 → 平津 | 441 | 6/6 | 0 |
| #2 | 平津 → 暁学園前 | 446 | 0/5 | 5 |
| #3 | 暁学園前 → 山城 | 447 | 6/6 | 0 |
| #4 | 山城 → 保々 | 448 | 9/9 | 0 |
| #5 | 保々 → 北勢中央公園口 | 449 | 0/6 | 6 |
| #6 | 北勢中央公園口 → 梅戸井 | 450 | 7/7 | 0 |
| #7 | 梅戸井 → 大安 | 451 | 8/8 | 0 |
| #8 | 大安 → 三里 | 452 | 7/7 | 0 |
| #9 | 三里 → 丹生川 | 453 | 9/9 | 0 |
| #10 | 丹生川 → 伊勢治田 | 442 | 5/5 | 0 |
| #11 | 伊勢治田 → 東藤原 | 443 | 8/8 | 0 |
| #12 | 東藤原 → 西野尻 | 444 | 8/8 | 0 |
| #13 | 西野尻 → 西藤原 | 445 | 0/5 | 5 |

## Next short complete original-review scope

**#10 丹生川 → 伊勢治田**, 5 pairs / 10 original PNGs, recorded interval length 1238.5 m. Exact directories:

- `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000442/000000`
- `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000442/000001`
- `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000442/000002`
- `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000442/000003`
- `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000442/000004`

Open original `basemap.png` and `smooth.png` separately. No pixels were viewed in this preparation.

## Current stations

0: 近鉄富田 (005982), 1: 大矢知 (005906), 2: 平津 (005882), 3: 暁学園前 (005872), 4: 山城 (005868), 5: 保々 (005841), 6: 北勢中央公園口 (005799), 7: 梅戸井 (005753), 8: 大安 (005722), 9: 三里 (005675), 10: 丹生川 (005617), 11: 伊勢治田 (005580), 12: 東藤原 (005537), 13: 西野尻 (005481), 14: 西藤原 (005458)

## Scope limits

Original PNGs viewed: **0**. Only relevant current own compact source/display arrays and own station IDs were compared to actual named plans or the explicitly separated saved complete candidate inputs above. Receipt presence/recorded byte counts were checked; no full-tree hash custody, synthetic campaign, new runner, native/app operation, tests, build or production change occurred. Historic isolated z17 rendering is not current Main composition or whole-line/platform acceptance. Exact paths, match booleans, recorded contracts and receipt files are in [existing evidence](existing-evidence-20261019.json).
