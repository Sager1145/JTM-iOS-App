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
