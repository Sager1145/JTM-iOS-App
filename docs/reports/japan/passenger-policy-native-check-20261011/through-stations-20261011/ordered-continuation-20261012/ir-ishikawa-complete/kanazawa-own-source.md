# IR Ishikawa #3 Kanazawa: own-source research and candidate fragment

**Window update:** kanazawa-native-seam-audit.md supersedes5..22 with the explicit5..26 display-transition proposal. The original fragment is retained as kanazawa-candidate-fragment-5-22.json.

2026-10-18, source-only. No code or production change; no tests, build, app/native launch, capture, or candidate CLI. This extends preparation.md, whose 210/210 retained original receipts match current own source/display/station IDs. Those receipts are legacy evidence, not acceptance of this unrendered candidate.

## Source and identity

The current #3 interval is 東金沢→金沢, decoded 31 controls, compact row continues from #2. N02 app/data/rail-sections.json **zero-based feature index9543** (not a stable feature ID) contains the 29 interior source controls and properties N02_001=12, N02_002=5, N02_003=IRいしかわ鉄道線, N02_004=IRいしかわ鉄道. Decoded13 / stored12 / feature-coordinate12 is [136.65639,36.58458]. Its heading change is37.5117° (interior142.4883°), on edges21.33m and39.46m. Scoped current repair searches found no own IR repair authority or display/station override. A subsequent implementation must choose the existing project correction/builder authority; this report does not create one.

Exact identified OSM objects were fetched, not a nearby-rail search. Own railway relation4669038 v26 (2026-07-14T16:11:56Z) identifies IRいしかわ鉄道線, 大聖寺→倶利伽羅, operatorIRいしかわ鉄道. It is route=railway, not a directional passenger train route. Ways834273931 v5 (2026-07-19T21:29:26Z) and394894111 v7 (2023-09-03T10:18:21Z) are explicit own gauge1067/usage main/track_ref2. Their shared node11164797904 joins them exactly. Both reversed form the northeast→southwest own reference. Their relation member positions are52 and51 (zero-based). Live geometry equals the retained degree-cell geometry; the exact versioned API responses and relation/endpoint evidence are retained in kanazawa-own-source/.

Way368759335 v10 (2023-09-03T10:18:21Z) is also an own relation member but has passenger_lines=2 and sourceKSJ2. It is a generalized two-line representation, not demonstrated independent surveyed opposite rail. Do not average it with track2 to manufacture a centre. Track2 also has KSJ2 ancestry: it is an attributed display reference, not independent survey ground truth. Exclude1435mm highspeed JR-West ways290127915/394844172 and service=yard ways.

The [official IR Kanazawa page](https://www.ishikawa-railway.jp/station/kanazawa/) identifies the conventional passenger service and neighboring Higashi-Kanazawa/Nishi-Kanazawa. The [IR official guide](https://www.ishikawa-railway.jp/uploads/media/BLaM_DoQVAA) distinguishes conventional platforms1–7 from Shinkansen transfer. [JR-West's Kanazawa station guide](https://eki.jr-odekake.net/premises?id=0541449) identifies Shinkansen11–14. This supports group ownership, not an exact track_ref2→platform2 claim. The linked JR PDF returned403; it was not visually inspected. No primary engineering survey or exact passenger face correspondence was established.

## Bounded display-reference proposal

kanazawa-candidate-fragment.json freezes the exact old decoded interval and a proposed replacement of decoded5..22 inclusive, preserving all source/station geometry outside that display window. The18 old controls become19 own-reference controls. Northern boundary [136.65912,36.58681] projects to [136.65909660136217,36.58683710652589] (3.6673m); southern [136.65273,36.58285] to [136.6526340877198,36.58296006775341] (14.9377m). Projections use the existing jp-manual-corrections/geo.mjs helper against the explicitly identity-guarded chain only. The source segment end index is handled as i+1 for slicing interior supports.

This window covers the observed V and its broader offset without entering the station platform fan. The retained immediate guards are decoded4 [136.66344,36.58926] and23 [136.65212,36.58249]. The candidate's minimum interior angle over the complete interval is166.2708°; its largest heading change is13.7292°, at the southern splice. Original-to-selected-reference distance reaches31.7489m at the V. These are coordinate observations, not rendered pixel residuals or proof of an optimal join. A larger5..27 alternative reduces the maximum candidate heading change to11.9238° but unnecessarily approaches the station; it is not staged. The staged minimal candidate needs explicit policy acceptance and original candidate rendering of both joins before being accepted or applied.

The proposal intentionally leaves the Kanazawa station coordinate [136.647771,36.578297] and the physical N02 path unchanged. It does not claim a surveyed centre or complete station-face alignment. If the policy requires a true pair midpoint or directional train-route membership, the evidence gap is exact: no second independently resolved passenger track and no platform-face/directional service binding have been established.

## Actual original images inspected

All files below are the retained ORIGINAL smooth.png and basemap.png, viewed with functions.view_image; no pixel modifications. The capture root is /Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/.

- 000011/000004: visible southeast red V against the gently curving labeled conventional IR corridor; labeled Shinkansen lies separately southeast.
- 000011/000003: northeastern body/road-bridge context. Red generalized body differs from the own conventional band beyond the single V; supports a bounded reference window rather than deleting only one point.
- 000011/000006: Asanogawa bridge/southwestern join context. Conventional and Shinkansen corridors remain visibly separate; some lateral source offset persists southwest.
- 000011/000007: station approach. Red enters the conventional platform group northwest of Shinkansen. Broad platform shading does not resolve exact faces; no station shift is supported.

The last three pairs extend viewed-originals.json to10 pairs/20 originals for the line. They support corridor identity and the current defect; no candidate pixels have been generated or accepted.
