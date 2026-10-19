# Kamisakaemachi: identified paired passenger legs and bounded display proposal

**Proposal only:** physical station005987 `[135.86019,35.00518]` projects onto the locally derived centre between two positively identified Keihan passenger tracks at **`[135.8601033764409,35.005199183147624]`**, a local-metric displacement of **8.182m west/north**. This is a centreline display alias candidate, not a surveyed platform centre, a physical-catalog correction, or runtime acceptance. Root's GSI aerial `regional-aerial/station-z18.png` was actually viewed: the two-track grade is west of the centre crosshair, with separate roads/buildings east and forest west. That independently supports the direction and modest size of the proposed correction. The staggered side platforms do not define one central station rectangle.

## Primary identity and exact connections

Retained primary Overpass caches:

- `/Users/sager/Documents/GitHub/Japan-Train-Map/outputs/osm-basemap-cache/E135N35.json`, fetched2026-08-18T10:31:02.971Z, endpoint `https://overpass-api.de/api/interpreter`.
- `E135N34.json` in the same directory, fetched2026-08-18T10:13:02.333Z. Both contain the same four selected ways and geometry around this site.

Only four already-known ways were retrieved from the [primary OSM API](https://api.openstreetmap.org/api/0.6/way/30662150/full.json), with exact node lists saved under `primary-sources/`. No regional collection was performed. All four live coordinate sequences exactly match retained E135N35 geometry. Compact caches omit source versions/node IDs; live full responses supply those. Tram-way metadata is newer than cache retrieval despite unchanged geometry.

| Track chain | Primary version / timestamp | Proven connection |
|---|---|---|
| [rail30662150](https://api.openstreetmap.org/api/0.6/way/30662150/full.json) → [tram80241107](https://api.openstreetmap.org/api/0.6/way/80241107/full.json) | railv19,2025-05-26T00:19:56Z; tramv18,2026-08-25T07:53:48Z | Exact shared node339087628 `[135.8614293,35.0063466]` |
| [rail518501760](https://api.openstreetmap.org/api/0.6/way/518501760/full.json) ↔ [tram518501759](https://api.openstreetmap.org/api/0.6/way/518501759/full.json) | railv12,2025-05-26T00:19:56Z; tramv12,2026-08-25T07:53:48Z | Exact shared node5057702066 `[135.8614157,35.0062981]` |

The selected rails have operator`京阪電気鉄道`, name`京阪電気鉄道京津線`, railway`rail`, gauge1435, usage`branch`, electrification1500V/contact-line, passenger_lines2 and no service tag. Their paired continuations retain that operator/name/gauge/passenger identity, with embedded`pavement`. The cached August18 classification is railway`tram`; primary August25 metadata changes that to railway`rail` without changing coordinates or connectivity. Thus `branch` here is the passenger line's usage tag, not evidence of a siding. The two rails are distinct parallel ways and are not claimed to share a node with each other at the station. No track travel-direction claim is inferred from way ordering.

Rail30662150 retains KSJ2/N02-2007 ancestry tags; that source alone is not an independent ground survey. Tram ways carry `source:geometry=Japan GSI ortho Imagery`. Exact connectivity and operator tags establish the selected leg; root's actual aerial corroborates the local rail grade.

Stop-position node3032429681, on30662150, is `[135.8601935,35.0054396]`, named上栄町, operator京阪電気鉄道, network京津線, railway`stop`, public_transport`stop_position`, train`yes`. It is one track's stop position, north of the catalog seed; it is not a station centroid and must not replace the seed merely because it is tagged.

## Quantitative local candidate

`candidate.json` pins the four ways, versions/tags/node sequences/coordinates, cache provenance, exact connections, local paired mean and projections. The mean uses same-northing correspondence **only between the two positively identified parallel passenger tracks**, then local perpendicular projection onto the derived mean. It does not select the nearest rail among unrelated features. Metric uses111320m/degree with longitude scaled by seed latitude; it is not an Apple-pixel residual or aerial digitisation.

Station projection is bracketed by node5057702077→339087611 on30662150 and node6176106447→6176114872 on518501760. Real platform staggering is preserved conceptually: the candidate represents the passenger corridor between the rails at the seed's chain position, not the midpoint of roof/artwork outlines.

| Retained physical support | Candidate mean projection | Local displacement |
|---|---|---|
| Incoming#4 rawindex27 `[135.85979,35.00438]` | `[135.85982126577125,35.00437278183586]` | 2.962m |
| Incoming#4 rawindex28 `[135.86004,35.00486]` | `[135.8599926733604,35.00487092592412]` | 4.483m |
| Station005987 | `[135.8601033764409,35.005199183147624]` | 8.182m |
| Outgoing#5 rawindex1 `[135.86034,35.0055]` | `[135.86028901425618,35.00553165819833]` | 5.834m |
| Outgoing#5 rawindex2 `[135.86048,35.00564]` | `[135.8604569830232,35.005662626568075]` | 3.279m |

A bounded proposal could correct only incoming#4 from rawindex28 `[135.86004,35.00486]` to the station and outgoing#5 from the station to rawindex2. Their physical outer supports should remain exact, with gradual correspondence tapers to the identified mean rather than short perpendicular connectors. Rawindices refer to `decodeIntervals`; the existing interval4 display override inserts earlier curve vertices, so locate endpoints by coordinates rather than reusing these indices in that override. The incoming rawindex25 `[135.85977,35.00337]` is already within0.002m of the identified mean; it is an optional farther unchanged support, not justification to extend the repair unnecessarily.

## Existing ownership and replay implications

Current `app/public/rail/jp-2025.json` has no Keishin `displayStationCoordinates`; station005987 is physical in both stages. Its existing interval4 display override belongs to `app/scripts/railway/repair-keishin-display-curve.mjs` and `keishin-display-curve-evidence.json`. That older bounded Otani curve repair is earlier than this station window and must remain unchanged. The current wrapper accepts only its exact override or no override; adding a station-window override directly would break its replay assertion. Any accepted implementation therefore needs an owning outer stage or explicitly composed replay that preserves that earlier correction and its provenance, not replacement of the entire override by raw geometry.

Swift `ios/RailKit/Sources/RailCore/Data/CompactPackage.swift:290` installs display interval overrides and then welds both ends to display station aliases. JS `app/public/rail-network.js:865` similarly supplies display aliases/intervals to production display construction. A station alias without matched #4/#5 approaches would merely promise connectivity and can create a local corner. Physical coordinates, mileage and route topology should remain unchanged; `RouteNetwork.swift:672` consumes display anchors for rendered route geometry. Existing repair's `repairParts` rebuilds one cached Keishin native part and asserts there are no measured follows/family/loop references to the line. An eventual accepted alias/approach repair needs that same cached part refreshed, shared dependency references checked, and root's Swift resource copy/native main review. None was changed or executed here.

Aerial screenshot is GSI seamless latest photo at root's station view, z18; date field is`---`, so no acquisition date is asserted. This supports a proposal for local corridor placement; exact geometric acceptance still belongs to root's bounded native review. No station floor-plan research, source modification, test, build or UI operation was performed.
