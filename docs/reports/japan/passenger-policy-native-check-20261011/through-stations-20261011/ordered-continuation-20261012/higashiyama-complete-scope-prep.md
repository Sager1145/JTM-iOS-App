# Higashiyama Line complete-scope preparation

## Fixed identity and source snapshot

- Existing list position: ordinal 17, immediately after the completed Jounan group entry recorded in `results.md`.
- Line: `jp-名古屋市-1号線東山線` / 名古屋市交通局 `1号線東山線` (`Higashiyama Line`, code H).
- Current package: `app/public/rail/jp-2025.json`, SHA-256 `a128bf177b2a13b0dd27e9520c04bc96691a0972bfdbdb9bfb939d85d2391942`, package version `2025.5.2`.
- Geometry provenance stated by the package: MLIT N02-25 station intervals. The line has 22 ordered stations, 21 physical segments, `railwayIdentity` equal to its line ID, and no `displayCoordinates`, `displayIntervalCoordinates`, or `displayStationCoordinates` override.
- Current native display cache: `display-lanes.json` SHA-256 `63a39f601f6e63cf068123c0298d3912ecc58a0cbed3112478b1cc862235d7e4`. It contains one part: part 0, interval range 0–20, 279 points, 20,717.7 m, no classification/anchors. There are no line-owned measured lanes, follows, family windows, or released intervals.
- Planning source: `ios/refactor-parallel/alignment-passenger-local-recheck-20261010.json`, SHA-256 `4fc732595d464ac561ffa9eb4d44a4520c2e11d5bde72ac06900a97cfd579921`. Its 21 interval records total exactly 90 planned viewpoints. This is a scope plan, not current pixel evidence; capture must bind fresh `view.json` identities and dependencies.

## Complete interval checklist

| # | From | To | km | source points | planned views |
|---:|---|---|---:|---:|---:|
| 0 | 005410 藤が丘 | 005430 本郷 | 1.297 | 22 | 5 |
| 1 | 005430 本郷 | 005437 上社 | 0.687 | 16 | 3 |
| 2 | 005437 上社 | 005470 一社 | 1.142 | 13 | 5 |
| 3 | 005470 一社 | 005488 星ヶ丘 | 1.124 | 21 | 5 |
| 4 | 005488 星ヶ丘 | 005500 東山公園 | 1.251 | 17 | 5 |
| 5 | 005500 東山公園 | 005482 本山 | 0.890 | 10 | 4 |
| 6 | 005482 本山 | 005478 覚王山 | 1.079 | 20 | 5 |
| 7 | 005478 覚王山 | 005473 池下 | 0.611 | 9 | 3 |
| 8 | 005473 池下 | 005460 今池 | 0.757 | 12 | 4 |
| 9 | 005460 今池 | 005450 千種 | 0.743 | 9 | 4 |
| 10 | 005450 千種 | 005453 新栄町 | 0.899 | 6 | 4 |
| 11 | 005453 新栄町 | 005459 栄 | 1.049 | 5 | 4 |
| 12 | 005459 栄 | 005464 伏見 | 1.022 | 14 | 4 |
| 13 | 005464 伏見 | 005451 名古屋 | 1.500 | 29 | 6 |
| 14 | 005451 名古屋 | 005423 亀島 | 0.950 | 11 | 4 |
| 15 | 005423 亀島 | 005426 本陣 | 0.951 | 6 | 4 |
| 16 | 005426 本陣 | 005440 中村日赤 | 0.655 | 4 | 3 |
| 17 | 005440 中村日赤 | 005475 中村公園 | 0.893 | 12 | 4 |
| 18 | 005475 中村公園 | 005504 岩塚 | 1.065 | 17 | 5 |
| 19 | 005504 岩塚 | 005533 八田 | 1.085 | 13 | 5 |
| 20 | 005533 八田 | 005564 高畑 | 1.046 | 13 | 4 |

Total: 21 complete intervals, 22 station endpoints in order, 90 planned viewpoints.

## Native and Main review gates

1. Capture every planned viewpoint for all 21 intervals in each required Inspector instance. Confirm actual `itemID`, `lineID`, interval index, endpoint IDs, fresh whole-line dependency, loaded basemap, and zero pending/failed before manual review. A count or Inspector distance statistic is not pixel acceptance.
2. Open every basemap/display/smooth panel. Check both termini (藤が丘 and 高畑), all 20 shared station seams, short tails, curve continuity, and smoothing for caps, chords, hooks, or returns. Preserve whole-part continuation at intermediate stations.
3. The line is a subway identity and much of the alignment lacks an exposed physical railway in Apple cartography. Where the basemap shows only a labelled transit guide, roads, buildings, station boxes, or no railway glyph, conclusions are limited to **cartographic display consistency**. Such frames cannot prove surveyed tunnel position or physical track accuracy. Record unavailable/occluded rail identity as WARNING rather than visual PASS or FAIL.
4. Give interval #14 名古屋→亀島 an explicit full-resolution review in every view and in Main ON/OFF context. Check the 名古屋 station departure, the complete underground bend/continuation, the 亀島 seam, and any short endpoint tail. The existing plan marks four views but contains no completed pixels; its known risk remains pending until fresh evidence is read.
5. Main scope should include complete interval framing for all 21 intervals plus close pairs for 藤が丘, 名古屋, 亀島, and 高畑. Check that line identity is not confused with adjacent JR/Meitetsu/Kintetsu corridors around 名古屋. Main acceptance must report actual rendered overlays and budget drops independently from Inspector evidence.

## Pending before capture

- The exact current Inspector-generated plan hash and candidate viewpoint count must be recorded from the fresh plan/report. The 90-view count above is the existing plan expectation and must not be forced if current deterministic planning legitimately differs.
- No fresh native or Main screenshots for this scope were found during this preparation. No geometry, physical station, lane, or source change is proposed here.
