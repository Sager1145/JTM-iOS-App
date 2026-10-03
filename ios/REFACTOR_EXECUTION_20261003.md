# iOS 整库结构重构执行记录

日期：2026-10-03。基线：`eaefd45f`。状态：结构迁移与后续产品边界已落地；本轮 app/native 与聚焦设备检查通过，完整 Swift 失败，七条修复定向 UI 流程分别通过，剩余整体验证未关闭。**不是整库、全部设备或性能验收完成声明**。

开始前保存了已有差异：`/tmp/jtm-refactor-20261003/preexisting.patch`。保留用户原有编辑器、字符串、路线压力数据生成器更改；README 的新增说明在原有更改之上整合。后续按用户要求归档北美资源并新增明确物理接续目录；没有为求解成功强行补造轨道。未提交或推送。

## 已落地的边界

- **S0 / S5**：`source-ownership.json` 为当前生产 Swift 文件逐项列出责任与验证入口，数量随活动 target 成员变化，以检查器输出为准。检查器从 Xcode 同步目录及 SwiftPM target 发现源码，检查遗漏、重复、已删除路径和包依赖。CI 新增独立 boundaries 检查；`verify.sh --native` 将现有地图/路线与新增功能生命周期检查接入统一入口。
- **S1 / S2**：新增实际使用的 `RailApplication`，与 `RailPresentation` 独立依赖 Core。导入 preflight、scratch staging、类型化草稿校验迁入该模块；app 保留本地化、generation、备份后的二次检查、取消接纳、发布和持久化确认。
- **S2**：`RideStorage` 独占磁盘；`RidePersistenceQueue` 独占操作顺序；`RideLibrary` 保留保存合并、saveSequence、删除 revision 和界面状态，并可注入存储实例和目录。默认目录及磁盘格式保持原样；DEBUG UI case 通过 UUID 注入独立目录，修复实测的样例持久化污染。
- **S3**：`MileageMatching` 接收 canonical WGS84 快照并返回有界匹配缓存。原统计 fingerprint、passport-only 路径、地区/日期 scope、过期结果检查保留。`TimetableQuickMatchController` 拥有 debounce、请求身份、查询结果与取消；`JourneyCompletionRequest` 拥有单个 AI 请求寿命，候选应用仍走编辑器。
- **S3 后续**：`StationPickerSearchController` 拥有目录快照、120 ms debounce、后台搜索、请求与加载身份，目录/准备/历史站三个挂起点逐次拒绝已取消的加载。`ShareRequestController` 拥有统计分享请求身份；生成前后和延迟呈现前核对日期/地区/行程组/store generation，页面离开时取消待呈现结果。
- **S4**：地图提取 `MapInteractionCoordinator`、`MapStationLabelCoordinator`、`MapRenderDiagnostics`，分别拥有命中/平台索引、标签选举与调度缓存、诊断。Coordinator 保留挂载、委托与场景组合；现有 renderer、相机、annotation identity、车道算法、单地图和单播放器不变。
- **S5**：Xcode 资源装配只消费已验证的时刻表，不再在构建过程中重写源树内的派生数据库。过期输入给出明确的生成命令。

逐条功能路径、保留边界和剩余验收见 [功能矩阵](REFACTOR_FEATURE_MATRIX.md)。保留成熟的 Core、Workspace、播放/分享、History 和本地化职责，不为减少行数机械拆分或复制状态。

## 后续产品边界与当前验证（2026-10-03）

- **北美永久退役**：应用只支持 jp/tw/hk/mo/kr；US/CA 地区枚举、设置开关、编号/时区入口及独立 store、split marker、恢复/合并兼容链均已移除。原始数据、混合资源旧副本和旧测试契约保存在仓库 `backups/north-america/2026-10-03/`，不属于 app 输入。Root 已核验三份独立清单及精确库存覆盖：主清单 171、legacy source 清单 21、`raw-source-files-manifest.json` 810，共 1,002 个唯一 payload 文件；810 项包含 808 个 raw na-rail 文件。新增 raw 清单只建立当前归档的大小/hash 基线，不构成迁移前原始文件字节一致的独立证明。设备上的历史用户文件不由这次仓库归档操作改写。
- **永久排版和方向规则**：`AppTypographyPolicy` 在 scene 根限制 Dynamic Type 为 `.xSmall ... .xLarge`，UIKit preferred-font 入口应用同样上下限，不是临时 UI 测试设置。Debug/Release 的 iPhone 支持方向均为 portrait；iPad 继续保留四种方向。新 app 构建通过；iPhone 8 项与 iPad 4 项字号/方向相关检查通过，两台实设系统 AX5 均观测 app 为 xLarge。iPad 四方向配置不等于四方向交互全部验收。
- **严格物理拓扑**：应用显式使用 `RouteGraph.BuildPolicy.physicalRailway` 与 `RouteSolver.TraversalPolicy.physicalRail`。轨道身份隔离运营商、线路、铁路类别及可用 level/track/source ID；缺少明确身份的 feature 用稳定源几何摘要隔离，完整/局部图不依赖枚举下标。站群、同名、近距离、乘客换乘和直通显示均不能授权铁路连接。`PhysicalJunction` 只接纳有证据、真实已有同坐标端点及有效期的零距离接续，不生成虚构直线或里程；required hints 检查两端线路/运营商。求解输出仅保留源轨道顶点，不以站点显示坐标或上一段 continuity anchor 补线。旧坐标/乘客图通过显式 parity 参数单独核验，不刷新旧 golden 掩盖新规则。
- **证据覆盖仍有限**：`app/data/physical-rail-topology.json` 当前清点五地区 756 个源属性轨道身份、829 个共享源顶点的接续候选。候选不自动进入 graph，也未逐条审查；它不是“全网连接已验证”的目录。四个已审查东京接续来自独立 `physical-rail-junctions.json`，既有 through-running display registry 继续独立处理显示。

| 本轮后续检查 | 已观察结果 | 日志 / 证据 |
| --- | --- | --- |
| 北美归档完整性与库存覆盖 | Root 核验 171 + 21 + 810 = 1,002 个唯一 payload 文件及精确库存覆盖；raw 810 项仅为当前归档 hash 基线，不是迁移前字节证明 | `backups/north-america/2026-10-03/` 三份清单；主清单日志 `/tmp/jtm-na-retirement/backup-integrity-final.log` |
| 物理拓扑独立直接测试 | 最新 18 项通过：身份隔离、证据/日期/hints、未知身份及完整/局部图一致性；已包含在下行 40 项中，不重复计数 | `/tmp/jtm-physical-component-check/test.log`；临时包链接真实 RailCore，不等同完整包测试 |
| 修正契约后的聚焦 SwiftPM | 40 项 / 4 suites 通过，3.622s：PhysicalTopology、LocalizationParity、RouteStationCandidatesParity、SamplePrecomputeProvenance；保留旧 golden 和浏览器 legacy attestation，严格 native 拒绝旧预计算 | `/tmp/jtm-na-retirement/corrected-contracts-final.log` |
| 四个接续对完整日本源图的接纳 | 全部接纳，拒绝 ID 为空；未执行完整图 Dijkstra | `/tmp/jtm-actual-junction-acceptance.log` |
| 北美/物理规则后的完整 SwiftPM | 已结束，整体失败：Presentation 333 项、Application 25 项通过；Core Swift Testing 837 项运行、166 issues（TrainServicePattern 57 + RailHistory 109）。该次 XCTest 旧缓存/策略断言失败，源码修正后的三项聚焦回归另行通过，不回写整套结果 | `/tmp/jtm-na-retirement/swift-full-latest.log`；缺失物理接续详见 [路线缺口记录](PHYSICAL_ROUTE_GAPS_20261003.md) |
| History 浏览器旧契约聚焦复跑 | 两个明确 browser golden 测试改用显式 legacy 图与测试专用端点复原后仍失败：2 tests / 10 issues / 419.913s。返回结果的 raw-vertex/raw-length/nonconnector-edge 断言全通过；8 条 legacy 路径 nil（Mashike、Takachiho、Shidami、KobeKaigan、SendaiTozai、UtsunomiyaLRT、ToyamaLoop、RinkaiOsaki），HAPI predecessor 差 10.586m，另有 SixRides 未标名 nil。生产严格守卫与原 golden 未改 | `/tmp/jtm-na-retirement/swift-history-web-parity-focused.log` |
| 新 app 完整构建 | 北美资源名单残留已修正，arm64 Simulator 重跑 BUILD SUCCEEDED，build-for-testing 成功 | `/tmp/jtm-na-retirement/editor-body-build-retry.log`、`ui-repair-sharing-build-for-testing.log` |
| 新 native 统一门禁 | 最新整套通过，包含新 production component；初次 ModuleCache 权限阻断为已恢复的环境问题 | `/tmp/jtm-na-retirement/native-latest-components.log`；此前 `native-final-fourth.log` |
| RailValidity 聚焦回归 | 3 项通过；旧换乘契约显式 passenger，当前缓存版本为 27 / 28，不改变生产严格默认 | `/tmp/jtm-physical-component-check/rail-validity.log` |
| 最新 Catalyst 构建与隔离交互 | Group 注入同一 network 后 BUILD SUCCEEDED；Root 实际执行行程 → 嵌套编辑 → Cancel 无崩溃；不等于全套 Catalyst 交互通过 | 最新组件构建 `/tmp/jtm-na-retirement/catalyst-latest-components-build.log`；实际交互 `catalyst-sheet-network-interaction.log` |
| 七条修复定向 UI 流程 | 分别通过：分享 98.148s；AI 中间站 531.666s；无效回复 86.192s；行程组 55.218s；dirty Cancel 44.480s；SaveGroupReturn 47.396s；保存/重启 74.086s。来自不同轮次，不是完整 UI suite 通过 | `/tmp/jtm-na-retirement/ui-repair-final.log`、`ui-repair-latest.log`、`ui-repair-three.log`、`ui-repair-sharing.log` |
| 分享图像 / scope 实际复测 | map/statistics 两种图像各 Light/Dark，四种预览的日期/地区/image 断言保留并通过。实际 Done 并确认日历消失后，正常 share.tap 成功；坐标 fallback 已移除 | `/tmp/jtm-na-retirement/ui-repair-sharing.log`、`ui-repair-sharing.xcresult`；TEST EXECUTE SUCCEEDED |
| 全屏 dimming / 独立铁路绘制面 | **NO-GO，未实现**；保持现有 MapKit 和固定 `.default` 底图 | 计划 M 与下方未关闭验收 |

## 实际验证（物理拓扑 / 北美退役变更前）

以下记录保留已发生的构建、通过和失败；它们不证明上述后续变更已完成整体验收。旧阶段日志目录：`/tmp/jtm-refactor-20261003/`。日志是本地执行证据，不随 Git 提交。

| 验证 | 结果 | 日志 |
| --- | --- | --- |
| 修改前完整 SwiftPM 基线 | 809 Core + 343 Presentation = 1,152 项通过 | `swift-baseline.log` |
| 最终工作树全部 RailApplication | 23 项 / 4 suites 通过 | `application-final.log` |
| 编辑诊断兼容 | 36 cases 通过；与原实现比对 field/severity/key/params/literal/id 一致 | `/tmp/jtm-editor-validation-harness.log`、`/tmp/jtm-editor-validation-golden` |
| native 统一门禁 | 通过；包含编辑、持久化、时刻表、路线取消/渐进发布、地图缓存/worker/图层、认证/HTTP 替身和 AI 请求生命周期 | `native-gate.log` |
| app 统一门禁 | 通过；完整构建、源码契约、资源与包内图片检查 | `app-gate-final.log`、`app-gate-app.log` |
| iOS Simulator 完整编译 | 通过 | `app-build.log` |
| Mac Catalyst 完整编译 | 通过 | `catalyst-build-final.log` |
| 资源 revision / 时刻表快照 checker | 8 + 7 项通过 | `resource-tests.log` |
| 干净 / 增量 / Catalyst 资源身份 | 三份资源 revision manifest 完全一致 | `resource-identity.txt` |
| 源码归属检查器自身测试 | 7 项通过 | `native-gate.log` |
| 后续 native 统一门禁 | 通过；包含新增分享 4 组、站点搜索 7 组受控时序检查 | `/tmp/jtm-refactor-completion/native-final.log` |
| 播放/视频与地图透明度生命周期 | 30 项播放 + 27 项视频检查通过；地图 fade/reversal/reduce-motion 检查通过 | `/tmp/jtm-refactor-completion/playback-lifecycle.log`、`playback-video-lifecycle.log`、`map-detail-fades.log` |
| 地图选择 UI | 通过；确认选择后相机聚焦，`basemapMuted == 0` | `ui-regression.log` |
| 时刻表 UI | 完整通过，1 case / 156.309s；日期/服务名变化清除旧结果，恢复有效输入后重新匹配 | `timetable-ui-complete.log`、`timetable-ui-complete.xcresult` |
| iPad 统计 scope UI | 存储隔离修复后完整通过，1 case / 84.385s；在原有 240 条污染数据仍保留的设备上验证独立 39 条输入 | `statistics-isolated-ui.log`、`statistics-isolated-ui.xcresult` |
| iPad 播放 UI | 控件可点击性失败；隔离 HEAD 基线在新建同型号设备复现相同断言，登记为原有问题 | `ipad-ui.log`、`baseline-ipad-ui-retry.log` |
| 既有路线投影局部基准 | 与原始扫描结果一致；计时仅为局部诊断，不能归因于本轮重构 | `projection-parity.log` |

构建中的 AppIntents metadata 提示来自 SDK 的无 AppIntents 依赖处理，不是 Swift 源码警告。native/app 门禁均保留源码 warning 检查。

时刻表 UI 的服务选择按钮和服务名称输入框均在 lazy Form 首屏之外；测试补充滚动定位，并在修改服务名后提交键盘输入再切换步骤，保留日期/服务变化的所有查询断言。最终运行成功退出并生成完整 xcresult。此前失败运行的 runner 曾卡在报告收集，已停止本任务的旧 xcodebuild 并保留文本日志。

持久化目录注入额外验证：`persistence-final.log` 包含独立 store 不串写、相同目录可重新读取，以及全部原有保存/恢复/回滚案例。

iPad 初次统计失败具有源码证据：样例钩子执行 merge 并保存，播放案例的整库样例污染了后续预期只有 39 条跨年行程的统计案例。现已按 case 隔离存储；播放控件可命中性已在 HEAD `eaefd45f` 的隔离工程及全新同型号 iPad 上复现同一断言（28.657s），因此登记为原有失败，未通过删除断言放行。基线日志：`baseline-ipad-ui-retry.log`。同基线统计页实际显示 240 = 201 + 39 条（`baseline-statistics-first-count.png`），并在预期 39 的断言处超时；进一步证实跨案例持久数据污染。

候选统计 UI 随后在同一污染设备上完整通过，覆盖 39/17 条筛选、跨年范围、端点取消及分类互斥。该任务创建的临时 iPad 模拟器已删除，基线工程、日志、截图与候选 xcresult 保留在上述日志目录。

## 复跑入口

```sh
./ios/verify.sh --boundaries
SCRATCH=/tmp/jtm-refactor-native ./ios/verify.sh --native
swift test --package-path ios/RailKit --filter RailApplicationTests
SCRATCH=/tmp/jtm-refactor-full ./ios/verify.sh --swift
```

`--native` 不执行全部 SwiftPM suite；`--core`、`--swift` 和默认入口仍执行完整包测试。完整 UI suite 需独立运行，命令在 `source-ownership.json` 和功能矩阵中登记。

## 未关闭的验收

- 完整 UI suites、所有辅助功能组合、视频/分享产物及 Catalyst 交互仍未全部通过。旧分享 enabled 超时、AI 控件/中间站失败，以及 Catalyst 的 AppLocalization 环境缺失崩溃与两次失败注入候选均保留为历史记录（`/tmp/jtm-refactor-completion/ui-full-run.log`、`catalyst-interaction.log`、`catalyst-editor-fix-interaction.log`、`catalyst-scene-env-interaction.log`）。最新 Catalyst 嵌套编辑/取消实际无崩溃；此前七条失败/修复定向流程现已在不同轮次分别通过，历史 1 PASS / 6 FAIL 与后续 3 PASS / 3 FAIL 日志保留。分享最终通过真实关闭日历后的正常按钮点击验证，未保留坐标 fallback。定向通过不证明完整 UI parity。
- 未建立同一设备冷/热缓存下的端到端帧时、启动、峰值内存对照，因此不宣称性能提升。
- **全屏底图阴影仍为 NO-GO、未实现**。高亮不再切换底图明暗已保留；不使用逐 tile 遮罩，也不将层级拆分冒充视觉需求完成。独立铁路绘制面的 public API 可行性和同步/性能门槛仍属于计划 M。

## 最终范围验证的后续结果（2026-10-03）

- arm64 iOS Simulator app build 与 build-for-testing 实际成功；构建产物无 US/CA 铁路、车站、样例或行程资源。资源名单中遗漏的 Debug 北美样例引用已删除。
- `verify.sh --native` 全部通过（`/tmp/jtm-na-retirement/native-final-fourth.log`），包括编辑、持久化、缓存、地图 worker、取消、渐进发布、请求生命周期与架构导入边界。三个因既有行程确认 API 增补导致测试替身未同步的编译问题已修正，生产逻辑未退回旧接口。
- 字号硬限及生产 Swift 源码归属 gate 通过，数量以当前检查器输出为准。iPhone 普通字号 5 项、真实系统 AX5 3 项通过；iPad 普通字号 3 项、真实系统 AX5 1 项通过，共 8 + 4 项。两台真实系统 AX5 均观测 app 为 `size=xLarge`，系统类别恢复为原 large；iPhone 竖屏播放及三方向旋转请求断言保留。日志：`phone-portrait-typography-normal.log`、`phone-portrait-typography-system-ax5.log`、`ipad-typography-normal.log`、`ipad-typography-system-ax5.log`；类别收据为 `phone-system-ax5-category.txt` / `ipad-system-ax5-category.txt`（均在 `/tmp/jtm-na-retirement/`）。
- 严格区间与物理拓扑 15 项回归通过：离轨车站坐标和相邻显示锚点均不会进入求解几何。真实绘制区间等于图中实际轨道顶点，不补非轨道桥线；旧数值黄金独立记录其旧坐标契约。
- 八个测试夹具生成器已移除北美输入，24 个模块语法检查和八个定向 `--check` 通过。所有五地区共同数值结果保持相同，旧输入移除后引用索引已重映射。原八个 builder 和本地化 catalog 新增仓库归档；共 171 个文件字节与 SHA-256 验证通过。
- 最新 40 项聚焦契约、iPad 字号与 Catalyst 构建/嵌套编辑取消已通过；完整 Swift 已结束且整体失败（路线/History 共 166 issues）；七条定向 UI 流程已分别通过，History 浏览器旧契约聚焦复跑也失败（10 issues / 419.913s），不能称全部 Core 通过。本任务拥有的两台模拟器已清理，日志保留。组件合成计时仅说明合成输入，不构成全国图或设备性能证明。全屏底图 dimming 仍未实现，M 的 NO-GO 不表示原功能需求完成。


## 行程确认与通过站规则验证（2026-10-03）

行程继续显示推测通过站，未知时间明确标注；起终点／有序必经站产生可人工确认的候选。地图编号与 VoiceOver 卡片共享选择。候选搜索输出截断和覆盖状态，不把单一候选或服务目录当作完整物理路网。当前 compact-v1 候选层未完成与独立已审核接续登记表的映射，不能证明全路网唯一性，因而保留人工确认／待确认流程。

`route_confirmation` 保存 pending／confirmed；待确认跳过绘线和精确里程，统计显示未知或已确认部分。全程确认才解除 pending，撤销恢复原状态。选择待确认会取消未完成的推断；补入通过站不会把刚确认的路径误降级；重复站点按访问顺序保留。

本次实际验证：

- iOS Simulator arm64 编译通过：`/tmp/jtm-route-policy/build-retry.log`；最终 UI 复跑同时完成最新源码编译。
- 路线搜索、推断、通过站填入、分段／方向几何回归：53 项、7 suites 通过，`/tmp/jtm-route-policy/core-tests.log`。
- 待确认持久化／导出、全程与局部确认／撤销、里程、状态优先级、路线身份：68 项、6 suites 通过，`/private/tmp/jtm-pending-route-build` 对应运行。
- iPhone 新建／已有行程打开取消和待确认入口通过；地图测试首轮因滚出地图视口后的定位失败，修正测试滚动目标后，地图与卡片双向选择和待确认可保存两个用例全部通过：`/tmp/jtm-route-policy/ui-retry.log`、`ui-retry.xcresult`。
- 源码边界及其 7 项自测通过：`/tmp/jtm-route-policy/boundaries.log`。最终差异空白检查通过。
- 北美导入拒绝 10 项、Web 针对性回归 20 项、英文站名生成器 9 项通过；正式 App bundle 仅有 jp/tw/hk/mo/kr 五个铁路包。主备份清单在最终核验时为 171 文件，大小与 SHA-256 全部匹配；808 个原始文件已移至仓库北美备份内，并有独立清单。

上述范围不等于完整设备套件、全路网连接证据审查或全屏遮罩验收完成。未提交或推送。

### Continued physical-source and raster validation

- Reviewed three additional physical source-identity boundaries from primary construction/facility evidence: Chayamachi Uno/Honshi-Bisan (1988-03-20), Kojima same-Honshi-Bisan operator boundary (1988-04-10), and Shiojiri Chuo/Shinonoi current Enrei approach (1983-07-05). Registry now has seven reviewed boundaries; coincident-vertex candidates remain non-authoritative. Exact evidence and abstraction limits are in `PHYSICAL_ROUTE_GAPS_20261003.md`.
- Actual-source round-trip/opening-date regressions passed: three tests / two suites in 1.979s, `/tmp/jtm-na-retirement/reviewed-japan-boundaries.log`. Missing reviewed boundary and pre-opening dates reject; on/after opening all coordinates remain source graph vertices, all traversed rail edges exclude passenger connectors, and the accepted boundary adds zero geometry. This does not establish national service-pattern completeness.
- Typography permanent clamp, 263-source ownership gate, regenerated topology inventory and timetable artifact alignment passed during this continuation. `git diff --check` passed before the latest bounded edits; final verification is still required.
- Latest simulator test build with DEBUG raster controls passed (`viewport-controls-build.log`). Default/narrow, exact/narrow and matched native-reference experiments collect displayed pixel evidence; collection success is not geometric acceptance. Explicit native path recovered all 5,000 source vertices without deviation. Some settled exact/matched samples show 0.5-device-pixel p95, while moving acceptance remains unresolved. A DEBUG-only prototype overlay-lifetime defect was found and corrected; it is being rebuilt before motion evidence is accepted. Production full-viewport veil remains unaccepted.
- Historical browser fixture failures were traced to walking-shortcut paths in eight families; the original distances/digests are preserved. Test-contract separation and comprehensive native source/date validation are in progress, not yet recorded as passing. No production transfer guard is relaxed.
- No commit, merge or push occurred in this continuation.

### Further results from the continued run

- History contract repair focused tests passed with original golds unchanged: `everyGeneratedRouteBoundaryMatchesWebSolve` 924.266s and `historicalFixtureSixRidesMatchOnDemandSolve` 5.442s; total 929.709s. Includes all 191 generated/pinned native outcomes and source-edge/date checks, plus SixRides. Legacy browser connector paths are audited explicitly and never returned as native `SolvedSection`. Log: `/tmp/jtm-na-retirement/swift-history-contract-split-independent.log`; detailed traces: `/tmp/jtm-na-retirement/historical-browser-connector-evidence.md`. This repairs the two previously failed focused tests, not a rerun of all 837 Core tests.
- Iwanuma added one independently evidenced physical boundary; registry now eight reviewed boundaries. MLIT/operator-authored physical reconstruction report supports a conservative documented-existing interval from 2011-04-21, explicitly not the original opening date. Actual history-applied Watari–Sendai round trip, absent-boundary rejection, source edges and registry interval passed with the other three reviewed boundary regressions: four tests / three suites in 4.732s, `/tmp/jtm-na-retirement/reviewed-japan-boundaries.log`.
- High-cadence video invalidated apparent sparse-PNG success: synchronous direct projection still produced 9–14.5px transition errors; public visible-region callback plus synchronous paint still produced 8–10.5px errors over approximately 0.29s. Five-thousand-vertex paired work remains around 4.3ms p50 / 4.8–5.0ms p95, but timing is not geometric correctness. No production viewport-veil adoption. One bounded Pro consultation is pending; no private MapKit layers or global transaction flush are used.
- Grok's bounded read-only sharing-input audit completed with exit0. It confirmed that the legacy 217-stop UI test now loads a 14-passenger-stop production record; removed generated pass-through names are not real recorded input. A clearly labelled synthetic UI-only pending-record stress fixture is being prepared without restoring deleted production passes or reducing sharing assertions. Its build/UI verification remains pending.
- No commit, merge or push has occurred.

### Latest completed continuation checks

- Long-journey sharing: both actual UI tests passed in 87.918s, `/tmp/jtm-na-retirement/long-journey-fixture-ui.log` and `.xcresult`. The 217-row fixture is explicitly synthetic, UI-only and pending confirmation. Production retains its 14 passenger stops; removed unverified passing stations were not restored. Grok completed the bounded input audit; its editing attempt made no edits, and Codex implemented and validated the fixture.
- Utazu: two primary-evidence source boundaries bring the reviewed registry to ten. Explicit two-line, four-direction actual-source coverage passed; the initial unhinted reverse route selected the eastern bypass. Default routing and permitted movements remain under review; hinted success does not close that issue.
- Corrected native-anchor raster experiment ended NO-GO: 36/353 paired video frames exceeded 1px; scene 742 reached 16px over 74 sections. Visual inspection confirmed opposing 16–17px stroke offsets. Internal corrected holdouts can read zero while native pixels disagree. Paired work p95 was 3.458ms, but maximum update gap was 183.575ms, above the frozen 150ms gate. Evidence: `/tmp/jtm-na-retirement/viewport-anchor-final-evidence.md`. No production adoption or further timing retry.
- Automatic approval review rejected transmission of the viewport code/performance packet to ChatGPT Pro because it may contain unpublished project material. Nothing was transmitted; the owned tab was closed. Explicit approval is pending, and local work continues.
- Playback/video export device checks are running. The full Core and UI suites have not been certified; no commit, merge or push has occurred.

- Utazu default routing repair: both singleton endpoint line memberships now contribute together only when no stronger preference exists. The prior unhinted reverse Marugame failure is repaired; all eight hinted/unhinted directional solves preserve exact physical-boundary/source-hop/date/no-connector assertions. Twenty-eight focused tests plus section parity passed. Source identity boundaries remain unrestricted; no incoming-approach constraint or individual-turnout certification is claimed.
- Video first run: cancellation and playback-stop passed; natural completion failed the Haruka identity assertion because the DEBUG hook chose the first asynchronously available ride. Two resulting partial H.264 files fully decoded (142/152 frames, 10.850/11.208s, 282×540). The runner stalled after tests ended; the owned process was terminated, so no complete xcresult is claimed for that run. All three tests now explicitly select the bundled single-line Kodama record and assert its identity. Build-for-testing passed; rerun underway.

- Deterministic video rerun passed all three actual UI cases (105.856s), `/tmp/jtm-na-retirement/video-deterministic.log` and `.xcresult`. All assert the explicitly selected bundled Kodama record. The latest three H.264 files completely decoded: partial 154/157 frames and 10.892/11.187s; natural-complete 239 frames and 23.250s; all 282×540. Last-frame inspection confirms the two partial route views and the completed whole-route panorama with finished progress. Earlier two partial assets are separately retained and not counted as new results. `/tmp/jtm-na-retirement/video-assets-deterministic/manifest.jsonl` inventories all five retained files.
- Latest entire native production harness gate passed, `/tmp/jtm-na-retirement/native-current.log`. This covers current source ownership, typography, resource artifacts and lifecycle/geometry/persistence contracts; it is not full SwiftPM, full UI, or device performance acceptance.

- Current native service catalog baseline finished with 54 issues in 675.827s: 53 catalog patterns / 142 directional legs plus an overbroad service-expiry test. The latter now isolates surveyed same-line Shinjuku–Tachikawa before/on service expiry. That corrected test and a new service-display/apply/persistence versus absent physical-boundary test both passed (18.896s). The 53 catalog failures remain recorded, with no new exemptions; inventory `/tmp/jtm-na-retirement/service-current-failures.json`. A full rerun after the test-only correction has not been claimed.
- Four current production-map zoom/rotation UI tests passed, `/tmp/jtm-na-retirement/map-zoom-current.log` and `.xcresult`: Japan and Tokyo repeated zoom, iPhone rotation lock, and two-finger map rotation. Diagnostics record maximum display-link gaps 34/65/68/73ms, zero geometry builds during gestures, actual settled coverage/overlays and native callbacks. This is a current threshold check, not comparative performance improvement; it used an isolated owned simulator while a package test was also running.
- Seven-sample real import/relaunch reached all 287 map records and Japanese network rendering. Its large-dataset test then failed at the first repeated-toggle hit-point check (301.352s); no timeout or assertion was relaxed. Failure log `/tmp/jtm-na-retirement/map-all-samples-current.log`; final result collection stalled, so no complete xcresult is claimed. A pre-toggle image/layout diagnostic is being added to investigate actual control visibility.
- Archive inclusion repair: 101 ZIP/GIS payloads were silently excluded by generic ignore rules. The explicitly requested dated raw backup now has a narrow `.gitignore` exception. All 1,006 archival files are visible to Git and none are ignored. The archive remains outside all app resource inputs; no commit/push has occurred.
- Newly confirmed cross-section physical proof gap is being repaired: source-only legs could still receive a complete route outcome after a station-code/coordinate-only seam. The map drew no invented chord, but complete-distance eligibility could be falsely asserted. Qualified graph endpoint continuity, dated reviewed-boundary checks, cached/exact-path handling and proven-part mileage are in progress; the prior native PASS predates this new fix.

### Physical seams and dataset diagnostics (continued)

- Qualified section-end identities now govern continuation; exact recorded paths require real dated source edges and reviewed zero-geometry identity boundaries. Cached results without the `physical-section-continuity-v2` semantics are rejected. Source-proven partial mileage remains available to totals, while complete-journey averages require full proof. The native harness gate passed after this integration (`/tmp/jtm-na-retirement/native-frozen.log`); focused continuity/Utazu and mileage matching tests passed (15 tests).
- The full service continuity run completed with 109 issues / 7 tests, including 107 issues across 298 catalog cases (`service-physical-continuity-final.log`). This is a diagnostic baseline, not acceptance: an actual Azusa repro confirms that visual station-anchor filtering incorrectly removes the prior qualified physical endpoint. An exact-node continuation repair and new regressions are in progress. No catalog exemption or proximity connection is introduced.
- The subsequent 287-record UI run completed its result bundle but failed the old map-render count assertion (`map-all-samples-proof-retry.xcresult`, 235.717s). The failure recording visibly retains all 287 list records. DEBUG-only inventory now distinguishes persisted records, processing phase and physically drawable routes; both dataset and all-record performance tests retain 287-record completeness, finished processing, render-count consistency and their original interaction/performance gates. Latest test build passed (`map-record-inventory-build.log`); actual UI rerun is in progress.
- Nippori remains unapproved: primary investigation diagrams establish the corridor but do not independently map the candidate local source identity boundary. The bounded review is `/tmp/jtm-na-retirement/nippori-physical-evidence.md`; no registry edge or opening date was added.
- No commit, merge or push has occurred. Full viewport basemap dimming remains unimplemented; external code/performance consultation remains blocked pending explicit disclosure approval.

- Exact-node repair completed: 27 physical/topology/Utazu source tests plus eight Application matching tests passed, as did extracted physical-gap/cache and Passport harnesses. Actual Azusa's entire forward 2019-03-16 新宿→松本 chain now solves. The latest full native gate passed (`native-exact-seed-gesture.log`) and app build-for-testing passed (`physical-seed-gesture-build.log`). Full service-catalog rerun is underway; no final catalog PASS claimed.
- Actual 287-record failure screenshot revealed a modal overlapping-route chooser opened by the map drag, rather than a hidden rail/layout failure. The app's tap now explicitly waits for its own non-consuming manipulation sensors to fail; no MapKit internal recognizers are inspected. New drag-does-not-select assertion and the original medium-sheet hit checks remain. The entire dataset UI test passed in 434.600s: real seven-file import, persistence/relaunch, Japan network, three toggle/pan rounds and 75-second residence (`map-pan-selection-fixed.log`, `.xcresult`). Recorded map state still contains 287 drawable rides; no geometry was forced to meet that count.
- Remaining full iPhone UI suite is running (`full-phone-ui-current.log`), excluding the just-passed dataset residence case to avoid repeating it. Opt-in projection experiments retain their own default skip. This is not yet a full UI PASS, and no commit/merge/push has occurred.

### Latest full package and phone-device continuation

- The complete service catalog after the exact physical seed repair finished with 105 issues across seven tests (1,003.581s): 103 catalog issues across 298 cases and two cross-company assertions. There are 102 unique failed pattern IDs; the 385 directional leg entries include repeated assertions. No failing pattern was exempted and no unreviewed junction was added. Inventory: `/tmp/jtm-na-retirement/service-exact-seed-failures.json`; log: `service-exact-seed.log`. This remains an overall failed acceptance gate.
- All other package tests then passed, excluding only the catalog just executed: Core Swift Testing 844 tests / 105 suites (1,500.878s), Presentation 333 / 32 suites, Application 26 / four suites, and 48 traditional XCTest cases. The complete generated-history boundary test passed in 971.563s. Log: `/tmp/jtm-na-retirement/swift-all-except-catalog-current.log`. These results do not convert the separate catalog failure into a full package PASS.
- The full frozen-binary iPhone UI run has passed all six map zoom/rotation tests, including both 287-record regions; all four applicable playback layout tests including bounded AX5 and portrait rotation requests; and all three deterministic video export tests. The complete suite remains running and has other failures under investigation. The two LocalJourney tests have source repairs awaiting a fresh build/device run: reveal the real lazy Form proposal, and preserve an unresolved Keisei through-service as pending rather than invent a missing physical junction. The old landscape-sidebar test now applies only to iPad; phone rotation-lock tests remain intact.
- A separate public `MKMapSnapshotter` compositor feasibility review identifies a coherent owned-image epoch, but also unresolved finite coverage, pitch, native interaction and attribution requirements. The macOS-only standalone probe produced no image or coordinate points. One evidence-based `NSApplication` bootstrap correction compiled cleanly but the unchanged three requests still returned `Bad MKMapSnapshotOptions`; host-service connection errors were also logged without a verified causal relationship. Original and repaired receipts are preserved under `/tmp/jtm-na-retirement/snapshot-compositor-probe/`. Failed completion timings are not rendering performance. No additional configuration retries and no production adoption occurred.

- Complete frozen-binary iPhone UI results are now available: 126 registered cases, 77 passed, 36 failed, 13 skipped; exit 65, about 87 minutes. This excludes the separately passed dataset case. Complete bundle, exported attachments and structured summary are preserved as `full-phone-ui-current.xcresult`, `full-phone-ui-attachments/`, and `full-phone-ui-summary.json`. Failures include lazy editor/picker rows, under-tab scroll clearance, partial-route endpoint presentation, obsolete North America/phone-landscape fixtures, protected stop deletion, and a 501ms stress gap against the unchanged 500ms gate. No blanket UI PASS is claimed.
- Source repairs are awaiting a fresh independent-directory app test build and device reruns. Known endpoint locations are now read off-main from exact regional station identities and applicable date stamps, with conflict/invalid-location rejection; explicit framing includes those endpoint-only points without adding strokes, route proof or mileage. Three native endpoint verifier groups passed and were wired into the permanent gate. Under-glass scrolling now reserves measured system-tab obstruction only for scroll content; compact content remains mounted but cannot receive taps/accessibility. Explicit deleted visits are omitted from required search anchors while the original draft retains destructive-conflict approval. Original actual-hit, cancel, save/reopen and font/orientation gates remain.

- Latest independent-directory app/UI build passed (`ui-repair-build.log`) and the complete native gate passed (`native-ui-repair.log`), including endpoint date/identity tests. Targeted UI now confirms the previously failing empty-number completion flow (30.533s). Both LocalJourney flows reached the correct apply/pending-confirmation states, then exposed the shared test helper's inability to find lazy rows above the current scroll position. The helper now searches both directions within its original eight-drag budget and uses the Form gutter; rebuilt UI validation remains pending. No production route or font constraint was changed for these harness fixes.


### Targeted UI and compositor follow-up

- `ui-repair-routing2.xcresult`: physical endpoint autofill + insertion + Undo passed (54.283s). Pending through-service flow reached the retained service leg; its later train-number replacement failed because deleting from the tapped cursor left a suffix. The test now selects the entire existing native field value before replacement and still requires exact equality. Ordinary correction reached the unchanged protected-stop summary but inspected a lazy projected list before scrolling; bounded reveal is added before the same exact-station assertion. Neither subsequent flow is yet accepted.
- `ipad-playback-hit-boundary.xcresult`: all four applicable iPad playback hit checks still failed; the landscape sidebar passed. A card `contentShape` experiment did not fix the problem and was removed. An opt-in passive public `UIView.hitTest` probe records the root SwiftUI hosting view at the button center, rather than a covering UIKit child; it does not identify a specific SwiftUI hit node. Root composition now places independent playback/map controls above the dock's native TabView; fresh build and actual hit rerun are pending.
- `ios-snapshot-probe.xcresult`: the opt-in UIKit XCTest runner's first public Tokyo snapshot did not complete within the fixed 30s deadline. It was cancelled and no further requests were made. No PNG, static projection result, throughput result or production compositor acceptance is claimed. This complements the separately failed macOS CLI-host probe; runtime-host/service cause remains unverified.
- Targeted current map rerun has passed region focus, selected journey camera preservation, separated Haruka endpoint labels, installed route retention under gestures, and explicit selection with automatic focus disabled. The nearby overview endpoint-label assertion also passed, then the test failed on obsolete `journeyMenuClose`; production exposes `journeyBackToList`, now used consistently with the other camera test. The unchanged maximum-distance plateau check still failed (5,358.7m versus 1,000m tolerance) with the centered gesture target; it remains unresolved, with no tolerance increase or forced camera clamp.

- Root-layer iPad experiment completed: all four playback hit gates still failed; both dock menu regressions passed. The ineffective layer reordering was reverted. The explicit Kodama playback fixture also failed the original hit gate, so asynchronous route selection alone does not explain the problem. A stable button-level hit rectangle is being tested separately from the replacing SF Symbol.
- The targeted map/panel run completed with 8 passed and 5 failed (full results in `ui-repair-map-panel.xcresult`); Tokyo station open/dismiss passed, replacing the retired Hoboken fixture. The corrected nearby-selection return control subsequently passed (24.006s). Native tab-clearance diagnostic exposes `tabBarOcclusion:0.0` despite a visible 79.697pt tab bar. The representable's `tabBarController` containment lookup does not measure the actual SwiftUI-hosted bar; a same-window public UITabBar fallback is being validated. No viewport shrink or detent feedback is added.

- Pending-service final rerun passed (134.678s, `ui-repair-routing3.xcresult`): exact endpoint identities/order and service leg are preserved through Save, UUID-isolated storage, relaunch, search and editor reopen; no physically unproved railway route was applied.
- Tab containment inference was disproved by the read-only geometry receipt: the probe has a real public SwiftUI UITabBarController, but its UIKit viewport ends exactly at the tab top (iPad probe bounds 411.5×255, window y485; bar local y255). The SwiftUI content extends beyond that safe-area host. The ineffective window traversal fallback was removed; the probe now lives inside the actual GeometryReader-sized scroll content and has that exact frame. Result awaits device rerun.
- Fixed button-level rectangle experiment also failed the unchanged iPad playback hit gate and was removed. This is not explained by early playback completion: the deterministic Kodama run paused at 31% while AX still reported the action not hittable. A DEBUG-only single compact layout probe isolates the two nested ViewThatFits candidates; no production layout replacement is yet adopted.
