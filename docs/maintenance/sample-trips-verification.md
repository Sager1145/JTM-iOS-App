# Bundled example trips: verification (2026-11-05)

Scope: the 287 bundled example rides: `app/data/train-store.json` (201 rides),
`train-store-tw` (28), `-hk`, `-kr` and `-mo` (1 each), plus
`special-samples/new-year-grand-loop.json` (39) and
`special-samples/tokyo-limited-express-loop.json` (16). Sources for the field
values are in `app/data/sample-trips.sources.md`. The example stores now use the app's own ride-store format and id scheme (`journey_` + 32 hex); the old descriptive ids are kept here for readability, and the old-to-new map is in `sample-trips.sources.md`.

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
| T1 | `rail-sections.json` (N02), 鹿児島線 折尾 | Two 鹿児島線 折尾 features share code 008707, about 300 m apart (130.7147 and 130.7116). The westbound solve from 折尾 runs 3.6 km east, then turns back. | `journey_6F379655E47131DD2F854B65A847B9F0` (`journey_6F379655E47131DD2F854B65A847B9F0`) 折尾→赤間 is solved as 23.8 km instead of about 16.7 km, which adds 7.2 km to statistics. The map drawing is correct, because the projection slices the display 鹿児島線. |
| T2 | `stations-kr.json` | 상주 (Sangju) is missing. Korail 무궁화호 on the 경북선 stops at 상주 and 함창, not at 백원 or 어등 (secondary sources are listed in `sample-trips.sources.md`). | The KR sample's stop list can't be corrected until 상주 exists. |
| T3 | `rail-sections.json` vs `jp-2025.json` | N02 track runs 80–220 m beside the display alignment on: 岡山–倉敷 (山陽線, 1.7 km), 豊栄–新潟 (白新線, 2.4 km), 保土ヶ谷–東戸塚 (1.1 km), 五稜郭 approaches (0.7 km), 思川–栃木 (0.6 km) and 東能代–秋田 (0.5 km). Between 新橋 and 品川, N02 models the JR East 東海道線 as one alignment on the 横須賀線 tracks; the display draws the surface 東海道線 up to 220 m away. 大鰐温泉–大館: up to 1.1 km apart. | Drawing is unaffected, because legs project onto display lines. Mileage and statistics follow N02. Rail Diagnostics captures are needed to decide which geometry is surveyed correctly (see 1.4). |
| T4 | `rail-sections.json`, 北陸線 鳩原 loop; 豊肥線 立野 switchback | N02 gives one track per direction: 敦賀→新疋田 takes the 6.6 km down track, not the 9.8 km up-track loop, and 立野 has no switchback. | `journey_65F43AE4739DB31208BF9295B6539472` (`journey_65F43AE4739DB31208BF9295B6539472`) is 3.2 km short, and the あそぼーい rides are 1.7 km short. Drawing is correct. |
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
| 1 | sample-data | `journey_A9554752F257CDA52831A6C0EED248AF` | 3 | 阪和線 → 大阪環状線 → 東海道線 | 2/3 | 0 | 34237 | 0 | 3 | OK (A: 関西空港→天王寺 = 関西空港線+阪和線) |
| 2 | sample-data | `journey_923A26BB27C37BDF1717F1E4F21D5AF2` | 11 | 東海道新幹線 | 11/11 | 0 | 0 | 0 | 36 | OK |
| 3 | sample-data | `journey_A3CFCBD90A222CC4066ACAF20A6C06C2` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 4 | sample-data | `journey_D7889CA9349256238A038E0045DE7D0D` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 5 | sample-data | `journey_4CB9E326EEC18D85989CEF90ACF970A1` | 4 | 東海道新幹線 | 4/4 | 0 | 0 | 0 | 6 | OK |
| 6 | sample-data | `journey_9EBA4C59A5675EBCE17BEBAC846CF2CA` | 3 | 本線 → 1号線浅草線 | 3/3 | 0 | 0 | 0 | 5 | OK |
| 7 | sample-data | `journey_C07243F8AADDB594384BBF1CC16C13EA` | 1 | 12号線大江戸線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 8 | sample-data | `journey_5C3BA9F2C1A8F58936EC22D01F4E22E2` | 4 | 6号線三田線 | 4/4 | 0 | 0 | 0 | 24 | OK |
| 9 | sample-data | `journey_09AC64CFCEE12C93E83510873DD6FEC1` | 7 | 4号線丸ノ内線 | 7/7 | 0 | 0 | 1016 | 17 | OK (B: 東京地下鉄 = 東京メトロ) |
| 10 | sample-data | `journey_EAACE466C535944D58A31E97A124CF0C` | 14 | 赤羽線 → 東北線 | 14/14 | 0 | 0 | 0 | 21 | OK |
| 11 | sample-data | `journey_F3AE731354D1EAA0C06B45E04BE9F302` | 30 | 東北線 → 赤羽線 → 山手線 → 大崎支線 → 総武線 → 東海道線 | 30/30 | 0 | 5512 | 0 | 502 | OK (B: 品鶴線 drawn as 総武線; D: 394 m snap at 大崎) |
| 12 | sample-data | `journey_9F1B97EDB6DCD7A4DB1908060F60E180` | 1 | 根岸線 | 1/1 | 0 | 0 | 0 | 4 | OK |
| 13 | sample-data | `journey_2840A4D4E48F45ECA2F36BE4ED5C5E2A` | 2 | みなとみらい21線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 14 | sample-data | `journey_595FE5006ED23F7B331795A1C3A877E9` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 26 | OK |
| 15 | sample-data | `journey_1BF192064CE880673A0BB314C77436DB` | 3 | 横浜線 | 3/3 | 0 | 0 | 0 | 2 | OK |
| 16 | sample-data | `journey_5DDC220B564315ABDE363017D45930D6` | 3 | 東海道新幹線 | 3/3 | 0 | 0 | 0 | 6 | OK |
| 17 | sample-data | `journey_A6980FF0C00F952ADEA44DB6724A69A7` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 18 | sample-data | `journey_45B9E5DDA1ACD772D91C5332674B66F6` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 19 | sample-data | `journey_7ED510CE68E0BE81303D118A1B9E3575` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 20 | sample-data | `journey_DAE47A568594FC62E600A5F695EB7365` | 10 | 東北線 → 中央線 | 10/10 | 0 | 0 | 0 | 34 | OK |
| 21 | sample-data | `journey_588AB2A1A40723D13732520638875B90` | 5 | 中央線 | 5/5 | 0 | 0 | 0 | 21 | OK |
| 22 | sample-data | `journey_B6AC22131D2441B90E2E47880C035680` | 2 | 8号線有楽町線 | 2/2 | 0 | 0 | 626 | 3 | OK (B: 東京地下鉄 = 東京メトロ) |
| 23 | sample-data | `journey_A6900040ECB7DC73804CD885E0C55A77` | 3 | 8号線有楽町線 | 3/3 | 0 | 0 | 422 | 0 | OK (B: 東京地下鉄 = 東京メトロ) |
| 24 | sample-data | `journey_2421C1DE7244064D1E03E50A9E4A1707` | 8 | 山手線 → 東北線 | 8/8 | 0 | 0 | 0 | 12 | OK |
| 25 | sample-data | `journey_5D02E4142B00032F153A4A2DF85B955D` | 9 | 東北新幹線 | 9/9 | 0 | 0 | 0 | 6 | OK |
| 26 | sample-data | `journey_E7BA8AD080B2F29F785AC451F915075F` | 12 | 東北新幹線 | 12/12 | 0 | 0 | 0 | 5 | OK |
| 27 | sample-data | `journey_290DDF7BAF84271A16574A1D9669181F` | 6 | 奥羽線 | 6/6 | 535 | 0 | 0 | 1120 | OK drawn (C: 大鰐温泉–大館 solved path up to 1.1 km off display; 東能代–秋田 535 m) |
| 28 | sample-data | `journey_03F366E23A32B262DDDA6774510A20D4` | 15 | 羽越線 → 白新線 | 15/15 | 2371 | 0 | 0 | 138 | OK drawn (C: 豊栄–新潟 solved path ~140 m beside display for 2.4 km) |
| 29 | sample-data | `journey_F977C83D37F1F33106F63344B048477F` | 6 | 上越新幹線 | 6/6 | 0 | 0 | 0 | 3 | OK |
| 30 | sample-data | `journey_B3210B8E26A09DDE4055CBC06E62E202` | 5 | 北陸新幹線 | 5/5 | 0 | 0 | 0 | 2 | OK |
| 31 | sample-data | `journey_AD986EA2AE199842C86F1FE0C72C1F98` | 4 | 信越線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 32 | sample-data | `journey_410D06F4D03FC76877879DC916484BBC` | 4 | 信越線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 33 | sample-data | `journey_5214DDD3F5A2C014BA41D682C8847138` | 12 | 長野線 | 12/12 | 0 | 0 | 0 | 0 | OK |
| 34 | sample-data | `journey_3741AFAFFD9A67394E057294ACF48B00` | 2 | 長野線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 35 | sample-data | `journey_55DB5F0FE70F752721E67BA029168A20` | 9 | 北陸新幹線 | 9/9 | 0 | 0 | 0 | 1 | OK |
| 36 | sample-data | `journey_74236A39F500AA7027A8F519567B952B` | 4 | 北陸新幹線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 37 | sample-data | `journey_65F43AE4739DB31208BF9295B6539472` | 11 | 北陸線 | 11/11 | 0 | 0 | 0 | 1018 | OK drawn (E: 鳩原 loop drawn; solved path on down track, 3.2 km short) |
| 38 | sample-data | `journey_F57EA63347F47F36D98DF654CBAFDA69` | 2 | 東海道新幹線 | 2/2 | 0 | 0 | 0 | 6 | OK |
| 39 | sample-data | `journey_FB79023EBDF3D810C09FBCE322F2B679` | 7 | 東海道新幹線 | 7/7 | 0 | 0 | 0 | 7 | OK |
| 40 | sample-data | `journey_059D25F92EEAD0E27416DA75021EFBB2` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 41 | sample-data | `journey_DC682B71ACE23212D62D87D4C371A5E1` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 42 | sample-data | `journey_E60A7D258F854777D4460EDFE961AE32` | 10 | 東海道新幹線 | 10/10 | 0 | 0 | 0 | 7 | OK |
| 43 | sample-data | `journey_80163C1B9EDB32F4644B6CED30B291F5` | 8 | 奈良線 | 8/8 | 0 | 0 | 0 | 4 | OK |
| 44 | sample-data | `journey_2C4B34CD53F9E78ECA8875BC1ABCD617` | 8 | 奈良線 | 8/8 | 0 | 0 | 0 | 4 | OK |
| 45 | sample-data | `journey_0488BA679E26E3DF7B20C50B61F5242A` | 3 | 東海道新幹線 | 3/3 | 0 | 0 | 0 | 6 | OK |
| 46 | sample-data | `journey_D04B2C63CEA86422F386166CABE2A3FB` | 7 | 東海道新幹線 | 7/7 | 0 | 0 | 0 | 7 | OK |
| 47 | sample-data | `journey_E0ABE3D84C386F12C84C5EBB53E9DB42` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 48 | sample-data | `journey_552CE7006F50D9DD20F7EFB7B0B91BA8` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 49 | sample-data | `journey_1CB70EB6BDEE3E624E5E990D2B1C00FB` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 50 | sample-data | `journey_FD6353765B0036EFBE30A6B9D31CE9D3` | 2 | 東北新幹線 | 2/2 | 0 | 0 | 0 | 33 | OK |
| 51 | sample-data | `journey_6C38BB258FF7BBA93CB1A6C6284BC9C4` | 5 | 東北線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 52 | sample-data | `journey_5DD4E6CA03675E3FA6AC32063B33E078` | 5 | 東北線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 53 | sample-data | `journey_1EAE35C4A37558CFA7DD681330411832` | 15 | 上越新幹線 → 北陸新幹線 | 15/15 | 0 | 0 | 0 | 2 | OK |
| 54 | sample-data | `journey_7A3B8940A7731646F2E0DB38A8C89C21` | 15 | 北陸新幹線 → 上越新幹線 | 15/15 | 0 | 0 | 0 | 2 | OK |
| 55 | sample-data | `journey_0F013B23352B2D55E622E87E2E8E1DB4` | 14 | 東北線 → 赤羽線 | 14/14 | 0 | 0 | 0 | 13 | OK |
| 56 | sample-data | `journey_8AD20CEBC2F4E010D786EA9CEE066ABE` | 17 | 池袋線 | 17/17 | 0 | 0 | 0 | 2 | OK |
| 57 | sample-data | `journey_37EBEBB6809CFBA2C08E96855F63306A` | 2 | 狭山線 | 2/2 | 0 | 0 | 0 | 1 | OK |
| 58 | sample-data | `journey_99AFD75780558F89BFB7FC505A282831` | 6 | 武蔵野線 | 6/6 | 0 | 0 | 0 | 2 | OK |
| 59 | sample-data | `journey_F9ABBBD9EF93833A99D5F678570D5898` | 2 | 池袋線 | 2/2 | 0 | 0 | 0 | 1 | OK |
| 60 | sample-data | `journey_025A9A2E73804710C0A0544D46DA840F` | 2 | 狭山線 | 2/2 | 0 | 0 | 0 | 1 | OK |
| 61 | sample-data | `journey_3D6CBC5295CE31F009A715F0A483EDF5` | 4 | 狭山線 → 池袋線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 62 | sample-data | `journey_578784BBC21BEB37C6BCDB3F75623287` | 6 | 武蔵野線 | 6/6 | 0 | 0 | 0 | 2 | OK |
| 63 | sample-data | `journey_AEDF22100651041F822E1DFD54EC4653` | 16 | 東北線 | 16/16 | 0 | 0 | 0 | 37 | OK |
| 64 | sample-data | `journey_D67EA61A2C641A02967314209A67C0A5` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 65 | sample-data | `journey_660F1956DE6A9A62DB219B218967D58C` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 66 | sample-data | `journey_10CEA8306C1111A9244968C8560B886D` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 67 | sample-data | `journey_5515D04C2ECC7C28FC099F7E25093E2D` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 68 | sample-data | `journey_4DBADC9CC0B33FDC9F5E0DA527EC5AA0` | 25 | 東北新幹線 → 北海道新幹線 | 25/25 | 0 | 0 | 0 | 33 | OK |
| 69 | sample-data | `journey_7FDB2E2A33B27404C1C8198B3C2B29F8` | 11 | 函館線 → 室蘭線 → 千歳線 → 函館線 | 9/11 | 51 | 5290 | 0 | 55 | OK (A: 苫小牧→南千歳 室蘭線+千歳線; 新札幌→札幌 千歳線+函館線) |
| 70 | sample-data | `journey_43D90DF84B5E40D6304EC290E8ED4E74` | 11 | 函館線 → 千歳線 → 石勝線 → 根室線 | 10/11 | 51 | 1178 | 0 | 0 | OK (A: 札幌→新札幌 函館線+千歳線) |
| 71 | sample-data | `journey_318CA3E19DF94AF4005322F937025412` | 16 | 根室線 | 16/16 | 0 | 0 | 0 | 0 | OK |
| 72 | sample-data | `journey_4404D8979CD787663FD77A73C2572D0C` | 16 | 根室線 | 16/16 | 0 | 0 | 0 | 0 | OK |
| 73 | sample-data | `journey_F6F27BD3CBEFAA23FC0956F049DED550` | 7 | 根室線 → 石勝線 → 千歳線 → 函館線 | 6/7 | 51 | 5290 | 0 | 0 | OK (A: 新札幌→札幌 千歳線+函館線) |
| 74 | sample-data | `journey_32E525B07148EE19DC4F3B99A36535ED` | 16 | 函館線 → 宗谷線 | 16/16 | 52 | 51 | 0 | 49 | OK |
| 75 | sample-data | `journey_10F4EC2286758F85D709118AAFA6260E` | 14 | 宗谷線 → 函館線 | 14/14 | 77 | 51 | 0 | 49 | OK |
| 76 | sample-data | `journey_8B59A27F6F916CAE6A525B4F32488204` | 2 | 南北線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 77 | sample-data | `journey_17CC2EDF6C8FBBE0584149B2BADE9D7B` | 2 | 南北線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 78 | sample-data | `journey_FF43AD962224E5B60A731748776A27EB` | 4 | 山鼻線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 79 | sample-data | `journey_5AB6DC7EDCD13272F4DD08F0EEEDDDB5` | 4 | 都心線 → 1条線 | 4/4 | 0 | 0 | 0 | 21 | OK |
| 80 | sample-data | `journey_97A52E47E661D43859B9236D25ECE603` | 1 | 東西線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 81 | sample-data | `journey_B9B2EB9096BA7E1B096FCF563147469F` | 1 | 南北線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 82 | sample-data | `journey_8BADA44ED18197CDFA42A2D89B3028F1` | 14 | 函館線 → 千歳線 → 室蘭線 → 函館線 | 12/14 | 683 | 1178 | 0 | 120 | OK (A: 札幌→新札幌, 南千歳→苫小牧; C: 五稜郭 approach ~120 m) |
| 83 | sample-data | `journey_A51DFF674B84CF19A725723E186BE42B` | 8 | 湯の川線 → 大森線 | 8/8 | 0 | 0 | 0 | 0 | OK |
| 84 | sample-data | `journey_0CD36C937D37303F9498C53BF7B42430` | 5 | 本線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 85 | sample-data | `journey_9D02C3A9C9EC22156727EE34EF3EECD9` | 5 | 函館線 | 5/5 | 682 | 0 | 0 | 120 | OK drawn (C: 五稜郭–桔梗 ~120 m for 0.7 km) |
| 86 | sample-data | `journey_915349569139B316338DF97618D6F773` | 5 | 北海道新幹線 → 東北新幹線 | 5/5 | 0 | 0 | 0 | 1 | OK |
| 87 | sample-data | `journey_024B5864D9989D220DE5C73F0EAE833F` | 2 | 東北新幹線 | 2/2 | 0 | 0 | 0 | 1 | OK |
| 88 | sample-data | `journey_440A0D15C84B56D9F16C5EB444C9E5B1` | 1 | 奥羽線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 89 | sample-data | `journey_81234AF32797B453C451E437222D2E60` | 1 | 奥羽線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 90 | sample-data | `journey_8B77161CDFB6C2A3CCCE5B7C674FF523` | 5 | 東北新幹線 | 5/5 | 0 | 0 | 0 | 1 | OK |
| 91 | sample-data | `journey_596792300B91ACEAE52DDC2FF9D11D2E` | 17 | 東北新幹線 | 17/17 | 0 | 0 | 0 | 33 | OK |
| 92 | sample-data | `journey_969009740BE6241F5DEEE35BD8CAA7BA` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 93 | sample-data | `journey_119A68426CA3EE502CDB96C972B317D4` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 94 | sample-data | `journey_DDD0A86A0B072018582A3CED0998B99D` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 95 | sample-data | `journey_9409400F1A9EC5DA6CDB7FFBD64EBE2D` | 7 | 東海道新幹線 | 7/7 | 0 | 0 | 0 | 7 | OK |
| 96 | sample-data | `journey_C60F2E6092D87D9F5F85243B93428D5E` | 7 | 東海道新幹線 → 山陽新幹線 | 7/7 | 51 | 77 | 77 | 36 | OK |
| 97 | sample-data | `journey_9B1957E8CA2CA62A34EEBFC519E64422` | 6 | 山陽線 → 伯備線 | 5/6 | 1683 | 4364 | 0 | 143 | OK (A: 根雨→米子 伯備線+山陰線; C: 岡山–倉敷 ~110 m) |
| 98 | sample-data | `journey_55E89F3BE5BD16BC06291B252CFFA81B` | 18 | 山陰線 → 山口線 | 18/18 | 0 | 0 | 0 | 4 | OK |
| 99 | sample-data | `journey_CE6CDD905BB6708E69DD82011EB8182B` | 3 | 山陽新幹線 | 3/3 | 0 | 0 | 0 | 8 | OK |
| 100 | sample-data | `journey_76C5FA48675C931CCDE2EB71E9A05658` | 8 | 本線 → 宇品線 | 8/8 | 0 | 0 | 0 | 35 | OK |
| 101 | sample-data | `journey_AEF095A24CF065375213A5A9A0AC163A` | 2 | 広島新交通1号線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 102 | sample-data | `journey_9F86A38C7DD4FAD1DB6894D4FD0118D1` | 16 | 本線 → 宮島線 | 16/16 | 0 | 0 | 0 | 1 | OK |
| 103 | sample-data | `journey_4B847D0A569A7FF0DFF0101FF69D5F0A` | 4 | 山陽線 | 4/4 | 0 | 0 | 0 | 14 | OK |
| 104 | sample-data | `journey_0D198248AFFDB230E7BBFF14146178C0` | 7 | 山陽新幹線 | 7/7 | 0 | 0 | 0 | 12 | OK |
| 105 | sample-data | `journey_54E586655BBD3609E653BC7290FA2B34` | 1 | 九州新幹線 | 1/1 | 0 | 0 | 0 | 1 | OK |
| 106 | sample-data | `journey_06EC08904789EE82E214ED3D28758DE5` | 4 | 長崎線 → 佐世保線 | 4/4 | 51 | 76 | 0 | 2 | OK |
| 107 | sample-data | `journey_71DD8854E028C292A3A8359556C3866B` | 10 | 西九州線 | 10/10 | 0 | 0 | 0 | 560 | OK (D: display 西九州線 ends 560 m short of MR 伊万里) |
| 108 | sample-data | `journey_082EA2B0A90F678FE1E8D274B729F9D4` | 19 | 西九州線 | 19/19 | 0 | 0 | 0 | 560 | OK (D: display 西九州線 ends 560 m short of MR 伊万里) |
| 109 | sample-data | `journey_B1AB45AE6B8B33C3A8CD8BC12BB07D33` | 27 | 西九州線 | 27/27 | 0 | 0 | 0 | 2 | OK |
| 110 | sample-data | `journey_FC8005E13BA7158E6129934006093962` | 24 | 佐世保線 → 大村線 → 長崎線 | 24/24 | 0 | 0 | 0 | 362 | OK (D: 早岐 switchback, display ends 362 m short) |
| 111 | sample-data | `journey_87D92EF0BAE97A00C634BA96DA890A46` | 8 | 本線 | 8/8 | 0 | 0 | 0 | 0 | OK |
| 112 | sample-data | `journey_08B980D1C7CB9F6CAD15CD060A45807F` | 5 | 本線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 113 | sample-data | `journey_AD59A05EAE440ED38AA3279A20557058` | 3 | 本線 | 3/3 | 0 | 0 | 0 | 1 | OK |
| 114 | sample-data | `journey_C9DEC0495C5FAE492C4FE858535C3E30` | 3 | 本線 | 3/3 | 0 | 0 | 0 | 1 | OK |
| 115 | sample-data | `journey_33CBB95F33F145A44996E104C7110877` | 4 | 西九州新幹線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 116 | sample-data | `journey_9E0FE255A29C5BBDEE31480F4AED2BE8` | 3 | 佐世保線 → 長崎線 | 3/3 | 51 | 76 | 0 | 2 | OK |
| 117 | sample-data | `journey_151F1405ADA1BC7794EB8C44CD7709C2` | 5 | 九州新幹線 | 5/5 | 0 | 0 | 0 | 3 | OK |
| 118 | sample-data | `journey_02C494EB5E72DE2FE0D3E5BC7D303309` | 5 | 豊肥線 | 5/5 | 0 | 0 | 0 | 950 | OK drawn (E: 立野 switchback drawn; solved path cuts it, 1.7 km short) |
| 119 | sample-data | `journey_71102CEF82BE99D98F5C7101CD080E07` | 5 | 豊肥線 | 5/5 | 0 | 0 | 0 | 950 | OK drawn (E: 立野 switchback drawn; solved path cuts it, 1.7 km short) |
| 120 | sample-data | `journey_425FC76FB050394D51554A9A2D6B369B` | 5 | 幹線 | 5/5 | 0 | 0 | 0 | 52 | OK |
| 121 | sample-data | `journey_8B16C03F0CFAADDD02FD4A3500661E2E` | 4 | 幹線 | 4/4 | 0 | 0 | 0 | 179 | OK (D: 水道町 stop 409 m from track; drawn stroke stops short) |
| 122 | sample-data | `journey_1100C5554DA23F0F99BBBD8F912CC604` | 4 | 豊肥線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 123 | sample-data | `journey_3B958DB027F701A9AFD801879294548F` | 7 | 豊肥線 | 7/7 | 0 | 0 | 0 | 1 | OK |
| 124 | sample-data | `journey_5E47ABA2FB7E3A6CC5F14CBCC010472D` | 5 | 九州新幹線 | 5/5 | 0 | 0 | 0 | 1 | OK |
| 125 | sample-data | `journey_A18C112CF65FF5C2AD464A2C3309FB24` | 18 | 指宿枕崎線 | 18/18 | 0 | 0 | 0 | 1 | OK |
| 126 | sample-data | `journey_B96A06031B5BCFDD1064C35D950BFB91` | 2 | 指宿枕崎線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 127 | sample-data | `journey_F497F768F6A74DE792D14B3DA43949F9` | 18 | 指宿枕崎線 | 18/18 | 0 | 0 | 0 | 1 | OK |
| 128 | sample-data | `journey_FF81EAF940C88B515459211A732AD78C` | 1 | 唐湊線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 129 | sample-data | `journey_61F39B7DCD1B8DFFC6688097802C44C8` | 2 | 指宿枕崎線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 130 | sample-data | `journey_45E72A351DEC6512AF96B89578A93E9A` | 9 | 鹿児島線 → 日豊線 | 9/9 | 0 | 0 | 0 | 24 | OK |
| 131 | sample-data | `journey_E9C359F48C7CC40ABC70DBD05B606CFA` | 10 | 日豊線 | 10/10 | 0 | 0 | 0 | 5 | OK |
| 132 | sample-data | `journey_6F379655E47131DD2F854B65A847B9F0` | 16 | 日豊線 → 鹿児島線 | 16/16 | 79 | 52 | 0 | 3409 | MILEAGE (F: solved path makes a 7.2 km out-and-back at 折尾; drawn stroke correct) |
| 133 | sample-data | `journey_31C35A5D2E003443D5E26D7654555B25` | 8 | 鹿児島線 | 8/8 | 79 | 77 | 0 | 25 | OK |
| 134 | sample-data | `journey_FEDC12334D0F270D498B929602534FA8` | 1 | 鹿児島線 | 1/1 | 0 | 0 | 0 | 10 | OK |
| 135 | sample-data | `journey_4BB3DDFC465CB6E4719AB69741432424` | 20 | 筑豊電気鉄道線 | 20/20 | 0 | 0 | 0 | 0 | OK |
| 136 | sample-data | `journey_FA2577CF26696BE8E3619FBC6FA06440` | 14 | 伊田線 | 14/14 | 0 | 0 | 0 | 7 | OK |
| 137 | sample-data | `journey_7DCFF106FEBEC9FBCFCB4EB3109885B8` | 12 | 日田彦山線 → 日豊線 | 12/12 | 0 | 0 | 0 | 5 | OK |
| 138 | sample-data | `journey_1B73B253ED48ADAE75E0A27CD5EDD87C` | 12 | 小倉線 | 12/12 | 0 | 0 | 0 | 0 | OK |
| 139 | sample-data | `journey_FA664788B3F334B952706589201D498B` | 12 | 小倉線 | 12/12 | 0 | 0 | 0 | 0 | OK |
| 140 | sample-data | `journey_BDD9F936F447CBF04C5075C26DA76C88` | 12 | 山陽新幹線 | 12/12 | 0 | 0 | 0 | 12 | OK |
| 141 | sample-data | `journey_CECE2010BC0D2F1EB19C89BFD5900CAD` | 12 | 宇野線 → 本四備讃線 | 12/12 | 0 | 0 | 0 | 1 | OK |
| 142 | sample-data | `journey_BEEF6E99345E6E5CD1F5B4AF369AC636` | 2 | 予讃線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 143 | sample-data | `journey_DFF892AFBEB679C6AA793A67226FF57C` | 3 | 高徳線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 144 | sample-data | `journey_771C696806C4705B412A265B953BD9A7` | 1 | 高徳線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 145 | sample-data | `journey_07E6AD25D8057D28D08088C1D40C2491` | 2 | 予讃線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 146 | sample-data | `journey_2A4BA95A7B92CB19921B27A2D3279C34` | 13 | 予讃線 → 土讃線 | 13/13 | 0 | 0 | 0 | 0 | OK |
| 147 | sample-data | `journey_510175D3C325909EF4C88C3A42E1108B` | 3 | 徳島線 | 2/3 | 0 | 5389 | 0 | 5 | OK (A: 阿波池田→阿波加茂 土讃線+徳島線) |
| 148 | sample-data | `journey_7607A5FC50F4ABA60EDB87451A5E0724` | 4 | 徳島線 → 土讃線 | 4/4 | 0 | 0 | 0 | 5 | OK |
| 149 | sample-data | `journey_D2D514AAEA06253635D51310E9C4C06B` | 23 | 土讃線 | 23/23 | 0 | 0 | 0 | 64 | OK |
| 150 | sample-data | `journey_6322F5578A2F139890D3B028ADDAF45A` | 48 | 土讃線 → 予讃線 → 本四備讃線 → 宇野線 | 48/48 | 0 | 0 | 0 | 64 | OK |
| 151 | sample-data | `journey_FBC327CBC341BD103BEEAE00FD568C91` | 2 | 山陽新幹線 | 2/2 | 0 | 0 | 0 | 6 | OK |
| 152 | sample-data | `journey_350E1BD8273A1E04690813FB31BF720C` | 3 | 駅前線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 153 | sample-data | `journey_0694D992D0F11AE81676A5DCDFBFD38D` | 3 | 駅前線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 154 | sample-data | `journey_C163CF0702200718E5E57A2BE6C21885` | 7 | 山陽新幹線 → 東海道新幹線 | 7/7 | 100 | 77 | 77 | 36 | OK |
| 155 | sample-data | `journey_E98005859D36F61CDF6C0BEDE09A3258` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 156 | sample-data | `journey_8888515C58457DCC681836C3325CE638` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 157 | sample-data | `journey_DEA753DDFBC0519639A0FECAA3242CC5` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 158 | sample-data | `journey_CD24799CE25B1CF61107969F8A30406F` | 3 | 東海道新幹線 | 3/3 | 0 | 76 | 76 | 28 | OK |
| 159 | sample-data | `journey_C03AE74555ED48DBCCA3989A84157CB7` | 9 | 東北線 → 中央線 | 9/9 | 0 | 0 | 0 | 26 | OK |
| 160 | sample-data | `journey_10321A2FDEF5906E4DCE8DB6986E3C03` | 9 | 中央線 → 東北線 | 9/9 | 0 | 0 | 0 | 34 | OK |
| 161 | sample-data | `journey_029F2E79178CF1AA008FB454C06992F7` | 4 | 東海道新幹線 | 4/4 | 0 | 0 | 0 | 28 | OK |
| 162 | sample-data | `journey_1C77A10398A5B717F5372522CD764D5F` | 3 | 東海道線 | 3/3 | 79 | 101 | 101 | 375 | OK (D: 熱海 end, 375 m) |
| 163 | sample-data | `journey_1F9D3D61F6C18F4BC2B202DC16B92231` | 9 | 東北線 → 中央線 | 9/9 | 0 | 0 | 0 | 26 | OK |
| 164 | sample-data | `journey_856C6D19621F1681AAF99048FEEAED8D` | 13 | 山手線 → 大崎支線 → 総武線 → 東海道線 | 13/13 | 0 | 5512 | 0 | 309 | OK (B: 品鶴線 drawn as 総武線) |
| 165 | sample-data | `journey_583C80C04E9545A24F3711263868E484` | 21 | 東海道線 | 21/21 | 1067 | 0 | 0 | 375 | OK drawn (C: 保土ヶ谷–東戸塚 ~200 m; D: 熱海 375 m) |
| 166 | sample-data | `journey_2445827DCEE24FDDD9BDAFF031574BF8` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 167 | sample-data | `journey_2634C4C2410DA151187D68ACC14F1201` | 3 | 東海道新幹線 | 3/3 | 0 | 76 | 76 | 28 | OK |
| 168 | sample-data | `journey_A83E8C0CD3219DDE9BDACE75633FE06B` | 2 | 東北新幹線 | 2/2 | 0 | 0 | 0 | 33 | OK |
| 169 | sample-data | `journey_8468CDB2F92CD8F1CB56D7175B261C34` | 2 | 東北新幹線 | 2/2 | 0 | 0 | 0 | 33 | OK |
| 170 | sample-data | `journey_5AB68AB4738C250255A82B17A485CD8E` | 2 | 東北線 | 2/2 | 0 | 0 | 0 | 26 | OK |
| 171 | sample-data | `journey_DD359818F2CA9B303F5EF5A05FCDA15D` | 2 | 東北線 | 2/2 | 0 | 0 | 0 | 26 | OK |
| 172 | sample-data | `journey_680A26B9C2D06FDE49DABFF6A02DF17C` | 1 | 総武線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 173 | sample-data | `journey_21B9459DC7DFD29026EE0E54B15BF121` | 4 | 東海道新幹線 | 4/4 | 0 | 0 | 0 | 6 | OK |
| 174 | sample-data | `journey_072BD550CC395E21A18FADA5A4255413` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 175 | sample-data | `journey_A50D14E9010F9184B45D3BD166A7488C` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 176 | sample-data | `journey_A4B7BCFE572DCF976943553B301BBF51` | 4 | 東海道新幹線 | 4/4 | 0 | 0 | 0 | 3 | OK |
| 177 | sample-data | `journey_7296C07F3881D0CAAF2DE8828D443471` | 4 | 鉄道線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 178 | sample-data | `journey_323ADE1BA38D637024FE37B30449D56E` | 4 | 鉄道線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 179 | sample-data | `journey_D34CC990A1B67E5BE0BA9D9730CA6916` | 4 | 東海道新幹線 | 4/4 | 0 | 0 | 0 | 3 | OK |
| 180 | sample-data | `journey_FD2B8C351E5D802CF873225C04133FB4` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 181 | sample-data | `journey_1539FA6CAEDB8148D507E34ED7D4D897` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 182 | sample-data | `journey_96B2EFFD4EC25479AFA91263963111A2` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 183 | sample-data | `journey_8C70A9CF2CB598C4C2ABDA2EAABCE0F5` | 5 | 東海道新幹線 | 5/5 | 0 | 0 | 0 | 28 | OK |
| 184 | sample-data | `journey_C1F3524AE95815918C6C76DA80E813CD` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 20 | OK |
| 185 | sample-data | `journey_F29762068C2DDB4CD79CF4AF30B29529` | 13 | 東海道線 → 山陽線 → 伯備線 → 山陰線 | 11/13 | 1683 | 42490 | 78 | 143 | OK (A: 浜松→姫路 東海道線+山陽線, 新見→米子 伯備線+山陰線; C: 岡山–倉敷) |
| 186 | sample-data | `journey_E97B57247FA4FAF2AD7C092FA6C78A0E` | 4 | 大社線 | 4/4 | 0 | 0 | 0 | 15 | OK |
| 187 | sample-data | `journey_1066A578B168E8867C0C2526F4C4918A` | 4 | 北松江線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 188 | sample-data | `journey_BB3AD8FEF0D118561F7FC4FA6227A5A6` | 7 | 山陰線 → 伯備線 → 山陽線 | 6/7 | 1683 | 50 | 0 | 143 | OK (A: 米子→新見; C: 倉敷–岡山 ~110 m) |
| 189 | sample-data | `journey_20A4F24136AEE7B83D1AD4A267C4DE85` | 1 | 山陽新幹線 | 1/1 | 103 | 102 | 0 | 29 | OK |
| 190 | sample-data | `journey_42081FC544A1354AECB52C9720DA202D` | 1 | 東海道線 | 1/1 | 0 | 0 | 0 | 3 | OK |
| 191 | sample-data | `journey_475F1E0ED575D680352459093F852ED6` | 8 | 大阪環状線 | 8/8 | 0 | 0 | 0 | 1 | OK |
| 192 | sample-data | `journey_95838C76BAA5FDF356AC92F8B54F802F` | 8 | 南海本線 | 8/8 | 0 | 0 | 0 | 0 | OK |
| 193 | sample-data | `journey_C409454EC8F3724E2ECD7CD942A27B3D` | 8 | 南海本線 | 8/8 | 0 | 0 | 0 | 0 | OK |
| 194 | sample-data | `journey_0DCC26B17610DE9969C200D26CBA75DE` | 4 | 南海本線 → 空港線 | 4/4 | 0 | 106 | 0 | 20 | OK |
| 195 | sample-data | `journey_A04D207B2E4D8CA4B9088FA6DF5BDD29` | 1 | 沖縄都市モノレール線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 196 | sample-data | `journey_959DFFAA45FED199E0FD06F93A12C93B` | 1 | 沖縄都市モノレール線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 197 | sample-data | `journey_EE957F00F2B8D8D291D4CD7EB1826810` | 4 | 沖縄都市モノレール線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 198 | sample-data | `journey_3A264FF820AE17659ADDD22FDDADB270` | 7 | 沖縄都市モノレール線 | 7/7 | 0 | 0 | 0 | 1 | OK |
| 199 | sample-data | `journey_B29C2B434D4A5E393447665740312185` | 7 | 沖縄都市モノレール線 | 7/7 | 0 | 0 | 0 | 0 | OK |
| 200 | sample-data | `journey_311418DF2394CCFFF6AA3C0151F0CB10` | 7 | 沖縄都市モノレール線 | 7/7 | 0 | 0 | 0 | 0 | OK |
| 201 | sample-data | `journey_2DB618BA4041AF100A4FB6C47DA4B27C` | 7 | 沖縄都市モノレール線 | 7/7 | 0 | 0 | 0 | 0 | OK |
| 202 | new-year-grand-loop-data | `journey_7866E65358DB80921D2614D5398FEEE1` | 4 | 常磐線 | 4/4 | 0 | 0 | 0 | 5 | OK |
| 203 | new-year-grand-loop-data | `journey_B9F7AF6F378531D710C6C4DB8A75FE84` | 14 | 常磐線 | 14/14 | 0 | 0 | 0 | 10 | OK |
| 204 | new-year-grand-loop-data | `journey_1F114EC77ED45EB89D68F1C32934755E` | 15 | 水戸線 | 15/15 | 0 | 0 | 0 | 3 | OK |
| 205 | new-year-grand-loop-data | `journey_5FAF02A78D0297BD7E6BC7189EEE5479` | 21 | 両毛線 → 上越線 | 21/21 | 636 | 0 | 0 | 192 | OK drawn (C: 思川–栃木 ~190 m for 0.6 km) |
| 206 | new-year-grand-loop-data | `journey_8B370FD51DD05BF218108C28B207147C` | 18 | 高崎線 | 18/18 | 0 | 0 | 0 | 1 | OK |
| 207 | new-year-grand-loop-data | `journey_C83F01E4FC0FB070B439E1F554DDB2E3` | 5 | 川越線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 208 | new-year-grand-loop-data | `journey_19E72EF8A279F9BEA3E43507CFD262B8` | 13 | 川越線 → 八高線 | 13/13 | 0 | 0 | 0 | 1 | OK |
| 209 | new-year-grand-loop-data | `journey_B1081E3920E5817960D57445107E8518` | 4 | 横浜線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 210 | new-year-grand-loop-data | `journey_1C50841EDDE0B8259BF3CD6982B04968` | 17 | 相模線 | 17/17 | 0 | 0 | 0 | 0 | OK |
| 211 | new-year-grand-loop-data | `journey_DC35D009289BDAA8CE95542D519A2D3C` | 3 | 東海道線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 212 | new-year-grand-loop-data | `journey_4DCB77A37D44B9E2340421841026E845` | 14 | 根岸線 → 東海道線 | 14/14 | 0 | 0 | 0 | 30 | OK |
| 213 | new-year-grand-loop-data | `journey_73881D4AC6CDEB95F29753E8F861455B` | 7 | 鶴見線 | 7/7 | 0 | 0 | 0 | 0 | OK |
| 214 | new-year-grand-loop-data | `journey_E5271380AA0BE6E27DCB2F8E8D465275` | 4 | 南武線 | 4/4 | 0 | 0 | 0 | 0 | OK |
| 215 | new-year-grand-loop-data | `journey_5A7792A36B7AFBF89C4188A3AF6AB319` | 1 | 南武線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 216 | new-year-grand-loop-data | `journey_74A2A9A828B6C4EA8C9EA2D4ACB5E5B1` | 4 | 東海道線 | 4/4 | 0 | 0 | 0 | 33 | OK |
| 217 | new-year-grand-loop-data | `journey_38D81E63FDF3CA29C2E2058E35C8A761` | 2 | 総武線 | 1/2 | 0 | 5512 | 0 | 11 | OK (B: 品鶴線/横須賀線 corridor drawn as 総武線; A) |
| 218 | new-year-grand-loop-data | `journey_D9EE58DC654F79D6E5D9B5AD1EE9222F` | 19 | 南武線 | 19/19 | 0 | 0 | 0 | 4 | OK |
| 219 | new-year-grand-loop-data | `journey_7E3B5F10D9F6347B6C726AEC1D57BA7A` | 2 | 中央線 | 2/2 | 0 | 0 | 0 | 28 | OK |
| 220 | new-year-grand-loop-data | `journey_56503D37265880A94FA191E1A470173B` | 7 | 武蔵野線 | 7/7 | 0 | 0 | 0 | 2 | OK |
| 221 | new-year-grand-loop-data | `journey_B39F46D813FA1636ED3CD36C7FA1358D` | 6 | 東北線 | 6/6 | 0 | 0 | 0 | 10 | OK |
| 222 | new-year-grand-loop-data | `journey_FD3D0B6540560EA9C1BD526322196797` | 4 | 東北線 | 4/4 | 0 | 0 | 0 | 37 | OK |
| 223 | new-year-grand-loop-data | `journey_D878F62C43D5A7C64B14222B73FD4CD0` | 15 | 武蔵野線 | 15/15 | 0 | 0 | 0 | 3 | OK |
| 224 | new-year-grand-loop-data | `journey_CBC698EF40ADC4349BF9FE4E96A022BA` | 9 | 総武線 | 9/9 | 0 | 0 | 0 | 6 | OK |
| 225 | new-year-grand-loop-data | `journey_B3F161407E8E14E91AF8646028705859` | 7 | 総武線 → 成田線 | 7/7 | 0 | 0 | 0 | 12 | OK |
| 226 | new-year-grand-loop-data | `journey_5F1433ABC14572422C3B891B334CCB7E` | 13 | 成田線 | 13/13 | 0 | 0 | 0 | 704 | OK (D: display 成田線 stroke starts 700 m past 成田) |
| 227 | new-year-grand-loop-data | `journey_E3C5A17962C2DDAE1DCC23DDE0AA3C1A` | 10 | 総武線 | 10/10 | 0 | 0 | 0 | 2 | OK |
| 228 | new-year-grand-loop-data | `journey_8DFA7F87666D8581074D297024482EF1` | 4 | 東金線 | 4/4 | 0 | 0 | 0 | 2 | OK |
| 229 | new-year-grand-loop-data | `journey_813F6AB74D714CCD2B098529CC5D7785` | 6 | 外房線 | 6/6 | 0 | 0 | 0 | 12 | OK |
| 230 | new-year-grand-loop-data | `journey_1D251A826357268B527F63C503905C1C` | 14 | 外房線 | 14/14 | 0 | 0 | 0 | 0 | OK |
| 231 | new-year-grand-loop-data | `journey_0FEE4DC2B4589497ABD4E35742C65942` | 20 | 内房線 | 20/20 | 0 | 0 | 0 | 12 | OK |
| 232 | new-year-grand-loop-data | `journey_F3236E4E4DBC6C24A60FCFF8CF8FD52D` | 9 | 内房線 | 9/9 | 0 | 0 | 0 | 1 | OK |
| 233 | new-year-grand-loop-data | `journey_70220CF57D13FED0E93F34B981914A11` | 17 | 京葉線 | 17/17 | 0 | 0 | 0 | 35 | OK |
| 234 | new-year-grand-loop-data | `journey_07159EDCA041241C5F7038F2DF87F3F4` | 4 | 総武線 | 3/4 | 0 | 0 | 0 | 13 | OK |
| 235 | new-year-grand-loop-data | `journey_4D8504078E1EDCDDD6273B29F6C844F1` | 3 | 総武線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 236 | new-year-grand-loop-data | `journey_48A839FEAF8AAB049FE99B5BFEB83C01` | 1 | 東北線 | 1/1 | 0 | 0 | 0 | 19 | OK |
| 237 | new-year-grand-loop-data | `journey_92A88D23E58F169A02F66FA4131F9CF4` | 8 | 中央線 | 8/8 | 0 | 0 | 0 | 3 | OK |
| 238 | new-year-grand-loop-data | `journey_5D0B999496F4E95DC91A57FB2FACD2BF` | 10 | 山手線 → 東北線 | 10/10 | 0 | 0 | 0 | 12 | OK |
| 239 | new-year-grand-loop-data | `journey_FDB4DA52F28136A256951A235E9FF713` | 7 | 常磐線 | 7/7 | 0 | 0 | 0 | 3 | OK |
| 240 | new-year-grand-loop-data | `journey_EA71B8D43807377F6733B3ECD2AF3A39` | 2 | 常磐線 | 2/2 | 0 | 0 | 0 | 6 | OK |
| 241 | tokyo-limited-express-loop-data | `journey_FB378E723A1A1C6D845DDBF2F4EC7B80` | 3 | 総武線 | 3/3 | 50 | 0 | 0 | 9 | OK |
| 242 | tokyo-limited-express-loop-data | `journey_FCF5080D6BF57735BD6B550726AEBCC2` | 4 | 東金線 | 4/4 | 0 | 0 | 0 | 2 | OK |
| 243 | tokyo-limited-express-loop-data | `journey_AE4B3D6ECECDF1F02B9D88E33DB71D35` | 3 | 外房線 → 京葉線 | 3/3 | 0 | 0 | 0 | 35 | OK |
| 244 | tokyo-limited-express-loop-data | `journey_1367E2AD44FB1282A603082C6B023451` | 1 | 東海道線 | 1/1 | 0 | 3003 | 0 | 220 | OK drawn (C: ひたち drawn on surface 東海道線; N02 solved path on the 横須賀線 alignment, ≤220 m) |
| 245 | tokyo-limited-express-loop-data | `journey_B113D59026AE72C23BC7DCC1E062B3D9` | 3 | 東海道線 | 3/3 | 77 | 0 | 0 | 33 | OK |
| 246 | tokyo-limited-express-loop-data | `journey_8473C35D9B0263A67C1AE3CF2EF35F88` | 3 | 東海道線 | 3/3 | 0 | 0 | 0 | 0 | OK |
| 247 | tokyo-limited-express-loop-data | `journey_DBB4A436D118AFC963F3D76ACC6D7F5A` | 17 | 相模線 | 17/17 | 0 | 0 | 0 | 0 | OK |
| 248 | tokyo-limited-express-loop-data | `journey_A15A2CDA79EC2AB1DB648F12DECB9CFF` | 4 | 横浜線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 249 | tokyo-limited-express-loop-data | `journey_3C1174A1740BAC769A067CDF20A0CF5F` | 1 | 中央線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 250 | tokyo-limited-express-loop-data | `journey_DA0120B61DAC677C7FE9EFB54CF8F052` | 2 | 中央線 | 2/2 | 0 | 0 | 0 | 28 | OK |
| 251 | tokyo-limited-express-loop-data | `journey_346B51D9286011FC76E1B3066295219B` | 7 | 武蔵野線 | 7/7 | 0 | 0 | 0 | 2 | OK |
| 252 | tokyo-limited-express-loop-data | `journey_8EEEEA38327E98645C7007A692CCAD31` | 5 | 東北線 | 5/5 | 0 | 0 | 0 | 13 | OK |
| 253 | tokyo-limited-express-loop-data | `journey_5F07101A177600FAEAB79C27F00916AF` | 1 | 東北線 | 1/1 | 50 | 0 | 0 | 0 | OK |
| 254 | tokyo-limited-express-loop-data | `journey_D8755000FA24D4235A8ED889B3A4AA9C` | 2 | 東北線 → 山手線 | 1/2 | 0 | 4281 | 0 | 0 | OK (A: 浦和→池袋 東北線+山手線(赤羽線)) |
| 255 | tokyo-limited-express-loop-data | `journey_868731BF1A9520928B670EC3A3B8566D` | 2 | 総武線 | 1/2 | 52 | 7388 | 0 | 20 | OK (A: 新宿→錦糸町 中央線+総武線) |
| 256 | tokyo-limited-express-loop-data | `journey_E4ED0EC66250F2E663AEB7ECE1FA8F5A` | 7 | 総武線 | 7/7 | 0 | 0 | 0 | 2 | OK |
| 257 | sample-data-tw | `journey_5C3C741549CF09E20FE4CC4F7389B758` | 12 | 桃園機場捷運 | 12/12 | 0 | 0 | 0 | 1 | OK |
| 258 | sample-data-tw | `journey_48FE139478368C9C7274289E1D49510A` | 1 | 板南線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 259 | sample-data-tw | `journey_7F9FEBF55983F06E943C4BF21837CD2E` | 4 | 板南線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 260 | sample-data-tw | `journey_B34C34D4052B67C1D1F2468F4B8826A4` | 4 | 板南線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 261 | sample-data-tw | `journey_E2BA1597EB6DEA75FB126926E564D6CD` | 5 | 台灣高速鐵路 | 5/5 | 0 | 0 | 0 | 2 | OK |
| 262 | sample-data-tw | `journey_253013612D5701BF5895AD9C0FC1A850` | 4 | 臺中線 | 4/4 | 0 | 0 | 0 | 1 | OK |
| 263 | sample-data-tw | `journey_0A8EC92F75B878119658D0752A71E41F` | 6 | 臺中線 | 6/6 | 0 | 0 | 0 | 1 | OK |
| 264 | sample-data-tw | `journey_85C2F9F935C9A4701208C881737C7ADC` | 6 | 臺中線 | 6/6 | 0 | 0 | 0 | 1 | OK |
| 265 | sample-data-tw | `journey_D902105FFF79F2BC91DD69001C1D1752` | 22 | 臺中線 → 縱貫線南段 | 22/22 | 0 | 0 | 0 | 1 | OK |
| 266 | sample-data-tw | `journey_D6E210E0D14743B7AFE4EF6855ADC7FA` | 16 | 阿里山線 → 神木線 | 16/16 | 0 | 0 | 0 | 434 | OK (D: 神木–阿里山 display 神木線 0.9 km shorter than solved path) |
| 267 | sample-data-tw | `journey_214DEC1A58D8A2E683D5E17A47BFCE7F` | 1 | 神木線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 268 | sample-data-tw | `journey_5BADD88C12380B6A886444FB69041F7F` | 1 | 神木線 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 269 | sample-data-tw | `journey_E12389096A2B7F909034258E902F941E` | 2 | 祝山線 | 2/2 | 0 | 0 | 0 | 54 | OK |
| 270 | sample-data-tw | `journey_DFA582684EEDC99182E6D448F71607F7` | 2 | 祝山線 | 2/2 | 0 | 0 | 0 | 54 | OK |
| 271 | sample-data-tw | `journey_D4687FB43F9C1C43E0B0E40017AC9EDC` | 16 | 神木線 → 阿里山線 | 16/16 | 0 | 0 | 0 | 434 | OK (D: 阿里山–神木 display 神木線 0.9 km shorter than solved path) |
| 272 | sample-data-tw | `journey_CEB49C47CA401AD978BFE56F3D55F4C7` | 29 | 縱貫線南段 | 29/29 | 0 | 0 | 0 | 3 | OK |
| 273 | sample-data-tw | `journey_2FDE3816A557FFFB50406D18A131A336` | 15 | 高雄捷運紅線 | 15/15 | 0 | 0 | 0 | 4 | OK |
| 274 | sample-data-tw | `journey_F889D3193B98C1B436F80571170668AA` | 24 | 高雄捷運紅線 | 24/24 | 0 | 0 | 0 | 4 | OK |
| 275 | sample-data-tw | `journey_927016E22113A45080FBC58092D28EB0` | 6 | 高雄捷運紅線 | 6/6 | 0 | 0 | 0 | 0 | OK |
| 276 | sample-data-tw | `journey_10253133B7525E17509D09650522E725` | 2 | 高雄捷運紅線 | 2/2 | 0 | 0 | 0 | 0 | OK |
| 277 | sample-data-tw | `journey_0960494E1EEF4CBDB6B1E4B1FE90BEB7` | 38 | 高雄環狀輕軌 | 38/38 | 0 | 0 | 0 | 5 | OK |
| 278 | sample-data-tw | `journey_392AB4A925F885DE6CD17FA95C36040E` | 5 | 高雄捷運紅線 | 5/5 | 0 | 0 | 0 | 0 | OK |
| 279 | sample-data-tw | `journey_BCCC18D524113D54156C5874685CEE29` | 5 | 高雄捷運紅線 | 5/5 | 0 | 0 | 0 | 2 | OK |
| 280 | sample-data-tw | `journey_4D389948FB54DDE74017B2CCFC5B526D` | 10 | 台灣高速鐵路 | 10/10 | 0 | 0 | 0 | 2 | OK |
| 281 | sample-data-tw | `journey_701B2439EE7B2E05AF11E637D13B1CB5` | 10 | 縱貫線北段 | 10/10 | 0 | 0 | 0 | 13 | OK |
| 282 | sample-data-tw | `journey_06535A45062A8500166100F9B37C31F1` | 7 | 宜蘭線 → 縱貫線北段 | 7/7 | 0 | 0 | 0 | 13 | OK |
| 283 | sample-data-tw | `journey_5A3C1D43A8E70734A5D5DA40D6D39099` | 1 | 台灣高速鐵路 | 1/1 | 0 | 0 | 0 | 0 | OK |
| 284 | sample-data-tw | `journey_C929D1DB4BBEDD1ED71B9C4885026D78` | 194 | 縱貫線北段 → 臺中線 → 縱貫線南段 → 屏東線 → 南迴線 → 臺東線 → 北迴線 → 宜蘭線 … | 194/194 | 0 | 0 | 0 | 13 | OK |
| 285 | sample-data-hk | `journey_E432976CF3960943D65E32F615830502` | 12 | 東鐵綫 | 12/12 | 0 | 0 | 0 | 0 | OK |
| 286 | sample-data-kr | `journey_B7F582C16E904392DA2C9CE339DF6780` | 10 | 경북선 | 10/10 | 0 | 0 | 0 | 1 | OK |
| 287 | sample-data-mo | `journey_E155548B9C8291DA928D5426A9D0134B` | 11 | 氹仔線 | 11/11 | 0 | 0 | 0 | 0 | OK |

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
