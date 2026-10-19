# Ordered continuation scope preparation — ordinals 19–21

## Order custody

The existing Inspector/risk-plan first-appearance order after ordinal 18 津島線 yields exactly the following three records: ordinal 19 `jp-四国旅客鉄道-予土線`, ordinal 20 `jp-土佐くろしお鉄道-阿佐線`, and ordinal 21 `jp-埼玉新都市交通-伊奈線`. The risk JSON uses a zero-based first-appearance index two lower than the continuation ordinal (17/18/19); this is an indexing convention, not a source mismatch. This preparation preserves the requested continuation ordinals and does not re-sort lines by package order or name.

Current package: `app/public/rail/jp-2025.json` SHA-256 `a128bf177b2a13b0dd27e9520c04bc96691a0972bfdbdb9bfb939d85d2391942`. Existing plan: `ios/refactor-parallel/alignment-passenger-local-recheck-20261010.json` SHA-256 `4fc732595d464ac561ffa9eb4d44a4520c2e11d5bde72ac06900a97cfd579921`. Every scope below is **pending**: no UI capture or pixel review was performed.

## Ordinal 19: `jp-四国旅客鉄道-予土線`

- Canonical source name/operator: 予土線 / 四国旅客鉄道. `railwayIdentity` is `jp-四国旅客鉄道-予土線`.
- Complete scope: 19 intervals, 20 ordered stations, 245 existing planned viewpoints.
- Original risk-list interval: **#3 土佐大正 → 土佐昭和**, 27 planned views. The plan stores no textual risk reason and has no completed pixels; the designation must remain pending rather than be reverse-engineered into a verdict.
- Package display overrides: none.

| # | From | To | km | source pts | views |
|---:|---|---|---:|---:|---:|
| 0 | 009535 若井 | 009558 家地川 | 5.775 | 104 | 18 |
| 1 | 009558 家地川 | 009549 打井川 | 4.822 | 107 | 15 |
| 2 | 009549 打井川 | 009526 土佐大正 | 7.007 | 159 | 22 |
| 3 | 009526 土佐大正 | 009493 土佐昭和 | 8.801 | 193 | 27 |
| 4 | 009493 土佐昭和 | 009477 十川 | 4.536 | 109 | 14 |
| 5 | 009477 十川 | 009515 半家 | 7.842 | 139 | 24 |
| 6 | 009515 半家 | 009545 江川崎 | 3.875 | 78 | 13 |
| 7 | 009545 江川崎 | 009537 西ヶ方 | 2.762 | 53 | 9 |
| 8 | 009537 西ヶ方 | 009489 真土 | 5.858 | 97 | 18 |
| 9 | 009489 真土 | 009488 吉野生 | 1.625 | 41 | 6 |
| 10 | 009488 吉野生 | 009484 松丸 | 2.324 | 46 | 8 |
| 11 | 009484 松丸 | 009459 出目 | 3.492 | 72 | 11 |
| 12 | 009459 出目 | 009455 近永 | 1.567 | 24 | 6 |
| 13 | 009455 近永 | 009441 深田 | 2.143 | 28 | 8 |
| 14 | 009441 深田 | 009416 大内 | 2.965 | 47 | 10 |
| 15 | 009416 大内 | 009411 二名 | 1.382 | 21 | 5 |
| 16 | 009411 二名 | 009414 伊予宮野下 | 2.209 | 24 | 8 |
| 17 | 009414 伊予宮野下 | 009423 務田 | 0.880 | 18 | 4 |
| 18 | 009423 務田 | 009471 北宇和島 | 6.232 | 132 | 19 |

**Endpoints and branch direction to inspect:**

- 若井 009535 is shared with 土佐くろしお鉄道 中村線. 中村線 窪川→若井 ends at the exact Yodo start `[133.105835,33.188045]`; both Yodo #0 and 中村線 若井→荷稲 then initially use `[133.10562,33.18771]`, `[133.10551,33.18744]`. Review the shared approach and the true split as a directional junction: no duplicate stem, terminal cap, wrong arm, or U-turn. Do not infer a train movement merely from the shared station ID.
- 北宇和島 009471 is shared with 予讃線. Yodo #18 and 予讃線 高光→北宇和島 share their final approach through `[132.56951,33.24095]`, `[132.56968,33.23958]`, `[132.569715,33.23924]`; 予讃線 then continues south to 宇和島. Review the complete #18 tail and continuation, preserving the shared approach without clipping the intermediate station context.
- Risk #3 is the long 土佐大正→土佐昭和 mountain interval (8.801 km, 193 source points, 27 planned views). Inspect every bend, tunnel/terrain-occluded section, both seams, and all short display tails. Lack of visible rail in wooded/tunnel terrain is WARNING, not alignment acceptance.
- Current native cache has one station-approach/groomed part, 1,518 points / 76,166.3 m, plus one full-part measured lane at -0.5. No follow/family/release rows are present.

## Ordinal 20: `jp-土佐くろしお鉄道-阿佐線`

- Canonical source name/operator: 阿佐線 / 土佐くろしお鉄道. `railwayIdentity` is `jp-土佐くろしお鉄道-阿佐線`.
- Complete scope: 20 intervals, 21 ordered stations, 150 existing planned viewpoints.
- Original risk-list interval: **#10 赤野 → 穴内**, 13 planned views. The plan stores no textual risk reason and has no completed pixels; the designation must remain pending rather than be reverse-engineered into a verdict.
- Package display overrides: none.

| # | From | To | km | source pts | views |
|---:|---|---|---:|---:|---:|
| 0 | 009057 後免 | 009077 後免町 | 1.018 | 34 | 4 |
| 1 | 009077 後免町 | 009087 立田 | 1.840 | 26 | 7 |
| 2 | 009087 立田 | 009112 のいち | 2.778 | 44 | 9 |
| 3 | 009112 のいち | 009193 よしかわ | 2.303 | 55 | 8 |
| 4 | 009193 よしかわ | 009203 あかおか | 1.334 | 26 | 5 |
| 5 | 009203 あかおか | 009205 香我美 | 1.418 | 22 | 6 |
| 6 | 009205 香我美 | 009211 夜須 | 1.698 | 24 | 6 |
| 7 | 009211 夜須 | 009227 西分 | 4.010 | 20 | 13 |
| 8 | 009227 西分 | 009229 和食 | 1.730 | 16 | 6 |
| 9 | 009229 和食 | 009230 赤野 | 1.435 | 13 | 6 |
| 10 | 009230 赤野 | 009239 穴内 | 3.939 | 26 | 13 |
| 11 | 009239 穴内 | 009244 球場前 | 2.647 | 24 | 9 |
| 12 | 009244 球場前 | 009242 あき総合病院前 | 0.580 | 13 | 3 |
| 13 | 009242 あき総合病院前 | 009240 安芸 | 0.844 | 15 | 4 |
| 14 | 009240 安芸 | 009256 伊尾木 | 2.693 | 24 | 9 |
| 15 | 009256 伊尾木 | 009271 下山 | 4.295 | 53 | 14 |
| 16 | 009271 下山 | 009280 唐浜 | 2.442 | 44 | 8 |
| 17 | 009280 唐浜 | 009281 安田 | 1.676 | 15 | 6 |
| 18 | 009281 安田 | 009288 田野 | 2.745 | 37 | 9 |
| 19 | 009288 田野 | 009290 奈半利 | 1.179 | 16 | 5 |

**Endpoints and branch direction to inspect:**

- 後免 009057 is shared with JR 四国 土讃線. 土讃線 土佐長岡→後免 ends at the exact Asa start `[133.645135,33.57918]`; Asa #0 then reverses the last shared supports toward `[133.64583,33.57943]`, `[133.6461,33.57953]` before turning onto its own eastbound alignment. Review the actual shared approach/fork direction and reject a capped duplicate or reverse fold.
- 奈半利 009290 is an exclusive terminal in the current package. Review the full #19 approach, last short tail, terminal station frame, and smooth endpoint; do not extend it to an unregistered continuation.
- Risk #10 is 赤野→穴内 (3.939 km, 26 points, 13 views). Its source includes a sparse eastern approach near `[133.85659,33.50617] → [133.86396,33.50641] → [133.864088,33.506197]`; inspect this whole window for a long chord, coast/road borrowing, end hook, or smoothing shortcut. The risk-list entry itself supplies no pixel conclusion.
- Current native cache has one station-approach/groomed part, 572 points / 42,635.0 m. No measured lane, follow, family, or release row is present.

## Ordinal 21: `jp-埼玉新都市交通-伊奈線`

- Canonical source name/operator: 伊奈線 / 埼玉新都市交通. `railwayIdentity` is `jp-埼玉新都市交通-伊奈線`.
- Complete scope: 12 intervals, 13 ordered stations, 56 existing planned viewpoints.
- Original risk-list interval: **#0 大宮 → 鉄道博物館**, 6 planned views. The plan stores no textual risk reason and has no completed pixels; the designation must remain pending rather than be reverse-engineered into a verdict.
- Package display overrides: none.

| # | From | To | km | source pts | views |
|---:|---|---|---:|---:|---:|
| 0 | 002914 大宮 | 002881 鉄道博物館 | 1.525 | 19 | 6 |
| 1 | 002881 鉄道博物館 | 002857 加茂宮 | 1.738 | 19 | 6 |
| 2 | 002857 加茂宮 | 002844 東宮原 | 0.777 | 5 | 4 |
| 3 | 002844 東宮原 | 002835 今羽 | 0.824 | 5 | 4 |
| 4 | 002835 今羽 | 002824 吉野原 | 0.787 | 6 | 4 |
| 5 | 002824 吉野原 | 002812 原市 | 0.768 | 10 | 4 |
| 6 | 002812 原市 | 002802 沼南 | 0.807 | 11 | 4 |
| 7 | 002802 沼南 | 002787 丸山 | 0.963 | 18 | 4 |
| 8 | 002787 丸山 | 002770 志久 | 1.297 | 28 | 5 |
| 9 | 002770 志久 | 002756 伊奈中央 | 1.052 | 16 | 5 |
| 10 | 002756 伊奈中央 | 002747 羽貫 | 1.152 | 20 | 5 |
| 11 | 002747 羽貫 | 002742 内宿 | 1.068 | 27 | 5 |

**Endpoints and direction to inspect:**

- 大宮 002914 is a shared station identity with multiple JR and Tobu lines, but the Ina New Shuttle guideway is an independent mode/corridor and the current data has no follow or family join to them. Review #0 from its own Omiya terminal guideway through the initial curve to 鉄道博物館; do not connect it to a conventional railway merely because the station ID is shared.
- 内宿 002742 is an exclusive terminal. Review #11 through its final curve/straight, station frame and endpoint tail; no synthetic continuation beyond the registered terminal.
- Risk #0 is 大宮→鉄道博物館 (1.525 km, 19 points, 6 views). Inspect the complete urban guideway departure, terminal cap, first bend and seam. Roads, conventional rails, buildings and station decks are competing cartography and must not substitute for the New Shuttle guideway.
- Current native cache has one part, 184 points / 12,772.5 m, and one full-part measured lane at -1. No follow/family/release rows are present.

## Common pending gates

1. Generate a fresh deterministic plan and bind each capture to the exact `lineID`, `itemID`, interval index, endpoint IDs and whole-line dependency. Existing totals (245 / 150 / 56) are expectations, not forced acceptance counts. Explain any legitimate current-plan difference.
2. Open every basemap/display/smooth panel for every complete interval. Check both termini, every station seam, all short tails, curve continuity and smoothing. Counts, zero-lane state and distance diagnostics cannot substitute for pixel review.
3. Capture Main complete-interval ON/OFF pairs and additional endpoint/fork context for 若井, 北宇和島, 後免, 奈半利, 大宮 and 内宿. Confirm actual overlay identity and budget drops separately.
4. Terrain, tunnel, roof, label or low-detail occlusion remains WARNING. No source geometry, physical station, topology or display lane change is authorized by this preparation.
