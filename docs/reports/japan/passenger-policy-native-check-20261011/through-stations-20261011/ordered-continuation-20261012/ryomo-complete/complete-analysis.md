# 28. 両毛線 — complete baseline analysis

All 18 station-to-station intervals (19 stations, Oyama–Shin-Maebashi) have been reviewed in each of the three actual native inspector apps: 268 viewpoints per app, 804 composite views total. Root opened all contact sheets 00–66 in each app. Captures alone were not treated as geographic acceptance.

The actual original RailMap.app was then reviewed in all 18 complete interval cameras, with network ON/OFF pairs (36 images). Every accepted pair has network rendered, zero budget drops, OFF confirmed, same camera to 0.00001 degrees, visible basemap pixels and visible interval endpoints. Initial tight-camera cases 01 and 02 are retained under `main-original/rejected-initial-tight-camera/`; case 01's Omoigawa end approached the right controls, so the common camera margin was widened before accepting coverage. Initial 02 was superseded conservatively by the same widened camera. Main receipt 00 has a stale scale label during ON, but visible basemap features, endpoints and the ON/OFF camera agree; no scale measurement is derived from that label.

## Observed candidates and retained constraints

- Oyama requires identifying the Ryomo passenger platform within the broad JR/Shinkansen/Mito station complex. Omoigawa River bend offsets vary locally.
- Tochigi east approach has a north bump/kink. The Tobu Nikko corridor to the south is independent.
- Iwafune northeast approach lies south of the Apple curve locally. Sano also has a smaller south-side difference near its passenger platform; the Tobu crossing and yard fan remain separate.
- Tomita–Flower Park is continuous, with a local curved-glyph difference. Ashikaga east watercourse and bridge approaches, then Yamamae/Omata, retain changing local offsets. JR Ashikaga and Tobu Ashikagashi across the river are distinct stations.
- Kiryu river S remains present. Watarase Keikoku branch, Tobu Kiryu crossing and the yard fan must not be absorbed into the Ryomo representative corridor.
- Iwajuku–Kunisada has a long continuous straight; local approach offsets remain.
- Isesaki is the strongest identity-sensitive candidate: the current stroke departs south of the Ryomo glyph near the Kasukawa bridge / west turn and station, close to the Tobu side. The three apps repeat it. This is not yet a proved wrong-route verdict: resolve the JR platform frame and longitudinal anchor before choosing repair coordinates.
- Isesaki–Komagata offsets vary near rivers and motorway, so a whole-line translation is unsupported.
- Maebashi east approach and station show a north-side difference. The Tone River bridge is north of the Apple railway glyph locally; Shin-Maebashi curves into the Joetsu passenger corridor, with the yard fan excluded.

All 19 own-platform longitudinal midpoint checks remain unaccepted. No production geometry, aliases, topology, kilometres or packaged resources were modified by this baseline review. The next ordered baseline owner is ordinal 29 大糸線; these repair and platform items stay open.

## Identity evidence and limits

[JR East October 2026 timetable, train 433M](https://timetables.jreast.co.jp/2610/train/010/011771.html) confirms the 19-station order in the reverse travel direction and continuation beyond Shin-Maebashi toward Takasaki. It supports service/station identity, not Apple track geometry or platform frame caps. A named line endpoint is not a physical track terminus.

JavaScript `decodeIntervals` and Swift `CompactPackage.decodeIntervals` / `decodeDisplayIntervals` were read for seam and station-endpoint welding. The frozen Ryomo owner has no display override fields. Main camera plans use those decoded current intervals. This was a focused data/source review; no build, runtime performance claim, national runner or full test matrix was needed or executed.

Evidence: `interval-review.json`, `review-progress.json`, per-app `capture-index.json`, all `root-review-sheets`, and `main-original/*-pair.json`. Pixel findings are relative to the visible Apple cartography; precise real-world geometry and full passenger platform frames remain separate acceptance work.
