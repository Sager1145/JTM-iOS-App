# Xcode 与 Swift 源码结构

2026-10-10 本次整理以当前工作副本为基础。主应用 173 个原始 Swift 文件、RailKit 120 个原始 Swift 文件和三个诊断应用的生产 Swift 都纳入了结构检查；拆分后主应用和 RailKit 共 333 个生产 Swift 文件。声明、函数数量和文件职责清单也包含原生回归测试，见 [逐文件清单](reviews/source-structure-inventory.md)。这是组织、命名、注释和抽取边界审查，不是每个函数的完整逻辑正确性、运行时或性能证明。

## 工程入口

更新于 2026-10-17：打开 `ios/JTM.xcworkspace` 可访问 RailMap 和统一的 RailDiagnostics。主应用单独打开 `ios/RailMap.xcodeproj` 仍可工作。当前功能、interface、implementation 与待收敛项见[实际接口归属表](../../docs/reference/function-interface-map.md)；下方 2026-10-10 的拆分数量与验证结果是历史记录。

| 产品 | 正式路径 | 依赖 |
|---|---|---|
| RailMap | `ios/RailMap.xcodeproj` | RailKit；文件系统同步 `RailMap/` 和 `RailMapUITests/` |
| RailDiagnostics | `ios/auxiliary/RailDiagnostics/RailDiagnostics.xcodeproj` | RailKit、InspectionKit、WorkbenchCore；统一编译原三个工作区及共享原生实现，使用 RAIL_DIAGNOSTICS 编译条件 |

诊断应用不并入 RailMap 发布 target。原三个工作区的目录保留为内部 implementation，独立工程入口已退役；统一 XcodeGen 配置在 `ios/auxiliary/RailDiagnostics/project.yml`。最终构建、原生观察与已安装旧副本清理进度见统一诊断 App 的设计/证据记录，不以工程合并宣称全部运行验收完成。

## 主应用文件归属

| 目录 | 职责 |
|---|---|
| App | App 入口、AppShell 和共享依赖生命周期 |
| Workspace | RailWorkspaceView、导航、面板状态和呈现 |
| Journeys | 行程列表、详情、身份桥接与记录状态 |
| JourneyEditor | 行程编辑、站点选择、字段组件、补全与路线修复 |
| Map | MapKit 桥接、协调器、几何、标签、标注和渲染 |
| Statistics | Passport 页面、统计与票面样式 |
| Sharing | 分享画布、拖放、统计卡片身份与快照 |
| Playback | 播放控制、运输栏与视频导出 |
| Timetable | 时刻表匹配、服务区间和选择界面 |
| Import | 文件读取、导入预检、OCR 和数据管理 |
| Infrastructure/Network | 网络载入、目录、缓存和原生站点查询 |
| Infrastructure/Persistence | 持久化队列、资料库、路线载入及其证据 |
| Infrastructure/Subscription | 订阅认证与 HTTP 服务 |
| Infrastructure | 跨功能平台适配小工具 |
| Design | 通用视觉组件、样式、色彩、动效和字体范围策略 |
| Localization | 文案与本地化规则 |
| Settings | 显示设置与设置页面 |
| Diagnostics | 主应用的诊断／测试界面与探针 |

`source-ownership.json` 是逐文件的责任清单，不是需要按顺序执行的验证流水线。新文件必须加入对应责任组。已退役 verify 命令从该清单中移除；剩余 native tests 只有在具体变更需要时才运行。

## 本次职责拆分与命名

- 原 `ContentView.swift` 实际承载 RailWorkspaceView，现命名为 `Workspace/RailWorkspaceView.swift`。`AppShell.swift` 的顶层类型也统一命名为 AppShell。
- `RailMapView.swift` 保留 SwiftUI／UIViewRepresentable 桥接；`RailMapCoordinator.swift` 通过 extension 保留 `RailMapView.Surface.Coordinator` 的原有类型身份、delegate 协议和生命周期。私有坐标辅助函数随协调器移动。
- 原 `RailMapAnnotations.swift` 分成播放标注、站点标注、行程标签、乘车站点 overlay、标注协调器和两类标注视图。MapAnnotationReconciler 保持 @MainActor。
- RideEditorView 保留草稿与提交状态；字段、站点选择、停站编辑、路线／策略／服务区间编辑、AI 门控和 package cache 分为独立文件。只把明确跨文件使用的 15 个顶层 private 类型改为 internal；类型内部的私有实现保持私有。
- 工作区中的 JourneyEditorLaunch、ScrollableIfNeeded、Coordinate→CoreLocation、Duration→milliseconds、AppTypographyPolicy 分别归入其所属职责。RouteRepairGuide 与 RouteRepairFlow 同文件。
- `StatisticsView.swift` 实际主要声明 StatisticsDashboardContent，现使用对应文件名；StatisticsCardKind 放入 Sharing。
- 时刻表详情与研究、线路纠正与本地服务浏览、统计文案、站点别名载入、品牌和 badge 索引、显示网络格式，以及诊断探针从混合文件中独立出来。编辑器 4 处可选文本绑定和 2 处逗号列表绑定使用 EditorBindings 的同一实现，保留专用端点／方向 setter 的副作用。
- RailKit 内部按领域分类。`Import.swift`、`RouteFeature.swift`、`RegionScope.swift`、`StationLineSelection.swift` 分别改为 ImportEngine、RouteNetwork、RegionScopeRule、JourneyDraftSelection 文件名；public 类型和 API 不因文件移动而改名。
- RailKit 的 EditorAIEligibility、JourneyClock 和 CatalogLinePreferenceMapping 从无关责任中拆出，见 [RailKit 审查](reviews/source-structure-railkit-review.md)。`JourneyDraftEdits` 已删除；行程编辑留在 `RideEditorView`。

## 函数与注释规则

一个文件可以包含紧密协作的模型／视图／私有 helper，不要求每个小类型都独占文件。文件名采用主要类型或明确的领域名；extension 桥接可用 `Coordinate+MapKit.swift` 这样的名称。

函数跟随其数据和生命周期所有者。只把不依赖 owner 私有状态、或能连同完整 owner 一起移动的实现拆出。算法内部共享状态、私有索引或 solver accumulator 不为了行数而开放访问权限。较大的求解器、图构建器、ContinuousStroke 和统计计算仍按其完整算法职责保留；后续逻辑改动以具体问题为边界。`OverlapLanes` 已删除。

注释说明当前合同、原因和边界。删除已退役验证器“每次运行自动保证”的说法，以及错误的旧文件名／尚未实现描述；保留仍有用的物理拓扑、数据来源、时间与线程语义解释。历史 benchmark 不视为新的测量。规格节号可以作为来源线索，但不能代替对当前行为的说明。

## 资源与验证边界

RailKit 各 target 的 `Resources/` 不移动；主应用 Assets、字体、Icon Composer 和资源复制脚本路径保持不变。SwiftPM 递归发现 feature 子目录；Xcode 文件系统同步组递归纳入主应用文件。直接读取 Swift 源文件的三处回归测试引用已修正。

验证按 [VERIFICATION.md](../VERIFICATION.md) 执行：路径／内容和访问边界审阅，Xcode plist／workspace 引用检查，再使用已有 DerivedData 的单架构增量编译。不新增 umbrella runner，不跑全矩阵，也不把编译结果当作 UI、性能、泄漏或全国数据结论。

## 本次验证结果

四个 Xcode 工程的 plist 语法、workspace 引用、诊断应用 package／资源路径和
333 个生产文件的唯一归属检查通过。主应用及 RailAlignmentInspector 的 arm64
模拟器增量编译通过；源码无编译警告。显示检查台只有无 AppIntents 依赖时的
可选 metadata 跳过提示。RouteWorkbench／ThroughWorkbench 做了路径和语法检查，
未在本聊天分别编译产品。未执行完整 native 测试、UI／性能／泄漏或设备矩阵。
结果与修复过的集成问题记录在 ../refactor-parallel/architecture-coverage.md。
