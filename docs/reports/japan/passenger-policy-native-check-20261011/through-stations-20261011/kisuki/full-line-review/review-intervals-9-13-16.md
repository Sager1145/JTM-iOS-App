# Kisuki complete-interval visual review: intervals 9–13 and 16

Read-only source/data review; only contact sheets and this evidence note were written. Followed current `ios/VERIFICATION.md` and `jtm-railway-audit-repair`. No builds, tests, native capture, UI operation, source edits, or new verification runners. Root owns dependency validation and native/main-product follow-up.

Evidence root: `docs/reports/japan/passenger-policy-native-check-20261011/parallel-instance-kisuki-keiyo/evidence`. Capture item directories are sorted plan item IDs, not numeric interval order. Every listed ordinal was actually viewed as a paired basemap/smooth row in contact sheets; suspect locations and final-tail cases were reopened at original 1024×768 resolution. Every interval includes ordinal zero and its final ordinal. Contact sheets `south-iN-pXX.jpg` preserve paired side-by-side views, four ordinal rows per sheet.

## Exact visual coverage

| Interval | Capture item directory | Visually inspected ordinals | Paired viewpoints |
|---|---|---|---|
| 9 | `008050` | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 | 13 |
| 10 | `008036` | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 | 14 |
| 11 | `008037` | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 | 20 |
| 12 | `008038` | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 | 13 |
| 13 | `008039` | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21 | 22 |
| 16 | `008042` | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 | 21 |

103 paired viewpoints inspected, with no missing pair in these assigned intervals. This is viewpoint review coverage, not whole-line acceptance, metres of independently proved track, or evidence for intervals owned by other reviewers. Interval 12 is fresh: first/final `view.json` timestamps 2026-10-12T04:31:14Z / 04:31:17Z, all 13 pairs present. Checkpoint at read: capturedCount 304, failedCount 0; neither number is an alignment verdict. Reused views retain 02:14–02:15Z capture timestamps. All assigned view metadata inspected below use whole-line dependency `978acffdebe9c80d8adb806d8750962900603f049c96ca6dbe6ad35136147608`; root supplied the current-production configure/dependency acceptance. This worker did not independently rerun capture or rehash dependencies.

## Results by interval

- **9, ordinals 0–12:** continuous valley and station-approach shape in all frames; persistent local separations from the blue Apple-labelled Kisuki track are visible, especially Kamiminarikami station/final approach at 11–12. Final original pair confirms the red curve north of the blue railway, rather than on the nearby road. Retain discrepancy, do not mark passed.
- **10, ordinals 0–13:** curve and long eastward valley remain continuous. Most pronounced local discrepancy is 0–3: red line lies north of Apple’s identified railway, including Yunohara approach at 2. Later valley/frame tails and station endpoint at 12–13 were inspected. Retain discrepancy, do not mark passed.
- **11, ordinals 0–19:** real large curves survive; no visually obvious broken stroke or extra connecting chord in contact rows. There are local separations through the first mountain straight and later reverse curve at 13–16. The straight mountain section’s physical/tunnel status is not established by these snapshots. Original 4 shows separately labelled prefectural road 156 beside the blue labelled railway; it must not become a road-snap target. Original 14 confirms modest red/blue reverse-curve separation. End approach 17–19 remains continuous. Retain discrepancy and physical-evidence limitation.
- **12, ordinals 0–12:** all fresh pairs inspected. Southern Yakawahongo approach 10–12 warranted original inspection at 11. The original shows much closer agreement than the reduced contact sheet suggests; red retains the station/rail corridor with small local curve differences. Do not describe its nearby river or broad road as the railway, and do not classify this as a large offset from the contact sheet alone. No gross broken connection seen; exact geographic acceptance remains limited by Apple track depiction and the modest local differences.
- **13, ordinals 0–21:** all reverse curves and the reversal stem/branches at 17–21 inspected. Original pairs at 6 and 10 show close-to-moderate red/blue differences, much smaller than some apparent red-to-river distances in the contact sheet. At 6 the red line crosses the river along the identified railway; the blue river is not an alternate rail alignment. The real reversal geometry at the final station is present in the basemap and smooth overlay; original 21 confirms its separate stem and through leg. Preserve these branches, do not smooth into a shortcut or delete a duplicated-looking stem. Local red/blue shape differences remain review candidates, not a proved topology defect.
- **16, ordinals 0–20:** complete final interval reviewed, including the Geibi/Kisuki convergence and final station at 18–20. Original 2 confirms a broad red curve displaced east of the Apple-labelled Kisuki track. Further local separation is visible in originals at 12, with the red curve/road crossing differing from the blue track. Main valley shape remains connected. Final original 20 confirms a continuous approach into the railway/station corridor and no gross terminal gap; it does not establish company lane/circle/card composition. Retain discrepancy, do not mark passed.

## Concrete original evidence and camera metadata

Each row below identifies the original `basemap.png`, `smooth.png`, and `view.json` in the same directory. Camera latitude/longitude are viewpoint centres, not a measured defect coordinate. Approximate pixel separations are visual estimates from original screenshots, not a computed Apple-track distance metric. Nominal camera scale is about 0.97 metres per point.

| Interval / ordinal | Original directory under evidence root | Camera centre (lat, lon) | Finding |
|---|---|---|---|
| 9 / 12 | `captures/008050/000012/` | 35.19665600, 133.00986700 | Kamiminarikami tail: red curve about 10–25 pixels north of labelled railway along right-hand station exit; local discrepancy. |
| 10 / 2 | `captures/008036/000002/` | 35.19552148, 133.01732757 | Yunohara valley: red about 20–45 pixels north of labelled railway through central bend/long right approach; strongest concrete local mismatch in interval10. |
| 11 / 14 | `captures/008037/000014/` | 35.18257609, 133.08032380 | Reverse curve: roughly 5–20 pixel local red/blue separations; actual reverse shape retained, not a chord replacement. |
| 12 / 11 | `captures/008038/000011/` | 35.14952389, 133.08919596 | Yakawahongo station approach: original confirms close corridor placement; small curve separation, no gross offset inferred from contact sheet. |
| 13 / 6 | `captures/008039/000006/` | 35.14033159, 133.10775377 | River crossing/curve: local red/blue shape difference, roughly 5–15 pixels. Follow labelled railway, not river or road. |
| 13 / 10 | `captures/008039/000010/` | 35.12938678, 133.11421906 | Gentle valley curve: small red/blue difference around bend; river is independently visible west of rail. |
| 16 / 2 | `captures/008042/000002/` | 35.03895798, 133.11991871 | Broad curve: red approximately 25–45 pixels east of labelled Kisuki railway near middle and lower approach; substantial local mismatch. |
| 16 / 12 | `captures/008042/000012/` | 35.01156939, 133.12964378 | Road crossing/reverse curve: local red/blue differences roughly 10–25 pixels near bend/crossing. |
| 16 / 20 | `captures/008042/000020/` | 35.00113500, 133.14831500 | Final Geibi/Kisuki station approach: continuous red convergence/station path visible; separate blue company line reference, no gross endpoint gap. |

Additional original pairs opened: interval11 ordinal4 (mountain straight/road distinction), interval13 ordinal21 (reversal station final tail). All other listed ordinals were examined in labelled paired contact-sheet rows, rather than inferred from file counts.

## Limits and next owning decision

Snapshots depict Apple’s thin blue labelled railway with limited detailed track/platform evidence. Agreement or disagreement here establishes a native visual candidate against that reference; it does not prove physical survey truth, operational passenger status, tunnel interior, official platform identity, production lane offsets, station circles/popups, main-map LOD, ridden routes, leaks, or performance. Missing or ambiguous reference details stay insufficient. No nearby road, river, or unrelated railway was selected as a substitute.

Root should carry the concrete interval9/10/16 mismatch candidates into the sole checklist and inspect their owning source/display boundary before repair, using official/georeferenced track evidence where needed. Interval11 smaller differences and interval12/13 modest differences remain scoped candidates; preserve their real bends and reversal branches. These six assigned intervals are visually reviewed, with unresolved geographic alignment findings; they are not an all-pass certificate for Kisuki or the checklist.
