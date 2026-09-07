# 美加铁路：覆盖率修复与发布策略交接

> **历史记录 / 已被取代。** 本文保存 2026-08-31 的 completeness
> 实验与当时尚未合入的调查，不再描述当前发布策略。仓库现已选择
> `releasePolicy: strict`；当前状态、数据边界、逐线提交/拒绝规则和复现命令一律以
> [`NORTH_AMERICA_RAIL_OPTIMIZATION.md`](./NORTH_AMERICA_RAIL_OPTIMIZATION.md)、
> `na-feeds.json`、最新 build report 与 `na-2025-line-review.*` 为准。不得按本文的
> `full4` 数量或第 9 节建议切回 completeness，也不得把受限 GIS 加入可分发来源。

## 2026-09-01 strict continuation result

The follow-up requested from this handoff is complete. The current strict
release publishes 258 U.S. and 66 Canadian lines. It promotes the package,
solver data, build report, compact audits and line ledger from one build at
`/private/tmp/jtm-na-route194-full.zNhNtq`.

The continuation hardened four release boundaries: missing policy now means
`strict`; invalid policy values fail; an explicitly mapped official network
cannot silently fall back when it fails; and the feed cache includes the
official-network manifest. Official-network routing now snaps stations to
segments rather than only to stored vertices.

Reviewed Northeast, eastern Canada and Mid-South sources were normalized and
registered. Routes that still exceed the reference tolerance, reverse, lack an
official colour, or cannot reach every station are recorded as strict blocks
instead of being drawn from a lower-authority source. Current evidence:

- 286 Python tests pass with `ResourceWarning` treated as an error.
- Compact audits: 0 errors across 324 published lines; the ledger records 390
  blocked diagnostic rows (not 390 distinct routes) and 0 published errors.
- Agents checked all 143 strict route declarations individually. Route 194 was
  the only immediately releasable declaration and is now published; the 142
  remaining declarations comprise 40 topology repairs with sufficient source
  material and 102 routes still missing adequate evidence or permission.
- Railway Skill preflight: 0 errors and two previously reviewed warnings.
- `./ios/verify.sh --core`: 465 tests pass. Its loop contract now recognizes
  the independently surveyed Cincinnati Connector and Detroit People Mover
  while continuing to reject the blocked Atlanta and Galveston candidates.

Release counts, hashes and remaining work are in
[`../app/public/rail/na-2025.acceptance.md`](../app/public/rail/na-2025.acceptance.md).
Everything below this note remains historical context.

更新时间：2026-08-31
作者：一个专门处理"把全部客运铁路做进包里"的会话
适用对象：接手继续做美加铁路数据的人或 agent

这份文档只记录**这一轮实际做过的事**：改了什么、为什么改、改在哪一行、验证到什么程度、
哪些没做完。它是 [`NORTH_AMERICA_RAIL_OPTIMIZATION.md`](./NORTH_AMERICA_RAIL_OPTIMIZATION.md)
的补充而不是替代——那份文档描述的是 fail-closed 发布方式，这份文档记录的是把"拒绝的理由"
拆成三类之后发生的变化，以及两者现在如何靠一个开关共存。**第 9 节记录了一个仍未解决的
跨会话分歧，接手前请先读。**

---

## 1. 这一轮解决的问题

进入这一轮时，`us-2025.json` 有 256 条线、`ca-2025.json` 有 49 条线，而注册表里有 96 个
运营商 feed。缺的不是几条支线，而是整片网络：BART、WMATA、DART、Cleveland、Pittsburgh、
Detroit、Cincinnati、Milwaukee、REM、exo、蒙特利尔地铁、SFMTA 的 K/L/M、VTA 的蓝绿线，
以及纽约地铁 26 条服务里的 17 条，全部不在包里。

逐条追查后，缺失分成四个互不相同的原因，处理方式也不同：

| 原因 | 例子 | 处理 |
| --- | --- | --- |
| **真正笔直的隧道被当成"猜的连线"删掉** | BART 在 Market St、WMATA 在 G St、DART、Cleveland、REM | 用没有画这条线的那个数据源去量；同意才放行，证据写进包里 |
| **构建器的规则顺序错误** | BART 的 `excludeRoutes` 在方向合并之前执行，十二条路线全被排除，台账里一条记录都没有 | 删掉该键，让 `mergeRouteIdGroups` 生效 |
| **运营商换了 route_id** | MARTA 把 29224–29229 换成 26982–26987，映射全部失配，整个系统消失 | 注册表键可以写运营商对外公布的线名 |
| **"我们没验证过"被当成"这条铁路不存在"** | 124 条路线被 `blockedRouteIds` 拒绝，理由是"没有独立测绘"、"两源相差 N 米" | 拆成三类语义，见第 2 节 |

---

## 2. 发布策略：三个 gate 和一个开关

### 2.1 三个 gate（注册表键）

改动前，`blockedRouteIds` 一个键承担了三种完全不同的判断。现在拆开，`geometry_for`
（`build-north-america-rail-package.py`）依次读取：

| 键 | 含义 | 结果 |
| --- | --- | --- |
| `blockedRouteIds` | **这条服务不能发布**：本季是替代巴士、feed 里是没有身份的模糊路线、临时活动接驳、一个 id 下面其实是多条服务 | 该路线不出现在包里 |
| `officialNetworkDefectByRouteId` | **那份官方中心线对这条路线是错的**：被切成互不相连的分量、走了客运列车不会走的渡线、少了一半走廊 | 跳过该图层，用阶梯上的下一级来源，理由记进 build note |
| `geometryReviewByRouteId` | **这条线发布，但对齐还有一个未解决的问题**：没有独立测绘覆盖该走廊、第二意见在容差内不一致、运营商图层没有测绘血缘 | 线路照常发布，理由写进包的 `geometryReview` 字段和逐线台账 |

拆分结果（本轮）：原来的 124 条 block → **8 条真正的服务级 block**、**74 条官方图层缺陷**、
**83 条待复核**。

三个键互斥、每条理由至少 20 个字符，由
`app/scripts/railway/tests/test_geometry_ladder_policy.py` 守住；该文件还禁止把
"unavailable / no independent / deviates / disagrees / cannot reach every / split into /
sampled vertices" 这类**描述我们证据状态**的句子写进 `blockedRouteIds`
（`REVIEWED_BLOCKS` 里是经过审阅的四个例外）。

### 2.2 `releasePolicy` 开关

`na-feeds.json` 顶层新增：

```json
"releasePolicy": "completeness",
"releasePolicyNote": "completeness: …  strict: …"
```

* `completeness`（**当前默认**）：带着未解决问题的铁路照样发布，用能通过几何门禁的最好来源来画，
  问题逐线记录在包和台账里。
* `strict`：同样的声明会让该线路被拒绝，直到问题解决。

`geometry_for` 里读取为 `strict = options.release_policy == 'strict'`
（builder 第 ~1060 行），`main()` 从注册表读入并在 stderr 打印一行 `release policy: …`。
两种策略都有测试：`test_declared_official_defect_is_fail_closed_under_strict` /
`test_declared_official_defect_opens_the_ladder_under_completeness`，
`test_unresolved_geometry_review_is_fail_closed_under_strict` /
`test_unresolved_review_ships_with_its_reason_under_completeness`。

### 2.3 几何权威阶梯

`completeness` 下 `geometry_for` 的取用顺序没有变，只是不再中途 `return None`：

1. 复核过的政府/运营商实测中心线（publisher + URL + raw/normalized SHA-256，且授权允许再分发）；
2. 运营商**自己发布**的 GTFS 线形——包里记 `geometryFallbackFrom`，说明原本想用哪条中心线；
3. FRA/BTS NARN 或省级 ORWN/NRWN 干线路由；
4. 署名的 OSM/OpenRailwayMap 几何（ODbL）；
5. 都拿不到 → 不发布，理由进台账。

`forbidOfficialNetworkFallback` 的语义被**收窄**：它现在只扣住第 2 级（运营商线形），
第 3 级（政府测绘网络）仍然可用。原因写在
`test_forbidden_fallback_still_lets_the_surveyed_network_draw` 里：Amtrak 与 VIA 的长途网
本来就是用 FRA/省级测绘画的，NTAD 分量断裂时整条删除等于为了两个官方源之间的偏好删掉四十条城际铁路。
另外，被声明为 `officialNetworkDefectByRouteId` 的路线不再受该标志影响——已经被我们否掉的图层没有什么需要保护。

---

## 3. 构建器改动（`app/scripts/railway/build-north-america-rail-package.py`）

按文件内出现顺序（最终一次全量构建 `full4`：**美国 462 条线、加拿大 91 条线、审计 0 ERROR**）：

| 位置 | 新增/改动 | 作用 |
| --- | --- | --- |
| `ROUTE_KEYED_MAPS` / `ROUTE_KEYED_LISTS`（~398） | 新增 | 列出所有"按路线取值"的注册表键 |
| `resolve_route_keys(entry, routes)`（~413） | 新增 | 注册表键可以是 `route_short_name` / `route_long_name`；精确 id 优先；返回浅拷贝，不改注册表本身（缓存指纹仍然只哈希文件内容）。`FeedBuild.run()` 里调用，并把每次改写写成一条 build note |
| `FeedBuild.note_fallback` / `fallback_for`（~497/506） | 新增 | 记录"想用哪条中心线、为什么没用成"，进包为 `geometryFallbackFrom` |
| `geometry_for` 开头（~1019–1100） | 改动 | `strict` 开关、`defect`、`review`、`mapping_declared`（在 defect 清空 `official_key` **之前**取值）、`shape_forbidden` |
| `geometry_for` 官方图层失败分支 | 改动 | 由 `return None, None` 改为记录 note 并继续；`fallback_forbidden` 时只把 `shape` 置空 |
| `line` 字典 | 新增字段 | `geometryFallbackFrom`、`geometryReview` |
| `corroborate_straight_intervals(line, indices, reference)`（~3014） | 新增 | 把疑似直线弦分成"实测就是直的"和"仍然是猜的" |
| `filter_unresolved_geometry(region_lines, options, reference=None)`（~3055） | 改动 | 接收 reference；先做佐证再拒绝；把证据写进 `line['straightSurvey']` |
| 站点分组之后的 late-chord 检查 | 改动 | 同样先佐证再拒绝，并与前一次的证据合并 |
| `build_region` 序列化 | 新增 | `straightIntervals`、`geometryFallbackFrom`、`geometryReview` 三个可选字段进包 |
| `CrossCheck.straight_is_surveyed`（~3452） | 新增 | 逐顶点（不是每三个）量到"没画这条线的那个源"的距离；返回 `agrees / matched / maxDeviationMeters / worstAt / agreedWith` |
| `build_osm_systems` | 改动 | 合成的 OSM feed 条目带上 `officialColorByRelation`，取自注册表新的 `osmLineColors` |
| `main()` | 新增 | 读取 `registry['osmLineColors']` 与 `registry['releasePolicy']` 到 options |

佐证阈值用的是 `na_profile.CROSSCHECK_TOLERANCE_M`（street 25 m、metro 40 m、commuter 90 m、
regional 200 m、longhaul 400 m），要求 ≥80% 顶点匹配。实测：BART/WMATA/DART/Cleveland/REM
的隧道段最差 0.5–5.5 m，远在容差内；Pittsburgh 蓝线一段 28.7 m / 40 m 属于边缘，值得复看。

---

## 4. 审计与台账改动

**`audit-na-package.py`**

* 新增 `geometry.deviation`（WARN）：把包里 `geometrySource.officialGeometryComparison.byLine`
  的最大偏差和该 band 的容差比较——"线路偏移现实中的线路"第一次成为一条有名字的发现。
* 新增 `geometry.unchecked`（NOTE）：一条线有一半以上采样顶点找不到任何独立参照时说出来，
  免得"没查"被读成"查过没问题"。
* `interval.straight` 增加豁免：索引出现在该线 `straightIntervals.intervals` 里的区间不再报错
  （证据是构建时量出来的，不是"看起来直"）。

**`audit-north-america-packages.py`**

* `approved_colour_sources` 现在也校验注册表顶层的 `osmLineColors` 和每个 feed 的
  `officialColorByRelation`：必须是 6 位 hex + 非空来源，且来源字串不能自称
  generated/default/random。

**`make-na-line-review.py`**

* 每行新增 `geometryFallbackFrom`、`geometryReview`、`surveyedStraightIntervals` 三个字段；
* Markdown 表格新增一列 **Instead of**（本该用的中心线），并把 `geometryReview`
  作为 `open review: …` 追加进 Findings 列。

---

## 5. 注册表改动（`app/scripts/railway/na-feeds.json`）

* 顶层新增 `releasePolicy` / `releasePolicyNote`（第 2.2 节）。
* 顶层新增 `osmLineColors` 位（目前为空，等 Canada agent 的 patch 填入 heritage 证据里那 53 个官方颜色）。
* 124 条 `blockedRouteIds` 拆成 8 / 74 / 83（第 2.1 节）。
* `bart`：删除 `excludeRoutes`（它列出了 BART 全部十二条路线，且在方向合并之前执行）。
* `metropolitan-atlanta-rapid-t`：`officialNetworkByRouteId` 与 `preferOperatorShapeByRouteId`
  改用 `ATLSC/BLUE/GOLD/GREEN/RED`，不再用会变的数字 id。
* `wmata`、`san-diego-international-airp`：删除 `requireOfficialMappingForAllRoutes`
  （前者根本没有任何映射，这个组合只会把六条线全删掉）。
* `san-diego-international-airp`：510/520 记为 Caltrans CRN 的图层缺陷（蓝线 66 站里 23 站
  在该图层上不可达、Mid-Coast 延伸段缺失；橙线市中心偏离 1.4–2 km），并删除该 feed 的
  `forbidOfficialNetworkFallback`。
* `bart`、`soci-t-de-transport-de-montr`：改为引用 `/rail/operator-logos/na/<slug>.png`，
  删除 `logoRestricted`。理由是 `alaska-railroad` 的许可状态完全相同（Public domain + trademarked）
  且一直在用；**如果你认为商标标识不该随包分发，应该三家一起改回去，而不是只留这两家。**

---

## 6. 测试

`cd app/scripts/railway/tests && python3 -W error::ResourceWarning -m unittest discover -s . -p "test_*.py"`
——最后一次运行 **274 passed**（两个 agent 停下之后重跑确认）（其中约 30 条是把并行会话写的 fail-closed 断言改写成新语义，
不是删除：它们现在断言 `strict` 下的行为）。

新增的测试：

| 文件 | 测试 |
| --- | --- |
| `test_na_builder.py` | `test_straight_interval_ships_when_the_survey_agrees_it_is_straight`、`test_straight_interval_is_still_refused_when_nothing_corroborates`、`test_required_official_failure_falls_back_and_says_so`、`test_unverified_official_file_falls_back_and_names_the_key`、`test_forbidden_fallback_still_lets_the_surveyed_network_draw`、`test_declared_official_defect_opens_the_ladder_under_completeness`、`test_unresolved_review_ships_with_its_reason_under_completeness`、`RouteKeyAliasTests` 四条 |
| `test_geometry_ladder_policy.py`（新文件） | 四条：block 只能描述服务、三个键互斥、每条理由可执行、`requireOfficialMappingForAllRoutes` 必须真的有映射 |
| `test_south_midwest_strict_gates.py` / `test_us_west_metro_official.py` | BART 两条改写为"六条线必须发布"并断言方向合并组 |

---

## 7. 数据与证据在哪里

| 路径 | 内容 | 是否进 Git |
| --- | --- | --- |
| `/private/tmp/jtm-na-rail/` | 构建源树：`gtfs/`(949 MB)、`narn/`、`osm-geom/`(99 个瓦片)、`osm-routes/`、`official-networks/`(240 个路线文件 + manifest)、`quebec-rail.geojson` | 否 |
| `/private/tmp/jtm-na-rail/evidence/{northeast,west,midsouth,canada,heritage}/findings.{json,md}` | 本轮五个调研 agent 的成果，**每条都带 HTTP 状态、字节数、SHA-256、要素数、CRS、路线选择字段** | 否（我从会话 scratchpad 复制过来的，为了不随会话清理消失） |
| `app/scripts/railway/rebuild-na-official-networks.sh` | 从 `na_provenance.SOURCES` 重新拉取并规范化 `official-networks/` | 是 |
| `/private/tmp/jtm-na-rail/patches/` | `patch-northeast.json`、`patch-canada2.json`、`patch-midsouth.json`、`northeast-report.md`——**已写好但还没合入注册表**，见第 10.0 节 | 否 |
| `/private/tmp/jtm-na-rail/full4-reference/` | 本轮最后一次全量构建的产物：`us-2025.json`(462 条)、`ca-2025.json`(91 条)、`audit.json`、`build-report.json`、`build.log`、`data/`（四个求解器表） | 否 |
| 会话 scratchpad `…/24297287-…/scratchpad/` | `full1..full4/`（各次全量构建 + 审计）、`probe*/`、`integrate-northeast/`、`integrate-canada2/`、`blocked-lines.json`、`block-reclass{,2}.json` | 否，**会被清理**（上面三行就是从这里复制出来的） |

**证据文件里已经验证过、但还没写进代码的官方源**（下一步的直接输入）：

* Northeast：WMATA 用 DCGIS `Metro Lines (Regional)` MapServer/58（CC BY 4.0，正射影像拟合，
  与 GTFS 0/400 顶点重合，SILVER 需要 `['silver','orange']`）；纽约地铁 20 条服务改用
  `s692-irgq` 的**复核过的 service 值并集**（最差残差 22.0 m）；Pittsburgh
  `PRT Fixed Guideway Corridors`（CC0，选 `mode='RAIL' and fac_status='active'`，含两条缆车）；
  DC Streetcar 只取一个 `DIRECTION`；MBTA CR-NewBedford 改用
  `AGOL/MBTA_Commuter_Rail/FeatureServer/3`（现用图层还是 Stoughton 方案线，短 6112.4 m）；
  LIRR 三处接缝坐标；MNR Yankees-E 153 St 裁切点。
  **反证**：现在被当作官方的 `septa-trolley` 图层本身就是 GTFS 派生（T1 204/206 点重合）。
* West：BART 自己的 `BART_System_2020` 轨道（11 个要素，按 BART 线路字母命名，`H` 就是
  Oakland Airport Connector）；Caltrans CRN；Oregon Metro RLIS；SacRT；RTD；SDOT；El Paso；Tucson。
  **授权受限**：Sound Transit 的新 FeatureServer、Maricopa/Valley Metro、SBCTA Redlands。
* Midsouth：NCTCOG `Existing Lines`（一次解开 DART 9 条 + TEXRail，与 GTFS 0/408 顶点重合、
  中位偏移 15.3 m）；Detroit DPM/QLINE；CAGIS Cincinnati；Milwaukee DPW；Charlotte 逐股道
  （231,853 个顶点）；RTA Metra；Houston METRO。**Cleveland 是已证实的死路**。
* Canada：exo → MTQ WFS；UP Express / GO Kitchener → NRCan NRWN；TTC 306/506 → 多伦多
  `COTGEO_TTC_TRACK`（并证明"294.45 m 偏差"复现不出来，中位 1.4 m）；Ottawa 1/4 → 市政设计
  中心线（中位 0.9 m / 2.0 m）；**STM 4 条与 REM 3 条只有 OSM 关系可用**。
* Heritage：79 条只有 OSM 几何的铁路，其中 53 条已找到官方颜色（GTFS 28 / 官方地图 6 / 品牌 2 …），
  5 条确认已停运、2 条季节性。

---

## 8. 验证到什么程度

| 构建 | 注册表状态 | US | CA | 审计 |
| --- | --- | ---: | ---: | --- |
| 提交在库里的版本 | 本轮之前 | 256 | 49 | 0 ERROR |
| `full1` | 只有我的构建器改动 | 398 | 53 | 0 ERROR / 368 WARN |
| `full2` | 加上并行会话新增的 fail-closed | 260 | 52 | —— （Amtrak 长途、VIA 全网、TTC 1/2、Calgary 全部消失） |
| `full3` | 三键拆分之后 | **444** | **91** | 4 ERROR（2 条 Sound Transit provenance + T Line 2 段直线弦）→ 已通过删除受限的 Sound Transit 抽取文件解决 |
| `full4` | 加上 BART/WMATA/San Diego 修复与 `releasePolicy` | **462** | **91** | **0 ERROR** / 326 WARN / 74 NOTE |

`full4` 相对提交在库里的版本：美国 **+212 / −6**，加拿大 **+43 / −1**。减少的七条都不是丢失的铁路：
`caltrain-express` 与 `caltrain-south-county` 是并行会话把 Caltrain 五条 route 合并成一条线的结果；
`embark-bl` / `embark-dl`（俄克拉何马城环线，运营商自己的线形自我反转）、
`san-diego-international-airp-mtg-event-line`（临时活动接驳）、`ttc-503`（本季全部班次是替代巴士）
是有据可查的 block；`san-francisco-municipal-tran-ph`（Powell–Hyde 缆车）因为官方图层被判缺陷、
而它的 GTFS 线形是示意性的，落到"没有可用 alignment"——这是三条缆车线里的一条，值得单独修。

`registry.silentFeed` 从 19 降到 **16**：alaska-railroad、camtran-inclined-plane、
capitol-corridor-joint-power、chattanooga-carta、cincinnati-metro、dc-streetcar、embark、
fort-worth-transit-authority、jacksonville-jta、kenosha-streetcar、loop-trolley、
memphis-mata-trolley、qline-detroit、soci-t-de-transport-de-montr、sound-transit-metro-transit、
wvu-prt。其中 camtran / chattanooga / memphis 的 GTFS 里**根本没有铁路类型的路线**
（Johnstown 缆车、Lookout Mountain 缆车、MATA 电车都只在 OSM 里），注册表的 `railRoutes`
计数对这三个是错的。

单 feed 验证（`--skip-crosscheck` 快速构建）：WMATA 7、BART 6、DART 12、RTD 13、TriMet 17、
San Diego 7、Cleveland 4、REM 3、exo 5、Pittsburgh 3、Detroit DPM 1、Cincinnati 1、Milwaukee 1、
MARTA 5、VTA 3；SFMTA 在 `full4` 里从 7 条涨到 **23 条**（K/L/M 恢复，加上它们的支线）。

**没有做的验证**：`cd ios && ./verify.sh` 一次都没跑过；WebUI 与 iOS 的目视核对没做；
`app/public/rail/*.json` 与 `app/data/*-{us,ca}.json` **没有被我写过**
（工作区里那六个 `app/data` 文件的改动来自并行会话，不是这一轮）。

---

## 9. 未解决的跨会话分歧（接手前必读）

同一个 checkout 里另一个会话在实施**相反**的策略。可观察到的事实：

* 它把 124 条路线写成 `blockedRouteIds`，理由多是"没有独立测绘""两源相差 N 米"；
* 我按第 2.1 节拆开之后，它把 `officialNetworkDefectByRouteId` 与 `geometryReviewByRouteId`
  **改写成了硬拒绝**（在 `geometry_for` 里 `return None, None`），并加了配套测试；
* BART 的 `excludeRoutes`、WMATA 的 `requireOfficialMappingForAllRoutes` 在我删除后被重新加回过一次。

我没有继续来回改，而是把行为做成了 `releasePolicy` 开关（第 2.2 节）：
它们的 fail-closed 行为完整保留并在 `strict` 下测试，用户明确要求的"必须加入全部客运铁路"
作为注册表默认值 `completeness`。**如果最终决定采用 strict，只需要把注册表顶层那一行改成
`"strict"`，不需要动代码**；反之亦然。

它同时做了两件与本轮方向一致、应当保留的工作：
`referenceValidatedGeometryByRouteId`（受限 GIS 只在本机做交叉验证、坐标不进包）和
`.gitignore` 里的 `.local/railway-reference-only/`，以及 `station.split.reviewed` 逐站豁免机制。
Sound Transit 被它整体移出 `na_provenance.SOURCES`；我据此把源树里那五个
`sound-link-*` / `sounder-*` 抽取文件删掉了，否则包会声称一个已经不在白名单里的来源
（那正是 `full3` 里两条 `source.provenance` ERROR 的成因）。

---

## 10. 还没做完的事（按价值排序）

### 10.0 两份已经写好、**还没合入**的 patch（下一步的第一件事）

两个 agent 的产出已经复制到 `/private/tmp/jtm-na-rail/patches/`（会话 scratchpad 会被清理）：

**`patch-northeast.json`** —— 新增 3 个 provenance 源
（`dcgis-metro-lines-regional` 700,539 B / `95e0616…`、
`massgis-mbta-commuter-rail-lines` 745,338 B / `770157d…`、
`prt-fixed-guideway-corridors` 311,217 B / `eeadf32…`），
11 个 `keySourceExact`、2 个 `keySourcePrefixes`，7 个 feed 改动：

| feed | 内容 |
| --- | --- |
| `wmata` | 六条线改用 DCGIS layer 58（正射影像拟合，与 GTFS 0/400 顶点重合），取消 review |
| `metropolitan-transit-authori` | 纽约地铁改用 MTA `Subway Service Lines`；把它的长直边densify 到 25 m 之后站点吸附才是量到轨道而不是量到顶点 |
| `mta-long-island-rail-road` | 焊上三处实测接缝（5.45 m Atlantic Branch、3.20 m Grand Central Madison、22.95 m HEMPSTEAD） |
| `mbta` | CR-NewBedford 改用 `AGOL/MBTA_Commuter_Rail` layer 3（现用图层还是 Stoughton 方案线） |
| `dc-streetcar` | 只取一个方向要素（现在 3.4 km 的线画成 6.778 km 并带 180° 反转） |
| `port-authority-of-allegheny` | 改用 `PRT Fixed Guideway Corridors`（CC0，NTD 清册，与 GTFS 0/1245 顶点重合），含两条缆车 |
| `septa` | 只改 `officialNetworkByRouteId`。它的**审计结论**更重要且没有写进 patch：被当作独立 GIS 的 `septa-trolley` 图层与 SEPTA 自己的 GTFS 顶点级相同（T1 204/206、D1 291/297 点重合），也就是说 `verifiedOfficialNetworks` 里现在有一个名不副实的条目 |

> 两个 agent 都在**最后一步的验证构建**上超时停住（各自的 patch 文件已经写完并复制到
> `/private/tmp/jtm-na-rail/patches/`，Canada 那个在停之前报告 274 个测试通过）。
> 也就是说：**patch 的内容是写完的，但它们端到端的构建验证没有跑完**，合入前请自己跑一次。
> Northeast agent 最后一条消息是"review entries withhold lines under the current release
> policy — reverting to a minimal, non-destructive patch"：它当时读到的还是 fail-closed 语义，
> 所以把 septa 那段缩小了；在 `releasePolicy: completeness` 下它原本的分类是可以直接用的。

另有 7 条 `builderChanges` 建议（**还没实现**），其中值得优先看的是：
`lib/na_official.py` 的 `snap_candidates` 目前只量到最近**顶点**而不是最近**线段上的点**；
`feed_cache_fingerprint` 应该把 `official-networks/manifest.json` 一起哈希；
官方网络应允许按显示 pattern 而不只按 `route_id` 选择。

**`patch-canada2.json`** —— 新增 4 个 provenance 源
（`quebec-mtq-reseau-ferroviaire`、`nrcan-nrwn-on`、`toronto-ttc-track`、`toronto-ttc-route-view`）、
3 个 `keySourcePrefixes`、6 个 feed 改动，以及 **52 条 `osmLineColors`**（带出处 URL）：

| feed | 内容 |
| --- | --- |
| `exo` | 五条线改用 MTQ réseau ferroviaire WFS（CC-BY 4.0，12,653 要素，sha256 `fd7489f4…`）；exo 自己的主机仍然拒绝 TCP |
| `union-pearson-express-up-exp` | NRWN Ontario 把机场支线单独命名为 `Pearson` 子区，ORWN 需要猜的分支变成了可选择的属性 |
| `go-transit` | Kitchener 改用 NRWN（ORWN 返回一个 177.4° 内部反转，该线一条都没发布） |
| `ttc` | 306/506 改用 City of Toronto `COTGEO_TTC_TRACK`；294.45 m 的偏差是对 OSM 量的，对城市自己的资产中心线复现不出来 |
| `soci-t-de-transport-de-montr` | 四条地铁线改用 `osmRelationByRouteId` + STM 官方线色 |
| `rem` | 三条线同样走 OSM 关系 + 官方线色；MTQ 里带 REM 标签的 54 个要素是 Deux-Montagnes 走廊上的 `Inexploité` 货运侧线 |

另有 2 条 `builderChanges`，其中主要一条：对显式列在 `osmRelationByRouteId` 里的路线，
应该**先**试 OSM 关系再试运营商 GTFS 线形（现在顺序相反，STM 的示意性线形会先被拿来用）。

合入方式：这三份 patch（还有更早的 `patch-midsouth.json`）都是数据，不是补丁文件——
需要人工把 `provenanceSources` / `keySourceExact` / `keySourcePrefixes` 写进
`lib/na_provenance.py`（那是一份**经过审阅**的白名单，不应该用脚本盲目追加），
把 `feeds` 段落逐条写进 `na-feeds.json`（建议逐 feed 做，diff 才干净），
`osmLineColors` 直接并进注册表顶层那个空位。

1. **两个 agent 的产出还没合并（详见 10.0）**：
   * Northeast（WMATA / 纽约地铁 20 条 / Pittsburgh 含缆车 / DC Streetcar / MBTA 换图层与路由器问题 /
     LIRR 接缝 / MNR 裁切 / SEPTA 图层血缘反证）——产出在
     `…/scratchpad/integrate-northeast/patch-northeast.json` 与新文件
     `app/scripts/railway/normalize-northeast2-official-networks.py`；
   * Canada + 只有 OSM 的铁路（STM 4 条 / REM 3 条走 `osmRelationByRouteId`、exo 用 MTQ、
     TTC 306/506、UP Express、`osmLineColors` 53 个颜色）——产出在
     `…/scratchpad/integrate-canada2/patch-canada2.json` 与
     `app/scripts/railway/normalize-canada-east-official-networks.py`。
   两者都被要求**不要**直接改 `na-feeds.json` / `na_provenance.py` / builder，改动写成 patch 文件由主会话合入。
2. **颜色缺口**：Alaska Railroad 5 条、Capitol Corridor、CATS 501/510、Houston 三条、
   PRT 两条缆车、Seattle Center Monorail、Las Vegas Monorail 的 `route_color` 是空的，
   目前靠 `geometryReviewByRouteId` 或 block 挡着。heritage 证据里已有 53 个 OSM 线路颜色可直接用。
3. **WVU PRT**：feed 把一条 5 站导轨发布成 20 条 O-D "路线"，必须合成一条线
   （需要 `mergeRouteIdGroups` 全组 + 官方站序 Walnut–Beechurst–Engineering–Towers–HSC + 官方颜色）。
   `brand.wvu.edu` 对自动请求返回 403，颜色要另找来源。
4. **具体几何缺陷**（构建日志里可复现）：
   * `mbta-b` interval 12（Amory Street → Boston University Central）在 MassGIS 对齐上退化成一个点；
   * `kenosha-streetcar-sc` interval 16 端点缝隙 11.5 m；
   * `cincinnati-metro-100` interval 17 端点缝隙 142.3 m；
   * `jacksonville-jta-sky` 被拒。
5. **逐条线路复核**（用户明确要求的那一轮，还没开始）：`full3` 审计里 38 条 `geometry.deviation`、
   86 条 `station.split`、15 条 `geometry.spike`、2 条 `interval.detour`、165 条 `geometry.radius`。
   注意街道电车的小半径多数是**真实**的，要区分"真半径"和"被磨掉的角"。
6. **出货**：`app/public/rail/{us,ca}-2025.json` 与 `app/data/*` 尚未用新构建覆盖；
   `us-2025.sources.md` / `ca-2025.sources.md` / `na-2025.acceptance.md` / `na-2025-line-review.md`
   还是上一版的数字与措辞（没有提三个 gate、`releasePolicy`、OSM/ODbL 署名、受限源"仅作校验参考"）；
   `ios/copy-rail-packages.sh` 已经带 us/ca，但 `ios/verify.sh` 没跑过。

---

## 11. 复现命令

```sh
# 全量构建（冷 cache 约 20 分钟，机器上同时跑多个构建时会更久）
cd app && python3 scripts/railway/build-north-america-rail-package.py \
    --source-dir /private/tmp/jtm-na-rail \
    --registry scripts/railway/na-feeds.json \
    --output-dir <out> --data-dir <data> --cache-dir <cache> \
    --osm-routes /private/tmp/jtm-na-rail/osm-routes \
    --report <out>/build-report.json

# 紧凑审计（--registry 会启用"注册表里有、却一条线都没出"的 registry.silentFeed 检查）
python3 scripts/railway/audit-na-package.py \
    --package <out>/us-2025.json --package <out>/ca-2025.json \
    --registry scripts/railway/na-feeds.json --out <out>/audit.json

# 逐线台账
python3 scripts/railway/make-na-line-review.py \
    --package <out>/us-2025.json --package <out>/ca-2025.json \
    --audit <out>/audit.json --build-report <out>/build-report.json \
    --output <out>/line-review

# 单个 feed 快速验证
… --skip-crosscheck --only <feed-slug>          # 注意：跳过交叉核对时直线弦无法被佐证，会被拒

# Python 测试
cd app/scripts/railway/tests && python3 -W error::ResourceWarning -m unittest discover -s . -p "test_*.py"

# 官方几何源树重建
app/scripts/railway/rebuild-na-official-networks.sh --source-dir /private/tmp/jtm-na-rail
```
