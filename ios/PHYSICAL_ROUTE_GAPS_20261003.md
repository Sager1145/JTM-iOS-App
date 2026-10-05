# Bounded physical route gap inventory — 2026-10-03

## Subsequent reviewed boundaries: Chayamachi, Kojima, Shiojiri, Iwanuma and Utazu

The diagnosis below records the pre-repair state. The registry now contains ten reviewed boundaries, including `chayamachi-uno-honshi-bisan` at the existing source vertex `[133.82593,34.57818]`. The [JB Honshi 2022 disclosure, PDF page 5 / printed page 42](https://www.jb-honshi.co.jp/corp_index/company/integrated_report/pdf/2022_booklet_disclosure_03.pdf), section 3(3), explicitly identifies the managed conventional double-track Chayamachi–Utazu railway, its physical connection to the Uno line at Chayamachi, and the Chayamachi–Kojima opening on 1988-03-20. [JR West's anniversary report](https://www.westjr.co.jp/press/article/2013/02/page_3318.html) and [the railway facility management authority](https://www.jehdra.go.jp/torikumi/tetudousisetu.html) corroborate the line context.

This permits one zero-length transition between the two source line identities at the station boundary. It does not certify an individual turnout coordinate, connect all 19 duplicated vertices, establish every platform's connectivity, or authorize the separate JR West/JR Shikoku boundary at Kojima. No new geometric segment is drawn. The new `ReviewedChayamachiRoutingTests` uses the actual two-line source geometry and station directory; without the reviewed transition it cannot solve Okayama–Kojima, before opening it cannot solve, and on/after opening it traverses only source rail edges and this single zero-length identity boundary. This bounded regression does not replace the complete service-pattern suite or establish national coverage.

Kojima was separately reviewed from the same booklet: row 2 explicitly divides the same continuous Chayamachi–Utazu infrastructure into West's Chayamachi–Kojima and Shikoku's Kojima–Utazu operating sections; row 5 records actual Kojima–Utazu opening on 1988-04-10. `kojima-honshi-bisan-operator-boundary` permits one same-line operator transition at `[133.8079,34.4638]`, an existing endpoint shared by source features 9682/5502. This source identity representation does not claim a georeferenced legal meterpost or turnout. Its new actual-source regression covers Chayamachi–Utazu in both directions, opening-date rejection, and surveyed rail-only output; acceptance is recorded only after that test executes successfully.

For Shiojiri, the decisive construction source is [Nagayama's 1983 JNR structural-design-office article](https://dl.ndl.go.jp/view/prepareDownload?contentNo=1&itemId=info%3Andljp%2Fpid%2F10432303), *Soil and Foundation* 31-9 (308), printed page 20. Figure 1 explicitly draws the completed Enrei Chuo East approach through Shiojiri onto Shinonoi toward Matsumoto, while distinguishing the western branch and older Tatsuno route. The text states actual operation started July 5; its manuscript date 1983-07-26 fixes the year. [JR East's station diagram](https://www.jreast.co.jp/estation/stations/img/floormap/0774_1f-2f.png) corroborates named-line continuity. `shiojiri-chuo-shinonoi` accepts one existing north station endpoint `[137.94792,36.11571]`, conservatively dated 1983-07-05 for the current approach. Current operator names represent inherited source identities, not historical corporate existence. No JR Central boundary or platform clique is inferred. `ReviewedShiojiriRoutingTests` covers the actual source approach in both directions and opening-date behavior; its execution result remains separately recorded.

Iwanuma uses [MLIT Tohoku's operator-authored reconstruction engineering record](https://wwwtb.mlit.go.jp/tohoku/content/000175092.pdf), September 2012: PDF page 46 / printed 44, Figure 1.3.6 and Sendai inset, depicts the restored Joban branch physically joining the Tohoku corridor at Iwanuma, dated 2011-04-21. The JR East chapter, PDF page 119 / printed 117, records completed Watari–Iwanuma recovery on 2011-04-12. [The city's description](https://www.city.iwanuma.miyagi.jp/shisei/gaiyo/gaiyo/index.html) explicitly identifies the railway branching point. `iwanuma-joban-tohoku` accepts one existing north station vertex `[140.86437,38.11279]`; its conservative `validFrom` 2011-04-21 is a documented-existing evidence window, not the original opening. Earlier connectivity is not disproven but remains outside this reviewed interval. The original 1897 date is not certified from primary evidence. Nippori and all other shared vertices remain independent. `ReviewedIwanumaRoutingTests` applies source history before checking actual current Watari–Sendai geometry, both directions, missing-boundary rejection and no additional geometric segment; it does not claim the current route was available throughout 2011.

All four actual-source boundary regressions passed together: four tests / three suites in 4.732s, `/tmp/jtm-na-retirement/reviewed-japan-boundaries.log`. This is bounded physical evidence and date validation, not a complete national service-pattern run.

Utazu now has two separately reviewed boundaries: the eastern Yosan bypass at `[133.82565,34.31357]` and the station arm at `[133.81426,34.30712]`. [Utazu town's physical three-arm aerial](https://www.town.utazu.lg.jp/uploaded/attachment/2792.pdf), PDF page 1 / printed page 8, and [JR Shikoku's dated maintenance railway diagram](https://www.jr-shikoku.co.jp/04_company/information/shikoku_trainnetwork/5-1.pdf), PDF page 27 / printed page 25, support the infrastructure. Their conservative `validFrom` 2019-10-18 is a documented-existing evidence window, not the commissioning date. The registry adds no geometry. An unhinted reverse Marugame route initially selected the eastern bypass because origin-only line inference penalized the destination line. Default hints now include both unambiguous endpoint memberships together when no stronger preference exists. Hinted and unhinted routes both ways to Sakaide and Marugame pass all source-hop and exact-boundary assertions (eight solves). Twenty-eight focused routing/topology checks and the separate section-solver parity check passed. This fixes route selection, not individual turnout certification: the graph still models unrestricted bidirectional identity boundaries and has no incoming-approach state. Permitted movements would require separately reviewed, dated source-edge pairs; neither these tests nor line preferences certify them.

The following inventory is the historical pre-repair diagnosis; its old registry counts and failure lists are retained as evidence, not current acceptance results.

Read-only diagnosis of four requested geographic cases: 岡山→児島, 上諏訪→松本, 上野→水戸/柏, 相馬→仙台. No production/data/test changes, new railway edges, assertion weakening, nationwide graph construction, Swift build, or external evidence retrieval.

Source: `app/data/rail-sections.json`, SHA-256 `88bb7fa1fb4c90c5618bce0349fa97cb54a3eba7f2a641108f24d064adde659b`. Feature numbers below are **zero-based positions in its features array**, not persistent railway/source IDs. Coordinates are `[longitude, latitude]`, WGS84 source values. Every named identity below has railway class `11` and institution type `2`; level, track_id and source_id are absent. Shared source geometry is diagnostic evidence of the abstraction, not proof of physical track connectivity.

## Failing legs currently recorded by the full run

```text
↳ nanpu-okayama-kochi (南風) failed legs: ["forward: 岡山→児島", "reverse: 児島→岡山"]
↳ azusa-shinjuku-matsumoto (あずさ) failed legs: ["forward: 上諏訪→松本", "reverse: 松本→上諏訪"]
↳ hachioji-tokyo-hachioji (はちおうじ) failed legs: ["forward: 東京→新宿", "reverse: 新宿→東京"]
↳ ome-tokyo-ome (おうめ) failed legs: ["forward: 東京→新宿", "reverse: 新宿→東京"]
↳ hitachi-shinagawa-iwaki (ひたち) failed legs: ["reverse: 水戸→上野", "forward: 上野→水戸"]
↳ hitachi-shinagawa-sendai (ひたち) failed legs: ["forward: 上野→水戸", "forward: 相馬→仙台", "reverse: 仙台→相馬", "reverse: 水戸→上野"]
↳ tokiwa-shinagawa-katsuta (ときわ) failed legs: ["forward: 上野→柏", "reverse: 柏→上野"]
↳ tokiwa-shinagawa-takahagi (ときわ) failed legs: ["forward: 上野→柏", "reverse: 柏→上野"]
↳ narita-express-ikebukuro (成田エクスプレス) failed legs: ["forward: 東京→空港第2ビル", "reverse: 空港第2ビル→東京"]
↳ narita-express-omiya (成田エクスプレス) failed legs: ["reverse: 空港第2ビル→東京", "reverse: 池袋→大宮", "forward: 大宮→池袋", "forward: 東京→空港第2ビル"]
↳ kinugawa-shinjuku-kinugawaonsen (きぬがわ) failed legs: ["forward: 池袋→浦和", "forward: 大宮→栃木", "reverse: 栃木→大宮", "reverse: 浦和→池袋"]
↳ hokuto-hakodate-sapporo (北斗) failed legs: ["forward: 苫小牧→南千歳", "forward: 新札幌→札幌", "reverse: 札幌→新札幌", "reverse: 南千歳→苫小牧"]
↳ ozora-sapporo-kushiro (おおぞら) failed legs: ["forward: 札幌→新札幌", "reverse: 新札幌→札幌"]
↳ tokachi-sapporo-obihiro (とかち) failed legs: ["forward: 札幌→新札幌", "reverse: 新札幌→札幌"]
↳ okhotsk-sapporo-abashiri (オホーツク) failed legs: ["forward: 旭川→上川", "reverse: 上川→旭川"]
↳ kanpachi-ichiroku-hakata-beppu (かんぱち・いちろく) failed legs: ["reverse: 由布院→博多", "forward: 博多→由布院"]
↳ thunderbird-osaka-tsuruga (サンダーバード) failed legs: ["reverse: 敦賀→京都", "forward: 京都→敦賀"]
↳ noto-kagaribi-kanazawa-wakuraonsen (能登かがり火) failed legs: ["forward: 金沢→羽咋", "reverse: 羽咋→金沢"]
↳ sunrise-izumo-tokyo-izumoshi (サンライズ出雲) failed legs: ["reverse: 米子→新見", "reverse: 姫路→静岡", "forward: 静岡→姫路", "forward: 新見→米子"]
↳ sunrise-seto-tokyo-takamatsu (サンライズ瀬戸) failed legs: ["forward: 静岡→姫路", "forward: 岡山→児島", "forward: 児島→坂出", "reverse: 坂出→児島", "reverse: 児島→岡山", "reverse: 姫路→静岡"]
↳ shiokaze-okayama-matsuyama (しおかぜ) failed legs: ["forward: 岡山→児島", "reverse: 児島→岡山"]
↳ super-hokuto-hakodate-sapporo (スーパー北斗) failed legs: ["reverse: 札幌→新札幌", "reverse: 南千歳→苫小牧", "forward: 苫小牧→南千歳", "forward: 新札幌→札幌"]
↳ super-ozora-sapporo-kushiro (スーパーおおぞら) failed legs: ["reverse: 新札幌→札幌", "forward: 札幌→新札幌"]
↳ super-tokachi-sapporo-obihiro (スーパーとかち) failed legs: ["reverse: 新札幌→札幌", "forward: 札幌→新札幌"]
↳ super-hakucho-hachinohe-hakodate (スーパー白鳥) failed legs: ["forward: 蟹田→木古内", "forward: 木古内→函館", "reverse: 函館→木古内", "reverse: 木古内→蟹田"]
↳ super-hakucho-shinaomori-hakodate (スーパー白鳥) failed legs: ["reverse: 木古内→蟹田", "forward: 蟹田→木古内"]
↳ hakucho-hachinohe-hakodate (白鳥) failed legs: ["reverse: 函館→木古内", "reverse: 木古内→蟹田", "forward: 蟹田→木古内", "forward: 木古内→函館"]
↳ hakucho-shinaomori-hakodate (白鳥) failed legs: ["forward: 蟹田→木古内", "reverse: 木古内→蟹田"]
↳ hokutosei-ueno-sapporo (北斗星) failed legs: ["reverse: 札幌→南千歳", "reverse: 南千歳→苫小牧", "reverse: 函館→仙台", "forward: 仙台→函館", "forward: 苫小牧→南千歳", "forward: 南千歳→札幌"]
↳ cassiopeia-ueno-sapporo (カシオペア) failed legs: ["forward: 仙台→函館", "forward: 函館→洞爺", "forward: 苫小牧→南千歳", "forward: 南千歳→札幌", "reverse: 札幌→南千歳", "reverse: 南千歳→苫小牧", "reverse: 洞爺→函館", "reverse: 函館→仙台"]
↳ super-hitachi-ueno-iwaki (スーパーひたち) failed legs: ["forward: 上野→水戸", "reverse: 水戸→上野"]
↳ super-hitachi-ueno-sendai (スーパーひたち) failed legs: ["forward: 上野→水戸", "forward: 相馬→仙台", "reverse: 仙台→相馬", "reverse: 水戸→上野"]
```

The log now includes nine pattern failures (the additional NEX airport case arrived after the earlier eight-pattern observation). Tokyo and NEX are outside this four-case investigation. No failure has been classified as an authorized unsolvable leg or suppressed.

## Reviewed physical evidence status

`app/data/physical-rail-junctions.json` contains only four reviewed Oshiage/Shibuya connections. **None of the boundaries below is reviewed there.** The existing candidate inventory `app/data/physical-rail-topology.json` marks each relevant identity pair `requires-independent-physical-evidence`:

| Identity pair | Nationwide shared source vertex count | Requested geographic subset |
|---|---:|---|
| JR West 宇野線 / 本四備讃線 | 19 | 茶屋町 and its southern common corridor: all 19 |
| JR East 中央線 / 篠ノ井線 | 2 | 塩尻: both |
| JR East 常磐線 / 東北線 | 27 | 日暮里: 3; 岩沼: 24 |

The geographic sites must remain distinct even when their pair of identity names is identical. Service catalog lines and stop lists are evidence of intended service behavior; they do not identify a specific physical switch or certify the connection between these source geometries.

## 1. 岡山→児島 — 茶屋町 source line boundary

Fixed catalog codes: 岡山 `007310` (JR West 宇野線), 児島 `007919` (JR Shikoku 本四備讃線). JR West 児島 `007920` shares the same station group and identical station geometry; the endpoint can be represented on the West membership without proving a train-runnable operator transition.

Within bbox `[133.7,34.4,134.05,34.75]`, JR West 宇野線 has one connected 396-vertex source component, JR West 本四備讃線 one 117-vertex component. Their identities remain separate in the physical graph. Their 19 common vertices cover duplicated station/approach geometry:

| Feature | Identity | Existing first → last surveyed vertex | Vertices |
|---:|---|---|---:|
| 7062 | JR West 宇野線 | `[133.82794,34.59174]` → `[133.82593,34.57818]` | 7 |
| 7068 | JR West 宇野線 | `[133.82593,34.57818]` → `[133.8256,34.57578]` | 2 |
| 9679 | JR West 本四備讃線 | same endpoints as 7068 | 2 |
| 7078 | JR West 宇野線 | `[133.8256,34.57578]` → `[133.82689,34.5577]` | 18 |
| 9687 | JR West 本四備讃線 | identical full coordinate array to 7078 | 18 |
| 7079 | JR West 宇野線 | `[133.82689,34.5577]` → `[133.83377,34.55246]` | 15 |
| 9688 | JR West 本四備讃線 | `[133.82689,34.5577]` → `[133.82798,34.55153]` | 6 |

The last two features diverge after the duplicated corridor; coincidence at 茶屋町 or the divergence does not identify a reviewed switch. This is a source line-label boundary with adequate surveyed corridor geometry on both sides, but missing independent track/switch evidence in the accepted topology.

Additional endpoint abstraction: West feature 9682 and Shikoku feature 5502 both have `[133.80748,34.46183]` → `[133.8079,34.4638]` at 児島. The next Shikoku source feature 5503 runs `[133.80745,34.46169]` → `[133.80748,34.46183]`. This duplicated operator boundary is separately unreviewed; it is not automatically required to reach the West 児島 membership, and it must not be inferred from group identity alone.

## 2. 上諏訪→松本 — 塩尻 source line boundary

Fixed codes: 上諏訪 `002706` (JR East 中央線), 松本 `002506` (JR East 篠ノ井線). 塩尻 has East 中央線 `002618`, East 篠ノ井線 `002616`, and JR Central 中央線 `002617`, all with the same two-vertex station geometry.

Within bbox `[137.8,35.9,138.25,36.4]`, East 中央線 is one 1,053-vertex source component and East 篠ノ井線 one 299-vertex component. Both source chains reach 塩尻, but their physical identities do not join.

| Feature | Identity | Existing first → last surveyed vertex | Vertices |
|---:|---|---|---:|
| 16045 | JR East 中央線 | `[137.94783,36.1139]` → `[137.95642,36.10749]` | 23 |
| 16037 | JR East 中央線 | `[137.94783,36.1139]` → `[137.94792,36.11571]` | 2 |
| 14543 | JR East 篠ノ井線 | identical full coordinate array to 16037 | 2 |
| 14537 | JR East 篠ノ井線 | `[137.94792,36.11571]` → `[137.94954,36.1473]` | 11 |

The **two shared vertices** are the station endpoints `[137.94783,36.1139]` and `[137.94792,36.11571]`. The source repeats the station segment under three line/operator memberships; this is a label/platform abstraction, not verified evidence that every platform or track is mutually connected. The relevant missing accepted boundary is East 中央線↔East 篠ノ井線. Routing via JR Central would add another unreviewed operator identity and is not justified by this inspection.

## 3. 上野→水戸 / 柏 — 日暮里 boundary plus separate source branches

Fixed catalog codes: 上野 `003505` is the source directory's 東北新幹線 membership; conventional 東北線 `003504` is explicitly grouped under it. 水戸 `002319` and 柏 `002984` are JR East 常磐線. This station-code fact is distinct from a railway junction and does not authorize a Shinkansen-to-conventional edge.

The 常磐 source chain has one connected 1,205-vertex component in bbox `[139.65,35.65,140.6,36.45]`, reaching 水戸/柏 and ending at 日暮里. It has exactly **three common vertices** with the East 東北 identity here:

| Feature | Identity | Existing first → last surveyed vertex | Vertices |
|---:|---|---|---:|
| 16682 | JR East 東北線 | `[139.77196,35.72734]` → `[139.77993,35.71981]` | 13 |
| 16713 | JR East 東北線 | `[139.77196,35.72734]` → `[139.77069,35.7284]` | 3 |
| 14927 | JR East 常磐線 | identical full coordinate array to 16713 | 3 |
| 14922 | JR East 常磐線 | `[139.77069,35.7284]` → `[139.77598,35.73354]` | 23 |

The third shared vertex inside the station segment is `[139.77092,35.72822]`. The existing candidate is unreviewed; duplicating this station segment does not prove that the Tōhoku main line and Jōban tracks switch into each other at any of these coordinates.

**Additional source-track limitation:** the 東北-labelled Ueno–Nippori branch containing these shared vertices is a fully isolated 42-vertex component, features `16679,16682,16690,16692,16700,16706,16708,16713`. A scan of every JR East 東北 source feature confirmed that no other such feature touches this component: this is not just clipping at the bbox. Its Ueno terminal includes `[139.7766,35.71262]` (feature 16690); another surveyed Ueno branch uses `[139.77573,35.71239]` (feature 16697) and conventional station geometry `[139.77664,35.71439]` → `[139.77507,35.71205]`.

A reviewed 日暮里 label transition would therefore not by itself prove complete continuity from the Tokyo/Ueno main trunk to the selected Jōban track. No connecting turnout/alignment between these parallel Ueno source branches is represented in the surveyed source chain or reviewed junction registry. This does not independently prove where, or whether, the real tracks join. The current station-candidate and continuity-anchor heuristics can consider multiple surveyed memberships; this read-only inventory did not replay those rankings or certify which branch the actual dated solver selected. The observed no-path leg is consistent with the absent accepted 日暮里 boundary; completeness across adjacent legs remains an additional track-level evidence question.

## 4. 相馬→仙台 — 岩沼 source line boundary

Fixed codes: 相馬 `001347` (JR East 常磐線); 仙台 `001177` is the source directory's 東北新幹線 membership, explicitly grouping conventional 東北線 `001182`. 岩沼 常磐 `001228` and 東北 `001229` have identical station geometry.

Within bbox `[140.65,37.7,141.08,38.4]`, the current raw 常磐 survey is one connected 537-vertex component from the 相馬 area to 岩沼. The 東北 source chain containing 仙台 has a 1,191-vertex component. The raw geometry does not reveal an internal break along that current 常磐 chain; the missing accepted identity transition is at 岩沼.

| Feature | Identity | Existing first → last surveyed vertex | Vertices |
|---:|---|---|---:|
| 14765 | JR East 常磐線 | `[140.85197,38.09796]` → `[140.85471,38.06843]` | 48 |
| 14766 | JR East 常磐線 | `[140.86294,38.11094]` → `[140.85197,38.09796]` | 23 |
| 16477 | JR East 東北線 | identical full coordinate array to 14766 | 23 |
| 14770 | JR East 常磐線 | `[140.86437,38.11279]` → `[140.86294,38.11094]` | 2 |
| 16476 | JR East 東北線 | identical full coordinate array to 14770 | 2 |
| 16501 | JR East 東北線 | `[140.86437,38.11279]` → `[140.87983,38.14239]` | 45 |

The **24 shared vertices** comprise the 23-vertex duplicated southern approach plus the other station endpoint. They include `[140.85197,38.09796]`, `[140.86294,38.11094]`, and `[140.86437,38.11279]`. The source duplicates a long approach under two named lines; arbitrary interior coincidences are not railway junction evidence.

The history overlay contains eight old 駒ケ嶺–浜吉田 常磐 source sections retired on `2011-03-12`; these do not establish an 岩沼 physical connection and are unavailable for this pattern's `2020-03-14` date. The catalog describes intended continuation over 東北本線, but that service description alone has not been accepted as surveyed track/junction proof.

## Exact uncovered cause and limits

All four geographic failures cross independent source identities that the new physical graph deliberately does not join. The missing accepted registry boundaries are 茶屋町, 塩尻, 日暮里 and 岩沼 (three unique line-identity pairs across four sites). JR operator identity at 児島 and parallel Ueno branches are additional abstractions that must remain explicit.

The inspections establish existing geometry and missing **reviewed topology evidence**, not physically proven new railway connections. No per-feature level or track-ID mismatch explains these particular boundaries. Applied service patterns clear stale routeSections and routePolicy, so their catalog line labels are not automatically hard Dijkstra constraints. No label-normalization or assertion weakening would resolve the missing accepted physical connections.

This was a raw-source bounded topology scan, not a complete dated route solve. Station-candidate ranking, adjacent-leg continuity, history retirement effects on every feature, and independent official track plans were not fully validated. No coordinate-coincidence seam is proposed or authorized by this report.

## Complete common-coordinate lists for the four source boundaries

- 茶屋町: [[133.82404, 34.56458], [133.82408, 34.56373], [133.82409, 34.56555], [133.82414, 34.56613], [133.82416, 34.56315], [133.82427, 34.56267], [133.82441, 34.56227], [133.82465, 34.56943], [133.82467, 34.56956], [133.8249, 34.5715], [133.82498, 34.56106], [133.82518, 34.56072], [133.82521, 34.56067], [133.82531, 34.5741], [133.8256, 34.57578], [133.82593, 34.57818], [133.82644, 34.55861], [133.82673, 34.55806], [133.82689, 34.5577]]
- 塩尻: [[137.94783, 36.1139], [137.94792, 36.11571]]
- 日暮里: [[139.77069, 35.7284], [139.77092, 35.72822], [139.77196, 35.72734]]
- 岩沼: [[140.85197, 38.09796], [140.85215, 38.09817], [140.85263, 38.0987], [140.85293, 38.09902], [140.85377, 38.09997], [140.85441, 38.1007], [140.85477, 38.1011], [140.8555, 38.10192], [140.85569, 38.10214], [140.85624, 38.10279], [140.85705, 38.1037], [140.85762, 38.10435], [140.85801, 38.10482], [140.85886, 38.1058], [140.85956, 38.10661], [140.85994, 38.10705], [140.86062, 38.10782], [140.86104, 38.10837], [140.86159, 38.10912], [140.86193, 38.10958], [140.86195, 38.1096], [140.86217, 38.10991], [140.86294, 38.11094], [140.86437, 38.11279]]

## Cross-section proof and station display coordinates

Two legs that solve independently are not proof of a continuous journey. Each next leg now starts from the previous qualified surveyed graph endpoint; only a reviewed, date-valid zero-geometry junction may change identity at that seam. The visual station anchor is excluded from this physical choice. Real next-section edges still enforce date and line constraints.

An actual Azusa 甲府→茅野 regression demonstrated that the visual-anchor subset could discard the preceding 中央線 endpoint at `[138.57021,35.66677]`, despite that endpoint being present in the graph and the original station candidate list. Starting from the qualified node repairs this genuine same-rail continuation without introducing any connection. The entire 2019-03-16 forward 新宿→松本 chain and bidirectional candidate-omission regressions passed. Unknown qualified keys, coincident independent identities, ordinary zero-length edges and pre-opening boundaries remain rejected.

Exact recorded source paths are independently checked against dated graph edges. A cache without `physical-section-continuity-v2` cannot establish the new contract. Real independent legs may remain visible with a partial outcome; unproven exact geometry is excluded from mileage matching. Proven ridden parts contribute to totals while only complete distances contribute to complete-journey averages.

The follow-up Nippori primary-source review did not approve a boundary. The candidate `[139.77196,35.72734]` links source Joban14927/Tohoku16713 geometrically, and the official investigation diagram confirms the corridor, but does not independently map that local source identity abstraction. No connection or original opening date is inferred from this coincidence.

### Nanpu exact-continuation diagnostic and Tadotsu evidence review

The isolated current-source replay reproduces four Nanpu boundary failures at its catalog seed `1988-04-10`. At `2026-10-03`, both Utazu legs solve with the same qualified physical continuation; both Tadotsu legs remain unresolved. Each leg solves independently. This separates conservative reviewed-evidence windows from a missing accepted identity boundary; neither is permission to replace a dated proof with proximity.

At Tadotsu, the forward seed is JR Shikoku 予讃線 / class 11 at `[133.75762,34.27184]`, followed by 多度津→善通寺 on 土讃線. The reverse seed is 土讃線 at `[133.75696,34.27065]`, followed by 多度津→丸亀 on 予讃線. A bounded primary-source review found no qualifying turnout/interlocking plan independently selecting a surveyed vertex for this identity transition. JTSB RI2007-2-2 Appendix 1 is network-scale branch evidence; its local incident diagram is at Inohana tunnel, not Tadotsu. No new edge or earlier validity date was added. Logs and review: `/tmp/jtm-na-retirement/nanpu-diagnosis-build/probe.log`, `/tmp/jtm-na-retirement/tadotsu-physical-evidence.md`.


## Reviewed junction batch — 2026-10-03

Evidence standard: an official per-train timetable showing stops on both named lines, or an official chronology explicitly documenting the connection/through-operation date. Each entry selects the candidate's nearest identical existing surveyed vertex on both exact railway identities; both station-key approaches are at most 1,500 m. This accepts one named source-identity boundary, not every platform or turnout. Timetable dates establish documented-existing evidence windows, not opening dates; earlier continuity is not inferred from an ignored date query. The original ten entries remain unchanged.

All 30 additions satisfy the approach bound (largest: 小倉 1,410.345 m; 新大阪 1,093.393 m). 大阪 is excluded because the identity transition is at 西九条; its candidate approach is 8,171.211 m. Rounded candidate coordinates at 上越妙高, 新青森 and 広電西広島（己斐） are stored at the exact shared raw survey precision. Where one railway identity has multiple packaged display line IDs, the candidate's matching IDs are retained; those display labels do not create graph edges.

| Station | Lines | validFrom | Kind | Evidence URL |
|---|---|---|---|---|
| 泉岳寺 | 京浜急行電鉄 本線 / 東京都 1号線浅草線 | 1968-06-21 | opening | [official source](https://www.keikyu.co.jp/history/chronology05.html) |
| 赤羽 | 赤羽線 / 東北線 | 1885-03-01 | opening | [official source](https://www.soumu.metro.tokyo.lg.jp/01soumu-archives/06kanko_butsu/0601sisiko/0601shigai/0601shigai69) |
| 池袋 | 赤羽線 / 山手線 | 1903-04-01 | opening | [official source](https://www.city.toshima.lg.jp/499/bunka/bunka/shiryokan/showaretro/2310081541.html) |
| 大崎 | 山手線 / 東海道線 | 2001-12-01 | opening | [official source](https://www.city.shinjuku.lg.jp/kusei/70kinenshi/h13.html); [official source](https://www.city.shinagawa.tokyo.jp/PC/kuseizyoho/kuseizyoho-siryo/kuseizyoho-siryo-youkososhinagawa/kuseizyoho-siryo-youkososhinagawa-kuseigaiyou/hpg000000616.html) |
| 田端 | 山手線 / 東北線 | 1903-04-01 | opening | [official source](https://www.city.toshima.lg.jp/499/bunka/bunka/shiryokan/showaretro/2310081541.html); [official source](https://www.city.toshima.lg.jp/129/bunka/bunka/shiryokan/kankobutu/005971.html) |
| 新発田 | 羽越線 / 白新線 | 1952-12-23 | opening | [official source](https://www.city.niigata.lg.jp/kita/shisetsu/yoka/bunka/kyodo/webhakubutukan/setumeiban2.files/kantenkiti_p.pdf); [official source](https://www.city.niigata.lg.jp/kita/about/rekishi/rekishi_nenpyo3.html) |
| 上越妙高 | 東日本旅客鉄道 北陸新幹線 / 西日本旅客鉄道 北陸新幹線 | 2015-03-14 | opening | [official source](https://www.jrtt.go.jp/construction/achievement/hokuriku2.html); [official source](https://www.jrtt.go.jp/settlement/history.html) |
| 高崎 | 上越新幹線 / 北陸新幹線 | 1997-10-01 | opening | [official source](https://www.jrtt.go.jp/construction/achievement/hokuriku1.html) |
| 西所沢 | 狭山線 / 池袋線 | 1929-05-01 | opening | [official source](https://www.seiburailway.jp/company/history/chronology/) |
| 新青森 | 東日本旅客鉄道 東北新幹線 / 北海道旅客鉄道 北海道新幹線 | 2016-03-26 | opening | [official source](https://www.jrhokkaido.co.jp/corporate/company/com_02.html); [official source](https://www.jrhokkaido.co.jp/corporate/company/comtop.html); [official source](https://www.jrtt.go.jp/settlement/history.html) |
| 長万部 | 函館線 / 室蘭線 | 1928-09-10 | opening | [official source](https://www.jrhokkaido.co.jp/corporate/company/com_02.html); [official source](https://www.town.oshamambe.lg.jp/soshiki/3/116.html) |
| 南千歳 | 千歳線 / 石勝線 | 1981-10-01 | opening | [official source](https://www.jrhokkaido.co.jp/corporate/company/com_02.html) |
| 新得 | 石勝線 / 根室線 | 1981-10-01 | opening | [official source](https://www.jrhokkaido.co.jp/corporate/company/com_02.html) |
| 旭川 | 函館線 / 宗谷線 | 1898-08-12 | opening | [official source](https://www.jrhokkaido.co.jp/CM/Info/press/pdf/20180710_AS_120thAnniversary.pdf) |
| 西4丁目 | 都心線 / 1条線 | 2015-12-20 | opening | [official source](https://www.city.sapporo.jp/sogokotsu/shisaku/romen/loopka-jigyougaiyou.html) |
| 松風町 | 湯の川線 / 大森線 | 1913-10-31 | opening | [official source](https://archives.c.fun.ac.jp/hakodateshishi/tsuusetsu_03/shishi_05-02/shishi_05-02-04-07-04-01.htm) |
| 新大阪 | 東海旅客鉄道 東海道新幹線 / 西日本旅客鉄道 山陽新幹線 | 1987-04-01 | opening | [official source](https://www.westjr.co.jp/press/article/2012/02/page_1458.html); [official source](https://www.westjr.co.jp/company/info/history/); [official source](https://company.jr-central.co.jp/company/business-history/) |
| 倉敷 | 山陽線 / 伯備線 | 1928-10-25 | opening | [official source](https://www.westjr.co.jp/company/info/issue/data/pdf/data2026_25.pdf) |
| 益田 | 山陰線 / 山口線 | 1933-02-24 | opening | [official source](https://www.city.masuda.lg.jp/material/files/group/2/2023-6-P7.pdf); [official source](https://www.westjr.co.jp/company/info/issue/data/pdf/data2026_25.pdf) |
| 紙屋町東 | 本線 / 宇品線 | 1912-11-23 | opening | [official source](https://www.hiroden.co.jp/company/outline/history01.html) |
| 広電西広島（己斐） | 本線 / 宮島線 | 1958-06-20 | opening | [official source](https://www.hiroden.co.jp/company/outline/history05.html) |
| 江北 | 長崎線 / 佐世保線 | 1930-11-30 | opening | [official source](https://www.city.saga-kashima.lg.jp/site_files/file/gikai/kaigiroku/2014/20140324_ippanshitsumon.pdf) |
| 早岐 | 佐世保線 / 大村線 | 1898-01-20 | opening | [official source](https://www.city.sasebo.lg.jp/kyouiku/bunzai/sasebo120histoy.html) |
| 諫早 | 大村線 / 長崎線 | 1934-12-01 | opening | [official source](https://www.city.isahaya.nagasaki.jp/uploaded/attachment/7604.pdf) |
| 鹿児島 | 鹿児島線 / 日豊線 | 1913-10-11 | opening | [official source](https://www.city.kagoshima.lg.jp/kyoiku/kanri/bunkazai/tiikikeikaku/r6workshop/documents/tyuuoustory.pdf); [official source](https://www.jrkyushu.co.jp/news/__icsFiles/afieldfile/2023/09/29/230929_110year_anniversary_ticket.pdf) |
| 小倉 | 日豊線 / 鹿児島線 | 1923-12-15 | documented-existing | [official source](https://www.jrkyushu.co.jp/news/__icsFiles/afieldfile/2023/11/21/231121_885kei_tokubetsu_nippou100nen.pdf) |
| 城野 | 日田彦山線 / 日豊線 | 1960-04-01 | documented-existing | [official source](https://www.hitahiko.jp/rekishi.php) |
| 多度津 | 予讃線 / 土讃線 | 1913-12-20 | opening | [official source](https://www.library.pref.kagawa.lg.jp/know/local/local_2033-19) |
| 熱海 | 東日本旅客鉄道 東海道線 / 東海旅客鉄道 東海道線 | 1987-04-01 | opening | [official source](https://www.city.atami.lg.jp/shisei/atamishi/1001244/1001251.html); [official source](https://www.jrtt.go.jp/settlement/history.html) |
| 泉佐野 | 南海本線 / 空港線 | 1994-06-15 | opening | [official source](https://www.nankai.co.jp/company/history/chronicle/brief/period_03.html) |

Census of all 201 JP sample rides (train-store IDs resolved through the sample manifest, normalized and replayed through the endpoint-trim pipeline): original ten junctions → expanded registry yields 131 → 140 zero-gap rides, 137 → 117 boundary gaps, and 88 → 87 non-boundary failures. Super Oki `20260719_03_super_oki5` has zero gaps. Remaining boundary gaps comprise 25 before the 18 conservative evidence windows, one date-qualified gap at 南千歳 on `20260716_07_hokuto20`, and 91 at other stations. Non-boundary causes are source verification (36), matched-source verification (38), unresolved legacy sections (12), and ambiguous inference (1). The date-qualified station assertion remains enabled and exposes the 南千歳 gap; the full ride-level list is printed by `JunctionApproachTests.realDataJunctionCensus`.

Validation: the requested `JunctionApproach|PhysicalEndpointTrim|PhysicalSectionContinuity|PhysicalTopologyRouting|Reviewed|RailHistory` filter completed 73 tests across 11 suites (72 passed, one retained census failure). All 40 registry junctions were accepted. The remaining 南千歳 failure is normalized section index 2, 南千歳→苫小牧, following 新札幌→南千歳; Hokuto does not use 石勝線, so the reviewed 千歳線–石勝線 edge cannot prove this other continuation. No production routing code was changed to conceal the failure.

## Junction batch 2 — 2026-10-04

Appended 78 validated junctions (35 east, 24 central, 19 west); the existing 40 records are unchanged. All 118 IDs are unique. Dates retain each fragment’s reviewed evidence window.

| id | Station | Lines | validFrom | First evidence URL |
|---|---|---|---|---|
| tobu-dobutsu-koen-east-00 | 東武動物公園 | jp-東武鉄道-伊勢崎線 / jp-東武鉄道-日光線 | 2026-03-14 | https://www.tobu.co.jp/pdf/timetable/time-table_01_kudari.pdf?202603 |
| shimo-imaichi-east-01 | 下今市 | jp-東武鉄道-日光線 / jp-東武鉄道-鬼怒川線 | 2026-03-14 | https://www.tobu.co.jp/pdf/timetable/time-table_01_kudari.pdf?202603 |
| shin-fujiwara-east-02 | 新藤原 | jp-東武鉄道-鬼怒川線 / jp-野岩鉄道-会津鬼怒川線 | 1986-10-09 | https://www.tobu.co.jp/pdf/timetable/time-table_01_kudari.pdf?202603 |
| aizukogen-ozeguchi-east-03 | 会津高原尾瀬口 | jp-野岩鉄道-会津鬼怒川線 / jp-会津鉄道-会津線 | 1990-10-12 | https://www.tobu.co.jp/pdf/timetable/time-table_01_kudari.pdf?202603 |
| ota-east-04 | 太田 | jp-東武鉄道-伊勢崎線 / jp-東武鉄道-桐生線 | 2026-03-14 | https://www.tobu.co.jp/pdf/timetable/time-table_02_kudari.pdf?202603 |
| keisei-takasago-east-08 | 京成高砂 | jp-京成電鉄-本線 / jp-京成電鉄-成田空港線 | 2010-07-17 | https://www.keisei.co.jp/keisei/keisei_museum/history/index5.html |
| yoyogi-uehara-east-12 | 代々木上原 | jp-東京地下鉄-9号線千代田線 / jp-小田急電鉄-小田原線 | 1978-03-31 | https://www.odakyu.jp/company/history/ |
| sagami-ono-east-13 | 相模大野 | jp-小田急電鉄-小田原線 / jp-小田急電鉄-江ノ島線 | 1929-04-01 | https://www.odakyu.jp/company/history/ |
| odawara-east-14 | 小田原 | jp-小田急電鉄-小田原線 / jp-小田急箱根-鉄道線 | 1950-08-01 | https://www.odakyu.jp/company/history/ |
| matsuda-east-15 | 松田 | jp-小田急電鉄-小田原線 / jp-東海旅客鉄道-御殿場線 | 1987-04-01 | https://www.odakyu.jp/company/history/ |
| atami-east-16 | 熱海 | jp-東日本旅客鉄道-東海道線 / jp-東日本旅客鉄道-伊東線 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/095/098901.html |
| ito-east-17 | 伊東 | jp-東日本旅客鉄道-伊東線 / jp-伊豆急行-伊豆急行線 | 1961-12-10 | https://www.izukyu.co.jp/company/history.php |
| fujisan-east-19 | 富士山 | jp-富士山麓電気鉄道-大月線 / jp-富士山麓電気鉄道-河口湖線 | 2026-03-14 | https://www.fujikyu-railway.jp/fujikaiyuu/ |
| tokyo-east-20 | 東京 | jp-東日本旅客鉄道-東海道線 / jp-東日本旅客鉄道-東北線-2 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/065/069941.html |
| tokyo-east-21 | 東京 | jp-東日本旅客鉄道-東海道線 / jp-東日本旅客鉄道-総武線 / jp-東日本旅客鉄道-総武線-3 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/060/063411.html |
| kanda-east-23 | 神田 | jp-東日本旅客鉄道-東北線-2 / jp-東日本旅客鉄道-中央線 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/155/155641.html |
| nippori-east-25 | 日暮里 | jp-東日本旅客鉄道-東北線-2 / jp-東日本旅客鉄道-東北線-4 / jp-東日本旅客鉄道-常磐線 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/045/048451.html |
| sakura-east-27 | 佐倉 | jp-東日本旅客鉄道-総武線 / jp-東日本旅客鉄道-成田線-2 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/060/063411.html |
| soga-east-29 | 蘇我 | jp-東日本旅客鉄道-京葉線 / jp-東日本旅客鉄道-内房線 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/045/049711.html |
| soga-east-30 | 蘇我 | jp-東日本旅客鉄道-京葉線 / jp-東日本旅客鉄道-外房線 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/095/098781.html |
| tachikawa-east-33 | 立川 | jp-東日本旅客鉄道-中央線 / jp-東日本旅客鉄道-青梅線 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/155/155641.html |
| takasaki-east-34 | 高崎 | jp-東日本旅客鉄道-高崎線 / jp-東日本旅客鉄道-上越線 | 2026-10-03 | https://timetables.jreast.co.jp/2610/timetable-v/238u2p.html |
| shin-maebashi-east-35 | 新前橋 | jp-東日本旅客鉄道-両毛線 / jp-東日本旅客鉄道-上越線 | 2026-10-03 | https://timetables.jreast.co.jp/2610/timetable-v/238u2p.html |
| omagari-east-38 | 大曲 | jp-東日本旅客鉄道-田沢湖線 / jp-東日本旅客鉄道-奥羽線 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/060/064581.html |
| fukushima-east-39 | 福島 | jp-東日本旅客鉄道-東北新幹線 / jp-東日本旅客鉄道-奥羽線 | 2026-10-01 | https://timetables.jreast.co.jp/2610/timetable-v/003d1p.html |
| morioka-east-40 | 盛岡 | jp-東日本旅客鉄道-東北新幹線 / jp-東日本旅客鉄道-田沢湖線 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/060/064581.html |
| goryokaku-east-48 | 五稜郭 | jp-道南いさりび鉄道-道南いさりび鉄道線 / jp-北海道旅客鉄道-函館線 | 2016-03-26 | https://www.shr-isaribi.jp/wp-content/uploads/2015/10/businessreport02.pdf |
| numanohata-east-49 | 沼ノ端 | jp-北海道旅客鉄道-室蘭線 / jp-北海道旅客鉄道-千歳線 | 2014-08-01 | https://www.jrhokkaido.co.jp/press/2014/140627-1.pdf |
| shiroishi-east-51 | 白石 | jp-北海道旅客鉄道-千歳線 / jp-北海道旅客鉄道-函館線 | 2014-08-01 | https://www.jrhokkaido.co.jp/press/2014/140627-1.pdf |
| shin-asahikawa-east-54 | 新旭川 | jp-北海道旅客鉄道-宗谷線 / jp-北海道旅客鉄道-石北線 | 2025-03-15 | https://www.jrhokkaido.co.jp/CM/Info/press/pdf/20241213_KO_kaisei.pdf |
| shinonoi-east-55 | 篠ノ井 | jp-東日本旅客鉄道-篠ノ井線 / jp-東日本旅客鉄道-信越線-3 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/000/000241.html |
| matsumoto-east-56 | 松本 | jp-東日本旅客鉄道-篠ノ井線 / jp-東日本旅客鉄道-大糸線 | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/110/111361.html |
| shiojiri-east-57 | 塩尻 | jp-東海旅客鉄道-中央線 / jp-東日本旅客鉄道-篠ノ井線 | 1987-04-01 | https://timetables.jreast.co.jp/2610/train/000/000241.html |
| naoetsu-east-59 | 直江津 | jp-東日本旅客鉄道-信越線 / jp-えちごトキめき鉄道-妙高はねうまライン | 2026-09-18 | https://timetables.jreast.co.jp/2610/train/060/063961.html |
| saigata-east-60 | 犀潟 | jp-北越急行-ほくほく線 / jp-東日本旅客鉄道-信越線 | 2026-03-14 | https://hokuhoku.co.jp/pdf/jikoku/jikoku20260314.pdf |
| isenakagawa-osaka-nagoya | 伊勢中川 | jp-近畿日本鉄道-大阪線 / jp-近畿日本鉄道-名古屋線 | 1961-03-29 | https://www.kintetsu.co.jp/senden/hinotori/ |
| isenakagawa-osaka-yamada | 伊勢中川 | jp-近畿日本鉄道-大阪線 / jp-近畿日本鉄道-山田線 | 1948-07-18 | https://www.kintetsu.co.jp/senden/shimakaze/ |
| isenakagawa-nagoya-yamada | 伊勢中川 | jp-近畿日本鉄道-名古屋線 / jp-近畿日本鉄道-山田線 | 1970-03-01 | https://www.kintetsu.co.jp/senden/shimakaze/ |
| ujiyamada-yamada-toba | 宇治山田 | jp-近畿日本鉄道-山田線 / jp-近畿日本鉄道-鳥羽線 | 1969-12-15 | https://www.kintetsu.co.jp/senden/shimakaze/ |
| toba-toba-shima | 鳥羽 | jp-近畿日本鉄道-鳥羽線 / jp-近畿日本鉄道-志摩線 | 1970-03-01 | https://www.kintetsu.co.jp/senden/shimakaze/ |
| saidaiji-kyoto-kashihara | 大和西大寺 | jp-近畿日本鉄道-京都線 / jp-近畿日本鉄道-橿原線 | 1964-10-01 | https://www.kintetsu.co.jp/senden/shimakaze/ |
| saidaiji-kyoto-nara | 大和西大寺 | jp-近畿日本鉄道-京都線 / jp-近畿日本鉄道-奈良線 | 1964-12-01 | https://www.kintetsu.co.jp/senden/aoniyoshi/ |
| yagi-kashihara-osaka | 大和八木 | jp-近畿日本鉄道-橿原線 / jp-近畿日本鉄道-大阪線 | 1967-12-20 | https://www.kintetsu.co.jp/senden/shimakaze/ |
| uehommachi-namba-osaka | 大阪上本町 | jp-近畿日本鉄道-難波線 / jp-近畿日本鉄道-大阪線 | 1970-03-21 | https://www.kintetsu.co.jp/senden/shimakaze/ |
| kashiharajingu-minamiosaka-yoshino | 橿原神宮前 | jp-近畿日本鉄道-南大阪線 / jp-近畿日本鉄道-吉野線 | 1965-03-18 | https://www.kintetsu.co.jp/senden/blue_symphony/index.html |
| juso-takarazuka-kyoto | 十三 | jp-阪急電鉄-宝塚線 / jp-阪急電鉄-京都線 | 2019-03-23 | https://www.hankyu.co.jp/kyotrain-garaku/service/ |
| jingumae-nagoya-tokoname | 神宮前 | jp-名古屋鉄道-名古屋本線 / jp-名古屋鉄道-常滑線 | 2005-01-29 | https://www.meitetsu.co.jp/library/exp_history/index.html |
| wakayama-hanwa-kisei | 和歌山 | jp-西日本旅客鉄道-阪和線 / jp-西日本旅客鉄道-紀勢線 | 2011-08-04 | https://www.jr-odekake.net/railroad/train/kuroshio/ |
| hineno-hanwa-airport | 日根野 | jp-西日本旅客鉄道-阪和線 / jp-西日本旅客鉄道-関西空港線 | 1994-06-15 | https://www.jr-odekake.net/railroad/train/haruka/ |
| kyuhoji-osakahigashi-kansai | 久宝寺 | jp-西日本旅客鉄道-おおさか東線 / jp-西日本旅客鉄道-関西線 | 2008-03-15 | https://www.jr-odekake.net/railroad/train/mahoroba/ |
| amagasaki-tokaido-fukuchiyama | 尼崎 | jp-西日本旅客鉄道-東海道線 / jp-西日本旅客鉄道-福知山線 | 2011-03-12 | https://www.jr-odekake.net/railroad/train/kounotori/ |
| miyazu-miyafuku-miyazu | 宮津 | jp-WILLER　TRAINS-宮福線 / jp-WILLER　TRAINS-宮津線 | 2015-04-01 | https://www.jr-odekake.net/railroad/train/hashidate/ |
| yamashina-tokaido-kosei | 山科 | jp-西日本旅客鉄道-東海道線 / jp-西日本旅客鉄道-湖西線 | 1987-04-01 | https://www.jr-odekake.net/railroad/train/thunderbird/ |
| omishiotsu-kosei-hokuriku | 近江塩津 | jp-西日本旅客鉄道-湖西線 / jp-西日本旅客鉄道-北陸線 | 1987-04-01 | https://www.jr-odekake.net/railroad/train/thunderbird/ |
| maibara-tokaido-boundary | 米原 | jp-東海旅客鉄道-東海道線-2 / jp-西日本旅客鉄道-東海道線 | 1987-04-01 | https://www.jr-odekake.net/railroad/train/sunriseseto_izumo/ |
| inotani-takayama-boundary | 猪谷 | jp-東海旅客鉄道-高山線 / jp-西日本旅客鉄道-高山線 | 1987-04-01 | https://www.jr-odekake.net/railroad/train/hida/ |
| shingu-kisei-boundary | 新宮 | jp-東海旅客鉄道-紀勢線 / jp-西日本旅客鉄道-紀勢線 | 1987-04-01 | https://www.jr-odekake.net/railroad/train/nanki/ |
| tsu-ise-kisei | 津 | jp-伊勢鉄道-伊勢線 / jp-東海旅客鉄道-紀勢線 | 2024-03-16 | https://isetetu.co.jp/pdf/up_timetable/file/1 |
| tsubata-ir-nanao | 津幡 | jp-IRいしかわ鉄道-IRいしかわ鉄道線 / jp-西日本旅客鉄道-七尾線 | 2015-03-14 | https://www.jr-odekake.net/railroad/train/notokagaribi/ |
| west-kamigori | 上郡 | jp-西日本旅客鉄道-山陽線 / jp-智頭急行-智頭線 | 1994-12-03 | https://timetable.jr-odekake.net/train-timetable/67481?date=20261003 |
| west-chizu | 智頭 | jp-智頭急行-智頭線 / jp-西日本旅客鉄道-因美線 | 1994-12-03 | https://timetable.jr-odekake.net/train-timetable/67481?date=20261003 |
| west-tottori | 鳥取 | jp-西日本旅客鉄道-因美線 / jp-西日本旅客鉄道-山陰線 | 2026-10-03 | https://timetable.jr-odekake.net/train-timetable/67481?date=20261003 |
| west-kobe | 神戸 | jp-西日本旅客鉄道-東海道線 / jp-西日本旅客鉄道-山陽線-3 | 2026-10-03 | https://timetable.jr-odekake.net/train-timetable/238531?date=20261003 |
| west-wadayama | 和田山 | jp-西日本旅客鉄道-播但線 / jp-西日本旅客鉄道-山陰線 | 2026-10-03 | https://timetable.jr-odekake.net/train-timetable/238531?date=20261003 |
| west-hokidaisen | 伯耆大山 | jp-西日本旅客鉄道-伯備線 / jp-西日本旅客鉄道-山陰線 | 2026-10-03 | https://timetable.jr-odekake.net/train-timetable/76231?date=20261003 |
| west-moji | 門司 | jp-九州旅客鉄道-山陽線 / jp-九州旅客鉄道-鹿児島線 | 2026-10-03 | https://timetable.jr-odekake.net/train-timetable/82781?date=20261003 |
| west-hakata | 博多 | jp-西日本旅客鉄道-山陽新幹線 / jp-九州旅客鉄道-九州新幹線 | 2011-03-12 | https://timetable.jr-odekake.net/train-timetable/91071?date=20261003 |
| west-takamatsu | 高松 | jp-四国旅客鉄道-予讃線 / jp-四国旅客鉄道-高徳線 | 2024-12-13 | https://www.jr-shikoku.co.jp/03_news/press/assets/2025/03/07/2024%2012%2013%2003.pdf |
| west-kubokawa | 窪川 | jp-四国旅客鉄道-土讃線 / jp-土佐くろしお鉄道-中村線 | 1988-04-01 | https://timetable.jr-odekake.net/train-timetable/103931?date=20261003 |
| west-nakamura | 中村 | jp-土佐くろしお鉄道-中村線 / jp-土佐くろしお鉄道-宿毛線 | 1997-10-01 | https://timetable.jr-odekake.net/train-timetable/78011?date=20261003 |
| west-yatsushiro | 八代 | jp-九州旅客鉄道-鹿児島線 / jp-九州旅客鉄道-肥薩線 | 2009-04-25 | https://www.jrkyushu.co.jp/trains/sllastyear/index.html |
| west-hayato | 隼人 | jp-九州旅客鉄道-肥薩線 / jp-九州旅客鉄道-日豊線 | 2004-03-13 | https://www.jrkyushu.co.jp/news/__icsFiles/afieldfile/2022/03/02/220302_hayatonokaze_lastrun_final.pdf |
| west-oita-kyudai | 大分 | jp-九州旅客鉄道-久大線 / jp-九州旅客鉄道-日豊線 | 2026-09-30 | https://www.jrkyushu-timetable.jp/sp/2610/0016/00167201.html?t=2828302e&d=20260930 |
| west-oita-hohi | 大分 | jp-九州旅客鉄道-豊肥線 / jp-九州旅客鉄道-日豊線 | 2026-09-30 | https://www.jrkyushu-timetable.jp/jr-k_time/2610/0030/00308301.html?c=28742&d=30&ym=202609 |
| west-yoshizuka | 吉塚 | jp-九州旅客鉄道-篠栗線 / jp-九州旅客鉄道-鹿児島線 | 2026-10-03 | https://www.jrkyushu-timetable.jp/sp/2610/0035/00350501.html?d=20261003&t=2806201 |
| west-keisen | 桂川 | jp-九州旅客鉄道-筑豊線 / jp-九州旅客鉄道-篠栗線 | 2026-10-03 | https://www.jrkyushu-timetable.jp/sp/2610/0035/00350501.html?d=20261003&t=2806201 |
| west-minamimiyazaki | 南宮崎 | jp-九州旅客鉄道-日豊線 / jp-九州旅客鉄道-日南線 | 2026-09-30 | https://www.jrkyushu-timetable.jp/sp/2610/0008/00087001.html?t=2887001&d=20260930 |
| west-tayoshi | 田吉 | jp-九州旅客鉄道-日南線 / jp-九州旅客鉄道-宮崎空港線 | 1996-07-18 | https://www.jrkyushu-timetable.jp/sp/2610/0008/00087001.html?t=2887001&d=20260930 |

Rejected/skipped pairs (missing evidence does not establish absence of a physical connection):

- east rejection details (session working notes, not committed): 浅草橋 JR–Toei is a crossing; 大月, 東京 東北–総武, 八王子 and 木古内 Shinkansen–conventional lack shared vertices; 海峡線 pairs lack package identity, compatible gauge evidence, or dated operator evidence; 植苗/平和 are unproven additional transitions; 押上/上越妙高 already exist. Other listed pairs lack complete official through-train/date evidence.
- central rejection details (session working notes, not committed): 十三 神戸–京都, 天王寺 環状–阪和, both 福知山–宮福 pairs and 福井 Shinkansen–Hapi lack shared vertices; 西九条 candidates do not prove the actual Haruka approach; 岸里玉出, 天王寺 環状–関西 and 綾部 lack complete dated evidence; historical 金沢/津幡 北陸 pairs lack dated service/closing evidence.
- west rejection details (session working notes, not committed): 姫路 山陽–播但 and 岡山 山陽–宇野 lack shared vertices; 下関 operator boundary and 熊本 豊肥–鹿児島 lack official same-train evidence; 武雄温泉 is a conventional/Shinkansen transfer without a shared vertex.

Validation: the requested `JunctionApproach|PhysicalTopologyRouting|Reviewed|RailHistory|OnEdgeCertification|PhysicalEndpointTrim|TrainServicePatterns` filter passed all 102 tests across 12 suites. The real-registry graph assertion accepted all 118 junctions with no rejected IDs. The sample-ride census reports 169/201 zero-gap rides, 35 boundary gaps, and 30 non-boundary failures.

## OSM survey junctions — 2026-10-04

The 1500 m cap applies to `osmConnector` only. `osmTrack` is same-identity survey geometry: attach stubs stay ≤ 50 m and there is no total-length cap. `rail-sections.json` and the rail-history overlay set no start date on these identities, so `validFrom` is the earliest official date of the segment (総武快速線 東京–錦糸町 1972-07-15; 東京駅 passenger opening 1914-12-20; 新橋–横浜 1872-10-14; 神田–上野 1925-11-01). Hachioji stays the historical one-day window.

| id | kind | ways | stubs (m) | validFrom |
| --- | --- | --- | --- | --- |
| otsuki-chuo-otsuki | osmConnector | 243609295 | 16.69 / 2.07 | 2026-03-14 |
| fukuchiyama-sanin-miyafuku | osmConnector | 734217342 | 27.22 / 43.76 | 2026-07-30 |
| hachioji-yokohama-chuo | osmConnector | 249149440, 638441264, 638441265 | 26.94 / 17.33 | 2008-09-23 (validTo 2008-09-24) |
| tokyo-tohoku-kanda | osmTrack | 348681062, 348681077, 362230881, 362230888, 34282732, 896850007, 896850005, 896850010, 273056373 | 12.30 / 21.41 | 1925-11-01 |
| tokyo-tokaido-shinkansen-shinagawa | osmTrack | 1174526293 and 39 following surveyed ways | 1.11 / 14.46 | 1964-10-01 |
| tokyo-sobu-shin-nihonbashi | osmTrack | 759433002, 759432998 | 33.69 / 22.76 | 1972-07-15 |
| tokyo-tokaido-shimbashi | osmTrack | 759433005, 210358354 | 33.69 / 9.34 | 1914-12-20 |
| shimbashi-tokaido-shinagawa | osmTrack | 210358354, 210358355, 244134593, 852774337, 1313812927 | 33.92 / 13.06 | 1872-10-14 |
| tokyo-tokaido-yurakucho | osmTrack | 365230218, 1381338053, 846477081, 23630772, 203301431, 203301434, 203301430, 203301433 | 12.30 / 31.19 | 1914-12-20 |

Registered after the earlier rejection (the display stroke attaches inside 50 m; the old way-chain stubs do not):

- tokyo-tokaido-shinkansen-shinagawa — path is the decoded 品川–東京 display interval (64 vertices), stubs 1.11 / 14.46 m. The earlier 39-way chain plus disconnected 74446959 stubbed at 65.45 / 32.02 m and was not registered.
- tokyo-tohoku-shinkansen-ueno — registered separately as a terminus osmTrack. The earlier chain stubbed at 92.44 / 6.88 m.

## Junction dates and missing seams — 2026-10-04

Registry before the r3 batch below was 160 entries (148 zeroLength, 2 shortLink, 4 osmConnector, 6 osmTrack). Applied the four jn5 `validFrom` improvements (新栃木 1931-08-11, 宇多津 station arm 1988-04-10, 十三 1921-04-01, 宮津 1988-07-16) and appended the 10-id fragment. The eastern 宇多津 bypass stays 2019-10-18. Backdates with saved official bytes are in `jn6/backdate.md`. Year-only sources use `YYYY-12-31` and the phrase `conservative year-end bound` (佐倉 1897, 大分豊肥 1914, 大分久大 1915, 渋川 1945, 佃 1914).

New geometry junctions:

| id | kind | pair | validFrom | validTo |
| --- | --- | --- | --- | --- |
| tokoname-tokoname-airport | zeroLength | 常滑線↔空港線 [136.83544, 34.89075] | 2005-01-29 | |
| agano-ikebukuro-seibu-chichibu | zeroLength | 池袋線↔西武秩父線 [139.22592, 35.90829] | 1969-10-14 | |
| tsukuda-tokushima-dosan | zeroLength | 徳島線↔土讃線 [133.85699, 34.03245] | 1914-12-31 | |
| naka-oguni-tsugaru-kaikyo | zeroLength | 津軽線↔海峡線 [140.59738, 41.05138] | 1988-03-13 | 2016-03-26 |
| kaifu-mugi-asato | shortLink 13.6 m | 牟岐線 [134.35076, 33.60587]↔阿佐東線 [134.35086, 33.60596] | 1992-03-26 | 2019-03-16 |

`naka-oguni-tsugaru-kaikyo` omits a 海峡線 catalog id. `line-service-catalog.json` has no `jp-北海道旅客鉄道-海峡線`. The loader does not decode `lineIDs`; the graph match is 北海道旅客鉄道 / 海峡線 / class 11. 佃’s 1914-12-31 is the JR Shikoku 2014 「徳島線全線開通100周年」 year-end bound. That page does not name 佃, and no 土讃線 opening day was in the saved bytes. 63 entries remain with `validFrom` ≥ 2000-01-01: post-2000 openings and through-service starts, dated service windows, and junctions whose earlier official year or day was not in saved operator/municipal bytes (JR East history PDFs returned HTTP 403; JR West databook 開業 cells are CID-garbled). 大宮 stayed 2026-10-01 until the r3 backdate below. 日暮里 was not set to 1896-12-25 because that press is 田端. 高崎 was not set to 1884-05-01 because that is the 高崎線 station opening, not 上越線.

## r3 batch — 2026-10-04

Registry is 171 entries (155 zeroLength, 5 shortLink, 4 osmConnector, 7 osmTrack). Added the 8-id r2 fragment, `kikonai-esashi-kaikyo` (1988-03-13 to 2016-03-26) and `goryokaku-esashi-hakodate-kamiiso` (1913-09-15 to 2016-03-26, vertex [140.73386, 41.80234], not the 1936 [140.73218, 41.80838] junction), and osmTrack `tokyo-tokaido-shinkansen-shinagawa`. `tokyo-tohoku-kanda` path is the 11 decoded 東京↔神田 display vertices plus the previous 14-point tail so the 神田 stub stays 21.41 m (the 神田 anchor is about 375 m from that N02 vertex).

Backdates: 大宮 1885-07-16, 新津 1912-12-31, 日暮里 1905-04-01, 秋田 1924-07-31, 下今市 1929-10-22, 尼崎 1904-11-03, 伯耆大山 `west-hokidaisen` 1928-10-25 (same JR West databook row as 倉敷, 伯備線全通).

おおさか東線 sections in `rail-history.json` (revision stays `2026-09-28.3`): 放出–久宝寺 `valid_from` 2008-03-15, 新大阪–放出 `valid_from` 2019-03-16. Targets are sections only.

成田エクスプレス: five patterns that already ran before 空港第2ビル gained a `-before-terminal2` twin (1991-03-19 until 1992-12-03) without that stop; the existing patterns start 1992-12-03. `narita-express-ofuna` only moved to 1992-12-03, because the same JR East 要覧 dates the 大船延長 to that day. スワローあかぎ lines now include 両毛線.

`osaka-osakaloop-tokaido` is the shared 梅田貨物線 vertex [135.48736, 34.69757]. It does not close sample `20260703_01_haruka` at 大阪: the ride's 東海道線 end is the passenger arm, 8,171 m along-track from that vertex, past the 1,500 m approach cap. The registry still contains the junction. No second link was added at the passenger platforms.

## Known limitation — はるか at 大阪 (2026-10-04)

The reviewed `osaka-osakaloop-tokaido` junction sits on the 梅田貨物線/うめきた arm. Section solving ends 新大阪→大阪 on the 東海道線 passenger arm, which has no physical track link to the 大阪環状線, so the boundary stays unproven (~8 km along-track from the junction). Fix: solve the sections that meet at a stop jointly so the shared endpoint can be the うめきた arm. `JunctionApproachTests` lists this junction as the only explicit exception.

## r5 batch — 2026-10-04

Registry is 181 entries (162 zeroLength, 5 shortLink, 5 osmConnector, 9 osmTrack). Merged the r4 five-id fragment and applied its four backdates (岩沼 1898-12-31, 熱海 1935-12-31, 品川 1885-12-31, 青森 奥羽↔津軽 1951-12-05 with validTo cleared). Added 八代 鹿児島線↔肥薩おれんじ鉄道線 2004-03-13, 栗橋 osmConnector 2006-03-18 (way 142969198 idx 8–10), 赤羽 osmTrack (way 650168486), and 神田 osmTrack (way 211381364 idx 3–9 plus the existing display coordinate [139.770875, 35.69177]; endpoints are the surveyed vertices [139.77054, 35.69096] and [139.77121, 35.69258]). tokyo-east-20 validFrom is 2015-03-14. tokyo-east-21 validFrom is 1980-12-31 (year-only JR East media article; 1980-10-01 and 1976-10-01 were not in the saved pages).

`rail-history.json` revision stays `2026-09-28.3`. JR 東北線 copies: 盛岡–目時–八戸 (IGR plus 青い森 south, plus the 八戸 throat) valid_to 2002-12-01, and 八戸–青森 (青い森 north, plus the throat) valid_to 2010-12-04. Current-operator valid_from retirements match those extents. 青山’s 2006-03-18 station retirement stays after the IGR station stamp so it still wins. zeroLength `aomori-tohoku-tsugaru` is [140.73407, 40.82905] from 1951-12-05 until 2010-12-04. No 盛岡 junction (same 東北線 identity). No 八戸 cross-operator junction.

Not applied: 幡生 (no official junction day in the MLIT chronology, the JR West databook, or the 2025 瑞風 press). 高崎 / 新前橋 stay 2026-10-03 (1921-07-01 is not in the saved Gunma page or the MLIT chronology). 成田エクスプレス 東京 sourceCode is already the 総武線 id 003766. No 東北線↔奥羽線 junction at 青森 (shared vertex exists; no saved 奥羽 arrival day).

## r7 batch — 2026-10-04

Registry is 189 entries (170 zeroLength, 5 shortLink, 5 osmConnector, 9 osmTrack). Merged the r6 seven-id fragment: 富士 1913-12-31, 宇土 1899-12-25, 津幡 北陸線↔七尾線 1900-08-31 until 2015-03-14 (distinct from `tsubata-ir-nanao`), 金沢 IR↔北陸線 2015-03-14 until 2024-03-16, 佐古 2025-03-15, 和歌山市 1971-03-31, 内子 2018-07-17. Backdates: 立川 `tachikawa-east-33` 1894-12-31, 門司 `west-moji` 1942-07-01, 新前橋 `shin-maebashi-east-35` 1921-07-01. 高崎 `takasaki-east-34` stays 2026-10-03; 1921-07-01 is 渋川–新前橋, not 高崎. `kasukabe-isesaki-noda` keeps validFrom 2017-04-21 and validTo is now null. 2024-03-16 was the アーバンパークライナー withdrawal; Tobu news 3658 still runs 東武アーバンパークライン and 春日部駅始発スカイツリーライナー.

幡生 `hatabu-sanin-sanyo` is zeroLength at [130.92696, 33.98088], on both 西日本旅客鉄道 山陰線 and 山陽線 (class 11). validFrom 2026-10-03 is the fetched JR West timetable day. No 小串–幡生 opening day was in the saved official pages. The line board 山陰本線(益田～下関) for 2026年10月3日 links train 851D (`/train-timetable/67461`), which runs 小串–幡生–下関. No 山陰線 feature was added at 下関.

新八代 osmTrack was not applied. `rail-sections.json` feature 3004 (九州旅客鉄道/鹿児島線/11) already joins [130.63372, 32.51754] and [130.63386, 32.51771] (23.01 m). Nearest OSM cache vertices in E130N32 (fetchedAt 2026-08-18) are way 579487413 idx 40 at 87.1 m / 64.2 m and way 190662067 idx 5 at 88.9 m / 65.9 m. Both ends must attach within 50 m, so a registered osmTrack would be rejected.
## Dating rule (2026-10-04)

A junction's `validFrom` is the day the **physical link** existed — not the day a timetable or document first showed it, and not a company-split or ownership date (1987-04-01 JR split, 2002-12-01 IGR, 2015-03-14 IR/えちごトキめき, 2016-03-26 いさりび). When a link is as old as both rows it joins, `validFrom` is null (no lower bound). Newer links keep a sourced construction date. Evidence that only proves "documented existing on day X" stays in `temporalEvidence`, never in `validFrom`.

Applied in cf1b5623: 47 records re-dated (evidence-window or ownership dates → null or the physical date), including `tokyo-east-20` 2015-03-14 (上野東京ライン), `tokyo-east-21` 1980-10-01 (東京 東海道↔総武), `morioka-east-40` 1997-03-22 (秋田新幹線), `utazu-honshi-bisan-yosan-eastern-bypass` 1988-04-10 (both 宇多津 arms opened with the 瀬戸大橋線; the 2019-10-18 facility document stays as evidence), `aomori-ou-tsugaru-jn3` 1951-12-05 (no validTo), `naka-oguni-tsugaru-kaikyo` no validTo (the link is still physical). Genuine opening dates already in the registry were kept. Nine records were added where no equivalent existed (三島, 宇土, 七尾, 青森 ×2, 日暮里 approach, 奥津軽いまべつ 海峡線 OSM track, 木古内 海峡↔いさりび, 目時). Registry: 190 entries. With this, `TrainServicePatternRouteTests.everyLegSolves` passes for every pattern.

## r8 batch — 2026-10-05

Registry is 199 entries (177 zeroLength, 6 shortLink, 6 osmConnector, 10 osmTrack). Added two zeroLength rows, both `validFrom` null under the dating rule above.

`nagoya-chuo-tokaido` is [136.8824, 35.16994], on 東海旅客鉄道 中央線 (features 11921, 11922) and 東海道線 (feature 12060), class 11. Station code 005448. JR East Nagano press `151218.pdf` (saved sha256 `3f7e0e965845dbaa821a4414989a660da4b479b08e79dfd9941693e9602d3c2c`) page 4 changes 大阪発「しなの9号」 to start at 名古屋 (現行 大阪発 8:57, 改正 大阪発 ―) and 大阪行「しなの16号」 to end at 名古屋 (現行 大阪着 19:18, 改正 大阪着 ―). 2016-03-26 stays in `temporalEvidence`.

`higashi-kanagawa-tokaido-yokohama` is [139.6324, 35.47706], the south end of the shared 2-point segment on 東日本旅客鉄道 東海道線 (features 16230, 16232) and 横浜線 (feature 13886). No 京浜東北線 features; that track is the 東海道線 identity. Station code 004597. Weekend 新横浜 横浜線 board `0888041.html` (sha256 `684e6275e607a6cf9bfcedfb7f82c6a7234b4b073a5a55cbf358d54ebb6e7825`) legend maps 桜 to 桜木町, and a cell is `data-dest="桜"`. 1996-04-02 stays out of `validFrom`.

阪急: `kyo-train-garaku-umeda-kawaramachi` and `kyo-train-original-umeda-kawaramachi` already list `宝塚線` before `京都線` (`train-service-patterns.json` lines 22211–22214 and 22263–22266). Those are the only `"company": "阪急電鉄"` patterns. No line edit. Hankyu integrated report `408.pdf` (sha256 `9063775176ef6cc61369208a96367d1f3c061872790415784f12a7c707978dda`) says 1910 宝塚本線（梅田-宝塚） and 1921 北大阪電気鉄道（現：京都本線、千里線）（十三-豊津）. The 2007 securities report `169.pdf` page 37 lists 京都本線 梅田～河原町 47.7 km, so that km table includes 梅田–十三 inside 京都本線. No saved official page states a current extent 京都本線＝十三–京都河原町. Residual census pair is still 神戸線→京都線 at 十三: minimum surveyed gap 21.56 m, [135.48241, 34.7197] to [135.48263, 34.71977]. 京都線 has no vertex within 2 km of 大阪梅田. Existing `juso-takarazuka-kyoto` is 宝塚線↔京都線 and does not match the 神戸線 end the solver used. No 神戸線 shortLink was added.

武蔵野南線 was not registered. `rail-sections.json` and `rail-history.json` (revision `2026-09-28.3`) have no 武蔵野線 vertex south of about 35.665. OSM cache `E139N35.json` fetchedAt `2026-08-18T10:37:59.411Z` has a continuous 30-way chain of `name=JR武蔵野線`, endpoints ≤2 m, 28,428.9 m, longest step 1,105.9 m (way 395832258). Way ids in order: 243611867, 399827727, 556644026, 399827728, 696156367, 828152081, 828152079, 119940834, 153361131, 153361133, 696156374, 696156375, 696156376, 395832258, 395857429, 395857447, 696156373, 1370623531, 225006132, 225006130, 151997258, 151997246, 151997247, 1294910181, 151997257, 151997261, 151997249, 136165975, 136165976, 696156370. Fuchu end [139.47656, 35.6675] is 25.73 m from 武蔵野線 vertex [139.47664, 35.66772] feature 17288. Tsurumi OSM end [139.67746, 35.51218] is 22.4 m from 東海道線 vertex [139.67762, 35.51233] feature 21746 and has no 武蔵野線 surveyed vertex within 200 m. An osmTrack needs both ends on 武蔵野線 before the junction loop (`RouteGraph.swift` surveyed-node snapshot at line 1199; rejection "endpoint is not an existing vertex" at line 1251). A following junction cannot attach to path vertices of an earlier osmTrack. An osmConnector over the 28 km chain exceeds the 1,500 m cap. Same-train evidence is saved: stop list `100921.html` title 特急鎌倉（鎌倉－鶴見－吉川美南） lists 8088M/8089M, 鶴見, 西国分寺, 吉川美南, and does not name 府中本町; 武蔵野線 board `708d2p.html` column 8089M is 特急 鎌倉 on 府中本町－西船橋－海浜幕張. 1976-03-01 was not used as a `validFrom` because nothing was registered.

杵築→中津 is diagnosis only. See scratchpad `r8/diag-kitsuki.md`. Ten interior station dots sit on 日豊線 edges (lateral ≤0.025 m, neighbour spans 30.1–410.6 m). The 520 m anchor-skip does not run because those dots are on the identity edge.

## r9 batch — 2026-10-05

Registry is 200 entries (177 zeroLength, 6 shortLink, 6 osmConnector, 11 osmTrack).

杵築→中津: an on-edge station anchor (lateral ≤1 m) is carried with `onEdgeIdentityPath` to the next same-identity node, the station coordinate pending, walk ≤520 m. A longer edge (the 700 m direct-edge case) still falls through to the direct edge. `sameIdentitySpan` is not used for that carry. The census path for `36-plus-3-blue-oita-hakata` 杵築→中津 on 2026-10-03 is `OnEdgeCertificationTests.censusKitsukiToNakatsu`.

`musashino-minami-fuchuhommachi-tsurumi` is osmTrack on 東日本旅客鉄道/武蔵野線/11 from the 府中本町 vertex [139.47664, 35.66772] (feature 17288, attach 25.73 m) along the 30-way OSM chain in `E139N35.json` (fetchedAt 2026-08-18T10:37:59.411Z, 28,428.9 m, 309 vertices, longest step 1,105.9 m) to an `endJunction` on 東日本旅客鉄道/東海道線/11 at [139.67762, 35.51233] (feature 21746, stub 22.27 m). The path edges stay on 武蔵野線 with no junction mark. The stub is one reviewed hop, so `sameIdentitySpan` does not cross it. Same-train evidence is 特急 鎌倉 8088M/8089M: `https://timetables.jreast.co.jp/2610/train/100/100921.html` and `https://timetables.jreast.co.jp/2610/timetable-v/708d2p.html`. Dating rule: `validFrom` is null. 1976-03-01 is journalism (Diamond/Oricon, March 2026, “50th anniversary on March 1”), not an official JR or MLIT opening page, so it stays in `temporalEvidence`.

京とれいん 雅洛: a service preferred-line list is no longer widened by every common station-membership line. 大阪梅田 and 十三 both have a 神戸線 platform, so that line was joining the preferred set and the 8× penalty never applied. 宝塚線 stays preferred; 神戸線 does not. No weight change. No 神戸線 shortLink. The 十三 boundary uses the existing `juso-takarazuka-kyoto` hop. Regression: `TrainServicePatternsTests.garakuRidesTakarazukaThroughJuso`.
