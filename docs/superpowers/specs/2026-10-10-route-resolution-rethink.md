# 大量行程线路解析：数据优先设计草案

日期：2026-10-10。状态：数据库子段匹配、跨图区段缓存和共享进行中任务已实现；历史执行证据见后续记录。本轮继续审查冷批次成本，落实运营日车站候选索引和同次求解输入复用；这两项改动的真实批量提速尚未测量。

## 目标

尽量使用行程已经确定的信息和数据库的有效证据，判断需要点亮哪条线路的哪些区段。批量加载的计算量应主要由不同的、尚未解析的物理区段决定；相同行程区段重复出现时复用结果。全国数据用于索引和证据查询，不能在每次行程加载时全库搜索或全图寻路。

## 已核实的现状

- `ios/RailMap/RiddenRouteStore.swift:222` 已按输入变化保留未变行程，缓存结果先发布；不能声称当前每次都从头重算全部行程。
- `RiddenRouteStore.swift:765` 缓存未命中的记录先进行区段推断，再找预计算数据，最后走旧求解。第一遍和旧求解都可能处理相同记录，应复用中间结果。
- `RiddenRouteStore.swift:1563` 已有 sectionCodes 或推断选择结果时直接获取来源几何；但随后构建 corridorGraph 并逐顶点 verifiedSourcePath。直接取几何已经存在，重复证明仍值得单独复用。
- `RouteGraph.swift:2856` corridorGraph 已按所选源 feature 集缓存，最多保留 32 个；命中前仍需生成点/空间索引候选与排序。不能把它误述为没有图缓存。
- `RouteSolver.swift:3428` 旧求解先尝试两个区域范围，再全国图；非首个约束尝试的结果仍须扩大范围。不能直接删掉扩大流程，否则会改变结果选择语义。
- `RouteSolveLimiter.swift:7` 全局生产求解并发为 1，且 RiddenRouteStore 的生产 worker 为 1，目的是控制图内存。增加 worker 不是本设计的主要方向。
- `RouteGraph.swift:766` 现有缓存摘要含整组 routeSections、日期、历史版本和有效策略；没有无条件拼入 train.id。`RiddenRouteStore.swift:2099` 实际按摘要读取，因此完整输入一致的不同记录已经能共享整条结果。短板是区段重叠、仅部分改变及冷批次同时未命中时的复用。
- 本次只读 SQLite 查询：现有 `Resources/train-service-timetable.sqlite` 包含 882 条 trips，551 条 trip_physical_route_sections，覆盖 84 个不同 trip_id。84 表示有记录，不表示 84 条均完整可应用，不能将数据库当作全覆盖物理路线库。
- `TrainTimetableDatabase.swift:225` 有 physicalRouteSections；`hasCompletePhysicalRoute` 要求每对客运停站均有对应非空 lineIDs 和 sectionCodes。日期、站身份、来源、时刻冲突和编辑适用性限制需要保留。
- `ResolvedRailRoute.swift:15` 已有 DirectedInterval(lineID, code, direction)，支持保留有序区段与重复通过。`StationIntervalResolver` 已按线路建立有界推断结构；应在其基础上复用。
- JavaScript 的 `app/public/app-route-solver.js` 与 `app/public/rail-network.js` 仍承担求解/显示/持久化格式的对应行为，涉及共享 ID 或缓存语义的实施必须一并审阅。

## 推荐流程

1. **明确物理选择优先。** 行程自带 ordered sectionCodes/lineIDs 时，解析成有向区段序列，检查存在性、所属线路、方向、日期有效性和已证明的连接边界；直接引用测绘几何。选择无效时保留失败状态，不另选一条看似合理的铁路。
2. **查已确认的数据库路线。** 确切日期/运营日、站身份、车次和已确认时刻等匹配到唯一适用 trip，且相关子段具有完整物理证据时，取出对应区段序列。缺少物理路径的停站表、服务品牌、直通关系只能缩小候选，不能作为点亮线路的证明。数据库答案不得覆盖用户明确选择。
3. **复用已解析区段。** 同一区段序列、方向、有效策略和数据版本复用几何及证明。对尚未明确区段的请求，按规范化起终点身份、有序经由/重复停站、约束、日期、上下文与版本共用求解结果及进行中的任务。
4. **只推断缺失部分。** 使用已有 StationIntervalResolver 与物理连接证据构成的区段层拓扑。先约束到已知线路/运营者/经由站；有歧义时保留候选或待确认，不能因为缩小候选后只剩一条就虚称唯一。
5. **通用求解兜底。** 原有 dated physicalRail 求解用于尚无可用证据的部分，保留当前区域扩大和全国兜底规则。兜底成功后记录来源与验证结果；能映射到有序区段时保留区段身份。历史路径、仅有测绘图路径、intervals 为空的 matchedGeometry 使用独立结果变体，不能编造当前区段 ID。
6. **按行程装配并增量发布。** 将共享区段结果关联到各条行程，独立检查前后边界。共享区段已确认不代表两条区段之间已确认物理连通。显示去重可合并覆盖，里程、播放、折返与重复行驶必须保留次数和顺序。

## 数据与缓存分工

- 物理区段索引：sectionCode -> 来源、lineID、方向、站点出现位置、原始几何引用、测绘版本、有效期。复用 intervalByCode，避免另建同样的全集。
- 区段证明：以 sectionCode + direction + 影响证明的约束 + 日期 + 拓扑/历史/来源版本 + 证明语义版本作为身份；来源几何必须受版本约束。证明载荷保留完整 source-qualified 路径键、起终点、anchorIndices、各部分连接结果，不能只保存 verified 布尔值。跨区段连接证明单独以有序端点身份、连接证据和日期缓存。
- 请求结果缓存：已确认 ID、区段顺序、经由站与重复次数、有效策略、实际派生约束、日期、跨国 scope、历史/站映射/拓扑版本。不同记录可共享；不要粗暴去掉车次等会改变派生约束的输入。旧求解请求还必须包含 continuityAnchor 与 physicalContinuationKey。站序推断按整个兼容停站 run 缓存，再提取各腿，避免丢失后续站对早期分支的影响。
- 起步保留精确日期键。只有能证明完整有效期内所有相关边/约束均不变后，才考虑按有效期区间共享；不要直接跨日套用历史路线。
- 共享任务只有一个 RouteSolveLimiter permit 所有者，禁止批次持 permit 等待另一项再申请 permit 的工作。订阅者退出不取消其他人仍需要的任务；按资源 generation 发布，缓存按内存/条目预算淘汰。
- 不缓存取消、未完成或因缺少当前输入产生的临时失败为长期结论。明确 unavailable/ambiguous 可按具体资源与语义版本复用。
- 全数据库作为统一证据查询入口，按地区/日期/稳定身份过滤并延迟读取几何；美国/加拿大已退役数据不参与。

## 实施顺序

第一阶段：保留现有行为（StationIntervalResolver 当前可以按相邻或最短政策选择，不等于数学唯一），抽取区段请求/结果身份，在冷批次共享推断中间结果、区段证明和进行中工作；只改已确认重复的计算。

第二阶段：将已确认数据库物理路径接入解析入口，保留匹配适用性、日期、来源与歧义规则；支持完整路线的已证明子段切片。任何切片不得越过未知区段或用名字/最近点推断边界。现有 TimetableTripMatch 仅匹配整条 trip；子段切片需新增按有序站点 occurrence 和运营日时刻偏移匹配的操作，检查全部已提供约束并拒绝多重适用结果。

第三阶段：把已证明区段序列作为显示、里程和播放共同引用的标准结果，减少旧几何求解后再次识别线路。仍保留 sourceCoordinates 与 displayCoordinates 的现有区别、历史几何与缺口。

## 验证与尚待回答的问题

本轮只有源码审阅和一项只读数据库统计，没有构建、全量测试或性能跑分。遵循 ios/VERIFICATION.md；不恢复已退役工具。

实施时选择现有、直接相关回归：显式选择、歧义与单向区段、重复停站/折返、不同日期有效性、不同上下文派生约束、共享任务取消、两区段连接失败、历史几何与显示源分离。对代码行为有具体疑问才运行单个既有测试；需要编译时协调一次增量构建。

性能只需一个用户实际慢行程集合，观察缓存命中、不同区段请求数、重复证明次数、兜底次数及首次/完成显示时间。用户已确认慢发生在批量导入或批量重新求解；现阶段不宣称瓶颈占比或提升倍数。

用户因 Safari 并发操作明确选择先只做本地分析，网页咨询暂停。GPT-6.1 Sol 独立设计审阅指出推断政策、连续性缓存身份、证明载荷、历史结果变体、数据库子段匹配和 permit 所有权问题，本稿已纳入。Grok 提供数据库适用性摘要；其“train.id 必然进入摘要”的断言经 solveContext/readCached 本地审阅否定，未采用。

## 第一批源码修复记录

用户指示「start 开始修复」后，实现以下生产改动，iOS 与辅助 Catalyst app 通过同一 RailCore 使用：

- StationIntervalResolver：固定网络实例内的线程安全有界 memo。键为完整有序停站 run、全部线路/运营者约束与搜索预算；缓存 resolved/ambiguous，unsupported 和取消不缓存。命中仍检查取消。日期/机构适用性由原调用者逐次检查，不通过 memo 绕过。最多 128 个请求，访问/约束/区段总计成本 16,384，单项超过 4,096 不保留。
- RouteGraphStore.corridorGraph：在现有 feature-set 缓存前加入完整坐标顺序与半径的请求命中，省去重复的空间候选收集和排序。metadata 与原图缓存共同逐出，保留原节点预算；超过 8,192 个请求顶点不保留坐标 buffer，仍可使用原 feature-set 缓存。
- RouteSolver.verifiedSourcePath：证明随 graph 生命周期缓存，保存完整 qualified path keys。键包括原始 multipart 几何、日期、线路/运营者约束、displayRowNames 和 anchorIndices；nodes/adjacency/grid/nodeMeta 修改清空 memo。仅保存成功且未取消的证明；行程边界仍单独执行 provenBoundaryContinuation。每图最多 32 项、坐标/路径键/锚点总成本 32,768，单项超过 8,192 不保留。

新增回归位于现有 StationIntervalResolverTests、GraphCachePolicyTests、PhysicalEndpointTrimTests，覆盖完整 run、重复经过、方向、预算、取消、不同网络、日期及图修改后的失效。按用户「先完成源码，暂不运行」要求未执行。独立 GPT-6.1 Sol 源码审阅提出走廊请求 buffer 的额外保留成本，已加上顶点上限；复核未发现剩余源码层阻碍。没有编译、运行或性能通过的结论。

本次另委派 Grok 4.7 xhigh 只读检查两处请求缓存；其读取期间源码已更新，重新读取达到本次 5-turn 上限，未返回可采纳结论。未据此声称检查通过，也未重试或启动额外检查。

缓存是进程内实例/图级复用；资源格式、section_codes/line_ids 身份、旧请求摘要、JS 求解规则和持久化缓存版本均未改变。相关 Swift/JS 身份与区段顺序语义已检查，未新增全库扫描、第二套求解器或全国预计算。数据库中缺少物理区段证明的服务不会被当作已解析。

## 后续源码整合（2026-10-10）

已实现数据库子路线匹配、固定 SolverInputs snapshot 的区段/跨图证明 memo、共享冷请求所有者，并接入 RiddenRouteStore 与 Catalyst app。数据库匹配保留完整原行程范围、重复站出现顺序、原边界及显式选择；按日期索引查询当前及前两运营日，不扫描全国图。仅完整可信 trip、物理区段链和已提供事实一致时采用。时刻精度 exact/minute 才能确认或排除候选；approximate/unknown/nil 不制造唯一结果。运营日用于铁路有效性，原始记录仍用于行程显示。

相同冷请求先加入 SharedRouteWork，再由唯一 producer 取得 RouteSolveLimiter；单订阅者取消不会取消其他订阅者。跨图区段 memo 保留有向/连续性输入，跨图证明保留 snapshot UUID 和有序源 feature identity，任何图结构修改撤销共享证明来源。行程之间不共享未证明的连接边界。历史/源/显示几何区别及原区域扩大兜底规则保留。

本阶段改变的是 native runtime cache：当时版本 30、physical-section-evidence-v3，并纳入已有 timetableRevision。后续显示整合已将 drawn cache 更新至 31。JS solver/precompute 版本及其证据不变。dataset fallback 同样观察数据库选择；不能跳过它返回旧几何。Workbench 报告新增 processLifetime 的 started/joined/cache-hit/completed counters，保留原状态/耗时报告和仅已确认当前区段导出。

当时独立源码审阅确认精度修复后未发现其余阻碍；Swift frontend parse 通过。后续用户已授权执行，实际结果见 [follow-through](../completed/2026-10-10-route-resolution-follow-through.md) 和 [Workbench inspection](../completed/2026-10-10-route-workbench-inspection.md)。

## 本轮冷批次复查与候选索引（2026-10-10）

本聊天 `01a12818-5189-7243-ab99-26f2810001a0` 收到直接续查要求。原路由与显示聊天均为 idle；沿用路由范围，保留其他聊天的移动、源码和数据修改。没有修改显示几何或铁路数据库。

历史报告表明问题主要仍在冷解析：201 条真实记录的先前首轮为 392.146 秒，缓存复用轮为 0.338 秒。两者是旧源码/旧运行状态的证据，不能当成本次改动的前后对照；第一次还包含资源准备和既有部分缓存。930 项证据待审阅中，848 项物理区间尚未证明，不能将这些记录当作完整数据库路径覆盖。

采用 [本聊天的 ChatGPT Pro 5/5 咨询](https://chatgpt.com/c/6acac774-2c94-83e9-b71a-3f7e1793369e) 建议，将职责明确为：有序区间身份选择 → 带日期的物理证明 → 同一网络显示笔画切片。Pro 无本地文件访问；以下改动与结论由 Codex 核对和执行。

### 已落实的生产改动

- `RailCore/Timetable/TimetablePhysicalRouteMatch.swift` 新增不可变 `CandidateIndex`。运营日读取全部相关 trips 后，只构建一次稳定车站 ID 倒排索引；每条行程从最小候选集合起步，保留包含全部原始客运停站身份的完整 trip，再执行原匹配器。不按线路显示名称、距离、时刻精度或缺失物理证明提前筛掉竞争者。原始区段边界不用于这一排除步骤，否则可能把应为 unsupported 的未知边界变成 unavailable。重复站的顺序与次数仍由原递归匹配判断。
- `RailMap/Infrastructure/Persistence/TimetableRouteEvidence.swift` 按原来的运营日和前两日查询窗口、6 项／5,000 trips 预算共享索引。全部数据库记录仍参与构建；未覆盖的区域继续使用现有网络证据，不伪称已有时刻表覆盖。索引附加存储为每个车站对应的 trip 下标集合，未增加持久化格式或长期负缓存。
- `RiddenRouteStore.swift` 的冷请求生产者接收外层已经准备的 `CanonicalRouteInput`，复用同一份数据库选择、运营日和 provenance；不再在 digest 之后对同一生产操作重复补全。独立缓存读取、预计算数据检查与其他批量入口仍有各自的输入准备，不能声称全生命周期只执行一次。原单 worker、permit、日期物理证明及段间连接检查保留。

这同时修复了可复现的预算问题：5,100 个车站完全无关、服务名相同的列车会耗尽旧匹配器 20,000 步预算，令有效候选返回 unsupported。索引先排除确实不可能包含原始停站的列车，使预算用于相关 occurrence；它本身不证明唯一性或物理连通性。没有改动 section_codes/line_ids、缓存摘要格式、JS 求解或显示规则。读缓存时仍先计算数据库补全后的 canonical digest；新得到的数据库选择进入既有摘要，旧的不同选择不会复用。

### 聚焦证据

- 新增预算回归在修改前实际失败：有效候选被返回为 unsupported，日志 `/private/tmp/jtm-route-budget-red.log`。首次仓库内构建遇到生成资源包的 Finder 属性签名错误，改用既有 `/private/tmp/railkit-build-bis` 增量产品；未清理源码或恢复验证脚本。
- 修改后时刻表物理子路线套件 17 个测试通过，日志 `/private/tmp/jtm-route-index-green.log`。包括预算回归、重复出现的站、未知时刻竞争者、未知原区段边界，以及已有跨午夜、明确选择和不完整物理链回归。这是算法回归结果，不是实际批量性能测量。
- 最终取消检查调整后，同一套件再次通过（17 个测试，0.184 秒测试执行时间）。只读 GPT-6.1 Sol high 复核未发现本轮候选排除、运营日或共享输入的重要缺陷；其结论不替代测试或性能观测。Grok 4.7 xhigh 本轮达到读取轮数上限，未交付可采纳结论，没有据此宣称复核通过。
- 最终源码的 RouteWorkbench Catalyst 增量构建成功，日志 `/private/tmp/jtm-route-index-catalyst-final.log`；仅有既有的无 AppIntents.framework 元数据提取提示。前次构建期间补入最后的取消检查，因此只重编译变化后的最终状态，未执行完整矩阵。全程重任务串行，未重跑 201 条批次或操作其他聊天的运行中 App，未 commit/push。
- 已审阅 JS 的 `app-route-solver.js` 中有序 section_codes 输出，以及 `rail-network.js` 中按区段身份、方向与 endpoint 切片的对应路径；本次没有改变共享身份或显示语义。

### 平滑与底图比较

查看 `/private/tmp/jtm-tabata-workbench/` 已保存的同相机 basemap、display、smooth 和 reference 证据。针对山手线駒込→田端 `#15`，本轮逐项确认当前 package 的来源／display 顶点和端点车站 ID 与该注册快照相等；历史 smooth 图可见其沿底图运行线弯曲。不过快照的 renderContract 为 centreline-v2，当前 InspectorStrokeGeometry 已为 inspector-centreline-v4-exact-physical-forks；因此这些截图仅能作为旧渲染的局部比较，不能认证当前平滑或岔口像素。旧证据的 0.849 米是该视窗内对缓存 OSM 代表轨道的单侧抽样距离，并非 Apple 铁路线像素距离、全区段最大误差或主 App 多车道高亮测量。

以后仍应按共享网络区段在固定相机、比例、地图样式下比较 source／display／最终平滑笔画；高亮使用同一 StrokeRef。位置和弯曲问题应在来源、datum、display override 或平滑层解决，不在每条行程内重复匹配像素。全国检查与当前主 App lane/branch 像素一致性仍由显示范围的现有检查计划记录，未在此宣称通过。

### 尚未改变的成本

区间已选中后，仍构建 corridorGraph 再查询成功证明 memo。跨图 memo 的 provenance 包含 snapshot UUID 与有序 featureIndices；后者由建图确定，而且图修改会撤销 provenance。因此将命中查询前移需要一个完整、可失效的来源身份契约，不能只用 section code 或端点代替。未缓存缺少证明的失败路径，也未跳过日期、物理边界检查。真实冷批次耗时、阶段占比和附加索引峰值内存尚未测量；不能把本轮局部修复称为全部慢求解已经解决。

### 2026-10-10 native inspection and optional verification follow-up (in progress)

User explicitly requested the two Mac inspector apps and a modular, lower-cost
optional verify command after retiring the old pipelines. Added `ios/verify.sh`
with separate opt-in Swift-filter, incremental build, RouteWorkbench launch and
RailAlignmentInspector launch modules under `ios/tools/verification/`. Default
help performs no checks; jobs default to two; app launch is never called a pass.
Shell syntax, all four dry-run command paths and rejected missing/invalid options
were observed. Native 201-journey inspection and current-revision Japan capture
are queued behind existing external Swift/SolveBench CPU work; completion and
geographic verdicts remain unclaimed.

### Actual native follow-up evidence

The queued work subsequently ran with user-approved CPU coordination.
RouteWorkbench completed201/201:197 resolved,4 partial,0 consistency failures;
930 findings remain explicit, including848 unproven physical intervals and78
unavailable intervals. Observed native load371.58665s, import0.3789s and
consistency review0.1442s are a single run, not a measured before/after speedup.
Report: `ios/refactor-parallel/route-current-inspection-20261010.json`.

RailAlignmentInspector captured446 original views, then focused repaired Keiyo
arms and other risk-selected curves/parallel corridors. Manual findings, exact
passenger-data repairs, failing/passing regression evidence and remaining
uncertainties are in
`docs/reports/japan/rail-alignment-repair-2026-10-10.md`. Original source versus
Apple offsets, ambiguous multi-track assignment and four route partial proofs
remain investigable issues; completed capture is not an alignment verdict.
