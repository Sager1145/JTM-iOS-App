# Meitetsu Tsushima Line Third Inspector native review

Status: **REPAIR REQUIRED.** This fresh Third Inspector review independently reproduces the false river-bridge dogleg in interval `#5` (Shobata → Fujinami). It also confirms that the Sukaguchi source endpoint sits at the northwest throat of the shared station graphic, rather than at the longitudinal middle of the visible platform body. The baseline is not accepted as complete display geometry.

## Coverage and method

- Line: `jp-名古屋鉄道-津島線` (`津島線`).
- Reviewed: all 7 intervals, all 44 viewpoints, and all 132 Third Inspector panels (`basemap.png`, `display.png`, and `smooth.png`) under `third/captures`.
- I opened every triplet in fresh interval contact sheets. I separately inspected the original-resolution `#5` bridge panels and enlarged `002592/000002`; I also opened and enlarged the Sukaguchi source/display/smooth triplet to distinguish the westbound Tsushima approach from the Nagoya Main Line and surrounding yard graphics.
- The Third scoped report records 44 captured viewpoints, 0 pending, and 0 failed. These figures establish coverage only.

## Interval findings

| Interval | Endpoints | Views | Third Inspector finding |
|---:|---|---:|---|
| `#0` | Sukaguchi → Jimokuji | 7 | The westbound interval follows the labelled Tsushima Line and keeps its complete body toward Jimokuji. At Sukaguchi, the source/display endpoint is the image-centre point near `(512,384)` in `002587/000000`. It lies at the northwest throat where the westbound branch meets the shared station complex. The relevant translucent station body continues southeast along the same railway axis to roughly `(670,480)`; the visible body begins around `(485,340)`, placing the endpoint close to the northwest boundary rather than its longitudinal middle (approximately the high-500s/low-400s in this frame). The north/northeast blue corridor is the Nagoya Main Line toward the adjacent stations, and the broad southeast pale-blue area is yard/shared-station casing; neither was treated as a separate Tsushima platform. The images therefore establish the throat placement, but do not select an exact replacement platform coordinate. |
| `#1` | Jimokuji → Shippō | 7 | All seven views show a continuous own-line interval with complete station tails. No reversal, branch visit, seam break, or detached cap is visible. |
| `#2` | Shippō → Kida | 6 | The route remains on the same westbound guide through all overlaps and preserves its shallow curvature. No concrete normal-offset or station-approach defect is visible. |
| `#3` | Kida → Aotsuka | 7 | The complete interval and both endpoint approaches are shown. Its bends are continuous, without a chord, fold, return hook, or wrong-line turn. |
| `#4` | Aotsuka → Shobata | 6 | The interval stays on the labelled railway into Shobata. The `#4/#5` seam has compatible direction and no separate cusp or cap. |
| `#5` | Shobata → Fujinami | 5 | **Rejected.** In Third `002592/000002`, cyan and magenta follow the own-line rail to about `(818,216)`, make a sharp southward notch to about `(837,232)`, and then turn northeast back toward the same straight diagonal. Apple’s paired blue railway strokes and the `Meitetsu Tsushima Line` label continue straight across the river; there is no turnout, bay, or bridge displacement supporting the notch. It is also visible in the overlapping bridge coverage. The rest of the five-view interval generally overlays the same own-line band, with no second equally clear lateral displacement, but the complete interval must be refitted and reprojected rather than repaired by deleting the three visible corner vertices alone. |
| `#6` | Fujinami → Tsushima | 6 | The line continues south from the shared Fujinami seam and enters Tsushima on the labelled north-south railway corridor. Its endpoint lies within the long own-line station casing, without a detached tail, reversal, or excursion onto an east-west road. The shared multi-track casing does not prove an exact platform face or metre-level midpoint. |

## Result and repair boundary

The independent Third set confirms that `#5` contains a cartographically impossible dogleg across an otherwise straight railway bridge. Repair evidence must cover all five `#5` viewpoints, preserve both adjacent station seams and travel direction, and demonstrate the whole interval's normal alignment. A local vertex deletion or constant translation is insufficient evidence.

The Sukaguchi endpoint observation is also concrete at the representation level: `[136.845755, 35.19893]` renders at the northwest throat/edge of the shared station body, not at its visible longitudinal middle. The Third images do not establish which shared platform face should own the Tsushima endpoint, so a replacement requires the focused z18 regional frame and shared-line identity comparison. This review does not move the physical station, change topology, or borrow the nearby Main Line/yard frame.

No additional continuity, wrong-direction, or missing-tail failure is visible in intervals `#1`–`#4` or `#6`. Those observations remain supporting evidence while `#5` and the Sukaguchi frame question are pending bounded repair review.
