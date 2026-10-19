# 名古屋本線 #16–#20 full-body display proposal V2

Status: **PROPOSAL ONLY / NOT ACCEPTED / NOT SOURCE-APPLICABLE.** V1 is retained separately as rejected endpoint-only process evidence.

## Construction

Every source vertex for #16–#20 was projected through the exact `mapRect` in each containing original Secondary basemap. The candidate controls move along the local line normal to the visible own black/paired railway centre. `controls.json` records the complete source arrays and per-vertex z17 pixel offsets, so the WGS output is reproducible (`8` MapKit map points per z17 pixel). Colored display/smooth/package strokes were not used as target geometry.

The offsets vary by local evidence rather than applying a global translation:

- #16: `0,2,2,1,1,0,0,1,2,-1,-3,0` px.
- #17: `-1,0,2,-2,-5,-4`, followed by the three frozen shared-stem vertices.
- #18: `-4,-4,-4,-6,-7,-8,-9` px.
- #19: `-10,-10,-10,-9,-9,-8,-8` px. This corrects the visible full-body south displacement; the previous 1.78 m smooth diagnostic is not used as evidence.
- #20: `-9,-9,-9,-8,-7,-6,-3,0` px. Root's label-free checks are recorded literally in `controls.json`, including view 0 x100…500 and views 1–2.

Three reviewed station aliases are used at both adjacent intervals: 丸ノ内, 新川橋 and 二ツ杁. 新清洲 and 須ヶ口 remain unchanged with WARNING because their own platform faces are unresolved.

## Static reprojection review

All 17 original-basemap reprojections were opened after V2 generation (#16 4, #17 3, #18 4, #19 3, #20 3). The orange proposal follows the own railway through the diagonal #16/#17 corridor, bridge approach, the complete #19 east-west body, and the #20 shallow rise. No new cap, zero-length edge, U-turn, hook, cross-line jump or curve-cutting chord was found.

## Shared-stem limitation

Main #17's final three source vertices remain the exact reverse of Tsushima #0's first three. This preserves the known inventory relation while the Sukaguchi face and Tsushima #0 final proposal are unresolved. Those physical/source vertices are **not claimed Apple-aligned**. No branch lead-in, follow row, station-to-switch connector or topology change is introduced here.

The Matsumoto fit worker was no longer a live collaboration target when coordination was attempted, so this proposal deliberately leaves the shared triple unchanged and marked pending rather than inventing a replacement.
