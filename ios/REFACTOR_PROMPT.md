# JTM iOS 渐进式重构 Prompt

你是一名负责 SwiftUI、MapKit 与 Swift 并发的资深工程师。请基于当前工作区的真实代码，对 JTM iOS App 实施保持行为一致的渐进式重构。目标是降低职责耦合、明确状态与任务所有权，让关键逻辑可以独立验证。

## 1. 先确认当前事实

阅读仓库适用的工程指令、`README.md`、`ios/RailKit/Package.swift`、`ios/verify.sh`，以及与本次改动相关的 `docs/decisions/` 文档。文档与实现不一致时，先追踪调用链，明确差异。

先检查 `git status` 和相关 diff。当前工作区已有大量已修改和未跟踪文件，应将这些内容视为本次重构的输入基线；不得覆盖、回退、清理或擅自提交已有工作。不要使用 reset、clean 或批量 checkout 恢复文件。

现有分层必须保留：

- `ios/RailKit/Sources/RailCore/`：纯领域逻辑，仅依赖 Foundation。
- `ios/RailKit/Sources/RailPresentation/`：展示决策与交互解析，仅依赖 Foundation 和 RailCore。
- `ios/RailMap/`：SwiftUI、MapKit、持久化、Vision OCR、视频导出等平台集成。
- `app/` 与 `port-fixtures/`：JavaScript 参考行为和跨语言一致性基线。

不要预设迁移到 MVVM、TCA 或新模块体系。沿用现有分层和项目惯例，只有真实调用关系需要时才增加抽象。

## 2. 重构候选与优先级

下面是初步阅读发现的候选，不是已证实的缺陷清单。先复核当前实现和调用方，再确定具体改动。文件行数仅用于定位，不作为验收目标。

### P1：工作区组合与交互编排

`ios/RailMap/ContentView.swift` 中的 `RailWorkspaceView` 约 3374 行，同时涉及布局、搜索与日期筛选、旅程选择、弹窗、地图控制、回放及分享入口。

先阅读 `AppShell.swift`、`WorkspaceLayout.swift`、`WorkspaceDerived.swift`、`JourneyPresentationBridge.swift`、`PresentationHost.swift`、`ImportFlow.swift` 和 `VideoExportFlow.swift`，识别已经存在的职责边界。

- 按拥有独立输入和生命周期的 UI 区域提取子视图；按完整操作流程提取编排逻辑。
- 让工作区保留布局组合、依赖注入和必要的跨区域协调。
- 保留 AppShell 对共享 store、PlaybackController 和地区范围的所有权。
- 复用 JourneyPresentationResolver 的动作优先级，避免在各个子视图重新推导。
- 保留 ImportFlow、VideoExportFlow、CategoryIndexes、ManualDates 和 WorkspaceDerived 的现有职责，避免再造平行实现。
- 不要仅将代码移入多个 extension，或新增一个接收所有 store 的巨大 ViewModel。
- 明确拆分前后的状态拥有者，避免因视图身份或条件分支变化丢失搜索、日期、滚动位置、展开状态和选择。

### P2：MapKit 渲染管线与 Coordinator

`ios/RailMap/RailMapView.swift` 约 2951 行。其 Coordinator 同时处理 update、rebuild、restyle、标注与标签、命中检测、手势、相机和回放桥接。

- 追踪 `update → rebuild/restyle`、`handleMapTap`、`layoutEndpointLabels`、`renderPlayback` 的真实数据流。
- 优先选择一个输入输出清晰的职责，例如几何构建或标签布局计算，完成一次可独立验证的提取。
- Coordinator 保留 MKMapViewDelegate、UIKit 生命周期及平台状态应用；纯计算按实际依赖放入合适层。
- 复用 `MapPlaybackLayer`、`MapEndpointLabels`、`RideTapIndex`、`NetworkLOD`、`MapOverlayStyles` 等已有实现，避免创建重复渲染框架。
- 明确缓存的输入、失效条件和拥有者，保持仅样式变化与几何重建的区别。
- 保留 MKMultiPolyline 批量绘制、LOD、视口裁剪、顶点预算、站名避让、平行轨道和连续笔画语义。
- 不要切换成每个区间一个 SwiftUI MapPolyline，也不要通过修改铁路原始几何来简化渲染代码。

### P3：异步任务与结果发布

检查 `RailNetworkStore.swift`、`RiddenRouteStore.swift`、`MileageStatisticsStore.swift` 中加载、求解、缓存与 UI 发布的边界。

特别追踪 `RiddenRouteStore.resolve(_:)`：当前使用外层 Task 等待 Task.detached，然后按旅程 ID 更新 rides 和 RideStatusCenter。核实同一旅程连续编辑、删除、clear 或整体 reload 时，旧结果是否可能覆盖新状态；在复现或调用链证据成立后再修复。

- 明确任务的拥有者、取消点以及结果仍有效的判定条件。
- 保留已有的渐进加载、缓存复用和优先旅程行为。
- 区分共享后台缓存任务与单次用户操作任务，不要机械删除所有 detached task。
- 不把昂贵计算移回主线程，不用新增 `@unchecked Sendable` 或忽略并发诊断掩盖问题。
- 仅为证实的竞态增加有针对性的回归测试，不抽象通用任务框架。

### P4：统计页面的展示数据整形

`StatisticsView.swift` 约 1649 行，包含卡片布局、日期与票面文案、服务分类及热门区间展示数据整形。

- 先复用 `StatisticsComponents.swift`、`StatisticsFormatting.swift` 和 `MileageStatisticsStore.swift`。
- 将独立、可测试的展示数据转换与视图布局分离；纯展示规则可进入 RailPresentation，依赖 SwiftUI/UIKit 的格式和渲染保留在 App 层。
- 保持统计口径、地区与日期范围、多语言、无障碍朗读和分享图片一致。
- 不重复计算 store 已经提供的统计结果，不为减少文件行数拆散紧密相关的票面组件。

## 3. 行为与范围约束

- 保持当前 iPhone/iPad、自适应布局、常驻地图与面板交互；不重新设计 UI。
- 保持跨标签页共享回放，避免切换页面时创建第二个播放器或重建地图。
- 保持本地数据格式、记录 ID、导入导出语义、日期与时区规则、地区编码和偏好键。
- 保持路由失败的真实状态；不得新增直线回退来掩盖求解失败。
- 不修改铁路数据包、拓扑、JavaScript 参考行为或 parity fixtures 来让测试通过。
- 不进行无关格式化、批量重命名、依赖升级、全局单例化或持久化框架迁移。
- 保留现有缓存带来的性能收益。更换缓存策略必须说明旧策略的问题和新策略的等价性，不能仅以代码风格为理由。

## 4. 执行方式

1. 先输出简短的职责与数据流说明，以及按优先级排序的改动计划。每项写明代码证据、目标边界、影响文件、必须保留的行为和验证方式。
2. 首批默认聚焦 P1 中一个完整的职责拆分，控制评审范围；随后按依赖和收益逐批推进已确认有价值的候选。没有证据或收益不足的候选说明理由后跳过。
3. 每批保持可编译，更新所有必要调用方及工程文件引用，不留下新旧两套执行路径。
4. 为提取出的关键规则和证实的缺陷增加行为测试，优先复用现有 fixtures 和测试入口。不要写仅断言类型存在、文件长度或实现细节的测试。
5. 保留说明约束与原因的注释。仅修正与本次改动有关的过时描述，不开展全仓库注释清理。
6. 常规实现选择自行完成；遇到需要改变产品语义、存储契约或铁路数据的事项，记录具体原因并单独提出，不混入结构重构。

## 5. 验证与验收

先阅读实际脚本参数并记录基线失败。迭代使用相关测试和窄范围验证，交付前运行完整门禁：

```bash
cd ios
./verify.sh --core
./verify.sh --swift
./verify.sh
```

这些模式有重叠，不要求每批机械执行全部命令；根据改动层选择迭代命令，最终完整验证一次。

涉及布局、地图或动画时，检查并使用适用的 `RailMapUITests`、`tools/verify-layout-ui-smoke.sh` 和 `tools/verify-reduce-motion-ui.sh`。重点覆盖：

- 搜索/日期筛选 → 打开旅程 → 返回列表后的状态保持。
- 紧凑、宽屏与 iPad 多列布局切换，以及面板拖动时的地图交互。
- 图层切换、地图缩放、选中旅程、站点点击与标签表现。
- 回放中切换目的页，以及取消视频导出后回放状态。
- 快速重复求解、编辑或删除后的结果一致性（若修改异步流程）。

涉及性能热路径时，用现有 `ios/tools/bench` 或 RailSignpost 支持的相同场景进行前后对比，不凭代码量减少宣称性能提升。

完成标准：职责边界有实际改善；行为和数据契约保持一致；相关测试、模块边界检查和 App 构建通过；没有重复逻辑或未使用抽象。若环境限制导致验证无法运行，准确说明命令和阻碍，不将其记为通过。

最终报告简洁列出：完成的职责拆分、关键文件、验证结果、未完成项及理由，以及有证据支持的剩余风险。只在公开接口或持久架构决策改变时更新对应的 canonical 文档。不要自动提交、推送或发布。
