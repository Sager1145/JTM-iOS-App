# Complete Keiyo native centreline visual review

2026-10-12. Visually inspected all 183 immutable viewports, every basemap/display/smooth triple, including ordinal0 and final ordinal for all 19 intervals. Contacts are four rows per sheet, columns basemap / cyan decoded display / red smooth. `contact-index.json` maps sheets; `coverage.csv` records each original directory, exact camera, part indices and dependency. View ordinals below are zero based; UI view number is ordinal+1. Counts establish receipt completeness, not acceptance.

| Line / interval | Viewed ordinals | Views |
|---|---|---:|
| Main0 | 0–12 | 13 |
| Main1 | 0–11 | 12 |
| Main2 | 0–5 | 6 |
| Main3 | 0–6 | 7 |
| Main4 | 0–5 | 6 |
| Main5 | 0–5 | 6 |
| Main6 | 0–7 | 8 |
| Main7 | 0–10 | 11 |
| Main8 | 0–13 | 14 |
| Main9 | 0–7 | 8 |
| Main10 | 0–10 | 11 |
| Main11 | 0–7 | 8 |
| Main12 | 0–10 | 11 |
| Main13 | 0–6 | 7 |
| Main14 | 0–8 | 9 |
| Main15 | 0–5 | 6 |
| Main16 | 0–4 | 5 |
| East2 interval0 | 0–16 | 17 |
| West3 interval0 | 0–17 | 18 |

Main exact ID `jp-東日本旅客鉄道-京葉線`; east/west append `-2`/`-3`. Main148 + east17 + west18 =183. Targeted report read after west completed: each interval captured expected count, pending0, failed0. ReviewVerdict remains pending in native report and was not promoted by this review.

## Strong observed discrepancy requiring identified-source/aerial review

Main11 ordinal3–7 through Kasai park / Kyu-Edogawa has a straight southern cyan and red stroke separated from the labeled Apple Keiyo railway. Main11 ordinal4 original confirms cyan itself follows this chord across park edge/river, approximately20–40 screen pixels south in this viewport. This is not just a smoothing-only shift. Exact camera35.64126025959366,139.86955657402575 (UI view5). Original `/private/tmp/jtm-remaining-lines-manual-evidence/captures/004516/000004/display.png` and `smooth.png`, camera/source metadata adjacent `view.json`.

Main12 ordinal1–6 continues a southern offset across Arakawa approach and bridge. Original ordinal2 cyan lies roughly20–30 pixels south of the parallel blue railway at the east approach, camera35.64592057920277,139.8541244037734 (UI view3); ordinal4 cyan is roughly20 pixels south across the bridge, camera35.6464213465975,139.84640232273316 (UI view5). Originals `captures/004517/000002/display.png` and `captures/004517/000004/display.png` under the same root. Ordinal6 approaches the southernmost visible parallel track at Shinkiba; avoid treating nearby depot branch as the passenger correction. Source/rendered display in ordinal2 includes[139.85457,35.64589]→[139.84976,35.64622]; original display part0. Ownership of neighboring strokes remains to be confirmed against decoded interval/native-part chains before proposing a repair. Pixel estimates are visual descriptions, not surveyed error measurements. Apple alone does not establish a replacement geometry.

## Complete corridor and fork observations

Main0–3 retain the Soga coastal curves and station approaches, with no gross break observed in these triples. Parallel rail artwork and station shading prevent individual platform-track acceptance. Main4–5 preserve passenger stroke beside the Makuhari yard; the blue yard fans are separate infrastructure, not omitted passenger branches. Main6–8 preserve the broad Minami-Funabashi curve and Futamata junction/river topology. Main9–10 preserve Shin-Urayasu/Maihama curves; no strong discontinuity identified. Main13–14 preserve Shinkiba and Shiomi northward curves and separate depot rails. Main15–16 underground Etchujima/Hatchobori/Tokyo show continuous cartographic stroke but insufficient basemap evidence for physical tunnel alignment; do not snap to surface road, intersecting subway or Tokyo surface platforms.

East2 all17 and west3 all18 explicitly show common north stem, real east/west fork and their separate downstream legs. Original east2 ordinal5 camera35.692656530284346,139.95789978468187 shows cyan taking east curved leg; original west3 ordinal5 camera35.692266886163594,139.95581475328183 shows west curved leg, without deleting either curve. Branch final tails were inspected at east2 ordinal16 and west3 ordinal17. Shared trunk representatives appear continuous in these isolated Inspector captures.

Original Minami station overlap main6 ordinal7 / main7 ordinal0 / east2 ordinal16 was inspected; cyan runs continuously along platform corridor, with no large cross-track connector visible. Original Ichikawa-Shiohama overlap main8 ordinal13 / main9 ordinal0 / west3 ordinal17 was inspected; continuous centreline observed in isolated evidence. Shiomi overlap main13 final / main14 ordinal0 was inspected in contacts and main14 ordinal0 original; real curving corridor retained. These views do not prove production shared folding, lane/follows joins, dots or family collapse; Main runtime remains root-owned.

## Provenance and limits

Originals root `/private/tmp/jtm-remaining-lines-manual-evidence`, sorted plan indices004513..004531. Main dependency `4b9dbee09010985bd3881cc6c0c549425cc2560bade187ae693a7278d0911702`; east2 `207ef121bf3aedd16e1c515d4e5a8bd17628f1b0b3a15aa1613868e844eba9e5`; west3 `e668ed373ca669bcd4c43c9c8ad7c632930f22a61c8f323df36db4ec765c08c1`. Root supplied fresh main0 plus matched prior native main1–16 validation; branches fresh. Current Keiyo inputs unchanged across root's later Kisuki/Hakone bundle work. No source changes, UI, builds or tests in this review. No whole-line PASS claim: main11–12 remain source/aerial candidates and underground physical alignment remains insufficient.
