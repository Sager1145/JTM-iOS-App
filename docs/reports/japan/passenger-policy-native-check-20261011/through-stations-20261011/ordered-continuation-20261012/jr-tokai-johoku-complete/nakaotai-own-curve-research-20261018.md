# Nakaotai own passenger curve — bounded source research, 2026-10-18

The #1 Nakaotai chord lead is supported by explicitly attributed **own Johoku passenger tracks**. This report freezes a control/projection sketch only. No source candidate has been accepted or applied, and there is no new builder, production edit, test, build or native operation.

The defect context is the actually inspected original pairs `000019/000005` and `000019/000006` below `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/`. They show the red trace passing north of the own mapped curve near Nakaotai Go/Ogisominami. The current decoded #1 controls26..33 are exact original N02 controls, not a recently introduced display alias. They occur at coordinate indices2..9 in zero-based own N02 feature11423, `N02_003=城北線`, `N02_004=JR東海交通事業`. The current interval is Owari-Hoshinomiya→Otai, physical length2.652km, continuation1.

## Exact own attribution

The existing degree-cell cache is `/Users/sager/Documents/GitHub/Japan-Train-Map/outputs/osm-basemap-cache/E136N35.json`, fetched `2026-08-18T10:17:07.262Z` from `https://maps.mail.ru/osm/tools/overpass/api/interpreter`. It is8,449,379bytes; only the two already identified own ways were extracted. The complete degree cell was not copied or downloaded again.

| Own object | Exact direct source/version | Own passenger identity |
| --- | --- | --- |
| [way58218285](https://api.openstreetmap.org/api/0.6/way/58218285/full.json) | v8,2026-03-13T03:21:42Z,82nodes | name東海交通事業城北線, operator東海交通事業; own train route11728676枇杷島→勝川, member17 |
| [way768955042](https://api.openstreetmap.org/api/0.6/way/768955042/full.json) | v7,2026-03-13T03:21:42Z,82nodes | same own line/operator; own train route11728762, name勝川=>枇杷島, member15 |
| [railway10406558](https://api.openstreetmap.org/api/0.6/relation/10406558.json) | v12,2026-05-06T01:35:18Z | operatorJR東海交通事業, nameJR東海交通事業城北線, route railway, 勝川→枇杷島; own ways members31/14 |

The [direct way memberships](nakaotai-own-sources/way-58218285-relations.json) and [paired way memberships](nakaotai-own-sources/way-768955042-relations.json) retain full route metadata/member lists. Route11728676v2 is2021-01-26; reverse route11728762v3 is2026-05-06. The reverse route has no `from` tag and has a malformed `seats=勝川` tag; its direction is stated in `name:ja`, not repaired or invented in this report. No `oneway` inference is made from node ordering.

Both ways have railway=rail, usage=branch, bridge=viaduct, layer1, no service=siding/yard, and explicit own passenger route membership. `usage=branch` therefore does not designate an unrelated depot spur here. The complete coordinate sequences fetched from the primary API exactly match the retained cache geometry. These two identified ways form the local paired reference around the disputed curve. Meitetsu Inuyama, subway Tsurumai, JR Tokaido and any other nearby rail were never used as projection candidates. A stale `KSJ2:LIN` tag alone was insufficient: other cached objects with that tag are actually named/operator-attributed Tokaido and are excluded.

The OSM source tags are **KSJ2 / MLIT2007**. The pair supplies own-line identity and differently resolved cartography, not an independent modern track survey or Apple pixel truth. Attribution: OpenStreetMap contributors, ODbL1.0; original N02/KSJ2 source attribution retained. Source/version JSONs and selected cache objects total about81KB under `nakaotai-own-sources/`; no large download is introduced.

## Frozen local window and joins

[The research sketch](nakaotai-own-sources/nakaotai-window-26-33-research-sketch.json) retains all old controls, complete versioned way node sequences, source tags, exact outside guards and source projections. It is a review artifact, not a production export.

- Proposed bounded own display window: decoded26..33 inclusive, from `[136.86961,35.21779]` to `[136.87634,35.21915]`.
- Preserve exact outside controls25 `[136.86727,35.21776]` and34 `[136.87783,35.21976]`, every station and all remaining interval controls.
- Reference: interpolate latitude at union longitudes only between the two explicitly identified parallel passenger ways, then take their paired centre. No nearest-rail search and no Apple glyph snapping. Perpendicular projection operates only on that derived own mean, with a local111320×cos35.218 longitude metric.
- Start projects to `[136.86960935045525,35.21781034486059]`,2.2656m; end to `[136.87633225945018,35.21916206063884]`,1.5160m. These are source-reference comparisons, not physical residuals.
- The exact-boundary sketch retains original26/33 and uses36 interior own mean supports,38controls total. Its maximum local deflection including the adjacent outside joins is2.2038°; the retained-boundary joins are1.9534° and1.3820°. This calculation indicates a feasible tangent connection; no rendered smoothness is claimed.

| Old decoded control | Exact source coordinate | Perpendicular distance to identified own pair mean,m |
| --- | --- | --- |
| 24 | `[136.86681, 35.21774]` | 2.4929 |
| 25 | `[136.86727, 35.21776]` | 0.1229 |
| 26 | `[136.86961, 35.21779]` | 2.2656 |
| 27 | `[136.87115, 35.21781]` | 3.6137 |
| 28 | `[136.87205, 35.21794]` | 6.1085 |
| 29 | `[136.87338, 35.21824]` | 15.3289 |
| 30 | `[136.87427, 35.21849]` | 15.7780 |
| 31 | `[136.87531, 35.21882]` | 9.1567 |
| 32 | `[136.87571, 35.21894]` | 4.3197 |
| 33 | `[136.87634, 35.21915]` | 1.5160 |
| 34 | `[136.87783, 35.21976]` | 8.9713 |

At the same longitudes, old controls29/30 lie15.7917/17.0409m north of the own pair mean. Perpendicular distances are15.3289/15.7780m. This agrees with the visible northward chord, while the selected boundary controls are close to the pair. Control34 outside the sketch is8.9713m from the own mean, so this bounded sketch does **not** claim to resolve all #1 alignment or the longer #2–4 lateral differences. The sketch excludes the passing-loop area farther west, any station re-centring, terminal fitting, physical source changes or extension toward neighboring railways.

A later implementation decision must preserve exact physical source/station IDs/km and the unchanged whole-line native cache dependencies outside this display window, refresh the native part through the established authority, and obtain the parent’s required visual review. No new policy/stage/exporter is introduced by this research. Historical #1 pixels establish the baseline concern; no candidate pixels or final product acceptance exists.
