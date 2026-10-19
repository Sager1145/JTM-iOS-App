# OSM passenger-chain evidence — Toei Mita Line — 2026-10-12

This is bounded comparison evidence for `jp-東京都-6号線三田線`. It is not an approved geometry replacement and does not authorize a physical, station-ID, topology, or mileage change.

## Captures

- `overpass-mita-passenger-relations.query` selects only relation `443286` and relation `8019910`, after a relation-only lookup in the requested Tokyo bounds (`35.62,139.63,35.80,139.78`) identified them as the two `type=route`, `route=subway`, `ref=I` directions.
- `overpass-mita-passenger-relations-20261012.json`: 197,574 bytes; SHA-256 `5fcc4e3c91b9dc4bf8b9a21d3c05069d8beed910adb3831158a5781a563c9fc2`; Overpass generator `0.7.62.4 2390de5a`; OSM base timestamp `2026-10-12T07:47:34Z`; 2 relations, 64 ways, and 1,143 nodes.
- `official-toei-mita-20261012.html` and `official-toei-subway-service-20261012.html` retain the command-line responses from the official URLs. Both are identical 212-byte Incapsula script shells (SHA-256 `d02032286070b4dd9d8fbd985a7bdca8af8edf52b89ff177db3bfcb2c8a9c43d`), so they contain no usable page text and must not be cited as a local content capture. The canonical URLs remain `https://www.kotsu.metro.tokyo.jp/subway/mita/index.html` and `https://www.kotsu.metro.tokyo.jp/about/service/subway.html`; a browser/manual capture is still needed if their statements must be retained locally.

## Relations and stops

Both relations are tagged `type=route`, `route=subway`, `ref=I`, `official_ref=6`, `network=都営地下鉄`, `operator=東京都交通局`, `public_transport:version=2`, and `wikidata=Q1374506`.

| Relation | Direction | Members | Stop nodes | Platform members | Role-empty track ways |
|---:|---|---:|---:|---:|---:|
| `443286` | 目黒 → 西高島平 | 62 | 27 | 18 | 17 |
| `8019910` | 西高島平 → 目黒 | 59 | 27 | 18 | 14 |

The stop order in each direction is the reverse of the other and contains the expected 27 names:

`西高島平 — 新高島平 — 高島平 — 西台 — 蓮根 — 志村三丁目 — 志村坂上 — 本蓮沼 — 板橋本町 — 板橋区役所前 — 新板橋 — 西巣鴨 — 巣鴨 — 千石 — 白山 — 春日 — 水道橋 — 神保町 — 大手町 — 日比谷 — 内幸町 — 御成門 — 芝公園 — 三田 — 白金高輪 — 白金台 — 目黒`.

Track-member order, excluding platform members:

- 目黒 → 西高島平 (`443286`): `664537127, 1378889434, 409233306, 24372343, 1378889439, 1378889442, 678481167, 661299592, 1379013574, 660716140, 663041995, 668656031, 296847776, 296847777, 184555271, 240734137, 834672582`.
- 西高島平 → 目黒 (`8019910`): `834672581, 240734136, 296847779, 1565131728, 296847770, 663041994, 687230734, 1379013575, 862542327, 661299593, 1378889441, 1378889440, 409233314, 409233325`.

All role-empty route ways are tagged `railway=subway`, `gauge=1067`, and `electrified=contact_line`. The underground chain uses `tunnel=yes` and layers `-1`, `-2`, or `-3`; the exposed northern chain uses `bridge=viaduct`, `layer=1`. No role-empty route way has `service=*`, so neither passenger relation includes a tagged depot/yard branch.

The 目黒–白金高輪 shared facility is explicit in the two direction relations. Way `664537127` (目黒 → 白金高輪 direction) and way `409233325` (白金高輪 → 目黒 direction) are named `東京メトロ南北線` and carry `operator=東京地下鉄;東京都交通局`, `usage=main`, `tunnel=yes`, and `layer=-2`. They are passenger mainline members, not a generic nearest-rail match.

Relation `443286` includes way `834672582` beyond its `stop_exit_only` node at 西高島平. The portion from the stop (`35.7918972,139.6457556`) to the way endpoint (`35.7921794,139.6443130`) is about 133.85 m. Any passenger centreline derived from the relation must trim at the terminal stop; that post-stop tail must not become a 27-station interval and must not be mistaken for yard service.

## Comparison with the current Mita display path

For a bounded diagnostic, the current Main full-detail chain was sampled at no more than 10 m spacing. At each sample, the nearest point on each opposing OSM passenger-track relation was found and their midpoint was compared with the current N02-derived centreline. This avoids selecting a generic nearby rail and approximates the centre of the identified track pair. It is still OSM comparison evidence, not an official survey; underground geometry in particular needs independent primary evidence before repair.

| # | Interval | Median centre residual | Centre residual p95 | Nearest-rail p95 |
|---:|---|---:|---:|---:|
| 0 | 西高島平–新高島平 | 2.25 m | 3.01 m | 1.23 m |
| 1 | 新高島平–高島平 | 1.59 m | 2.53 m | 10.67 m |
| 2 | 高島平–西台 | 2.10 m | 5.62 m | 9.13 m |
| 3 | 西台–蓮根 | 1.02 m | 3.84 m | 3.50 m |
| 4 | 蓮根–志村三丁目 | 2.47 m | 4.52 m | 3.17 m |
| 5 | 志村三丁目–志村坂上 | 3.10 m | 12.01 m | 9.52 m |
| 6 | 志村坂上–本蓮沼 | 1.96 m | 6.66 m | 4.01 m |
| 7 | 本蓮沼–板橋本町 | 1.50 m | 6.18 m | 4.08 m |
| 8 | 板橋本町–板橋区役所前 | 3.56 m | 11.59 m | 9.33 m |
| 9 | 板橋区役所前–新板橋 | 5.27 m | 19.11 m | 17.36 m |
| 10 | 新板橋–西巣鴨 | 8.35 m | 10.53 m | 7.76 m |
| 11 | 西巣鴨–巣鴨 | 11.90 m | 19.38 m | 17.10 m |
| 12 | 巣鴨–千石 | 6.46 m | 11.31 m | 7.16 m |
| 13 | 千石–白山 | 14.67 m | 33.25 m | 31.38 m |
| 14 | 白山–春日 | 12.94 m | 18.17 m | 15.96 m |
| 15 | 春日–水道橋 | 5.72 m | 6.57 m | 4.45 m |
| 16 | 水道橋–神保町 | 4.11 m | 7.33 m | 5.60 m |
| 17 | 神保町–大手町 | 1.09 m | 12.78 m | 6.45 m |
| 18 | 大手町–日比谷 | 13.32 m | 16.05 m | 12.01 m |
| 19 | 日比谷–内幸町 | 3.59 m | 14.36 m | 8.33 m |
| 20 | 内幸町–御成門 | 11.67 m | 13.38 m | 11.35 m |
| 21 | 御成門–芝公園 | 3.09 m | 6.26 m | 4.10 m |
| 22 | 芝公園–三田 | 5.94 m | 15.18 m | 15.18 m |
| 23 | 三田–白金高輪 | 3.05 m | 27.77 m | 27.77 m |
| 24 | 白金高輪–白金台 | 2.89 m | 6.61 m | 10.86 m |
| 25 | 白金台–目黒 | 1.70 m | 12.47 m | 10.57 m |

Across the complete chain, the median centre residual is 3.81 m, p95 is 16.25 m, and the median residual vector is only `+0.22 m east, +0.46 m north`. The direction and magnitude vary by interval. This contradicts one uniform WGS84/global rendering translation. It supports localized N02 generalization disagreements, most clearly around 千石–白山 and 白山–春日, while the exposed northern intervals are mostly within a few metres at the median. The large underground residuals remain candidates for focused primary evidence; they are not repair instructions.
