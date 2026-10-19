# 津島線 #5 display-only proposal V2

Status: **proposal only**. No physical N02 geometry, route topology, IDs, kilometres, production resources, native parts, or source package are changed.

## Correction from V1

V1 is rejected because its east guard was not on the own railway. Full-resolution point-2 sampling gives the following paired-rail casing edges and centres for the labelled Meitetsu Tsushima Line:

| x | upper edge y | centre y | lower edge y | old source y | old residual |
|---:|---:|---:|---:|---:|---:|
| 619 | 318 | 323 | 327 | 325.2 | +2.2 px south |
| 727 | 259 | 264 | 269 | 266.0 | +2.0 px south |
| 799 | 219 | 224 | 229 | 226.5 | +2.5 px south |
| 837 | 198 | 203 | 208 | 232.3 | +29.3 px south |
| 871 | 179 | 184 | 189 | 211.7 | +27.7 px south |
| 908 | 160 | 165 | 170 | 189.4 | +24.4 px south |

The `x=619,727` samples are label-free. At `x=799,837`, the dark paired-rail centre is separated from the cyan drainage feature below it. The `x=871,908` columns cross label glyphs, so their centres are constrained by the adjacent label-free railway and carry larger uncertainty. Identity comes from the labelled, paired railway continuing across the river and into the same interval on both banks; no road, building border, or drainage colour is used as a substitute.

The earlier ±2.4 m claim conflicted with the image because it was an uncertainty estimate around a misidentified southern corridor edge. Depending on which casing edge is compared, the visible error is roughly 15–29 px; centre-to-centre samples above show 24–29 px, about 23–28 m at this viewport scale. V1's uncertainty is invalid.

## Expanded owning window

No literal east rail-locus guard survives the full-resolution check: source points 0 and 1 are also about 8 px south of the own rail, and source index 2 is 24 px south. V2 therefore expands from 勝幡 through source index 8 instead of creating a return to a bad guard.

- The new 勝幡 display endpoint is `[136.75033208465572, 35.1953063726649]`, the own-line rail/frame centre at point-0 pixel `(508,377)`. It is 7.87 m from the unchanged physical station coordinate.
- The bridge controls are derived directly from point-2 pixels `(908,165)`, `(871,184)`, `(837,203)`, `(799,224)`, `(727,264)`, and `(619,323)`.
- A further own-rail control at point-2 `(452,415)` carries the fit westward.
- Source index 8 `[136.74262,35.1918]` is the first exact literal west guard. Candidate index 9 and every coordinate after it equal source indexes 8–17 byte-for-byte.
- The largest control turn inside the replaced window is 2.43°. The join into the exact west guard is 5.01°; the following 8.10° bend belongs to the unchanged visible source curve.

`candidate-v2.json` contains the complete 19-point display interval, the provisional 勝幡 display alias, all pixel anchors, and the exact unchanged suffix. `candidate-v2.geojson` contains the same complete candidate and replacement controls.

## Transform and complete interval review

The same MapKit transform documented in V1 is used:

```text
mapX = rect.x + px / 1024 * rect.width
mapY = rect.y + py / 768  * rect.height
longitude = mapX / 268435456 * 360 - 180
latitude  = atan(sinh(pi * (1 - 2 * mapY / 268435456))) * 180 / pi
```

All 15 original basemaps and `view.json` records were reused. Views 0–2 independently cover the changed eastern approach and bridge, view 3 covers the exact-suffix join and following bend, and view 4 covers the unchanged 藤浪 tail and endpoint. Reprojections for Primary, Secondary, and Third show the V2 orange path on the own railway through the bridge and no new return, cap, or secondary excursion. Red preserves the rejected physical/source path for comparison.

The label-free bridge centre is estimated at ±1.5 px (about ±1.5 m). Label-crossed controls use ±3 px, and the 勝幡 station/frame endpoint uses ±5 px because the translucent frame and label overlap. These are cartographic uncertainties, not surveyed rail precision. The moved 勝幡 alias and the rebuilt native smoothing remain unaccepted until actual native and Main replay.

