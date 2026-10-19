# Hisatsu south: complete manual native image review

Reviewed 121 viewpoints of `jp-九州旅客鉄道-肥薩線`, intervals 18–26, in all three stages: Apple `basemap.png`, actual shipped-part `display.png` (cyan), and `smooth.png` (red). Every ordinal below was visually inspected, including distance-zero starts and final short tails, through 34 labelled contact sheets `south-i*-o*.jpg`. Four candidate triplets were additionally viewed at original 1024×768 resolution and retained under `south-originals/`. Exact per-view IDs, source paths, timestamps, cameras and render dependencies are in `south-coverage.json`.

The line remains visibly continuous throughout these views. I observed no break, perpendicular station seam, isolated doubled segment, road/river takeover, or extra loop. This is an isolated-centreline observation, not acceptance of the main map's lanes, family joins or station dots. Several sustained offsets remain candidates for bounded aerial/identified-track investigation; capture completion is not geographic acceptance.

| Interval | Stations | Capture directory | Exact ordinals viewed | Final distance / final short tail |
|---|---|---|---|---|
| 18 | 吉松009944 → 栗野009952 | 000950 | 0–22 inclusive (23) | 7514.171m / 164.171m |
| 19 | 栗野009952 → 大隅横川009959 | 000951 | 0–19 inclusive (20) | 6441.145m / 141.145m |
| 20 | 大隅横川009959 → 植村009963 | 000953 | 0–9 inclusive (10) | 2911.991m / 111.991m |
| 21 | 植村009963 → 霧島温泉009969 | 000954 | 0–9 inclusive (10) | 2991.219m / 191.219m |
| 22 | 霧島温泉009969 → 嘉例川009979 | 000955 | 0–17 inclusive (18) | 5672.498m / 72.498m |
| 23 | 嘉例川009979 → 中福良009983 | 000956 | 0–6 inclusive (7) | 2077.458m / 327.458m |
| 24 | 中福良009983 → 表木山009990 | 000957 | 0–8 inclusive (9) | 2481.903m / 31.903m |
| 25 | 表木山009990 → 日当山009998 | 000958 | 0–14 inclusive (15) | 4747.852m / 197.852m |
| 26 | 日当山009998 → 隼人010003 | 000959 | 0–8 inclusive (9) | 2559.791m / 109.791m |

Original directories are `/private/tmp/jtm-remaining-lines-manual-evidence/captures/<directory>/<six-digit ordinal>/`. Each includes the three images and `view.json`. Distances identify camera positions along the interval, not geographical error.

## Candidates requiring primary/aerial corroboration

These discrepancies are present in both actual display and smooth, so a smooth-only change would not resolve them. Apple’s labelled railway establishes the comparison feature; it does not itself establish the correct passenger track coordinates. No geometry or station projection is proposed from nearest-feature matching.

| Candidate | Exact views / original receipt | Observation | Next bounded evidence |
|---|---|---|---|
| North approach to 大隅横川 | #19 ord16–17; original `000951/000017`; camera 31.9099451532,130.7001336150 | Both stages lie east of the labelled Hisatsu railway along the north straight and turn, approaching the station without a break. Separation is clearly visible in the original triplet. | Aerial around this approach plus positively identified same passenger leg. Retained `south-originals/000951-000017/`. |
| North approach to 霧島温泉 | #21 ord5–7; original `000954/000007`; camera 31.8724526814,130.7365732709 | Both stages bow east of Apple’s labelled railway, toward route50, while railway and river remain distinct. This is the clearest open-corridor candidate in the south set; the line rejoins the station-area corridor continuously in ord8–9. | Bounded aerial of the river/road/rail bend. Retained `south-originals/000954-000007/`. |
| Forest bend between 表木山 and 日当山 | #25 ord7–9; original `000958/000008`; camera 31.7778132659,130.7433384913 | Both stages cut south/inside the labelled forest railway bend; original imagery shows sustained separation through the bend, with no break. | Same-leg primary identity and aerial where visible. Forest/tunnel concealment may prevent an actual alignment decision. Retained `south-originals/000958-000008/`. |
| South of 栗野, route55/expressway bend | #19 ord4–6; original `000951/000005`; camera 31.9408657526,130.7104908527 | Original resolution downgrades the contact-sheet impression: both stages follow the correct broad railway bend with smaller local side separation. No road takeover. Lower priority than the three above. | Only investigate if a bounded aerial independently shows a meaningful discrepancy. Retained `south-originals/000951-000005/`. |

No pixel-to-metre deviation measurement was performed. These are visually observed source/display candidates, not confirmed source defects or proposed repair endpoints.

## Remaining interval observations and limits

- #18: all23 views continuous through the Yoshimatsu railway group, river crossing and Kurino approach. Local offsets in ord5–6 and15–20 are modest in contact views. Apple’s faint forest geometry in ord10–15 cannot establish exact track centring. Multiple visible station tracks are not evidence that the isolated passenger centreline has an ownership error.
- #20: all10 views continuous through the river/road bends and both station approaches; local separations around ord4–6 and8–9 do not show a distinct wrong corridor.
- #22: all18 views continuous south from Kirishima-Onsen, across the river and through the forest straight to Kareigawa. Both stages remain on the labelled railway corridor. Modest local curve separation near ord14–15 and station artwork in16–17 does not justify a projection.
- #23: all7 views continuous, generally following the river railway corridor. Ord2–3 show a smaller inside-curve separation; neither a river nor road replaces the railway identity. Nakafukura endpoint remains continuous.
- #24: all9 views continuous through the Nakafukura–Omotegiyama bends and final31.9m tail. Local inside-curve separation around ord3–4 merits no independent repair claim from these vector images.
- #25: the candidate above is distinct from the continuous open town approach ord10–14; the road, river and railway remain separately readable there.
- #26: all9 views continuous from Hinatayama, over the town/river corridor, through the approach joining the visibly separate Nippo railway, into Hayato and the final109.8m tail. No isolated-line duplicate or hard join was seen. Main-map ownership/family joins need root's actual main app review.

The receipts explicitly describe complete-line DisplayParts smoothed with retained station/end anchors at z17, then viewport-clipped: isolated centreline with no lanes/follows/joins/family collapse. They remain `result: pending`, `reviewFresh: false`; this review does not convert those fields into automatic acceptance. The captures contain no JTM station dots, so station-dot coordinates and line-dot contact are unverified here; blue Apple station artwork is not a JTM marker or a platform-centre reference. Forest, tunnel, roofs and broad station artwork do not expose physical track centres. The already-established south operating-status evidence is reused without an external news claim or collection.

No source edit, native UI operation, build or test was performed for this review.
