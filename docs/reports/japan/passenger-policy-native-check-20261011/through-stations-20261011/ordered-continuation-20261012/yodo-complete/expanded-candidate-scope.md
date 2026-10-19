# Yodo expanded candidate scope and implementation dependencies

Design only. Precise station aliases await high-zoom original own-frame evidence. No production, code, app or physical data changed. The loop-v1 station endpoint and preserved-prefix assumptions are provisional under this expanded scope.

| Owner | Complete intervals | Display station aliases | Outer guards |
|---|---|---|---|
| Yodo `jp-四国旅客鉄道-予土線` | #0 Wakai–Iejigawa; #18 Muden–Kita-Uwajima | 009535; 009471 | 009558; 009423 |
| Nakamura `jp-土佐くろしお鉄道-中村線` | #0 Kubokawa–Wakai; #1 Wakai–Kaina | 009535 | 009500; 009571 |
| Yosan `jp-四国旅客鉄道-予讃線` | #87 Takamitsu–Kita-Uwajima; #88 Kita-Uwajima–Uwajima | 009471 | 009452; 009486 |

All six complete intervals require new candidate review. Unchanged Yodo #1–17 may reuse baseline evidence only after exact dependency checks. Current three owners have no display station/interval overrides. Preserve physical station rows, IDs, compact segments, continuing flags, kilometres, railway identity and route graph; use line-scoped `displayStationCoordinates` and complete `displayIntervalCoordinates` for the display repair.

Root's adjudication identifies Wakai normal displacement and Kita-Uwajima chainage displacement beyond the intentional half-lane. Its coordinates are estimates, not frozen aliases. Determine each narrow own-frame's longitudinal endpoints and midpoint in an exact high-zoom raw camera, then project normally to the identified passenger rail band. Attached buildings/bulbs, whole group polygons, old N02 chainage and unresolved opposing-face averages are not midpoint evidence.

## Exact shared seams

Decoded Yodo #0 and Nakamura #1 share their first61 supports, indices0–60. Nakamura #1 restores its first point from its preceding continuing compact row. This is current literal source identity, not physical turnout proof. Wakai frame/stem correction may change this common display prefix in BOTH owners; loop-v1's preserved61 condition cannot remain an unconditional design constraint. Freeze a revised evidenced shared span and its end boundary in both owners, identical in forward direction, while keeping the outgoing Yodo westward loop and Nakamura southern arm distinct. Do not invent a fork by snapping to a nearest vertex.

Wakai alias = Yodo #0 start = Nakamura #0 end = Nakamura #1 start, literally. If platform chainage moves, repartition the Nakamura adjacent display intervals rather than drawing a connector to the old boundary. Review complete common stem and incoming/outgoing directions.

Decoded Yodo #18 ends in three identical supports shared with Yosan #87: Yodo indices130–132 = Yosan indices26–28. Kita-Uwajima alias = Yodo #18 end = Yosan #87 end = Yosan #88 start, literally. If the identified frame is farther south, repartition Yosan #87/#88 and extend Yodo's evidenced shared approach to that common frame. Preserve the actual branch direction toward Muden and the north Yosan continuation; do not make a hook back to the old station chainage or add route edges.

Raw common points are insufficient: carry corresponding shape boundaries through `displayPartsForLine`, smoothing, station approach anchoring and lane taper/follow. Independent spline contexts can separate identical raw supports. Shape boundaries must not add station slots. An exact shared-follow, if needed and evidenced, gets authority only inside its proven span, without kernel extension beyond the fork; family ownership stays separate. Current selected-owner native rows have no follows or family windows, so do not add them automatically.

## Native parts and measure suffixes

Consumed native ruler input is `app/public/rail/display-lanes.json`, not compact package `lanes`. Current part0 rows are Yodo1518 vertices/76166.3m with final-coordinate fallback; Nakamura817 vertices/43113.4m with compact interval range0–13; Yosan4127 vertices/297876.7m with final-coordinate fallback. Consumed lane ranges are Yodo0–76166.3 at−0.5; Nakamura0–43113.4 at+0.5; Yosan0–775 at−0.5. Compact rows differ: Yodo0–5783.7; Nakamura4300–10325; no compact Yosan lane. Root's consumed-resource adjudication agrees with the native input.

Derive the three candidate owners through `app/public/rail-network.js:displayPartsForLine` and `app/scripts/railway/build-display-lanes.mjs:partRowsForLine`, passing the same effective display stations and intervals. Rebuild owned native rows, vertex counts, fallback coordinates, interval extent metadata and station slots from actual final parts. Measure remapping must use final part geometry and its existing ruler, not raw proposal lengths. `repair-tsushima-sukaguchi-display.mjs:deriveCandidateMeasuredReferences` illustrates the scoped approach but is hard-coded to Meitetsu and must not be invoked for Yodo.

Measures before an unchanged guard remain unchanged; interior references project onto their own interval/part; later references shift by final-part length delta. Respect existing rounding and exact full-part endpoint mapping. Yodo #0 changes shift every later measure, and #18 changes the final total: update its full-line lane end. Nakamura #0/#1 changes shift later measured suffixes while their coordinates may remain unchanged: update its full-line lane end. Yosan #87/#88 is distal, so its initial775m lane remains unchanged if its prefix is literal unchanged.

Current Yosan-2/Yosan-3 follows into Yosan end at209100m and249700.32822160423m, before the affected distal intervals. Preserve these exact references and slices after confirming unchanged prefix; refresh resource dependency identity where required by the changed owner. No selected-owner hub reports, chain boundaries or family windows were found. Check any newly discovered measure-bearing reference rather than assuming lanes are the only users.

`build-display-network.py` consumes native rows, applies lanes and emits station slots/records and manifest dependencies, remeasuring final chains on its own ruler. Main dots use their slot/stroke anchor. Do not cancel the intentional half-lane by moving a correct raw alias. When resources are eventually built, preserve current history input and the existing external history-directory requirement. No build was run here.

## Bounded next steps

1. Root obtains high-zoom original own-frame, approach and fork evidence with exact cameras; freeze aliases from those picks.
2. Prepare the six complete candidate intervals. Carry loop witnesses only where the expanded station/stem repair preserves their validity. Preserve outer guards unless a concrete defect requires further scope; do not make return bends to known-wrong guards.
3. Check literal alias/end joins, shared direction/boundaries and common projected control order. Preserve physical data and kilometres.
4. Derive owned native parts and measure-reference changes. Prove unchanged intervals, aliases, final geographic slices and render contract before reusing Yodo #1–17 pixels; whole-line digest alone does not decide local reuse.
5. Review all six complete intervals in every requested Inspector and Main station midpoint/dot, shared span, fork, lane boundary and outer endpoints. Keep forest/tunnel/cartographic and dated-service limits. Helper/reprojection success is not native acceptance.

Reviewed sources: current package/native input, JS display owner, Swift `CompactPackage.decodeDisplayIntervals`, both display builders, scoped measured-reference owner example, and `wakai-adjudication.json`. JS and Swift weld displayed interval endpoints to line-scoped aliases; this requires matching adjacent endpoints but does not prove a good approach.
