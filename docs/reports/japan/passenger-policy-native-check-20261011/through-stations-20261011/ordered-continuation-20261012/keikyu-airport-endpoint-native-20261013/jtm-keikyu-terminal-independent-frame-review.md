# Keikyu airport terminal independent frame review

Read-only review of `terminal-z18-before/apple-map-extraction/basemap.png` (999×654), `analysis.json`, and the saved Main terminal ON/OFF pair. No source or candidate geometry was changed.

## Terminal 1·2 frame

The own Keikyu station frame is the broad southwest–northeast translucent rectangle labelled by the `Keikyu Kuko Line`, not either narrow north–south `Tokyo Monorail Haneda Line` frame. The Keikyu rectangle is bounded approximately by these raw extraction pixels:

- northwest long-edge end: `(258, 443)`
- northeast long-edge end: `(498, 305)`
- southeast long-edge end: `(590, 368)`
- southwest long-edge end: `(350, 506)`

The resulting longitudinal axis is:

- southwest endpoint: `(304, 474.5)` → `[139.7848083, 35.5490752]`
- northeast endpoint: `(544, 336.5)` → `[139.7860957, 35.5496775]`
- midpoint: `(424, 405.5)` → `[139.7854520, 35.5493764]`
- visible frame-axis length: about `134.4 m`

The current constructed station coordinate `[139.785857, 35.549719]` maps to `(499.5, 327)`. It is about `52.9 m` from the frame midpoint and about `22.1 m` from the northeast longitudinal endpoint. The Main ON/OFF pair independently shows the cyan endpoint dot at that northeast end of the diagonal frame. This supports the root finding that the current dot is not longitudinally centred.

Pixel picking uncertainty is approximately ±4 px (about ±2 m) on the unobscured southwest and northwest edges and ±8–12 px (about ±4–6 m) on the northeast/southeast end, where road labels and fills obscure parts of the outline. The larger semantic warning remains: this is Apple station-frame cartography, not surveyed underground rail or a platform-centre certificate.

## Automatic candidates and monorail exclusion

The two `analysis.json` platform candidates are not the Keikyu longitudinal frame:

- candidate 1 axis `(285.0, 416.9)`→`(343.6, 509.8)` is steep northwest–southeast, aligned with the monorail-side structures;
- candidate 2 axis `(384.1, 572.9)`→`(400.4, 603.2)` is also steep and south of the Keikyu frame.

Both candidates already report `unresolved` / `no_supported_parallel_rail_at_midpoint`; neither should be used as the Terminal 1·2 centre.

## Terminal 3 distinction

The saved Terminal 3 Main pair is a separate frame problem. Its own Keikyu frame is the more east–west translucent rectangle labelled `Keikyu Kuko Line`; the adjacent narrow parallel `Tokyo Monorail Haneda Line` rails/frame must be excluded. The current cyan `#4/#5` route is visibly south of the labelled Keikyu guide/frame. The Terminal 1·2 diagonal midpoint above must not be propagated to Terminal 3, and no connecting fake bend or global smoothing follows from this review. Exact Terminal 3 coordinates remain pending its separate raw z18 extraction.
