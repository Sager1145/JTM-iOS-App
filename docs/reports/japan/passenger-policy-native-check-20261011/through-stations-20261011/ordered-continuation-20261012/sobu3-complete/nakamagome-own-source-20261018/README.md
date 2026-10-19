# Nakamagome: fresh own passenger source and staged fragment

2026-10-18. Candidate evidence only for `jp-東日本旅客鉄道-総武線-3`, interval3 西大井004235 → 武蔵小杉004301. **No production geometry, builder/code/tests, app/native capture or Main display changed.** The [original-image review](../intervals-0-3-4-5-original-review-20261018.md) supplies the concrete red southward offset at `captures/005754/000005/{smooth.png,basemap.png}`. This follow-up stages an attributable, bounded display fragment for review, not an accepted repair.

## Exact fresh objects and route identity

Four direct OSM API responses were saved locally: [way365183512 and nodes](way-365183512-full.json), [its direct memberships](way-365183512-relations.json), [way751605913 and nodes](way-751605913-full.json), [its direct memberships](way-751605913-relations.json). No area query, unknown neighbouring-way acquisition or complete route geometry was fetched. The web reader could not access these API JSON URLs; direct HTTPS GET succeeded after network permission was available. Observation time: `2026-10-18T20:22:12Z`. Original response bytes and their SHA-256/byte lengths are recorded in [candidate-fragment.json](candidate-fragment.json).

| Way | Fresh version / object timestamp | Explicit identity | Direct Yokosuka–Sobu membership |
| --- | --- | --- | --- |
| [365183512](https://www.openstreetmap.org/way/365183512) | v18 / 2026-10-06T08:49:59Z; 22 versioned nodes | `東海道本線（品鶴線）`, JR East, `railway=rail`, `railway:traffic_mode=passenger`, `usage=main`, gauge1067, one-way=yes | relation11664782 v39, **横須賀・総武快速線 (千葉 → 大船)**; relation21262041 v7, **千葉 → 久里浜**. Both directly include this way. Hinkaku railway relation5426444 v32 also directly includes it. |
| [751605913](https://www.openstreetmap.org/way/751605913) | v12 / 2026-10-04T07:01:08Z; 12 versioned nodes | Same named JR East passenger Hinkaku/main/gauge1067 identity; stored geometry runs oppositely | relation11664583 v48, **横須賀・総武快速線 (大船 → 千葉)**; relation21262040 v11, **久里浜 → 千葉**. Both directly include this way. |

All returned node IDs, node versions/timestamps and coordinates are retained in the raw responses and summarized in the candidate. Each live coordinate chain exactly equals that way's existing 2026-08-18 cache geometry. This confirms the old reference was not an abandoned local shape; it does not turn secondary OSM geometry into an official geographic survey. Route membership supplies passenger-corridor identity, not precise platform measurement or legal railway up/down naming. Nearby retained Shinkansen references365183499/500/503 are JR Central/highspeed/gauge1435 and remain excluded; no Shinkansen coordinates enter the candidate.

## Source window and boundary witnesses

The offset originates in MLIT N02 feature16210 (`東日本旅客鉄道` / `東海道線`, class11/type2). No interval3 display override currently exists. The previous v15 `[139.70782,35.59201]` is still about9.19m from the selected own reference, so it was **not forced into a splice boundary**. The offset continues west across additional coarse source supports.

The staged fragment retains exact original display vertex13 through vertex32 as its outer boundaries, corresponding to raw N02 feature vertices10…29. The whole replacement window is about1km of this one interval, rather than a whole-line fit. Source vertices outside the window, both station identities/coordinates, canonical source segments and the stored interval kilometre value remain unchanged. The frozen baseline in the candidate records the complete original interval and physical segment for a later owner to guard against source changes.

Boundary witnesses use the repository's existing `projectPointOntoPolyline` in `app/scripts/railway/jp-manual-corrections/geo.mjs`:

| Boundary | Exact retained raw N02 coordinate | Projection onto selected way365183512 | Residual | Bracketing OSM nodes |
| --- | --- | --- | ---: | --- |
| Display v13 / N02 v10 | `[139.70858,35.59237]` | `[139.70858420934155,35.59236189884047]` | 0.977918m | 2202950665 → 1656329602 |
| Display v32 / N02 v29 | `[139.69821,35.58934]` | `[139.69820603576093,35.589349037339225]` | 1.066929m | 1656329434 → 1656329388 |

These are candidate seam witnesses, not an accuracy acceptance threshold. Selecting v32 allows the western boundary to return close to the **same** named reference after the continuing offset. Projection points locate the source cut; they are not inserted as tiny perpendicular connector legs. The candidate retains the two exact N02 boundary coordinates and the19 exact intervening nodes of **one** track, way365183512, in stored southwest order. It does not average directional tracks, choose the nearest of several tracks at each point, invent a curve, or move canonical geometry.

The opposite way751605913 is an independent identity/shape cross-check, not candidate geometry. Its geometry ends inside the broader fragment window, so residual comparison to that way is limited to the covered suspect controls13…15; no western-boundary extrapolation is used.

## Reviewable staged outputs

- [candidate-fragment.json](candidate-fragment.json): frozen own baseline; source versions/nodes/route memberships; boundary witnesses; fragment coordinates and exact node IDs; local comparisons; source attribution and limits.
- [comparison.geojson](comparison.geojson): original bounded display fragment, candidate fragment, both fresh independent passenger references and projected boundary witnesses. This is data for review, not a rendered native observation.

Source and candidate fragment lengths are **998.763005m → 996.696615m** by the existing repository haversine helper. Stored canonical km is preserved and is not replaced with either display length. A hypothetical interval splice would change93 →94 display points. Including each unchanged adjacent outer control, the largest local deflection is **17.179446° → 6.858098°**; candidate boundary turns are6.858098° at the start and1.002874° at the end. These are source-geometry measurements only, not pixel/native performance or physical-position acceptance. No production part/follow/family measure was regenerated.

## Interpretation and outstanding work

The exact N02 origin, fresh independent named passenger tracks and direct Yokosuka–Sobu route memberships support a sparse-source offset rather than a special Tokyo underground detour in this window. The adjacent distinct Shinkansen corridor remains separate. Neither the lack of a tunnel tag nor visual overlap alone proves every local bridge/grade detail.

This is a **reviewable candidate fragment**, not permission to bypass integration review or native comparison. Before any later application, the repair owner must confirm the bounded seams and exact baseline, preserve the canonical route/station/km records, review measured display dependents, and inspect the actual resulting own-corridor display. Current Main composition and geographic platform/track-centre acceptance remain pending. Attribution: © OpenStreetMap contributors, ODbL1.0; retained N02 boundaries from processed MLIT N02 2025 data.
