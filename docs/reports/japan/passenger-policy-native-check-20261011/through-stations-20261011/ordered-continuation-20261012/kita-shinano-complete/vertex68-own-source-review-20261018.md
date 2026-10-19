# Kita-Shinano #0 v68/69: own source and tiny display proposal

2026-10-18. **The actually viewed Apple own-labelled corridor supports removing the isolated red right-step at old vertex69 for display, retaining68 and every other coordinate.** No OSM70m corridor shift, physical tunnel-centre claim, station movement or physical source edit is proposed. Parent independently viewed both point14 originals and agreed that the red right-step is isolated while the own blue corridor is continuous. A fresh candidate render is still required.

## Original own controls and actual pixels

Own `jp-しなの鉄道-北しなの線` interval0 runs **妙高高原001746→黒姫001788**, north→south. v67 `[138.18863,36.83697]`→v68 `[138.18858,36.8364]`→v69 `[138.18864,36.83637]`→v70 `[138.18854,36.83439]`. v66 `[138.18861,36.838]` and71 `[138.18852,36.83422]` are outside guards. N02 own feature15085 coordinate67 supplies decoded68; raw66..69 equal decoded67..70 exactly. This is an existing source jog, not an introduced display alias. The62.02°/60.32° turns and6.296m transverse edge only identify the local geometry; they are not the reason for acceptance.

Actually reopened these **two original PNGs**:

- `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000186/000014/basemap.png`
- `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000186/000014/smooth.png`

The labelled blue **Kita Shinano Line** corridor continues almost north–south at the small shoulder, with no matching blue transverse right-step visible. In smooth, red approaches old68, steps east/right at69, then returns to its south-going run. The genuine broader north-side bend stays distinct and must remain. These are the own conventional corridor pixels, not a neighboring road or another railway. Labels partly overlap the thin line; this is a visible cartographic continuity judgment, not a subpixel measurement or underground survey.

Using the existing view.json camera/Mercator rectangle to locate the **geometry vertices** gives67 `(512.474,414.494)`,68 `(507.814,480.875)`,69 `(513.406,484.369)`,70 `(504.085,714.952)` in the original1024×768 image. Thus the red68→69 edge steps right approximately5.59px. These are metadata-projected source positions, not measured blue rail-pixel residuals. The original is historical fixed-z17-v2, light, centreline-v5, ownLane0/mainLane0; it is not fresh Main multi-line evidence. Frozen local copies `apple-p14-basemap.png`, `apple-p14-smooth.png`, `apple-p14-view.json` retain the exact originals and contract in `vertex68-own-source-20261018/`.

## Own conventional source on both sides

Only six exactly identified own ways and the two tunnel-way relation responses were freshly fetched. Full originals, source URLs and SHA256 values are retained in `own-tunnel-and-control-comparison.json`. Scoped cache evidence comes from E138N36, fetched2026-08-18T10:36:10.600Z. All six fresh geometries equal cached coordinates exactly.

| Own north→south chain | Versions | Actual shared-node continuity |
|---|---|---|
|462174017(reverse)→462174024(reverse)→462174020(reverse)|1/3/1|North link joins tunnel at4575781783; tunnel joins south link at4575781784.|
|462174018→462174025→462174023|1/3/1|North link joins tunnel at264809245; tunnel joins south link at264809263.|

All six are own name北しなの線/operatorしなの鉄道, railwayrail/usagemain, gauge1067,1500V, no service tag. Tunnel024/025 are both `tunnel=yes`, layer−1, named野尻トンネル, sourceBing2011; v3 dated2024-02-25. Their interior nodes are disjoint and none carries a switch tag; no retained connecting way supports a cross-track step at this point. This is no positive source support for a physical switch, not a survey proving its absence.

Own railway relation4669040v29 includes west chain south→north at members41..43 and east chain at65..67. Explicit train relation14097999v22, tagfrom軽井沢/to能生/nameかもめビーチ, contains020→024→017 at166..168: a northbound passenger route object on the west chain. The east tunnel's returned response contains the own railway relation only. These objects establish attributable conventional main tracks; they do not prove current scheduled service, select a southbound display rail from geometry alone, or justify importing another track. Cached abandoned1254501772 farther west is explicitly excluded; neither abandoned line, expressway nor Shinkansen is used.

## Why the OSM tunnel shape is not the repair geometry

The source tunnel pair bows substantially **east** of the N02 near-straight local controls. Existing geo-helper projections onto each attributed tunnel give:

| Old vertex | West tunnel024 | East tunnel025 |
|---|---:|---:|
|65|21.061m|24.954m|
|66|34.574m|39.587m|
|67|61.605m|66.831m|
|68|70.843m|77.339m|
|69|65.473m|71.962m|
|70|21.273m|25.510m|
|71|16.351m|20.371m|
|72|12.485m|15.723m|

These are source comparisons, not map-pixel errors. Control64 lies beyond the acquired tunnel extent; its endpoint-clamped comparison in the source JSON is expressly not used as a lateral residual. OSM's underground shape does not invalidate the clear own-labelled Apple corridor as a display reference, nor authorize moving the whole displayed corridor70m east. No averaging of the two tracks is proposed. Physical tunnel centre/curvature remains unverified.

## Exact bounded display proposal

`display-only-step-proposal.json` freezes old67..70 and proposed `[old67,old68,old70]`, with outside66/71 exact. **Only old displayed69 is removed.** No new coordinate is introduced. Old68 and all other interval coordinates, station endpoints, physical compact rows, IDs and stored mileage remain exact; broader true bends remain untouched.

The resulting calculated turns at retained68/70 are3.103°/4.467°, and old69 is5.392m from the proposed68→70 segment. These are secondary construction checks; the actual red-only shoulder and continuous own blue corridor provide the display basis. This proposal makes no claim that a physical railway point or switch was deleted. The candidate implementation/export and focused evidence are recorded separately in `vertex69-display-candidate-implementation-20261018.md`. No production apply/native capture/build occurred in this source/implementation work; fresh complete-interval candidate review remains pending.
