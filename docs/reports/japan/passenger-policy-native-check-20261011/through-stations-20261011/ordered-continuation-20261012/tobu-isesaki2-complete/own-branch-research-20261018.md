# Hikifune → Oshiage own-branch research — 2026-10-18

Scope: `jp-東武鉄道-伊勢崎線-2`, interval 0, the short crosswise control pair south of Hikifune. Research and staged display geometry only. No production edit, test, build, app launch, capture or native acceptance by this researcher. Parent owns current imagery and final acceptance.

## Finding and bounded proposal

The approximately 6.33 m east–west segment B→C is **present in the original N02 2025 own-line geometry**. It was not newly introduced by the Oshiage display override. Its endpoints are B `[139.81658,35.71726]` and C `[139.81651,35.71726]`; station A remains `[139.816637,35.718314]`, and next guard D remains `[139.81643,35.71575]`.

Explicit Oshiage passenger-route memberships identify the two inner own tracks. At B/C latitude, B is between those tracks and C is west of both. These named track paths continue longitudinally at the notch; their mapped crossover members are farther south. This supports a minimal **display-only deletion of C**, retaining B, station A, D and every later display control. The first turn falls from approximately 87.49° to 2.097° and the next join at D is 2.432°. The proposal does not move or recenter Hikifune, select the surface Asakusa route, or realign the whole inherited body.

Candidate: [own-branch-sources-20261018/display-notch-removal-candidate.json](own-branch-sources-20261018/display-notch-removal-candidate.json), with a full display LineString and exact preserved physical station/segment snapshot. It remains `candidate-only-needs-parent-current-native-review`. [The complete numerical comparison](own-branch-sources-20261018/hikifune-own-track-comparison.json) includes both deletions and an exact own southbound source-support alternative.

The operator plan is schematic and OSM ways carry KSJ2 ancestry. Consequently this conclusion concerns an unsupported sharp cartographic join, not a hidden track survey or proof that the retained body is pixel aligned. In particular, the inherited D support remains west of the contemporary mapped own pair; this bounded proposal does not certify or replace that larger approach.

## Original N02 and generator provenance

The retained [N02 fragment extract](own-branch-sources-20261018/n02-own-hikifune-fragments.json) contains both repository features and the exact matching fragments from the [official N02 2025 archive](https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-25/N02-25_GML.zip), selected by `N02_003=伊勢崎線`, `N02_004=東武鉄道` and exact coordinates. Repository `app/data/rail-sections.json` feature 17599 ends at B on the station side; feature 17603 begins B→C→D. The official archive repeats that topology exactly. The original archive was reused at `/private/tmp/jtm-denentoshi-own-direction-originals-20261018/mlit-N02-25_GML.zip`; only relevant extracted features are retained here.

Manual correction B4, dated 2026-09-10, in `app/scripts/railway/jp-manual-corrections/corrections.json` creates this separate branch line. It copies existing Hikifune `003479` from the main Tobu row and Oshiage `003526` from Hanzomon, then builds its interval from the **own** `東武鉄道|伊勢崎線` key (`tightM=40`, `looseM=200`, `snapM=20`). `resolveStationSpec`, `buildIntervalsFromSpec`, and `applyAddLine` in `jp-manual-corrections/apply.mjs` account for the copied station anchors and N02 chain. Thus the presence of B/C can be attributed directly to selected original own source fragments; no neighbor-snapping explanation is needed.

Current `repair-oshiage-display.mjs` decodes that physical interval, preserves the upstream supports, and changes the southern approach arc and central Oshiage cut. Its `branchPath.slice(0,boundary+1)` retains B and C. The old B/C notch therefore survives into current display geometry rather than originating in that repair. The legacy own view `006083/000000/smooth.png` was inspected, but its z17 roof shading cannot independently resolve this approximately 6 m pair.

## Own passenger identity and platform context

Tobu’s [official Hikifune station plan](https://www.tobu.co.jp/railway/guide/station/insidemap/1104/) and [original diagram](https://www.tobu.co.jp/cms-img/stations/insidemap/1104_image01.gif) show four main passenger tracks at two islands and the separate Kameido platform 5. The [station information page](https://www.tobu.co.jp/railway/guide/station/info/1104.html) distinguishes Oshiage from the surface Tokyo Skytree/Asakusa direction. The diagram supplies station topology, not metric plan controls or a surveyed turnout alignment.

The [retained OSM API response](own-branch-sources-20261018/osm-api-hikifune-own-branch.xml) and [identity extract](own-branch-sources-20261018/osm-own-branch-identity.json) identify:

- Own Oshiage-bound southbound way **61754727**, version 20, `operator=東武鉄道`, `name=東武伊勢崎線`, `usage=branch`, `oneway=yes`, bridge/layer 1. It is a member of own Oshiage-bound train route [11065585](https://www.openstreetmap.org/relation/11065585) and Hanzomon through-route [10025574](https://www.openstreetmap.org/relation/10025574), both explicitly `from=東武動物公園`, `to=押上〈スカイツリー前〉`. Continuation way [155874957](https://www.openstreetmap.org/way/155874957) is layer −2 farther south.
- Own reverse passenger way **155874950**, version 17, is selected by reverse Oshiage→Tobu routes [11065584](https://www.openstreetmap.org/relation/11065584) and [10025573](https://www.openstreetmap.org/relation/10025573). Its native coordinate ordering is south→north.
- The outer surface Asakusa members are different ways: **723619184** (northbound route 5392090) and **723619185** (southbound route 9504526). They are excluded from every B/C projection, despite sharing the operator/line name.
- Island platform polygons **155704809** and **155704812** lie between the respective inner own branch tracks and outer surface tracks. The Kameido track/platform are separate. This corroborates the own inner-pair attribution; no platform average is used to relocate station A.

The own branch ways retain `source=KSJ2` and a note referring to MLIT Railway 2007. More detailed current vertices and explicit route membership provide attributable own geometry, but cannot be represented as an independent engineering or pixel survey. Attribution: © OpenStreetMap contributors, ODbL 1.0.

Mapped crossover **155874972** begins at `[139.8165877,35.7166404]`; crossover **800175600** connects the vicinity of `[139.8165754,35.7160505]` and `[139.8165331,35.7166425]`. These longitudinally inclined members are south of latitude 35.71726, and do not reproduce B→C at one latitude. This is evidence from the retained map, not a claim that OSM inventories every physical switch. Physical geometry is unchanged by all proposed display variants.

## Own-only projection and tangent comparison

Distances use a local equirectangular metric: longitude scale `111320*cos(35.71726°)` and latitude scale `111320` metres per degree. Reported decimal precision makes calculations reproducible; it is not positional accuracy. Only explicit own branch ways 61754727 and 155874950 are searched.

| Control | Own southbound 61754727 | Own northbound 155874950 |
| --- | ---: | ---: |
| B `[139.81658,35.71726]` | 2.510 m | 0.646 m |
| C `[139.81651,35.71726]` | 8.834 m | 5.656 m |

The southbound projection segment has exact source controls `[139.8166091,35.7173008]`→`[139.8165877,35.7166404]`; the northbound segment has `[139.8165563,35.7171076]`→`[139.8165793,35.7173197]`. Exact projection coordinates and fractions are in the comparison JSON.

At unchanged latitude **35.71726**, interpolation yields southbound `[139.8166077778922,35.71726]` and northbound `[139.8165728261669,35.71726]`. Their arithmetic cross-track reference is `[139.81659030202954,35.71726]`. This is a comparison reference only; neither it nor either mapped rail is substituted for a physical station coordinate or accepted whole-platform midpoint.

| Variant | Changed controls | First/join turns | Assessment |
| --- | --- | --- | --- |
| Original | none | B 87.486°, C 87.537° | Original N02 crosswise notch |
| Delete B only | remove B, keep C | C 3.124°, D 0.284° | Less favorable: retains control west of both own branch rails |
| **Delete C only** | remove C, keep B | B 2.097°, D 2.432° | Preferred bounded proposal: one deletion, keeps own-band B and every downstream control |
| Exact own southbound supports | replace B/C by three own way61754727 vertices | 4.684°, 2.094°, 6.676°, D 6.003° | Larger comparison alternative; inherits a return to off-band D, so not preferred without imagery evidence |

The exact own southbound alternative uses source nodes 7967415777 `[139.8166487,35.7178117]`, 769413251 `[139.8166091,35.7173008]`, and 769413249 `[139.8165877,35.7166404]`. No synthetic curve, source-coordinate averaging, neighbor rail projection or platform-center move is used. Its [GeoJSON](own-branch-sources-20261018/ownSouthboundSupports-display-candidate.geojson) is explicitly comparison-only, not selected. The [delete-C GeoJSON](own-branch-sources-20261018/deleteCOnly-display-candidate.geojson) visualizes the proposed minimal deletion.

“Joins tangent” here means the proposal removes the approximately right-angle discontinuity and yields the stated small straight-control deflections; it does not assert exact engineering tangency or continuous-curvature geometry.

## Preserved scope and acceptance boundary

All variants preserve A, Hikifune’s physical station row and shared mainline owner, Oshiage’s physical row, physical interval **1.184 km** and original source vertices, line/station IDs, and all current display controls from D onward. The reviewed Oshiage B3 representative common cut `[139.81345102105016,35.70970842655579]`, lane assignment, southern arc and physical `oshiage-tobu-hanzomon` junction `[139.81374,35.70843]` are unchanged. Existing Oshiage engineering figures concern the southern B3 cut and are not reused as metric proof of Hikifune’s short notch.

No staged candidate is applied or accepted by this report. Parent current imagery review is needed to choose a display amendment and identify any additional concrete dependency. Existing legacy z17 views cannot settle the short own-track residual. Source files, URLs, retained byte counts and external archive path are listed in [sources-manifest.json](own-branch-sources-20261018/sources-manifest.json); no new large PDF was downloaded.

## Read-only integration review of the existing authority

The existing owner is `app/scripts/railway/repair-oshiage-display.mjs`. The minimal implementation point, after parent acceptance, is to build `branchApproach` from unchanged physical `branchPath` using the current terminal and arc helpers, verify exact A/B/C/D source controls, then remove its C at display index 2. Doing this **after** `reviewedNorthArc` leaves the existing physical `boundary` index and southern arc construction unchanged. Each replay reconstructs from physical input, so it cannot repeatedly consume an already shortened display prefix. Do not delete C from `segments`, `rail-sections.json` or raw N02.

Keep policy `oshiage-platform-display` as owner; append the own-Hikifune evidence and bounded single-deletion description to its provenance. The existing policy text that says all other supports survive needs this explicit exception. `repair-through-running-display.mjs` calls this same owner first, and the Oshiage registry has `baseOverride: oshiage-platform-display`; it therefore preserves this owned approach rather than recreating it with the generic through alignment. The B3/B1 station endpoints and separate company marks do not change.

The current branch has one **explicit complex** native part row: `partsByRegion.jp` part 0, interval range −1/−1, vertex count 36, total 1044.3 m, with all coordinates embedded in slot 7 and empty withheld slot 8. Python `chains_from_part_rows` calls `chain_from_embedded_coordinates` for this row; a package-only display edit would leave native using the old notch. The current owner CLI already refreshes part rows through `partRowsForLine` before `repairLanes`; retain that path. Expected candidate row has **35 vertices, 1038.4 m**, same kind/indices, same endpoint and withheld spans. Exact before/proposed rows are retained in [existing-authority-integration.json](own-branch-sources-20261018/existing-authority-integration.json). The figures are a targeted arithmetic proposal, not a builder run.

A targeted current-data query found no branch entries in `byRegion`, `followsByRegion`, `familyWindowsByRegion`, `hubReportByRegion` or `chainBoundariesByRegion`. Thus no branch numeric-window rebase or new generic mapper is justified. Existing `repairLanes` removes branch/main follow/tenant relations and holds shared Metro terminal lane zero; its output policy and unrelated lines stay unchanged. Parent should confirm the final part uses the selected explicit coordinates at delivery.

The existing `app/tests/oshiage-display.test.mjs` already covers physical preservation, replay idempotency, B3 endpoints, shared marks, reviewed southern arc and Hikifune/main meeting at zooms 12/16/19. Its “central cut preserves surveyed supports” prefix assertion currently requires every raw control before the southern boundary; that assertion must become the same exact prefix with only original C excluded. Extend this existing test with B retained, C absent only from display, raw B/C unchanged, station A unchanged, physical 1.184 km unchanged, D onward/southern arc unchanged, and explicit part row equal to final display geometry. The old southern arc and endpoint assertions remain useful. No test was run or edited in this review.
