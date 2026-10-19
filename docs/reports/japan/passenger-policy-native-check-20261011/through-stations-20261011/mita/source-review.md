# Toei Mita Line whole-line source review — 2026-10-12

Read-only review for the reported large offset over the Tokyo Toei Mita Line, scoped to `jp-東京都-6号線三田線` from 西高島平 to 目黒. This review follows `AGENTS.md`, `ios/VERIFICATION.md`, and the passenger representative display policy. It did not launch an inspector, run a test or build, change railway data, or inspect new pixels. Changes are limited to this note and its bounded primary-source captures. Existing Hongo-sanchome, Osaki, Shinagawa, Tokyo, Keiyo and other repairs remain untouched.

## Result

**WARNING — source/reference disagreement is the leading candidate; a renderer-wide translation is not supported by the current data path.** The line is still fundamentally an MLIT N02-25 centreline. No approved production passenger-track replacement covers the full Mita Line, and most of the route is underground, where an Apple basemap label or station footprint cannot establish the passenger alignment. Existing Meguro evidence covers only the bounded shared section and does not establish the whole line.

The current source review rules out the following as a uniform whole-line cause:

- Japan is excluded from `AppleMapDatum.candidateCountries`; native display leaves Japanese WGS84 coordinates unchanged. A GCJ-02/global-service datum shift cannot be applied to this line by the current code.
- Mita has no `displayStationCoordinates`, `displayIntervalCoordinates`, whole-line follow, family window, render-group replacement, stroke exclusion, or chain-boundary override.
- Screen lanes affect only two bounded measure ranges, not the whole line: `16928.9–20216.2 m` at lane `+0.5`, and `22647.9–26578.9 m` at lane `-0.5`.
- Namboku follows Mita only over the shared southern section: follower `jp-東京地下鉄-7号線南北線#0`, follower metres `0–2650`, canonical Mita metres `26578.930586656144–23950` in reverse. Mita is the leader, so this row does not move Mita onto another line.
- The current Mac Catalyst Main package is not stale. Its bundled `jp-2025.json` is byte-identical to `app/public/rail/jp-2025.json` (SHA-256 `19cbed77baabe5cb4a408268f0dd0d8e866669c33b568c00851994c4bff04dc9`). The bundled display manifest records the same JP package SHA and current `display-lanes.json` SHA `496cf8b20f4655db1805543ecc4a78779b81a5de40babe00038071da21733315`.

This does **not** prove that N02 is displaced from Apple's visible railway, nor that Apple exposes an exact underground reference. It establishes only that the same current source reaches Main without a Japan datum conversion or a whole-line display translation.

## Current identity and provenance

- Compact package: `app/public/rail/jp-2025.json`, `compact-v1`, version `2025.5.2`, generated date `2026-08-18`, CRS `WGS84`, line array index `305`.
- Line: `jp-東京都-6号線三田線`; `railwayIdentity` is the same ID; operator `東京都`; `operatorShort` `東京都交通局`; kind `subway`; code `I`; color `#006ab8`.
- Extent: 27 stations, 26 station intervals, declared total `26.545 km`.
- Physical source: `app/data/rail-sections.json`, MLIT National Land Numerical Information N02 2025, CRS `EPSG:6668` (JGD2011). The retained Mita subset has 56 section features and 446 raw section vertices.
- Station source: `app/data/stations.json`, the same N02 edition and CRS. Its 27 Mita station LineStrings and `display_point` fields are the nearest retained station-specific source records.
- Package provenance: `app/public/rail/jp-2025.sources.md` and `jp-2025.json.geometrySource` say station intervals are cut from N02 geometry. The registered OSM physical-track corrections listed there cover named Tokyo/JR corridors, not this Mita line.
- Through-service identity: `ios/RailKit/Sources/RailCore/Resources/japan-through-services.json` keeps `mita-meguro` from `2000-09-26` and later Sotetsu/Tokyu/Mita patterns. Those records describe passenger service legs and dates, not replacement geometry.
- Existing official/local evidence: `../meguro-review.md` records the registered shared station midpoint and official Meguro/Shirokane passenger relationship. No retained full-line Mita engineering alignment, platform geobinding, or identified passenger-track cache was found.

## All current intervals

`segments[i][1] == 1` means the compact row omits the shared first vertex; the decoder prepends the preceding station endpoint. Vertex counts below are stored-row counts.

| # | From | To | km | Stored vertices |
|---:|---|---|---:|---:|
| 0 | `003104` 西高島平 | `003112` 新高島平 | 0.803 | 12 |
| 1 | `003112` 新高島平 | `003117` 高島平 | 0.644 | 9 |
| 2 | `003117` 高島平 | `003128` 西台 | 1.049 | 14 |
| 3 | `003128` 西台 | `003140` 蓮根 | 0.801 | 19 |
| 4 | `003140` 蓮根 | `003158` 志村三丁目 | 1.149 | 26 |
| 5 | `003158` 志村三丁目 | `003165` 志村坂上 | 0.919 | 21 |
| 6 | `003165` 志村坂上 | `003193` 本蓮沼 | 1.060 | 14 |
| 7 | `003193` 本蓮沼 | `003216` 板橋本町 | 0.933 | 10 |
| 8 | `003216` 板橋本町 | `003245` 板橋区役所前 | 1.176 | 12 |
| 9 | `003245` 板橋区役所前 | `003268` 新板橋 | 0.919 | 9 |
| 10 | `003268` 新板橋 | `003293` 西巣鴨 | 1.073 | 11 |
| 11 | `003293` 西巣鴨 | `003354` 巣鴨 | 1.363 | 8 |
| 12 | `003354` 巣鴨 | `003415` 千石 | 0.886 | 7 |
| 13 | `003415` 千石 | `003461` 白山 | 1.104 | 19 |
| 14 | `003461` 白山 | `003529` 春日 | 1.291 | 33 |
| 15 | `003529` 春日 | `003580` 水道橋 | 0.722 | 12 |
| 16 | `003580` 水道橋 | `003651` 神保町 | 1.015 | 16 |
| 17 | `003651` 神保町 | `003719` 大手町 | 1.480 | 20 |
| 18 | `003719` 大手町 | `003802` 日比谷 | 0.858 | 6 |
| 19 | `003802` 日比谷 | `003842` 内幸町 | 0.947 | 18 |
| 20 | `003842` 内幸町 | `003911` 御成門 | 0.974 | 13 |
| 21 | `003911` 御成門 | `003962` 芝公園 | 0.858 | 15 |
| 22 | `003962` 芝公園 | `003986` 三田 | 0.594 | 10 |
| 23 | `003986` 三田 | `004025` 白金高輪 | 1.636 | 32 |
| 24 | `004025` 白金高輪 | `004044` 白金台 | 1.033 | 19 |
| 25 | `004044` 白金台 | `004072` 目黒 | 1.258 | 30 |

## Physical, display, and native-cache comparison

The web-derived Mita display part is one continuous part, `jp-東京都-6号線三田線#0`, with 413 vertices and `26578.9 m`. Its `partsByRegion` row is marked `station-approach/groomed`; it is not a second surveyed alignment.

Compared with the decoded compact chain, the current display part retains the same order and coordinates except that micro-kink grooming removes two source vertices:

- `[139.75323, 35.70997]` in 白山–春日 (`#14`)
- `[139.75149, 35.66096]` at the 御成門–芝公園 seam (`#21`)

This is a two-vertex local simplification, not a whole-line translation. There is no broad smoothing or coordinate fit in this path.

The retained inspector plan `parallel-instance-kisuki-keiyo/evidence/plan.json` has digest/SHA-256 `1e616b862b86493543065ce15a1a7c0961f8dbc481124be66005108c9997587a`, package version `2025.5.2`, and 115 planned viewpoints for the 26 Mita intervals. For every interval, its `identity.source` and `identity.display` arrays are equal at exact IEEE-754 longitude/latitude bit patterns. `BatchInspection.swift` defines these fields as immutable input identity, not an alignment verdict. Therefore this proves the plan had no per-interval display override; it does not prove agreement with Apple pixels.

The current Main display manifest has the Mita line as one chain, 413 full-detail vertices, 37 overview vertices, bounds `139.645685…139.764149 / 35.632485…35.791895`, chunk SHA-256 `21d704a5ee204d83cdae0fb9e2d29d31587a638e4ce579a158734f619e20ef24`, and no dependency lines. The manifest input hashes match the current compact and lane artifacts.

The manifest key is exactly `jp|jp-東京都-6号線三田線`, and slicing `jp.display.bin` at offset `4711556`, length `18930` produces a document whose own `lineId` is `jp-東京都-6号線三田線`, whose only fragment has `lineKey=jp|jp-東京都-6号線三田線`, one part, 413 vertices, and whose 27 station rows all have that same line key. The decoded full-detail coordinates match the current `partsByRegion` Mita part at seven decimal places. Thirty-two coordinates differ only in JSON floating-point representation after the builder's seven-decimal serialization; the largest geographic difference is about 5.7 mm. Therefore the compiled Main owner, catalog index, chunk range, and meaningful geometry agree with the current Mita part. This rules out a wrong-owner/wrong-index or materially stale native chunk for this source state, without claiming anything about rendered pixel placement.

## Bounded OSM passenger-chain comparison

`primary-sources/overpass-mita-passenger-relations-20261012.json` retains the two current OSM direction relations, `443286` and `8019910`, each with exactly 27 ordered stop nodes and an identified role-empty passenger track chain. The 目黒–白金高輪 ways are explicitly tagged as the shared Namboku/Mita facility with both operators. No passenger-chain way has `service=*`; the northbound relation's approximately 133.85 m post-stop tail at 西高島平 is explicitly excluded from interval evidence.

A diagnostic midpoint comparison against both opposing identified tracks has a whole-line median residual of 3.81 m and median vector `+0.22 m east, +0.46 m north`, with direction and magnitude changing by interval. The strongest median disagreements are localized: 千石–白山 14.67 m, 白山–春日 12.94 m, 大手町–日比谷 13.32 m, and 内幸町–御成門 11.67 m. Exposed northern interval medians are mostly 1–3 m. This current comparison contradicts one uniform global translation and strengthens localized N02 generalization as the source candidate, especially around the visually reported coarse bend at 千石–白山. OSM remains comparative evidence, not an official engineering alignment; see `primary-sources/osm-passenger-chain-review.md` for method, all interval values, exact ways, tags, exclusions, and capture hashes.

## Station-source discrepancy

The compact station anchors and current `app/data/stations.json` `display_point` values are exactly equal at 19 of 27 stations. Eight differ locally:

| Station | Difference |
|---|---:|
| 白山 | 25.13 m |
| 春日 | 5.63 m |
| 水道橋 | 7.27 m |
| 神保町 | 0.06 m |
| 内幸町 | 17.38 m |
| 御成門 | 1.29 m |
| 芝公園 | 32.48 m |
| 三田 | 8.31 m |

These differences are consistent with different representative-point calculations on curved/multi-vertex N02 station LineStrings: compact anchors often use the endpoint midpoint, while the station dataset's `display_point` can lie at the along-LineString midpoint. They are concrete local candidates around 白山, 内幸町, and 芝公園, but cannot explain a uniform offset over all 26 intervals. They also do not authorize changing physical anchors or mileage.

## Ranked root-cause candidates

1. **N02 coarse/generalized centreline versus Apple's visible/reference railway.** This is the only candidate spanning the whole line. It predicts that the elevated northern section will show a repeated source-to-identified-track residual even with lane zero, while underground sections may remain unmeasurable. Current evidence does not yet quantify that residual.
2. **Local station representative mismatch.** This predicts larger local displacement around 白山, 内幸町, and 芝公園 than at the 19 exact station anchors. It cannot predict a constant whole-line vector.
3. **Bounded lane presentation.** This can affect only the two listed measure windows and should change with zoom/screen scale. It cannot move 西高島平–神保町 or the unlaned middle/southern spans uniformly.
4. **Runtime corner rounding/LOD.** The native continuous-stroke path rounds and simplifies in projected screen space, but consumes the 413-vertex WGS84 part. It may alter local shape at a given zoom, not create one geographic translation. Actual Main pixels are required to test this.
5. **Datum shift or shared-follow error.** Current code/data contradict these as whole-line causes: Japan receives identity datum conversion, and the only Mita-related follow makes Namboku follow a bounded southern Mita span.

## Minimum evidence needed before any repair

- Use the exposed/elevated north first: compare 西高島平–新高島平, 高島平–西台, and 志村三丁目–志村坂上 against an identified passenger rail pair at high magnification. A consistent residual there can test the whole-source hypothesis without relying on an underground station footprint.
- Inspect the elevated-to-underground transition 志村坂上–本蓮沼 separately. A residual that starts or changes there would contradict a single whole-line translation.
- For underground intervals, require an official georeferenced engineering alignment or an Apple-extracted black railway that can be identified as the Mita passenger corridor. Labels, station polygons, POIs, nearby roads, and the nearest generic rail are insufficient.
- In Main, capture lane-zero and laned windows at the same camera/zoom, especially around the two lane boundaries. This distinguishes source displacement from screen-space parallel-company presentation. The zero-lane Inspector alone cannot certify production lanes, circles, LOD, or composition.
- Recheck 白山, 内幸町, and 芝公園 with their station LineStrings and platform evidence before considering a display-only representative-point change. Preserve physical station IDs, route topology, interval endpoints, and mileage.

No geometry repair is justified from this source review alone. A repair should target the earliest reproducible owner only after the evidence identifies the passenger corridor; it must not snap to a generic nearest road/rail or convert an observed display residual into physical/mileage changes.
