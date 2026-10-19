# 铁路身份 Phase 0 冻结清单

日期 2026-10-19。本文只清点本检出里的迁移输入，不改几何、历史或包。保护样例以 `docs/reference/railway-data-overhaul-preparation.md` 第 83–94 行（ADR §9.6 同表）为准，再按名称在本树检索。

哈希见 `app/data/registry/phase0-freeze.json`（`schema` = `jtm-registry-freeze/1`）。

## a. 范围

`app/public/rail/*-2025.json` 共 6 个 `format: compact-v1`：`cn-2025.json`（`2026.10.18`，25546573 字节）、`hk-2025.json`（`2025.2.1`，167988）、`jp-2025.json`（`2025.5.2`，10094306）、`kr-2025.json`（`2025.1.0`，866015）、`mo-2025.json`（`2025.2.0`，8318）、`tw-2025.json`（`2025.6.1`，492537）。地区代码为 `cn`、`hk`、`jp`、`kr`、`mo`、`tw`。

本检出没有 `us-2025.json`、`ca-2025.json`、`na-2025.json`。ADR §5 的 P4 排除 NA。`load.mjs` 的 `COUNTRIES`（第 21–28 行）是这六个 slug，末项为 `cn`。

## b. 当前 schema

`app/scripts/build/rail-database/schema.sql` 有 36 张表。文件不写版本号。`load.mjs:1002` 执行 `insertMeta.run("schema_version", "4");`。

- `meta` :32 构建来源键值，含 `schema_version`
- `country` :37 每个已发布国家包一行
- `country_language` :61 读音表的界面语言
- `data_source` :71 几何、属性、读音的来源文本
- `institution_type` :85 N02 事业者种别码
- `railway_class` :94 N02 铁道区分码
- `roma_source` :102 compact 站行第 6 字段的罗马字来源码
- `structure_kind` :107 隧道/桥梁种类码
- `service_status` :112 `serviceSpans` 状态码
- `name_field` :121 读音表字段名
- `operator` :129 包内运营者
- `operator_alias` :143 公司别称到显示名
- `line` :153 包线路；主键即 package line id；`railway_identity` 在第 169 行
- `line_alignment` :191 JP 方向配对的父线
- `line_alignment_pair` :200 上下行成对区间
- `line_service_span` :213 非普通客运区间（按站序号）
- `line_extra_segment` :224 额外线段（HK 缺中心线）
- `line_reversal_tail` :235 折返尾（阿里山）
- `line_structure` :244 隧道/桥梁的米制范围
- `lane` :257 共享走廊的屏幕 lane
- `station` :275 物理站群
- `station_english` :292 审定英文名
- `station_english_jp` :313 JP 站群码的英文投影
- `line_station` :333 一条线上的一个停靠
- `line_station_english` :350 站群合并后的逐线英文
- `interval` :365 站间区间
- `interval_vertex` :384 区间折线顶点
- `station_name` :401 `station-names*.json` 的镜像
- `line_station_name` :419 落到每个 `line_station` 的名称
- `source_section` :435 求解器区间图
- `source_section_vertex` :448 求解区间几何
- `source_station` :461 站台码与包站群的交叉引用；`station_id` 可空（第 467 行）
- `source_station_vertex` :483 站台中心线
- `logo_asset` :503 引用的徽章文件
- `logo_credit` :510 逐线徽章署名
- `operator_logo_manifest` :516 运营者徽标来源

另有 7 个视图，不持有身份：`station_detail` :302、`jp_station_detail` :322、`line_name` :544、`station_name_wide` :555、`station_line` :580、`interval_detail` :591、`badge_provenance` :621。

## c. 旧身份空间

线路 id 在 `lines[].id`。后缀正则：`-N` = `(?<!p)-\d+$`；`-pN` = `-p\d+$`；两者兼有 = `-\d+-p\d+$`（这 2 条算在 `-pN` 里，不算在 `-N` 里）。站群码是包内 `lines[].stations[][0]`，也是 `stations*.json` 的 `properties.n02_group_code`。站台码是 `properties.n02_station_code`（加载时 `load.mjs:270–271` 亦接受 `N02_005c` / `N02_005g`）。

| 地区 | 线 | `-N` | `-pN` | 兼有 | 包内站行 / 唯一站群 | GeoJSON 要素 / 唯一站群 / 唯一站台 |
|---|---:|---:|---:|---:|---|---|
| cn | 3991 | 3990 | 0 | 0 | 21573 / 14065 | 21576 / 14066 / 14066 |
| hk | 28 | 8 | 0 | 0 | 453 / 282 | 453 / 282 / 282 |
| jp | 658 | 46 | 16 | 2 | 10234 / 9042 | 10237 / 9046 / 10154 |
| kr | 82 | 0 | 0 | 0 | 1412 / 1097 | 1412 / 1097 / 1400 |
| mo | 3 | 0 | 0 | 0 | 17 / 15 | 17 / 15 / 15 |
| tw | 39 | 0 | 0 | 0 | 586 / 505 | 586 / 507 / 559 |

线 id 例：`cn-osm-relation-152884`，`cn-osm-relation-162982-branch-2`，`cn-guangshengan-hsr`；`hk-mtr-ael`，`hk-mtr-lr-505`；`jp-IRいしかわ鉄道-IRいしかわ鉄道線`，`jp-九州旅客鉄道-筑肥線-2`，`jp-東日本旅客鉄道-上越線-p2`，`jp-東海旅客鉄道-東海道線-2-p1` 与 `jp-九州旅客鉄道-鹿児島線-2-p1`；`kr-gyeongbuseon`；`mo-mlm-taipa`；`tw-alsr-alishan`，`tw-klrt-c`。HK 的 8 个 `-N` 都是轻铁路线号（`hk-mtr-lr-505`、`507`、`610`、`614`、`615`、`705`、`706`、`751`），不是几何分段。CN 的 3990 个 `-N` 是 OSM relation 数字后缀、`-branch-N`，以及 `cn-osm-named-151201073`、`cn-osm-named-100198457`；关系形 1241、分支形 2747。唯一不以数字结尾的是 `cn-guangshengan-hsr`。这不是 JP 那种几何分段。

站台码：JP 10237 行全是 6 位，例 `010112`、`010127`、`004091`；站台码 ≠ 站群码 1146 行。包内多出的站群是 `M000001`、`M000002`；只在 GeoJSON 的站群是 `000078`、`000084`、`000093`、`000099`、`000382`、`000428`。HK：`MTR-` 125 行 / 98 个唯一值（`MTR-HOK`、`MTR-KOW`、`MTR-TSY`），`LR-` 205 行，`TRAM-` 123 行。TW 没有字面 `OP-` 前缀；行数 TRA 260、TRTC 124、KRTC 39、KLRT 38、AFR 23、TYMC 22、TMRT 18、NTDLRT 15、NTMCC 14、THSR 12、NTMC 12、NTALRT 9，例 `THSR-0990`。0010 第 13 行与 `StationCodeAliases.swift:19` 把这套语法称作 `OP-ID`；`tw-2025.sources.md:269` 写明字段是 TDX `StationUID`。KR 全部为 `KR-`（1412 行 / 1400 唯一），例 `KR-GYEONGBUSEON-BUSAN`。MO 全部为 `MLM-`（17 行 / 15 唯一），例 `MLM-BARRA`；没有 `MTR-` 行。CN 站台码两族：`CN-OSM-` 17416 行（例 `CN-OSM-N6270117708`）、`CN-12306-` 4160 行（例 `CN-12306-IZQ` 广州南、`CN-12306-SBT` 沈阳北、`CN-12306-PNE` 攀枝花南）。同文件 `CN-12306-GZS` 是光泽，不是广州南。只在 GeoJSON 的站群是 `cn-official-12306-psw`。`source_review_id` 在 3 个要素上：成都南 `CN-12306-CNW`、彭山 `CN-12306-PSW`（同值 `cn-reviewed-physical-10286390-chengdu-north`）、西昌西 `CN-12306-XCE`（`cn-reviewed-physical-10259709-chengdu-north`）。

`railway_identity`：库列在 `schema.sql:169`，由 `load.mjs:722` 写入 `line.railwayIdentity`。`app/data/rail.db` 只是 Git LFS 指针（134 字节，oid `d7bbd736…`，标称 137682944 字节），本检出不能做 SQL 计数。值在 `jp-2025.json` 的 `railwayIdentity`：658 行都有，595 个不同值，41 个值被多线共用（最多 9）。例：`jp-IRいしかわ鉄道-IRいしかわ鉄道線`、`jp-WILLER　TRAINS-宮津線`、`jp-jr-east-ueno-tokyo-through`（该值在包内）。CN/HK/KR/MO/TW 的 line 对象没有这个字段。

旧别名在 `ios/RailKit/Sources/RailCore/StationCodeAliases.swift`，`enum` 第 22 行，`canonical` 第 25 行。没有别名表，只有三条改写再加原样返回：倒数第二段是 `MTR`/`LR`/`MLM` 时只留最后两段（第 23、29–30 行）；首段 `TRAM` 收成 `TRAM-` + 末段（第 32–33 行）；第二段 `NETWORK` 则删掉该段（第 35–38 行）；其余原样（第 40 行），包括 JP 六位码和 TW `OP-ID`。当前 `stations-hk.json` / `stations-mo.json` 已是 `MTR-HOK`、`MLM-BARRA` 这种规范形。`hk-2025.sources.md:15` 与 `mo-2025.sources.md:12` 仍举例旧的嵌线写法 `TML-MTR-WKS`、`MLM-TAIPA-MLM-BARRA`。

## d. 外部引用

装载后都进 `source_station.station_code` / `group_code`（`schema.sql:465–466`；注释第 456–460 行）。没有名为 `osm`、`n02` 或 `source_review` 的列。

- JP：N02 站台 `n02_station_code`、站群 `n02_group_code`，文件 `app/data/stations.json`。线 id 与 `railwayIdentity` 在 `jp-2025.json` 的 `lines[]`。
- TW：TDX `StationUID` 存在 `stations-tw.json` 的 `n02_station_code`（`tw-2025.sources.md:269`）。站群 `n02_group_code` 与包内 `tw-official-…`。语法名 `OP-ID` 见 0010:13，不是单独字段。
- HK：站台码在 `stations-hk.json` 的 `n02_station_code`（`MTR-` / `LR-` / `TRAM-`）。OSM route relation 只作为几何来源写在 `hk-2025.sources.md:133`，不是站码列。
- MO：`stations-mo.json` 的 `n02_station_code` 为 `MLM-…`（`mo-2025.sources.md:12`）。
- KR：合成站码 `KR-<linePrefix>-<slug>` 在 `stations-kr.json` 的 `n02_station_code`（`kr-2025.sources.md:20–23`）。官方记录来自 data.go.kr（同文件第 31–33 行）。OSM 只用于中心线（第 35 行）。本检出没有 KRIC 站码字段；`KRIC` 只出现在 `station-english` 审校稿的散文里。
- CN：站台码在 `stations-cn.json` 的 `n02_station_code`（`CN-12306-` / `CN-OSM-`）。`source_review_id` 只在 3 个要素上，是审阅 provenance，不是站码列。线 id 在 `cn-2025.json`。
- NA：无包。`app/scripts/railway/build-north-america-rail-package.py:431` 与 `:608` 有 `osmRelationByRouteId`，`load.mjs` 不读它。

## e. 事实 owner

对照 ADR §3.8–§3.10。检索范围是 `*.swift`、`*.py`、`*.mjs`、`*.js`、`*.json`、`*.sql`。符号都在本检出。

§3.8：`CompactPackage.decodeIntervals` `CompactPackage.swift:252`；`decodeIntervals` `app/public/rail-network.js:910`（另有 `jp-manual-corrections/geo.mjs:89`）；`decoded_intervals` `build-display-network.py:352`（另有 `make-na-sample-stores.py:165`）；`decodeDisplayIntervals` `CompactPackage.swift:290`；`displayStationCoordinates` `CompactPackage.swift:90`；`displayPartsForLine` `rail-network.js:1379`；`DisplayParts` 是 `DisplayParts.swift:52` 的 enum；`LineTopology` 第 233 行，`reversalTails` / `extraSegments` 第 239–240 行；`build-display-lanes.mjs` 与 `build-display-network.py` 在 `app/scripts/railway/`；`display-lanes.json` 在 `app/public/rail/`。`BatchInspectionPlan` `BatchInspection.swift:83`；`pointOrdinal` 同文件第 67 行。

§3.9：`serviceSpans` 由 `load.mjs:832` 与 `serviceSplitForLine`（`rail-network.js:2274`）消费；`CompactPackage.Line` 的 CodingKeys（`CompactPackage.swift:143–147`）不含 `serviceSpans`。`drawsContinuousStroke` `rail-network.js:3207`。`strokeExcludedByRegion` `build-display-lanes.mjs:3489`。`LineServiceCatalog` `LineServiceCatalog.swift:5`。`RailHistoryOverlay` `RailHistory.swift:102`。`RailHistoryStations` `RailHistoryStations.swift:39`。`RailDisplayHistoryFile` `RailDisplayNetworkFormats.swift:684`。`build_region_history` `build-display-network.py:2644`。`JapanThroughServices` `JapanThroughServices.swift:6`。

§3.10：`DiagnosticRequest` `ios/auxiliary/RailAlignmentInspector/InspectionKit/Sources/RailInspection/DiagnosticRequest.swift:84`；`DiagnosticSession` `ios/auxiliary/RailDiagnostics/Sources/DiagnosticSession.swift:10`；`BatchInspectionIdentity` `BatchInspection.swift:41`；`evidenceSHA256` `DiagnosticReview.swift:7`（写入 `DiagnosticSession.swift:301`）；`pointOrdinal` 与 `BatchInspectionPlan` 见上。检出内没有名为 `identity-plan-*.json` 的文件。写入点是 `BatchCaptureController.swift:396` 与 `:536`。报告只引用库外路径，例如万叶准备文档第 11 行的 `identity-plan-4c6abd39….json`。

## f. 修复 authority 与已否决候选

下文 `Q` = `docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012`。`applyPreparedWrites` 在 `app/scripts/railway/repair-three-reversal-extents.mjs:233`。

- 横滨相铁、糸鱼川：FOUND。`app/scripts/railway/repair-yokohama-itoigawa-own-platform-display.mjs:21–22`（相铁本线 `004633` 区间 0、大糸线 `001666` 区间 7）与 `yokohama-itoigawa-own-platform-display-evidence.json`。
- 品川／大崎：FOUND。`repair-shinagawa-apple-forks-display.mjs:15`、`repair-shinagawa-display-lanes.mjs`、`repair-tokyo-southern-branches.py`、`tokyo-southern-branches-overrides.json`、`docs/reports/japan/tokyo-osaki-legacy-repair-2026-10-01.md`、`docs/reports/japan/tokyo-southern-branch-audit-2026-10-01.md`、`docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/osaki/latest-fragments-source-review.md`。
- 京叶 shared fork：FOUND。`app/scripts/railway/keiyo-shared-corridor-evidence.json:3–5`（干线 `jp-東日本旅客鉄道-京葉線`，支线 `-2`）。
- 北松江 #6：FOUND。`repair-ichibata-kitamatsue-display.mjs:31` 只删 15/17/19；`:62–64` 把自跟随源后缀重测，target part1 保持 `150, 0`。证据 `ichibata-kitamatsue-display-evidence.json`。审查 `Q/ichibata-kitamatsue-complete/interval-6-own-source-review-20261019.md`。
- 渡良濑花轮 #8：FOUND。`watarase-hanawa-step-display-evidence.json:6` 只删区间 8 的 vertex 5，保留 v4 与前一组 v2/v3。写者 `repair-watarase-hanawa-step-display.mjs:22`。审查 `Q/watarase-keikoku-complete/hanawa-step-own-source-review-20261019.md`。
- 宫津 #9/#15：FOUND。`miyazu-yosano-display-evidence.json:6` 为区间 9；`:6763` 写明 #9 已应用，#15 是另案未决。审查 `Q/miyazu-complete/interval-9-source-review.md` 与 `interval-15-own-source-review-20261018.md`。写者 `repair-miyazu-yosano-display.mjs`。
- 夷隅 `substitute_bus`：FOUND。`jp-manual-corrections/corrections.json:43–60` id `A3`，`lineId` `jp-いすみ鉄道-いすみ線`。显示修复另有 `repair-isumi-kurohara-display.mjs` 与 `isumi-kurohara-display-evidence.json`。
- 宫福 rejected：FOUND。`Q/miyafuku-complete/rejected-interval0-candidate-20261018/README.md:1–7`。当前写者仍是 `repair-miyafuku-own-display.mjs`，证据 `miyafuku-own-display-evidence.json`。否决快照是同目录的 `miyafuku-own-display-evidence.json`，不是现行 authority。
- 布崎 rejected：FOUND，无独立候选文件。`Q/chat-handoff-20261017/work-inventory-20261019.md:73` 记录窄替换会产生 24.37° 接头并否决。来源审查 `Q/ichibata-kitamatsue-complete/interval-11-own-source-review-20261019.md`。
- 西野尻 rejected：FOUND，审查明确不建候选。`Q/sangi-sangi-complete/interval-13-own-source-20261019/interval-13-own-source-review-20261019.md:3`；`work-inventory-20261019.md:74`。
- CN `source_review_id` 与地铁误标：FOUND。`docs/reports/sources/china-real-train-paths-20261018/three-connectors-source-review.json:377` 与 `:392`；`overhaul-handoff-20261019.md:49`。站表三处见 §c。地铁误标见 `docs/reports/sources/crtrainroute-study-20261018.md:174` 与 `china-real-train-paths-20261018/README.md:221`。
- 广州南／沈阳北／攀枝花南、楚雄—丽江：FOUND。`crtrainroute-study-20261018.md:174` 与 `:179` 保留沈阳北、广州南、攀枝花南缺证。`chuxiong-lijiang-continuation4.json:4` 只调查楚雄→丽江，不补边。广州南站码是 `CN-12306-IZQ`，不是 `GZS`。
- Manyo 旧 23 对与缺失 named plan：FOUND。`Q/manyo-shinminato-complete/preparation-20261019.md:7–11` 保留 23 对，并写明 `identity-plan-4c6abd39ef63d0d3997036c5a4d763f2f51e0cf5c88bd17f25537270c44f3869.json` 不在库内。`work-inventory-20261019.md:76` 与 `:180`。东线写者 `repair-manyo-east-display.mjs` 与 `manyo-east-display-evidence.json` 是另一条已接受显示修复，不是这 23 对的 named plan。

本地仅有、不写入 `protectedFiles`：`.gitignore:192` 排除 `app/scripts/railway/*-apple-*evidence.json`。脚本点名的两个文件是 `mita-apple-display-evidence.json`（`repair-mita-apple-display.mjs:21`）与 `shinagawa-apple-forks-display-evidence.json`（`repair-shinagawa-apple-forks-display.mjs:15`）。本工作树磁盘上没有这两个文件，因此不哈希。

## g. 例外清单

已写明、本阶段不重算的例外都在 ADR，没有单独报告文件。`unmapped-source`：`source_station.station_id IS NULL` 为 JP 6 行、TW 2 行（ADR 第 95、424 行）。`rail.db` 是 LFS 指针，这 8 行没有在本检出重查。`identity-not-a-railway` 的例子 `jp-jr-east-ueno-tokyo-through` 在 JP 包的 `railwayIdentity` 里。其余已知例子只在 §9.5：都营新宿多站码、`shared-facility-candidate` 的押上/目黒等、`name-line-not-unique` 的 JP 3 / TW 2 / CN 81、`line-label-collision` 的 `本線` ×11 与 `東海道線` ×3。CN 81 仍是 ADR §9.5 的数字；本冻结没有重算 CN 的 `(站名, 线名)` 组。

P0（身份账本，不是本冻结）将按 §9.5 生成、且只列不改的报告：`line-family-candidate`、`same-operator-split-names`、`same-operator-multi-codes`、`cross-complex-same-station`、`unmapped-source`、`ambiguous-company-text`、`identity-not-a-railway`、`history-unmatched`、`shared-facility-candidate`、`name-line-not-unique`、`line-label-collision`、`line-alias-is-country-code`。这些报告文件现在都不存在。

## h. 注册表输入白名单

不变量 11（ADR 第 273 行）：注册表输入只有 compact 包、站点表、名称表、历史叠加与审定覆写。`registryInputs` 共 22 条，哈希在 `phase0-freeze.json`：

- 包：`app/public/rail/{cn,hk,jp,kr,mo,tw}-2025.json`
- 站点表：`app/data/stations.json`、`stations-{cn,hk,kr,mo,tw}.json`（`readSources` 第 231–232 行）
- 名称表：`app/data/station-names.json`、`station-names-{cn,hk,kr,mo,tw}.json`。`load.mjs:239` 把 `COUNTRIES` 里的 `station-readings*` 改写成这些名称表再读。已发布英文名 `station-english.json`（`:222`）与 `station-english-jp.json`（`:241–242`）
- 历史叠加：`app/data/rail-history.json`。`readSources` 不打开它；不变量 11 仍把它算作输入。盘上没有其他 `rail-history-*.json`。`RailHistory.swift:96` 的注释仍允许 `rail-history[-<cc>].json`，分国家文件不在盘上
- 额外钉住：`app/data/station-readings-cn.json`。`load.mjs:239` 实际打开的是 `station-names-cn.json`。其他 `station-readings*` 不进白名单
- 审定覆写：无。ADR §9.1 第 313 行计划的 `app/data/registry/{region}/station-derivation-exceptions.json` 不存在

`readSources`（`load.mjs:218`）还读取、并留在白名单外的文件：`rail-sections.json` 与 `rail-sections-{cn,hk,kr,mo,tw}.json`（`:229–230`、`:244`）；`app/public/rail/logo-credits.json`（`:252`）；存在才读的 `operator-logos/jp/manifest.json` 与 `operator-logos/jp-badges/manifest.json`（`:253–258`）；`app/public/app-operator-branding.js`（`loadBranding` `:121`）。`{slug}-2025.sources.md` 只做 `existsSync`（`:237`）。

同样不在白名单：`display-lanes.json`；`corrections.json` 与 `app/data/**/candidates/`；`station-names-coverage.json`；`station-english-verified-*`、`station-english-kr-second-pass*`、`station-english-coverage.json`；`tokyo-southern-branches-overrides.json`；`jp-directional-alignment-overrides.json`；`app/scripts/railway/jp-rail-history-events.json`（构建原料）。`display-lanes.json`、`corrections.json` 与 `tokyo-southern-branches-overrides.json` 在 §i 受保护。

## i. 受保护文件

`protectedFiles` 共 47 条，全部是已跟踪文件（上限 60）。P0 期间字节必须不变。完整路径与 sha256 在 `phase0-freeze.json`。其中 6 个 compact 包与 `app/data/rail-history.json` 同时是注册表输入。铸造只读 `registryInputs`。

受保护且不是注册表输入的有：`app/public/rail/display-lanes.json`；§f 的修复写者与证据（横滨相铁／糸鱼川、京叶 shared corridor、北松江 #6、花轮 #8、宫津 #9、夷隅显示、宫福现行证据、万叶东线、品川 fork 写者、品川派生尺、大崎／品川南支 Python 与 `tokyo-southern-branches-overrides.json`、`repair-three-reversal-extents.mjs`）；审查与否决记录（北松江 #6、布崎 #11、花轮、宫津 #9 与 #15、宫福 `rejected-interval0-candidate-20261018/README.md` 及其否决快照 `miyafuku-own-display-evidence.json`、西野尻、万叶 `preparation-20261019.md`、`work-inventory-20261019.md`、大崎 `latest-fragments-source-review.md`、东京大崎旧修复与南支审计）；CN 缺证（`crtrainroute-study-20261018.md`、`china-real-train-paths-20261018/README.md`、`three-connectors-source-review.json`、`overhaul-handoff-20261019.md`、`chuxiong-lijiang-continuation4.json`）。

未列入：测试、`highspeed-catalog.json`、时刻表报告、诊断采集索引、京叶其他曲线证据、否决目录里的 `.mjs.txt` 文本快照、`railway-repair-workflow.md`、`china-production-evidence` 副本、万叶 `existing-evidence`、整棵 osaki／manyo 抽取树。布崎与西野尻只有审查散文，没有单独的否决候选 JSON。

本地仅有、不写入 `protectedFiles`、不哈希：`.gitignore:192` 排除 `app/scripts/railway/*-apple-*evidence.json`。脚本点名 `mita-apple-display-evidence.json`（`repair-mita-apple-display.mjs:21`）与 `shinagawa-apple-forks-display-evidence.json`（`repair-shinagawa-apple-forks-display.mjs:15`）。本工作树磁盘上没有这两个文件。

## 附：冻结基线

本冻结的基线是 main `daeae851` 加上本分支（HEAD `13e82fca`）。`railway-sources/local/` 按仓库政策只留在本机（`.gitignore` 第 86 行），不进入 `protectedFiles`。
