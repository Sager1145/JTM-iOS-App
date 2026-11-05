# Bundled example trips: verification (2026-11-05)

Scope: the 287 bundled example rides: `app/data/train-store.json` (201 rides),
`train-store-tw` (28), `-hk`, `-kr` and `-mo` (1 each), plus
`special-samples/new-year-grand-loop.json` (39) and
`special-samples/tokyo-limited-express-loop.json` (16). Sources for the field
values are in `app/data/sample-trips.sources.md`.

## 1. Route correctness

### Method

Every leg of every ride was checked mechanically, two ways.

1. **The app's own draw path** (`ios/RailKit/Tests/RailCoreTests/SampleTripDisplayCensusTests.swift`).
   The test is opt-in. Run it with:
   `SAMPLE_DISPLAY_CENSUS=1 SAMPLE_DISPLAY_CENSUS_OUTPUT=/abs/census.json swift test --filter SampleTripDisplayCensusTests`.
   - **What it does:** loads each region's compact-v1 display package (the geometry behind "display all rail routes") into a `RouteNetwork`, the same way `DisplayNetworkCache` does. It then calls `precomputedDisplayParts`, which is the call `RiddenRouteStore` makes before drawing a precomputed ride.
   - **Per leg it records:** which display lines carried the drawn stroke, and whether the projection fell back to the raw solver path. It also records the largest distance in each direction between the drawn stroke and the solved path, sampled every 50 m.
2. **Independent geometry check** (`app/scripts/samples/audit-sample-routes.py`).
   - **Matching:** the solved path of each leg is resampled every 25 m, and each sample is matched to the display package within 60 m.
   - **What it reports:**
     - the longest run with no display line nearby (catches straight chords and missing track);
     - the longest run whose nearby lines are all outside the leg's line names (catches a wrong branch or line);
     - the same check against operator names (catches a wrong operator).
   - **What it ignores:** the first and last 450 m of each leg (endpoint snaps), and runs under 150 m, which are noise at this tolerance.
   - **Output:** with `--census`, `--notes app/scripts/samples/sample-route-notes.json` and `--md`, it writes the table in section 1.3.

Both checks ran on the committed precompute (`route_solver_version` 28). This change's precompute leaves the route geometry of every ride byte-identical to `main`: only stop fields and section names changed.

### Result

- **Legs drawn:** 2,225 legs across 287 rides, all solved. 2,209 are drawn as slices of display lines. The other 16 are drawn from the solver path, which stays within 60 m of the display network for its whole length (legend A).
- **Defects found:** no ride is drawn on a wrong line, wrong branch, wrong operator or in the wrong direction, and no ride contains a straight chord. The long straight drawn edges (up to 8.4 km) are all display-package geometry on genuinely straight alignments: 青函トンネル, 北陸新幹線 tunnels between 越前たけふ and 敦賀, 九州新幹線 tunnels, the 函館線 美唄–砂川 straight, and 東鐵綫.
- **Mileage defect:** one ride has an error in its solved path, which feeds distance statistics. The drawing is correct. It is item T1 below.
- **Earlier fixes:** the two misrouted rides fixed earlier (Haruka 38 関西空港→天王寺, and サンライズ出雲 浜松→姫路, which had strayed onto non-JR track) stay fixed: `institution_filter_mode: hard`, and no off-operator run.
- **Rejected experiment:** I tried adding explicit `route_sections` with both line names for the 16 two-line hops. It changed three solves for the worse: Haruka 天王寺→大阪 was forced onto the east side of the 環状線 (4.2 km off), 阿波池田→阿波加茂 grew by 0.5 km, and one Tokyo-loop leg was lost. The projection still refused to draw any of the 16 hops across two lines. I reverted it, so those rides keep their inferred per-hop lines.

Verdict legend used in the table:

- **A.** The hop crosses from one line to another, and the precompute's per-hop line hint names only one of them, which is correct for the endpoints. The path is right. The projection does not draw one hop across two display lines, so the solver path is drawn instead; it stays within 60 m of the display network for its whole length.
- **B.** A naming difference between N02 and the display package, not a routing error. N02 names the operator 東京地下鉄 where the package says 東京メトロ. The package draws the 品鶴線/横須賀線 corridor (東京–品川–西大井–鶴見) as `総武線` (`jp-東日本旅客鉄道-総武線-3`).
- **C.** The leg is drawn on the correct display line. The solver's N02 path, which is what mileage uses, runs beside it at the stated offset. That is a geometry difference between `rail-sections.json` and the display package (topology item T3).
- **D.** An endpoint gap: the display stroke ends short of the station, or the station sits off the track.
- **E.** At a switchback or a directional loop, the display draws the real track and the N02 path takes the other track or cuts the corner. The drawing is correct; the distance differs by the stated amount.
- **F.** The solved path contains an out-and-back spike.

### Topology and geometry items (national datasets, not edited here)

| # | Dataset | Item | Effect |
|---|---|---|---|
| T1 | `rail-sections.json` (N02), 鹿児島線 折尾 | Two 鹿児島線 折尾 features share code 008707, about 300 m apart (130.7147 and 130.7116). The westbound solve from 折尾 runs 3.6 km east, then turns back. | `20260722_06_sonic44` 折尾→赤間 is solved as 23.8 km instead of about 16.7 km, which adds 7.2 km to statistics. The map drawing is correct, because the projection slices the display 鹿児島線. |
| T2 | `stations-kr.json` | 상주 (Sangju) is missing. Korail 무궁화호 on the 경북선 stops at 상주 and 함창, not at 백원 or 어등 (secondary sources are listed in `sample-trips.sources.md`). | The KR sample's stop list can't be corrected until 상주 exists. |
| T3 | `rail-sections.json` vs `jp-2025.json` | N02 track runs 80–220 m beside the display alignment on: 岡山–倉敷 (山陽線, 1.7 km), 豊栄–新潟 (白新線, 2.4 km), 保土ヶ谷–東戸塚 (1.1 km), 五稜郭 approaches (0.7 km), 思川–栃木 (0.6 km) and 東能代–秋田 (0.5 km). Between 新橋 and 品川, N02 models the JR East 東海道線 as one alignment on the 横須賀線 tracks; the display draws the surface 東海道線 up to 220 m away. 大鰐温泉–大館: up to 1.1 km apart. | Drawing is unaffected, because legs project onto display lines. Mileage and statistics follow N02. Rail Diagnostics captures are needed to decide which geometry is surveyed correctly (see 1.4). |
| T4 | `rail-sections.json`, 北陸線 鳩原 loop; 豊肥線 立野 switchback | N02 gives one track per direction: 敦賀→新疋田 takes the 6.6 km down track, not the 9.8 km up-track loop, and 立野 has no switchback. | `20260708_02_shirasagi2` is 3.2 km short, and the あそぼーい rides are 1.7 km short. Drawing is correct. |
| T5 | `jp-2025.json` display strokes | Strokes stop short of their stations: 西九州線 at MR 伊万里 (560 m), 佐世保線 at 早岐 (362 m), 成田線 east of 成田 (700 m), the 熊本市電 stop at 水道町 (409 m from track). In TW, 神木線 is 0.9 km shorter than the solved path between 神木 and 阿里山. | A small visible gap at that stop. |

### 1.4 Rail Diagnostics captures

The plan was z17 basemap/display captures of the T1 and T3 spots:

- `jp-九州旅客鉄道-鹿児島線` intervals 68–70
- `jp-西日本旅客鉄道-山陽線` intervals 40–43
- `jp-東日本旅客鉄道-白新線` intervals 0–2
- `jp-東日本旅客鉄道-東海道線` intervals 2–5

They are **not captured**. `bash ios/verify.sh build --target diagnostics` fails on `main` with exit 65: the RailDiagnostics target compiles `RailMap/JourneyEditor/NewTripView.swift` but not the new `TripMapView.swift`, so `TripMapContent` is missing. That is a project-membership fix in another session's area and is reported separately. The route verdicts above rest on the RailKit census, which runs the same projection code the app draws with.

### 1.3 Per-ride table (all 287 rides)

Columns: legs are precomputed hops. "Display lines drawn" lists the display lines the app slices for the drawing, in travel order, with consecutive repeats merged and long lists cut after 8. "Projected" counts legs drawn as display-line slices. The m columns are the geometry-check maxima described above (0 = none over 150 m). "drawn↔solved" is the census maximum distance between the drawn stroke and the solved path.

| # | Store | Ride | Legs | Display lines drawn (in order) | Projected legs | Max off-network m | Max off-line m | Max off-operator m | Max drawn↔solved m | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | sample-data | `20260703_01_haruka` | 3 | 阪和線 → 大阪環状線 → 東海道線 | 2/3 | 0 | 34237 | 0 | 3 | OK (A: 関西空港→天王寺 = 関西空港線+阪和線) |
| 2 | sample-data | `20260703_02_tokaido_shinkansen_hikari_kodama` | 11 | 東海道新幹線 | 11/11 | 0 | 0 | 0 | 36 | OK |
| 3 | sample-data | `20260703_03_tokaido_main_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 4 | sample-data | `20260704_01_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 5 | sample-data | `20260704_02_kodama918` | 4 | 東海道新幹線 | 4/4 | 0 | 0 | 0 | 6 | OK |
| 6 | sample-data | `20260704_03_keikyu_asakusa_line` | 3 | 本線 → 1号線浅草線 | 3/3 | 0 | 0 | 0 | 5 | OK |
| 7 | sample-data | `20260704_04_oedo_line` | 1 | 12号線大江戸線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 8 | sample-data | `20260704_05_mita_line` | 4 | 6号線三田線 | 4/4 | 0 | 0 | 0 | 24 | OK |
| 9 | sample-data | `20260704_06_marunouchi_line` | 7 | 4号線丸ノ内線 | 7/7 | 0 | 0 | 1016 | 17 | OK (B: 東京地下鉄 = 東京メトロ) |
| 10 | sample-data | `20260704_07_saikyo_line` | 14 | 赤羽線 → 東北線 | 14/14 | 0 | 0 | 0 | 21 | OK |
| 11 | sample-data | `20260704_08_shonan_shinjuku_line` | 30 | 東北線 → 赤羽線 → 山手線 → 大崎支線 → 総武線 → 東海道線 | 30/30 | 0 | 5512 | 0 | 502 | OK (B: 品鶴線 drawn as 総武線; D: 394 m snap at 大崎) |
| 12 | sample-data | `20260704_09_negishi_line` | 1 | 根岸線 | 1/1 | 0 | 0 | 0 | 4 | OK |
| 13 | sample-data | `20260704_10_minatomirai_line` | 2 | みなとみらい21線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 14 | sample-data | `20260704_11_keihin_tohoku_line` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 26 | OK |
| 15 | sample-data | `20260704_12_yokohama_line` | 3 | 横浜線 | 3/3 | 0 | 0 | 0 | 2 | OK |
| 16 | sample-data | `20260704_13_kodama915` | 3 | 東海道新幹線 | 3/3 | 0 | 0 | 0 | 6 | OK |
| 17 | sample-data | `20260704_14_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 18 | sample-data | `20260705_01_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 19 | sample-data | `20260705_02_kodama802` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 20 | sample-data | `20260705_03_chuo_line` | 10 | 東北線 → 中央線 | 10/10 | 0 | 0 | 0 | 34 | OK |
| 21 | sample-data | `20260705_04_chuo_sobu_line` | 5 | 中央線 | 5/5 | 0 | 0 | 0 | 21 | OK |
| 22 | sample-data | `20260705_05_yurakucho_line` | 2 | 8号線有楽町線 | 2/2 | 0 | 0 | 626 | 3 | OK (B: 東京地下鉄 = 東京メトロ) |
| 23 | sample-data | `20260705_06_yurakucho_line` | 3 | 8号線有楽町線 | 3/3 | 0 | 0 | 422 | 0 | OK (B: 東京地下鉄 = 東京メトロ) |
| 24 | sample-data | `20260705_07_yamanote_line` | 8 | 山手線 → 東北線 | 8/8 | 0 | 0 | 0 | 12 | OK |
| 25 | sample-data | `20260705_08_hayabusa59` | 9 | 東北新幹線 | 9/9 | 0 | 0 | 0 | 6 | OK |
| 26 | sample-data | `20260706_01_hayabusa11` | 12 | 東北新幹線 | 12/12 | 0 | 0 | 0 | 5 | OK |
| 27 | sample-data | `20260706_02_super_tsugaru2` | 6 | 奥羽線 | 6/6 | 535 | 0 | 0 | 1120 | OK drawn (C: 大鰐温泉–大館 solved path up to 1.1 km off display; 東能代–秋田 535 m) |
| 28 | sample-data | `20260706_03_inaho14` | 15 | 羽越線 → 白新線 | 15/15 | 2371 | 0 | 0 | 138 | OK drawn (C: 豊栄–新潟 solved path ~140 m beside display for 2.4 km) |
| 29 | sample-data | `20260707_01_toki308` | 6 | 上越新幹線 | 6/6 | 0 | 0 | 0 | 3 | OK |
| 30 | sample-data | `20260707_02_hakutaka555` | 5 | 北陸新幹線 | 5/5 | 0 | 0 | 0 | 2 | OK |
| 31 | sample-data | `20260707_03_local` | 4 | 信越線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 32 | sample-data | `20260707_04_local` | 4 | 信越線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 33 | sample-data | `20260707_05_local` | 12 | 長野線 | 12/12 | 0 | 0 | 0 | 0 | OK |
| 34 | sample-data | `20260707_06_a_ltdexp` | 2 | 長野線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 35 | sample-data | `20260707_07_hakutaka565` | 9 | 北陸新幹線 | 9/9 | 0 | 0 | 0 | 1 | OK |
| 36 | sample-data | `20260708_01_tsurugi17` | 4 | 北陸新幹線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 37 | sample-data | `20260708_02_shirasagi2` | 11 | 北陸線 | 11/11 | 0 | 0 | 0 | 1018 | OK drawn (E: 鳩原 loop drawn; solved path on down track, 3.2 km short) |
| 38 | sample-data | `20260708_03_hikari648` | 2 | 東海道新幹線 | 2/2 | 0 | 0 | 0 | 6 | OK |
| 39 | sample-data | `20260708_04_hikari706` | 7 | 東海道新幹線 | 7/7 | 0 | 0 | 0 | 7 | OK |
| 40 | sample-data | `20260708_05_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 41 | sample-data | `20260709_01_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 42 | sample-data | `20260709_02_hikari713` | 10 | 東海道新幹線 | 10/10 | 0 | 0 | 0 | 7 | OK |
| 43 | sample-data | `20260709_03_miyakoji_rapid` | 8 | 奈良線 | 8/8 | 0 | 0 | 0 | 4 | OK |
| 44 | sample-data | `20260709_04_d_section_rapid` | 8 | 奈良線 | 8/8 | 0 | 0 | 0 | 4 | OK |
| 45 | sample-data | `20260710_01_nozomi252` | 3 | 東海道新幹線 | 3/3 | 0 | 0 | 0 | 6 | OK |
| 46 | sample-data | `20260710_02_kodama824` | 7 | 東海道新幹線 | 7/7 | 0 | 0 | 0 | 7 | OK |
| 47 | sample-data | `20260710_03_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 48 | sample-data | `20260710_04_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 49 | sample-data | `20260710_05_hikari718` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 50 | sample-data | `20260710_06_yamabiko221` | 2 | 東北新幹線 | 2/2 | 0 | 0 | 0 | 33 | OK |
| 51 | sample-data | `20260710_07_keihin_tohoku_local` | 5 | 東北線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 52 | sample-data | `20260711_01_keihin_tohoku_negishi_local` | 5 | 東北線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 53 | sample-data | `20260711_02_kagayaki501` | 15 | 上越新幹線 → 北陸新幹線 | 15/15 | 0 | 0 | 0 | 2 | OK |
| 54 | sample-data | `20260711_03_hakutaka560` | 15 | 北陸新幹線 → 上越新幹線 | 15/15 | 0 | 0 | 0 | 2 | OK |
| 55 | sample-data | `20260711_04_saikyo_local` | 14 | 東北線 → 赤羽線 | 14/14 | 0 | 0 | 0 | 13 | OK |
| 56 | sample-data | `20260711_05_seibu_ikebukuro_semiexp` | 17 | 池袋線 | 17/17 | 0 | 0 | 0 | 2 | OK |
| 57 | sample-data | `20260711_06_seibu_sayama_local` | 2 | 狭山線 | 2/2 | 0 | 0 | 0 | 1 | OK |
| 58 | sample-data | `20260712_01_musashino_local` | 6 | 武蔵野線 | 6/6 | 0 | 0 | 0 | 2 | OK |
| 59 | sample-data | `20260712_02_seibu_ikebukuro_semiexp` | 2 | 池袋線 | 2/2 | 0 | 0 | 0 | 1 | OK |
| 60 | sample-data | `20260712_03_seibu_sayama_local` | 2 | 狭山線 | 2/2 | 0 | 0 | 0 | 1 | OK |
| 61 | sample-data | `20260712_04_seibu_sayama_ikebukuro_local` | 4 | 狭山線 → 池袋線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 62 | sample-data | `20260712_05_musashino_local` | 6 | 武蔵野線 | 6/6 | 0 | 0 | 0 | 2 | OK |
| 63 | sample-data | `20260713_01_keihin_tohoku_negishi_local` | 16 | 東北線 | 16/16 | 0 | 0 | 0 | 37 | OK |
| 64 | sample-data | `20260713_02_kodama801` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 65 | sample-data | `20260713_03_tokaido_main_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 66 | sample-data | `20260713_04_tokaido_main_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 67 | sample-data | `20260713_05_kodama816` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 68 | sample-data | `20260713_06_hayabusa27` | 25 | 東北新幹線 → 北海道新幹線 | 25/25 | 0 | 0 | 0 | 33 | OK |
| 69 | sample-data | `20260713_07_hokuto21` | 11 | 函館線 → 室蘭線 → 千歳線 → 函館線 | 9/11 | 51 | 5290 | 0 | 55 | OK (A: 苫小牧→南千歳 室蘭線+千歳線; 新札幌→札幌 千歳線+函館線) |
| 70 | sample-data | `20260714_01_ozora3` | 11 | 函館線 → 千歳線 → 石勝線 → 根室線 | 10/11 | 51 | 1178 | 0 | 0 | OK (A: 札幌→新札幌 函館線+千歳線) |
| 71 | sample-data | `20260714_02_nemuro_main_local` | 16 | 根室線 | 16/16 | 0 | 0 | 0 | 0 | OK |
| 72 | sample-data | `20260714_03_nemuro_main_local` | 16 | 根室線 | 16/16 | 0 | 0 | 0 | 0 | OK |
| 73 | sample-data | `20260714_04_ozora12` | 7 | 根室線 → 石勝線 → 千歳線 → 函館線 | 6/7 | 51 | 5290 | 0 | 0 | OK (A: 新札幌→札幌 千歳線+函館線) |
| 74 | sample-data | `20260715_01_soya` | 16 | 函館線 → 宗谷線 | 16/16 | 52 | 51 | 0 | 49 | OK |
| 75 | sample-data | `20260715_02_soya` | 14 | 宗谷線 → 函館線 | 14/14 | 77 | 51 | 0 | 49 | OK |
| 76 | sample-data | `20260716_01_sapporo_subway_namboku_sapporo_susukino` | 2 | 南北線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 77 | sample-data | `20260716_02_sapporo_subway_namboku_odori_nakajimakoen` | 2 | 南北線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 78 | sample-data | `20260716_03_sapporo_streetcar_nakajimakoendori_susukino` | 4 | 山鼻線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 79 | sample-data | `20260716_04_sapporo_streetcar_susukino_chuokuyakushomae` | 4 | 都心線 → 1条線 | 4/4 | 0 | 0 | 0 | 21 | OK |
| 80 | sample-data | `20260716_05_sapporo_subway_tozai_nishi11_odori` | 1 | 東西線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 81 | sample-data | `20260716_06_sapporo_subway_namboku_odori_sapporo` | 1 | 南北線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 82 | sample-data | `20260716_07_hokuto20` | 14 | 函館線 → 千歳線 → 室蘭線 → 函館線 | 12/14 | 683 | 1178 | 0 | 120 | OK (A: 札幌→新札幌, 南千歳→苫小牧; C: 五稜郭 approach ~120 m) |
| 83 | sample-data | `20260717_01_hakodate_tram` | 8 | 湯の川線 → 大森線 | 8/8 | 0 | 0 | 0 | 0 | OK |
| 84 | sample-data | `20260717_02_hakodate_tram` | 5 | 本線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 85 | sample-data | `20260718_01_hakodate_liner` | 5 | 函館線 | 5/5 | 682 | 0 | 0 | 120 | OK drawn (C: 五稜郭–桔梗 ~120 m for 0.7 km) |
| 86 | sample-data | `20260718_02_hayabusa10` | 5 | 北海道新幹線 → 東北新幹線 | 5/5 | 0 | 0 | 0 | 1 | OK |
| 87 | sample-data | `20260718_03_hayabusa95` | 2 | 東北新幹線 | 2/2 | 0 | 0 | 0 | 1 | OK |
| 88 | sample-data | `20260718_04_ou_main_local` | 1 | 奥羽線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 89 | sample-data | `20260718_05_ou_main_local` | 1 | 奥羽線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 90 | sample-data | `20260718_06_hayabusa` | 5 | 東北新幹線 | 5/5 | 0 | 0 | 0 | 1 | OK |
| 91 | sample-data | `20260718_07_yamabiko` | 17 | 東北新幹線 | 17/17 | 0 | 0 | 0 | 33 | OK |
| 92 | sample-data | `20260718_08_kodama839` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 93 | sample-data | `20260718_09_tokaido_main_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 94 | sample-data | `20260718_10_tokaido_main_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 95 | sample-data | `20260718_11_hikari659` | 7 | 東海道新幹線 | 7/7 | 0 | 0 | 0 | 7 | OK |
| 96 | sample-data | `20260719_01_hikari703` | 7 | 東海道新幹線 → 山陽新幹線 | 7/7 | 51 | 77 | 77 | 36 | OK |
| 97 | sample-data | `20260719_02_yakumo11` | 6 | 山陽線 → 伯備線 | 5/6 | 1683 | 4364 | 0 | 143 | OK (A: 根雨→米子 伯備線+山陰線; C: 岡山–倉敷 ~110 m) |
| 98 | sample-data | `20260719_03_super_oki5` | 18 | 山陰線 → 山口線 | 18/18 | 0 | 0 | 0 | 4 | OK |
| 99 | sample-data | `20260719_04_sakura770` | 3 | 山陽新幹線 | 3/3 | 0 | 0 | 0 | 8 | OK |
| 100 | sample-data | `20260720_41_hiroden1_hiroshimaeki_fukuromachi` | 8 | 本線 → 宇品線 | 8/8 | 0 | 0 | 0 | 35 | OK |
| 101 | sample-data | `20260720_42_astram_hondori_johoku` | 2 | 広島新交通1号線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 102 | sample-data | `20260720_43_hiroden2_kamiyachonishi_shokocenter` | 16 | 本線 → 宮島線 | 16/16 | 0 | 0 | 0 | 1 | OK |
| 103 | sample-data | `20260720_44_sanyo_local_shininokuchi_hiroshima` | 4 | 山陽線 | 4/4 | 0 | 0 | 0 | 14 | OK |
| 104 | sample-data | `20260720_45_sakura753_hiroshima_hakata` | 7 | 山陽新幹線 | 7/7 | 0 | 0 | 0 | 12 | OK |
| 105 | sample-data | `20260720_46_tsubame325_hakata_shintosu` | 1 | 九州新幹線 | 1/1 | 0 | 0 | 0 | 1 | OK |
| 106 | sample-data | `20260720_47_midori35_shintosu_arita` | 4 | 長崎線 → 佐世保線 | 4/4 | 51 | 76 | 0 | 2 | OK |
| 107 | sample-data | `20260720_48_mr627d_arita_imari` | 10 | 西九州線 | 10/10 | 0 | 0 | 0 | 560 | OK (D: display 西九州線 ends 560 m short of MR 伊万里) |
| 108 | sample-data | `20260720_49_mr369d_imari_tabirahiradoguchi` | 19 | 西九州線 | 19/19 | 0 | 0 | 0 | 560 | OK (D: display 西九州線 ends 560 m short of MR 伊万里) |
| 109 | sample-data | `20260720_50_mr_tabirahiradoguchi_sasebo` | 27 | 西九州線 | 27/27 | 0 | 0 | 0 | 2 | OK |
| 110 | sample-data | `20260720_51_seasideliner3233d_sasebo_nagasaki` | 24 | 佐世保線 → 大村線 → 長崎線 | 24/24 | 0 | 0 | 0 | 362 | OK (D: 早岐 switchback, display ends 362 m short) |
| 111 | sample-data | `20260721_01_nagasaki_tram3_nagasakieki_heiwakoen` | 8 | 本線 | 8/8 | 0 | 0 | 0 | 0 | OK |
| 112 | sample-data | `20260721_02_nagasaki_tram3_urakamieki_nagasakieki` | 5 | 本線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 113 | sample-data | `20260721_03_nagasaki_tram1_nagasakieki_dejima` | 3 | 本線 | 3/3 | 0 | 0 | 0 | 1 | OK |
| 114 | sample-data | `20260721_04_nagasaki_tram1_dejima_nagasakieki` | 3 | 本線 | 3/3 | 0 | 0 | 0 | 1 | OK |
| 115 | sample-data | `20260721_05_kamome22` | 4 | 西九州新幹線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 116 | sample-data | `20260721_06_relay_kamome22` | 3 | 佐世保線 → 長崎線 | 3/3 | 51 | 76 | 0 | 2 | OK |
| 117 | sample-data | `20260721_07_sakura749` | 5 | 九州新幹線 | 5/5 | 0 | 0 | 0 | 3 | OK |
| 118 | sample-data | `20260721_08_asoboy3` | 5 | 豊肥線 | 5/5 | 0 | 0 | 0 | 950 | OK drawn (E: 立野 switchback drawn; solved path cuts it, 1.7 km short) |
| 119 | sample-data | `20260721_09_asoboy4` | 5 | 豊肥線 | 5/5 | 0 | 0 | 0 | 950 | OK drawn (E: 立野 switchback drawn; solved path cuts it, 1.7 km short) |
| 120 | sample-data | `20260721_10_kumamoto_tram_a_kumamotoeki_karashimacho` | 5 | 幹線 | 5/5 | 0 | 0 | 0 | 52 | OK |
| 121 | sample-data | `20260721_11_kumamoto_tram_karashimacho_suidocho` | 4 | 幹線 | 4/4 | 0 | 0 | 0 | 179 | OK (D: 水道町 stop 409 m from track; drawn stroke stops short) |
| 122 | sample-data | `20260721_12_hohi_local1493m_shinsuizenji_musashizuka` | 4 | 豊肥線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 123 | sample-data | `20260721_13_hohi_local1498m_musashizuka_kumamoto` | 7 | 豊肥線 | 7/7 | 0 | 0 | 0 | 1 | OK |
| 124 | sample-data | `20260721_14_sakura767` | 5 | 九州新幹線 | 5/5 | 0 | 0 | 0 | 1 | OK |
| 125 | sample-data | `20260722_01_ibusuki_1321d_kagoshima_yamakawa` | 18 | 指宿枕崎線 | 18/18 | 0 | 0 | 0 | 1 | OK |
| 126 | sample-data | `20260722_02_ibusuki_5321d_yamakawa_nishioyama` | 2 | 指宿枕崎線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 127 | sample-data | `20260722_03_ibusuki_1326d_nishioyama_minamikagoshima` | 18 | 指宿枕崎線 | 18/18 | 0 | 0 | 0 | 1 | OK |
| 128 | sample-data | `20260722_03a_kagoshima_tram_kagoshimachuoeki_miyakodori` | 1 | 唐湊線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 129 | sample-data | `20260722_03b_nanohana3328d_minamikagoshima_kagoshima` | 2 | 指宿枕崎線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 130 | sample-data | `20260722_04_kirishima8` | 9 | 鹿児島線 → 日豊線 | 9/9 | 0 | 0 | 0 | 24 | OK |
| 131 | sample-data | `20260722_05_nichirin10` | 10 | 日豊線 | 10/10 | 0 | 0 | 0 | 5 | OK |
| 132 | sample-data | `20260722_06_sonic44` | 16 | 日豊線 → 鹿児島線 | 16/16 | 79 | 52 | 0 | 3409 | MILEAGE (F: solved path makes a 7.2 km out-and-back at 折尾; drawn stroke correct) |
| 133 | sample-data | `20260722_07_kirameki6` | 8 | 鹿児島線 | 8/8 | 79 | 77 | 0 | 25 | OK |
| 134 | sample-data | `20260722_08_sonic54_kokura_kurosaki` | 1 | 鹿児島線 | 1/1 | 0 | 0 | 0 | 10 | OK |
| 135 | sample-data | `20260722_09_chikuho_electric_kurosaki_nogata` | 20 | 筑豊電気鉄道線 | 20/20 | 0 | 0 | 0 | 0 | OK |
| 136 | sample-data | `20260722_10_heichiku_ita_nogata_tagawaita` | 14 | 伊田線 | 14/14 | 0 | 0 | 0 | 7 | OK |
| 137 | sample-data | `20260722_11_hitahikosan_986d_tagawaita_kokura` | 12 | 日田彦山線 → 日豊線 | 12/12 | 0 | 0 | 0 | 5 | OK |
| 138 | sample-data | `20260722_12_monorail_kokura_kikugaoka` | 12 | 小倉線 | 12/12 | 0 | 0 | 0 | 0 | OK |
| 139 | sample-data | `20260722_13_monorail_kikugaoka_kokura` | 12 | 小倉線 | 12/12 | 0 | 0 | 0 | 0 | OK |
| 140 | sample-data | `20260723_01_sakura740` | 12 | 山陽新幹線 | 12/12 | 0 | 0 | 0 | 12 | OK |
| 141 | sample-data | `20260723_02_shiokaze5` | 12 | 宇野線 → 本四備讃線 | 12/12 | 0 | 0 | 0 | 1 | OK |
| 142 | sample-data | `20260723_03_ishizuchi10` | 2 | 予讃線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 143 | sample-data | `20260723_04_kotoku_local_takamatsu_ritsurin` | 3 | 高徳線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 144 | sample-data | `20260723_05_uzushio10` | 1 | 高徳線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 145 | sample-data | `20260724_01_ishizuchi9` | 2 | 予讃線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 146 | sample-data | `20260724_02_nanpu9` | 13 | 予讃線 → 土讃線 | 13/13 | 0 | 0 | 0 | 0 | OK |
| 147 | sample-data | `20260724_03_tsurugisan6` | 3 | 徳島線 | 2/3 | 0 | 5389 | 0 | 5 | OK (A: 阿波池田→阿波加茂 土讃線+徳島線) |
| 148 | sample-data | `20260724_04_tokushima_local_463d` | 4 | 徳島線 → 土讃線 | 4/4 | 0 | 0 | 0 | 5 | OK |
| 149 | sample-data | `20260724_05_nanpu17` | 23 | 土讃線 | 23/23 | 0 | 0 | 0 | 64 | OK |
| 150 | sample-data | `20260724_06_nanpu28` | 48 | 土讃線 → 予讃線 → 本四備讃線 → 宇野線 | 48/48 | 0 | 0 | 0 | 64 | OK |
| 151 | sample-data | `20260724_07_kodama970` | 2 | 山陽新幹線 | 2/2 | 0 | 0 | 0 | 6 | OK |
| 152 | sample-data | `20260724_08_tosaden_south` | 3 | 駅前線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 153 | sample-data | `20260724_09_tosaden_north` | 3 | 駅前線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 154 | sample-data | `20260725_05_hikari706` | 7 | 山陽新幹線 → 東海道新幹線 | 7/7 | 100 | 77 | 77 | 36 | OK |
| 155 | sample-data | `20260725_06_local` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 156 | sample-data | `20260726_01_local_numazu` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 157 | sample-data | `20260726_02_local_mishima` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 158 | sample-data | `20260726_03_hikari706` | 3 | 東海道新幹線 | 3/3 | 0 | 76 | 76 | 28 | OK |
| 159 | sample-data | `20260726_04_chuo_rapid_shinjuku` | 9 | 東北線 → 中央線 | 9/9 | 0 | 0 | 0 | 26 | OK |
| 160 | sample-data | `20260726_05_chuo_rapid_tokyo` | 9 | 中央線 → 東北線 | 9/9 | 0 | 0 | 0 | 34 | OK |
| 161 | sample-data | `20260726_06_kodama_atami` | 4 | 東海道新幹線 | 4/4 | 0 | 0 | 0 | 28 | OK |
| 162 | sample-data | `20260726_07_odoriko` | 3 | 東海道線 | 3/3 | 79 | 101 | 101 | 375 | OK (D: 熱海 end, 375 m) |
| 163 | sample-data | `20260726_08_chuo_rapid_shinjuku2` | 9 | 東北線 → 中央線 | 9/9 | 0 | 0 | 0 | 26 | OK |
| 164 | sample-data | `20260726_09_shonan_shinjuku_yokohama` | 13 | 山手線 → 大崎支線 → 総武線 → 東海道線 | 13/13 | 0 | 5512 | 0 | 309 | OK (B: 品鶴線 drawn as 総武線) |
| 165 | sample-data | `20260727_01_tokaido_through_numazu` | 21 | 東海道線 | 21/21 | 1067 | 0 | 0 | 375 | OK drawn (C: 保土ヶ谷–東戸塚 ~200 m; D: 熱海 375 m) |
| 166 | sample-data | `20260727_02_local_mishima` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 167 | sample-data | `20260727_03_hikari702` | 3 | 東海道新幹線 | 3/3 | 0 | 76 | 76 | 28 | OK |
| 168 | sample-data | `20260727_04_nasuno259` | 2 | 東北新幹線 | 2/2 | 0 | 0 | 0 | 33 | OK |
| 169 | sample-data | `20260727_05_komachi` | 2 | 東北新幹線 | 2/2 | 0 | 0 | 0 | 33 | OK |
| 170 | sample-data | `20260727_06_local_akihabara` | 2 | 東北線 | 2/2 | 0 | 0 | 0 | 26 | OK |
| 171 | sample-data | `20260727_07_local_tokyo` | 2 | 東北線 | 2/2 | 0 | 0 | 0 | 26 | OK |
| 172 | sample-data | `20260727_08_narita_express` | 1 | 総武線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 173 | sample-data | `20260727_09_kodama837` | 4 | 東海道新幹線 | 4/4 | 0 | 0 | 0 | 6 | OK |
| 174 | sample-data | `20260727_10_local_numazu` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 175 | sample-data | `20260728_01_local_mishima` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 176 | sample-data | `20260728_02_kodama829` | 4 | 東海道新幹線 | 4/4 | 0 | 0 | 0 | 3 | OK |
| 177 | sample-data | `20260728_03_entetsu_sukenobu` | 4 | 鉄道線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 178 | sample-data | `20260728_04_entetsu_return` | 4 | 鉄道線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 179 | sample-data | `20260728_05_kodama834` | 4 | 東海道新幹線 | 4/4 | 0 | 0 | 0 | 3 | OK |
| 180 | sample-data | `20260728_06_local_numazu` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 181 | sample-data | `20260729_01_local_mishima` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 182 | sample-data | `20260729_02_kodama840` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 183 | sample-data | `20260729_03_kodama911` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 184 | sample-data | `20260729_04_local_numazu` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 185 | sample-data | `20260729_05_sunrise_izumo` | 13 | 東海道線 → 山陽線 → 伯備線 → 山陰線 | 11/13 | 1683 | 42490 | 78 | 143 | OK (A: 浜松→姫路 東海道線+山陽線, 新見→米子 伯備線+山陰線; C: 岡山–倉敷) |
| 186 | sample-data | `20260730_01_ichibata_taisha` | 4 | 大社線 | 4/4 | 0 | 0 | 0 | 15 | OK |
| 187 | sample-data | `20260730_02_ichibata_kitamatsue` | 4 | 北松江線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 188 | sample-data | `20260730_03_yakumo22` | 7 | 山陰線 → 伯備線 → 山陽線 | 6/7 | 1683 | 50 | 0 | 143 | OK (A: 米子→新見; C: 倉敷–岡山 ~110 m) |
| 189 | sample-data | `20260730_04_sakura762` | 1 | 山陽新幹線 | 1/1 | 103 | 102 | 0 | 29 | OK |
| 190 | sample-data | `20260730_05_shinkaisoku_osaka` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 3 | OK |
| 191 | sample-data | `20260730_06_osaka_loop` | 8 | 大阪環状線 | 8/8 | 0 | 0 | 0 | 1 | OK |
| 192 | sample-data | `20260730_07_nankai_sakai` | 8 | 南海本線 | 8/8 | 0 | 0 | 0 | 0 | OK |
| 193 | sample-data | `20260731_01_nankai_shinimamiya` | 8 | 南海本線 | 8/8 | 0 | 0 | 0 | 0 | OK |
| 194 | sample-data | `20260731_02_rapit_alpha3` | 4 | 南海本線 → 空港線 | 4/4 | 0 | 106 | 0 | 20 | OK |
| 195 | sample-data | `20260731_03_yui_naha_akamine` | 1 | 沖縄都市モノレール線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 196 | sample-data | `20260731_04_yui_akamine_naha` | 1 | 沖縄都市モノレール線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 197 | sample-data | `20260731_05_yui_tedako_shuri` | 4 | 沖縄都市モノレール線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 198 | sample-data | `20260731_06_yui_shuri_miebashi` | 7 | 沖縄都市モノレール線 | 7/7 | 0 | 0 | 0 | 1 | OK |
| 199 | sample-data | `20260731_07_yui_miebashi_naha` | 7 | 沖縄都市モノレール線 | 7/7 | 0 | 0 | 0 | 0 | OK |
| 200 | sample-data | `20260731_08_yui_naha_miebashi` | 7 | 沖縄都市モノレール線 | 7/7 | 0 | 0 | 0 | 0 | OK |
| 201 | sample-data | `20260801_01_yui_miebashi_naha` | 7 | 沖縄都市モノレール線 | 7/7 | 0 | 0 | 0 | 0 | OK |
| 202 | new-year-grand-loop-data | `new_year_grand_loop_20251231_01` | 4 | 常磐線 | 4/4 | 0 | 0 | 0 | 5 | OK |
| 203 | new-year-grand-loop-data | `new_year_grand_loop_20251231_02` | 14 | 常磐線 | 14/14 | 0 | 0 | 0 | 10 | OK |
| 204 | new-year-grand-loop-data | `new_year_grand_loop_20251231_03` | 15 | 水戸線 | 15/15 | 0 | 0 | 0 | 3 | OK |
| 205 | new-year-grand-loop-data | `new_year_grand_loop_20251231_04` | 21 | 両毛線 → 上越線 | 21/21 | 636 | 0 | 0 | 192 | OK drawn (C: 思川–栃木 ~190 m for 0.6 km) |
| 206 | new-year-grand-loop-data | `new_year_grand_loop_20251231_05` | 18 | 高崎線 | 18/18 | 0 | 0 | 0 | 1 | OK |
| 207 | new-year-grand-loop-data | `new_year_grand_loop_20251231_06` | 5 | 川越線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 208 | new-year-grand-loop-data | `new_year_grand_loop_20251231_07` | 13 | 川越線 → 八高線 | 13/13 | 0 | 0 | 0 | 1 | OK |
| 209 | new-year-grand-loop-data | `new_year_grand_loop_20251231_08` | 4 | 横浜線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 210 | new-year-grand-loop-data | `new_year_grand_loop_20251231_09` | 17 | 相模線 | 17/17 | 0 | 0 | 0 | 0 | OK |
| 211 | new-year-grand-loop-data | `new_year_grand_loop_20251231_10` | 3 | 東海道線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 212 | new-year-grand-loop-data | `new_year_grand_loop_20251231_11` | 14 | 根岸線 → 東海道線 | 14/14 | 0 | 0 | 0 | 30 | OK |
| 213 | new-year-grand-loop-data | `new_year_grand_loop_20251231_12` | 7 | 鶴見線 | 7/7 | 0 | 0 | 0 | 0 | OK |
| 214 | new-year-grand-loop-data | `new_year_grand_loop_20251231_13` | 4 | 南武線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 215 | new-year-grand-loop-data | `new_year_grand_loop_20251231_14` | 1 | 南武線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 216 | new-year-grand-loop-data | `new_year_grand_loop_20251231_15` | 4 | 東海道線 | 4/4 | 0 | 0 | 0 | 33 | OK |
| 217 | new-year-grand-loop-data | `new_year_grand_loop_20251231_16` | 2 | 総武線 | 1/2 | 0 | 5512 | 0 | 11 | OK (B: 品鶴線/横須賀線 corridor drawn as 総武線; A) |
| 218 | new-year-grand-loop-data | `new_year_grand_loop_20251231_17` | 19 | 南武線 | 19/19 | 0 | 0 | 0 | 4 | OK |
| 219 | new-year-grand-loop-data | `new_year_grand_loop_20251231_18` | 2 | 中央線 | 2/2 | 0 | 0 | 0 | 28 | OK |
| 220 | new-year-grand-loop-data | `new_year_grand_loop_20251231_19` | 7 | 武蔵野線 | 7/7 | 0 | 0 | 0 | 2 | OK |
| 221 | new-year-grand-loop-data | `new_year_grand_loop_20251231_20` | 6 | 東北線 | 6/6 | 0 | 0 | 0 | 10 | OK |
| 222 | new-year-grand-loop-data | `new_year_grand_loop_20251231_21` | 4 | 東北線 | 4/4 | 0 | 0 | 0 | 37 | OK |
| 223 | new-year-grand-loop-data | `new_year_grand_loop_20251231_22` | 15 | 武蔵野線 | 15/15 | 0 | 0 | 0 | 3 | OK |
| 224 | new-year-grand-loop-data | `new_year_grand_loop_20260101_23` | 9 | 総武線 | 9/9 | 0 | 0 | 0 | 6 | OK |
| 225 | new-year-grand-loop-data | `new_year_grand_loop_20260101_24` | 7 | 総武線 → 成田線 | 7/7 | 0 | 0 | 0 | 12 | OK |
| 226 | new-year-grand-loop-data | `new_year_grand_loop_20260101_25` | 13 | 成田線 | 13/13 | 0 | 0 | 0 | 704 | OK (D: display 成田線 stroke starts 700 m past 成田) |
| 227 | new-year-grand-loop-data | `new_year_grand_loop_20260101_26` | 10 | 総武線 | 10/10 | 0 | 0 | 0 | 2 | OK |
| 228 | new-year-grand-loop-data | `new_year_grand_loop_20260101_27` | 4 | 東金線 | 4/4 | 0 | 0 | 0 | 2 | OK |
| 229 | new-year-grand-loop-data | `new_year_grand_loop_20260101_28` | 6 | 外房線 | 6/6 | 0 | 0 | 0 | 12 | OK |
| 230 | new-year-grand-loop-data | `new_year_grand_loop_20260101_29` | 14 | 外房線 | 14/14 | 0 | 0 | 0 | 0 | OK |
| 231 | new-year-grand-loop-data | `new_year_grand_loop_20260101_30` | 20 | 内房線 | 20/20 | 0 | 0 | 0 | 12 | OK |
| 232 | new-year-grand-loop-data | `new_year_grand_loop_20260101_31` | 9 | 内房線 | 9/9 | 0 | 0 | 0 | 1 | OK |
| 233 | new-year-grand-loop-data | `new_year_grand_loop_20260101_32` | 17 | 京葉線 | 17/17 | 0 | 0 | 0 | 35 | OK |
| 234 | new-year-grand-loop-data | `new_year_grand_loop_20260101_33` | 4 | 総武線 | 3/4 | 0 | 0 | 0 | 13 | OK |
| 235 | new-year-grand-loop-data | `new_year_grand_loop_20260101_34` | 3 | 総武線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 236 | new-year-grand-loop-data | `new_year_grand_loop_20260101_35` | 1 | 東北線 | 1/1 | 0 | 0 | 0 | 19 | OK |
| 237 | new-year-grand-loop-data | `new_year_grand_loop_20260101_36` | 8 | 中央線 | 8/8 | 0 | 0 | 0 | 3 | OK |
| 238 | new-year-grand-loop-data | `new_year_grand_loop_20260101_37` | 10 | 山手線 → 東北線 | 10/10 | 0 | 0 | 0 | 12 | OK |
| 239 | new-year-grand-loop-data | `new_year_grand_loop_20260101_38` | 7 | 常磐線 | 7/7 | 0 | 0 | 0 | 3 | OK |
| 240 | new-year-grand-loop-data | `new_year_grand_loop_20260101_39` | 2 | 常磐線 | 2/2 | 0 | 0 | 0 | 6 | OK |
| 241 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_01` | 3 | 総武線 | 3/3 | 50 | 0 | 0 | 9 | OK |
| 242 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_02` | 4 | 東金線 | 4/4 | 0 | 0 | 0 | 2 | OK |
| 243 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_03` | 3 | 外房線 → 京葉線 | 3/3 | 0 | 0 | 0 | 35 | OK |
| 244 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_04` | 1 | 東海道線 | 1/1 | 0 | 3003 | 0 | 220 | OK drawn (C: ひたち drawn on surface 東海道線; N02 solved path on the 横須賀線 alignment, ≤220 m) |
| 245 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_05` | 3 | 東海道線 | 3/3 | 77 | 0 | 0 | 33 | OK |
| 246 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_06` | 3 | 東海道線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 247 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_07` | 17 | 相模線 | 17/17 | 0 | 0 | 0 | 0 | OK |
| 248 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_08` | 4 | 横浜線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 249 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_09` | 1 | 中央線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 250 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_10` | 2 | 中央線 | 2/2 | 0 | 0 | 0 | 28 | OK |
| 251 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_11` | 7 | 武蔵野線 | 7/7 | 0 | 0 | 0 | 2 | OK |
| 252 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_12` | 5 | 東北線 | 5/5 | 0 | 0 | 0 | 13 | OK |
| 253 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_13` | 1 | 東北線 | 1/1 | 50 | 0 | 0 | 0 | OK |
| 254 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_14` | 2 | 東北線 → 山手線 | 1/2 | 0 | 4281 | 0 | 0 | OK (A: 浦和→池袋 東北線+山手線(赤羽線)) |
| 255 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_15` | 2 | 総武線 | 1/2 | 52 | 7388 | 0 | 20 | OK (A: 新宿→錦糸町 中央線+総武線) |
| 256 | tokyo-limited-express-loop-data | `tokyo_limited_express_loop_20260529_16` | 7 | 総武線 | 7/7 | 0 | 0 | 0 | 2 | OK |
| 257 | sample-data-tw | `20260802_01_taoyuan_airport_mrt_express_t2_taipei` | 12 | 桃園機場捷運 | 12/12 | 0 | 0 | 0 | 1 | OK |
| 258 | sample-data-tw | `20260802_02_trtc_bl_taipei_main_ximen` | 1 | 板南線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 259 | sample-data-tw | `20260802_03_trtc_bl_ximen_zhongxiao_fuxing` | 4 | 板南線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 260 | sample-data-tw | `20260802_04_trtc_bl_zhongxiao_fuxing_ximen` | 4 | 板南線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 261 | sample-data-tw | `20260805_01_thsr_165_taipei_taichung` | 5 | 台灣高速鐵路 | 5/5 | 0 | 0 | 0 | 2 | OK |
| 262 | sample-data-tw | `20260805_02_tra_local_3262_xinwuri_taichung` | 4 | 臺中線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 263 | sample-data-tw | `20260806_01_tra_tze_chiang_3000_137_taichung_changhua` | 6 | 臺中線 | 6/6 | 0 | 0 | 0 | 1 | OK |
| 264 | sample-data-tw | `20260806_02_tra_local_2204_changhua_taichung` | 6 | 臺中線 | 6/6 | 0 | 0 | 0 | 1 | OK |
| 265 | sample-data-tw | `20260808_01_tra_tze_chiang_3000_191_taichung_chiayi` | 22 | 臺中線 → 縱貫線南段 | 22/22 | 0 | 0 | 0 | 1 | OK |
| 266 | sample-data-tw | `20260808_02_alsr_5_chiayi_alishan` | 16 | 阿里山線 → 神木線 | 16/16 | 0 | 0 | 0 | 434 | OK (D: 神木–阿里山 display 神木線 0.9 km shorter than solved path) |
| 267 | sample-data-tw | `20260808_03_alsr_120_alishan_shenmu` | 1 | 神木線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 268 | sample-data-tw | `20260808_04_alsr_121_shenmu_alishan` | 1 | 神木線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 269 | sample-data-tw | `20260809_02_alsr_zhushan_observation_alishan_zhushan` | 2 | 祝山線 | 2/2 | 0 | 0 | 0 | 54 | OK |
| 270 | sample-data-tw | `20260809_03_alsr_zhushan_observation_zhushan_alishan` | 2 | 祝山線 | 2/2 | 0 | 0 | 0 | 54 | OK |
| 271 | sample-data-tw | `20260809_01_alsr_8_alishan_chiayi` | 16 | 神木線 → 阿里山線 | 16/16 | 0 | 0 | 0 | 434 | OK (D: 阿里山–神木 display 神木線 0.9 km shorter than solved path) |
| 272 | sample-data-tw | `20260809_04_tra_tze_chiang_3000_125_chiayi_kaohsiung` | 29 | 縱貫線南段 | 29/29 | 0 | 0 | 0 | 3 | OK |
| 273 | sample-data-tw | `20260810_01_krtc_red_kaohsiung_gangshan_station` | 15 | 高雄捷運紅線 | 15/15 | 0 | 0 | 0 | 4 | OK |
| 274 | sample-data-tw | `20260810_02_krtc_red_gangshan_station_siaogang` | 24 | 高雄捷運紅線 | 24/24 | 0 | 0 | 0 | 4 | OK |
| 275 | sample-data-tw | `20260810_03_krtc_red_siaogang_sanduo` | 6 | 高雄捷運紅線 | 6/6 | 0 | 0 | 0 | 0 | OK |
| 276 | sample-data-tw | `20260810_04_krtc_red_sanduo_kaisyuan` | 2 | 高雄捷運紅線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 277 | sample-data-tw | `20260810_05_klrt_c3_counterclockwise_loop` | 38 | 高雄環狀輕軌 | 38/38 | 0 | 0 | 0 | 5 | OK |
| 278 | sample-data-tw | `20260810_06_krtc_red_kaisyuan_kaohsiung` | 5 | 高雄捷運紅線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 279 | sample-data-tw | `20260812_01_krtc_red_kaohsiung_zuoying` | 5 | 高雄捷運紅線 | 5/5 | 0 | 0 | 0 | 2 | OK |
| 280 | sample-data-tw | `20260812_02_thsr_826_zuoying_taipei` | 10 | 台灣高速鐵路 | 10/10 | 0 | 0 | 0 | 2 | OK |
| 281 | sample-data-tw | `20260812_03_tra_local_1208_taipei_keelung` | 10 | 縱貫線北段 | 10/10 | 0 | 0 | 0 | 13 | OK |
| 282 | sample-data-tw | `20260812_04_tra_local_4209_nuannuan_nangang` | 7 | 宜蘭線 → 縱貫線北段 | 7/7 | 0 | 0 | 0 | 13 | OK |
| 283 | sample-data-tw | `20260812_05_thsr_161_nangang_taipei` | 1 | 台灣高速鐵路 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 284 | sample-data-tw | `20260813_01_star_of_taiwan_round_island_loop` | 194 | 縱貫線北段 → 臺中線 → 縱貫線南段 → 屏東線 → 南迴線 → 臺東線 → 北迴線 → 宜蘭線 … | 194/194 | 0 | 0 | 0 | 13 | OK |
| 285 | sample-data-hk | `HK-SAMPLE-EAL-LOW` | 12 | 東鐵綫 | 12/12 | 0 | 0 | 0 | 0 | OK |
| 286 | sample-data-kr | `KR-SAMPLE-GYEONGBUKSEON` | 10 | 경북선 | 10/10 | 0 | 0 | 0 | 1 | OK |
| 287 | sample-data-mo | `MO-SAMPLE-MLM-TAIPA` | 11 | 氹仔線 | 11/11 | 0 | 0 | 0 | 0 | OK |

## 2. Fields the add-trip editor writes

The editor (`RideEditorView`, `NewTripView`, `StopEditorView`, `RouteSectionEditorView`) writes these fields:

- **Ride:** `number`, `number_en`, `train_type`, `vehicle_type`, `company`, `direction`, `date`, `region`, `visible`, the ridden flags (`ride_segment` per stop), `notes`, `origin`/`destination` and `route_sections`.
- **Each section:** `from`, `to`, both station codes, `line_names` and `operator_names`.
- **Each stop:** `name`, `n02_station_code`, `platform_number`, `arrival`, `departure`, `stop_type` and `ride_segment`.

Every ride has every key. Values are normalized by `app/scripts/samples/normalize-sample-fields.py`; a `--check` rerun reports all seven stores unchanged. Two changes in this pass:

- **Platforms:** `platform_number` is filled on 168 stops of 43 rides (70 in the first pass, 98 in the research pass), from the のりば column of the date-specific JR西日本 おでかけネット train pages already cited for their times. They were parsed from the raw page, not a summary. Each page's train number and timetable edition (JR時刻表 2026年07月号 or 08月号) were checked against the ride. いしづち9号 shares its page with しおかぜ9号; 高松 platform 7 belongs to いしづち9号, which is the only one of the two that serves 高松.
- **Section names:** 1,048 sections now carry `from`/`to` station names beside their codes, as the editor's section rows do. All 2,068 sections now share one shape.

Values still empty, and why:

| Field | Filled | Empty | Why empty |
|---|---|---|---|
| `number`, `number_en`, `train_type`, `company`, `date`, `region`, `visible` | 287 | 0 | |
| `direction` (up/down) | derived | n/a | Derived from the route by RailCore `TravelDirection`, which the app shows as arrows. It is not a data field to fill. The stored value matches that inference (112 up, 109 down, 2 内回り loop words). The 64 rides with no stored value are lines where the inference has no up/down convention. None was hand-filled. |
| 方面/headsign | user-entered | n/a | The 方面 label is the rider's own choice. It is kept only where the original record had one (54 rides, inside `number`, e.g. `普通（12:02 高崎行）`, `とさでん路面電車 桟橋方面`). None was invented. |
| `vehicle_type` | 122 | 165 | This pass added 108 from a parallel research pass grouped by operator: 37 from official pages (71 from Wikipedia, used where the official page refused automated fetches or doesn't name the stock). A value is filled only where the source shows one fleet for that service on the ride date. The other 165 rides: either several types run the service (はやぶさ E5/H5, ソニック 883/885, 京急, trams, mixed commuter fleets), the train couldn't be identified (踊り子 熱海→東京, the こだま846A ride's 新大阪–名古屋 leg), or no source covers it (JR東海 三島・沼津 locals, private-line locals). Candidates for each are listed in `sample-trips.sources.md`. **Left for the user: 165.** |
| `notes` | 67 | 220 | Optional. Used only for provenance and verification disclosures. |
| `route_sections` | 250 | 37 | Mostly limited-express rides whose lines the precompute infers per hop from the stops; 8 of the 37 are Tokyo-loop rides. An explicit section changed three solves for the worse (section 1), so these stay inferred, which is also what the editor writes when a user doesn't pick lines. |
| stop `platform_number` | 168 of 1,973 called stops | 1,805 | All 168 come from the のりば column of the date-specific JR西日本 おでかけネット train page for the ride, read from the raw HTML: 70 in the first pass and 98 in this one, across 43 rides (Shinkansen, はるか, しらさぎ, つるぎ, はくたか, やくも, サンライズ出雲, スーパーおき, 京都 locals). No other operator publishes a per-train or fixed-per-direction platform the research could fetch: jreast.co.jp refused fetches, and the JR九州, JR四国 and JR北海道 station pages don't number platforms per service. Stations where the page leaves the cell blank stay null. **Left for the user: 1,805.** |
| times at called stops | 1,301 of 1,973 called stops | 672 | Only recorded or date-valid official times are entered, and there is no backprojection. The 672 are intermediate stops of local, tram and metro rides that have no trip identity (315 JP, 280 new-year loop, 41 Tokyo loop), and the HK, KR and MO samples (13 + 11 + 12), where MTR, Korail and MLM publish headways only or nothing readable for the date. |

Unverified timetables, kept as recorded and disclosed in `notes`:

- なすの259, こまち and 踊り子: the July 2026 JR East edition is no longer served.
- こだま846A: the 新大阪–名古屋 leg was probably a different train.
- 長野電鉄 A特急: only the 2021 edition is available.
- KR 경북선.

## 3. Load performance

Pending: re-measurement from the data-perf build (route-cache acceptance and memory fixes) on the shared iPhone 17, on a separate bundle ID.
