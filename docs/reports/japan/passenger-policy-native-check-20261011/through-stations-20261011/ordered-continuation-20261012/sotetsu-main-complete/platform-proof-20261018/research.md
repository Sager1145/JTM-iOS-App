# Sotetsu Yokohama own-platform evidence, 2026-10-18

Research scope: identify Sotetsu's own terminal group and platform extent before resolving the A–B–C sharp tip. This work changes evidence files only. No production geometry, native capture, build or test was performed here. The parent chat owns final integration and actual Apple Maps review.

## Supported result

The current operator map establishes a separate **2F Sotetsu terminal with tracks 1–3**, approaching from the southwest and terminating toward the northeast beside its 2F concourse. An older operator submission supplies a numerical platform length and curved-track plan. OSM supplies independently identifiable own-group coordinates. The sources support checking B as an eastward excursion; they do not justify freezing the inherited A or using the nearest blue glyph without identifying its owner.

## Primary official station and engineering references

1. **Current operator station page:** [Sotetsu Yokohama](https://www.sotetsu.co.jp/train/stations/yokohama/), retrieved 2026-10-18, directly links [the August 2026 station map](https://cdn.sotetsu.co.jp/media/2026/train/stations/yokohama.pdf). The existing unchanged local original is `../targeted-refinement-20261017/official/yokohama.pdf`; the rendered page here is `sotetsu-current-page-01.png`. Its 2F plan and north arrow distinguish the own tracks and boarding/alighting faces from the JR/Keikyu transfer passages, underground Tokyu/Minatomirai access and municipal subway access. The platform diagram has car 1 at the concourse/terminal end and car 10 at the approach end. Direction is an interpretation of that north-arrow plan; no exact geographic bearing or endpoint coordinates are published. This schematic is not a metrically registered floor plan.

2. **Operator technical submission hosted by MLIT:** [2011-05-25 platform-safety meeting materials](https://www.mlit.go.jp/common/000145491.pdf), retained unchanged as `mlit-20110525-platform-safety.pdf`. PDF page **18** identifies Sotetsu Yokohama as three tracks/four platform faces, **210 m usable length**, a stub terminal **without a headshunt**. PDF page **20**, titled `相鉄 横浜駅構内概略平面図及び現況図`, shows curved own tracks, a common buffer end on its **left**, and approach on its **right**. Bottom annotations explicitly label track 1 **R=700 m**, tracks 2 and 3 **R=1000 m**. Two separate R=300 m annotations occur in surrounding linework; their ownership is unresolved and they were not adopted as a representative-track radius. These are historical geometry labels, not a present-day surveyed curve or map registration. Renders: `mlit-page-18.png`, `mlit-page-20.png`, `mlit-page-20-plan-detail.png`, `mlit-page-20-plan-lower-detail.png`.

3. **City regional context:** [Yokohama City's station-area-map page](https://www.city.yokohama.lg.jp/kurashi/machizukuri-kankyo/toshiseibi/toshin/excite22/shokai/map.html) links [the area map](https://www.city.yokohama.lg.jp/kurashi/machizukuri-kankyo/toshiseibi/toshin/excite22/shokai/map.files/0050_20231016.pdf), retained as `city-yokohama-surrounding-map.pdf` and `.png`. The drawing states November 2020. It identifies Sotetsu beside JOINUS, west of the JR group, with its own 2F and 1F gates, and draws the Sotetsu departure toward Futamatagawa to the southwest. It is a pedestrian area map and does not establish detailed platform caps.

## Exact georeferenced overhead reference

Source: **国土地理院 / GSI 全国最新写真（シームレス）**. [Official layer list](https://maps.gsi.go.jp/help/use.html), [tile coordinate specification](https://maps.gsi.go.jp/development/siyou.html), [layer description](https://maps.gsi.go.jp/legend/seamlessphoto.pdf). Tiles are 256 px XYZ Mercator; GSI documents the domestic datum as JGD2011. No datum transformation was applied here. Attribution and reuse follow the [GSI tile terms](https://maps.gsi.go.jp/development/index.html).

`gsi-seamlessphoto-z18-manifest.json` records 20 original JPEG URLs/files, retrieved 2026-10-18, and exact mosaic registration. `gsi-seamlessphoto-z18-mosaic.png` is a 1024×1280 tile stitch, no scaling, rotation, warp or annotation; top-left global pixel is `[232739*256,103418*256]` at z18. Image acquisition date was not established, so retrieval date must not be presented as photography date. The building/park roof covers much of the own-group area immediately west of JR. Visible building/roof edges are not platform caps.

For longitude λ and latitude φ in degrees, map a source coordinate into this original mosaic using:

```text
x = 256 * (2^18 * (λ + 180) / 360 - 232739)
y = 256 * (2^18 * (1 - asinh(tan(φ*pi/180))/pi) / 2 - 103418)
```

| Existing source point | [lon,lat] | Original mosaic [x,y] px |
|---|---|---|
| A | [139.620466,35.464424] | [389.290,676.811] |
| B | [139.62052,35.46423] | [399.356,721.212] |
| C | [139.61993,35.46359] | [289.372,867.692] |
| Raw rail continuation E | [139.62082,35.46456] | [455.280,645.684] |

## Explicitly identified OSM group, not nearest-rail selection

Source: **© OpenStreetMap contributors**, [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/), [attribution/licensing](https://www.openstreetmap.org/copyright). `osm-overpass-query.ql` queries railway/public-transport objects only in `[south,west,north,east]=[35.462,139.618,35.467,139.624]`; raw response `osm-overpass-raw.json` has 207 objects and database timestamp **2026-10-18T04:49:10Z**. [Overpass output documentation](https://wiki.openstreetmap.org/wiki/Overpass_API/Overpass_QL#out) explains the retained version, changeset, timestamp and complete geometry. The raw response remains authoritative for exact tags. `osm-sotetsu-identified.json` and `.geojson` extract the identified group and its own approach tracks; no OSM data was written to production.

| Object | Own-identity evidence | Version / last object edit |
|---|---|---|
| [stop_area relation 9552394](https://www.openstreetmap.org/relation/9552394) | `name:ja=横浜 (相模鉄道)`, `operator=相模鉄道`; contains own platform way and all three SO01 stop nodes | v3, 2020-10-04T16:53:56Z |
| [platform way 396805192](https://www.openstreetmap.org/way/396805192) | `railway=platform`, `public_transport=platform`, `area=yes`; **own operator established by relation membership**, not its own absent name/operator tags | v2, 2019-12-01T21:05:15Z |
| [track 1 way 396805197](https://www.openstreetmap.org/way/396805197) | `name=相模鉄道本線`, `operator=相模鉄道`, `railway:track_ref=1`, `source=Bing` | v6, 2021-01-13T14:45:28Z |
| [track 2 way 396805196](https://www.openstreetmap.org/way/396805196) | same explicit name/operator, track_ref=2, source=Bing | v8, 2023-03-11T15:14:46Z |
| [track 3 way 396805194](https://www.openstreetmap.org/way/396805194) | same explicit name/operator, track_ref=3, source=Bing 2014; `service=siding` is an OSM tag, not a reason to discard the officially passenger-used platform track | v7, 2023-03-11T15:14:46Z |
| [stop 7024303318](https://www.openstreetmap.org/node/7024303318), [3319](https://www.openstreetmap.org/node/7024303319), [3320](https://www.openstreetmap.org/node/7024303320) | `operator=相模鉄道`, `network=相鉄線`, `ref=SO01`, local_ref=1/2/3 | all v26, 2026-08-20T05:12:08Z |

The selected track endpoints have explicitly tagged **buffer_stop** nodes at their northeast ends:

| Track | Southwest end [lon,lat] | Northeast buffer [lon,lat] / node | OSM chord length |
|---|---|---|---|
| 1 | [139.6199214,35.4635471] | [139.6209925,35.46518], node 3996454576 | 205.859 m |
| 2 | [139.6198551,35.4635789] | [139.620924,35.4652059], node 3996454579 | 205.186 m |
| 3 | [139.6197899,35.4636088] | [139.6208565,35.4652337], node 3996454582 | 204.882 m |

Buffer-node last edits: track 1 v5 2023-06-21T02:51:43Z; tracks 2/3 v2 2023-03-12T23:00:12Z. Each whole platform track has only **three nodes**, with its SO01 stop near the northeast end. This mapping is strongly useful for owner, extent and direction; its straight hidden-platform chords **cannot establish true current tangent or curvature**. Stop-position nodes are not the platform midpoint. The nearby municipal subway stop nodes also carry an `alt_name` mentioning Sotetsu JOINUS; they are excluded by their subway operator/network identity.

## A/B and platform-bound calculation

`osm-platform-bound-analysis.json` records every original polygon node and the calculation. Local metres use an equirectangular projection centred at `[139.6204,35.4644]`. The longitudinal axis is the own **track 2** southwest-to-northeast chord, bearing **28.15085°**. No neighbouring JR rail participates.

Projecting the own platform polygon onto that axis gives a **217.597 m longitudinal envelope**. Its axis-crossing southwest cap is `[139.61985348,35.46357644]`, northeast cap `[139.62098704,35.46530185]`, and longitudinal midpoint `[139.62042026,35.46443914]`. These are **derived projections of OSM**, not surveyed cap coordinates. The envelope includes the common terminal/concourse end and differs from the official **210 m usable platform length**; do not force numerical equality.

| Point | Relation to longitudinal midpoint | Right/southeast of track 2 chord | Own mapped group containment |
|---|---:|---:|---|
| A | +0.47 m northeast | 4.45 m | Inside actual comb-shaped platform-fill polygon and its convex hull |
| B | 16.24 m southwest | 18.94 m | Outside both; 9.27 m from polygon/hull outer edge |
| C | 104.20 m southwest | 5.40 m | Inside polygon and convex hull |

A is longitudinally central in this own-group reference. B makes a substantial southeast excursion before returning to A. This reopens the earlier rejected deletion/realignment candidate: the older nearest-blue-glyph comparison did not independently establish the glyph's physical ownership. **Containment above describes the OSM geometry only.** Its simplified straight edges may omit several metres of the real curved platform; the 9.27 m value is not a measured discrepancy from the actual platform edge. Official radii support gentle curvature, not an arbitrary straight replacement.

## Registration and remaining coordinate limits

- Current official schematic: own terminal group, level and coarse compass direction supported; no measurable map coordinates.
- Historical MLIT plan: common buffer end, curved platforms, own track numbering and 210 m usable length supported. Left/right are reversed relative to the current operator schematic. It contains chainage annotations but no geographic grid or labelled road/river/bridge control point. The exact chainage origin is not used to create geographic coordinates.
- **Independent engineering-plan ↔ GSI affine control point pairs accepted: zero.** Roof edges in GSI cannot be equated with hidden platform tips. The historic platform shape, internal stairs/elevator bulge and buffer layout are potential correspondences only if another source exposes those same features. Three nearly collinear rail endpoints would also be a weak affine registration even if independently identified.
- OSM gives explicit own-group geographic support without pretending the official plan itself is registered. It should be overlaid on the exact raw Apple imagery/cartographic capture, retaining its dated simplification limitation, before choosing a new terminal dot or curve.
- No coordinate from the broad JR station centre, the old N02 station centre, a municipal subway POI or an unidentified neighbouring blue frame is adopted here.

Evidence verdict: **own operator/platform/level/direction identified; whole longitudinal extent supported approximately by an attributed mapped polygon and historical numerical length; exact present Apple frame caps and final representative curve remain for parent review.**


## Independent review after new Apple imagery

The parent subsequently supplied fresh exact-camera imagery from `/private/tmp/jtm-platform-proof-20261018/yokohama-imagery/alignment/captures/000000/`. I independently viewed `000000/{basemap,smooth}.png` and `000001/{basemap,smooth}.png`, and read view0 `view.json`/`capture-state.json`. Both original image pairs show the football/air-conditioning/garden roof west of JR; the old B takes the stroke to its east edge toward the adjacent exposed JR tracks. The proposed A–C chord remains beneath the identified own station roof, with A at a longitudinally reasonable position established separately by the own OSM relation/polygon.

**Verdict: accept deleting B only as the bounded repair of the false local sharp tip, preserving A, C and all other coordinates.** This does not accept a new fitted curve or move the terminal dot. `delete-b-independent-review.json` records the camera, projection, measured bearings and limits. From the exact MapKit rect, view0 source pixels are A `[800,600]`, B `[820.133,688.804]`, C `[600.165,981.762]`. The candidate C→A bearing is **27.6299°**, within **0.521°** of the explicitly tagged own track-2 OSM chord. The old C→B bearing is 36.9009°, followed by B→A 347.2264°, manufacturing the approximately49.67° corner. A and C are inside the own mapped polygon, and their whole chord lies inside its convex envelope by convexity.

Residual limits remain: roofs conceal physical rails/caps; OSM simplifies the hidden curves; historical radii do not measure present track position. Several-metre representative-centre/curve error is unmeasured. The accepted claim is removal of the unsupported local excursion while staying in the identified own-group envelope. The imagery comes from a zero-lane Inspector view; final Main lane/circle composition still belongs to the parent review.
