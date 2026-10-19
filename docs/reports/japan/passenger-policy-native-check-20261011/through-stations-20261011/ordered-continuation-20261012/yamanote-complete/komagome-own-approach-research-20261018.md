# Komagome own Yamanote approach — 2026-10-18

Scope: queue42 `jp-東日本旅客鉄道-山手線`, interval **#14 巣鴨→駒込**, within this package's named 17-station Shinagawa→Tabata arc. This is not an audit of the whole operating loop. Read-only source and retained-original review; no app/native operation, capture, tests, build, code edit or production mutation. Parent Main build inputs remain untouched.

## Disposition: candidate only; preserve current geometry pending own-corridor review

The 26.83° lead at decoded vertex5 C `[139.74677,35.73622]` is original own N02 2025 geometry, **not an introduced display alias**. Current interval #14 has no display override, and Komagome `003343` has no display station alias. Current raw controls match the frozen 2026-10-12 baseline recorded by the earlier own-platform research.

The explicitly identified own Yamanote passenger pair continues northeast smoothly near C. C is appreciably farther south of both tracks than neighboring source controls. A minimal display-only deletion of C reduces the local source notch, but does not establish a correctly aligned own approach: C is approximately **13.63 m** from the nearer mapped own passenger rail, and adjacent inherited supports remain south of the pair. Parent is **not applying** this candidate. Preserve the physical raw B/C/D chain and carry the lead forward for own-corridor geometry review after the current Main batch.

Candidate-only exact controls, own-track projections, source segment witnesses, alternative local joins and the original matching official N02 feature are retained in [komagome-own-control-comparison-20261018.json](own-platform-sources-20261018/komagome-own-control-comparison-20261018.json). This is a research record, not an exported package or an accepted repair.

## Source and retained originals

Current `app/public/rail/jp-2025.json` segment14 is `[0.779,1,...]`. Because its continuation flag is 1, the decoded first point is the previous interval's endpoint/station Sugamo `[139.74035,35.73372]`; do not omit it when measuring or proposing a display path. The local controls are:

| Name | Decoded index | Coordinate |
| --- | ---: | --- |
| A, earlier guard | 3 | `[139.74531,35.73572]` |
| B, before C | 4 | `[139.74648,35.73618]` |
| C, numerical lead | 5 | `[139.74677,35.73622]` |
| D, after C | 6 | `[139.74697,35.73634]` |
| Komagome endpoint | 7 | `[139.748054,35.736861]` |

Repository `app/data/rail-sections.json` feature14397, `N02_003=山手線`, `N02_004=東日本旅客鉄道`, contains B/C/D exactly. A targeted read of the already archived [official N02 2025 ZIP](https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-25/N02-25_GML.zip) found one matching own feature with the identical local chain. Original archive path: `/private/tmp/jtm-denentoshi-own-direction-originals-20261018/mlit-N02-25_GML.zip`; no archive download was repeated. Relevant exact feature content is included in the comparison JSON.

Both original files were actually opened and inspected:

- `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/005033/000002/basemap.png`
- `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/005033/000002/smooth.png`

Their metadata names `jp-東日本旅客鉄道-山手線#14#point-2`, captured 2026-10-11T21:25:19Z, zoom17, 1024×768 at 1×, north-up, approximately0.966m/point. The own source B/C/D values survive in its viewport-clipped `sourceCoordinates` with normal serialization roundoff; its first source point is clipped and is not the full interval start. The red line has a local change of bearing west of the station road crossing; the basemap shows multiple parallel blue railway glyphs and a separate Namboku crossing. These pixels do not independently resolve which physical rail is beneath every red pixel or establish a station cap. Metadata remains pending/reviewFresh=false. No current-renderer admission or whole-interval acceptance is inferred from this historical pair.

## Explicit own passenger and platform attribution

The cached [OSM first-party API response](own-platform-sources-20261018/osm-api-komagome-own-platforms.xml) was retrieved through `https://api.openstreetmap.org/api/0.6/map?bbox=139.7455,35.7357,139.7485,35.7372`. The earlier [own identity extract](own-platform-sources-20261018/osm-komagome-own-evidence.json) retains exact tags, node IDs, geometry, versions and relevant route memberships. No new area query or unbounded nearest-track search was needed.

| Own object | Retained version/date | Attribution/role |
| --- | --- | --- |
| [1565541058](https://www.openstreetmap.org/way/1565541058) → [1565541057](https://www.openstreetmap.org/way/1565541057) | each v1, 2026-10-06 | `name=山手線`, `operator=東日本旅客鉄道`, `railway:traffic_mode=passenger`, `railway:track_ref=山手線 : 外回り`, sourceBing; west→east outer direction |
| [1565541052](https://www.openstreetmap.org/way/1565541052) → [1565073018](https://www.openstreetmap.org/way/1565073018) | v1 andv2, 2026-10-06 | same own operator/passenger identity, `山手線 : 内回り`, sourceBing; native direction east→west |
| [1972920](https://www.openstreetmap.org/relation/1972920) | v130, 2026-10-08 | explicit JR Yamanote outer passenger route; selects both outer ways and own platform144126002 |
| [1972960](https://www.openstreetmap.org/relation/1972960) | v134, 2026-10-08 | explicit JR Yamanote inner passenger route; selects both inner ways and the same own platform |
| [144126002](https://www.openstreetmap.org/way/144126002) | v12, 2025-09-10 | own island platform, ref1;2, level−1; both own passenger-route memberships and station relation9873846 |

The open-cut approach tag on the own west ways and the platform's relative floor level do not turn this into Namboku tunnel geometry. The Namboku platform **1332808517** belongs to explicitly separate Namboku stop relation **7967130**, with subway/tunnel tags and level−2/layer−3. It is excluded from all projections. Nearby `山手貨物線` ways1565072842/1565541054/1565541055/1565541056 are also excluded, despite the common JR operator and corridor. The mixed-use corridor is not substituted for Yamanote's own platform pair.

Own platform144126002's western cap controls are `[139.7469923,35.7364565]` and `[139.7469707,35.736498]`. Their cross-section comparison centre is `[139.7469815,35.73647725]`, approximately34.43m from C. Thus the lead is on the **western approach** relative to this attributed platform footprint, not proved to be inside the passenger platform. This cap comparison is not a whole-platform midpoint and is not a proposed station coordinate.

Attribution: © OpenStreetMap contributors, ODbL1.0. SourceBing is an OSM attribution tag, not an independently performed photo survey by this researcher. Platform tags, directional memberships and detailed vertices identify an attributable own reference, but do not certify modern centimetre-level alignment.

JR East's [official Komagome page](https://www.jreast.co.jp/estation/stations/712.html) was read and identifies its B1–2F station plan. The identified image URL is `https://www.jreast.co.jp/estation/stations/img/floormap/0712_b1-2f.png`; direct retrieval returned HTTP403, so no new diagram pixels were saved or viewed. This report does not use that unavailable diagram as metric proof or claim to have read its platform labels. Existing source catalog entries remain historical leads.

## Own-only quantitative comparison

Only the four explicitly named own Yamanote passenger ways above were projected. Calculations use a local equirectangular metric with longitude scale `111320*cos(35.73622°)` and latitude scale111320m/degree. Decimal precision is for reproducibility, not a claim of positional accuracy.

| Source control | Distance to own outer path | Distance to own inner path |
| --- | ---: | ---: |
| A | 8.16m | 3.89m |
| B | 11.84m | 5.74m |
| **C** | **20.31m** | **13.63m** |
| D | 16.95m | 9.90m |
| Existing Komagome endpoint | 11.46m | 1.27m |

Near C, outer way1565541058 uses `[139.7465177,35.7363181]`→`[139.747219,35.7366191]`; inner way1565541052 uses `[139.7472559,35.7365575]`→`[139.7463757,35.7361948]` in its native east→west direction. Both are smooth own longitudinal controls, with no corresponding southward station-entry notch. Exact projection feet, segment indices and fractions are in the JSON; no projection onto Namboku, freight or an unlabelled Apple neighbor was computed.

| Local proposal | Turns at retained controls | Status |
| --- | --- | --- |
| Current A→B→C→D→station | B16.200°, C26.827°, D5.841° | Original own source geometry |
| Delete C only | B3.930°, D8.717° | Smallest candidate-only notch reduction; all other supports retained |
| Delete B only | C13.596°, D5.841° | Keeps the strongest southward off-band control; not preferred |
| Delete B and C | D5.922° | Removes an additional source support without necessary proof; not preferred |

Delete C only addresses the local source deflection. It does **not** bring the remaining B/D body onto the own pair or prove that a larger shift/curve replacement is correct. There is no source-supported reason to move the physical station, invent a pair average at the station's chainage, erase a real broad curve or borrow Namboku geometry. Current own-corridor pixels and complete-interval final-stroke review are still needed before choosing a display amendment.

## Exact boundaries for any later candidate

The research candidate is limited to display interval14, deleting decoded index5 only after exact source guards. Keep raw physical segment14 (including B/C/D), its continuation flag1 and **0.779km**, stationIDs003354/003343, both physical endpoints, and all other controls. Keep shared Sugamo/Komagome station positions and adjacent intervals13/15 unchanged; no new `displayStationCoordinates` alias is justified. The existing Shinagawa alias concerns004095 only and is unrelated.

The current adjacent Komagome→Tabata repair is owned by `repair-tabata-curve.mjs` / `tabata-yamanote-display-curve` and is scoped to interval15. Its replay/native-prefix assumptions must be reviewed before integrating any new interval14 display change; this report does not alter that owner or predict a native row from stale evidence. No part/ruler rebuild, lane/follow rebase or test execution was performed. Parent explicitly retains candidate-only status and will revisit the own corridor after the current Main batch.
