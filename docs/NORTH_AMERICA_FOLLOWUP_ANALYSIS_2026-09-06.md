# 北美铁路剩余问题分析：2026-09-06

本轮延续上一轮修复，检查当前 US 353 / CA 83 条线路及其报告。仅新增分析文档，没有修改生产代码、线路包或样本。完整站点成员、距离、旧颜色记录和输入 SHA-256 见[机器可读证据](NORTH_AMERICA_FOLLOWUP_ANALYSIS_2026-09-06.json)。

## 1. P1：跨城市车站共用 ID，已造成错误线路归属

逐个 station group ID 枚举所有成员对，按 WGS84 坐标计算球面距离。美国有 **61 个 ID 的最大跨度超过 2 km，其中 54 个超过 100 km**；加拿大没有超过 2 km 的同 ID 组。2 km 是复核筛选值，不是自动合并或拆分规则。

| 共用 ID | 最大跨度 | 冲突实例 |
|---|---:|---|
| `us-official-healy` | 4,531 km | Alaska Aurora Winter / Chicago Metra |
| `us-official-broadway` | 4,338 km | Caltrain / Boston MBTA |
| `us-official-concord` | 4,267 km | BART / MBTA Fitchburg |
| `us-official-fullerton` | 2,786 km | California Amtrak、Metrolink / Chicago CTA |

这不是仅有数据层面的疑点。实际执行 `RailNetwork.buildNetworkFromCompactPackage` 和 `RailMapPopup.buildPopupModel`，只取当前包中的 CTA Red 与 Southwest Chief 两条真实线路，Chicago Fullerton 的弹窗就同时列出两条。当前 `port-fixtures/station-display.json` 的完整网络结果还包含加州 Metrolink；Healy 弹窗包含 Metra，Concord 弹窗包含 MBTA。

具体机制：

- `rail-network.js:3614` 按裸 `stationGroupId` 汇总成员；每条线路的 station ID 本身带 line ID，因而问题是错误分组，不应描述成所有站点查询键都被覆盖。
- `railmap-popup.js:44` 直接列出该组的线路，没有城市或距离校验。
- `StationDisplay.swift:255`、`:359` 使用相同组成员构造 Swift 弹窗。已有一致性样本包含错误关联，所以跨平台测试通过不能证明关联正确。
- `build-north-america-rail-package.py:4181` 在单次构建内按名称分配 `region-official-name[-N]`；不同 scoped build 的名称空间相互不可见。
- `merge-na-feed-build.py:536` 的保护仍不完整：只要任意外国运营商成员足够近，最小距离检查便保留 ID，即使同 ID 还有很远的成员；已有 rename map 的目标也没有在此重新验证。最小复现：只有远端成员时分配 `-2`，同时加入一个近端换乘成员后却返回空重命名表。

修复应先分清同 ID 下的物理地点，再按已确认的线路成员分配稳定 ID，保留真正换乘关系。必须同步 station features、readings、共享走廊引用及样本；不能批量去掉 `-2` 后缀，也不能仅在弹窗隐藏远端线路后宣称数据修好了。

## 2. P1：审计把大陆级 ID 冲突与站台偏移归为同一类警告

`audit-na-package.py:920` 附近统一生成 `WARN station.split`，并在遇到第一项超限后停止检查该 ID。当前 0 ERROR 因而不代表没有真实数据错误。

一个明确的漏报幅度例子是 `us-official-forest-hills`：成员最大间距 **406.5 km**，当前报告只记录第一组 **166 m** 的差异。应分别报告已核实的跨地点冲突与可复核的站台偏移，并检查组内完整距离或物理地点分组，避免行序改变结论。

另有 New York Penn、Newark Penn、Washington Union 三个已在 registry 中记录证据但仍未完全归并的复合车站。这与跨城市 ID 冲突是相反方向的问题，应分别处理。尤其 `us-official-penn` 同时涉及 New York 和 Newark，不能只按名称归并。

## 3. P2：城市台账隐藏了 15 条真正未发布的记录

已实际运行 `make-city-ledger.py`，输出到临时文件复核。它在第 164 行附近把全部 `geometry-release-blockers` 当作“已发布、只有区间扣留”，没有查询发布包成员。

| 项目 | 当前输出 | 按实际发布身份核对 |
|---|---:|---:|
| published | 436 | 436 |
| geometry bucket 被计为已发布的记录 | 36 | 21 |
| 未发布的记录数 | 336 | 351 |

误归类的 15 条包括 Jacksonville Skyway 两条、Kenosha feed/OSM、WVU、Hop、PATH、REM 两条、STM 四条、QLINE 和 Shore Line East。应以 `lineId in publishedIds` 判断，并用记录中的真实 `feed` 归属城市。**351 仍是记录数，不是 351 条独立铁路**；其中存在替代来源、方向及重复线路记录，不能直接作为覆盖缺口。

## 4. P2：10 条已补色记录仍留在旧运营商别名下

当前 56 条 OSM 颜色阻塞记录中，10 条的 relation ID 已有 `osmLineColors`。它们分别仍挂在 `osm-ctrail`、`osm-m-1-rail`、`osm-metropolitan-transit-syste`、`osm-port-authority-of-new-york`、`osm-pulsar`、`osm-transdev` 下。

上轮报告合并按新的运营商 slug 替换，未清掉这些旧别名下的记录；这是报告更新遗漏。应以 OSM relation ID 做稳定身份核对，替换旧的颜色失败原因，并连接到新的几何候选及扣留决定。去掉旧记录不会恢复显示：这些候选仍存在几何或站点清单阻塞。不能把 56 减 10 后的 46 项颜色记录解释成 46 条只需补色的独立线路。

## 5. 已核实不应重复修复的旧问题

- **白色线路**：当前审计已有 `colour.invisible`。在内存中将一条真实线路的 `colorReference` 改为 `#FFFFFF`，实际得到该 ERROR；旧文档的“白色可以通过审计”已过时。
- **NARN 回退不留记录**：当前覆盖不足与部分区间回退分支均写入 `usedInstead` 等字段；`test_na_builder_dropped_records.py` 的 8 项测试通过。历史包的记录完整性仍不能由此追认。
- **临时来源路径**：主 builder 的 `--source-dir` 当前为必填项；此次检查未在铁路 shell/JSON 配置中发现硬编码临时路径。历史 provenance 文档仍引用临时产物，不能把它们当作可恢复输入，也不能沿用旧“11 个脚本默认写临时目录”的数字。

## 6. 仍需轨道证据或现场图形复核的部分

当前报告把 Denver RTD 10 条、Sacramento 3 条、Valley Metro/Phoenix 4 条等挡在公开路线 GIS 缺少独立测绘来源证明的门槛；Calgary 2 条还有具体的换轨、回折和绕行问题。这里只复核了代码与已保存证据，没有重新搜索这些城市的新测绘数据，因此不声称今天不存在可用的新来源。

TTC 512 的 350 m / 112 m 绕行、6 条线路的尖折提示、80 项曲率提示仍需结合具体轨道核对。地下回车环线、真实换轨与错误投影不能仅靠比值区分。此前三项结构预检警告也保持未决。没有执行新的 Web/iOS 地图目视验收，不能将这些提示统一定为缺陷或统一消除。

建议下一轮顺序：**站点 ID 与审计门槛 → 台账身份与旧记录清理 → 已有证据的复合车站归并 → 按城市补充轨道来源**。前三项有明确的本地复现和修复落点；新增线路的测绘缺口应独立推进。
