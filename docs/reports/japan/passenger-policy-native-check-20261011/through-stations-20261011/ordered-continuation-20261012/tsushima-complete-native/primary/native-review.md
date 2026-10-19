# Meitetsu Tsushima Line Primary Inspector native review

Status: **REPAIR REQUIRED.** The complete Primary evidence set exposes a false dogleg in interval `#5` (Shobata → Fujinami). The displayed route leaves the labelled Meitetsu Tsushima Line guide on the east side of the river bridge, makes an unsupported southward notch, and returns to the same straight railway. The baseline therefore is not accepted as complete display geometry.

## Coverage and method

- Line: `jp-名古屋鉄道-津島線` (`津島線`).
- Reviewed: all 7 intervals, all 44 viewpoints, and all 132 Primary Inspector panels (`basemap.png`, `display.png`, and `smooth.png`) under `primary/captures`.
- I opened every triplet in interval contact sheets and compared the basemap, cyan display, and magenta smooth panels. I then opened the five `#5` display panels at original resolution, enlarged the river-bridge defect from `002592/000002`, and inspected original-resolution triplets at the Sukaguchi and Tsushima ends.
- The scoped report records 44 captured viewpoints, 0 pending, and 0 failed. These counts establish evidence coverage only; they do not establish cartographic correctness.

## Interval findings

| Interval | Endpoints | Views | Primary Inspector finding |
|---:|---|---:|---|
| `#0` | Sukaguchi → Jimokuji | 7 | The westbound departure is continuous and follows the labelled Tsushima Line guide through the broad curve. At Sukaguchi, however, the source/display endpoint is at the western throat of the large shared station casing, near the point where the Tsushima branch meets the Nagoya Line corridor, rather than at the longitudinal middle of the visible platform body. Because this is a shared multi-track complex, the panels do not by themselves prove the exact own-platform midpoint, but they do show that endpoint/frame alignment needs a bounded raw-frame check before acceptance. No wrong eastbound Nagoya-Line excursion is shown. |
| `#1` | Jimokuji → Shippō | 7 | The full interval remains on the same westbound railway guide. Both tails are present, and the overlapping views show no reversal, branch swap, detached cap, or visible seam break. |
| `#2` | Shippō → Kida | 6 | The route is continuous across all six views and retains its shallow bends. No definite normal displacement or wrong-line approach is visible at contact-sheet and full-panel scale. |
| `#3` | Kida → Aotsuka | 7 | The complete east-west interval and both station approaches are present. Curves remain continuous without a chord, hook, or local reversal. |
| `#4` | Aotsuka → Shobata | 6 | The route follows one continuous Tsushima Line guide into Shobata. The `#4/#5` station seam is present and has compatible travel direction; no separate defect is visible on the `#4` body. |
| `#5` | Shobata → Fujinami | 5 | **Rejected.** In `002592/000002`, cyan and magenta leave the straight labelled own-line guide at approximately `(818,216)`, descend to approximately `(837,232)`, and then turn back northeast. The basemap railway pair crosses the river as one continuous straight diagonal and contains no turnout, bridge jog, or southward bay at this location. The same notch is visible in the overlapping bridge view, so it is route geometry rather than a label occlusion. Outside this notch, the five overlapping panels generally keep the displayed stroke within the visible own-line band; I found no second comparably definite normal-offset section, but that does not justify deleting only the notch vertices without refitting and reprojection-checking the complete interval. |
| `#6` | Fujinami → Tsushima | 6 | The line continues south from the `#5/#6` seam and follows the labelled Tsushima Line/Bisai Line corridor into Tsushima. The terminal stroke ends inside the long north-south blue station casing and does not visit an east-west road or another line. The large shared station graphic does not support a metre-level or exact platform-face claim, but there is no visible detached terminal tail or return hook. |

## Repair boundary and result

The `#5` river-bridge notch is a concrete wrong-shape defect and blocks acceptance of the seven-interval baseline. A repair should use the continuous own-line bridge glyph across the complete `#5` interval, retain the Shobata and Fujinami seams, and reproject every `#5` viewpoint to check the whole normal residual. Removing three points in isolation or applying a constant translation would not establish that the rest of the interval remains on the same railway.

Sukaguchi also remains an endpoint-frame question: the current dot/endpoint is visually at the shared western throat rather than the middle of the long platform casing. That observation warrants focused raw-frame and shared-line identity evidence before choosing an override; this review does not invent a new station coordinate. Tsushima is visibly inside its own north-south station band, but the Apple casing is not surveyed platform evidence.

Intervals `#1`–`#4` and `#6` show no additional concrete continuity or direction failure in this Primary set. Their observations remain supporting evidence only until the repaired `#5` geometry and the Sukaguchi endpoint question receive bounded follow-up review. Source IDs, station order, kilometre measures, and physical/legal topology were not changed.
