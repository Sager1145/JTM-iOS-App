# Keikyu Airport V5 — Third native visual review

Verdict: **ACCEPT for this Third Inspector candidate rendering**. I reviewed the actual pixels rather than treating the capture counter, lane state, or internal distance values as alignment evidence.

## Coverage receipt

- Opened all nine original-detail contact pages, `review-0.jpg` through `review-8.jpg`.
- Reviewed all 27 viewpoints and every basemap/display/smooth panel: 81 panels total.
- Full-resolution captures are under `captures/001329` through `captures/001334`: interval counts 4/4/3/4/5/7 for Airport intervals 0–5.
- All 81 raster files are readable 1024×768 PNGs. The Third rasters are independent outputs rather than byte copies of Primary (0/81 corresponding PNGs are byte-identical).
- All 27 metadata records identify the expected Airport interval and share `wholeLineRenderDependency` `3af34319e9ae54d158c4aff64aa9b1dfb41177172bd88a84f39635ce81a9170f` with `referenceDependency: Apple-only`.

## Visual findings

- **#0, four views:** The unchanged Kamata shared start and the first southeast bend remain continuous. Candidate display and smoothing stay on the Airport corridor through Kojiya; there is no short cap, backwards hook, or visible join at the fitted controls.
- **#1, four views:** The full Kojiya→Otorii arc is smooth and stays with the uncomplicated own railway band. The rejected upper building/frame-edge hump does not reappear in either display or smooth output. The Otorii seam has the same forward direction on both adjacent views.
- **#2, three views:** Otorii→Anamori-Inari remains a single continuous path. The two station-frame seams do not create a V, doubled segment, or return toward the separately shown physical source.
- **#3, four views:** The Anamori→Tenkūbashi approach crosses the river/interchange on the diagonal Keikyu identity. It does not turn onto the perpendicular Monorail geometry. Display and smoothing preserve the approach direction into the Tenkūbashi frame.
- **#4, five views:** Tenkūbashi→Terminal 3 follows the own Keikyu guide through every view. The middle curve has no new wiggle or chord, and the T3 shared endpoint continues directly into interval 5 without a visible splice or artificial terminal cap.
- **#5, seven views:** The candidate preserves V5's varying runway arc through the faint but continuous labelled Keikyu guide; it does not fall back to the old south source or use a constant offset. Display and smooth panels agree in curve direction through the whole span. The last two views enter the diagonal Terminal 1·2 frame and end near its longitudinal middle. The north–south Monorail boxes and guide remain visually separate.

## Evidence limits

Several underground airport views contain labels or translucent station polygons over the rail glyph. Their continuity is supported by overlapping adjacent views, but this receipt does not claim surveyed track or platform accuracy. The source/physical line visible in the panels is intentionally distinct and is not an accepted cartographic target. This review is limited to the Third Inspector; Main behavior and production lane/family behavior remain Root's separate checks.
