# #39 田園都市線 — read-only preparation

Exact scope: `jp-東急電鉄-田園都市線`; 27 stations /26 complete intervals. Current package2025.5.2. Read current ios/VERIFICATION.md. No production changes, tests, builds, captures, or app launches.

## Legacy capture availability

Legacy report:132 planned viewpoints,120 captured,0 failed,12 pending. Completed captures cover23 intervals. Missing: #7 二子新地→高津 (3 views), #9 溝の口→梶が谷 (4), #12 宮前平→鷺沼 (5). These remain pending; no coverage inferred.

Located 120 actual exact-line captured states, using captureDirectoryIndices (lexicographically sorted item IDs, NOT risk-ordered plan items). Own slots4280–4305. Directory000046 is another line; never infer identity from the plan array ordinal. Verified receipt file existence/byte counts: 0 mismatches. No image hashes or national scans.

All 120/120 completed receipts match current exact source and decoded-display coordinates plus from/to station IDs against their named immutable identity plans; mismatching rows: []. Receipt plan digests: {'57a1c7394e4341c4f370a98c84a73f64b909e156bdaf48f4513bcb73c0a08db6': 7, 'ca243929d9af5237145ae651192f3d6ecb23530b44a940bb978fe55c6d0db9b7': 113}.

## Reuse boundary

Saved isolated centreline captures are valid historical own-line evidence with unchanged scoped geometry. They are NOT automatically current native renderer acceptance: current BatchCaptureGeometry revision appends `specified-capture-v3;projection-witness-v1`, and its style contract adds explicit zoom/outputs/coverage tokens; saved captures use `fixed-z17-v2`. No current wholeLineRenderDependency recomputation was attempted. Main production lanes/follows/circles are explicitly outside these legacy zero-lane captures. All verdicts remain pending.

Saved contracts:
- 120 views: `inspector-centreline-v5-preserve-small-survey-curves;fixed-z17-v2;exact-interior-or-same-line-three-way-endpoints;ownLane=0;mainLane=0;angle=30.0;blend=300.0;fraction=0.4;deviationPx=1.0;deviationMetres=10.0;w=1.5;lane=2.7;r=3.5999999999999996;rmin=3.0;ramp=24.0;weight=1.0;scale=8.0;viewport=1024x768;backing=1;flat;light;poi-excluded;buildings`

## Targeted candidates (data leads, not visual defect verdicts)

Physical junction registry exact own-line record: `[{"id": "shibuya-denentoshi-hanzomon", "region": "jp", "station": "渋谷", "stationCode": "003922", "lineIDs": ["jp-東急電鉄-田園都市線", "jp-東京地下鉄-11号線半蔵門線"], "from": {"identity": {"operatorName": "東急電鉄", "lineName": "田園都市線", "railwayClassCode": "12"}, "coordinate": [139.69997, 35.65945]}, "to": {"identity": {"operatorName": "東京地下鉄", "lineName": "11号線半蔵門線", "railwayClassCode": "12"}, "coordinate": [139.69997, 35.65945]}, "evidence": ["https://www.tokyometro.jp/news/2023/214826.html", "https://www.tokyu.co.jp/history/chapter05_2_1/"], "geometryEvidence": "app/data/rail-sections.json: identical existing surveyed vertex on both named railway identities", "reviewedAt": "2026-10-03", "validFrom": "1978-08-01", "validTo": null, "temporalEvidence": "Official opening/through-operation start establishes earliest accepted connection date; absence of a closing date is not a future timetable guarantee."}]`. Shibuya station003922 has lane0 and circle owner `jp-東京地下鉄-11号線半蔵門線`; own #0 display override is present. Review this endpoint/through continuity and complete #0 carefully.

Largest station seam deflection candidates (angle between last incoming/first outgoing display segments):
- station6 二子玉川: 1.86°; complete adjacent intervals#5/#6
- station23 すずかけ台: 1.19°; complete adjacent intervals#22/#23
- station5 用賀: 0.75°; complete adjacent intervals#4/#5
- station15 あざみ野: 0.56°; complete adjacent intervals#14/#15
- station13 鷺沼: 0.27°; complete adjacent intervals#12/#13
- station14 たまプラーザ: 0.19°; complete adjacent intervals#13/#14
- station12 宮前平: 0.18°; complete adjacent intervals#11/#12
- station7 二子新地: 0.15°; complete adjacent intervals#6/#7

Largest internal display control deflections:
- interval#3 駒沢大学→桜新町, vertex9: 29.58° at [139.65374, 35.63029]
- interval#4 桜新町→用賀, vertex14: 21.13° at [139.63415, 35.62667]
- interval#5 用賀→二子玉川, vertex16: 20.63° at [139.62784, 35.6126]
- interval#0 渋谷→池尻大橋, vertex33: 15.97° at [139.69311, 35.65383]
- interval#16 江田→市が尾, vertex1: 14.83° at [139.55119, 35.55818]
- interval#0 渋谷→池尻大橋, vertex21: 14.07° at [139.6976, 35.65892]
- interval#20 田奈→長津田, vertex10: 13.88° at [139.49913, 35.53193]
- interval#14 たまプラーザ→あざみ野, vertex5: 13.24° at [139.5561, 35.57615]

Other own-station crossings/parallel-corridor review leads from line geography: 二子玉川→溝の口 shared 東急大井町線 corridor; 長津田 platform group/crossing; 中央林間 terminal versus independent 小田急 corridor. These are prioritization leads only; registry establishes only the Shibuya through junction in this scope.

## Exact capture directory map

- #0: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004280`; completed 7
- #1: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004281`; completed 6
- #2: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004292`; completed 6
- #3: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004299`; completed 6
- #4: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004300`; completed 5
- #5: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004301`; completed 7
- #6: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004302`; completed 3
- #7: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004303`; completed 0
- #8: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004304`; completed 4
- #9: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004305`; completed 0
- #10: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004282`; completed 6
- #11: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004283`; completed 4
- #12: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004284`; completed 0
- #13: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004285`; completed 5
- #14: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004286`; completed 5
- #15: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004287`; completed 5
- #16: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004288`; completed 5
- #17: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004289`; completed 6
- #18: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004290`; completed 4
- #19: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004291`; completed 6
- #20: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004293`; completed 5
- #21: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004294`; completed 5
- #22: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004295`; completed 5
- #23: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004296`; completed 5
- #24: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004297`; completed 5
- #25: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004298`; completed 5

## Actual original-image review (2026-10-18)

Viewed the original `smooth.png` and original `basemap.png` in each directory below with `functions.view_image`: fourteen unmodified 1024×768 originals. Selection used each saved `view.json` camera and point ordinal: endpoints for #0/#4/#6/#20/#25; nearest saved camera to the high-angle own control for #3/#5. No crops, contact sheets, redraws, pixel transformations, native launches or fresh captures. Saved red smooth strokes are isolated zero-lane whole-line geometry clipped into these views; their presence beyond the selected interval is not evidence of another interval's completed capture.

| Scope and original directory | Actual observation | Finding / limit |
|---|---|---|
| #0, Shibuya; `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004280/000000/` | The red stroke reaches the Shibuya centre from the southwest, following the broad underground transit cartographic bend; the independent north–south and southwest rail groups remain visibly distinct. | No obvious disconnected red endpoint in this one frame. The precise own underground passenger frame and through junction with 半蔵門線 are obscured by station/building/transit shading. This view cannot establish a surveyed tunnel alignment or final shared-circle/through rendering. |
| #3, 駒沢大学→桜新町; `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004299/000002/` | Near the Shimmachi1 label, approximately image x450–500/y380–395, red forms a visibly deeper southward V than the gentler blue transit bend in the original basemap. This is the same locality as display control vertex9 (29.58° data lead). | Concrete visual deviation candidate against the labelled underground cartography. Do not describe this as proven physical rail/tunnel displacement. Resolve whether the requested reference is that transit cartography before proposing geometry. Complete #3 is not reviewed from this camera alone. |
| #4, 桜新町→用賀, Yoga endpoint; `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004300/000004/` | Red runs along the northeast–southwest labelled transit corridor and bends southwest through the station-area shading. No obvious gross detached segment or reversal is visible in this frame. | Retain pending. The actual narrow longitudinal passenger frame/caps are not independently established by the broad shading; do not certify the Yoga point's chainage or midpoint. This is underground transit cartography, not aerial proof of tracks. |
| #5, 用賀→二子玉川, north throat; `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004301/000005/` | Red turns from the north–south approach into a southwest diagonal through several distinct blue turning/parallel strokes before the station. Its angular turn is visually sharper than the smooth blue alternatives around the throat. | Prioritize own Den-en-Toshi continuation identification. Multiple blue paths and the independent Oimachi approach compete; proximity/colour alone cannot select a replacement. No assertion that every visible blue alternative is own railway. |
| #6, 二子玉川→二子新地, Futako-tamagawa endpoint; `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004302/000000/` | Same throat is visible in the north of this overlapping camera. Red continues southwest across the long shaded station corridor and Tama River bridge, with no obvious isolated gap at the endpoint camera centre. | Confirms the throat candidate is visible from another original camera, not a separate acceptance. Parallel blue rails remain distinguishable; own representative centre and correct station platform midpoint require identification. The entire #6 interval is not certified by this frame. |
| #20, 田奈→長津田, Nagatsuta endpoint; `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004293/000004/` | Red crosses the station building/footprint in the northern of several east–west rail corridors; the blue labelled Yokohama corridor lies farther south. A separate curving Tokyu approach is visible from the northwest. | No obvious red reversal or gap. Station building coverage hides precise own platform caps/rail locus, and the adjacent independent corridors must stay distinct. Do not claim exact alignment or merge to a nearby labelled Yokohama stroke. |
| #25, つきみ野→中央林間, terminal; `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004298/000004/` | Red approaches from the east and terminates around image centre, near the northern edge of the broad east–west station shading. The independent north–south Odakyu corridor lies farther west. | Endpoint/frame candidate remains unresolved: broad station shading is not proof of the narrow own passenger platform, and its cap-to-cap midpoint has not been established. Do not extend to the north–south corridor or recenter on the entire blue building footprint. |

Each directory was inspected as both `<directory>/smooth.png` and `<directory>/basemap.png`; its original `view.json` supplies exact camera and ownership. These observations establish specific review candidates and visible limitations only. No capture or line is accepted from this preparation. The #3 cartographic V is the clearest localized observed issue; #5/#6 are multi-corridor throat review candidates. The remaining selected frames provide endpoint/context evidence with unresolved station-frame ownership or occlusion. No original pixels were changed, and no production source was edited.
