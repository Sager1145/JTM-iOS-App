# Miyazu Line: bounded original pixel review and missing request

2026-10-18. Exact own line jp-WILLER　TRAINS-宮津線 (U+3000). Viewed11 retained completed ORIGINAL basemap.png+smooth.png pairs (22 files) with functions.view_image. No pixels altered. Exact absolute paths, viewpoints, old named identity plans and per-view observations are in bounded-viewed-originals.json. This is11 of237 retained pairs, not full-line pixel acceptance.

## Concrete visual leads

Strongest: interval9 与謝野→京丹後大宮, decoded4 [135.12226,35.54194], before[135.12334,35.54232], after[135.12221,35.54194]. In captures/000040/000001 the red line has a shallow southward dip/flat trough near the Shimoyamada map label where the blue railway curves gently and monotonically. This is a concrete false-support candidate visible in the originals. Its heading23.38° includes a very short following edge, so do not delete a point without reviewing the complete local source window and explicit own route. No replacement geometry is established here.

Secondary leads: interval14 小天橋→かぶと山 decoded27 [134.9255,35.61907] (captures/000029/000004) has a polygonal red shoulder near the route178 crossing; interval16 久美浜→コウノトリの郷 decoded17 [134.88508,35.59802] (000031/000003) and decoded30 [134.88496,35.59506] (000031/000004) show angular red shoulders against smoother blue curves. The river bridge curve near decoded7 [134.891,35.60144] (000031/000001) also has a southeast red chord/offset. These are source-review leads, not confirmed topological errors or accepted repair fragments. Preserve the real broad S and river/bridge curvature.

## Real curves and unresolved coast

- Interval11 峰山→網野,000026/000001: the hill curve is real; no isolated false V confirmed.
- Interval11,000026/000010: modest red inner shoulder/chord at the broad compound curve near Ishimaru. Preserve the compound turn; secondary alignment lead only.
- Interval14,000029/000003: the other half of the S corroborates the genuine large curve. Do not flatten it because individual source supports are angular.
- Interval4 丹後由良→栗田,000035/000006: coastal blue geometry contains both an outer curve and a straight chord/alternative. The red generalized curve differs, but a standard-map frame does not establish which physical alignment is the own passenger route. No coast repair is justified without explicit own source identity/engineering context; no nearest-blue or nearest-road selection.

## Miyazu junction and station limits

Own interval5 栗田→宮津 endpoint frame000036/000013 shows the Miyazu broad blue platform group and red approach without an obvious hook. It does not fully show the protected Miyazu/Miyafuku physical connection [135.195,35.53084], which is603m southwest from the station display point and lies outside/clipped at the frame boundary. The missing own interval6 宮津→天橋立 is still necessary for that fork/adjacent approach. No station-cap, pair midpoint, or physical junction acceptance follows from the broad platform fill.

Amino seam frame interval12,000027/000000 shows the real long station curve without an isolated seam hook; exact platform ends/centre remain unresolved from broad shading.

## Prepared missing-only request

/private/tmp/jtm-miyazu-missing-20261018/request.json uses the existing schemaVersion1 alignment capture request, current app/public/rail/jp-2025.json input, exact canonical own line ID, intervals[3,6,15] only, z17/light/standard1600×1200 basemap+smooth. It excludes every completed interval and therefore does not duplicate the237 valid retained completed views. The legacy missing count is28; the fresh consumer's sampling can produce a different view count. prepared-request-source.json freezes the selected current own station rows/compact intervals and preceding seam controls for review.

The request was prepared only: not submitted or run. No app/native launch, capture, tests, build, production/code changes or source geometry edits. IR evidence unchanged.
