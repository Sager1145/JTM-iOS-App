# iOS 功能接口与架构审计（2026-11-05）

范围：`ios/RailMap/`（App）与 `ios/RailKit/Sources/`（RailCore / RailPresentation / RailApplication）。基线：`main` @ `10001a4be`。
性质：只读审计，本文是后续重构的依据；本次没有修改 Swift 代码，也没有构建或运行测试。

路径约定：`App/…` = `ios/RailMap/…`；`Core/…`、`Pres/…`、`AppL/…` 分别是 `ios/RailKit/Sources/RailCore/…`、`RailPresentation/…`、`RailApplication/…`。行号对应基线提交。

## 0. 方法与约束

- 由 8 个并行只读子代理分别审计：App/Workspace/Settings/Design、Map、Journeys/JourneyEditor/Localization、Playback/Sharing/Statistics/Timetable/Import、Infrastructure、RailCore 路由/行程/导入及 RailApplication、RailCore 渲染/车站/统计/身份及 RailPresentation，另有 1 个 Opus 代理追踪跨层数据流。由主会话汇总和裁决。
- 主会话亲自复核了以下证据：
  - `RouteSolver.swift:3640-3642` 的 `guardedFallback`；
  - `allowLegacy` 双趟求解（`RiddenRouteStore.swift:644,866,1628,1656`）；
  - `MapAnnotationReconciler` 的 DEBUG/Release 双实现（`RailMapCoordinator.swift:2705-2735`）；
  - `WorkspaceDerived.swift:385,388` 的恒等 map；
  - 两套乘车时长（`Statistics.swift:2226,2240` 与 `PassportStatistics.swift:205`）；
  - 若干死代码（`solveMissingConcurrently`、`minZoomByLineId`、`WorkspaceRideDetailView`、`PanelDetentResolver`）。
  - 其余条目是子代理读代码后给出的证据，未逐行复核的已在“不确定”中标注。
- 已有文档 `docs/reference/function-interface-map.md`（2026-10-18）中链接的 `docs/reports/integration/function-interface-architecture-2026-10-15.md` 在本仓库中**不存在**，属于死链。该文档有意保留的设计不在本文中重新争论：三段式保存链、header/chunk/full 三档包加载、旧求解第二趟。本文只在其上指出新的问题。
- 判断准则（第一性原理）：
  - 一个功能 → 一个接口 → 一个实现。
  - A→B 能解决的问题，不拆成 A→B→C→D。
  - 只转发的 wrapper/bridge/coordinator、只有一个实现的 protocol、形状相同的 DTO 转换，都视为坏味道。
  - 能解释出真实职责（隔离、并发、可测性、Web 一致性）的层次予以保留。

### 并行分支状态（2026-11-05 读取）

| 分支 / 会话 | 状态 | 与本文相关的改动 |
|---|---|---|
| `claude/data-perf-audit-a92ca0`（data-perf） | 已提交 2 个 commit | `JSNumber` 快路径、`Dates` 装饰排序、junction/history 解码按 URL 缓存（放在 `RiddenRouteStore` 的新 static 中）、`orderedJourneyGroups` 存储化、`availableYears` 进 `WorkspaceDerived`、`RailMapCoordinator.draws` 提前返回、`AppShell.statisticsLoadKey` 改用 `ridesKeyGeneration`。另有 11 条**未实现**建议，见其 `2026-11-05-data-performance-audit.md`。 |
| `claude/feature-ui-reorg-7a3f5b`（ui-reorg） | 已提交 1 个 commit | Settings 重组；删除 Settings 中重复的路网开关；“Frame network”移入 Map Layers；Upcoming 标题加“+”（`WorkspacePanelActions.swift`、`PrimaryTab.swift`）。 |
| `claude/add-trip-map-ui-9560dd`（add-trip） | 未提交的工作区改动 | `NewTripView.swift` +379 行；新增 `JourneyEditor/TripMapView.swift`（第二个 `MKMapView`）、`Core/Routing/TripRouteGeometry.swift`、`Core/Routing/TripRouteVia.swift`。 |
| `claude/sample-trips-normalize-f5d84a`（sample-trips） | 未提交的工作区改动 | 只改 `app/data/` 的样例数据，与本文无代码重叠。 |

下文用“**[data-perf 已处理]**”“**[data-perf 建议未实现]**”“**[ui-reorg 涉及]**”“**[add-trip 涉及]**”标注重叠情况。

---

## 1. 实际功能接口总表

只列真实能力，不含 private helper。“调用方”列出主要入口。

### 1.1 App 外壳与工作区

| 功能 | 接口 | 实现 | 调用方 |
|---|---|---|---|
| 启动、依赖生命周期 | `AppShell(localization:appearance:)` | `App/App/AppShell.swift:9`（持有 9 个 store 及 `@AppStorage` :54-56） | `App/App/RailMapApp.swift:78,82` |
| 菜单栏与键盘命令 | `RailCommandBridge`、`RailMapCommands` | `App/App/RailMapApp.swift:106,182` | `App/Workspace/RailWorkspaceView.swift:2110`（`installRailCommands`）；手机端另一套 :2547 |
| 工作区派生值（memo） | `WorkspaceDerived`（11 个方法） | `App/Workspace/WorkspaceDerived.swift:61` | `RailWorkspaceView.swift:374,1112,1303,1370,1570,2965,3458`；`PassportWorkspaceView.swift:138`；`StatisticsDashboardContent.swift:1419`；`ShareComposerView.swift:893,945` |
| Tab 导航 | `PrimaryTab`、`WorkspaceTabs(selection:page:)` | `App/Workspace/PrimaryTab.swift`、`WorkspaceTabs.swift:5` | `RailWorkspaceView.swift:873,1856` |
| Sheet/对话框 | `WorkspaceSheet`、`WorkspaceDialog`、`WorkspacePresentations`、`PresentationHost.afterTeardown` | `App/Workspace/WorkspaceSheetContent.swift:5`、`WorkspacePresentations.swift:5,14`、`PresentationHost.swift:23` | `RailWorkspaceView.swift:628,746` |
| 工具目的地（数据、设置） | `UtilityDestination`、`UtilityDestinationView` | `App/Workspace/UtilityDestination.swift:12,64` | `RailWorkspaceView.swift:1270,1126,777` |
| 底部常驻 sheet 几何 | `BottomChromeMetrics`、`ResidentMapChrome`、`WorkspaceMapChrome` | `App/Workspace/BottomChrome.swift:36`、`ResidentMapChrome.swift:13`、`WorkspaceMapChrome.swift:6` | `RailWorkspaceView.swift:812,1787,2281` |
| 显示设置 | `DisplaySettings`（15 个字段）、`SettingsView` | `App/Settings/DisplaySettings.swift:9`、`SettingsView.swift:29` | `Map/RailMapView.swift:81`、`Journeys/RideCard.swift:54` 等 |
| 玻璃/按压/触控/字号 | `railGlass`、`RailPressStyle`、`RailRowPressStyle`、`railMinimumTouchTarget`、`AppTypographyPolicy`、`railType` | `App/Design/GlassStyle.swift:23`、`RailMotion.swift:280,321`、`ControlSizing.swift:43`、`RailType.swift:116` | 全 App |

### 1.2 行程与编辑

| 功能 | 接口 | 实现 | 调用方 |
|---|---|---|---|
| 行程增删改、显隐、移动 | `ItineraryStore.add/replace/duplicate/delete/toggleVisibility/move -> Commit<T>` | `App/Journeys/ItineraryStore.swift:237-340` | `JourneyListRow.swift:95,155-174`、`JourneyEditing` |
| 带回滚的提交 | `JourneyEditing.addAndPersist/replaceAndPersist` | `App/JourneyEditor/JourneyEditing.swift:11-110` | `RailWorkspaceView.swift:973,3216`、`JourneyGroupPicker.swift:139`、`JourneyMenuView.swift:24,32` |
| 行程组 | `JourneyGroupCatalog.groups(in:)`、`ItineraryStore.orderedJourneyGroups` | `Core/Journeys/JourneyGroup.swift`、`ItineraryStore.swift:150` | `JourneyListRow.swift:83`、护照、分享 |
| 行程搜索 | `JourneySearch.search(_:alsoNamed:)` → `JourneySearchMatcher.matches` | `App/Journeys/JourneySearch.swift:27`、`Pres/Journeys/JourneySearchMatcher.swift` | `RailWorkspaceView.swift:332` |
| 标题、详情、路线状态 | `JourneyTitle.cardName`、`JourneyDetailSnapshot(train:)`、`RouteStatusResolver.status` | `Pres/Journeys/*` | `RideCard.swift:121`、`RideDetailView.swift:259,347`、`RiddenRouteStore.swift:250` |
| 行/卡片呈现 | `JourneyPresentationResolver.selected/workspace`、`JourneyBridge.routeState` | `Pres/Journeys/JourneyPresentationResolver.swift`、`App/Journeys/JourneyPresentationBridge.swift:46-114` | `RailWorkspaceView.swift:2339`（仅此一处） |
| 编辑已有行程 | `RideEditorView`（2108 行） | `App/JourneyEditor/RideEditorView.swift` | `RailWorkspaceView.swift:898,911`、`RideDetailView.swift:130` |
| 新建行程 | `NewTripView`（1458 行） | `App/JourneyEditor/NewTripView.swift` | `RailWorkspaceView.swift:678` **[add-trip 涉及]** |
| 选站 | `StationPickerView` + `StationPickerSearchController` | `App/JourneyEditor/StationPickerView.swift:82,312` | `StopEditorView.swift:159`、`NewTripView` |
| 草稿校验 | `RideDraftValidation.issues`（AppL）→ App 同名类型映射文案 | `AppL/Editor/RideDraftValidation.swift:45`、`App/JourneyEditor/EditorValidation.swift:46` | `RideEditorView.swift:1748`、`NewTripView.swift:1298,1309` |
| 新行程路线候选 | `TripRoutePlanner.plan` | `Core/Routing/TripRoutePlanner.swift:56` | `NewTripView.swift:1187` |
| 新行程路线证明 | `TripRouteValidation.validate` | `AppL/Routing/TripRouteValidation.swift:37` | `NewTripView.swift:1230`（唯一） |
| 本地补全 | `LocalJourneySearch.search`、`LocalJourneyAutofill.proposal` | `Core/Routing/LocalJourneySearch.swift:64`、`Core/Editor/` | `RailwayRouteCorrectionView.swift:187,193,215`、`LocalJourneyFillView.swift:261`、`TripRoutePlanner.swift:149,170,262`、`RouteRepair.swift:112`、`RecordedRouteAdmission.swift:128` |
| 物理路线修复 | `RouteRepairSession.search` → `RouteRepairFlow.advance` → `RouteRepair` → `RecordedRouteAdmission` | `AppL/Journeys/RouteRepairSession.swift:20`、`Core/Routing/RouteRepairFlow.swift:47` 等 | `RideEditorView.swift:1992,2028`、`RailWorkspaceView.swift:2785,2836` |
| 站名显示 | `AppLocalization.stationName(...)` 多个重载、`sectionEndpoint`、`BracketedStationText` | `App/Localization/AppLocalization.swift:230`、`StationNaming.swift:132,165`、`BracketedStationText.swift` | 见 §2 A8 |

### 1.3 地图

| 功能 | 接口 | 实现 | 调用方 |
|---|---|---|---|
| 地图宿主 | `RailMapView.Surface`（22 个存储属性） | `App/Map/RailMapView.swift:194` | `updateUIView` :468 |
| 差异检测与重建 | `Coordinator.update`（14 个参数）→ `MapDrawChanges.plan` | `App/Map/RailMapCoordinator.swift:237`、`Pres/Map/MapUpdatePlan.swift:82` | `RailMapView.swift:482` |
| 相机触发重建 | `scheduleCameraRebuild`（120 ms）→ `rebuild` | `RailMapCoordinator.swift:791,848,1173` | MapKit delegate |
| LOD | `NetworkVisibilityPolicy`、`LaneLOD.resolve`、`NetworkLOD.select/fitToBudget/buildRect` | `Pres/Map/NetworkVisibilityPolicy.swift`、`Core/Rendering/LaneLOD.swift`、`App/Map/NetworkLOD.swift:95-158` | `RailMapCoordinator.swift:843,1055,1311,1443` |
| Overlay 安装与样式 | `MapOverlayInstaller.install`、`MapOverlayStyles` | `App/Map/MapNetworkRendering.swift:279-520`、`MapOverlayStyles.swift:22` | `RailMapCoordinator.swift:1560-1800,4122` |
| 标注调和 | `MapAnnotationReconciler.plan/apply`（DEBUG）/ `reconcile`（Release） | `App/Map/MapAnnotationReconciler.swift:42,85,124` | `RailMapCoordinator.swift:2706-2733` |
| 标签放置 | `buildMarkers` 内联选举 + `MapLabelCollisionGrid` + `MapEndpointLabels.layout` | `RailMapCoordinator.swift:1957-2800`、`MapLabelCollisionGrid.swift:12`、`MapEndpointLabels.swift:290` | `runLabelPass` :1913 |
| 点击行程命中 | `MapInteractionCoordinator.rideHits` → `RideTapIndex` → `RideTapResolver.hits` | `App/Map/MapInteractionCoordinator.swift:30`、`RideTapIndex.swift:172,207`、`Pres/Map/RideTapResolver.swift` | `handleMapTap` :3438 |
| 回放图层 | `MapPlaybackLayer.render/frame/repaint`、`PlaybackMapRendering`（单一实现） | `App/Map/MapPlaybackLayer.swift:80`、`App/Playback/PlaybackController.swift:27` | `RailMapCoordinator.swift:4023-4040` |
| 相机 | `RailMapController.fit/fitIfNeeded`、`MapCameraPolicy` | `App/Map/RailMapController.swift:21-420` | `RailMapCoordinator.swift:431,486`、`MapPlaybackLayer.swift:604` |
| 车站卡/线路卡 | `StationCardView`、`RailwayLineCardView` | `App/Map/StationCardView.swift:101`、`RailwayLineCardView.swift:96` | `RailWorkspaceView.swift:3256` |

### 1.4 回放、分享、统计、时刻表、导入

| 功能 | 接口 | 实现 | 调用方 |
|---|---|---|---|
| 回放 | `PlaybackController.start/estimate/togglePause/previous/next/setSpeed`，内核 `Playback.compile/plan/Playhead` | `App/Playback/PlaybackController.swift:394,270`、`Core/Rendering/Playback.swift:300,1076,966` | `PassportWorkspaceView.swift:155`、`RailWorkspaceView.swift:3570-3589` |
| 视频导出 | `VideoExportFlow.plan/start/abandonRecording`、`PlaybackVideoExporter` | `App/Playback/VideoExportFlow.swift:51,68,87`、`PlaybackVideoExporter.swift:131,240` | `RailWorkspaceView.swift:727,3515,3614` |
| 里程/护照统计 | `MileageStatisticsStore.load(scope:…)` → `MileageMatching.match` → `Statistics.buildMileageStatsView` + `PassportStatistics.build` | `App/Statistics/MileageStatisticsStore.swift:323`、`AppL/Statistics/MileageMatching.swift:68`、`Core/Statistics/Statistics.swift:2216`、`App/Statistics/PassportStatistics.swift:148` | `AppShell.swift:196`、`ShareComposerView.swift:1039` |
| 分享卡片 | `ShareComposerModel`、`ShareCardRenderController.render/export`、`SharePNGWriter` | `App/Sharing/ShareComposerModel.swift`、`ShareCardRendering.swift:117,230,376` | `RailWorkspaceView.swift:741` |
| 单行程图片 | `JourneyPoster.render`（CoreGraphics） | `App/Sharing/JourneyShareImage.swift:202` | `RideCard.swift:254`、`RideDetailView.swift:127`、`StationCardView.swift:272` |
| 时刻表快速匹配 | `TimetableQuickMatchController.search` → `TimetableTripMatch.candidates` | `App/Timetable/TimetableQuickMatchController.swift:55`、`Core/Timetable/TimetableTripMatch.swift:6` | `NewTripView.swift:387` |
| 时刻表数据库 | `TrainTimetableDatabase.bundled/trips/trip/sources` | `Core/Timetable/TrainTimetableDatabase.swift` | 多处 |
| 导入 | `ImportFileReader.read` → `ImportFlow.check/commit` → `ImportPreflight.inspect` → `ItineraryStore.runImport` → `ImportStaging.stage` → `ImportEngine.Session` | `App/Import/ImportFlow.swift:277,341`、`AppL/Import/ImportPreflight.swift:106`、`ItineraryStore.swift:460`、`AppL/Import/ImportStaging.swift`、`Core/Import/ImportEngine.swift:222` | `DataImportView`、`DataManagerView.swift:24` |
| 换乘指南/OCR | `TransferGuideOCR.read`、`TransferGuideImport.read/commit` | `App/Import/TransferGuideOCR.swift:97`、`TransferGuideImport.swift:126,364` | `TransferGuideImportView.swift:632` |

### 1.5 基础设施与 RailCore 核心

| 功能 | 接口 | 实现 | 调用方 |
|---|---|---|---|
| 显示路网分块 | `RailNetworkStore.ensure(regionsIntersecting:cameraZoom:)` | `App/Infrastructure/Network/RailNetworkStore.swift:610`（→ :851、:1355、:1459、:1100） | `RailWorkspaceView.swift:3268` |
| 整区绘制模型 | `RailNetworkStore.ensure(_ region)` → `decodeGeometry`/`decode` | `RailNetworkStore.swift:570,686,1645` | `RideEditorView:315,1128`、`TransferGuideImportView:110,186,653`、`RailWorkspaceView:429,504` |
| 显示路网格式 | `RailDisplayNetwork.manifest/blob/chunk/history/stationIdentity` | `App/Infrastructure/Network/RailDisplayNetwork.swift`、`RailDisplayNetworkFormats.swift`（948 行） | `RailNetworkStore`、`MapRideStationImportance.swift:17-25` |
| 整包缓存 | `DisplayNetworkCache.package/lineParts/generation/network` | `App/Infrastructure/Network/DisplayNetworkCache.swift:77-128` | `RiddenRouteStore` 等约 10 处 |
| 编辑器站目录 | `loadCatalog(for:)` | `App/Infrastructure/Network/EditorCatalogLoading.swift:52` | `RideEditorView:387`、`StationPickerView:320`、`NewTripView:1125` |
| 统计边索引 | `EdgeIndexCache.index/merged/scoped` | `App/Infrastructure/Network/EdgeIndexCache.swift` | `MileageStatisticsStore:689`、`CategoryIndexes:65`、`TraversedLineDetector:169` |
| 行程持久化 | `ItineraryStore.mutate/commitWorkingSet` → `RideLibrary.saveResult` → `RidePersistenceQueue` → `RideStorage.writeStore` → `MergedStore`/`ExportCache` | `App/Infrastructure/Persistence/*` | `JourneyEditing`、导入 |
| 单程路线解析 | `RiddenRouteStore.load/resolve` → `RideRouteResolution.resolve(_:allowLegacy:)` | `App/Infrastructure/Persistence/RiddenRouteStore.swift:303,495`、`Core/Routing/RideRouteResolution.swift:172` | `AppShell.swift:161` |
| 区段求解 | `RouteSolver.solveOfficialInterval/solveSectionOnDemand`（internal） | `Core/Routing/RouteSolver.swift:2805,3691` | `RideRouteResolution.swift:324-338` |
| 站序 → 区间链 | `StationIntervalResolver.resolve` | `Core/Routing/StationIntervalResolver.swift:214` | `RideRouteResolution.swift:57` |
| 身份注册表 | `RegistryIdentityLookup`、`RegistryIdentityCache`、`RegistryIdentityUpgrade`、`StationNameLookup` | `Core/Identity/RegistryIdentity.swift:708,941`、`RegistryBundle.swift:243`、`StationNameParts.swift:125` | `App/Infrastructure/…/BundledRegistry.swift:121-131` |
| 运营者标签 | `OperatorBranding.companyLabel`、`OperatorIdentity`、`RegistryIdentity.operatorLabel/operatorLogo` | `Core/Identity/OperatorBranding.swift:92`、`OperatorIdentity.swift`、`RegistryIdentity.swift:120,127` | 见 §2 A9 |
| 历史叠加 | `RailHistoryOverlay`、`RailHistory.apply` | `Core/History/*` | `RiddenRouteStore:1890`、`EdgeIndexCache:250`、`JourneyStationAliases:20` |
| 日期/时钟 | `Dates.*`、`RegionClock`、`JourneyClock` | `Core/Utilities/Dates.swift`、`Pres/Regions/RegionClock.swift:62`、`JourneyClock.swift:37` | 全局 |
| 订阅（ChatGPT） | `ChatGPTSubscriptionAuth.shared`、`ChatGPTSubscriptionService` | `App/Infrastructure/Subscription/*`、`Core/Import/ChatGPTSubscriptionProtocol.swift` | `JourneyCompletionView:57`、`TrainResearchView:219` |

---

## 2. 同一功能多实现（按严重度排序）

编号 A1…，严重度为 **高 / 中 / 低**。每条给出证据、最小目标设计（A→B）和影响估计。

### A1【高·正确性】乘车总时长两套算法，结果可能不一致

- 仪表盘和车票使用 `Statistics.sumRideMinutes`（`Core/Statistics/Statistics.swift:1894`，赋值在 :2226、:2240）。它直接用印刷时刻相减，不处理时区。
- 护照使用 `train.journeyClock.rideMinutes(...)`（`App/Statistics/PassportStatistics.swift:205`），做了时区修正，并且重新累加了一遍 km。
- 两个值都会上屏：`StatisticsDashboardContent.swift:668`、`MileageStatisticsStore.swift:1330` 读 `stats.rideMinutes`；`StatisticsDashboardContent.swift:1051` 读 `passport.totalMinutes`。跨时区行程会出现两个不同的“总乘车时间”。
- 根因：`JourneyClock.swift:25-30` 为了 JS 一致性禁止把时区修正放进 RailCore。时区表也因此在 `Statistics.statisticsReferenceDate`（`Statistics.swift:1640-1670`）和 `RegionClock`（`Pres/Regions/RegionClock.swift:90-136`）各有一份。
- 目标：把区域→时区表（`RegionZone`）下沉到 `Core/Utilities`。`Statistics.trainRideMinutes(train, offsetMinutes:)` 由调用方传偏移，只在一个聚合器里计算；`PassportStatistics` 读同一个值。
- 影响：消除一个用户可见的不一致；删除一份时区表（约 40 行）和护照里的重复累加（约 30 行）。
- 状态：无人处理。

### A2【高】统计范围切片在 4–6 处各算一遍，其中 2 处是手写副本

- `StatisticsMembership.slice`（`Pres/Statistics/StatisticsMembership.swift:28`）的调用：
  - `WorkspaceDerived.statisticsScope`（`WorkspaceDerived.swift:181`）；
  - `passportScope`（:384）；
  - `scopedDates`（:420）；
  - `MileageStatisticsStore.load(scope:)`（`MileageStatisticsStore.swift:324-330`），无缓存，并且又跑一遍 `scope.filter`。
- `ShareComposerView.swift:880-888`（`scopedTrains`）和 :935-940（`trains(in:selection:)`）手写了同一规则：`RideLedger.hasBeenRidden && includesYear && includesJourneyGroup && includesDate`。
  - 它们在计算属性里，每次读取都重算。
  - `scopeWork`（:908）在导出时被读 3 次（:1095、:1118、:1131）。
  - `scopedTrains` 只在 `#if DEBUG` 下使用（:1086）。
- `ShareCardRendering.swift:213` 对已经切过范围的 trains 再跑一次 `scope.filter`。
- `ShareComposerView.swift:17` 自持一个 `@State WorkspaceDerived`，缓存是冷的。
- `AppShell.swift:177` 第三次构造 `StatisticsScope(region, area)`。
- 风险：分享卡片与仪表盘显示的行程集合可能漂移。
- 目标：一个 `StatisticsSlice` 值，键为（trains generation、rides generation、scope、selection）。由 `MileageStatisticsStore` 或 `WorkspaceDerived` 计算一次，仪表盘、覆盖地图和分享卡片都读它；`load` 接收已切好的 trains。删除分享侧的手写规则和 `scopedTrains`。
- 影响：删约 100 行，搬约 300 行到 RailKit（可测）；每次统计/分享 body 少 3–5 次 O(N) 遍历。
- 状态：data-perf 已把 `availableYears` 纳入 `WorkspaceDerived` **[data-perf 已处理一小部分]**；主体未处理。

### A3【高】路线修复流程在工作区与编辑器各实现一遍（4 个调用点）

- 工作区（卡片修复）：`RailWorkspaceView.swift:2733-2940`，约 210 行。包含 `applyAutomaticRepair`、`continueCardRepair`、`persistRepair`、`publishRepair`、`undoRouteRepair`、`repairMarks`。
- 编辑器（草稿修复）：`RideEditorView.swift:1965-2060`。包含 `repairGapMarks`、`repairRoute`、`continueRepair`、`presentRepair`。
- 四处 `RouteRepairSession.search` 调用（`RideEditorView.swift:1992,2028`、`RailWorkspaceView.swift:2785,2836`）传入相同的 `loadJourneyStationAliases`/`loadJourneyAdmissionContext` 闭包，后面跟着相同的 `result.accepts` 和 `advance.train != prepared` 处理。
- 暂停状态有两种形状：`RouteRepairGuide`（`App/JourneyEditor/RouteRepairFlow.swift:5-22`）和 `RideEditorView.RepairContinuation`/`RouteGuideRequest`（`RideEditorView.swift:109-130`）。
- Gap 映射写了两遍：`RideEditorView.swift:1965-1973` 与 `RailWorkspaceView.swift:2871-2879`，都把 `RiddenRouteStore.SectionGap` 映射到 `RouteRepair.Gap`。
- 调用链：View → `RouteRepairSession`（38 行，只做 `Task.detached` 加转发）→ `RouteRepairFlow` → `RouteRepair` → `RecordedRouteAdmission` → `LocalJourneySearch`，共 5 跳。
- 目标：`RouteRepairFlow.run(train:baseline:package:resume:) async`（Core）自带 alias/admission 加载；App 只有一个 `RouteRepairController(commit: (Train) -> Void)`，提供 `run/continue/undo`。暂停类型合并为一个；`RouteRepair.Gap.init(_ SectionGap)`。删除 `RouteRepairSession.swift`。
- 影响：删 150–200 行；2 个暂停类型合为 1 个，4 对闭包归零；“修复期间行程已变更”的语义只维护一处。
- 状态：无人处理。add-trip 不改 `RideEditorView`/`RailWorkspaceView`，可以在它合并后立即做。

### A4【高】单程解析的两代求解并存（`allowLegacy`），且求解器内部违背 ADR 0007 fail-closed

- `RideRouteResolution.resolve(_:allowLegacy: Bool = true)`（`Core/Routing/RideRouteResolution.swift:172`）：
  - 第一趟用 `StationIntervalResolver`，依据提示、不建图（:230-290）；
  - 第二趟回落到 `RouteSolver.solveOfficialInterval ?? solveSectionOnDemand`（:314 起）。
- `RiddenRouteStore` 在 :866 用 `allowLegacy:false` 推断，在 :644、:1628、:1656 用 `true`。`JourneyWorkKey.allowLegacy`（:1329）让共享工作的键空间翻倍。两趟的编排仍在 App 层，ADR 0012 声称它已迁到 `RideRouteResolution`，实际只迁了一部分。
- `RouteSolver.swift:3640-3642` 写着 “Last resort: a result the endpoint guard rejected is better than no route at all”，返回 `guardedFallback`。:3611-3637 还有放弃机构偏好的 soft fallback（attempt mode `no_common_line_soft_fallback` 等，:1328-1333）。这与 ADR 0007 fail-closed 冲突。没有发现直线弦合成。
- 目标：
  - `RideRouteResolution.resolve(request) -> Outcome` 内部固定“区间推断 → 逐段求解”的顺序，App 不再传 `allowLegacy`；删除 `JourneyWorkKey.allowLegacy`、`rejectPrecomputed`/`PrecomputedRouteRejections`（`RiddenRouteStore.swift:1316,1432`）。
  - `guardedFallback` 二选一：删除并返回 nil；或作为 `.unproven` 结果显式上报。至少更新 ADR 0007。
- 影响：App 删 150–250 行；每程少一次 `inferStationSections`（见 C6）。
- 状态：无人处理。行为风险高，需要路线一致性测试护航。

### A5【高】同一行程的“身份/变更”被哈希 5 种方式；路线按整个 `Train` 判等，改颜色也会重解

- 五种哈希：
  - `DrawnRide.geometryDigest`（`RiddenRouteStore.swift:1131-1158`）；
  - 地图的 `rideSignature`（`RailMapCoordinator.swift:603`，逐程拼字符串，含停站哈希）和 `ridesDigest`（:3217）；
  - `WorkspaceDerived.ridesDigest`（:197）；
  - `AppShell` 的 `RideKey` 数组（:330）；
  - `MileageStatisticsStore.entryDigest`/`fingerprint`（:849-978，在主线程遍历所有停站，`fullDistanceKnown` 每程算两次，`ridesByID` 建 3 次）。
- 路线求解键为整个 `Train` 判等（`RiddenRouteStore.swift:313,326`），而 `DrawnRide` 复制了 `colorHex`、`visible`（:1142-1146）。于是改颜色、显隐、备注或 `setRidden` 都会重读路线缓存并重建 ride，地图签名随之变化并触发重建。
- 目标：`drawnRide()` 只算一次 `routeDigest`（停站、区段、日期、策略）；store 发布 `ridesGeneration: Int`，所有键都用它。颜色和显隐按 id 从 `Train` 读，走已有的 `routePaintOnly` 路径（`Coordinator.update`）。
- 影响：删约 150 行；地图 update 路径上不再逐程哈希停站或拼字符串；纯样式编辑不再触发路线重读和几何重建；每次编辑少一次主线程 fingerprint。
- 状态：
  - data-perf 用 `ridesKeyGeneration` 替换了 `AppShell.statisticsLoadKey` 的逐程映射 **[data-perf 已处理第 4 项]**；
  - “与路线无关的编辑仍会重解”是其建议 #8 **[data-perf 建议未实现]**；
  - 地图与统计侧的另外 3 种哈希无人处理。

### A6【高·性能】地图把同一段行程几何切片 3 次，坐标类型来回转换

- (a) 构建 MKPolyline：`RailMapCoordinator.swift:1668-1678`（`builtStrokeCoordinates`、Douglas-Peucker）。
- (b) 点击索引：`drawnStrokes` → `drawnCoordinates` → 再次 `ContinuousStroke.slice`（:2922-2933、:3123-3172）。`RideTapIndex` 另存一份 `[[[Coordinate]]]`（`RideTapIndex.swift:88`），每次点击都对每个顶点调 `.clLocation`。
- (c) 端点：`displayedStationCoordinate` 为了取首尾点重切整段（:3304-3351）。
- (d) 回放：通过 `RailMapView.swift:473` 的闭包再转换一次。
- 转换链为 `Coordinate → CLLocationCoordinate2D → Coordinate → CL`（`asCoordinates` :3175、`Self.coordinate` :4116）。
- 目标：几何缓存对每段只产出一个 `RideDrawnStroke { mapPoints, endpoints }`，polyline、点击索引、端点和回放都读它。`RideTapIndex` 直接对 `MKMapPoint` 分块，删除自己的墨卡托投影步骤（`RideTapIndex.swift:133-160`）。
- 影响：删约 120 行转换代码，去掉一份全量几何的内存副本；每次 ride rebuild 和点击索引失效都少一次切片。
- 状态：“点击索引每次 rebuild 都失效”是 data-perf 建议 #5 **[data-perf 建议未实现]**；三次切片本身无人处理。
- 新风险：add-trip 新增的 `Core/Routing/TripRouteGeometry.swift` 按区间把显示折线切给 `TripMapView`（第二个 `MKMapView`），形成第 4 条几何管线 **[add-trip 涉及]**。合并前应确认它复用 `ContinuousStroke`/`DisplayParts` 的切片，而不是另写一套。

### A7【高】`RailNetworkStore` 两条平行绘图管线；同一个 `<cc>-2025.json` 有 4 条解码路径

- 管线 A：整包解码（`RailNetworkStore.swift:686,1645` 经 `DisplayNetworkCache.generation` :1655），产出 `lines`/`stations`，含每站 popup 与全部区间。
- 管线 B：分块显示路网，产出 `mapLines`/`mapStations`（:355）。
- 管线 A 的消费方很少：运营者名建议（`RideEditorView:1128`）、换乘指南站匹配（`TransferGuideImportView:653`）、UI 测试取景（`RailWorkspaceView:429`）、一处调试拾取（:504）。`RailNetworkStore.stations(in:)`（:1587）及其 `stationsByRegion` 缓存没有非测试调用方。
- 同一个包的 4 条解码路径：
  - `CompactPackage.Headers.load`：启动时为徽标全量扫描约 9 MB 的日本包，只读线名和颜色（:1634）；
  - `DisplayParts.LoadedPackage.load`（`DisplayNetworkCache.swift:375`）；
  - `CompactPackage.StationDirectory`（`EditorCatalogLoading.swift:63`）；
  - RailCore 中未使用的 `CompactPackage.load`（`Core/Data/CompactPackage.swift:304`）和 `LineTopology.byLineID(contentsOf:)`（`Core/Rendering/DisplayParts.swift:281`）。
- 目标：
  - 删除管线 A。运营者名取自 `loadCatalog(for:)` 或 manifest 的 `Line.operator`；换乘指南匹配改用 `EditorCatalog`。
  - 徽标从显示路网 manifest 的 `lines` 读取（已有 `name/color/colorDark/operator/logo/operatorShort`，`RailDisplayNetworkFormats.swift:78-106`），用几 KB 读取替代 9 MB 扫描。
- 影响：删约 250 行；少一次整区解码，少为日本约 9k 站组构建 popup；冷启动少一次 9 MB JSON 扫描。
- 不确定：`RouteBadgeIndex` 还读 package art 和 `isLoop`（:72），需确认 manifest 能覆盖；`TransferGuideImportView:186` 需要日本站数据，需确认 `EditorCatalog` 是否足够。
- 状态：无人处理。

### A8【高】站名解析有 5 条以上路径

1. `AppLocalization.stationName(_:code:region:allowNameFallback:)`（`App/Localization/AppLocalization.swift:230`）。
2. `AppLocalization.stationName(_:in:code:)`（`StationNaming.swift:132`）：在 `train.stops` 里扫 4 遍，再调 `RegistryStationDisplay.resolve` → `Region.resolved` → `preferredReadingCode` → 路径 1。
3. `sectionEndpoint(...)`（`StationNaming.swift:165`）：路径 2 的近似副本，外加 `StationCodeAliases` 逻辑。用于 `ServiceRangeEditorView.swift:69,71`、`RouteSectionEditorView.swift:15,16`、`RideDetailView.swift:1081,1083`、`ServiceSectionSummary.swift:12`。
4. `BracketedStationText.title/secondary`：约 15 个调用点用相同的 4 参数形状（`NewTripView.swift:636,644,817,826,1018,1038`、`StationPickerView.swift:387,390,453,462`、`RideDetailView.swift:430,433,601,612,1417`）。`title` 的 `localization:` 参数未使用。
5. `NewTripView.stationTitle/stationQualifier/stationSubtitle/recordedQualifier/visitQualifier`（:1016-1082）基于 `StationLabel` 重做了一遍，并把 line-labels 回退写了 3 次（:1031、:1056、:1073）**[add-trip 涉及]**。

- 另外，“`RegistryStationDisplay.resolve → preferredReadingCode → localization.stationName`”这段被复制了 3 次：`RailMapCoordinator.swift:688-740`、`PlaybackController.swift:322`、`StationNaming.swift:145`。
- “按归一化名称找站码”也有 3 个变体：`Train.stationCode(named:)`（`StationNaming.swift:60`）、`JourneyDetailSnapshot.stationCode(named:recorded:)`（`Pres/Journeys/JourneyDetailSnapshot.swift:20`）、`endpointStationCode`（`StationNaming.swift:69`）。
- 目标：一个纯值函数 `StationDisplayText.resolve(stop:, train:, engine:) -> (title, qualifier, copy, spoken)`，放在 RailPresentation；`AppLocalization` 只提供引擎查找。`BracketedStationText` 并入；`JourneyDetailSnapshot` 预建 `stopIndex` 供详情和区段编辑器使用。
- 影响：删约 150 行，4 个格式化入口合为 1 个；多区域同名站（如嘉義，见 `StationNaming.swift:1-40`）这类 bug 只需在一处修。
- 状态：无人处理。`NewTripView` 部分等 add-trip 合并后再动。

### A9【高】运营者身份 4 条路径并存；身份注册表 4 个全局单例

- 旧路径 A：`OperatorBranding` 按自由文本公司名查标签表（`Core/Identity/OperatorBranding.swift:64-100`），约 17 个调用点。
- 旧路径 B：`OperatorIdentity` 读独立的 `operator-identities.json`（`Core/Identity/OperatorIdentity.swift:4-92`），用于 `RegistryIdentity.swift:159` 和 `ServicePatternBrowsePolicy.swift:254`。
- 新路径：`RegistryBundle.operatorRecords`，经 `RegistryIdentity.operatorLabel/operatorLogo`（:120,127）读取。它通过 `brandingSource(for:)`（:508-524）调用旧的 `OperatorBranding.companyLabel` 来复现标签，新路径依赖旧路径。
- 应用方式不一致：
  - `ServicePatternBrowsePolicy.companyDisplayName`（:249-257）先查 `OperatorIdentity` 再查注册表；`JourneyRouteIdentity.operatorLabels`（:66-79）直接查注册表。
  - App 的 `JourneyBranding.operatorLogoPath`（:134-146）先调 `JourneyRouteIdentity.operatorLogo`，再用 `operatorID(forExactName:)` 重复查一遍。
  - `PassportStatistics.swift:~245` 在已有 `operatorID/operatorIDs` 时仍按 `train.company` 文本分组。
- 4 个单例：`BundledRegistry.install`（:121-131）装了 3 个全局 provider。`RegistryIdentityLookup`、`RegistryIdentityCache`、`RegistryIdentityUpgrade`、`StationNameLookup` 各有一把锁和一个 `nonisolated(unsafe) static`。
  - `directoryFromCache`（`BundledRegistry.swift:162-170`）每次调用都新建 `StationNameDirectory`，没有缓存。
  - `StationNameDirectory.parts(forOfficialName:)` 和 `leadingOfficialName` 每次 O(N) 重新 fold 全部 key，而 `RegistryIdentity` 已持有预 fold 的 `stationIDsByOfficialName`/`stationIDsByBase`（:36-42）。
- 目标：一个 `RegistryProvider`，提供 `phase(region)`、`identity(region)`、`names(region)`；`StationNameDirectory` 成为 `RegistryIdentity` 的 lazy 字段。运营者统一走 `RegistryIdentity.label/logo(forCompanyText:region:)`，`OperatorIdentity.json` 并入 bundle，`OperatorBranding` 只作 bundle 未就绪时的回退。
- 影响：删约 250 行，3 个安装调用合为 1 个；消除每次查名的 O(N) fold。
- 状态：无人处理。需对照 ADR 0013 的 M1–M5 进度。

### A10【中】地图标注调和器 DEBUG 与 Release 是两份实现

- `MapAnnotationReconciler.swift:24-122`（`plan`+`apply`，DEBUG 使用）与 :124-170（`reconcile`，Release 使用）。调用点 `RailMapCoordinator.swift:2706-2735` 用 `#if DEBUG / #else` 分开。
- 两者是同一个保留/恢复/新增/退役算法的拷贝。DEBUG 下测得的行为不一定等于发布行为。
- 目标：只保留 `plan`+`apply`，计数器作为 plan 的字段。
- 影响：删约 50 行；测试面合一，诊断度量的是真实代码路径。

### A11【中】线路最小缩放级别由 3 层决定，`NetworkLOD` 大半是转发

- `Core/Rendering/Visibility.minZoomForLength`（阈值 150/70/30/12）由 `RailNetworkStore.swift:1657-1672` 算好，作为 `portedMinZoom` 传入。
- `Pres/Map/NetworkVisibilityPolicy.lineMinZoomMapLibre` 用自己的 300/120/50/20 km 梯度，再与 `portedMinZoom` 取 max，长度规则被应用了两次。
- `App/Map/NetworkLOD.swift:49-92`（`minZoomMapLibre/minZoom/stationMinZoom*`）只转发给 policy，并被 `RailDisplayNetworkFormats.swift:119` 和 `RailNetworkStore.swift:1275-1796` 约 9 次调用。数据层由此依赖了 `Map/`（见 D2）。
- 标签侧：`RideMarkerVisibility.minimumMapLibreZoom`（Core，接收 `trainType`/`country` 但都忽略）与 `StationLabelVisibility.minimumMapLibreZoom`（Pres）各一份。
- 目标：RailPresentation 中只保留一个 `MapDetail` 梯度。Web 梯度仅在一致性测试需要时作为输入；删除 `NetworkLOD` 的转发函数。
- 影响：删约 150 行，减少 2 个接口；消除“长度判两次”的语义歧义。

### A12【中】标签避让 3 种算法、淡入淡出 3 套引擎、比例尺测量 4 种

- 避让：
  - `MapLabelCollisionGrid`（96 pt 网格）；
  - `MapEndpointLabels.layout`（O(n²) 的 `placed.contains` 加环形搜索，`MapEndpointLabels.swift:290`）；
  - `buildMarkers` 内为 `RideStationAnnotation` 选左右侧（`RailMapCoordinator.swift:2452`）。
  - 端点布局在 :2091、:3413，以及每帧的 :862、:936 都会执行。
- 淡入淡出：`MapOverlayStyles` 的透明度时钟（:74-170）、`RideStationOverlayRenderer.Fade` 加独立 CADisplayLink、`MapAnnotationReconciler.fade`（UIView 动画）。
- 比例尺：
  - `RideTapIndex.mapPointsPerViewPoint`（:234）与 `MapProjection.mapPointsPerScreenPoint`（:69），跨度和守卫条件不同；
  - `RideStationOverlay.swift:284,332` 用公式推导；
  - `MapPlaybackLayer.swift:408` 用 `visibleMapRect.width/bounds.width`，地图旋转时不对；
  - `MapGeometryFrame`（`MapNetworkRendering.swift:585`）。
- 渲染器样式应用写了 3 遍：`rendererFor` 的 polyline 分支（:4157-4169）与 multipolyline 分支（:4174-4190）完全相同，另有 `MapOverlayStyles.rescale`（:262-299）。
- 目标：
  - 每次 camera 回调只算一个 `CameraSample { zoom, mapPointsPerPoint, rect }` 传给所有消费者；
  - 一个带 box API 的标签放置器，先预留端点卡片；
  - 一个 `MapOverlayStyles.configure(renderer:key:scale:)`。
- 影响：删约 100 行；修正旋转下回放的比例尺。

### A13【中】统计的每个卡片都构建两遍

- 小组件路径：`MileageStatisticsStore.widgetData`（:1044-1295，约 250 行），供 `StatsWidgetView`、网格和分享卡片使用。
- 详情卡路径：`StatisticsDashboardContent.swift` 中 13 个 `*Card` 函数。
  - 覆盖率：`MileageStatisticsStore.swift:1206-1222` 与 `StatisticsDashboardContent.swift:593`；
  - 服务占比：:1060 与 :645；
  - 排名：:1071 与 :1212。
- 目标：每个 `StatisticsCardKind` 有一个 row-model builder，两种渲染器都读它。
- 影响：删 200–300 行。

### A14【中】导入预检与提交把整个文档跑两遍引擎

- `ImportPreflight.inspect`（`AppL/Import/ImportPreflight.swift:~125-170`）对每行跑一遍 `ImportEngine.Session`，然后丢弃结果。`commit` 再经 `ItineraryStore.runImport` → `ImportStaging.stage`（`ItineraryStore.swift:489-496`）重跑。两次的进度接线也不同（`ImportFlow.swift:293-302` 与 `ItineraryStore.swift:482-503`）。
- `ImportStaging.Snapshot` 镜像了 `Session` 的字段。
- 目标：报告可提交且 store generation 未变时，`Report` 携带 `ImportStaging.Snapshot`，`commit` 只做校验和发布。
- 影响：大文件导入耗时减半；删约 100 行。需要测试确认 Snapshot 与 Report 的改名和 ID 结果一致。

### A15【中】工作区内同一规则写两遍

- Tab→页面的 switch 写了两遍：`RailWorkspaceView.swift:879-890` 与 :1856-1862，`journeyEditor` 分支也重复（:874、:1849）。`allJourneysPanel()`（:1093）只返回 `ridesList`。
- 地图范围规则写了两遍：`mapRides`（:3450-3480）与 UI 测试 hook 里的 `inCurrentMapScope`（:369-389）。
- `commitJourneyEditor`（:973-1040）中两段 switch 完全相同（各约 14 行）。
- `PrimaryTab.headerActionCount`（`PrimaryTab.swift:27-32`）把 3/4/4/2 写死，与 `WorkspacePanelActions.swift:21-37` 的分支互为镜像，改一处另一处就会静默出错。**[ui-reorg 涉及]**：ui-reorg 刚给 Upcoming 加了“+”并改了这两个文件，合并后需复查。
- 目标：一个 `tabContent(_:)`；一个 `mapScopeIDs(for:)`，或放进 `WorkspaceJourneyRules`；`headerActionCount` 改为从 actions 数组计数。
- 影响：删约 50 行。

### A16【中】错误提示、偏好存储、按钮样式各有多种做法

- “保存失败”有 5 种呈现：
  - `WorkspaceDialog.saveFailed`（`WorkspacePresentations.swift:27-35`）；
  - 编辑器自己的 alert（`RailWorkspaceView.swift:928-945`）；
  - 修复失败 alert（:699、:2916-2921）；
  - `JourneyMenuView.swift:87`；
  - `JourneyGroupPicker.swift:111`。
  - 此外工作区还有 `.fullScreenCover`（:670）、`.sheet(item: $routeRepairGuide)`（:676）、`.popover`（:1339），都游离在 `WorkspaceSheet`/`WorkspaceDialog` 之外。
- 偏好有 3 种存储机制：
  - `@AppStorage` 裸字符串键，`launch-map-scope`/`launch-map-region` 在 `SettingsView.swift:42-43` 与 `RailWorkspaceView.swift:131,134` 各声明一次；
  - `DisplaySettings` 手写字典 `"display-settings-v5"`，每个字段拼写 5 遍（`DisplaySettings.swift:19-170`），`SettingsView` 手动调用 12 次 `display.persist()`；
  - `ItineraryStore(preferences:)`/`RideLibrary` 各自持有 `UserDefaults`。
  - 读音设置由 View 同步到 `AppLocalization`（`SettingsView.swift:187-192`、:457-461），只在设置页可见时运行；`AppLocalization.swift:82,92` 在初始化时又静态读取一次。
- 按钮/按压样式有 4 种：
  - `RailCapsuleButtonStyle`（`ControlSizing.swift:4`）内联复刻了 `RailPressStyle`（`RailMotion.swift:280`）的缩放、透明度和禁用常量；
  - `RailRowPressStyle` 是第三个变体；
  - `railMenuControlSurface`（`GlassStyle.swift:61`）复制了胶囊的 `.quaternary.opacity(0.5)` 填充。
- 设计 token 重名或重复：
  - `RailStyle.cardCornerRadius = 20`（`RailStyle.swift:152`）与 `WorkspaceMenuMetrics.cardCornerRadius = 28`（`WorkspaceLayout.swift:30`）同名不同义；`chromeCornerRadius = 20`（:167）与前者数值相同。
  - 触控尺寸 44 写了两处（`WorkspaceLayout.swift:17`、`RailStyle.swift:183`），调用方分别依赖两处。
  - `RailStyle` 把地图渲染常量和 UI token 混在一起。
- Dynamic Type 上限有两种机制：根部的 `AppTypographyPolicy.supportedSizes`，以及只有 Statistics 使用的 `RailType.Role`。
- 目标：
  - `WorkspaceDialog.notice(title, detail)` 统一提示，修复引导改为 `WorkspaceSheet.repairGuide`；
  - 一个带类型化键的 `Preferences`，`DisplaySettings` 改为 Codable，并在 didSet 时防抖持久化；
  - `RailCapsuleButtonStyle` 组合 `RailPressStyle`；
  - `RailMetrics` 只放 UI token（card 20、dockedCard 28、touch 44），`RailStyle` 只放地图绘制常量。
- 影响：合计删约 200 行。
- 状态：Settings 部分 **[ui-reorg 涉及]**，需在它合并后再动 `SettingsView`。

### A17【中】字符串表的别名层与并行查找路径

- `editorText`（`AppStrings.swift:100`，10 个调用点）只是 `text` 的别名；`journeyText(key,params,fallback)`（:114，91 个调用点）只是 `countryText` 的别名。
- `LocalJourneyStrings.text(_:language:)`（`LocalJourneyStrings.swift:5-30`）是独立的查找路径，每次调用都重建一个 18 项字典，并且不在 `AppStrings.contributors` 中。
- `NewTripStrings` 放在 `JourneyEditor/` 而不在 `Localization/`。
- 6 个 View 各自定义私有的 `text(_ key:)` 前缀函数：`NewTripView:1451`、`JourneyCompletionView:55`、`LocalLineServicesSection:16,88`、`RailwayRouteGuideView:504`、`LocalJourneyFillView:49`、`RailwayRouteCorrectionView:271`。
- 两个 `RideDraftValidation` 同名（App 与 AppL），需要写 `RailApplication.` 限定（`EditorValidation.swift:9,12,47`）。
- 目标：删除两个别名；`LocalJourneyStrings` 并入共享表（`ios.localFill.*`）；App 的同名类型改为 `RideDraftIssueText`。
- 影响：删约 100 行，去掉 1 条查找路径和每次调用的重建。

### A18【中】ChatGPT 会话状态机写了两遍

- `TrainResearchView.swift:14-27,219-250` 与 `JourneyCompletionView.swift:23-30,57,441-455` 各有 `auth/service/models/selectedModel/ownsLogin/currentService()/run/cancel/loadModels`。`Service` 实际总是传 `Auth.shared`，等于一个单例包装。
- 两个临时 `URLSession` 配置：`ChatGPTSubscriptionAuth.swift:58`、`ChatGPTSubscriptionService.swift:11-24`。
- 目标：一个 `@Observable ChatGPTSession`。
- 影响：删约 80 行。

### A19【中】图片分享 3 条路径，其中一条泄漏临时文件

- 分享合成器：`ImageRenderer` → `SharePNGWriter`（`ShareCardRendering.swift:364,376`），会清理旧的 `rail-statistics-*.png`（:382-392）。
- 单行程：CoreGraphics 手绘（`JourneyShareImage.swift:202-305`）→ `ActivitySheet`（:421）。它写入 `rail-journey-<UUID>.png`（:299），没有找到清理代码；切换类型、语言或重试都会重新渲染，因此会泄漏临时文件。
- 地图快照：`StatisticsMapSnapshot.render`（`StatisticsShareImage.swift:20-190`）。
- 目标：一个 `ShareArtifactWriter` 负责命名、写入和清理；统一使用一种分享方式。
- 影响：删约 60 行，修复临时文件泄漏。

### A20【中】RailCore 内部的重复基础设施

- ISO 日期解析写了 7 遍：
  - `Dates.isValidDateString`（`Core/Utilities/Dates.swift:132`）；
  - `TrainServicePatterns.GregorianDay`；
  - `TrainServiceBranding.normalizedDate/daysInMonth`；
  - `LineServiceCatalog.isDate`（:185）；
  - `TimetablePhysicalRouteMatch.gregorianDate`（:380）；
  - `RailHistory.isRealISODay`；
  - `TrainTimetableDatabase.validate/nextGregorianDay/weekdayColumn`（:565,1446,1461）。
  - 另有 `EditorTime.swift:198,211` 的 `daysInMonth/isLeapYear`，以及 App 的 `PassportStatistics.swift:372-388`。
  - 目标：一个 `Dates.parseISODay -> (y,m,d)?` 加 `weekday/addDays`，删约 120 行。
- 站名归一化有 3 种以上 fold：
  - `Stations.normalizeStationName`（`Stations.swift:382`）；
  - `SearchFold.fold`（`Utilities/SearchFold.swift:20`）；
  - `TransferGuide.Text.matchKey`（`TransferGuideText.swift:853`，自带一张ヶ/俱表）；
  - 以及 `TimetablePhysicalRouteMatch.folded`（:409）、`RecordedRouteMapping.sameStation`（:16）。
  - 目标：一个 `StationNameKey`。需要 golden test 护航。
- 站码别名闭包 `packageCodes.contains(c) ? c : aliases[c] ?? c` 复制了 3 次：`LocalJourneySearch.swift:75`、`RecordedRouteAdmission.swift:161`、`TripRoutePlanner.swift:73`。`StationCodeAliases.canonical` 是另一种同名规范化，在约 37 个比较点被惰性调用，而它的注释（`StationCodeAliases.swift:8-10`）声称在解码时已经应用。目标：在 `Stop` 解码边界规范化一次。
- 约 10 个手写“锁加静态字典”的 memo：
  - RailCore：`RailResourceRevisions`、`JapanThroughServices`（:428-440）、`LineServiceCatalog`（:141-153）、`TrainTimetableDatabase`（:691-705）、`Stations.identityIndexes`；
  - App：`EditorCatalogCache`、`RiddenRouteStore` 的三件套、`BundledRegistry`；
  - data-perf 新增的 `junctionRegistryCache`/`overlayByURLCache` 也属于此类。
  - 失败语义各不相同。另有 4 个 `RouteSolveLimiter(limit: 1)`，用于规避嵌套许可死锁。
  - 目标：RailCore 中一个 `BundledResourceMemo<Key, Value>`，只缓存成功结果，并对每个 key 的并发加载去重。
- 堆与图：3 份 min-heap（`RouteSolver.swift:4377`、`LocalJourneySearch.swift:398`，以及 `PhysicalRouteMatcher.swift:122-139` 的 O(n²) 数组扫描）。图/邻接构建有 4 种：`RouteGraph.build`、`LocalJourneySearch.buildGraph`、`StationIntervalResolver` 邻接、`RailwayRouteChoices.slices`。
  - 目标：先合并成一个通用堆（约 100 行）；`RailwayRouteChoices.choices` 并入 `LocalJourneySearch`（约 80 行）。合并图模型属于大重构，暂不建议。
- `rail-sections.json` 有两个解码类型：`Statistics.SectionFeatureCollection`（`Statistics.swift:576`）与 `RouteGraph.SectionFeatureCollection`（`RouteGraph.swift:3243`），各带一套 `SectionProperties`。
  - `Statistics.applyingHistoryOverlay`（:792-830）把 Section 转成 `RouteGraph.SectionFeature` 再转回，逐属性字符串化后重新 JSValue 化。
  - 目标：共享一个解码类型，history 直接作用其上，删约 50 行并省掉一次全量复制。
- `Statistics.allDates`（:2206）与 `Dates.allDates`（`Dates.swift:47`）重复。
- 区域列表 `["jp","tw","hk","mo","kr","cn"]` 字面量出现 8 次（如 `Stations.swift:62`、`Train.swift:886,912,1167,1830`）；`Region` 枚举在 App（`RegionCatalog.swift:52`），RailCore 全部用字符串。目标：把 `Region` 下沉到 RailCore。

### A21【中】`Train` 的 JSON 与类型化双实现（JS 移植遗留）

- 以下函数各有 JSON 形与类型化两个重载：
  - `validateTrain`（`Train.swift:1012` 与 :1019）；
  - `validateTrainStore`（:963 与 :991）；
  - `validateSupportedRegions`（:884 与 :910）；
  - `canonicalStopShape`（:1945 与 :1972）；
  - `recordDiagnostics`（:1028 与 :1049）。
- 生产代码只用类型化形式；JSON 形式服务 `ImportEngine` 和 bench。`canonicalStopShape(Stop)` 为了调用 `normalizeNullableTime`，经 `JSON.string` 绕了一圈（:1976-1981）。
- `RiddenRouteStore.swift:1296-1301` 把 `Train` 用 `.sortedKeys` 编码成 JSON，只为做 `JourneyWorkKey.request: Data`。
- 目标：在导入边界完成 JSON→Train 后，只保留类型化路径。
- 影响：估计删 600–900 行（`Train.swift` 共 2924 行）。需要 port fixture 一致性测试，风险中到高。

### A22【低】其余双实现

- 回放时长有两层：`PlaybackController.nativePlan`（:284-296）重算了 `seconds`，Core 的 `Playback.plan` 只留下 `trains/skipped`。`estimate`（:270）与 `start`（:417）在主线程各编译一次，没有缓存；`Playback.cacheKey`（`Playback.swift:1128`）只有测试使用。
- `ridden` 分类过滤：`RiddenCategoryVisibility.draws`（Core）与 `Statistics.riddenFeatureVisible`（:2309-2319，只有测试使用）。
- 两个导出器：`MergedStore.export`（:65-84，无缓存）与 `ExportCache.export`（:19-50）各自拼接 envelope。
- 三个几乎相同的“-2025.json 缺失”错误类型：`EditorCatalogLoadError`、`DisplayNetworkCache.MissingPackage`、`RailNetworkStore.LoadError`。
- `rail-history` 加载有 3 个入口；data-perf 已统一到 `RiddenRouteStore.cachedHistoryOverlay` **[data-perf 已处理]**。但缓存仍放在 App 的路线 store 中，应下沉为 `RailHistoryOverlay.bundled(country:)`，见 D1。
- `physical-rail-junctions.json` 在 `prepareSolverInputs`（:1513）与 `latestValidFrom`（:1864）各解码一次 **[data-perf 已处理]**。

---

## 3. 过度分层（只转发的层、单实现 protocol、无价值的间接）

| # | 链 / 层 | 证据 | 判定与目标 | 影响 |
|---|---|---|---|---|
| B1 | View → `RouteRepairSession` → `RouteRepairFlow` → `RouteRepair` → `RecordedRouteAdmission` → `LocalJourneySearch` | `AppL/Journeys/RouteRepairSession.swift`（38 行，`Task.detached` 加转发，`summary` 也是转发） | 删掉 `RouteRepairSession`，Core 提供 async 入口（见 A3） | -1 文件，-1 跳 |
| B2 | `RailCommandBridge`：Commands → `bridge.newJourney()` → `performNewJourney?()` → `installRailCommands` 闭包 → workspace 方法 | `RailMapApp.swift:106-165`、`RailWorkspaceView.swift:2110-2195`（约 85 行）；19 个闭包中只有 8 个有包装方法；24 个标题每次刷新都从 localization 复制；手机端快捷方式另写一份（:2547-2585） | 改为 `WorkspaceCommand` 枚举加一个 `perform(_:)`，标题在菜单处读取 | 删 100–130 行 |
| B3 | `MapSelectedStationSnapshotController` → `loadSelectedStationSnapshot` → `actor MapRideStationImportance` → `RailDisplayNetwork` | `App/Map/MapSelectedStationSnapshotController.swift`（86 行）、`MapRideStationImportance.swift`（75 行）；两层都按国家缓存同一个 Snapshot，后者还重新解码 manifest 和 history（:17-25），而 `RailNetworkStore` 已常驻这些数据 | 一个 `@MainActor` loader，注入 store 常驻的 manifest/history | 删约 60 行，少 1 次 manifest 和 history 解码 |
| B4 | `JourneyEditing` 被当作 store 句柄传给行和分组选择器 | `JourneyListRow.swift:64,85,95,155-174`、`JourneyGroupPicker.swift:134` 通过 `editing.itineraries.*` 访问 | 带回滚的提交改为 `ItineraryStore.replaceWithRollback`；行直接拿 store | -1 类型 |
| B5 | `JourneyBridge`（文件名叫 Bridge，只有 `routeState` 一个桥） | `JourneyPresentationBridge.swift:46-70`，唯一调用点 `RailWorkspaceView.swift:2342`；其余内容是 `JourneyActionAppearance` | `reason` 文案随状态一起由 resolver 生成；文件改名为 `JourneyActionAppearance.swift` | 去掉一个误导性的层 |
| B6 | 路线状态 4 级枚举：`RouteOutcome` → `RouteStatusEntry` → `RideRouteStatus` → `JourneyRouteState`，再在 Bridge 中补 reason | `Pres/Journeys/RouteStatusResolver.swift:61-157` | 合为 `RouteOutcome` 加 `RideRouteStatus`（携带呈现） | 删约 60 行，4 个枚举变 2 个 |
| B7 | `UtilityDestinationView` 只把 5 个依赖转交给 `DataManagerView`/`SettingsView`；`DataManagerView` 同时从参数和 environment 拿 `network` | `UtilityDestination.swift:64-111`、`DataManagerView.swift:20` | 叶子 View 统一从 environment 读取 | 少量 |
| B8 | store 双注入：参数加 environment | `AppShell.swift:103-110`；参数注入见 `PassportWorkspaceView.swift:32-34`、`DataImportView.swift:16`；environment 可选值见 `RideDetailView.swift:214-216`、`RideEditorView.swift:10-12`、`RouteLogoSquare.swift:43-44` | 叶子 View 用 environment，只在需要绑定处传参数 | 统一一种方式 |
| B9 | `VideoExportFlow`（91 行）：`plan` 转发 `estimate`；`start` 是 `persist` 加 `exporter.start`；`abandonRecording` 转发 `cancel`；工作区还绕过它直接访问 `videoExport.exporter/settings` | `VideoExportFlow.swift:51-87`、`RailWorkspaceView.swift:751,3554,3567,3611` | 并入 exporter | 删约 60 行 |
| B10 | `NetworkLOD` 中的 min-zoom 转发 | 见 A11 | 直接调用 policy | 见 A11 |
| B11 | `PanelDetentResolver`（192 行）没有 iOS 生产调用方；App 只用 `PanelDetent` 枚举（`RideSheet.swift:70,78`），且另有 `SheetStage` 表示同样的三档 | `Pres/Workspace/PanelDetentResolver.swift`、`RideSheet.swift:53,206` | 删除 resolver；`SheetStage` 自己定义 `next/higher/lower`，或直接用 `PanelDetent` | 删约 160 行 |
| B12 | `MapRebuildPolicy`（12 字段 init 只为算一个 Bool）、`MapDrawChanges`（14 个 Bool） | `Pres/Map/MapRebuildPolicy.swift:8-80`、`MapNetworkRendering.swift:27` | 改为纯函数 `shouldRebuild(current:, built:)` | 删约 60 行样板 |
| B13 | 参数袋重复：`RailMapView` 属性 → `Surface`（22 个）→ `Coordinator.update`（14 个），`pendingViewUpdate` 闭包里再重复一次 | `RailMapCoordinator.swift:237,256-270` | 一个 `MapDrawInput` 结构，diff 变成两个值的函数 | 删约 50 行 |
| B14 | 单实现 protocol：`PlaybackMapRendering`（只有 Coordinator 实现，`RailMapCoordinator.swift:52`）、`RouteGraph.DisplayLocatable`（只有 `Coordinate` 实现，`RouteGraph.swift:2679`） | — | 前者存在的理由是依赖方向（Playback 不依赖 Map），可改为闭包对；后者直接用具体类型 | 少量 |
| B15 | 单次使用的 static 包装：`LaunchJourneySelector.first`、`PickDuringRunRule.resolve`、`LongitudeArc.smallest`、`JourneyClock.today/isUpcoming/hasPassed/isTodayOrEarlier`（逐一转发给 `home`）、`MileageStatisticsStore.coverageReading/year(of:)/includes*`（包装 `StatisticsMembership`）、`LocalJourneySearch.choices`（`LocalJourneySearch.swift:40-61`，14 参数转发，无生产调用方） | 各文件 | 有独立测试价值的保留；纯转发的内联或删除 | 删约 100 行 |
| B16 | `WorkspaceDerived` 中 11 个手写 memo 槽加 8 个 key 结构 | `WorkspaceDerived.swift:65-410` | 一个泛型 `Memo<Key, Value>` | 约 200 行降到约 80 行 |
| B17 | RailKit 三 target 的划分 | RailApplication 只有 6 个类型、约 800 行，与 RailPresentation 互不依赖；而像用例的 `StatisticsMembership`、`WorkspaceJourneyRules` 反而放在 RailPresentation | RailCore 边界（编译器强制不依赖 UIKit/SwiftUI）有价值，保留。RailApplication 与 RailPresentation 的拆分不划算：先完成 D 节的下沉，再考虑合并为一个 target | 构建文件 -1 target |

---

## 4. 跨层数据重复传递、转换、复制、重解码、重派生

这里按四条最热的数据流组织。四条链路均由 Opus 代理逐跳追踪。

### 4.1 启动 → 行程列表

链路：
`AppShell.swift:155` `ItineraryStore.load` → `RideLibrary.savedStore()` → `store` → `regroup`/`group(store:)`（`ItineraryStore.swift:919-951`）→ `Loaded{trains（排序副本）, days, regions}` → `WorkspaceDerived.days`（:84）→ `WorkspaceJourneyRules.filteredDays` → 每行 `presentation(for:)`（`RailWorkspaceView.swift:2339`）→ `JourneyBridge.routeState` → `RiddenRouteStore.status` → `RouteStatusResolver` → 4 级枚举 → `JourneyPresentationResolver.selected` → `JourneyListRow`。

| # | 问题 | 证据 | 目标 | 状态 |
|---|---|---|---|---|
| C1【中高】 | `ItineraryStore` 持有两份工作集（`store.trains` 为编辑顺序，`loaded.trains` 为排序副本，另有 `days` 分桶），每次改动都整体重建。读方混用两者：`orderedJourneyGroups:150` 和 `JourneyEditing` 读 `store`，其余读 `loaded`。重组期间两者不一致，`reassertingSelection`（:889）就是为此打的补丁 | `ItineraryStore.swift:150,388-391,621,889,919-951` | 一个不可变 `WorkingSet{trains, sortedOrder, days, ids, pendingIDs, groups, indexByID}`，一次遍历构建、一次发布 | data-perf 缓存了 `orderedJourneyGroups`、加速了排序 **[data-perf 已处理一部分]**；双工作集本身无人处理 |
| C2【中】 | 每次编辑对整个 store 校验 3 次（`mutate:627`、`RideLibrary.saveResult:258`、`RideStorage.writeStore:186`，加上解码、加载和合并时）。`replace`（:233）又跳过了 `mutate` 的全量检查，两条路径不一致。区域支持在 3 处检查（`replace:234`、`add:274`、`mutate:621`）；ID 冲突检查两次（`RideDraftValidation.idTaken` 与 `replace` 的 `savedKeepingID` :244-250） | 同左 | 只在变更边界校验变更的记录；`writeStore` 接收 `ValidatedStore` | **[data-perf 建议 #9 未实现]** |
| C3【中】 | 每行在每次 body 求值时计算 `presentation(for:)`，并且每行都读 `selectedTrainID`（`JourneyListRow.swift:64`），所以任何选择变化都会让所有行重算 | `RailWorkspaceView.swift:2579-2588` | 传入 `isSelected: Bool`；presentation 按 `(id, revision)` 由 store 记忆 | 无人处理 |
| C4【中】 | `presentation(for:)` 闭包被逐层传递约 9 处（`PassportWorkspaceView` → `StatisticsDashboardContent`、`WorkspaceJourneyMenu`、`RideChooserView`、列表行，如 :765、:778、:1167），而它依赖的 4 个对象本来就在 environment 中 | `RailWorkspaceView.swift:2339` | 一个放在 environment 的 `JourneyPresentationProvider` | 无人处理 |
| C5【低】 | `WorkspaceDerived.passportScope` 做了两次恒等 map：`Loaded.Day` 就是 `typealias JourneyDay`（`ItineraryStore.swift:53`），却在 `WorkspaceDerived.swift:385,388` 来回映射，每次缓存未命中复制两次数组，并且破坏下游 `ArrayGeneration` 的缓冲区同一性。`StatisticsDashboardContent.swift:1424` 又把结果包成新的 `Loaded` | 已复核 | 删除两次 map | 无人处理，可立即做 |

### 4.2 行程 → 路线解析 → 地图

链路：
`AppShell.swift:161` `.task(id: routeLoadKey)`（键为整个 `[Train]`，:296）→ `RiddenRouteStore.load`（:303）→ 逐程比较 `completedInputs[id] == train` → `decode` → 磁盘缓存、求解器或预计算数据集 → `drawnRide()`（:1086，复制颜色、显隐、停站）→ `visibleRides` → `WorkspaceDerived.rides(scopedTo:)`（:291）→ `RailMapView.updateUIView`（:464）→ `Coordinator.update`（:237，逐程拼签名 :280-285）→ `rebuild` → `MapLineGeometry.prepare/materialize` → `ContinuousStroke.slice` → `MKMapPoint` → `CLLocationCoordinate2D`。点击和回放时再转回 `Coordinate`。

| # | 问题 | 证据 | 目标 | 状态 |
|---|---|---|---|---|
| C6【高】 | 每程做两次车站推断：`hasAmbiguousStationChoice`（`RideRouteResolution.swift:160`）与 `resolve`（:200）各调一次 `RouteSolver.inferStationSections`；`RiddenRouteStore.inferenceIsAmbiguous`（:1432）为此重新构造一个 `RideRouteResolution`；`CacheKeyTrain` 和 `allowedInstitutionTypeCodes` 也各建两次（:162、:192-199） | 同左 | `resolve` 返回值携带歧义标记，删除独立查询 | 无人处理 |
| C7【中】 | `canonicalRouteInput`（`normalizeExportTrain` 加时刻表匹配）在 `RiddenRouteStore.swift:940,1277,1683,1741,2146` 共 6 处按阶段重算；`routeCacheDigest` 在 :967、:1279、:1685、:1772、:2149 重算 | 同左 | 每程每次 decode 只算一次 `CanonicalRouteInput` 加 digest，并逐阶段传递（`providedCanonicalInputs` 已在其中一条路径上传递） | 无人处理 |
| C8【高·性能】 | 每次 rebuild 把行程扫描 2–3 遍：`prepareNetworkGeometry`（`RailMapCoordinator.swift:1038-1081`）做 `NetworkLOD.select` 加 byID 字典加逐段扫描；`rebuild()` 重做 `select`（:1311）、`linesByStrokeID`（:1350）和同样的扫描（:1371-1382）；异步准备完成后再次进入 rebuild | 同左 | 一个 `NeededGeometry{selected, neededChains, selectedChains}`，按（frame key、selection）缓存 | 无人处理 |
| C9【高·性能】 | 每次标签 pass（包括平移中的 moving pass）都通过 `buildMarkers`（:1957）重派生全站数据：`Dictionary(grouping: stations)`（:2023）、`connectionsByPlace`（:2156）、`linesByStrokeID`（:2026）、`installedStationCoordinates`（:2002）、`ridesDigest` 重哈希所有停站（:2133）；`stations.compactMap` 在视口裁剪完成前就做了 `era.shows`、字符串键和本地化（:2585）；每站每锚点新建 `CLLocation`（:31-48） | 同左 | `stations` 变化时预建 `StationIndex{byPlace, connections, terminals}`；`linesByStrokeID` 按 `linesGeneration` 缓存；可见站用空间索引 | **[data-perf 建议 #4 未实现]** |
| C10【中】 | 每次 camera 回调至少算 3 次 zoom（`MapProjection.zoomLevel` 两次 convert），调用点有 :866、:812、:902、:1243、:3931、:3906，以及 `rendererFor` 每个渲染器两次（:4148,4153）；`hasLanedLines`（:1265）和 `strokeBucketPending`（:3914）每次扫描全部线路 | 同左 | 一个 `CameraSample`（见 A12）；一个按 `linesGeneration` 缓存的标志 | 无人处理 |
| C11【中】 | 显示数据的镜像结构：`RailDisplayNetworkFile.LineFragment`（:312）→ `DrawnLine`（:1459-1586）；坐标 `[[Double]]` → `Coordinate` → 数据基准偏移副本；`DrawnSegment` 存 3 份坐标数组，cn 下是 3 份真副本 | `RailNetworkStore.swift:1459-1586`、`AppleMapDatum.swift:71` | `Coordinate` 直接 Decodable；只保留一份坐标数组，加按需计算的偏移 | 无人处理 |
| C12【低】 | 构建矩形有损往返：`onBuildRect` 把 `buildRect` 交给 store，store 在 `RailNetworkStore.swift:908` 用 `padding/(1+2·padding)` 反推可见矩形 | 同左 | 直接传 `visibleRect` | 无人处理 |
| C13【低】 | 只写不读的状态：`minZoomByLineId`（`RailMapCoordinator.swift:78`，在 :400 每次线路变化时 O(lines) 构建，从未读取，已复核）；`preservesCameraDuringResize`（:818） | 已复核 | 删除 | 可立即做 |

### 4.3 行程 → 统计 → 仪表盘/分享

链路：
`AppShell.swift:194` `.task(id: StatisticsLoadTrigger)` → `MileageStatisticsStore.load(scope:)`（:323，重做 `scope.filter` 和 `slice`）→ `fingerprint`（:849，在主线程遍历所有停站）→ `matchRides`（:743，`DrawnRide` → `MileageMatching.Journey`）→ `Statistics.buildMileageStatsView`（Core）加 `PassportStatistics.build`（App）。并行地，`WorkspaceDerived.statisticsScope`、`passportScope` 和分享侧各自再切一次。

| # | 问题 | 证据 | 目标 | 状态 |
|---|---|---|---|---|
| C14【高】 | 范围切片 4–6 次 | 见 A2 | 见 A2 | 见 A2 |
| C15【高·性能】 | 统计加载路径上有 4 种键：`AppShell.StatisticsLoadKey`（含整个 trains 和 ride 列表，:315-345）、`Fingerprint`/`entryDigest`/`passportDigest`（:849-980）、`MileageMatching.CachedEntry.digest`，以及分享侧手拼的 `statisticsInputKey/loadKey/renderKey/computationIdentity/inheritedStoreKey`。`scopeWork`（`ShareComposerView.swift:908`）在 body 中被读 5 次以上 | 同左 | 一个 `StatisticsRevision: Int`，由 store generation 和 rides generation 决定；`scopeWork` 按 generation 记忆 | `AppShell` 键 **[data-perf 已处理]**；其余无人处理 |
| C16【中】 | `ShareComposerModel` 为每个范围和每张自定义日期卡新建一个 `MileageStatisticsStore`（:348-352、:544、:570、:583），每个都完整执行 load、匹配和 entryCache | 同左 | 按 `(countries, leaves)` 共享一个匹配上下文 | 无人处理 |
| C17【中】 | 统计在部分行程陆续到达时反复重载；`fingerprint` 和 `slice` 在主线程同步执行 | `AppShell` 的 task id 加 `MileageStatisticsStore.load` | 加载中防抖或闸门；把 `fingerprint` 移进 task | **[data-perf 建议 #2 未实现]** |
| C18【中】 | `EdgeIndexCache` 只有一个槽，在多国范围下统计与 `TraversedLineDetector` 互相驱逐 | `EdgeIndexCache.swift:15` | 检测器复用 `CategoryIndexes.byCountry`，或改为两槽缓存 | **[data-perf 建议 #1 未实现]** |
| C19【低】 | `MileageMatching.Result.trains` 原样回传输入；`renderRecordTicket`（`ShareCardRendering.swift:~329`）不用传入的 `trains`，重新读 `itineraries.store?.trains ?? loaded?.trains`；`widgetJourneyDetail` 每行做一次 `trains.first(where:)`（`MileageStatisticsStore.swift:1100`） | 同左 | 删除回传；直接用参数；建 id 索引 | 无人处理 |

### 4.4 编辑一程 → 保存 → 地图和统计刷新

链路：
`RideEditorView` 的 `@State draft` → `.onChange`（:324）→ `revalidate`（:1747）→ App 的 `RideDraftValidation`（`EditorValidation.swift:46`）→ AppL 的 `RideDraftValidation.issues` → 再包装为 App 的 `RideDraftIssue`。保存：`JourneyEditing.replaceAndPersist`（:62）→ `ItineraryStore.replace`（:237，再查区域和 ID）→ `commitWorkingSet` → `RideLibrary` → `publishRecordIndex`（重建两个集合）→ `regroup`（全量排序和分桶）。之后 `loaded.trains` 变化 → `routeLoadKey` 变化 → 走 4.2；统计键变化 → 走 4.3 的全量 fingerprint。

| # | 问题 | 证据 | 目标 | 状态 |
|---|---|---|---|---|
| C20【高·性能】 | 保存一程是 O(N) 且常数很大：`RideStorage.writeStore`（:183-195）对每个 train 执行 `upgradeOnce`（与 `upgradeOutputs` 深度比较 `Train !=`，并保留第二份 `[String: Train]`），然后全量校验；`ExportCache.export`（`MergedStore.swift:19`）为了比对缓存，对每个 train 构建 `StoreOperations.json(train)`，所以缓存只省掉了字符串化，没省掉 JSON 树构建；最后从磁盘读回旧文件逐字节比较，再整体原子写入 | 同左 | 缓存按每个 train 的 revision 建键；在内存中与上次写入的字节比较，不再读盘。ADR 0005 只要求原子、有序写入，这样仍然满足 | 无人处理（需按实际 N 测量） |
| C21【中】 | 保存入口不统一：多数走带回滚的 `JourneyEditing.replaceAndPersist`；`RailWorkspaceView.swift:2609`（`setRidden`）、:477（add）、`TransferGuideImport.swift:370` 直接调用 store，没有回滚 | 同左 | 所有写入走一个入口，即 `ItineraryStore.replaceWithRollback`（见 B4） | 无人处理 |
| C22【低】 | `NewTripView` 的提交在 `commit()` 中用相同参数调用 `RideDraftValidation.issues(...).blocking` 两次（:1298、:1309）；时钟文本手写（`clock/extraDays` :1419-1441），而 `EditorTime.confirmPicker/canonical`（`Core/Editor/EditorTime.swift:77-110`）已有同样功能 | 同左 | 一个 `DraftCommit.finalize(draft, originalID:, existingIDs:) -> Result<Train, [Issue]>`；时间文本走 `EditorTime` | **[add-trip 涉及]**，并入其重做 |

---

## 5. 分层位置错误

| # | 内容 | 证据 | 目标位置 |
|---|---|---|---|
| D1【高】 | `RiddenRouteStore`（2813 行）承载了领域逻辑：`prepareSolverInputs`（:1479-1522）；历史子系统（`historyState`、`latestValidFrom` :1825-1876、`retiredStations`、`applyRailHistory`、`routeCacheDigest`、`routeTemplateDigest`）；预计算分片解码器（:2330-2520）与 `datasetRides` 的准入逻辑（RailCore 已有 `DatasetManifestIndex`、`PrecomputedRouteDisplay`、`RailPrecomputedRouteGate`，格式被拆在两个模块）；磁盘 `RuntimeCache` 格式（:2412-2500）。另外 `NewTripView.swift:1213` 由 View 调用路线 store 的 static `latestValidFrom` | 同左 | RailCore `SolverResourceLoader`/`RouteResolutionCache`。App 只保留 `DrawnRide`/MapKit 和 `@Observable` 状态。约 1000 行可下沉并可用 `swift test` 测试。data-perf 新增的两个 static 缓存也应随之下沉 |
| D2【高】 | 显示路网的格式规范与解码器在 App（`RailDisplayNetworkFormats.swift` 加 `RailDisplayNetwork.swift`，约 1100 行）。代价已经出现：`RailNetworkStore.swift:~1680` 因为 “RailCore cannot import it” 只能传原始 map。`NetworkLOD`（`Map/`）被数据层（`RailNetworkStore`、`RailDisplayNetworkFormats`）引用，依赖方向反了 | 同左 | RailCore `DisplayNetworkFormat`（manifest、index、chunk 校验、history）；MapKit 转换作为 App 侧的薄扩展；LOD 规则放 RailPresentation |
| D3【高】 | `RailWorkspaceView`（3669 行，约 45 个 `@State`）承担业务编排：`commitJourneyEditor`（:973-1040）、路线修复（A3）、`selectFromMap/pick/yieldRun` 与选择租约（:3354-3412）、`launchExtent`（:1603-1635） | 同左 | 一个 `@MainActor WorkspaceModel`（选择、编辑器、修复、对话框）。`launchExtent` 放到 RailPresentation 的 `LaunchJourneySelector` 旁。View 目标约 1500 行 |
| D4【高】 | `RailMapCoordinator`（4276 行，`buildMarkers` 约 850 行，`rebuild` 约 650 行，50 多个私有 var，58 个 `#if DEBUG`）是上帝对象。标签选举规则（:2610-2616 排序、:2046-2062 名称合并、:2150-2300 ride 点和标签选举）离不开活的 map view，无法单测 | 同左 | 规则移到 RailPresentation（已有 `StationLabelVisibility` 可承接）。Coordinator 拆为 NetworkGeometryPhase、MarkerElection、RideOverlays、Selection、DebugHooks |
| D5【中】 | 纯领域统计在 App：`PassportStatistics`（390 行，只依赖 Foundation/RailCore/RailPresentation）；`MileageStatisticsStore` 的 fingerprint、digest、`fullDistanceKnown`（约 250 行）；`StatisticsScope` 的纯集合部分（`StatisticsArea.swift:48-128`）；`EdgeIndexCache.merge/appendingVector`（:129-224、:301-370）。`MileageStatisticsStore` 共 1375 行、6 种职责（选择状态、任务编排、指纹、`DrawnRide` 适配、约 250 行本地化小组件格式化、车票内容） | 同左 | 统计切片和指纹放 RailApplication（或合并后的 target）；小组件和车票格式化放 RailPresentation；边索引扩展放 `Statistics`。这也是 A2 产生手写副本的根因 |
| D6【中】 | RailCore 中的呈现规则：`StationDisplay.PopupModel/Naming/PopupRow`（`StationDisplay.swift:304-520`）；`Statistics.MileageStatsView/DailyStats/Category.i18n`（含恒等 `dateLabel` 闭包）；`RegistryStationDisplay` 的 primary/caption；`StationLabel` 的 11 个文本构造器（约 313 行）；`RouteRepairFlow.summary` 生成带本地化键的用户文案（`RouteRepairFlow.swift:95-108`）；`ImportEngine.MessageKey`/`Event.progressBar`（:103-145）；回放相机追踪（`Playback.swift:741-890`） | 同左 | 移到 RailPresentation，App 已自建的则删除。注意：有 Web 一致性 fixture 约束的部分需保留 parity |
| D7【中】 | RailPresentation 中的领域规则：`RegionClock/JourneyClock`（时区算术，见 A1）、`RegionScopeRule`（由站码推区域）、`StatisticsMembership.slice`、`RouteStatusResolver`、`DisplayNetworkEra`。区域解析共有 5 种形式（`RegionScopeRule.matched`、App 的 `Region.matched/resolved`、`RegionCodeIndex`、`SolverRegistryInput.regionCode`、`RegistryIdentityUpgrade.lookupRegion`） | 同左 | 时区表、区域规则和 `Region` 下沉到 RailCore |
| D8【中】 | RailApplication 中应属 RailCore 的领域校验：`RideDraftValidation` 与 `TrainValidation.recordDiagnostics`（`Train.swift:1049`）分处两个 target；`TripRouteValidation` 只有一个调用方。另外 App 的 `JourneyDraftWork`（`JourneyEditing.swift:113-137`）和 `TravelDirection.infer` 加 `saveDraft`（`RideEditorView.swift:1939-1952`）写在 View 里 | 同左 | 记录级规则放 RailCore；草稿组装放 RailApplication |
| D9【中】 | `Design/` 访问 store：`RouteLogoSquare`（`Design/RouteLogoSquare.swift:43-70`）从 environment 读 3 个 store，并写死 JR East 路径前缀（:96）；`OperatorBadge`（:18-257）做图片解码和测量 | 同左 | Design 原语只接收 `(path, color, side)`，行程到徽标的解析移到 `JourneyBranding` |
| D10【低】 | 地图 chrome 的布局算术：`railFade/railPresent/transportLift` 在 `ResidentMapChrome.body`（:43-52）和 `wideMapSurface`（`RailWorkspaceView.swift:2279-2296`）各写一遍；`railHeight/playbackBarHeight` 的 preference 处理复制 3 次，`@State` 在两处各有一份；`controller.*Obstruction` 从 5 个地方写入。`BottomChromeMetrics`（`BottomChrome.swift:36-224`）是纯 CGFloat 算术 | 同左 | 纯值 `MapChromeLayout`，与 `BottomChromeMetrics` 一起放 RailPresentation，与 `WorkspaceLayoutPolicy` 并列以便单测 |
| D11【低】 | 两个相机写入者：回放直接 `setVisibleMapRect`（`MapPlaybackLayer.swift:276`），其余都经 `controller.fit`。`StationCardView/RailwayLineCardView` 在 `.task` 中直接取数 | 同左 | 相机统一经 controller 写入 |

---

## 6. 死代码与仅测试使用的公开 API（低风险、可立即删除）

均经 grep 确认无生产调用方；带 ✔ 的由主会话复核。删除前需再 grep 一次，包括 UITests、`#if` 分支和 `RAIL_DIAGNOSTICS`。

| 符号 | 位置 | 约行数 |
|---|---|---|
| ✔ `RiddenRouteStore.solveMissingConcurrently`、`JourneyWorkQueue`、`IndexedJourneyResult`、`maximumJourneyWorkers` | `RiddenRouteStore.swift:1365-1704` | 110 |
| `awaitScopeRegistry`（恒定返回 `[]`，使 :1281、:1736 的 `skipped` 失效） | `RiddenRouteStore.swift:1974` | 20 |
| ✔ `WorkspaceRideDetailView` | `RideDetailView.swift:26-72` | 47 |
| ✔ `ArrivingJourneyCard`、`RideRoute` | `RideSheet.swift:18-50,165-215` | 85 |
| ✔ `PanelDetentResolver` | `Pres/Workspace/PanelDetentResolver.swift` | 160 |
| ✔ `RailInterpolatedFont`/`railInterpolatedFont`、`RailMotion.reduced` | `RailMotion.swift:232-258` | 30 |
| `availableDates(_:region:)` | `RailWorkspaceView.swift:3140-3146` | 7 |
| ✔ `minZoomByLineId`（只写）、`preservesCameraDuringResize` | `RailMapCoordinator.swift:78,400,818` | 10 |
| `RailNetworkStore.stations(in:)` 与 `stationsByRegion` | `RailNetworkStore.swift:1587` | 30 |
| ✔ `Statistics.riddenFeatureVisible`；`markerCategoryForStation`（:418）；`isRetiredNetworkEdge`（:779）；字符串版 `edgeKey`（:448） | `Statistics.swift` | 60 |
| `Stations.Readings` | `Stations.swift:1028-1081` | 55 |
| `BundledRegistry.DecodeCache.lookup/identity(region:load:)`（与静态 `identity(for:)` 是两个解码器） | `BundledRegistry.swift:~20-45` | 30 |
| `ImportEngine` 的 sample/part API（`acceptedManifest`、`sampleManifestDates`、`sampleParts`、`sampleLoad`、`seedAction`、`acceptPart`、`prefetchIndices`、`replaceTrainStoreFromParts/FromStore`） | `ImportEngine.swift:555-931` | 250（需先查 fixture harness） |
| `LocalJourneySearch.choices` | `LocalJourneySearch.swift:40-61` | 25 |
| `DraftMapSnapshot.snapshot`（只调用 init） | `Pres/Editing/DraftMapSnapshot.swift:53-57` | 5 |
| `CompactPackage.load`、`LineTopology.byLineID(contentsOf:)` | `Core/Data/CompactPackage.swift:304`、`Core/Rendering/DisplayParts.swift:281` | 30 |
| `ShareComposerView.scopedTrains`（只在 DEBUG 使用） | `ShareComposerView.swift:880-888` | 10 |
| DEBUG 原型 `MapIndependentRailPrototype`（667 行）在 Map 生产路径上有 19 个 hook | 如 `RailMapCoordinator.swift:1206,3443,4125`、`RailMapView.swift:459` | hook 收拢到一个 DebugHooks |
| `DisplayNetworkCache` 的测试 hook（`forcedFailures`、`blockNextLoad`、`testing*`） | `DisplayNetworkCache.swift` | 60（移到测试替身） |

合计约 1200 行。

---

## 7. 推荐修改顺序

原则：
- 先删除再合并，先合并再下沉；
- 先做与并行分支无冲突的，等对应分支合并后再动它们的文件；
- 每步都是能单独审查的 A→B 变更；
- 按 `ios/VERIFICATION.md`，只跑受影响范围的现有测试或一次共享增量构建。

| 阶段 | 内容 | 前置 | 预计收益 |
|---|---|---|---|
| **P0 立即（无冲突）** | §6 死代码；C5 恒等 map；A10 调和器单实现；A17 字符串别名；A12 中 `rendererFor` 的重复分支 | 无 | 约 -1300 行，零行为变化 |
| **P1 正确性** | A1 乘车时长统一（`RegionZone` 下沉 RailCore）；A4 中 `guardedFallback` 的去留（先改 ADR 0007，再改代码）；A19 临时文件泄漏 | 无 | 消除用户可见的不一致和泄漏 |
| **P2 统计数据流** | A2/C14 单一 `StatisticsSlice`；C15 单一 `StatisticsRevision`；A13 卡片 row-model 合一；D5 把 `PassportStatistics`/指纹下沉 | data-perf 合并（它改了 `WorkspaceDerived`、`PassportWorkspaceView`、`AppShell`） | 约 -400 行，搬约 650 行到可测模块；每次统计或分享 body 少 3–5 次 O(N) |
| **P3 行程身份与工作集** | A5 `routeDigest` 加 `ridesGeneration`，样式编辑不再重解；C1 单一 `WorkingSet`；C2 只校验变更记录；C20 保存路径去掉逐条 JSON 树和读盘 | data-perf 合并（它改了 `ItineraryStore`、`RiddenRouteStore`） | 编辑从 3 次 O(N) 加排序降到 1 次；改颜色或显隐不触发几何重建 |
| **P4 路线修复与编辑** | A3 修复流程合一（删除 `RouteRepairSession`）；C21 统一写入入口；B4 `JourneyEditing` 并入 store；A8 站名解析合一；C22 `DraftCommit` | add-trip 合并（`NewTripView`） | 约 -350 行，减少 3 个类型 |
| **P5 地图** | A6 一次切片 `RideDrawnStroke`；C8 `NeededGeometry`；C9 `StationIndex`；A12/C10 `CameraSample`；A11 min-zoom 合一；B3 快照 loader 合一；D4 拆分 Coordinator | data-perf 合并（`RailMapCoordinator`）；add-trip 的 `TripRouteGeometry` 先对齐切片源 | 平移和缩放的标签 pass 去掉全站重派生；rebuild 少 1–2 次全程扫描；约 -400 行 |
| **P6 数据层下沉** | A7 删除整包绘图管线、徽标改读 manifest；D1 把 `RiddenRouteStore` 领域部分（约 1000 行）下沉 RailCore；D2 把显示路网格式下沉；A20 `BundledResourceMemo`、ISO 日期、`Region` 下沉；A9 身份注册表单 provider、运营者单路径 | P3 完成；ADR 0013 进度确认 | 冷启动少一次 9 MB 扫描和一次整区解码；约 -800 行，搬约 2000 行到可测模块 |
| **P7 外壳与样式** | D3 `WorkspaceModel`；B2 命令枚举；A16 提示、偏好、按钮、token 统一；A15 工作区重复规则；B16 泛型 Memo | ui-reorg 合并（`SettingsView`、`RailWorkspaceView`、`PrimaryTab`、`WorkspacePanelActions`） | 约 -600 行 |
| **P8 大重构（需单独立项）** | A21 `Train` JSON 双实现；A4 两代求解合一；A20 图模型和堆合一；A14 导入单趟；B17 合并 RailApplication 与 RailPresentation | P0–P6 完成，port fixture 一致性测试 | 约 -1500 行；导入大文件耗时减半 |

总量粗估：可删约 5000–6000 行，可下沉约 3000 行到 RailKit（变为可用 `swift test` 测试），可合并接口或类型约 25 个。性能收益集中在 P3、P5 和 P6，均未实测，需在实施时用现有 bench 或 `ContinuousClock` 度量。

## 8. 不确定与未覆盖

- 性能结论都来自读代码，未做 profile。data-perf 的实测是在高负载主机上得到的，只能作比例参考。
- 未逐行读完的大文件：`RouteSolver`（4423 行，“无直线弦合成”的结论基于 grep）、`RouteGraph`、`Train.swift` 的 JSON 部分、`MapLineGeometry`、`StatsWidgetView`、`PassportTicketFace`、`TransferGuide*`、`JourneyCompletion`。
- A7：需确认 manifest 能覆盖 `RouteBadgeIndex` 所需的 art/`isLoop`，以及 `EditorCatalog` 能满足换乘指南的日本站匹配。
- A14：需验证 Preflight 的 Report 与 Staging 的 Snapshot 在改名和 ID 结果上一致。
- A11、A20、D6：部分重复是为了 Web/JS 一致性有意保留的（代码注释已说明）。合并前必须以 `node app/scripts/build/build-port-fixtures.mjs --check` 和 `FixtureParityTests` 为准。data-perf 报告指出 `FixtureParityTests` 中 “group totals drive visibility” 在其工作区已失败 7 条，`reviewed-station-renames-2019.json` 缺失，因此基线本身需要先修复。
- D7 中的旧/新格式（v2/v3 显示路网、`train-store-<region>.json` 折叠、`backup.json` 对、N02 与 vector 边、`allowLegacy` 预计算数据集）都仍然有效。迁移是单向的，建议按日期门控删除，不建议直接删。
- add-trip 分支是未提交的工作区状态，合并时 `NewTripView` 的行号会变化；A8(5)、C22 需按合并后的代码重新定位。
- `docs/reference/function-interface-map.md` 中指向 `docs/reports/…` 的链接是死链，建议在下一次文档维护时修正。
