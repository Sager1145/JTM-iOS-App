# Mita OSM representative display candidate — method note

This note describes `mita-osm-display-candidate.json`, a read-only geometry candidate for comparing the Tokyo Toei Mita Line with the labelled Apple corridor. It is not an automatic correction, an official engineering alignment, or production data.

## Identity and scope

- Product identity: `jp-東京都-6号線三田線`, 27 current station identities and 26 station intervals, canonical direction 西高島平 → 目黒.
- Geometry evidence: retained Overpass response `overpass-mita-passenger-relations-20261012.json`, SHA-256 `5fcc4e3c91b9dc4bf8b9a21d3c05069d8beed910adb3831158a5781a563c9fc2`, OSM base timestamp `2026-10-12T07:47:34Z`.
- Passenger directions: OSM relation `443286` (目黒 → 西高島平) and relation `8019910` (西高島平 → 目黒). Both have 27 named stop positions in reverse order and are tagged `type=route`, `route=subway`, `ref=I`, `operator=東京都交通局`.
- Eligible geometry is restricted to role-empty `railway=subway` ways in those two passenger relations. Platform ways, generic nearby rails, roads, and non-member ways are not candidates. No used way has `service=*`.
- Relation `443286` way `834672582` begins at the 西高島平 terminal stop and continues about 133.85 m beyond it. It is excluded before chaining, so the candidate neither creates a 27th interval nor absorbs a terminal tail or yard branch.

This follows the passenger representative contract: identity comes from the route relation, operator, station order, direction, level and passenger topology. The OSM relation is a comparison source, while the current N02 station codes remain the stable product identities.

## Construction

1. Concatenate each relation's role-empty ways in member order by exact OSM node ID. Reverse relation `443286` so both chains run 西高島平 → 目黒.
2. Bind each of the 27 stop positions to its own direction chain with a monotone whole-line projection. Every stop is an exact chain node: maximum projection offset `0.000 m`. Both stop-measure sequences are strictly increasing, and all source way joins are exact.
3. Cut both direction chains at each consecutive stop pair. For every interval, retain the exact relation ID, stop node IDs, overlapping way IDs, ordered node IDs, along-chain measures and track length.
4. Sample the two interval curves at equal normalized passenger distance. The number of steps is `ceil(max(trackLengthA, trackLengthB) / 10 m)`. This matches station-to-station progress monotonically; it does not choose a nearest rail at each sample.
5. Average each matched coordinate pair in a local metric projection. Force every raw interval endpoint to the midpoint of its two opposing stop positions. The resulting raw midpoint chain therefore preserves all 27 station centres and has no inter-interval seam.
6. Simplify each interval independently with Douglas–Peucker tolerance `0.5 m`, preserving station endpoints. After WGS84 rounding to seven decimals, the largest measured dense-to-simplified error is `0.498 m`.
7. Concatenate the 26 simplified intervals without duplicating station endpoints. The selected candidate has 361 vertices and length `26,447.140 m`.

## Diverging track handling

The JSON records minimum, median, p95 and maximum separation of the matched direction tracks for every interval. A `TRACK_PAIR_DISAGREEMENT_GT_20M` flag is emitted whenever any matched sample exceeds 20 m. No interval is silently snapped to one track, a road, a platform outline, or a neighboring railway.

Four intervals are flagged:

- `1` 新高島平–高島平: maximum `26.124 m`, 16 samples over 20 m.
- `2` 高島平–西台: maximum `24.773 m`, 11 samples over 20 m.
- `23` 三田–白金高輪: maximum `37.966 m`, 59 samples over 20 m.
- `24` 白金高輪–白金台: maximum `26.274 m`, 25 samples over 20 m.

The northern flags correspond to the direction tracks spreading around 高島平. The southern flags occur at the transition into the shared Mita/Namboku facility: relation `443286` uses ways `409233306, 1378889434, 664537127`, while relation `8019910` uses `409233314, 409233325`. Those identified passenger paths are retained and averaged, but their separation remains a visual-review warning. Underground OSM geometry does not establish geodetic truth merely because both route relations contain it.

## Meguro boundary option

The opposing OSM stop midpoint at 目黒 is `[139.7157636,35.6325057]`. The existing registered three-company display anchor for Mita, Namboku and Tokyu Meguro is `[139.71566,35.632485]`, about `9.633 m` west-southwest of that midpoint.

The JSON preserves both:

- `rawOsmMidpointCoordinates` on interval 25 retain the unmodified paired-track result.
- The selected `coordinates` and top-level `candidate.coordinates` preserve the registered shared display anchor. The delta (`-9.354 m` east component, `-2.302 m` north component) is introduced linearly across 白金台–目黒, starting at zero at 白金台 and reaching the full offset only at 目黒.

This taper is a bounded display-boundary compatibility option, clearly separate from the OSM measurement. It prevents an abrupt terminal kink and preserves the existing shared endpoint without claiming that the registered point is the surveyed centre of the two OSM tracks.

## Interval measurements

Track `443286` is listed after reversal into canonical direction. Pair values are separation between the two matched tracks, before midpoint averaging.

| # | Interval | Track 443286 | Track 8019910 | Pair median / p95 / max | Samples >20 m |
|---:|---|---:|---:|---:|---:|
| 0 | 西高島平–新高島平 | 797.674 m | 797.433 m | 3.299 / 3.882 / 3.962 m | 0 |
| 1 | 新高島平–高島平 | 644.609 m | 644.039 m | 12.768 / 25.761 / 26.124 m | 16 |
| 2 | 高島平–西台 | 1170.768 m | 1170.581 m | 12.768 / 23.403 / 24.773 m | 11 |
| 3 | 西台–蓮根 | 665.447 m | 672.750 m | 4.207 / 11.052 / 11.718 m | 0 |
| 4 | 蓮根–志村三丁目 | 1179.147 m | 1170.548 m | 3.669 / 10.620 / 11.718 m | 0 |
| 5 | 志村三丁目–志村坂上 | 1005.659 m | 1010.929 m | 3.771 / 5.436 / 6.075 m | 0 |
| 6 | 志村坂上–本蓮沼 | 1016.339 m | 1017.175 m | 4.146 / 5.184 / 5.441 m | 0 |
| 7 | 本蓮沼–板橋本町 | 837.200 m | 838.619 m | 4.828 / 5.003 / 5.028 m | 0 |
| 8 | 板橋本町–板橋区役所前 | 1207.488 m | 1204.796 m | 4.665 / 5.023 / 5.101 m | 0 |
| 9 | 板橋区役所前–新板橋 | 975.619 m | 972.089 m | 6.921 / 11.161 / 11.361 m | 0 |
| 10 | 新板橋–西巣鴨 | 997.669 m | 1003.200 m | 5.352 / 10.395 / 11.361 m | 0 |
| 11 | 西巣鴨–巣鴨 | 1387.297 m | 1387.205 m | 4.334 / 11.828 / 14.269 m | 0 |
| 12 | 巣鴨–千石 | 910.843 m | 911.112 m | 4.909 / 11.598 / 14.269 m | 0 |
| 13 | 千石–白山 | 1017.336 m | 1019.082 m | 5.454 / 10.498 / 11.598 m | 0 |
| 14 | 白山–春日 | 1315.036 m | 1313.500 m | 4.635 / 5.107 / 5.142 m | 0 |
| 15 | 春日–水道橋 | 732.303 m | 734.330 m | 4.139 / 12.623 / 14.175 m | 0 |
| 16 | 水道橋–神保町 | 1000.554 m | 1000.778 m | 13.295 / 15.500 / 15.661 m | 0 |
| 17 | 神保町–大手町 | 1485.142 m | 1489.253 m | 5.511 / 12.817 / 13.396 m | 0 |
| 18 | 大手町–日比谷 | 885.306 m | 884.582 m | 4.451 / 12.603 / 13.396 m | 0 |
| 19 | 日比谷–内幸町 | 877.958 m | 880.447 m | 5.519 / 15.185 / 15.833 m | 0 |
| 20 | 内幸町–御成門 | 1028.656 m | 1029.570 m | 4.040 / 12.102 / 15.833 m | 0 |
| 21 | 御成門–芝公園 | 748.408 m | 744.504 m | 8.285 / 11.021 / 11.119 m | 0 |
| 22 | 芝公園–三田 | 695.660 m | 696.242 m | 4.276 / 4.657 / 4.738 m | 0 |
| 23 | 三田–白金高輪 | 1628.313 m | 1597.096 m | 15.694 / 35.255 / 37.966 m | 59 |
| 24 | 白金高輪–白金台 | 918.815 m | 942.202 m | 13.350 / 22.433 / 26.274 m | 25 |
| 25 | 白金台–目黒 | 1318.973 m | 1312.716 m | 4.263 / 10.650 / 14.870 m | 0 |

## Validation status and intended use

The candidate records all 27 stop pairs and all 26 intervals. Both source chains have exact node-ID way joins, strictly increasing stop measures, zero stop projection offset, and no opposite-direction continuity error. Candidate interval seams are exact. Each interval contains its complete retained way and node provenance.

Use the candidate only as an overlay for a focused visual comparison against an identified labelled Apple Mita corridor, especially intervals 13–14 and the four track-disagreement warnings. A visual match can prioritize follow-up evidence; it does not by itself make OSM authoritative for underground alignment or authorize a production edit.
