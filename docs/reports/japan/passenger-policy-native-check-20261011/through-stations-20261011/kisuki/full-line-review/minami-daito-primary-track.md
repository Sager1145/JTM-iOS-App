# Minami-Daito: identified primary passenger-leg reference

2026-10-12. Bounded research for `jp-西日本旅客鉄道-木次線`, station **005094 南大東**, and its immediate approaches. Production source, physical topology, station and mileage are unchanged. No build, test or native operation was performed by this researcher.

## Result

The existing OSM cache positively identifies the named/operator-tagged main passenger leg: **way1216370470 → node266915272 → way24548951**. This is an exact recorded graph connection through the named station, rather than an unidentified nearest railway. Both ways have `railway=rail`, `usage=main`, `passenger_lines=1`, `KSJ2:LIN=木次線`, `name=JR木次線`, `operator=西日本旅客鉄道`, `gauge=1067`, `electrified=no`. Neither has a `service`, freight `usage` or `oneway` tag. Absence of a restriction tag does not establish operational traversal permissions. OSM relation **1839646**, version36, is `route=railway`, `name=JR木次線`, operator JR West, and includes both ways. Sources: [original way1216370470 response](minami-daito-primary-sources/way-1216370470-full.json), [original way24548951 response](minami-daito-primary-sources/way-24548951-full.json), [small-area primary OSM response](minami-daito-primary-sources/station-bbox.osm).

The local [proposed-reference.geojson](proposed-reference.geojson) preserves the original coordinate/node sequence within bbox **132.920–132.936 / 35.302–35.312**, plus one outside-bbox support at each outer end. It contains the two connected way pieces and separately labelled station POI, catalog-point projection and nearby platform POI. It is a research reference, not an accepted runtime repair.

## Retained cache and bounded primary reads

- [E132N35.json](/Users/sager/Documents/GitHub/Japan-Train-Map/outputs/osm-basemap-cache/E132N35.json): `format=osm-basemap-cell`, fetched **2026-08-18T10:26:58.149Z**, endpoint `https://overpass-api.de/api/interpreter`; bbox `[35,132,36,133]`, margin0.02°. Its compact elements preserve way IDs, tags and geometry, but omit node IDs, OSM versions and object timestamps.
- [E133N35.json](/Users/sager/Documents/GitHub/Japan-Train-Map/outputs/osm-basemap-cache/E133N35.json): fetched **2026-08-18T10:27:46.258Z**, endpoint `https://maps.mail.ru/osm/tools/overpass/api/interpreter`. It is the adjacent retained cell; Minami-Daito's selected ways are in E132N35.
- To recover the missing exact-node graph and same-line station tags, only two known way/full objects and one small station bbox **132.927–132.929 /35.307–35.309** were read from the primary OSM API. [Retrieval URLs, result sizes and time](minami-daito-primary-sources/retrieval.json) are retained. No online regional collection was fetched.
- Way**1216370470** is version**3**, timestamp **2024-05-25T08:18:32Z**. Way**24548951** is version**12**, timestamp **2024-09-09T23:50:29Z**. Their live coordinate arrays exactly equal the retained E132N35 geometry. These timestamps identify OSM objects, not their survey dates.

Both retain `source=KSJ2` and the note “National-Land Numerical Information (Railway) 2007, MLIT Japan”. This common ancestry prevents treating OSM as wholly independent surveyed truth relative to the package's N02 source. Later edits/object versions alone do not establish imagery tracing or present precise track position. Primary OSM source URLs: [way1216370470](https://api.openstreetmap.org/api/0.6/way/1216370470/full.json), [way24548951](https://api.openstreetmap.org/api/0.6/way/24548951/full.json). Licence: [OpenStreetMap copyright / ODbL](https://www.openstreetmap.org/copyright).

## Exact supports and station projection

| Role | ID / ordered support | WGS84 longitude, latitude |
|---|---|---|
| Northeast outer guard, original way1216370470 index12 | node266915300 | `[132.9363352,35.3109174]` |
| Northeast within-bbox support, index13 | node266915301 | `[132.9356922,35.3106541]` |
| Eastern curve, index25 | node266915280 | `[132.9300078,35.3076200]` |
| Next western curve support, index26 | node266915277 | `[132.9295752,35.3076292]` |
| Exact way junction / tagged station POI | node266915272 | `[132.9283746,35.3079602]` |
| First westward departure support, way24548951 index1 | node266914619 | `[132.9275512,35.3082366]` |
| Last within-bbox western support, index12 | node266914600 | `[132.9204084,35.3090476]` |
| Western outer guard, index13 | node266914599 | `[132.9190846,35.3089778]` |

The station node has `railway=station`, `KSJ2:STN=南大東`, `KSJ2:LIN=木次線`, `name=南大東`, and English `Minami-Daitō`; version8, timestamp **2024-03-22T07:39:17Z**. It is the final node of way1216370470 and first node of way24548951. Its projection onto this same recorded leg is therefore itself, but that is a station POI, not a measured platform centre.

Current catalog physical point `[132.92799,35.307895]` projects onto the already identified western departure's segment **266915272→266914619**, way24548951 index0, fraction **0.36535433387796207**, at **`[132.9280737672415,35.30806118393788]`**, approximately **20.00m** away. Calculation used local equirectangular clamped orthogonal projection with cos(latitude), 111320m/degree. The point is a reference candidate only; neither its decimal precision nor proximity proves a correct platform centre or authorizes moving the physical station. Nearby node**11752209665**, `[132.9284126,35.3080162]`, is separately tagged `railway=platform`, `public_transport=platform`, `shelter=yes`; it likewise is not certified as platform centre.

Root's [GSI seamless aerial screenshot](regional-aerial/minami-daito-z18.png), viewed directly by this researcher, shows the railway grade north of the source/crosshair and separate from the road/fields. It supports investigating the named leg's northern placement. The screenshot's imagery date was unavailable (`---`), and this researcher did not digitize, calibrate or measure a rail centre from it. Source cache geometry, primary graph identity and root's actual aerial observation must remain distinct evidence.

## Hataya and Hinobori: separate leads only

The same E132N35 cache contains named/operator-tagged Kisuki main-rail candidates for both places. For **Hataya**, way**1216384773** meets station-length way**24548937** at `[132.9393875,35.3348104]`, then way**24548947** at `[132.9396673,35.3348496]`. Way24548947 continues toward Izumo-Daito. For **Hinobori**, way**1284806443** meets short way**24548954** at `[132.931235,35.2764078]`, then way**1265836065** at `[132.9314552,35.2762379]`. The southern river leg includes ways**1265836042/1265836064/1265836063/1265836062/1265836044**; bridge-tagged pieces are recorded separately. These are exact cached coordinate endpoint joins with the same Kisuki/operator/main/passenger tags, not yet independently recovered node-identity or aerial-position proof.

Those caches can supply selected-leg candidates for the two visual shifts, but cannot by themselves settle accurate geography because their KSJ2 source is shared and their compressed records lack nodes/versions. No extra API requests, station projections, geometry proposals or repair mechanics were performed for Hataya/Hinobori. They require their own bounded primary-node and aerial/grade review if root advances those candidates.

No current-day service, train-specific platform allocation, ground-survey accuracy, pixel residual, native acceptance or whole-line pass is claimed.
