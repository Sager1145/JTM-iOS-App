# Meitetsu Tsushima Line complete-scope preparation

## Identity and frozen inputs

- Existing continuation order: ordinal 18, `jp-名古屋鉄道-津島線` / 名古屋鉄道 津島線.
- Current package: `app/public/rail/jp-2025.json`, SHA-256 `a128bf177b2a13b0dd27e9520c04bc96691a0972bfdbdb9bfb939d85d2391942`, package version `2025.5.2`.
- The line has 8 ordered stations and 7 physical segments. `railwayIdentity` equals the line ID. There are no line-level display-coordinate, display-interval, or display-station overrides.
- Current native cache: `display-lanes.json`, SHA-256 `63a39f601f6e63cf068123c0298d3912ecc58a0cbed3112478b1cc862235d7e4`. It contains one part spanning intervals 0–6, 111 points, 11,767.9 m, with no classification/anchors. No line-owned measured lane, follow, family window, or released interval exists.
- Existing scope plan: `ios/refactor-parallel/alignment-passenger-local-recheck-20261010.json`, SHA-256 `4fc732595d464ac561ffa9eb4d44a4520c2e11d5bde72ac06900a97cfd579921`. Its seven records total 44 planned viewpoints. These are pending plan inputs, not native or Main acceptance.

## Complete interval checklist

| # | From | To | km | source points | planned views |
|---:|---|---|---:|---:|---:|
| 0 | 005352 須ヶ口 | 005368 甚目寺 | 1.935 | 22 | 7 |
| 1 | 005368 甚目寺 | 005370 七宝 | 1.783 | 11 | 7 |
| 2 | 005370 七宝 | 005372 木田 | 1.656 | 10 | 6 |
| 3 | 005372 木田 | 005355 青塚 | 1.964 | 16 | 7 |
| 4 | 005355 青塚 | 005375 勝幡 | 1.632 | 15 | 6 |
| 5 | 005375 勝幡 | 005396 藤浪 | 1.293 | 17 | 5 |
| 6 | 005396 藤浪 | 005420 津島 | 1.488 | 20 | 6 |

Total: 7 complete intervals, 8 ordered station endpoints, 44 planned viewpoints.

## Connection-direction custody

- **須ヶ口 / 名古屋本線:** station 005352 is shared literally by both records. 津島線 #0 begins at `[136.845755,35.19893]` and then uses `[136.84497,35.19937]`, `[136.84472,35.19948]`. Those points are the reverse of the final supports of 名古屋本線 #17 丸ノ内→須ヶ口. 名古屋本線 #18 須ヶ口→新川橋 leaves eastward. Therefore the complete display review must retain the direct east-side 名古屋本線 approach through 須ヶ口 into the west/north shared stem and then the 津島 branch; it must not create a station reversal, a wrong-way U-turn, or a capped duplicate at the shared stem.
- **津島 / 尾西線:** station 005420 is shared literally. 津島線 #6 ends through `[136.73078,35.18055]`, `[136.73081,35.18017]`, `[136.73101,35.17845]`, `[136.73107,35.17803]`; the same ordered tail is present in 尾西線 #16 町方→津島. 尾西線 #17 leaves 津島 southward. Review the north/shared approach and south continuation separately and confirm that the product shows the legal line directions without a false return, terminal cap, or borrowed parallel arm.
- `physical-rail-topology.json` (SHA-256 `9baedae7805d2855acbe34aca81d0bdcc3ea527391a84c07356b0a068d5406e3`) records three shared N02 vertices with 名古屋本線 near `[136.84472,35.19948]` and four with 尾西線 near `[136.73078,35.18055]`, both as `requires-independent-physical-evidence`. This supports scope selection and shared-source custody; it does not by itself prove passenger routing or pixel alignment.

## Interval #5 dogleg

- The small 勝幡→藤浪 dogleg is present in the published source array, not introduced by smoothing or a display override: `[136.74725,35.19365] → [136.74706,35.1938] → [136.74693,35.19374]` in travel order.
- The same three literal vertices occur, in reverse feature order, in `app/data/rail-sections.json` N02 feature 20651, properties `N02_001=12`, `N02_002=4`, `N02_003=津島線`, `N02_004=名古屋鉄道`. Raw file SHA-256: `88bb7fa1fb4c90c5618bce0349fa97cb54a3eba7f2a641108f24d064adde659b`.
- This establishes the dogleg's immediate source lineage only. It does not prove that the bend matches the current visible passenger rails. All five #5 views require full-resolution basemap/display/smooth review; compare the local rail curve and reject a smoothing chord, spike, road-following excursion, or label-driven false kink. If Apple rail identity is hidden or ambiguous, record WARNING rather than modifying or declaring it correct.

## Capture and review gates

1. Generate a fresh plan and bind every capture to `lineID`, `itemID`, interval index, both station IDs, and current whole-line dependency. Confirm loaded basemaps and actual pending/failed counts. Do not force 44 if the current deterministic plan validly changes; explain any difference.
2. Open every basemap/display/smooth panel for all seven intervals. Inspect both endpoints, all six shared station seams, every short tail, and the entire #5 dogleg. Counts and distance metrics are not pixel evidence.
3. Capture Main complete-interval ON/OFF pairs for all seven intervals plus close/shared-context views at 須ヶ口 and 津島. Include enough 名古屋本線 and 尾西線 context to assess the actual merge direction, without treating a shared station ID alone as proof of a physical or service join.
4. Confirm display and smooth continuity independently: no short terminal caps at intermediate stations, no duplicate shared stem, no sudden lane-side flip, no U-turn, and no curve cut across visible rail.

## Pending

- No fresh native or Main capture was performed for this preparation. All seven intervals and both shared connection contexts remain pending actual pixel review.
- No source, display geometry, physical station, topology, or lane change is proposed.

## Current binding after ordinal16 formal delivery

The earlier package/lane hashes above are preparation history. Before ordinal18 acquisition, current formal JP SHA is `fc1b976887463fcf262235178fdefd8038d954eb12189d07fe63ce1586354455`, current lanes SHA is `cb8e97c73172205778082523cb997b4abf8fbcc1934ead84611f2d284cfdd20b`, and the exact Tsushima line-object SHA is `d9901cb2d4c2cddbd573aca7b4926eba701097d180eea3bc18c63f3575e182b0`. Tsushima itself still has no display aliases/interval overrides; all seven source intervals and its native part are unchanged by the Jounan repair. Actual ordinal18 captures remain pending.
