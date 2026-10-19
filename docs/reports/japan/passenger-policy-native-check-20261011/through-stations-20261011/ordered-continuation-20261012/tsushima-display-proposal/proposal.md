# 津島線 #5 河橋東側 display-only proposal

Status: **proposal only**. This does not change the N02 physical geometry, station rows, IDs, kilometres, route topology, native parts, or production resources.

## Evidence scope

The evidence is the complete five-view `jp-名古屋鉄道-津島線#5` baseline capture in each of the Primary, Secondary, and Third Inspectors: 15 `basemap.png` images and their 15 `view.json` files under `tsushima-complete-native/*/captures/002592`. All three apps use the same immutable map rectangles for point ordinals 0–4. The replacement window is visible in views 0–2, its west continuation is visible in view 3, and view 4 covers the remaining approach to 藤浪. The individual paths and SHA-256 receipts are frozen in `evidence-receipts.json`.

The identified reference is the labelled Meitetsu Tsushima Line railway: a continuous paired rail glyph on the same diagonal on both banks of the Nikko/Miyakogawa channel. Identity is established by its labelled continuity, paired railway strokes, bridge crossing, and connection to the same interval on both sides. The nearby grey arterial roads, bridge approaches, building outlines, and thin blue drainage lines were not used as rail evidence. Colour alone was not used to select the path.

## Observed defect and bounded window

The current physical/source sequence contains the N02 feature 20651 points:

```text
[136.74725, 35.19365]
[136.74706, 35.19380]
[136.74693, 35.19374]
```

They create a visible southward notch and return while the own Meitetsu double-rail glyph remains continuous through the bridge. Relative to the straight own-glyph span between the two surrounding literal source guards, the three points are approximately 8.5 m, 14.0 m, and 12.9 m off the span.

The proposal replaces the complete source index `2...6` window, approximately 311.6 m, rather than deleting only the three bad points:

- East literal guard, source index 2: `[136.74802, 35.19403]`
- West literal guard, source index 6: `[136.74492, 35.19284]`
- Nine candidate controls sample the MapKit-map-space segment at eighth intervals. Both guards remain byte-exact.
- Source indexes `0...1` and `7...17`, both stations, and all physical data remain exact.

The candidate has 22 display coordinates versus 18 physical coordinates. Its complete coordinate array and the replacement controls are in `candidate.json` and `candidate.geojson`.

## Pixel-to-coordinate transform

Each view is 1024 × 768 points and has an 8192 × 6144 `MKMapRect`. For a displayed pixel `(px, py)`:

```text
mapX = rect.x + px / 1024 * rect.width
mapY = rect.y + py / 768  * rect.height
longitude = mapX / 268435456 * 360 - 180
latitude  = atan(sinh(pi * (1 - 2 * mapY / 268435456))) * 180 / pi
```

The inverse transform was used for reprojection. In point-2, the retained guards project to `(908.09, 189.35)` and `(619.15, 325.07)`; in point-1 they project to `(594.88, 351.39)` and `(305.94, 487.12)`; in point-0 they project to `(292.50, 522.58)` and `(3.56, 658.30)`. These agree with the own paired railway through the overlap. Red in the reprojections is the old source; orange is the proposed display path; blue dots mark candidate controls.

## Review result and limits

Static reprojection across all three captures removes the unsupported notch and stays on the same labelled railway through the full bridge window. The joins at both guards are continuous; the candidate changes heading by about 8.4° at the east guard and 3.6° at the west guard, matching the visible broad approach rather than adding a return or a short cap.

The centre of the paired glyph is readable to about ±2.5 pixels in the label-free sections. At the recorded 0.9727 m/point scale, this is approximately ±2.4 m lateral cartographic uncertainty. This is a display-cartography proposal, not surveyed track geometry. Native grooming/smoothing and product rendering have not been replayed, so this file does not accept the repair for production.

