# Tokyo southern branch audit — 2026-10-01

The shipped Japan package lacked the direct 大崎–西大井 physical interval. Its 山手線 品川–大崎 interval and 総武線-3 品川–西大井 interval cannot represent that connection: concatenating them sends a train back through 品川. The independent override supplies the missing 大崎支線 as two separately surveyed directional alignments, with existing station codes only. Shared-package integration belongs to the geometry repair task.

## Scope and baseline

Japan compact-v1 version 2025.5.1, baseline 655 line rows / 9,576 intervals. This audit covered 品川004095, 大崎004135, 西大井004235 and the three conventional branch paths south of 品川. It examined compact source intervals, N02 rail-sections, the JavaScript display decoder and ridden-route canonicalization. No simulator or app build was run.

| Existing physical row | Adjacent in-scope stations | Baseline finding |
| --- | --- | --- |
| `jp-東日本旅客鉄道-東海道線` | 品川004095–大井町004197 | Eastern conventional trunk present |
| `jp-東日本旅客鉄道-山手線` | 品川004095–大崎004135–五反田004110 | Western loop branch present |
| `jp-東日本旅客鉄道-総武線-3` | 品川004095–西大井004235 | 品鶴線 branch present |
| `jp-東日本旅客鉄道-赤羽線` | 池袋003390–板橋003286–十条003218–赤羽003155 | Does not supply a southern connection |
| 大崎支線 | 大崎004135–西大井004235 | Absent from both package station intervals and the local N02 source-section graph |

Exact common N02 vertices already identify two existing display branch boundaries. 東海道線 interval 6 and 山手線 interval 0 share the 品川 approach until `[139.73762,35.62049]`; the 東海道 trunk then continues toward 大井町. 山手線 interval 0 and 総武線-3 interval 2 share another approach until `[139.7328,35.61677]`; the former turns toward 大崎 and the latter toward 西大井. Collapsing the whole 品川–西大井 interval onto 品川–大井町 would erase this western branch. Shared display alignment is a presentation policy; the source intervals remain separate.

## Evidence

[JRTT, 第4章 大崎駅接続区間](https://www.jrtt.go.jp/construction/asset/constUtwr-2_03.pdf), section 1 and diagram 3-4-1-1, distinguish the 山手貨物線 toward 品川, 大崎支線 toward 蛇窪, 山手電車線, and the 臨海副都心線 approach inserted between the two 大崎支線 tracks. This is primary engineering topology evidence, not a WGS84 coordinate dataset. Retrieved 2026-10-01.

[JR East, 2019-09-06 timetable change](https://www.jreast.co.jp/press/2019/20190906_ho01.pdf), printed page 2, shows 武蔵小杉–西大井–大崎–恵比寿–渋谷–新宿 in its diagram and stop table. [Current 大崎 timetable](https://timetables.jreast.co.jp/timetable/list0319.html) distinguishes 湘南新宿ライン northbound/southbound, 山手線, りんかい線 and 相鉄線直通. [Current 西大井 station information](https://www.jreast.co.jp/estation/station/info.aspx?StationCd=1149) lists JS16 and JO16. Retrieved 2026-10-01.

The retained coordinates come from the existing `Japan-Train-Map/outputs/osm-basemap-cache/E139N35.json` snapshot, fetched 2026-08-18T10:37:59.411Z. They are explicitly **OpenStreetMap-derived secondary geometry**, not official N02 survey geometry. The committed evidence stores 69 selected running-track ways, original relevant tags, snapshot SHA-256, source endpoint, WGS84 CRS and ODbL 1.0 attribution. The source record's MLIT imagery tags do not make the derived vertices official measurements.

No coordinates were blended across the two track surveys. Ordered way boundaries join by exact original coordinate equality; arbitrary distance-based physical junctions were not created. Station locations are bounded projections of existing station references onto each selected physical track segment.

## Reproducible candidates

`app/scripts/railway/tokyo-southern-branches-overrides.json` contains primary evidence, source vertices, ordered way IDs, source fork boundaries and integration constraints.

`app/scripts/railway/repair-tokyo-southern-branches.py` exposes `repair(package)`, `repair_sections(sections)` and `repair_stations(stations, package)`. All return copies; the command writes only an explicitly requested candidate output. It adds no invented stop, shared-package mutation or renderer code.

| Candidate | Permitted traversal in 大崎→西大井 station order | Interval | 大崎 anchor | 西大井 anchor |
| --- | --- | --- | --- | --- |
| `jp-東日本旅客鉄道-大崎支線` | forward / southbound | 97 vertices, 2,521.0 m | `[139.7280338341397,35.61984111600728]` | `[139.7216189410469,35.60169998665798]` |
| `jp-東日本旅客鉄道-大崎支線-p1` | reverse / northbound | 95 vertices, 2,509.0 m | `[139.72778560340058,35.61974827764918]` | `[139.7215786632762,35.601711973869165]` |

The projected 大崎 anchors are 22.3 m and 46.9 m from the baseline 山手線 station reference. The 西大井 anchors are 1.0 m and 2.9 m from the baseline 総武線-3 reference. Every anchor lies exactly on its own retained segment and equals the encoded interval endpoint. The two platform alignments are distinct; their station-code equality is station identity, not a new track connection.

| Track | True north fork in source | True south 品鶴線 junction | North lead-in |
| --- | --- | --- | --- |
| Southbound | `[139.727308,35.6209449]` | `[139.7255211,35.6087882]` | 139.3 m |
| Northbound | `[139.7266308,35.6219452]` | `[139.7255384,35.6088669]` | 265.8 m |

Both north forks connect exactly to source 山手貨物線 ways; both south forks connect exactly to source 東海道本線（品鶴線） ways. They must remain separate from the parallel 山手電車線 and the crossing 臨海副都心線 in physical routing. A representative conventional display stroke may merge them only through explicit reviewed display metadata.

Each candidate carries `southernBranchTopology` and generic `displayBranchLeadIns`. The lead-in starts at the surveyed north fork and ends exactly at the 大崎 interval anchor. Existing `extraSegments` requires station indexes and overwrites geometry endpoints with those stations; it cannot encode an unstaffed junction without inventing a stop. The north lead-in therefore remains metadata, not an extra passenger interval.

The compact delta is +2 line rows, +2 intervals and +4 station rows, with zero new station codes. Both rows share one physical `railwayIdentity` and the northbound row references the base as a paired alignment. The optional source-graph supplement adds two physical section features and four station membership rows; callers own package statistics and dependent display/fixture regeneration.

## Verification

- `python3 app/scripts/railway/repair-tokyo-southern-branches.py --check --output /tmp/tokyo-southern-branches-candidate.json`: PASS. Exact source seams, retained south junctions, running-track tags, bounded projections, local bounds and interval lengths checked.
- `python3 -m unittest discover -s app/scripts/railway/tests -p test_tokyo_southern_branches.py -v`: PASS, 5 focused tests. A deliberately altered source seam is refused; existing rows remain unchanged; replay is idempotent; directional geometry stays separate; lead-in and interval seams remain exact.
- Candidate JavaScript `buildNetworkFromCompactPackage` and `canonicalizeRouteFeature`: PASS. Each station interval produces one network part and its corresponding ridden route preserves 97/95 vertices. Wrong-direction explicit selection returns null. Neither path visits 品川 or 大井町, and no station-to-station chord replaces the curved source geometry.

## Follow-up: close both north forks without a new station

The initial two station intervals and north lead-ins were insufficient by themselves: the retained package had no adjacent 山手貨物線 main alignment at those exact OSM fork coordinates. JRTT distinguishes this station-free main track from the 大崎支線 platforms, so adding a fictitious 品川–大崎 stopping interval would misrepresent physical membership.

The evidence now retains a complete 26-way, 99-vertex, 3,359.8 m 山手貨物線 main chain, including the shared 品鶴線 approach. It runs from `[139.7402933,35.6313495]` north of 品川 to `[139.7231215,35.6266277]` near 五反田. Both north branch forks are exact original vertices on this chain. Two short way geometries are reversed solely to form a continuous displayed source polyline; this station-free geometry assigns no railway up/down or routed traversal restriction.

Displaying that entire raw chain would reintroduce a separate conventional stroke north of 品川: its northern endpoint is only 3.6 m from the retained physical 総武線-3 survey, but 110.3 m from the requested conventional surface display representative. The final override therefore displays only the previously uncovered main north of the 目黒川 fork, once on the base 大崎支線 row.

The bounded displayed main contains 41 vertices and measures 1,465.3 m. It begins at the existing N02 display vertex `[139.7328,35.61677]`; its source projection differs by 3.881 m. It ends at existing N02 山手線 vertex `[139.72321,35.62672]`; the retained OSM endpoint differs by 13.012 m. Both actual north fork vertices remain exact and unaltered inside this displayed main. This is an explicit display-only representative-corridor policy, not a physical junction between freight and 山手電車線 tracks. No source interval, source-graph edge, station membership or direction is added for these endpoint aliases.

The base row stores `displayFreightMainPolicy` with the source-way reference, source count, endpoint aliases and measured offsets. The full 99 original source vertices remain reproducible from the committed evidence. `displayBranchLeadIns[1]` carries the bounded station-free display main; the paired row retains only its own original north lead-in and does not duplicate the main.

The five focused tests passed again after this extension. They now additionally prove that both north forks occur in the complete source main and bounded display main, the two display endpoints are the reviewed existing N02 vertices, the offsets remain bounded, and the new main adds no stroke north of 品川. The source package and optional source-graph supplement remain idempotent.

## Remaining integration and evidence limits

The geometry repair owner must append the reviewed lead-in display parts, elect a representative shared conventional stroke, join the source branch to its reviewed display junctions, preserve station-circle aliases, regenerate graph/display fixtures and verify both clients. The existing physical intervals and branch source coordinates must remain canonical WGS84.

**INCOMPLETE:** Official measured WGS84 geometry for the missing 大崎支線 is not available in the retained N02 inputs. This override uses separately attributed OSM geometry under the existing Tokyo correction pattern. Final Web/iOS rendering, zoom behavior, camera alignment, cold-solver integration and final statistics were not independently signed off by this worker. These limitations are not converted into a nationwide PASS.
