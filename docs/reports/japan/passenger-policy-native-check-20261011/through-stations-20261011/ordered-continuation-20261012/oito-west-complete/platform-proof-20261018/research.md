# Itoigawa: own Oito bay and west approach evidence

Research date: 2026-10-18. Evidence-only assignment; no production geometry, topology, native app, builds or tests changed/run. The requested repair is being integrated separately by the parent chat.

## Decision supported

The current Oito terminal anchor `[137.861115,37.043114]` is south of the separately identifiable conventional island/bay. It must not be justified by proximity to a Shinkansen station point, a Hisui point or the old N02 common vertices. The own Oito bay gives a geographically independent candidate for native Apple comparison. The candidate is the longitudinal midpoint of **only the cut edge serving platform4**, projected to its adjacent bay rail; it is not the centroid/midpoint of the full2/3/4 island.

This research does **not** establish a new physical switch, a shared passenger graph edge, or exact track engineering coordinates. Its source-tagged geographic candidate still needs the parent's independent native own-frame/rail-band review before a display repair is accepted.

## Operator identity and level

[JR West's Itoigawa station page](https://eki.jr-odekake.net/premises?id=0541482), retrieved2026-10-18, lists Oito toward Minami-Otari at platforms3 and4; Echigo Tokimeki toward Ichiburi/Tomari can also use3. Hokuriku Shinkansen uses11/12. The diagram labels the conventional platforms1F and Shinkansen3F, and shows4 as a west-facing cut/bay within the conventional island. Therefore “platform3” alone cannot identify a unique Oito track or prove common track with Hisui.

The page dates its diagram2021-01-08. Its [current direct PDF](https://eki.jr-odekake.net/premises/0541482_41b6421c-4493-4312-a947-b66179180b37.pdf) was opened during research. The already saved `../official/itoigawa-20210108.pdf` was rendered without modification as `jrwest-itoigawa-diagram.png`. This is schematic identity/level evidence, not a geographic survey. No operating company was contacted.

[Itoigawa City's transport analysis](https://www.city.itoigawa.lg.jp/uploaded/attachment/2966.pdf), station-structure section p16, separately lists conventional Itoigawa with2faces/4tracks and connections to JR West Shinkansen and Oito. Its timetable context is2016; it is supporting historic station-group evidence, not current switch proof.

## Georeferenced government sources

Source: 国土地理院 / [GSI tile catalogue](https://maps.gsi.go.jp/development/ichiran.html). Saved unaltered tiles are `seamlessphoto-18-X-Y.jpg` and `std-18-X-Y.png`; exact URLs are in `tiles.json`. [GSI tile specification](https://maps.gsi.go.jp/development/siyou.html) supplies256px XYZ tiles and Mercator placement; Japan's underlying datum is JGD2011. OSM coordinates are WGS84; sub-metre datum equivalence is not asserted here.

`seamlessphoto-spec-11-1808-796.geojson`, downloaded from [GSI's photo metadata](https://maps.gsi.go.jp/xyz/seamlessphoto_spec/11/1808/796.geojson), covers the station and west approach with `データソース=電子国土基本図（オルソ画像）`, `撮影年月=2022年10月`. This resolves imagery age; it does not make2026 track operations a measured fact. Official layer definitions are retained in `gsi-layers1.json`.

The overhead shows the Oito branch curving in from the south and a separate elevated Shinkansen corridor. Deep roof shadow obscures the bay rail near the platform. The standard map resolves the conventional island cut and a separate bay line; the orthophoto is insufficient by itself to certify that hidden terminal rail.

Mosaic georeferencing, north up:

- `*-mosaic.png`: origin tile `(z18,x231457,y101993)`, size1280×1280.
- `*-station-throat.png`: origin tile `(z18,x231452,y101993)`, size2560×1536. Grey cells are absent tiles outside the deliberately bounded acquisition, not image data.
- Global pixel coordinates are `X=(lon+180)/360×2^18×256`, `Y=(1-asinh(tan(lat))/π)/2×2^18×256`; subtract origin tile×256. No image warp, manual rotation or offset was applied.

The station mosaics project source supports40/41/42 to approximately `(320.89,549.50)`, `(565.09,467.76)`, `(614.49,513.53)`. Thus the last old edge visibly leaves the conventional platform direction toward the Shinkansen building footprint.

## Geographic bay extraction and candidate

The original [OpenStreetMap API bbox response](https://api.openstreetmap.org/api/0.6/map?bbox=137.849,37.036,137.866,37.047) is saved as `osm-itoigawa-bbox.osm`, retrieved2026-10-18. `osm-own-bay-and-west-guard.osm` preserves the exact relevant ways and original nodes; `osm-rail-platform-extract.geojson` provides readable extracted geometry/tags. This is a first-party copy of the crowdsourced geographic database, **not an official operator track plan**. Several features explicitly cite `GSImaps/ort` or `Itoigawa ortho`, so map/photo/OSM agreement must not be counted as three independent surveys.

Relevant source objects:

| Source object | Geographic role | Important limits |
| --- | --- | --- |
| [way24603555](https://www.openstreetmap.org/way/24603555) | Named JR大糸線, operator JR West, non-electrified single passenger main approach | Own branch before station throat; source `GSImaps/ort` |
| [way1262851194](https://www.openstreetmap.org/way/1262851194) | Named JR大糸線 approach to `[137.8585082,37.0425822]` | Database geometry only |
| [way651661538](https://www.openstreetmap.org/way/651661538) | Intermediate database connection to `[137.8594954,37.0428295]` | Named **Hisui**, sourceKSJ2; cannot establish Oito co-track operations or switch connectivity |
| [way651661534](https://www.openstreetmap.org/way/651661534) → [way633881900](https://www.openstreetmap.org/way/633881900) → [way651661532](https://www.openstreetmap.org/way/651661532) | Separately named JR大糸線 bay rail to dead end `[137.8617507,37.0435204]` | Tagged `service=siding`, electrification tag questionable for Oito identity; names alone are not current operations proof |
| [way1262851197](https://www.openstreetmap.org/way/1262851197) | Platform polygon `ref=2;3;4`, version2, timestamp2025-03-07 | Use only its identifiable cut edge4, not the whole island |

The geographic bay rail follows:

```
[137.8594954,37.0428295]
[137.8600415,37.0430098]
[137.8606034,37.0431988]
[137.8613135,37.0434010]
[137.8617507,37.0435204]  # mapped dead end, not proposed station midpoint
```

The platform polygon's cut-edge cap endpoints are exactly extracted as:

```
A [137.8606376,37.0431901]
B [137.8617923,37.0435123]
```

This approximately108.57m **mapped cut edge** is associated with4 by the operator bay arrangement plus the GSI standard map cut, not merely by the island's `ref=2;3;4` tag. Its precise extraction does not certify that the entire edge is currently the usable passenger stopping face: the official schematic is not measurable, and the overhead is shadow-limited. A shorter separately visible own4 Apple frame takes precedence for the requested frame-centre convention. The local Mercator cut-edge midpoint is `[137.86121495,37.04335120]`; normal projection to the adjacent bay rail gives **research candidate `[137.8612063311,37.0433704838]`**. The candidate uses the geographic rail bearing about70.4° true/northeast; it avoids the old final southeast hook. This is roughly29.6m from old station42, predominantly north. Full numeric output and original metadata are in `own-platform4-candidate.json`; geometry roles are in `own-platform4-geographic-evidence.geojson`.

The own west guard is `[137.8562777,37.0418574]` on named non-electrified Oito way24603555, before the mapped shared throat. The JSON includes a continuous geographic chain from this own guard to the bay midpoint. The middle way651661538's conflicting Hisui identity is expressly retained as a limitation. It is a candidate **display path for independent evidence comparison**, not authority for physical topology or a shared-renderer follow span.

`std-mosaic-own-platform4-proof.png` and `seamlessphoto-mosaic-own-platform4-proof.png` label the bay rail yellow, cut edge4 magenta, own midpoint candidate green, and old source40–42 orange. Raw mosaics remain separate. The standard-map cut and candidate fit agree; the hidden rail remains shadow-limited in the overhead.

## Adoption boundary

Use these files to independently identify the own conventional bay in native Apple imagery and to review the complete Oito incoming interval. A display candidate may end exactly at the selected own-frame midpoint after that review. Do not extend it to the mapped rail dead end, average it with Shinkansen/Hisui points, alter physical station IDs/mileage, or promote the intermediate database connection to physical switch proof. If Apple's own frame differs, retain the platform identity and use the native supported rail/frame intersection instead of copying these geographic coordinates blindly.

## Attribution and retained receipts

GSI images: 国土地理院 / [地理院タイル](https://maps.gsi.go.jp/development/ichiran.html); [GSI use terms](https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html), saved as `gsi-use.html`; projection documentation saved as `gsi-tile-spec.html`. OSM: © OpenStreetMap contributors, [copyright/licence](https://www.openstreetmap.org/copyright), saved as `osm-copyright.html`; geographic database is ODbL. Original feature timestamps/versions remain in XML and extracted JSON. Diagrams and images here are local sourced research evidence; they were not presented as a new official survey or production dataset.

## Independent Apple imagery follow-up, 2026-10-18

The parent supplied its completed29-view own Oito imagery capture at `/private/tmp/jtm-platform-proof-20261018/itoigawa-imagery/`. This researcher performed no native operation. Views23/25/26/27/28 were visually read; this is **five local views**, not a verdict on all29. View23 and28 raw basemaps/metadata are retained locally as `apple-view23-*` and `apple-view28-*`.

View28 is1600×1200, north-up, pitch0; `snapshotProjection` independently reports2map points per pixel in both axes. Using the saved actual `mapRect` and MapKit's2^28 world width, the geographic points project without an image offset:

| Geographic item | Actual view28 pixel |
| --- | --- |
| Own4 mapped western cut cap A | `(622.01,564.45)` |
| Own4 mapped eastern cut cap B | `(1052.52,413.96)` |
| Bay midpoint candidate | `(834.05,480.20)` |
| Old terminal42 | `(800.00,600.00)` |
| Old control41 | `(701.20,508.45)` |
| Old control40 | `(212.80,671.93)` |

`apple-view28-projections.json` preserves the calculation inputs/results. `apple-view28-own4-projections.png`, the raw3× crop, and `apple-view28-own4-caps-and-rail-3x.png` show the points against the returned Apple pixels. The midpoint candidate lies in the narrow own bay trench, aligned northeast toward its buffer direction. Old42 lies on the Shinkansen roof boundary. Western capA is consistent with the visible cut onset; eastern capB reaches the footbridge/roof edge and is partly obscured. Therefore the candidate's **rail/platform-family identity is corroborated**, while the active eastern passenger-face cap and exact current usable length remain unmeasured. The whole long2/3/4 island was never used as the candidate face.

The candidate should be rendered/reviewed directly as an Oito-only display repair ending at the identified own4 rail/frame midpoint. If the parent's standard Apple own4 frame shows a shorter cap, use that cap midpoint on the own bay rail rather than forcing the108.57m OSM cut extent. Do not preserve the old Shinkansenward hook while waiting for a neighbor-line audit.

For splice ownership, `apple-view23-old-tail-and-own-chain.png` shows the old independent Oito curve and the progressively north-displaced later controls. Retain old expanded interval7 coordinate32 `[137.85539,37.04126]` as the last conservative own-curve guard; replace33 onward. Old33 remains on the own curve but is already offset by a few pixels;34–37 diverge farther north, and38–41 must not be borrowed as an identified own bay ingress. The updated JSON includes `recommended_old_source_splice_guard` and `own_candidate_guard_to_midpoint`, starting32 then continuing on independently named Oito way24603555's own curve. Follow the visually continuous own route through the throat into the bay. The conflicting middle database Hisui tag remains a limitation on physical connectivity; a bounded own display polyline does not create a shared follow or a physical graph edge.

Acceptance still belongs to the parent's complete affected interval and Main product review. These saved images establish the old endpoint's wrong platform family and the candidate's own bay direction, not final lane/popup behavior or a whole-line alignment pass.
