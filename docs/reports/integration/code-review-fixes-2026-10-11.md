# 16 项代码审查问题修复

2026-10-11。范围为 [原始审查](code-review-2026-10-11.md) 的 S1、S2、B1–B14，基于同一未提交工作区实施，保留已有改动。执行 code-review、codebase-design、iOS 指南、Superpowers 的诊断/实现/复审/验证实践；按用户偏好使用 Sol 独立工作者及 Grok 4.7 有界工具修复。

**状态：16 项均已修复。** 最终独立复审确认没有未解决的范围内实质问题。以下检查只支持各自列出的源码、构建及针对性行为结论。

## 修复范围

| 项目 | 修复 |
|---|---|
| S1 | Web 图按测量铁路身份区分节点，只接入 reviewed physical junction；旧几何回退及 raw 正缓存需匹配当前版本、完整求解上下文及源指纹，当前负解不回退；物理身份和有效期纳入源指纹。移除仅凭距离的补线，也修复离线预计算的同类路径。 |
| S2 | StrokeJunctionIndex 与新 RecordedRouteMapping 登记到现有 RailCore 责任组。 |
| B1 | 清空外出国家工作集后才切换持久化命名空间，失败的新会话进入恢复保护；下载、分块解析与停站索引发布检查会话归属，失败会作废未完成的准备。 |
| B2 | streaming、readiness、缓存、持久化和地图发布均检查会话 generation。 |
| B3 | 静态构建使用保留的共享资源注册表，更新或退役已失效的 package 入口。 |
| B4 | 分组及最后的取消检查发生在导入提交前；提交后同步发布，所有 Cancel 入口遵守提交边界，继续保存。 |
| B5 | 备份数据和元数据写入完整 UUID 代，再原子发布指针；读取/恢复解析同一代，保留旧备份兼容。 |
| B6 | 保存返回本次写入的结果；截图导入保留错误并提供重试，重试不重复添加记录。 |
| B7 | 共享 occurrence-aware 映射，将物理区段映射到记录停站区间；统计、缺口、日期、播放、标记及标签使用正确归属。 |
| B8 | 停站选区映射全部物理区段；已有服务 leg 使用精确物理选区编辑和清除，保留选区外身份。 |
| B9 | 方向缓存身份包含其依赖的归一化几何与结构。 |
| B10 | 局部线路修正直接 splice 原链的映射区间；局部 Undo 恢复该切片并保留外部源边界。 |
| B11 | PNG companion 解码或尺寸读取失败视为 stale。 |
| B12 | 视频扫描入口拒绝非有限或非正 FPS。 |
| B13 | 移除只依赖已退役 AFR/Nankai verifier 的专用 helper 测试，不恢复旧流水线。 |
| B14 | 拆分目标链后，正向和反向 follow 的 canonical 距离按目标 measure_start 重基。 |

## 验证记录

| 检查 | 实际结果 |
|---|---|
| Web 初始定向选择 | 9 个测试文件，55 通过、0 失败，1.56 秒。包含真实 static builder 的微型临时夹具构建；25 个资源及 7 个 parts manifest 的存在性查询。 |
| Web 调用链补充最终选择 | 5 个受影响测试文件，22 通过、0 失败，0.19 秒；覆盖旧几何回退、raw 正缓存、相同坐标但不同物理身份/有效期的源指纹、断开的相邻 leg、离线负解、失败切换残留下载和旧停站索引发布。复审发现缓存依赖后，由原 16 项扩大到 22 项；与初始选择有重复，不累加成独立测试数。 |
| Swift 初始定向选择 | JourneyServiceSections 4 项、RailCore 30 项、MileageMatching 9 项；首次有 1 项服务编辑断言失败，其余通过。 |
| Swift 失败修正后 | 只重跑 RouteSectionServiceEditingTests：7 通过、0 失败；新增精确物理 leg 编辑/清除回归。其余不受这次修正影响的证据复用。 |
| Python follow 回归 | 仅 DisplayNetworkHistoryTests 的正向重基、反向重基、未拆分保持距离 3 项，通过；父任务再次确认同一生产 helper 的结果。 |
| 原生增量构建 | 复用 /private/tmp/jtm-refactor-resume-20261009/app-build，RailMap / generic iOS Simulator / arm64 / jobs 1；exit 0，BUILD SUCCEEDED。 |
| 工具与归属 | 两个 Swift 工具语法解析通过；ImageIO 有效/非图片/截断 PNG 探针确认解码行为；责任表 335 项、335 唯一，两个目标源文件各登记一次且存在。 |

首次 Swift 失败是未改动的 code-only 源区段与旧相邻区间归一化副本之间的 nil/空名称差异；按“选区外源约束保持精确”的合同修改断言，而非归一化整条合法原链。初次编译提示既有 PhysicalEndpointTrimTests 的两处未使用表达式；App 构建只有不依赖 AppIntents.framework 而跳过可选元数据提取的警告，没有源编译错误。

原始定向 Swift 命令：

```sh
bash ios/verify.sh swift --filter 'RouteSectionServiceEditingTests|RailwayRouteEditingTests|RouteSectionExportTests|JourneyServiceSectionsTests|MileageMatchingTests|sourceBoundaryStopDistances|directionCacheFollowsGeometry|routeOnlyLineBoundaryRemainsAConstraintWithoutInventingPassingCalls' --jobs 2
bash ios/verify.sh swift --filter 'RouteSectionServiceEditingTests' --jobs 2
```

独立工作者逐项复审 16 项，并发现、反馈了受影响调用链遗漏：Web 旧几何回退、凭距离补线、失败切换后的晚到车站发布、App 物理 leg 编辑选区，以及物理身份源指纹与 raw 正缓存消费。所有整改均已重新复审，最终没有未解决的范围内实质问题。复审未重复构建或测试。

完整临时证据位于 /private/tmp/jtm-fix-20261011，包括 swift-focused.log、swift-service-final.log、app-incremental-build.log、web-final-focused.txt、web-publication-final.txt、各范围变更前副本与工作者结果。以上表格保留实际结论，临时文件失效不改变本报告的范围边界。

只协调一个重型任务。为了运行必要的原生检查，暂时暂停已有 RailAlignmentInspector 批次于 58,207/92,216；重型检查结束后恢复同一证据目录和 plan，界面确认“批量检查运行中”，进度已达 58,320，原有失败数 6 保留。这个批次属于既有任务，不将其历史进度或人工作出的结论算成本次修复验证。不另行执行全国源数据重建、完整测试矩阵、旧 umbrella runner、性能/像素/泄漏认证。增量 App 构建仍运行既有 Copy rail packages 阶段，在 DerivedData 的 bundle 中生成显示几何派生产物，不修改仓库源数据。未提交、推送或发布。

## 证据边界

初次修复阶段的原生导入取消、磁盘失败与重试仅做源码调用链复审和增量编译；随后按用户要求补做了下述原生针对性验证。PNG 的轻量 ImageIO 探针只确认解码行为，不等同于完整 WebKit 栅格化。FPS guard 采用源码与语法检查，未扫描视频。全国打包数据、设备像素、泄漏和性能不在本次检查结论内。

## 原生取消、写入失败与重试补做验证

增加显式选择的 `RailMapTests` scheme/hosted unit target，直接 `@testable import RailMap`，保留真实 ItineraryStore、ImportFlow、TransferGuideImport、RideLibrary 和 RideStorage 调用链。测试使用全新临时目录；三个备份发布阶段通过原子数据写入依赖精确抛出写入错误，主存储和恢复写入使用真实目录冲突。OCR 输出固定后，仍执行真实截图解析、草稿构建、提交和重试。生产默认仍使用 Vision 与 `Data.write(..., .atomic)`；未增加通用文件系统框架或独立验证脚本。

| 场景 | 实际通过证据 |
|---|---:|
| append/replace 导入在提交前取消，内存和已存文件不变 | 2 |
| append/replace 在 onCommit 取消，仍返回并保存已提交工作集 | 2 |
| 实际 ImportFlow 开始后立即取消，保留原工作集 | 1 |
| 实际主文件写入失败显示本次错误，下一次保存使用当前编辑 | 1 |
| 截图保存失败后重试，不重复加入记录、不覆盖期间的编辑 | 1 |
| 备份数据/元数据/指针发布分别失败，旧代保持一致且可恢复 | 3 |
| 恢复写入失败仍保留恢复入口，重试成功后才消耗备份 | 1 |
| 挂起截图识别时取消，回到 waiting，迟到工作不能恢复读取状态 | 1 |
| 不同场景合计 | **12** |

先在一个隔离 iPhone 17 Pro / iOS 27.0 / arm64 模拟器运行原 11 个场景，7 个测试函数全部通过。日志发现新测试目标重复加载 RailCore，已移除测试 bundle 的额外 package product 链接，由 `BUNDLE_LOADER` 使用 App 的唯一实现；只重跑同组，仍为 11/11，重复类警告消失，函数执行 0.357 秒。新测试主程序仅在 Debug 的真实 hosted XCTest 进程中避开 AppShell，防止启动地图或读取保存工作集。

Grok 有界只读复核指出截图取消状态遗漏，父任务核对实际 `TransferGuideImport.cancel()` 及两个选择入口后，单例运行确实失败：取消后 `isRunning == true`，phase 未回到 waiting，1 个用例记录 4 个问题。断言执行已结束，但 Xcode 失败报告收尾等待数分钟；仅终止这个已核实的 xcodebuild 进程，exit 143。保留失败日志，**不将中断结果包记为完成或通过**。

修复只增加 `cancel()` 中 `.reading → .waiting` 的状态复位，保留 `.read` 草稿与 `.imported` 结果。之后只执行新增取消单例和受影响的截图保存重试用例；后者也检查取消已完成草稿/导入结果不会清空它们。**2/2 通过、0 失败、0 跳过，exit 0，TEST SUCCEEDED**，函数执行 0.155 秒。其余没有相关变化的证据复用；11 与 2 有一个重复场景，不累加为 13。

实际使用既有 DerivedData 和 `-jobs 1 -parallel-testing-enabled NO`；先选择 `-only-testing:RailMapTests/NativeImportPersistenceTests`，整改后只选两个受影响函数。未执行 UI 套件、完整矩阵或旧流水线。增量构建仍运行既有 bundle 资源阶段。仅有两个目标不依赖 AppIntents.framework、跳过可选元数据提取的构建警告。

证据：`/private/tmp/jtm-native-validation-20261011/NativeImportPersistence-linked.xcresult`、`ScreenshotCancellation-green.xcresult`、对应结果摘要和运行日志；失败单例为 `screenshot-cancel-red.log`。永久回归源码：[NativeImportPersistenceTests.swift](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/RailMapTests/NativeImportPersistenceTests.swift)。本次专用模拟器已删除，未操作既有模拟器或真实行程存储。

原取证批次暂停于 70,574/92,216（既有失败 6），重型检查完成后恢复同一 plan/output。界面已确认“批量检查运行中”，进度增长到 70,576，既有失败数仍为 6。本次不认证真实硬件磁盘耗尽、掉电/进程终止、真实图片 OCR 准确率、像素或性能。
