# Tsushima Line intervals 1–3 — three-Inspector static review

## Receipt

- Opened every basemap/display/smooth panel for current captures `002588` (#1, 7 views), `002589` (#2, 6 views), and `002590` (#3, 7 views) under each of `primary`, `secondary`, and `third`.
- Total: 60 viewpoints / 180 panels. All identify `jp-名古屋鉄道-津島線`, dependency `3f1df5d5cffad0f8f9b4b47bc9d20a5724592ecf6c2fe55eaad2c02d03a1f59c`, and visibly loaded Apple basemaps.
- Scope: #1 甚目寺 (`005368`) → 七宝 (`005370`); #2 七宝 → 木田 (`005372`); #3 木田 → 青塚 (`005355`).

## Result

**The three complete intervals require cartographic refit; this is not only a station-alias issue.** The same concrete normal displacement repeats in all three Inspectors. At label-free portions, cyan display and magenta smooth lie on the south/lower side of the thin own Meitetsu Tsushima rail rather than its centre:

- #1 view 4 (`002588/000004`): across the central straight east of the station band, the overlay runs visibly below the unique blue rail centre; the residual is several pixels and continuous across the frame rather than a one-point spike.
- #2 view 3 (`002589/000003`): through the label-free straight around the vertical road/canal crossing, display/smooth stay south of the own blue rail. The line is continuous, but continuity does not make the locus correct.
- #3 view 3 (`002590/000003`): over the long shallow diagonal near the north–south road crossing, the overlay is again visibly south of the own rail for most of the frame. The same relationship continues through adjacent views 2–5 while the Apple rail bends gradually.

No isolated gap, cap, reversal, or sharp smoothing cusp appears in #1–#3. The defect is a coherent but locally varying normal residual, so a constant translation is not supported. A candidate should trace the unique own rail through all 20 viewpoints, retain the observed shallow curves, and use valid label-free guards on both sides of each station.

## Station guards

- **甚目寺 / #1 east end of #0, west end of #1:** current source is centred at the camera but the own rail is visibly north of it; this agrees with the separate z18 observation `old y327` versus own black rail around `y315`. The station alias and both adjacent intervals must share one exact reviewed tuple. The broad blue station fill is not a midpoint measurement.
- **七宝 / #1–#2 seam:** both intervals reach the same station area without a gap, but the source path sits on the lower side of the own rail/platform rendering. The complete narrow platform longitudinal ends are not defensible at z17. Keep midpoint selection pending the dedicated z18 station raw, then use the exact same tuple in #1, #2, and the display alias.
- **木田 / #2–#3 seam:** continuity is present, but display/smooth approach on the south side of the own rail and the broad blue station shape cannot establish the narrow own platform midpoint. The #2/#3 arrays and alias must be updated together once z18 frame ends are identified.
- **青塚 / #3 west end, #4 east end:** #3 reaches the correct own corridor and shows no short-tail hook. The current point appears within the broad station area, but these captures do not prove its narrow-platform longitudinal midpoint. Do not preserve it as an accepted guard or move it from the broad fill alone; bind it to the dedicated station raw and update #3/#4 together if changed.

This review supports expanding the candidate to all seven Tsushima intervals. It does not provide final midpoint coordinates and does not accept any endpoint merely because the line remains continuous.
