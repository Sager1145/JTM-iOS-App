# Johoku V1 rejected-window pixel review

Reviewed 2026-10-13. I opened the ten full-resolution V1 raw reprojections for intervals 2 (views 0–2), 5 (views 0–1), 6 (views 0–1), and 7 (views 0–2). Orange is the V1 proposal and red is the prior source projection. This note records independent pixel evidence for a later candidate; it does not accept V1 or select geographic coordinates.

## Interval 2: reject the middle bow

The black Johoku band is a single continuous shallow curve in all three views. V1 leaves it on the south side through the middle and rejoins only toward the right endpoint. This is not a switch, second track, label-gap detour, or station frame.

- View 0: the own band is continuous from the left edge through the bend near `(430,320)` and into the near-horizontal right section near `(565,366)`. Orange separates below it before the bend and rejoins near the right section.
- View 1 gives the cleanest cross-check. Label-free/dark-band centres are approximately `(550,324)`, `(650,351)`, `(700,368)`, `(750,383)`, `(850,413)`, and `(900,428)`, each ±2–3 px. Orange forms a visibly deeper south bow between roughly `x=560…830`; the black band and red projection retain the shallower curve.
- View 2 repeats the same geometry. Useful band centres are approximately `(600,343)`, `(700,352)`, `(800,376)`, and `(900,407)`, ±2–3 px. The orange excursion is again south of the sole rail before converging at the right.

V2 should interpolate along these band centres across the label interruptions. It should not chase the grey `Iyotetsu Loop Line` letters or preserve the V1 south control point.

## Interval 5: preserve the shallow rail hump

The own black line has a small but visible northward crest; V1's straighter orange segment cuts across its inside. There is no competing tram line in this window.

- View 0 label-free band centres are approximately `(75,310)`, `(125,304)`, `(175,300)`, `(225,298)`, `(275,294)`, `(350,290)`, `(375,289)`, and `(425,300)`, generally ±2 px. They describe the shallow crest and return. Text over `x≈200…330` must be bridged from the clean anchors on both sides, not treated as rail pixels.
- View 1 independently shows the same crest at approximately `(550,321)`, `(600,316)`, `(700,307)`, `(850,297)`, `(900,298)`, and `(950,310)`, ±2–3 px. V1 is closest at the ends but flattens the middle.

The correction can be small, but it needs enough intermediate controls to retain that crest instead of a straight endpoint chord.

## Intervals 6/7: Kayamachi frame and seam

Views 6-1 and 7-0 are the same Kayamachi station context from the two adjacent intervals. The sole own north–south Johoku rail passes through a clear translucent station body. The usable longitudinal body runs approximately from `(496,417)` to `(515,491)` along the rail, giving a representative midpoint near `(506,454)`, with about ±4 px uncertainty at the ends. This frame is label-free and distinct from the west/southwest Takahama railway.

V1 leaves the shared interval endpoint near `(499,327)`, about 127 px north along the same rail and outside the clear station body. Both interval 6's end and interval 7's start must use one exact line-scoped Kayamachi tuple derived from the frame midpoint; adding a return segment to the old point would create a hook.

- Interval 6 view 0 confirms that the preceding east–west curve joins the same north–south rail continuously. Its V1 orange curve also departs from the visible black/red locus on the west side, so the revised join should be retapered rather than connected by a short diagonal.
- Interval 7 view 0 supplies the clearest station-frame evidence above.
- Interval 7 views 1–2 show the continuation into the eastern side of the Furumachi rail complex. Apart from the rejected Kayamachi start, the proposal follows the entering Johoku identity; these two views do not justify moving onto a central or western Takahama track. Furumachi's exact own-face representative remains governed by the separate full-line review.

## Decision boundary

V1 remains rejected for the interval 2 false bow, interval 5 flattened crest, and the shared interval 6/7 Kayamachi endpoint outside its own station frame. The anchors above are suitable for checking V2 reprojections. They are pixel observations from Apple cartography, not surveyed positions, and they do not establish native or Main acceptance.
