# 津島線 display proposal V4 review

Status: **PROPOSAL ONLY — production source not applied.**

## Scope and evidence actually viewed

- Candidate intervals: #1–#6. Interval #0 is intentionally left for the separately owned 須ヶ口→甚目寺 integration.
- Baseline native evidence opened before fitting: all three Inspector captures for #1–#3, 60 viewpoints / 180 basemap-display-smooth panels; detailed receipt: `interval1-3-three-app-review.md`.
- Candidate reprojections opened after fitting: all 111 images under `reprojections/{primary,secondary,third}` (#1 7, #2 6, #3 7, #4 6, #5 5, #6 6 per Inspector; 37 per Inspector). These are direct overlays on each original basemap, not app runtime output.
- Station-focus z18 raws opened: 甚目寺, 七宝, 木田, 青塚, 勝幡, 藤浪, 津島. Picks use the longitudinal midpoint of the narrow own Meitetsu platform faces, projected normally to the own rail guide. Wide blue station/building casings were not used as centroids.

## Candidate judgment

The #1–#6 proposal is suitable for candidate-native replay. The orange path follows the same shallow curves as the labelled Meitetsu 津島線 guide in all 111 baseline windows. It removes the repeated south/lower displacement visible in #1–#4, retains the reviewed bridge curve in #5, and preserves the continuing southbound curve through #6. No new cap, zero edge, reversal, hook, or straight chord across a visible curve was found.

Station aliases are shared literally between adjacent intervals. `station-frame-picks.json` records both narrow platform faces, their averaged longitudinal endpoints, longitudinal midpoint, normal projection to the own rail, original dot and uncertainty. The seven full-resolution annotated originals are under `station-frame-annotations/` (yellow faces, white axis/midpoint, red old dot, green proposed rail point).

The reproducible z18 pass changes 甚目寺, 七宝, 木田, 青塚 and 勝幡 from their old guards. It also corrects the earlier draft conclusion at 藤浪: the complete narrow platform faces run approximately `(321,478)→(552,237)` and `(338,502)→(575,254)`; their axis midpoint is `(446.5,367.75)` and the own-rail projection is `(447,369)`, yielding `[136.73863336805346,35.18864586718895]`. The old source-centered pixel `(499.5,327)` and V3 normal-only displacement do not represent the platform’s longitudinal midpoint.

## Remaining limits / warnings

- Station picks are cartographic readings with approximately ±4 px uncertainty (±6 px at the longer diagonal 勝幡/藤浪 faces); the JSON preserves those bounds rather than presenting the coordinates as survey measurements.
- 津島 `005420` remains exactly `[136.73107,35.17803]`. It is inside the shared north-south station band, but labels/building fill obscure the complete longitudinal platform face. The evidence does not justify moving it or creating a separate 尾西線 alias.
- Reprojection review establishes Apple cartographic agreement only. It does not establish surveyed track position or native smoothing behavior. Three-Inspector candidate replay and Main remain pending.
- Interval #0 and the exact 須ヶ口→甚目寺 seam are outside this artifact and must be integrated with the separately reviewed #0 candidate before any whole-line acceptance.
