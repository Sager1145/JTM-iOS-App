# 功能接口与架构审查（2026-10-15）

> **已过时（2026-10-15 22:40）**：本文多数条目已经修复或被重新裁定，当前结论见 [docs/reports/integration/function-interface-architecture-2026-10-15.md](../../../docs/reports/integration/function-interface-architecture-2026-10-15.md) 的“第三轮”一节。保留本文作为历史记录。

范围：`ios/RailKit`（RailCore / RailPresentation / RailApplication）、`ios/RailMap` 全部功能目录、`ios/auxiliary`、`ios/tools`。只读审查，没有修改代码。
方法：六路并行只读审查（Codex 三路、Grok 三路），按“一个功能 = 一个接口 = 一个实现”和深模块原则逐片评估；关键结论由主审抽查源码确认（标 ✅）。行号对应 2026-10-15 的工作副本。

判断标准：

- **深模块**：接口小、背后行为多。删除测试：删掉它，复杂度是消失（说明它只是转发）还是散回 N 个调用方（说明它在挣钱）。
- **一个适配器 = 假想接缝**：只有一个实现、也没有测试替身的 protocol/注入点，不应存在。
- **不做兜底**：静默 fallback、legacy 别名、兼容垫片和已退役功能的残留，都会让错误伪装成成功。
- **A+B 能解决就不拆 ABCD**：为行数切出来的 Stage/Builder/Context 是臭抽象。

---

## 一、总体诊断（先读这一节）

问题的根源不是文件太长，而是**同一份数据有多个所有者、同一个功能有多条管线**。最近的 `refactor(railkit): separate … stages` 系列提交和 333 文件的源码拆分，按行数切文件，没有合并重复管线。结果是接口变多，数据搬运没有减少。下面五个结构性问题，解释了后面列出的大部分臭味。

### 1. 铁路包数据没有唯一所有者：同一文件被解析 2–3 次

| 读取 | 位置 | 产物 |
|---|---|---|
| `CompactPackage.Headers.load` | `RailNetworkStore.swift:1539` | 徽章／线路头信息 |
| `DisplayParts.LoadedPackage.load` | `RailNetworkStore.swift:1565` | 显示 parts + 种子 |
| `DisplayParts.LoadedPackage.load` ✅ | `DisplayNetworkCache.swift:119` | 求解用 `RouteNetwork`（即使拿到种子也会重新 parse 一次，种子只能省掉 parts 布局） |
| `RailIntervalCodes.intervals` → `decodeIntervals` | `DisplayNetworkCache.swift:130`、`RailIntervalCodes.swift:27` | 区间坐标（`decodeDisplayIntervals` 已经解码过一遍） |
| `rail-sections*.json` | `EdgeIndexCache.swift:242` | 统计 EdgeIndex，再把显示 parts 追加进去（`:298-360`） |
| 显示 chunk blob（第二份 JSON 几何） | `DisplayChunkReader.swift:33` `subdata` + JSON decode | 地图 `DrawnLine` |

源码注释给出的代价：日本包 parse 约 280 ms，几何约 1.7 s（`RailNetworkStore.swift:400-402`）；路线布局约 1.5 s（`:1598-1600`）。此外，`RouteNetwork.Line` 同时持有 `parts`、`intervals` 和完整的 `compactLine`（`RouteNetwork.swift:162-164`），常驻内存里有三份测量坐标。

**目标形态**：每个地区由一个 `RegionDataset` 负责，只解码一次，一次产出 `{headers, displayParts, routeNetwork, intervalCodes, edgeIndex 增量}`。地图、求解和统计都只拿引用。`DisplayNetworkCache` 和 `EdgeIndexCache` 不再自己打开文件。

### 2. 行程模型被投影成一串几乎同构的结构

`Train` 会被转成下面这些结构：

- `Dates.Train/Stop`：`TrainDateBridge.swift:17-24`、`StatisticsMembership.swift:45-49`、`LaunchJourneySelector.swift:59-67`、`WorkspaceJourneyRules.swift:166-174`
- `Statistics.Train/Stop`：`Statistics.swift:1822-1851`、`RideLedger.swift:90-99`、`PassportStatistics.swift:177-218`、`MapRideMarkers.swift:206`、`PlaybackController.swift:339`
- `MileageMatching.Journey`：`MileageStatisticsStore.swift:721-750`
- `TrainContext` 和 `CacheKeyTrain`：`RideRouteResolution.swift:192-197, 542-551`；`RouteGraph.RouteSection` 在 `RouteResolutionMemo.swift:70-94` 中每次调用都会重建

编辑校验则把 `Train` 编码成 JSON、转成字符串、再解析成动态 JSON，交给 `TrainValidation`（`RideDraftValidation.swift:250-256`、`ImportPreflight.swift:232-240`）。

`RideLedger` 有 15 个调用文件，处在渲染和过滤路径上；每次重新计算 scope，都要做 O(行程 × 停站) 的分配。

**目标形态**：日期、统计和账本函数直接接受 `RailCore.Train/Stop`。需要派生字段时，每个行程按 revision 缓存**一个**快照（日期、乘车站标记、时刻、路线段），由持久化层产出，所有下游共用。`TrainValidation` 直接校验类型化值，并返回结构化诊断（path、reason），JSON 只留在外部导入这一处接缝。

### 3. 一段连续乘车会构造三条折线，显示链还要拼接三次

1. N02 求解坐标（`RideRouteResolution.swift:339`），统计使用，必须保留。
2. 紧凑包切片（`canonicalizeRouteFeature`，`:375-381`）。连续线路上 `drawnCoordinates`（`RailMapCoordinator.swift:3055`）最后会改用显示链，这一条白算了；`StrokeRide.swift:10-24` 的注释也说它是错误的像素几何。
3. 显示链切片。同一条链在一次 prepare 中被拼接三次：`JunctionCandidateIndex.init`（`MapLineGeometry.swift:261-266`）、`prepareStrokeReferences`（`RailMapCoordinator.swift:2968`）、`continuousChainPixels`（`:224`）。

另外，`precomputedDisplayParts` 对每条预计算行程都会再做一次 canonicalize 和最近点切片（`PrecomputedRouteDisplay.swift:21-52`）。

**目标形态**：`DrawnSegment` 只保留 `sourceCoordinates`（统计用）和显示链引用（链 id + 区间）。显示链的 WGS84 拼接结果存在 `DrawnLine` 上（按 contentID），junction 索引、stroke 索引和像素缓存都从这一份派生。

### 4. 时刻表有三套目录，求解器还会重复查询

- 浏览／搜索：`ServicePatternBrowsePolicy.makeSearchSnapshot` 把 legacy `TrainServicePatterns.search`、SQLite `TrainTimetableDatabase` 和 `LineServiceCatalog` 的结果合并起来（`ServicePatternBrowsePolicy.swift:103-163`）。
- 数据库打不开时，`TrainTimetableDatabase.bundled` 用 `try?` 返回 nil（`:665-670`），浏览会静默退回 legacy 结果。
- 编辑器已经把 `Trip.physicalRouteSections` 应用到草稿上了。求解器的 `TimetableRouteEvidence` 仍会把整个 `Train` JSON 编码作为缓存键，再查三个服务日的 SQLite，然后跑 `TimetablePhysicalRouteMatch`（`TimetableRouteEvidence.swift:44-84`）。

**目标形态**：只保留一个 `TimetableCatalog.query`，返回 occurrence、完整度和来源。legacy JSON 只作为数据迁移的输入，不作为运行时的第二实现。草稿携带 `Match`，求解器直接使用。

### 5. 分层：模块边界和真实接缝不一致

- **RailApplication 是一个编译桶，不是一个深模块**：里面是六个互不相关的静态 namespace，各自基本只有一个生产调用方（`MileageMatching`、`TripRouteValidation`、`RouteRepairSession`、`ImportStaging`、`ImportPreflight`、`RideDraftValidation`），主要工作是包装 Core 值。建议解散，各自并入它编排的 Core 能力或直接调用方。
- **RailPresentation 混入了领域规则**：`RideLedger`（乘车状态语义）和 `RegionClock`/`JourneyClock`（地区时间语义）应属于 RailCore。
- **App 层的耦合集中在四个巨型 owner**：`RailMapCoordinator.swift` 4189 行、`RailWorkspaceView.swift` 3607 行、`RiddenRouteStore.swift` 2472 行、`RideEditorView.swift` 2437 行。问题不在行数，在于它们内部藏着重复管线（见下文）。全局单例 `RideStatusCenter.shared`（`RideRouteStatus.swift:17-30`）是“依赖没有传下去”时留下的过渡结构，`RideDetailContent` 会静默回退到它（`RideDetailView.swift:197-203`）。

**结论**：保留 RailCore（领域 + 数据）和 RailPresentation（无 UI 框架的展示规则）两层，RailApplication 解散。之后不再做按行数拆文件的重构，重构预算全部用于合并上面四条重复管线。

---

## 二、功能 → 接口 → 实现总表

“一个实现”的行表示形态健康；⚠ 表示同一功能有多个实现或接口，详见第三节。

### 数据与网络

| 功能 | 接口 | 实现 | 状态 |
|---|---|---|---|
| 显示网络读取 | `RailDisplayNetwork.manifest/blob/chunk/lines/popup` | `Infrastructure/Network/RailDisplayNetwork.swift:9-264`，格式 `RailDisplayNetworkFormats.swift` | ⚠ 与紧凑包几何重复（一-1） |
| 运行时网络状态 | `RailNetworkStore.loadAll/ensure/linePreview/stations(in:)` | `RailNetworkStore.swift:27` | ⚠ 三个 `DrawnLine` 构造路径（`:1389-1478`、`:1604-1725`、`:1179-1239`）；每批 chunk 都全量重建数组（`:1061-1102`） |
| 求解网络 | `DisplayNetworkCache.network(scope:/country:)` | `DisplayNetworkCache.swift:21` | ⚠ 第二次解码包 |
| 统计边索引 | `EdgeIndexCache.index/merged/scoped` | `EdgeIndexCache.swift:6` | ⚠ 第三份网络；显示增强失败时 `try?` 静默降级（`:48-56`） |
| 包文件 | `CompactPackage`、`DisplayParts.LoadedPackage.load` | `RailCore/Data/CompactPackage.swift:14`、`Rendering/DisplayParts.swift:316` | ⚠ 解码重复 |
| 历史叠加 | `RailHistoryOverlay.load`、`RailHistory.apply`、`RailHistoryStations.directory` | `RailCore/History/RailHistory.swift:223,456`、`RailHistoryStations.swift:44` | 可以；`directory` 每次调用都重建，应缓存 |
| 资源版本门 | `RailResourceRevisions`、`RailPrecomputedRouteGate` | `RailResourceRevisions.swift:20`、`RailHistory.swift:47` | ⚠ 接受三种区间拼写和无证明的 part（兜底） |

### 路由

| 功能 | 接口 | 实现 | 状态 |
|---|---|---|---|
| 已记录行程 → 物理路线 | `RideRouteResolution.resolve` | `RailCore/Routing/RideRouteResolution.swift:172` | 正确的唯一入口 |
| 图与 Dijkstra | `RouteGraph`、`RouteSolver` | `RouteGraph.swift:39`、`RouteSolver.swift:9` | 深；但 `dijkstra/solveSection` 等内核步骤只有测试在用，却是 public |
| 显示规范化 | `RouteNetwork.canonicalizeRouteFeature` | `RouteNetwork.swift:801` + 三个 extension 文件 | 一个类型分在四个文件 |
| 紧凑包路线提案 | `LocalJourneySearch.search`、`RailwayRouteChoices.choices`、`RecordedRouteAdmission`、`TokyoConventionalRouteInference`、`RailwayRouteInference`、`RouteRepair`、`RouteRepairFlow`、`TripRoutePlanner` | `Routing/*.swift` | ⚠ 一件事拆成 8 个类型（见三-OVER-SPLIT） |
| 求解缓存／限流 | `RouteResolutionMemo`、`RouteSolveLimiter`、`SharedRouteWork` | `Routing/*.swift` | 三者职责不同，可以保留 |
| App 侧行程路线 | `RiddenRouteStore.load/resolve/clear` | `Infrastructure/Persistence/RiddenRouteStore.swift:15` | ⚠ 第二遍 legacy 求解（`:770-800`，冷启动约 1.8 s 的索引） |

### 渲染与地图

| 功能 | 接口 | 实现 | 状态 |
|---|---|---|---|
| 屏幕空间描边 | `ContinuousStroke.buildStroke/slice/laneProfile` | `RailCore/Rendering/ContinuousStroke.swift` | 唯一的生产车道模型 |
| 重叠车道（web 移植） | `OverlapLanes`、`StationJoinSmoothing` | `Rendering/OverlapLanes.swift`（3487 行）、`StationJoinSmoothing.swift`（1215 行） | ✅ **零生产调用方**，只有 parity 测试 |
| 帧几何 | `MapLineGeometry.prepare/materialize` | `RailMap/Map/MapLineGeometry.swift:672-882` | ⚠ 6 个几何 struct；链被拼接三次 |
| 几何缓存／覆盖安装 | `MapNetworkGeometryCache`、`MapOverlayInstaller`、`MapOverlayStyles` | `MapNetworkRendering.swift:90-258`、`MapOverlayStyles.swift:22` | 可以 |
| LOD | `NetworkLOD.select/fitToBudget`、`LaneLOD.resolve`、`Visibility`、`StationVisibility`、`RideMarkerVisibility` | 分散在 RailCore/Map | `LODLine/LODBuild` 是假想接缝 |
| 地图更新决策 | `MapDrawChanges.plan`（14 个 bool）、`MapRebuildPolicy`（12 个标量） | `RailPresentation/Map/MapUpdatePlan.swift:13-61`、`MapRebuildPolicy.swift:23-62` | ⚠ 两个参数袋服务同一个调用点，应合成一个决策函数 |
| 标签／碰撞／标注 | `MapStationLabelCoordinator`、`MapLabelCollisionGrid`、`MapAnnotationReconciler` | `RailMap/Map/*.swift` | 唯一调用方是 coordinator 中内联的标记循环（`RailMapCoordinator.swift:1895-2818`） |
| 相机 | `RailMapController` + `MapCameraPolicy` | `RailMapController.swift:21` | 可以 |
| 原型绘制栈 | `MapProjectedRailScene`、`MapRailHomography` | `RailMap/Map/*.swift`，生产 coordinator 里有 `#if DEBUG` 分支（`:1148-1155`） | ⚠ 应移到 Diagnostics |

### 行程、编辑、导入

| 功能 | 接口 | 实现 | 状态 |
|---|---|---|---|
| 行程仓库 | `ItineraryStore` | `RailMap/Journeys/ItineraryStore.swift:19` | ⚠ 修改+保存有三种风格（见三） |
| 修改命令 | `JourneyEditing.add/replace/delete/…` | `JourneyEditor/JourneyEditing.swift:9` | ⚠ 只是给 store 加上 save 的包装 |
| 新建行程 | `NewTripView` | `JourneyEditor/NewTripView.swift`（1234 行） | ⚠ 与 `RideEditorView(isNew:)` 重复 |
| 编辑行程 | `RideEditorView` | `JourneyEditor/RideEditorView.swift`（2437 行） | ⚠ |
| 草稿校验 | `RideDraftValidation.issues` → app 中的 `EditorValidation` | `RailApplication/Editor/RideDraftValidation.swift`、`RailMap/JourneyEditor/EditorValidation.swift` | ⚠ 规则与 `TrainValidation` 重复；app 又定义了一套 `Field/Severity` |
| 站点搜索 | `StationPickerSearchController`、`TripStationSearchView` 内置索引、`StopEditorView` 退役站搜索 | 三处 | ⚠ 三个实现 |
| 路线状态 | `RideStatusCenter`、`RouteStatusResolver`、`JourneyBridge.routeState` | `Journeys/RideRouteStatus.swift:37`、`RailPresentation/Journeys/RouteStatusResolver.swift` | ⚠ 全局单例 + 静默回退 |
| JSON 导入 | `ImportFlow.load/check/commit` → `ImportPreflight`/`ImportStaging` → `ImportEngine.Session` | `RailMap/Import/ImportFlow.swift:92` 等 | 链路深，但 preflight 内有 JSON 往返 |
| 截图导入 | `TransferGuideImport` + `TransferGuide.parse/build` | `Import/TransferGuideImport.swift:24`、`RailCore/Import/TransferGuide.swift` | 可以；保存风格与其他路径不同 |
| AI 补全 | `JourneyCompletion`、`JourneyCompletionView` | `RailCore/Import/JourneyCompletion.swift`、`JourneyEditor/JourneyCompletionView.swift` | `RideEditorAI.denial` 是纯转发 |
| 持久化 | `RideLibrary`（门面）→ `RideStorage` → `MergedStore` | `Infrastructure/Persistence/*.swift` | `save` 只是包装 `saveResult`；`migrateLegacyStores` 每次启动都会跑 |

### 时刻表

| 功能 | 接口 | 实现 | 状态 |
|---|---|---|---|
| 时刻表数据库 | `TrainTimetableDatabase` | `RailCore/Timetable/TrainTimetableDatabase.swift` | ⚠ 失败时 `try?` 返回 nil |
| legacy 服务模式 | `TrainServicePatterns.search/apply` | `TrainServicePatterns.swift` | ⚠ 第二目录 |
| 线路服务摘录 | `LineServiceCatalog` | `LineServiceCatalog.swift` | ⚠ 第三目录 |
| 快速匹配 | `TimetableQuickMatchController` + `TimetableTripMatch.candidates` | `RailMap/Timetable/*.swift` | 注入的 `Lookup/Debounce` 是假想接缝 |
| 物理路线证明 | `TimetablePhysicalRouteMatch.resolve` ← `TimetableRouteEvidence.enrich` | RailCore + `Infrastructure/Persistence` | ⚠ 重复查询 |
| 直通运行 | `JapanThroughServices`、`TripConnectivity` | `Timetable/JapanThroughServices.swift`、`Routing/TripConnectivity.swift` | ⚠ `Link.network` 从不会被返回；`allows` 只放行 sameLine，planner 和编辑器的规则不一致 |

### 统计与分享

| 功能 | 接口 | 实现 | 状态 |
|---|---|---|---|
| 统计引擎 | `Statistics` | `RailCore/Statistics/Statistics.swift`（2324 行） | ⚠ 自带一套平行的 Train/Stop；未知国家都按日本处理（`:323-330`） |
| 里程 store | `MileageStatisticsStore` → `MileageMatching.match` | `RailMap/Statistics/MileageStatisticsStore.swift:48` | ⚠ 多层投影 |
| 护照聚合 | `PassportStatistics.build` | `Statistics/PassportStatistics.swift:34` | ⚠ `zip` 静默截断不等长输入 |
| 统计 UI | `StatisticsDashboardContent`（带 ticketOnly/widgetOnlyKind 等模式开关） | `StatisticsDashboardContent.swift:8-57` | ⚠ 一个视图承担多种模式 |
| 分享编排 | `ShareComposerModel` + `ShareCanvasGeometry` + `ShareDragPlanner` + `ShareCardRenderController` + 1153 行的 View | `RailMap/Sharing/*.swift` | ⚠ 拆分过度；每张卡片一个完整的统计 store |
| 行程海报 | `JourneyPoster.blocks` | `Sharing/JourneyShareImage.swift:28-188` | ⚠ 与详情页的格式化重复 |

### 横切

| 功能 | 接口 | 实现 | 状态 |
|---|---|---|---|
| 本地化 | `AppLocalization.text` / `AppStrings.table` | `RailMap/Localization/AppStrings.swift` | ⚠ 还有 `journeyShareText`、`groupText` 两套独立查表；✅ `groupText` 每次调用都会重建整个字典（`JourneyGroupStrings.swift:4-14`） |
| 地区 | `Region`、`RouteScope`、`RegionToday` | `Infrastructure/Network/RegionCatalog.swift:52` | 可以 |
| 站点地点 | `StationPlaceStore.place(for:)` | `StationPlaceStore.swift:30` | MapKit 坐标适配与 `AppleMapDatumProbe` 重复 |
| 订阅 | `ChatGPTSubscriptionAuth/Service` | `Infrastructure/Subscription/*.swift` | `CredentialStoring` protocol 只有一个实现 |
| 播放 | `PlaybackController` + `MapPlaybackLayer` + `Playback`（Core） | `RailMap/Playback`、`RailCore/Rendering/Playback.swift` | 可以；`PlaybackMapRendering` 带重建门控，暂时保留 |
| 工作区外壳 | `RailWorkspaceView` 中的三种布局 | `RailWorkspaceView.swift:221-230` | ⚠ 地图、播放条、控件这一套栈写了三遍（`ResidentMapChrome`、`wideMapSurface`、`hingedCardLayout`） |

---

## 三、臭味清单（按类型）

### DUPLICATE：同一功能多个实现

1. **两套新建／编辑行程编辑器**：`NewTripView` 与 `RideEditorView(isNew:)`，两边都各自加载路线包、接入时刻表。工作区里的 `WorkspaceSheet.newJourney/.edit`（`WorkspaceSheetContent.swift:7-8,127-139`）没有任何赋值点；`JourneyMenuView.swift:64-80` 又自己弹出一个编辑器和失败提示。→ 只留一个草稿编辑器，用 create/edit 配置区分。
2. **三种修改+持久化风格**：`JourneyEditing`（修改+保存）、`ItineraryStore.merge/replaceAll`（内部保存）、`TransferGuideImport`（多次 add 后保存一次）、`ImportFlow`（commit 后在外部保存）。→ 一个原子的仓库命令接口，结果里包含持久化结果和回滚。
3. **两个路线重建接口**：`rebuildRouteSections` 丢掉了 `rebuildRoute` 的 solving 结果（`ItineraryStore.swift:242-269`），`JourneyEditing.swift:135-139` 又包了一层。
4. **三个时刻表目录**（一-4）。
5. **三个站点搜索实现**（二-行程表）。
6. **三套本地化查表**（二-横切）。
7. **两个 `ridesDigest`**：哈希内容不同（`RailMapCoordinator.swift:3149` 与 `WorkspaceDerived.swift:195`）。
8. **两种车道模型**：✅ `OverlapLanes` + `StationJoinSmoothing` 共 4702 行，没有生产调用。
9. **工作区 chrome 写了三遍**。
10. **海报格式化与详情格式化重复**。
11. **校验规则重复**：`RideDraftValidation` 重述 schema 规则后又调用 `TrainValidation`；app 层又定义了一遍 `Field/Severity/Issue` 并做穷举映射。
12. **356 个 `ios/tools/normalize-*.py`**：同一个工作流复制成 356 份，每份都重新扫描 `jp-2025.json`。→ 一个 normalizer 加声明式 profile，一次运行处理所有 profile。

### HYPOTHETICAL SEAM：只有一个实现

- `LODLine`/`LODBuild`（`NetworkLOD.swift:160-172`），没有测试替身。
- `StationRouteResolver`（`Stations.swift:10`）只有测试替身；生产路径不经过它。
- `MapSelectedStationSnapshotController.Loader`、`TimetableQuickMatchController.Lookup/Debounce`、`StationPickerSearchController.Search/Debounce`：注入点都没有任何测试使用。
- `ChatGPTSubscriptionCredentialStoring`：一个私有 keychain 实现。
- `EditorCatalogBuilder` 的 `operatorRedirects`：只有测试会传入。

### SHALLOW / PASS-THROUGH：删除测试后什么都不会丢

- `RailwayRouteInference.search/choice` 原样转发给 `RecordedRouteAdmission`（✅ 唯一生产调用方是 `RideEditorView`）。
- `RouteConfirmationRepair.clearInferredPending` 直接返回 `(trains, 0)`（✅），却还挂在加载路径上（`ItineraryStore.swift:558`）。
- `RideEditorAI.denial`、`JourneyBranding.usesDetectedLines`（没有调用方）、`DraftMapPins.snapshot`、`RideLibrary.save`（包装 `saveResult`）。
- `AppStrings.dataText/editorText/guideText/statsText`：只是用相同参数调用 `text`。
- `LocalJourneySearch.choices`：只有测试在用。
- `WorkspacePanelActions`：只按 tab 分派父视图已经构造好的闭包；`WorkspaceTabs.title` 与 `DuoWorkspaceShell.title` 是同一个查找。

### OVER-SPLIT：一件事拆成很多块

- **紧凑包路线提案**拆成 8 个类型：`RailwayRouteChoices`、`LocalJourneySearch`、`RecordedRouteAdmission`、`TokyoConventionalRouteInference`、`RailwayRouteInference`、`RouteRepair`、`RouteRepairFlow`、`TripRoutePlanner`。`LocalJourneySearch.Result.uniqueChoice` 还会反过来调用 `RecordedRouteAdmission.outcome`，所以 admission 策略从两个类型都能进入。→ 合成一个 `PackageRouteProposal` 模块，对外只给 `propose(train/span, policy) -> Outcome`。Tokyo 推断、修复步骤和 planner 过滤都作为内部策略。
- **地图几何**：6 个 struct（`LineBuild`、`FamilyRunBuild`、`FamilyFallbackRunBuild` 和三个 `Prepared*`）。`Prepared*` 跨 actor 边界，有理由存在；family 和 fallback 应合成一种折线产物。
- **地图更新**：`MapDrawChanges` 和 `MapRebuildPolicy` 两个参数袋服务同一个调用点。
- **分享编排**：model、geometry、drag planner、render controller 四块，View 仍持有 20 多个状态。
- **RouteNetwork**：一个类型分在 4 个文件；`PrecomputedRouteDisplay` 和 `ResolvedRailRoute` 可以并回主文件。
- **RouteSolver 公开面**：内核步骤只有测试使用，却是 public。生产只需要一个入口 `RideRouteResolution`。

### FALLBACK / 兼容垫片 / 退役残留

- 静默降级：`TrainTimetableDatabase.bundled`（`try?` 后退回 legacy）、`EdgeIndexCache`（`try?` 后只用 N02）、`loadDisplayHistories`（`try?` 后退回今天）、`StationReadingsStore`（损坏的文件被当成空表缓存）、`TripRouteValidation`（解析失败被当成全部通过，`:49-72`）、`PassportStatistics`（`zip` 截断）、`ShareCardRendering`（缺失 frame 时用 600×600 顶上，导出时静默跳过）、`DatasetManifestIndex`（字段损坏时退化为全量扫描）。→ 一律返回 typed 的 loaded/degraded/failed 状态，并在诊断中显示。
- legacy 路径：`RiddenRouteStore` 的第二遍 `allowLegacy` 求解；v2 显示格式仍接受 pre-v2 的可选字段（`RailDisplayNetworkFormats.swift:384-423`）；`RailServiceValidity` 接受三种拼写；`RailPrecomputedRouteGate` 接受无证明的 part；`RideLibrary.migrateLegacyStores` 每次启动都会运行。
- **North America 残留**（AGENTS.md 规定不提供兼容）：`RiddenRouteStore.swift:1116-1135` 的 US/CA 契约注释、`Statistics.swift:111-120`、`TrainServiceBranding.swift:196` 的 `"acela"/"corridor"`、`CompactPackage.swift:322-324` 的基准注释、`validateSupportedRegions` 中对 `us-/ca-` 前缀的处理。
- 未知地区：`classifySectionMask` 把未识别的国家按日本处理（`Statistics.swift:323-330`）。
- **死代码**：
  - ✅ 已抽查：`OverlapLanes`、`StationJoinSmoothing`、`JourneyDraftSelection` + `JourneyDraftEdits`（7 个 public 类型，只有测试使用）、`JourneyHeroIdentity`、`WorkspaceRetainedPages`、`exportFrameSerial`。
  - 来自审查报告，尚未抽查：`onPreparationFailure`、`railJourneyMenuSource/Destination`、`ItineraryStore.importJSON`（只有测试使用）、`ItineraryStore.add(region:)`、`StopTimingStatus.label`、`RailDisplayNetwork.records(intersecting:in:)` 的 manifest 版本、`TripConnectivity.Link.network`、`CompactPackage.lineCode`、`Visibility.minZoomForRank`、`DisplayParts.continuousCoordinates`、`OperatorIdentity.matchingCodes/matches`、`Stations.Readings`。
- **有意保留，不要删除**：`StationCodeAliases.canonical`（这是持久化数据的语法，不是死别名）；`DisplayParts` 中空 groom 和 retrace 的分支（要等包重建后才能删）；`JSMath/JSNumber/JSString`（V8 数值一致性）；`PlaybackVideoExporter` 的 Catalyst 截图回退。

### DATA RE-TRANSPORT：数据在层间反复搬运

一-1 到一-4 已经覆盖主线，这里补充热路径上的几处：

- `publishDisplayNetwork` 每到一批 chunk，就遍历所有常驻线路和站点重建两个数组（`RailNetworkStore.swift:1061-1102`），相机移动时会反复触发。
- `DisplayChunkReader.slice` 用 `subdata` 拷贝之后再做 JSON 解码。
- `WorkspaceDerived` 只解决了一个 body 内的三次过滤（约 4.9 ms），Stats 和 Passport 还会再切一次 membership，分享界面另外分配自己的缓存。
- 分享：`loadKey`、`statisticsInputKey`、readiness 和 `loadStatistics` 各自重建 scope 集合（`ShareComposerView.swift:934-1007`），渲染时每张卡片再过滤一次。
- `ItineraryStore.regroup` 每次编辑都会两次创建 `Dates.Train`（`:789-806`）。
- `RouteResolutionMemo.solve` 每次调用都重建 `CacheKeyTrain` 和 `RouteGraph.RouteSection`。

---

## 四、行动清单（按收益/风险排序）

| # | 动作 | 收益 | 风险 |
|---|---|---|---|
| 1 | 删除已确认的死代码：OverlapLanes/StationJoinSmoothing（4.7k 行）、JourneyDraftSelection/Edits、JourneyHeroIdentity、RouteConfirmationRepair、RailwayRouteInference、WorkspaceRetainedPages、exportFrameSerial、未使用的 WorkspaceSheet 分支、NA 残留注释与标记 | 立刻减少接口面，没有行为变化 | 低。`OverlapLanes` 有 parity 测试对应 web 的 `app/public/rail-stroke.js` 系列 fixture；删除前先确认 `build-port-fixtures.mjs --check` 不依赖这两个 Swift 类型 |
| 2 | 每个地区一个 `RegionDataset`，包只解码一次；`DisplayNetworkCache` 和 `EdgeIndexCache` 不再自己打开文件；`RouteNetwork.Line` 去掉 `compactLine` 中的坐标 | 启动和首次统计省下秒级时间，常驻内存减少一到两份坐标 | 中：涉及加载顺序和并发（seed / inFlight） |
| 3 | 显示链只拼接一次并挂在 `DrawnLine` 上；连续线路不再构造紧凑包切片；预计算行程直接存显示切片 | 缩放 prepare 热路径变快，冷求解少一条折线 | 中：需要地图视觉回归 |
| 4 | 全程使用规范 `Train/Stop`：删除 `Statistics.Train/Stop` 和调用方自建的 `Dates.Train`；按行程 revision 缓存一个派生快照；`TrainValidation` 输出结构化诊断，删除 JSON 往返和 app 层的诊断类型 | 去掉 O(行程×停站) 的重复分配，消除跨层字段漂移 | 中 |
| 5 | 时刻表统一为一个 `TimetableCatalog.query`，删除 legacy 运行时路径和 `try?`；草稿携带 `Match` 给求解器 | 删掉一套目录和重复的 SQLite 查询 | 中：legacy 数据要先迁移进 DB |
| 6 | 编辑器合一（NewTripView 并入 RideEditorView），仓库命令原子化，站点搜索合一，去掉 `RideStatusCenter.shared` | App 层最大的一块重复消失 | 中高：UI 回归面大 |
| 7 | 路线提案的 8 个类型合成一个模块；`RouteSolver` 收窄为 internal | 接口面大幅缩小 | 中 |
| 8 | 解散 RailApplication；`RideLedger` 和 `RegionClock` 移入 RailCore | 分层与真实接缝一致 | 低（机械移动） |
| 9 | 所有静默降级改成 typed 状态；删除 `allowLegacy` 第二遍求解（先统计还有多少命中） | 错误不再伪装成成功 | 中 |
| 10 | 356 个 normalize 脚本改为一个命令加 profile | 工具层去重 | 低（不影响 App） |

**停止的事情**：不再做按行数拆文件或拆 Stage 的重构，不再新增 Coordinator、Builder 或 Context 中间层，不再为“以后可能有第二个实现”建 protocol。

---

## 附：证据来源

六份原始审查报告（本次会话 scratchpad，不入库）：

- core1：RailCore 中的 Routing / Rendering / Data / Identity / Stations / History / Utilities
- core2：RailCore 中的 Timetable / Import / Journeys / Editor / Statistics，以及 RailApplication、RailPresentation
- app1：RailMap 中的 Map / Workspace / Playback
- app2：RailMap 中的 Journeys / JourneyEditor / Statistics / Timetable / Import / Sharing
- app3：RailMap 中的 App / Infrastructure / Diagnostics / Localization / Design / Settings，以及 tools / auxiliary
- flow：跨层数据流追踪

未标 ✅ 的调用方计数和“无调用方”结论来自审查者的全树 grep。动手删除前，应对每个目标再 grep 一次。
