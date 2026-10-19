# Kisuki intervals9/10/16: identified primary passenger legs

2026-10-12, bounded read-only source research. Production source, physical geometry, station points, passenger topology and mileage are unchanged. No UI/build/test operation. Research references only; none is an accepted repair.

## Interval16 first: exact passenger identity

**Viewpoint2** (35.03895798,133.11991871) lies on the retained named/operator/main/passenger **way1442622132** Yuki departure leg. The exact primary-node connections are **way1442622133 → node266913630 → way1442622132 → node266913832 → bridge way969666261**. All three have `railway=rail`, `name=JR木次線`, `KSJ2:LIN=木次線`, `operator=西日本旅客鉄道`, `usage=main`, `passenger_lines=1`, `gauge=1067`, `electrified=no`. No `service` tag identifies a siding. Node266913794 `[133.1192858,35.0446775]`, inside way1442622132, is explicitly tagged 油木 / Yuki, `railway=station` and the same KSJ line. This is positive same-line graph identity, not a nearest-track choice.

Selected original ordered supports around viewpoint2, way1442622132: index27 node266913851 `[133.1209564,35.0401348]`; index28 node266913852 `[133.1208822,35.0399880]`; index29 node12640135847 `[133.1207922,35.0398474]`; index30 node266913853 `[133.1206779,35.0397015]`; index31 node266913855 `[133.1190212,35.0379328]`; index32 node12640135846 `[133.1188822,35.0377853]`; index33 node266913859 `[133.1187245,35.0376451]`. The long sparse support between indices30/31 is retained evidence, not permission to replace a true bend with a chord or assume the source is accurate.

**Viewpoint12** (35.01156939,133.12964378) lies on **way1364934495**, with the exact sequence **bridge way1053613195 → node266913962 → way1364934495 → node12640073798 → bridge way1364934496**. All share the same named JR West Kisuki/main/passenger tags. The bridges carry `bridge=yes`, `layer=1`, so river/road intersections do not authorize a new graph connection or a road-snap. Nearby upstream cached way1108162439 is explicitly `tunnel=yes`, `layer=-1`, followed by way1108162438 and bridge1053613195; it is a tunnel evidence boundary, not missing surface track to invent.

Selected way1364934495 supports: node266913962 `[133.1290504,35.0124691]`, node266913961 `[133.1292484,35.0120401]`, node266913960 `[133.1293813,35.0118073]`, node266913958 `[133.1295254,35.0116191]`, node12640135801 `[133.1297052,35.0114398]`, node266913947 `[133.1299205,35.0112789]`, node12640073800 `[133.1308069,35.0107123]`. Their sequence and node identities are supplied unchanged in the GeoJSON.

## Intervals9/10: same leg through Izumo-Minari

The paired tail of interval9 (view12 camera35.196656,133.009867) and interval10's view2 (35.19552148,133.01732757) are positively connected as **way1132447256 → node266913452 → way24548956 → node266913455 → way1132447258**. Way1132447256 is oriented from the station toward the north; reverse it for southward tracing. Way1132447258 is stored east-to-west; reverse it for eastward tracing. Exact common node IDs avoid treating a visual crossing or coordinate proximity as adjacency.

Way24548956 contains station node**266913453**, explicitly **出雲三成 / Izumo-Minari**, `[133.00992,35.1964823]`, `railway=station`, `public_transport=station`, `KSJ2:LIN=木次線`. The Kamiminarikami basemap neighborhood label in the earlier visual report is not the railway station's identity. All three ways have the same JR木次線 / JR West / main / passenger_lines1 tags; none has a siding service tag.

Viewpoint10/2's relevant way1132447258 supports include node266914658 `[133.0188935,35.1955559]`, node266914631 `[133.0182894,35.1954767]`, node266914630 `[133.0175064,35.1953087]`, node266914629 `[133.0172375,35.1952530]`, node266914626 `[133.0168710,35.1952282]`, node266914635 `[133.0165864,35.1952268]`. Its tagged level-crossing node11944767197 `[133.0122833,35.1957743]` is part of this already identified railway; it does not join the road to the railway graph.

## Primary receipts and cache applicability

Retained cache: `/Users/sager/Documents/GitHub/Japan-Train-Map/outputs/osm-basemap-cache/E133N35.json`, `format=osm-basemap-cell`, fetched2026-08-18T10:27:46.258Z from `https://maps.mail.ru/osm/tools/overpass/api/interpreter`, bbox `[35,133,36,134]`, margin0.02°. This retained primary cache has way IDs/tags/coordinates but omits node IDs, versions and timestamps.

Only nine already identified way/full objects were read from the primary OSM API to recover those missing identities. Original replies are under `south-primary-sources/way-ID-full.json`; URLs, byte counts and retrieval times are in [retrieval.json](south-primary-sources/retrieval.json). The initial sandbox DNS failure was resolved by the supported approved network read; no regional online collection, bbox query or station-floorplan research occurred.

| WayID | OSM version | Object timestamp | Stored endpoint node IDs | Coordinates exactly equal retained cache |
|---|---|---|---|---|
| 1442622133 | 1 | 2025-10-16T15:59:29Z | 266913620 → 266913630 | True |
| 1442622132 | 1 | 2025-10-16T15:59:29Z | 266913630 → 266913832 | True |
| 969666261 | 1 | 2021-08-02T02:38:26Z | 266913832 → 266913835 | True |
| 1053613195 | 4 | 2025-10-16T15:59:29Z | 266913953 → 266913962 | True |
| 1364934495 | 2 | 2025-10-16T15:59:29Z | 266913962 → 12640073798 | True |
| 1364934496 | 2 | 2025-10-16T15:59:29Z | 12640073798 → 266913950 | True |
| 1132447256 | 3 | 2025-03-08T12:43:04Z | 266913452 → 266915654 | True |
| 24548956 | 8 | 2025-03-08T12:43:04Z | 266913452 → 266913455 | True |
| 1132447258 | 3 | 2025-03-08T12:43:04Z | 266914658 → 266913455 | True |

[Identified-leg GeoJSON](south-identified-leg-reference.geojson) keeps all nine original full ordered way/node coordinate sequences and tags. It is source documentation, not a corridor-centre proposal. No relation membership request was needed: exact shared nodes plus line/operator/main/passenger tags positively identify the bounded legs. Current-day train traversal/platform use is not established by these historical tags.

Primary URL pattern for the actual retained receipts: `https://api.openstreetmap.org/api/0.6/way/ID/full.json`; for example [way1442622132](https://api.openstreetmap.org/api/0.6/way/1442622132/full.json), [way1364934495](https://api.openstreetmap.org/api/0.6/way/1364934495/full.json), [way1132447258](https://api.openstreetmap.org/api/0.6/way/1132447258/full.json). OSM data licence: [OpenStreetMap / ODbL](https://www.openstreetmap.org/copyright).

## Shared ancestry and aerial decision

Every selected way retains **`source=KSJ2`**, the note **National-Land Numerical Information (Railway) 2007, MLIT Japan**, and the KSJ N02 source reference. The package likewise originates from N02 national-land railway data. Consequently OSM is useful for identified connected-leg support and comparison, but is not wholly independent surveyed truth relative to the package. A 2025 OSM split/object timestamp does not prove new imagery tracing; retained old node IDs and source tags make that distinction material. Exact cache equality establishes reuse freshness for these replies, not centimetre precision or correctness.

I inspected both retained regional-aerial references' context and directly viewed `regional-aerial/miinohara-south-z18.png`. Its documented camera is **35.083282,133.112458**, substantially north of the interval16 candidates. It shows a distinguishable railway/road grade in that separate location, but cannot corroborate view16/2 or16/12. The retained Minami-Daito reference is likewise unrelated to the interval9/10 candidates. Photo dates in those retained screenshots are `---`; neither supplies a targeted surveyed rail centre here.

**Root needs targeted aerial corroboration**, prioritized at **35.038958,133.119919** (Yuki departure curve) and **35.011569,133.129644** (southern Kisuki reverse curve/bridge), then **35.196656,133.009867** (Izumo-Minari/tail) and **35.195521,133.017328** (Yunohara valley). Use the identified connected leg to distinguish the grade from Route314/river, retain actual bridges and bends, and mark tunnel interiors insufficient. Root owns this native/browser work. Aerial observation, exact OSM graph identity and Apple displayed-track mismatch must stay separate evidence; none alone authorizes snapping or a whole-line pass.
