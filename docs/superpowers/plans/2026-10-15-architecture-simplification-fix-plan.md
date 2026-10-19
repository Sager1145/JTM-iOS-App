# 架构简化修复计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Independent bounded investigations may use the user's routing/offload preferences; shared owner changes remain sequential. Checkboxes record implementation, not planning completion.

**Goal:** 删除无生产价值的实现和重复转换，让行程写入、铁路包读取、显示链准备和时刻表查询各有一个明确所有者，同时保留物理证据、现有用户能力与按需内存策略。

**Architecture:** 保留现有可工作的 module 与平台 adapters，先删除确认冗余，再集中实际规则与数据。共享不可变载入结果，不预建所有派生索引；用既有功能 interface 替换重复路径，不叠加通用 Manager/Repository/Context。

**Tech Stack:** Swift 6 / SwiftUI / MapKit / Foundation / SQLite；既有 JavaScript fixtures 和 Python 时刻表构建工具。

**Spec:** [用户提供的六路审查](../../../ios/docs/reviews/feature-interface-audit-2026-10-15.md)；补充[当前功能与接口梳理](../../reports/integration/function-interface-architecture-2026-10-15.md)。两份报告是待裁定的证据清单，不是所有删除建议都自动成立；下节裁定优先。

## Global Constraints

- 产品支持 Japan、Taiwan、Hong Kong、Macao、Korea；北美档案不进入产品，不新增其兼容。
- iPhone 仅竖屏；保留 iPad 方向与自适应布局；Dynamic Type 限定 `.xSmall ... .xLarge`。
- 物理连接必须有日期、身份及实际轨道证据；不以近邻、同名、换乘组、直通展示或直线补缺口。
- 规范数据、统计与缓存使用 WGS84；MapKit 显示变换只应用一次；source/display 不合并为同一可变几何。
- 保留用户未提交修改，不自动提交、推送、发 issue 或发布。本计划仅写文档，执行另外开始。
- 采用 [ios/VERIFICATION.md](../../../ios/VERIFICATION.md)。一次一个 heavy job，复用已有 build/scratch；不跑全量 fixture generator、全国重建、完整矩阵、全树 hashes 或新 umbrella runner。
- 不因文件长或目录多而拆分/合并；不因只有一个生产调用方就删除有真实行为的 module 或测试 seam。

## Review Focus

1. 缺资料、解析失败和乘客尚未确认是不同结果；记录可保存为 pending，但不得计作物理证明。Tasks 3、8、10、12 覆盖。
2. 用户在后台任务期间编辑、导入、切地区、取消，旧快照不得覆盖新状态；多订阅者取消不得清掉他人结果。Tasks 4、5、6、8、9 覆盖。
3. 显示链反向、闭环、分支、重复到站、历史线路与台湾/香港等 datum 变换不能因复用缓存而改变证据或显示。Tasks 6、7、9 覆盖。
4. 导入失败、磁盘写失败与重试不能重复加记录、覆盖后续编辑或丢备份；删除旧入口后测试必须走产品路径。Task 5 覆盖。
5. 午夜跨日、空日期、同名车站、资料版本变化、未覆盖服务日不能因统一模型或目录而任意选中候选。Tasks 2、6、8、9、13 覆盖。

## 对审查结论的裁定

| 审查建议 | 本计划采用的范围与修正 |
| --- | --- |
| 删除 OverlapLanes / StationJoinSmoothing | 当前 Swift 生产引用检索只发现两者内部互用，其余是测试；可进入删除批次。Web 仍使用对应 JS，不能顺带删除 JS/fixtures。执行时重查辅助产品和资源引用。 |
| “包只解析一次” | **一次 resident resource identity 的并发请求共享一次完整解码**，不是每地区永久驻留，也不是启动全量构建。header-only 扫描、显示 chunk、source rail-sections 是不同读取合同。 |
| “三条折线都能删到两条” | 先共享显示链拼接，再判断纯显示重复。`canonicalizeRouteFeature` 还可能选择方向轨道并重新验证 source，不能整段跳过。 |
| “Train 全程只需一个快照” | 先删除同义 Dates/Statistics 记录；保留真实 route request、证据、缓存依赖 key 和统计日期语义。不新增包含所有派生值的万能快照。 |
| “三个时刻表目录都是同一实现” | 它们含 occurrence、历史模式、局部线路摘录等不同知识。统一访问和来源语义；未覆盖资料先迁移后删除读取器，禁止丢数据或伪造完整 occurrence。 |
| “数据库失败是完全静默” | `ServicePatternPickerView.swift:434` 已显示 unavailable。修复重点是显式 open/query 失败及停止自动混入替代结果，不重复造告警系统。 |
| “TripRouteValidation 失败视为全部通过” | 不准确：保留候选但 `physicallyResolvedIDs` 为空，按现有合同仍是未证明。保留 pending 行程能力，补清晰失败结果，不删除记录。 |
| “RailApplication 解散风险低” | 不按 namespace 数量裁定；它包含导入候选、取消/代次协作等真实规则。逐项收敛后仍有职责就保留 target；target 删除放最后且有条件。 |
| “NewTripView 与编辑器直接合一” | guided create 与完整编辑确有不同交互；合一的是草稿、搜索、验证和保存实现，不强迫用户改用同一张表单。 |
| “356 个 normalizer 几乎相同” | 脚本有来源、日期、站点别名、编组/座席等硬约束，不能文件名一替换就批量删除。已有 `reviewed_timetable_staging.py`，优先复用它，不再造平行框架。 |
| 性能秒级收益 | 报告注释是历史测量；本计划只预期减少特定解析/拼接次数，不预先承诺启动时间、峰值内存或帧率收益。 |

## 执行顺序与文件职责

每个 Task 是可以独立审阅、完成后可运行的软件改动。默认原地保留当前工作树；需要隔离时先检查现有 managed worktree，不能丢掉未提交的前置修复。

```text
T1 死代码 ─→ T2 同义模型 ─→ T3 校验 ─→ T4 状态 ─→ T5 写入 ─→ T11 编辑/搜索
T1 ─→ T6 包读取 ─→ T7 显示链
T3 + T5 ─→ T8 时刻表 ─→ T9 路线策略
T1 ─→ T10 本地化/平台整理
各实际 owner 的改动 ─→ T12 失败合同收尾 ─→ T14 module 归属裁定
T13 构建工具可单独做；不与 App 改动混成一个验收批次
```

优先执行 **T1 → T2 → T3 → T6 → T7**，这五项分别交付实际删除、减少模型搬运、去 JSON 往返、共享完整解码、共享显示链。T4/T5 随后收回状态和写入；时刻表、路线策略与 UI 统一分开推进。箭头表示输入依赖，不要求为无依赖任务等待整阶段。

### Task 1：删除已证实的死实现与纯转发

**Files:** `ios/RailKit/Sources/RailCore/Rendering/{OverlapLanes,StationJoinSmoothing}.swift`；`RailPresentation/Editing/{JourneyDraftSelection,JourneyDraftEdits}.swift`；`RailPresentation/Journeys/JourneyHeroIdentity.swift`；`RailCore/Routing/{RouteConfirmationRepair,RailwayRouteInference}.swift`；`ios/RailMap/Workspace/{WorkspaceTabs,WorkspaceSheetContent}.swift`；`Playback/PlaybackController.swift`；`Journeys/ItineraryStore.swift`；`JourneyEditor/RideEditorView.swift`；`ios/source-ownership.json`；对应测试/文档。

**Interfaces:** RailwayRouteInference 唯一的生产调用 `RideEditorView.swift:864`（`search`）改为直接调用 `RecordedRouteAdmission.search`。`choice` 只在测试中使用（`RailwayRouteInferenceTests`、`TripRoutePlannerTests`），改用 `RecordedRouteAdmission.admission(...).automaticChoice`。`RouteConfirmationRepair.clearInferredPending` 现在是常量 no-op（原样返回 trains，`changed: 0`），pending 标记本来就没有被改动：删除该文件和测试，以及 `ItineraryStore.swift:558–560` 中永远不成立的 `changed > 0` 分支。不触碰 `RideRouteResolution.resolve`（生产调用方 `RiddenRouteStore.swift:1548`）。

- [x] 对每个目标按符号/成员检索所有 Swift 产品、测试、Xcode/ownership 和 fixture 模块；区分内部互用、真实调用和测试-only。未确认无调用的报告条目不自动加入删除集。
- [x] 删除 OverlapLanes/StationJoinSmoothing 及仅证明这套死 Swift 算法的测试；先把仍有独立生产价值的 shared fixture helpers/行为用例留到 ContinuousStroke 对应面。JS 实现、Web fixture 及其生成器保持。
- [x] 删除无生产调用的 `JourneyDraftSelection`/`JourneyDraftEdits`（仅 `StationLineSelectionTests` 使用）、`JourneyHeroIdentity`（仅 `JourneyHeroIdentityTests`）、从未构造的 `WorkspaceRetainedPages`（`WorkspaceTabs.swift:149–166`）、只写不读的 `PlaybackController.exportFrameSerial`（`:123`、`:750`），以及从未构造的 `WorkspaceSheet.newJourney/.edit`（新建/编辑走 `presentJourneyEditor`，`RailWorkspaceView.swift:454`）。把 RailwayRouteInference 的转发调用改到既有 owner，移除 clearInferredPending 调用。逐项确认没有顺带移除保存/取消/错误操作。
- [x] 公共 helper 逐个处理：`JourneyBranding.usesDetectedLines`（`JourneyBranding.swift:15–17`）没有调用方，直接删除。`RideEditorAI.denial` 是有生产调用的转发（`RideEditorView.swift:2080`），把调用方内联为 `JourneyCompletion.requestEligibility(...).denial`，行为不变。单一实现 protocol 若承载平台生命周期或现有测试控制，不按数量删除。
- [x] 更新 `ios/source-ownership.json`（OverlapLanes `:423`、StationJoinSmoothing `:429`、RailwayRouteInference `:439`、draft/hero `:495–498`）、API 文档、旧功能映射中的现行断言（`project.pbxproj` 无这些符号）。`app/data/sample-passing-cleanup-artifact-manifest.json:337` 用旧路径列出了 RailwayRouteInference：它是历史清单，不改，只在删除记录中说明；检查相关 Swift 编译及保留的 ContinuousStroke 回归面。**不要运行**全量 `build-port-fixtures.mjs --check`：它生成 JS 答案，不导入被删 Swift 类型，且包含高内存场景；先源码核对依赖即可。

**完成判据:** 删除目标无剩余产品引用；pending 不被自动清除；生产车道模型仍为 ContinuousStroke。修正先前报告把无生产调用的 OverlapLanes、JourneyDraftEdits 当作活跃实现的映射，历史证据原文保留。

### Task 2：日期/乘车语义直接使用规范 Train/Stop

**Files:** `RailCore/Utilities/Dates.swift`、`RailCore/Statistics/Statistics.swift`；App `Journeys/{TrainDateBridge,ItineraryStore}.swift`、`Statistics/{MileageStatisticsStore,PassportStatistics}.swift`、`Playback/PlaybackController.swift`、`Map/MapRideMarkers.swift`；Presentation `Journeys/RideLedger.swift`、`Statistics/StatisticsMembership.swift`、`Journeys/LaunchJourneySelector.swift`、`Workspace/WorkspaceJourneyRules.swift`；相关调用与测试。

**Interfaces:** 保留 `Dates.trainDate/daySpan/trainSpans/sortByDateAndDeparture` 的业务操作名，参数改为现有 `RailCore.Train`；统计读取规范 Stop，统计日期继续显式使用当前 normalized bucket。

- [x] 迁移 DatesParityTests 的输入解码到规范 Train；保留“无日期、ID 推断、24+ 小时、跨多日、同日排序”的既有期望，不为类型改名新建镜像测试。
- [x] 日期方法直接读取 Train/Stop；删除 forDates（`TrainDateBridge.swift:17–24`）和分组后按 ID 找回 Train 的路径（`ItineraryStore.swift:789–792`），让排序结果就是原记录。移除 Presentation 和工作区局部重建的 Dates carrier。
- [x] 将已乘/时长规则读入规范 Stop；迁移 Statistics.Train/Stop 的消费者，保留 `MileageMatching.Journey/Segment` 中真实的匹配、出处和完整度信息。明确统计日期覆盖字段，禁止默默改用 raw Train.date。
- [x] 日期模型删除与统计模型删除分别审阅；已有缓存使用其真实依赖，不创建全量派生快照缓存。只有仍观察到重复计算且有现成 revision owner 时才延续已有局部缓存。
- [x] 选择 DatesParityTests、RideLedgerTests、StatisticsMembershipTests 中受影响的小型用例；复核播放和地图 marker 的已乘规则一致。

**完成判据:** 不再存在 `Train → Dates.Train → ID 反查 → Train`；已乘定义不在 map/playback/stats 各保一份。

### Task 3：消除校验类型复制和 typed → JSON → typed 往返

**Files:** `RailApplication/Editor/RideDraftValidation.swift`、`RailApplication/Import/ImportPreflight.swift`、`RailCore/Journeys/Train.swift`（TrainValidation 定义）；App `JourneyEditor/EditorValidation.swift`；`RideDraftValidationTests`、`TrainValidationParityTests`、`ImportPreflightTests`。

**Interfaces:** App 直接复用 `RailApplication.RideDraftValidation.Field/Severity`，本地化与聚焦属性留 app；typed 记录校验归现有 TrainValidation，诊断包含字段位置与 reason，外部 JSON shape 检查仍在 import seam。

- [x] 先用 typealias/既有类型复用删除 app Field/Severity 和 identity switch；保留 UI 特有的文案参数、定位和 literal message。
- [x] 将 schema 业务约束集中为可直接校验规范 Train/Store 的一个实现；动态 JSON 入口先检查字段类型/缺失/未知值并构造规范值，再调用该规则。不能让解码默认值掩盖非法原始输入。
- [x] draft/preflight 改走 typed 校验；删除 JSONEncoder→String→JSON.parse 回环，不让 UI 再重述 schema 规则。保留编辑特有的 ID 冲突提示与不阻止保存的 warning。
- [x] 在现有测试补一个 raw input 与 typed input 对同一非法事实得到相同 reason/path 的用例；保留导入 shape 错误和重复 ID、错误停站序号。只运行相关 suite/个案。

**完成判据:** 公共业务约束一处定义，app 只做展示；JSON 仅用于真正读写外部格式。此任务不重写规范导出格式。

### Task 4：移除 RideStatusCenter 全局镜像

**Files:** App `Journeys/{RideRouteStatus,JourneyPresentationBridge,RideDetailView,JourneyCardInformation,ItineraryStore}.swift`、`Infrastructure/Persistence/RiddenRouteStore.swift`、`Infrastructure/Network/TraversedLineDetector.swift`、`App/AppShell.swift`、`RailWorkspaceView.swift`、`JourneyEditor/{RideEditorView,NewTripView}.swift`、`JourneyShareImage.swift`、`RouteLogoSquare.swift`（当前 `RideStatusCenter.shared` 一共 11 个调用文件）；Presentation `Journeys/RouteStatusResolver.swift`。

**Interfaces:** `RiddenRouteStore` 提供按 ID 读取的路线状态与重算操作；`ItineraryStore` 提供记录 ID/确认状态；经过线路结果归其既有 detector/route owner。`RouteStatusResolver.status` 保留唯一状态规则。

- [x] 画出当前 shared 字段的真实写入 owner 与消费者；每个字段只选一个已有 owner，不新建替代的全局状态中心。
- [x] 从 AppShell 把现有 owner 注入实际功能根部；详情、海报、logo、编辑器读同一事实。需要显式值的导出使用一次不可变投影，不复制长期可观察状态。
- [x] 迁移 `resolveAgain`（`RideRouteStatus.swift:138`）到 route owner。把 `trainIDs`（`:58`；编辑器以 `existingIDs` 参数传入，见 `RideEditorView.swift:2074`、`NewTripView.swift:1055`）迁到 itinerary owner；删除 publish/begin/finish/clear 镜像协议、weak wire 和 `explicit ?? singleton` 分支。
- [x] 用 RouteStatusResolver/JourneyPresentationResolver 现有回归面验证 pending、局部缺口、单条重算、删除后状态；一个实际详情/分享操作检查 owner 生命周期即可，不跑 UI 矩阵。

**完成判据:** shared singleton 与全部镜像写入消失；旧后台结果不能复活已删记录。

### Task 5：收敛行程修改与持久化提交

**Files:** App `JourneyEditor/JourneyEditing.swift`、`Journeys/ItineraryStore.swift`、`Import/{ImportFlow,TransferGuideImport}.swift`、`Infrastructure/Persistence/{RideLibrary,RidePersistenceQueue,RideStorage}.swift`；`NativeImportPersistenceTests.swift`。

**Interfaces:** `ItineraryStore` 继续拥有工作集与 generation；把已有 JourneyEditing 的 add/replace/批量导入保存协作收回同一提交实现。返回工作集结果及保存结果，区分“内存已应用、磁盘失败”；不声称内存与文件跨系统原子事务。

- [x] `ItineraryStore.importJSON`（`:434`）没有生产调用，但测试依赖面比“两个测试”大：`NativeImportPersistenceTests.swift:127` 直接调用一次，helper `baseline(preferences:)`（`:477`）也调用它，而该 helper 被约 10 个测试使用。先把这个 helper 和 `:127` 改走产品 `runImport`（`:350`；生产调用方 `ImportFlow.swift:392`、`RouteStressHarness.swift:74/157`），确认这些测试仍然断言原来的事实，再删除同步入口。保留忙状态/ready/generation/cancel 检查。
- [x] 对 add/replace/delete/move/visibility、样例 merge/replace、JSON 与截图批量提交统一“验证候选 → 检查基线 → 发布工作集 → 排队一次保存”的所有权。优先扩大现有 owner，而非再叠一个仓库门面。
- [x] 保留现有 add/replace 的条件回滚语义；回滚不得覆盖提交后用户编辑。截图保存重试仅重存当前工作集，不重新 add。破坏性操作先做现有备份。
- [x] 删除调用方各自的 save 编排及纯转发 convenience；RideLibrary 继续合并写请求，queue 继续排序，RideStorage 继续原子 IO。
- [x] 用 NativeImportPersistenceTests 受影响个案验证 ID 碰撞、后台导入时编辑、写失败后继续编辑/重试、恢复和取消；不制造第二套测试专用提交实现。

**完成判据:** 一个修改操作不会保存多次；没有测试-only 生产写入口；失败与重试结果可由调用方正确展示。

### Task 6：共享完整包解码，保留按需与有界驻留

**Files:** App `Infrastructure/Network/{RailNetworkStore,DisplayNetworkCache,EdgeIndexCache,EditorCatalogLoading}.swift`、`JourneyEditor/EditorRoutePackageCache.swift`；辅助 inspector `InspectorModel.swift:141`（另有一次 `LoadedPackage.load`，只核对、不强制迁移）；Core `Rendering/DisplayParts.swift`、`Data/CompactPackage.swift`、`Stations/RailIntervalCodes.swift`、`Routing/RouteNetwork.swift`。允许新建 **一个** `Infrastructure/Network/RegionPackageStore.swift`，仅在现有 cache owner 无法自然持有共享读取时使用。

**Interfaces:** 一个 actor-owned `package(country:) async throws -> DisplayParts.LoadedPackage` 提供不可变完整解码；请求 identity 必须包括地区及当前资源 revision。metadata 的 header-only 入口继续存在；RouteNetwork/EdgeIndex 仍是按需派生。

- [x] 以现有 `DisplayNetworkCache.inFlight/retain`（`:25`、`:30–31`）为基线集中完整文件读取。现状：detached task 共享，订阅者取消不会取消它；joiner 不清 `inFlight`，发起者 `catch`（`:104–106`）在失败时清槽；`retain` 与 `seed` 都只保留一个地区（`networks = [key: network]`）。同 identity 同时请求共用 task，失败不当作成功缓存，单个订阅者取消不删除他人 task。revision 在 owner 内据现有 RailResourceRevisions 派生，不另加平行版本协议。
- [x] 当前同一地区最多会被完整 parse **三次**：`RailNetworkStore.decode`（`:1565`，经 `ensure` → `decodeGeometry`）、`DisplayNetworkCache.build`（`:119`）、`EditorRoutePackageCache.load`（`:20`；NewTripView 会同时载入 catalog 和这个 package）。这三处改为消费同一 LoadedPackage。EdgeIndex 本身不 parse compact 文件，已经在 await `DisplayNetworkCache.network`，不需要改。`EditorCatalogLoading` 只解码 `CompactPackage.StationDirectory`（不含 segments），保持这条轻量读取；只有在已有驻留 LoadedPackage 时才可以复用，不能为 catalog 触发完整解码。删 seededParts（`DisplayNetworkCache.swift:64–70`；line ID 一致时跳过布局，但仍会再 parse）这种旁路，真实 source rail-sections、display blob 不改成 compact 替代物。
- [x] 共享解码之后也必须共享 DisplayParts 布局：由现有 DisplayNetworkCache 继续按需构建一次 RouteNetwork；RailNetworkStore 的 full decode 读取同 resource generation 的 network line parts，不再自行为每条线运行 DisplayParts。EditorCatalog 仅请求 package，不被迫构建 layout。不得删除 seed 后反而重新计算两遍布局。
- [x] 保留 header-only 启动、viewport chunks 和当前 cache 释放/限流方式；owner 不永久 retain 五地区，不提前构建 route/stats。淘汰后允许合法重读；“一次”只承诺一次驻留 identity 内共用完整解码。
- [x] 保留“取得 build permit → 释放旧 retained value → 分配替代值 → 在 permit 内发布”的顺序；edge 构建会等待 display 构建：两者是各自的 `RouteSolveLimiter(limit: 1)` 实例（`DisplayNetworkCache.swift:26`、`EdgeIndexCache.swift:20`），edge 在持有自己 permit 时 await display（`EdgeIndexCache.swift:46–51`）。合成同一个不可重入 permit 会死锁，也不要误用 `RouteSolveLimiter.shared`。多地区 route 合并保留 catalog 顺序，统计 index 合并保留原调用顺序，两者不共用一个拼接 key。
- [x] 对 interval 坐标的重复 decode 与 RouteNetwork.Line.compactLine 持有逐字段查消费：只删除确实同语义的坐标副本，把仍需 source 的字段留在 source owner；不以显示平滑坐标代替源证据。
- [x] 缩小 compactLine 时保留其实际消费的 nameNorm、permittedTraversal、stationOrderDirection、displayStationCoordinates、displayIntervalCoordinates、displayReversalBranches；显示 reversal 元数据不能被当作多余坐标删除。统计仍保持 N02/source 优先的 collision、类别和 dated denominator 语义。
- [x] 在现有 cache/headers 测试面补小型并发读取计数、失败后正常请求、revision 变化、淘汰再载入；保留 `CompactPackageHeadersTests.geometryIsNotRequired`。需要新增测试文件时仅测试真实 loader interface。
- [ ] 如需验证收益，任选一个现有 region/一次冷 full ensure，记录读/parse 次数和内存；不运行全国 baseline/candidate。未测时只报告消除了哪些重复读取。 未测：本收尾没有冷启动 parse/内存计数。

**完成判据:** 同一驻留快照不再被不同消费者完整 parse 两次；不增加启动几何加载或全国索引驻留。

### Task 7：一次准备共用显示链，随后删除纯显示重复计算

**Files:** App `Map/{MapLineGeometry,RailMapCoordinator,MapNetworkRendering}.swift`、`Infrastructure/Network/RailNetworkStore.swift`；Core `Rendering/StrokeRide.swift`、`Routing/{PrecomputedRouteDisplay,RideRouteResolution}.swift`。

**Interfaces:** 在当前几何准备/cache owner 中按 `DrawnLine.contentID + chain identity` 持有一次 joined chain，junction、stroke reference、pixel projection 共同读取。屏幕投影缓存另外包含 frame/LOD/datum 依赖。

- [x] 拼接实现已经只有一个：`joinedChainCoordinates`（`MapLineGeometry.swift:203–204`）。问题是三处调用各算一遍，没有共享结果：`continuousChainPixels`（`:224`）、`JunctionCandidateIndex.init`（`:265`）、`prepareStrokeReferences`（`RailMapCoordinator.swift:2968–2969`）。本任务是保存并复用这一次结果，而不是合并三套实现；只改复用，不改线路选择、锚点顺序或坐标域。
- [x] 核对当前 datum：`prepareDisplayLine` 在构造 DrawnLine 前已经做了 `AppleMapDatum.display`（`RailNetworkStore.swift:1401`；canonical decode 路径在 `:1608–1610`），DrawnLine.intervals 不是 raw WGS84。`MapLineGeometry.swift:192–198` 的注释写的是 WGS84，与实际不符，要修正。缓存保持现有显示域，不要第二次调用 AppleMapDatum。
- [x] 用共同 chain/cumulative measures 承载切片；保留反向、闭环、分支与 contentID 失效。只有原生渲染确实不消费且无物理意义的 intermediate coordinates 才删除。
- [x] cache identity 除 contentID 外保持现有 anchor、junction/follow dependency 的失效；overview/full replacement 即使 line ID 相同也不能复用旧几何。chain 不在当前 frame、被淘汰、日期不适用或 StrokeRide 拒绝时保留现有显式几何，不强制 snap 到今天的链。
- [x] 独立检查方向轨道选择和 source reproof，两者都继续运行。方向选择在 `RouteNetwork.canonicalizeRouteFeature`（`RouteNetwork.swift:626–667`）内；source reproof 不在其内，而是调用方 RideRouteResolution 的 `verifiedSourcePath`（`:261–264`、`:397–402`）。历史几何跳过 canonicalization（`:373–380`）。`DrawnSegment` 不在本任务强制改成仅 chain reference，除非所有历史/独立腿/预计算消费者都能表达，且不再需要 display arrays。
- [ ] 选 StrokeRideTests 的 `preparedIndexMatchesExhaustive/preparedIndexSnapshot`、StrokeJunctionDependencyTests 的 `throughHostArrivalInvalidatesOnlyItsBranch`；改到 canonicalization 时另选 DirectionalAlignmentSelectionTests 的 `automaticDirection` 和 RideRouteResolutionTests 的 `historicalGeometryIsNotRedrawn`。只处理当前实际变更；有显示路径变化时，在一个真实病例做原生截图对比，再考虑第二个确有 datum 依赖的病例。 未完成视觉部分：没有原生截图对比；本收尾也没有重跑这些用例。

**完成判据:** 每条实际准备链只 join 一次；source 证明不变，坐标域明确。没有把取不到 chain 的路线改成直线或静默丢弃。

### Task 8：统一时刻表查询合同与已匹配证据复用

**Files:** Core `Timetable/{TrainTimetableDatabase,ServicePatternBrowsePolicy,TrainServicePatterns,LineServiceCatalog,TimetablePhysicalRouteMatch}.swift`；App `Timetable/{ServicePatternPickerView,TimetableQuickMatchController}.swift`、`Infrastructure/Persistence/TimetableRouteEvidence.swift`；对应 builder/资料 schema 仅在确需迁移时改。

**Interfaces:** 先改为显式 throwing database-open，唯一查询 owner 返回有来源的 occurrence / pattern / excerpt 结果及 coverage；不能把 pattern 编造成 occurrence。以既有 `TimetablePhysicalRouteMatch.Match/Provenance` 复用匹配证据，不新增平行 Match 类型。

- [x] 区分资源不支持、缺失/损坏、查询失败和合法零结果；更新当前 picker 的已有状态展示，移除失败后自动返回另一目录冒充同类成功的路径。现状：`TrainTimetableDatabase.init(url:)` 会抛错，但 `bundled()` 用 `try?` 吞掉了（`:668–670`）。数据库为 nil 时，`loadTimetable` 在设置 `timetableQueryFailed` 之前就返回（`ServicePatternPickerView.swift:472–474`），picker 同时显示 unavailable 说明（`:434`）和 legacy `TrainServicePatterns` 行（`ServicePatternBrowsePolicy.swift:142–152`）。`TrainServicePatterns.patterns` 在缺 JSON 时 `fatalError`（`:311–329`），也要改成显式失败。`LineServiceCatalog` 失败已经有局部 unknown 状态，不回退到其他目录，保持不动。
- [x] 按日期/服务 ID 对现有三种资料做**目标查询**，列出未覆盖的 pattern/excerpt；把可保真表达的知识迁入统一存储，保留来源、半开有效期、完整度和原始 station identity。无需全国再生成以证明一个服务。
- [ ] 当相关知识已迁移且消费者只调用同一查询入口时，删除对应 legacy runtime reader；迁移未完成的条目明确呈现其真实种类，不静默隐藏或伪称时刻表完整。新 schema/产物变更单独审阅。 未删 legacy readers。仍保留 171 个 pattern-only services、20 个 pre-occurrence patterns、16 个未覆盖 excerpts。
- [x] 编辑器已应用的 occurrence match 作为与 Train 内容、serviceDate、timetableVersion、calendar、rail revision 绑定的 transient 证据交给 route evidence owner。编辑停站/时间/路线/日期或升级资料即失效，未绑定证据仍走权威匹配；不信任随 JSON 导入的“已证明”标记。
- [x] 去掉以 `JSONEncoder` 编码 `Request{train, sections}`（改写 id 后、sorted keys；`TimetableRouteEvidence.swift:13–16`、`:45–51`）作为缓存 key 的做法，用 matcher 真正依赖的 typed identity；证明依赖不清前宁可不复用。保留原始记录/别名和三个服务日的跨夜候选语义，不因优化而只查当天。
- [x] 选 ServicePatternBrowsePolicyTests、TrainTimetableDatabaseTests、TimetableServiceDayContextTests、TimetablePhysicalRouteMatchTests 中数据库损坏、零结果、跨夜、重复到站、歧义、版本失效个案。

**完成判据:** 一次真实 query 的来源、完整度和失败有确定解释；相同有效证据不重查；部分来源没有被“统一”丢掉。

### Task 9：合并路线提案策略，删除有替代合同的旧求解路径

**Files:** Core `Routing/{RecordedRouteAdmission,LocalJourneySearch,RailwayRouteChoices,TokyoConventionalRouteInference,RailwayRouteInference,RouteRepair,RouteRepairFlow,TripRoutePlanner,RouteSolver,RideRouteResolution}.swift`；App `Infrastructure/Persistence/RiddenRouteStore.swift`、编辑器/修复调用方。

**Interfaces:** `RecordedRouteAdmission` 拥有唯一 automatic admission/outcome 规则；LocalJourneySearch 是内部搜索算法，TripRoutePlanner/RouteRepairFlow 只保留真实的新建请求/多步修复语义。不是按“8 个文件”强并成另一个公开 PackageRouteProposal。

- [x] 删除 RailwayRouteInference 转发后，收回 `LocalJourneySearch.Result.uniqueChoice` 到 admission owner 的反向策略依赖；Tokyo 策略作为其内部实现，所有调用共享同一 pending/唯一性判断。
- [x] 保留手动 passenger choice 与 corridor preference/package inference 区别；统一 planner 和 editor 使用的物理连接规则，`TripConnectivity.link` 目前只返回 `.sameLine/.throughService/.none`（`TripConnectivity.swift:16–25`），`.network` case 不可达：确认没有其他构造点后删除，否则保持不授予新连接。前提：T1 已删除 RailwayRouteInference 转发。
- [x] 按每个 RouteSolver public 符号查 app/auxiliary 真实消费，仅测试调用的内核收为 internal，测试用 @testable；RideRouteResolution 仍普通 import 测完整生产策略。
- [ ] 对 decodeUncached（`RiddenRouteStore.swift:760–801`：`allowLegacy: false` 的 first-pass `:776` → precompute `:783–793` → 默认 `allowLegacy: true` 的 legacy-pass `:796–800`），用几个现存实际命中病例解释后一次求解究竟补了什么；可用一次局部计数，不建长期监控。若承担未迁移的 dated/official 证明，将该必要策略并回同一 resolution 操作后再删第二调用；不是简单删 allowLegacy=true。 未测：legacy pass 保留，没有命中病例计数，因此没有删除第二次求解。
- [ ] 以 RecordedRouteAdmissionTests、LocalJourneySearchTests、RideRouteResolutionTests 和一例有证据的旧路径命中回归，确认显式区间不改道、断裂不造连接、未确认不变已确认。删除旧输入拼写/无证明 part 也必须先检查当前正式产物的相关记录与 builder，而非盲开兼容。 未作为证明勾选。Task 9 改写了期望以匹配更早未提交的 TripConnectivity 行为；Haruka、Hokuto、Super Oki 等跨行样本没有提案，需要所有者决定。本收尾不改期望。

**完成判据:** 策略单点、对外步骤少，必要能力保留；无法证明的结果仍明确 unavailable/pending。

### Task 10：本地化、布局与小型平台冗余收敛

**Files:** App `Localization/{AppLocalization,AppStrings,JourneyGroupStrings,JourneyShareStrings}.swift`、`Workspace/RailWorkspaceView.swift`、`Design/` 对应 chrome、`Map/{MapProjectedRailScene,MapRailHomography,NetworkLOD}.swift`、`Diagnostics/`、Subscription auth、Settings；对应真实消费者。

**Interfaces:** 既有 `AppLocalization.text` 是统一文案查找；group/share key 加命名空间，调用方直接使用，删除过渡 wrapper。布局共享内容、保留布局参数；原型路径明确属于 DEBUG Diagnostics。

- [x] group 字典移为静态表并与 share 字符串归入已有 AppStrings 查找；迁移调用，保留四语言文本、参数和键隔离，删除相同参数的 convenience 转发。
- [x] 相同地图/chrome/播放控件内容只定义一次，三种布局只决定位置；不改 portrait、panel、safe area、basemap dimming。不同的 ridesDigest 先比消费依赖，哈希字段不同就不合并。
- [x] 把仅 DEBUG 的 projected rail 原型归 Diagnostics，并更新实际 target 引用；相同 datum 规则调用生产 AppleMapDatum，诊断仍可测量它，不能使探针失去独立观测意义。
- [x] 对无测试/无其他实现的 loader closure、credential storage protocol、LOD generic seam 逐项内联到现有 owner；保留确实需要模拟延迟/排序/平台生命周期的 seam，不新设替代 protocol。
- [ ] 目标引用/文案检查；只有布局/隔离代码改变才做一次增量 native compile 和一个受影响设备/布局检查。更新当前 API/功能文档中的已删项与北美过期描述；北美拒绝检查保留，禁止变成接受未知地区。 未做 iPad 截图，也没有新的设备布局检查。已删类型的 API 文档更正记在 Task 14。

**完成判据:** 查表不每次建字典；同义 wrapper 和无职责 seam 消失；真实布局和诊断能力保留。

### Task 11：合并编辑流程的共同实现与站点搜索

**Files:** App `JourneyEditor/{NewTripView,RideEditorView,TripStationSearchView,StationPickerView,StationPickerSearchController,StopEditorView,EditorPackageCache}.swift`、工作区呈现、JourneyMenuView；Core `Editor/EditorCatalog.swift`、`Stations/StationIndex.swift`。

**Interfaces:** 新建/编辑复用同一草稿验证、服务选择、package 获取和 Task 5 提交；一个实际 station-search implementation 接收 region/date/当前或退役 eligibility，返回 station identity，不依靠名称合并结果。

- [x] 保留 guided create 的起终点/日期/候选路线交互，先迁移共同的草稿操作、时刻表应用和提交；如果迁完后 `RideEditorView(isNew:)` 再无真实入口，删除该模式，避免强行把 NewTripView 换成完整编辑页。
- [x] 搜索索引和排序集中到已有 catalog/search owner；两个 picker 只做展示与选择。退役站 eligibility 是真实日期规则，搜索共用后仍显式过滤。
- [x] 清掉重复的错误 sheet 和重复 package load（工作区未达的 `WorkspaceSheet.newJourney/.edit` 已在 T1 删除；package 共享依赖 T6 对 `EditorRoutePackageCache` 的处理）；取消搜索/切地区后的结果不得进入新草稿。
- [ ] 用 EditorCatalogTests、TransferGuideRetiredStationTests 等相关语义面，加一个实际新建和一个编辑已有行程的 UI 检查；不跑所有表单状态矩阵。 未做点击自动化。Task 11 的新建/编辑 UI 只有截图。

**完成判据:** 一个站点查询实现和一个保存实现，两种真实用户任务保持各自入口；不再有两套字段规则。

### Task 12：在真实 owner 内消除静默伪成功与重复 scope

**Files:** App `Infrastructure/Network/{EdgeIndexCache,StationReadingsStore,RailNetworkStore}.swift`、`Statistics/{PassportStatistics,MileageStatisticsStore}.swift`、`Sharing/{ShareComposerModel,ShareComposerView,ShareCardRendering}.swift`；Core `Data/{DatasetManifestIndex,DisplayChunkReader}.swift`；Application `Routing/TripRouteValidation.swift`。

**Interfaces:** 各 owner 复用/补足自己的真实失败结果；不统一加 loaded/degraded/failed 通用框架。分享统计按完整 scope identity 共享一次计算结果，卡片只持布局与 scope。

- [x] 资料读取失败不缓存为空表，历史载入失败不冒充今日；缺少统计 denominator 不发布貌似完整 coverage。缺资源与合法空资料分别处理，已有状态足够就复用。
- [x] Passport 的 positional zip 在入口确认数量/身份；不相符则明确不可计算，不把截短结果发布。TripRouteValidation 保持“记录可存、证明为空”，必要时增加现有结果中的 failure reason，不把 retainedIDs 等同已证明。
- [x] 分享必须等明确 frame/readiness，删除硬塞 600×600（`ShareCardRendering.swift:202`）和跳卡导出的伪成功；按相同地区/日期/分组/资料/行程代次复用统计计算，不为每张卡建完整 store，也不跨不同 scope 错误复用。
- [x] 将 loadKey/readiness/export 对 scope 的重复遍历收回同一次现有准备结果；网络发布只在实际常驻内容改变时发布，保留稳定 region/blob 顺序和 contentID。若确有全表发布瓶颈，再改成按已加载条目组装；不预建另一份全量映射。
- [x] `DisplayChunkReader.subdata` 不单独为“零拷贝”造格式/unsafe decoder；只在同一数据布局改动且有可用解码方式时处理。无观测瓶颈就保持当前 slice。
- [x] 用 ShareComposerScope/LayoutTests、TripRouteValidationTests、Passport 相关现有断言及一个 damaged resource 个案验证实际失败与恢复；失败后不自动循环重试。

**完成判据:** 不完整输出有可见原因，不被当成完整成功；scope 只计算一次且依赖完整，未创建另一套万能快照。

### Task 13：时刻表 normalizer 改为共享算法与显式资料 profile

**Files:** `ios/tools/reviewed_timetable_staging.py`、仍在用的 `normalize-*.py`、`ios/tools/tests/{test_reviewed_timetable_staging,test_reviewed_timetable_staging_additional,test_normalizer_rejection_preservation}.py`；必要时新增 `ios/tools/normalize-reviewed-timetable.py` 和放在资料源旁的声明式 profile。

**Interfaces:** 一个命令明确选择 profile；共享 station lookup/ID collision/write 逻辑，profile 保存日期、来源、预期停站/时刻、座席/编组、alias/forced-code 等已审阅约束。默认不写资料，只有显式选中的 staging 操作才写目标文件。

- [x] 从仍有真实维护入口的两个同族脚本试迁移，不全量重新运行历史脚本。盘点调用与来源证据后再决定历史脚本保留/删除范围。
- [x] 复用已有 staging helper，一次 invocation 载入所需 Japan station directory；profile 不包含任意执行代码，不把特殊证据约束悄悄变宽。
- [x] 在临时输出目录对选定两例对比生成记录语义，并修改一项 source-pinned 字段确认拒绝；复用现有 rejection tests，不动正式 timetable/railway 产物。
- [x] 只迁移通过同等约束与等价输出的同族脚本；不同来源 grammar 是实际 adapter，可保留内部独立解析。更新维护入口后再删除对应脚本，停用批量历史兼容转发。

**完成判据:** 已迁移族只有一个执行实现，资料差异清楚可审；不宣称所有 normalizer 已同构，不生成全国新数据库。

### Task 14：最后裁定 module 归属，更新文档并收尾

**Files:** `ios/RailKit/Package.swift`、当前剩余 RailApplication/RailPresentation files、对应 tests；`ios/RailMap.xcodeproj/project.pbxproj`、auxiliary package/product 引用、`ios/source-ownership.json`、`docs/reference/api-reference.md`、现行 ADR 与功能映射。

**Interfaces:** 不新增业务 interface，仅收回可见性与真实归属。RideLedger/RegionClock/JourneyClock 若全为 domain 规则，移动到 RailCore 保持调用语义；本地化/界面呈现继续 Presentation/App。

- [x] 在上述行为收敛后，对剩余 RailApplication 六个用例逐个做 deletion test；将真正同 owner 的策略并回 Core 或调用方，真实候选生成/事务编排仍需独立测试面则保留。禁止为了删 target 让 SwiftUI 重新拥有业务规则。
- [x] 仅当 target 为空且依赖图更简单时删 RailApplication product/target，迁移 tests 与所有产品引用；否则明确记录保留原因。整体 package 删改需更新 ADR，不把它作为 Task 1 的机械清理。
- [x] 复核地图决策参数袋和 RouteNetwork 多文件：只有重复决策/公开内部类型才收敛；文件数与 bool 数不单独作为移动理由。删除纯转发后保留已经有 leverage 的 MapUpdatePlan/MapRebuildPolicy 测试规则。
- [x] 修正 `ios/VERIFICATION.md` 的自相矛盾：`:3` 说 verify.sh 已删除，`:82`/`:84` 仍描述退役的 umbrella，但 `:15–20` 和现存的 `ios/verify.sh`（按模块分派到 `ios/tools/verification/*.sh`）是现行轻量入口。修正旧 API 文档无源码定义的 AppleMapsJourney/AppleMapsLink，更新功能→interface→implementation 和删除记录；在已有 `ios/refactor-parallel/architecture-coverage.md` 写本批结果与仍待处理项。
- [x] 用当前依赖图选择一次 package 编译/受影响 focused tests，App target 引用变更时做一次增量 native compile；只编译实际受影响辅助产品，不补全套产品矩阵。

**完成判据:** 无新的 A→B→C 转发链；文档与实际源码一致，所有行为收益与未测性能界限有记录。

## 验证与执行规则

本次制定计划只读源码和测试入口，**没有执行以下测试/构建**。执行时先复核当前 diff 和测试函数输入，按具体不确定性选择一项，不把列表整体当自动流水线。

```sh
# 示例：只在 Task 2 确需执行日期行为时
bash ios/verify.sh swift --filter DatesParityTests --jobs 2

# 示例：只在 Task 8 改了日期/物理证据匹配时
bash ios/verify.sh swift --filter TimetablePhysicalRouteMatchTests --jobs 2

# 原生产品：复用已有 DerivedData，执行前协调 heavy slot
xcodebuild -project ios/RailMap.xcodeproj -scheme RailMap \
  -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /private/tmp/jtm-architecture-incremental \
  CODE_SIGNING_ALLOWED=NO -jobs 2 build
```

最后命令的 DerivedData 示例必须换成当前可复用的目录；没有相关 source 变化就复用既有证据，不从空目录开始建立新 baseline。`ios/verify.sh` 是 2026-10-10 之后保留的 opt-in 分派脚本（`swift` 模块运行 `swift test --package-path ios/RailKit --filter`），上面的 swift 示例有效；它没有 native 模块。

测试所属：RailCoreTests 包括 Dates/TrainValidation/ServicePattern/TrainTimetableDatabase/TimetableServiceDay/TimetablePhysicalRouteMatch/RecordedRouteAdmission/LocalJourneySearch/EditorCatalog/TransferGuideRetiredStation/RideLedger；RailPresentationTests 包括 StatisticsMembership；RailApplicationTests 包括 ImportPreflight/RideDraftValidation/TripRouteValidation。`NativeImportPersistenceTests` 和 `ShareComposerLayoutTests`/`ShareComposerScopeTests`（`ios/RailMapTests/ShareComposerLayoutTests.swift`）属于 Xcode `RailMapTests`，不能用 RailKit 的 swift filter 冒充执行。上面的 xcodebuild 示例只是 `RailMap` scheme 的 `build`。`RailMap` scheme 的 TestAction 只有 `RailMapUITests`，不包含 `RailMapTests`。原生个案要用 `xcodebuild test -scheme RailMapTests ... -only-testing:RailMapTests/<Suite>/<case>`。用 `RailMap` scheme 跑 `-only-testing:RailMapTests/...` 选不中测试，记为未验证。filter 选中 0 个测试不算通过。

有新行为或修复时，先补/强化真实 interface 的回归用例，运行确认失败的具体原因，再实现并运行同一用例；只删无调用死码、同义 enum、注释和机械移动不新建镜像测试。编译不能证明像素、物理地理、泄漏或性能。选定一条实际问题路径的测量足够后即停止，不扩大为全矩阵。

每批完成记录四项：删除了什么；谁现在拥有规则/数据；最小验证实际结果；仍未证明什么。没有代码提交或发布步骤。

## 暂不纳入本轮执行

- 不以一次大重写同时完成所有 14 项，不为“最终两层”先移动整个代码树。
- 不新增全行程派生快照体系、全局错误状态框架、永久五地区 Dataset、零拷贝私有解码器或自动监控。
- 不因导入预检与提交都校验就删预检；不因截图和 JSON 都生成 Train 就删 Vision；不因有多种分享画幅就删已有用户能力。
- 前一份梳理中的 Web 几何双写/按需导出仍成立，但本次六路审查针对 iOS；Web 的这两项应作为独立小改动执行，不和原生数据 owner 同时重构。

## 计划编制证据

已读取当前六路报告并复核：死 Swift 算法/fixture 关系、完整解码入口、header-only 合同、日期投影、校验 JSON 回环、导入实际路径、时刻表 picker 失败提示、TripRouteValidation 的 pending 语义、normalizer 已有共享 helper。一个 GPT-6.1 Sol 有界只读复核聚焦包读取与显示链约束；没有再启动六路全库扫描，也没有把他人的已核实标记直接当本次执行结果。

### 审计修订（2026-10-15）

本计划经三路只读源码核对（Grok 4.7）后修订，上文各 Task 已就地更正。主要更正：

- T1：`clearInferredPending` 本身就是 no-op，死分支在 `ItineraryStore.swift:558–560`，计划原先写的 “changed==0 修复分支” 并不存在；`RideEditorAI.denial` 有生产调用，应内联而不是删除；明确了 retained page 和未达 WorkspaceSheet case 的具体符号。
- T5：`importJSON` 经 helper 被约 11 个测试依赖，不是两个。
- T6：漏了第三处完整解码 `EditorRoutePackageCache`；EditorCatalog 只读 StationDirectory，不应被迫完整解码；EdgeIndex 不自行 parse。
- T7：拼接只有一个函数，问题在于没有缓存结果；source reproof 在调用方，不在 `canonicalizeRouteFeature` 中。
- T8：补全 picker 在 nil 数据库时的真实行为，以及 `TrainServicePatterns` 的 `fatalError`。
- T9：`.network` case 不可达。
- 验证：`ios/verify.sh` 仍以轻量形式存在，`VERIFICATION.md` 内部矛盾归入 T14；native 测试需要 `xcodebuild test -only-testing`。

已核实无误、未改动的结论：OverlapLanes/StationJoinSmoothing 仅互相引用；draft/hero 类型仅测试使用；LoadedPackage、RailResourceRevisions、geometryIsNotRequired、compactLine 字段与消费者；TripRouteValidation 失败时 `physicallyResolvedIDs` 为空；校验的 JSON 回环（`RideDraftValidation.swift:252–256`、`ImportPreflight.swift:238–240`）；`EditorValidation.swift` 中重复的 Field/Severity；RailApplication 共 6 个文件；356 个 normalizer；所有引用的测试名与路径都存在。

计划的首批建议为 T1（死代码）→ T2（同义行程模型）→ T3（校验）；包读取与显示链分别在 T6/T7 交付。任务顺序可以按当前修改冲突调整，但不能跨过各自证据/资料迁移前置条件。
