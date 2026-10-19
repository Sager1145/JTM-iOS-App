# Secondary native visual review — Nagoya Main Line #16–20 related scope

## Receipt

- Static review only. I opened every `basemap.png`, `display.png`, and `smooth.png` in these five capture scopes: **17 viewpoints / 51 panels**.
- `002451`: `jp-名古屋鉄道-名古屋本線#16`, 新清洲 (`005323`) → 丸ノ内 (`005337`), 4 viewpoints / 12 panels.
- `002452`: #17, 丸ノ内 (`005337`) → 須ヶ口 (`005352`), 3 viewpoints / 9 panels.
- `002453`: #18, 須ヶ口 (`005352`) → 新川橋 (`005374`), 4 viewpoints / 12 panels.
- `002454`: #19, 新川橋 (`005374`) → 二ツ杁 (`005377`), 3 viewpoints / 9 panels.
- `002456`: #20, 二ツ杁 (`005377`) → 西枇杷島 (`005376`), 3 viewpoints / 9 panels.
- Every `view.json` identifies the stated line and interval and carries `wholeLineRenderDependency` `a4deaa92cf35b09b220f3a11390084b246901bc22d1b8d1ab9a6605caf34f77f`. All 17 basemaps visibly loaded. Counts are the coverage receipt, not the alignment judgment.

## Finding

**REPAIR PENDING for station placement; the five interval bodies show no additional concrete gap, cap, shortcut, reversal, or cross-corridor jump.** Cyan display and magenta smooth remain on the same Meitetsu Nagoya Main Line corridor through the diagonal north approach, Sukaguchi yard throat, Shinkawa bridge, the east-west straight, and the Nishibiwajima approach. This bounded evidence does not certify Apple cartography as surveyed track position.

### #16 — 新清洲 → 丸ノ内

- `002451/000000`: the line starts in the correct multi-track 新清洲 corridor and leaves southeast on the continuous own diagonal alignment. The broad station/yard fill and several tracks do not expose a defensible complete own platform face; 新清洲 endpoint midpoint remains **WARNING**, not a reason to snap.
- `000001` and `000002`: display and smooth follow the same diagonal own rail across the river and intervening body. No visible chord across a bend, lateral excursion, or smoothing hook.
- `000003`: the approach remains continuous into 丸ノ内, but the endpoint issue seen from the next interval remains. The current point is near/beyond the southeast end of the visible own diagonal station frame rather than its longitudinal middle.

### #17 — 丸ノ内 → 須ヶ口

- `002452/000000`: 丸ノ内 source/display point is approximately `(512,384)`. The visible own diagonal station frame is approximately `(477,280)` → `(529,376)`, with midpoint near `(503,328)`. The current point is roughly 57 px from that midpoint and is visibly at the southeast frame end. The previously estimated coordinate `[136.84204344,35.20469593]` remains proposal evidence only.
- `000001`: body follows the visible own diagonal rail with no concrete kink.
- `000002`: the shared 須ヶ口 point enters the correct large Meitetsu complex, but converging Nagoya Main/Tsushima tracks obscure the exact line-owned platform face. Corridor identity is supported; longitudinal midpoint is **WARNING**.

### #18 — 須ヶ口 → 新川橋

- `002453/000000`: same shared 須ヶ口 ambiguity as #17; no separate discontinuity between the two interval renders.
- `000001` and `000002`: continuous own-line exit from the yard, river approach and bridge; no visible cap or wrong-direction fold.
- `000003`: 新川橋 lies on the correct curved corridor. Labels and overlapping cartography do not expose the complete narrow face, so this view cannot certify the current endpoint as its longitudinal midpoint.

### #19 — 新川橋 → 二ツ杁

- `002454/000000`: the west guard continues from the correct bridge/curve corridor; the 新川橋 frame limitation above remains.
- `000001`: display and smooth follow the shallow east-west own railway guide through the complete body. No straightening across a visible curve or off-corridor spur is present.
- `000002`: the line reaches the correct 二ツ杁 station corridor continuously. The visible station fill is label-obscured and does not provide two defensible complete longitudinal bounds in this z17 frame; midpoint remains **WARNING** pending the clearer station raw.

### #20 — 二ツ杁 → 西枇杷島

- `002456/000000`: same 二ツ杁 guard and continuous eastward departure as #19; no seam hook between intervals.
- `000001`: the shallow curve through the multi-line crossing area remains on the named Nagoya Main Line guide. Smooth does not jump to the north-south neighboring line.
- `000002`: the terminal side remains continuous into the 西枇杷島 corridor. Dense adjacent tracks and station fill prevent a defensible own-face midpoint judgment from this view. This is a station-placement **WARNING**, not a visible body failure.

## Scope limit

This receipt supports reuse of the five body paths while station aliases are resolved from clearer own-frame evidence. It does not validate production Main behavior, the Tsushima branch geometry, or any station coordinate outside these five Nagoya Main Line intervals.
