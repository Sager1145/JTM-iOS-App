# Matsumoto secondary Inspector candidate review receipt

Reviewed: 2026-10-13
Evidence root: `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/matsumoto-direction-review-20261013/secondary-complete-native-candidate`

## Coverage and dependencies

Every saved native panel was opened: 47 viewpoints × basemap/display/smooth = 141 PNG panels, all 1024×768. Every panel contained a rendered Apple basemap; no blank/loading-grid or low-variance capture was found.

- `jp-アルピコ交通-上高地線#0`: 3 viewpoints (`captures/000333/000000..000002`), whole-line render dependency `8df7754de8d13ebfc7c19e829414021d31425500017b60c0492804cc5882e200`.
- `jp-東日本旅客鉄道-大糸線#30`: 7 viewpoints (`captures/004875/000000..000006`), dependency `c1631a464880071cc6b7b62051ba74b2db38d621a00d3be2ec6727dddf5fb496`.
- `jp-東日本旅客鉄道-大糸線#31`: 3 viewpoints (`captures/004876/000000..000002`), same dependency `c1631a464880071cc6b7b62051ba74b2db38d621a00d3be2ec6727dddf5fb496`.
- `jp-東日本旅客鉄道-篠ノ井線#4`: 8 viewpoints (`captures/005681/000000..000007`), dependency `71d120d8eab02590363310ce6d98a944119f077d049ca8f76e5f82d0cb4e1a5c`.
- `jp-東日本旅客鉄道-篠ノ井線#5`: 26 viewpoints (`captures/005682/000000..000025`), same dependency `71d120d8eab02590363310ce6d98a944119f077d049ca8f76e5f82d0cb4e1a5c`.

## Visual result

ACCEPT for this secondary Inspector candidate scope.

- Oito #31: in all three views, the display and smoothed line remain on the named Oito approach. At `004876/000002` the station tail enters the northwestern JR bay and ends at the selected platform-frame midpoint. The former diagonal J-to-old-dot cross-platform tail, acute return, hook, and detached cap are absent.
- Oito #30/#31 seam: `004875/000005..000006` through `004876/000000..000001` remains continuous, with no visible gap, overlap reversal, or new kink at the interval seam.
- Shinonoi #4/#5: all 34 views preserve a continuous south approach, Matsumoto station passage, north departure and long Tazawa-side continuation. No new station-area sharp return, broken join, or wrong branch transfer is visible. The Matsumoto physical fork context remains separate from the Oito display endpoint.
- Kamikochi #0: all three views keep the Alpico approach independent on its own southwest curve/platform side; it is not welded to the repaired Oito endpoint.
- Endpoints and short tails for all five complete scopes were visible in their assigned views and show no new cap, foldback, or discontinuity.

Limit: several rural Shinonoi #5 frames use a faint/simplified Apple railway depiction, so those panels support visible continuity and absence of a gross road/river excursion, not surveyed metre precision. This receipt covers the secondary Inspector rasters only; it does not substitute for the separate primary/third Inspector or Main ON/OFF evidence.
