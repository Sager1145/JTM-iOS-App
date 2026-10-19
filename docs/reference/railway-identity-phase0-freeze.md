# 铁路身份 Phase 0 冻结清单

日期 2026-10-19。本文只清点本检出里的迁移输入，不改几何、历史或包。`docs/reference/railway-data-overhaul-preparation.md` 不在本检出（无 `docs/reference/` 目录；ADR 0013 第 4、7 行有链接）。保护样例以 ADR §9.6 第 449–458 行（该处注明准备文档 L83–94）为准，再按名称在本树检索。

哈希见 `app/data/registry/phase0-freeze.json`（`schema` = `jtm-registry-freeze/1`）。

## a. 范围

`app/public/rail/*-2025.json` 共 5 个 `format: compact-v1`：`hk-2025.json`（`2025.2.1`，167988 字节）、`jp-2025.json`（`2025.5.2`，9587739）、`kr-2025.json`（`2025.1.0`，866015）、`mo-2025.json`（`2025.2.0`，8318）、`tw-2025.json`（`2025.6.1`，492537）。地区代码为 `hk`、`jp`、`kr`、`mo`、`tw`。

本检出没有 `cn-2025.json`、`us-2025.json`、`ca-2025.json`、`na-2025.json`。CN 与 NA 没有已提交的包。`load.mjs` 的 `COUNTRIES`（第 20–26 行）同样只有这五个 slug。ADR §5 的 P4 排除 NA。

## b. 当前 schema

`app/scripts/build/rail-database/schema.sql` 有 36 张表。文件不写版本号。`load.mjs:993` 执行 `insertMeta.run("schema_version", "3");`。

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
| hk | 28 | 8 | 0 | 0 | 453 / 282 | 453 / 282 / 282 |
| jp | 657 | 45 | 16 | 2 | 10232 / 9042 | 10237 / 9046 / 10154 |
| kr | 82 | 0 | 0 | 0 | 1412 / 1097 | 1412 / 1097 / 1400 |
| mo | 3 | 0 | 0 | 0 | 17 / 15 | 17 / 15 / 15 |
| tw | 39 | 0 | 0 | 0 | 586 / 505 | 586 / 507 / 559 |

线 id 例：`hk-mtr-ael`，`hk-mtr-lr-505`；`jp-IRいしかわ鉄道-IRいしかわ鉄道線`，`jp-九州旅客鉄道-筑肥線-2`，`jp-東日本旅客鉄道-上越線-p2`，`jp-東海旅客鉄道-東海道線-2-p1` 与 `jp-九州旅客鉄道-鹿児島線-2-p1`；`kr-gyeongbuseon`；`mo-mlm-taipa`；`tw-alsr-alishan`，`tw-klrt-c`。HK 的 8 个 `-N` 都是轻铁路线号（`hk-mtr-lr-505`、`507`、`610`、`614`、`615`、`705`、`706`、`751`），不是几何分段。

站台码：JP 10237 行全是 6 位，例 `010112`、`010127`、`004091`；站台码 ≠ 站群码 1146 行。包内多出的站群是 `M000001`、`M000002`；只在 GeoJSON 的站群是 `000078`、`000084`、`000093`、`000099`、`000382`、`000428`。HK：`MTR-` 125 行 / 98 个唯一值（`MTR-HOK`、`MTR-KOW`、`MTR-TSY`），`LR-` 205 行，`TRAM-` 123 行。TW 没有字面 `OP-` 前缀；行数 TRA 260、TRTC 124、KRTC 39、KLRT 38、AFR 23、TYMC 22、TMRT 18、NTDLRT 15、NTMCC 14、THSR 12、NTMC 12、NTALRT 9，例 `THSR-0990`。0010 第 13 行与 `StationCodeAliases.swift:19` 把这套语法称作 `OP-ID`；`tw-2025.sources.md:269` 写明字段是 TDX `StationUID`。KR 全部为 `KR-`（1412 行 / 1400 唯一），例 `KR-GYEONGBUSEON-BUSAN`。MO 全部为 `MLM-`（17 行 / 15 唯一），例 `MLM-BARRA`；没有 `MTR-` 行。

`railway_identity`：库列在 `schema.sql:169`，由 `load.mjs:714` 写入 `line.railwayIdentity`。`app/data/rail.db` 只是 Git LFS 指针（134 字节，oid `d7bbd736…`，标称 137682944 字节），本检出不能做 SQL 计数。值在 `jp-2025.json` 的 `railwayIdentity`：657 行都有，595 个不同值，41 个值被多线共用（最多 9）。例：`jp-IRいしかわ鉄道-IRいしかわ鉄道線`、`jp-WILLER　TRAINS-宮津線`、`jp-jr-east-ueno-tokyo-through`（该值在包内）。HK/KR/MO/TW 的 line 对象没有这个字段。

旧别名在 `ios/RailKit/Sources/RailCore/StationCodeAliases.swift`，`enum` 第 22 行，`canonical` 第 25 行。没有别名表，只有三条改写再加原样返回：倒数第二段是 `MTR`/`LR`/`MLM` 时只留最后两段（第 23、29–30 行）；首段 `TRAM` 收成 `TRAM-` + 末段（第 32–33 行）；第二段 `NETWORK` 则删掉该段（第 35–38 行）；其余原样（第 40 行），包括 JP 六位码和 TW `OP-ID`。当前 `stations-hk.json` / `stations-mo.json` 已是 `MTR-HOK`、`MLM-BARRA` 这种规范形。`hk-2025.sources.md:15` 与 `mo-2025.sources.md:12` 仍举例旧的嵌线写法 `TML-MTR-WKS`、`MLM-TAIPA-MLM-BARRA`。

## d. 外部引用

装载后都进 `source_station.station_code` / `group_code`（`schema.sql:465–466`；注释第 456–460 行）。没有名为 `osm`、`n02` 或 `source_review` 的列。

- JP：N02 站台 `n02_station_code`、站群 `n02_group_code`，文件 `app/data/stations.json`。线 id 与 `railwayIdentity` 在 `jp-2025.json` 的 `lines[]`。
- TW：TDX `StationUID` 存在 `stations-tw.json` 的 `n02_station_code`（`tw-2025.sources.md:269`）。站群 `n02_group_code` 与包内 `tw-official-…`。语法名 `OP-ID` 见 0010:13，不是单独字段。
- HK：站台码在 `stations-hk.json` 的 `n02_station_code`（`MTR-` / `LR-` / `TRAM-`）。OSM route relation 只作为几何来源写在 `hk-2025.sources.md:133`，不是站码列。
- MO：`stations-mo.json` 的 `n02_station_code` 为 `MLM-…`（`mo-2025.sources.md:12`）。
- KR：合成站码 `KR-<linePrefix>-<slug>` 在 `stations-kr.json` 的 `n02_station_code`（`kr-2025.sources.md:20–23`）。官方记录来自 data.go.kr（同文件第 31–33 行）。OSM 只用于中心线（第 35 行）。本检出没有 KRIC 站码字段；`KRIC` 只出现在 `station-english` 审校稿的散文里。
- CN：无包，无 `source_review_id` 数据字段。该符号只在 ADR 0013。
- NA：无包。`app/scripts/railway/build-north-america-rail-package.py:431` 与 `:608` 有 `osmRelationByRouteId`，`load.mjs` 不读它。

## e. 事实 owner

对照 ADR §3.8–§3.10。检索范围是 `*.swift`、`*.py`、`*.mjs`、`*.js`、`*.json`、`*.sql`。

§3.8 均在本检出，除最后两项：`CompactPackage.decodeIntervals` `CompactPackage.swift:248`；`decodeIntervals` `app/public/rail-network.js:876`（另有 `jp-manual-corrections/geo.mjs:89`）；`decoded_intervals` `build-display-network.py:238`（另有 `make-na-sample-stores.py:165`）；`decodeDisplayIntervals` `CompactPackage.swift:286`；`displayStationCoordinates` `CompactPackage.swift:90`；`displayPartsForLine` `rail-network.js:1345`；`DisplayParts` 是 `DisplayParts.swift:52` 的 enum；`reversalTails` / `extraSegments` 同文件第 239–240 行；`build-display-lanes.mjs` 与 `build-display-network.py` 在 `app/scripts/railway/`；`display-lanes.json` 在 `app/public/rail/`。`BatchInspectionPlan`、`pointOrdinal`：MISSING（只出现在 ADR）。

§3.9 均在：`serviceSpans` 由 `load.mjs` 与 `serviceSplitForLine`（`rail-network.js:2212`）消费；`CompactPackage.Line` 的 CodingKeys（`CompactPackage.swift:145`）不含 `serviceSpans`。`drawsContinuousStroke` `rail-network.js:3106`。`strokeExcludedByRegion` `build-display-lanes.mjs:3304`。`LineServiceCatalog` `LineServiceCatalog.swift:5`。`RailHistoryOverlay` `RailHistory.swift:102`。`RailHistoryStations` `RailHistoryStations.swift:39`。`RailDisplayHistoryFile` `RailDisplayNetwork.swift:661`。`build_region_history` `build-display-network.py:2414`。`JapanThroughServices` `JapanThroughServices.swift:6`。

§3.10 全部 MISSING：`DiagnosticRequest`、`DiagnosticSession`、`BatchInspectionIdentity`、`evidenceSHA256`、`pointOrdinal`、`BatchInspectionPlan`。`identity-plan-*.json` 0 个文件。上述符号的检索没有命中源码或 JSON。

## f. 修复 authority 与已否决候选

`docs/reports/` 与 `docs/reports/japan/` 不存在。ADR §9.6-7 点名的 `repair-three-reversal-extents.mjs` / `applyPreparedWrites` 只出现在 ADR 第 460 行。

- 横滨相铁：NOT FOUND in this checkout。检索 `横浜相鉄`、`相鉄`、`Sotetsu`。命中的是线路目录与拓扑，没有修复 authority。
- 糸鱼川：NOT FOUND。检索 `糸魚川`、`大糸`。命中的是时刻/服务名称。
- 品川/大崎：shared-fork authority NOT FOUND。检索 `品川`、`大崎`。旁注（不是 authority）：`docs/tokyo-southern-branch-audit-2026-10-01.md`、`docs/tokyo-osaki-legacy-repair-2026-10-01.md`。
- 京叶：NOT FOUND。检索 `京葉`。旁注在 `app/public/rail/README.md` 与 `jp-2025.sources.md`，没有 authority 文件。
- 北松江 #6：NOT FOUND。检索 `北松江`、`Kitamatsue`、`150→0`。只在 ADR 第 201、451 行。
- 渡良濑花轮 #8：NOT FOUND。检索 `渡良瀬`、`花輪`、`Watarase`。没有两组 v5/v2 的修复记录。
- 宫津 #9/#15：NOT FOUND。检索 `宮津`、`accepted repair`。`ios/PHYSICAL_ROUTE_GAPS_20261003.md:340` 只是接点日期，不是 export 覆写 authority。
- 夷隅 `substitute_bus`：FOUND。`app/scripts/railway/jp-manual-corrections/corrections.json` id `A3`（第 43–60 行），`lineId` `jp-いすみ鉄道-いすみ線`，`serviceStatus` `substitute_bus`。
- 宫福 rejected：NOT FOUND。检索 `宮福`、`rejected`。`PHYSICAL_ROUTE_GAPS_20261003.md:312` 写明福知山–宮福的否决细节是未提交的 session notes。
- 布崎 rejected：NOT FOUND。检索 `布崎`。只在 `port-fixtures/station-display.json` 的站名行。
- 西野尻 rejected：NOT FOUND。检索 `西野尻`。同样只在该站名夹具。
- CN `source_review_id`：NOT FOUND。检索 `source_review_id`、`地铁误标`。只在 ADR。
- 广州南 / 沈阳北 / 攀枝花南：NOT FOUND。检索 `广州南`、`廣州南`、`GZS`、`沈阳北`、`瀋陽北`、`SBT`、`攀枝花`、`PNE`。只在 ADR。
- 楚雄—丽江：NOT FOUND。检索 `楚雄`、`丽江`、`麗江`。只在 ADR。
- Manyo 23 对：NOT FOUND。检索 `Manyo`、`万葉`、`23 pairs`、`identity-plan`。`corrections.json:116` 的 `jp-万葉線-新湊港線` 是普通修正条目，不是 23 对清单，也没有 named plan。

## g. 例外清单

已写明、本阶段不重算的例外都在 ADR，没有单独报告文件。`unmapped-source`：`source_station.station_id IS NULL` 为 JP 6 行、TW 2 行（ADR 第 95、424 行）。`rail.db` 是 LFS 指针，这 8 行没有在本检出重查。`identity-not-a-railway` 的例子 `jp-jr-east-ueno-tokyo-through` 在 JP 包的 `railwayIdentity` 里。其余已知例子只在 §9.5：都营新宿多站码、`shared-facility-candidate` 的押上/目黒等、`name-line-not-unique` 的 JP 3 / TW 2 / CN 81、`line-label-collision` 的 `本線` ×11 与 `東海道線` ×3。CN 81 无法在本检出重算，因为没有 CN 包。

P0（身份账本，不是本冻结）将按 §9.5 生成、且只列不改的报告：`line-family-candidate`、`same-operator-split-names`、`same-operator-multi-codes`、`cross-complex-same-station`、`unmapped-source`、`ambiguous-company-text`、`identity-not-a-railway`、`history-unmatched`、`shared-facility-candidate`、`name-line-not-unique`、`line-label-collision`、`line-alias-is-country-code`。这些报告文件现在都不存在。

## h. 注册表输入白名单

不变量 11（ADR 第 273 行）：只读 compact 包、站点表、名称表、历史叠加、审定覆写。本检出因此允许：

- 包：`app/public/rail/{hk,jp,kr,mo,tw}-2025.json`
- 站点表：`app/data/stations.json`、`stations-{hk,kr,mo,tw}.json`（`load.mjs:223–224`）
- 名称表：`app/data/station-names.json`、`station-names-{hk,kr,mo,tw}.json`（`load.mjs:231` 把 `station-readings*` 改写成这些路径）；已发布英文名 `station-english.json`（`load.mjs:214`）与 `station-english-jp.json`（第 233–234 行）
- 历史叠加：`app/data/rail-history.json`。`rail-history-*.json` 没有其他文件。`RailHistory.swift:96` 允许 `rail-history[-<cc>].json`，分国家文件不在盘上
- 审定覆写：无。ADR §9.1 第 313 行计划的 `app/data/registry/station-derivation-exceptions.{region}.json` 不存在

明确不在白名单：`rail-sections*.json`；`display-lanes.json` 与其他显示派生；`corrections.json` 与 `app/data/**/candidates/`；`station-readings*`；`station-names-coverage.json`；`station-english-verified-*`、`station-english-kr-second-pass*`、`station-english-coverage.json`；`tokyo-southern-branches-overrides.json`；`jp-directional-alignment-overrides.json`；`app/scripts/railway/jp-rail-history-events.json`（构建原料，不是叠加文件）。

## i. 受保护文件

P0 期间字节必须不变：上面 5 个 compact 包、`app/public/rail/display-lanes.json`、`app/data/rail-history.json`，以及 §f 找到的 authority `app/scripts/railway/jp-manual-corrections/corrections.json`（只列该 authority，不含同目录碎片）。已否决候选文件没有找到，故不列入。`protectedFiles` 共 8 条。包与 `rail-history.json` 同时是注册表输入；`display-lanes.json` 与 `corrections.json` 受保护，但铸造时不得读取。

## 附：冻结基线与主工作树的差异（2026-10-19 核对）

本冻结基于分支 `adr-0013-identity-registry`（HEAD 75344e02）。主工作树另有约 6300 项未提交改动（多会话并行），其中与本重构直接相关的有：

- `docs/reference/railway-data-overhaul-preparation.md`、`docs/reports/**`（已暂存未提交）——上文 f 节“NOT FOUND”的修复 authority 与否决候选大多位于此处；
- `ios/auxiliary/RailDiagnostics`、`ios/auxiliary/RailAlignmentInspector` 等诊断工具（未跟踪）——§3.10 引用的 `DiagnosticSession` 等符号位于此处，故在本基线显示 MISSING；
- RailKit 源码目录重组（`ios/RailKit/Sources/RailCore/Stations/`、`Journeys/Train.swift` 等为未跟踪新路径）；
- CN 包与 `rail-sections-cn.json` 等（未提交）。

后果：P0（纯增量 JS/数据）可在本基线完成；`protectedFiles` 只覆盖本基线存在的文件，上述内容落入提交后必须补充冻结条目。
P1 的 Swift 改动（乘车记录引用、打包身份表解析）依赖正在重组的 RailKit 目录，须待该基线提交后再做，以免与并行会话冲突。
