# 名古屋本線 #16–#20 display proposal

Status: **PROPOSAL ONLY — not accepted and not production-applicable.**

## Scope and construction

This proposal contains five complete display intervals of `jp-名古屋鉄道-名古屋本線`: #16 新清洲→丸ノ内, #17 丸ノ内→須ヶ口, #18 須ヶ口→新川橋, #19 新川橋→二ツ杁 and #20 二ツ杁→西枇杷島. Physical coordinates, station IDs, kilometres, segments and topology remain unchanged.

The candidate uses the three independently reviewed own-frame midpoint projections:

- 丸ノ内 `005337`: pixel `(474,231)`, `[136.84200320734033,35.204625793777495]`.
- 新川橋 `005374`: pixel `(454,269)`, `[136.85237591897993,35.19550425786567]`.
- 二ツ杁 `005377`: pixel `(482,309)`, `[136.8596121226845,35.19473890827177]`.

新清洲 and 須ヶ口 retain their source aliases with explicit WARNING because the available multi-track views do not prove a unique line-owned platform face. No wide blue casing centroid was substituted.

The five source bodies were retained after the complete 17-view / 51-panel Secondary review found them on the same own black-rail corridor. This is deliberately not a constant translation: only the supported station endpoints change, while each body keeps its observed shallow curvature and original controls. In particular, #19's previously measured smooth residual is only 1.78 m and does not justify shifting its complete body. `controls.json` records the source arrays and the exact endpoint operation for replay.

## Shared-stem constraint

The final three coordinates of Main #17 remain byte-exact and equal the first three source coordinates of Tsushima #0 in reverse order:

```text
Main #17 tail: [136.84472,35.19948] → [136.84497,35.19937] → [136.845755,35.19893]
Tsushima #0:   [136.845755,35.19893] → [136.84497,35.19937] → [136.84472,35.19948]
```

This preserves the existing display inventory relation pending the separate Tsushima #0 integration. It does not establish that the physical source vertices are Apple-aligned, and it does not add a branch lead-in, follow row or new graph edge.

## Reprojection receipt

All 17 candidate reprojections under `reprojections/interval-*` were opened at their saved resolution:

- #16: 4 views
- #17: 3 views
- #18: 4 views
- #19: 3 views
- #20: 3 views

The candidate remains continuous on the named corridor, including the #16/#17 丸ノ内 seam, #18/#19 新川橋 seam and #19/#20 二ツ杁 seam. No new cap, zero edge, reverse fold, hook or chord across a visible bend was found. The orange path does not jump to adjacent north-south lines at 西枇杷島.

These are static basemap reprojections. Native smoothing, production Main rendering and the unresolved 新清洲/須ヶ口 station faces remain pending; this proposal must not be described as accepted or surveyed.
