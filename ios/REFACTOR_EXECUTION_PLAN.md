# 工作区与地图渐进重构执行计划

## 基线与约束

起点为 `9d14f71` 加已有未提交修改（18 个修改文件、10 个新文件）。保留这些修改，不重置或提交工作区。上一轮只读审查的完整验证通过：RailCore 310、RailPresentation 207、iPhone UI 19、Python 562、Node 5。iPad 可点击性用例在当前树与干净 HEAD 同样失败，作为既有失败跟踪。

RailCore 只依赖 Foundation；RailPresentation 只依赖 Foundation/RailCore；平台操作留在 RailMap。AppShell 保留共享 store、唯一 PlaybackController 和单一地图。工作区保留选择、搜索、筛选、弹窗协调和组件连接，不创建全能 ViewModel。缺陷修复与行为保持型拆分分别验证，不修改 fixture 或铁路发布数据。

## 责任边界

| 所有者 | 输入/职责 | 输出/边界 |
| --- | --- | --- |
| AppShell | 共享 store、播放控制器、目的地 | 向工作区和地图注入同一实例 |
| RailWorkspaceView | 状态所有权、缓存派生结果、业务入口连接 | 面板内容、已解析操作、呈现绑定 |
| 工作区呈现/面板组件 | 窄输入和操作回调 | 保持身份的视图层级；不自行保存或重新计算业务数组 |
| JourneyEditing / ImportFlow / VideoExportFlow | 普通编辑/导入/导出各自生命周期 | 保持既有保存顺序、反馈和取消语义 |
| RailMapController | 相机命令和框选状态 | MapKit 相机及控制器状态同步 |
| MapRebuildPolicy / 几何缓存 | 输入变化、LOD、builtRect、预算 | 是否重建及可复用几何 |
| overlay 更新边界 | 已构建几何和样式 | MapKit overlay 安装；不吞并播放、标记或图层职责 |

## 分步实施

### 1. 当前改动缺陷
- [x] 导入地区状态与报告共用生命周期；取消、重开保留一致地区，提交 guard 保留。
- [x] OSM 四边界缓存命名迁移后，读取者只采用一致的有效缓存集合；覆盖旧缓存共存，避免删除用户缓存。
- 验证：新增状态转换 UI 回归、缓存迁移 Python 测试；完成 Swift/app 编译。

### 2. 工作区组件边界
- [x] 提取系统 TabView 及面板布局，保留页类型擦除和常驻列表/详情的身份。
- [x] 提取弹窗呈现协调组件，状态绑定和删除入口留在工作区，保持 teardown 后操作。
- [x] 提取面板操作内容，输入来自已有 resolver；不重算筛选、搜索或日期数组。
- 验证：`ios/verify.sh --swift`；列表返回、搜索、面板横竖屏、播放 UI 回归。

### 3. 地图网络渲染边界
- [x] 以实际调用关系分离几何缓存状态及 overlay 更新；继续复用 MapRebuildPolicy。
- [x] 保留 builtRect、LOD、预算、命中几何、RenderStats 和样式独立更新路径。
- 已有相机命令主要位于 RailMapController，不为制造改动再次迁移。
- 验证：规则边界测试、Swift/app gate、图层开关和地图密度 UI 用例。

### 4. 单独处理既有缺陷
- [x] 严格 JSON 词法，保留合法 JSON 与 JS 数字语义；补非法数字、控制字符及合法边界测试。
- [x] IndexedDB 预热结果受地区/代次限制，旧回调不能污染新会话。
- [x] Web 播放开场暂停使旧 moveend 回调失效；补暂停、恢复、停止转换测试。
- [x] 详情 sheet 在首次呈现时也检查记录是否存在，缺失时关闭，避免空白页。
- [x] 修复主题色切换和减少透明度/增强对比度级联；主题行为测试通过，CSS 完成独立静态复核，真实浏览器验证未完成。
- [x] 对多 dataset part 路线补行为证据；仅有明确收益时调整聚合，不强行拆 RiddenRouteStore。
- 已检查七个实际数据集的全部 287 个 part：每个数据集内均无重复 train ID。多 part 覆盖问题仍是条件性风险；本轮保留路线管线，避免在无当前调用需求时改变缓存聚合语义。
- 验证：对应真实模块回归测试；fixture 不变。

### 5. 验证工具与文档
- [x] verify.sh 合计全部 Swift Testing 目标摘要；保留检查强度。
- [x] 统计规则契约覆盖 WorkspaceJourneyRules；CI 路径覆盖相关源文件/构建配置。
- [x] 仅更新实际改变的职责、接口和操作说明。

### 6. 整体验收
- [x] 完整 `ios/verify.sh`、Python railway 测试、Node 测试、`git diff --check`。
- [x] 实际 iPhone UI 回归；iPad 用例与既有失败对照，不用构建代替 UI 测试。
- [x] 独立复核修改，记录实际结果、未完成项及原因。

本计划按可编译、可独立审查的步骤推进；复现不足的问题先验证，不将假设写成已修复事实。

## 执行记录

- OSM：新旧缓存共存、父子分片、重复 way 更新回归 11/11；全套 Python 566/566。旧文件保留，出现新格式后采用新格式集合；未完整下载仍须遵守下载器非零退出。
- JSON：词法边界测试 5 项（含全部 32 个 C0 控制字符），RailCore 315/315；合法输入和现有 fixture 通过。
- 验证摘要：用上一轮实际日志核对合计为 517，替代原先只报 310；shell 语法检查通过。
- 整合 `ios/verify.sh --swift` 通过：RailCore 315 + RailPresentation 207，共 522；应用编译与源码契约通过。日志：`/tmp/jtm-refactor-integrated.log`。
- 新增导入状态转换 UI 用例通过：手选 Taiwan → 预检 → 取消 → 重开，地区与可提交报告均保留。日志：`/tmp/jtm-refactor-import-ui5.log`。该用例同时暴露 DEBUG 自动呈现任务在取消后继续执行的问题；现已遵守任务取消并只执行一次，生产呈现路径不变。
- 独立复核已检查工作区组件连接、导入状态和地图提取，未发现新增回归；iPhone 完整 UI 已通过，iPad 对照已完成，最终完整 gate 通过。

## 保留与后续事项

- `RiddenRouteStore` 保持原有取消、loadRevision、缓存优先级和缺失区间语义，不因文件长度拆分。
- iPad 宽屏用例的地图开关可点击性是当前树和干净 HEAD 均复现的既有失败；最终重跑当前树仍在同一可点击性断言失败；未删除或放宽检查。
- 本轮复核另观察到导入预检未绑定旅程 store 版本。现有可到达路径及实际影响仍需单独验证；它不属于此次地区生命周期修复，不宣称已经解决。

- iPhone 17 Pro / iOS 27：完整 20 项 UI 回归通过，0 失败；包含连续平移复用、横屏密度、列表返回、搜索、面板拖动、编辑、导入重开与播放。日志：`/tmp/jtm-refactor-iphone-ui.log`；结果：`/tmp/jtm-refactor-ui/WorkspaceRegression.xcresult`。

- iPad Air 13-inch (M4) / iOS 27：宽屏用例失败，仍为 `RailMapUITests.swift:314` 的 `mapNetworkToggle` 可点击性；此次错误为无有效点击点，干净 HEAD 基线为相同断言等待超时。日志：`/tmp/jtm-refactor-ipad-ui.log`；结果：`/tmp/jtm-refactor-ui/IPadRegression.xcresult`。基线日志：`/tmp/jtm-ui-ipad-head-baseline-20260907/run/LayoutSmoke-46321.log`。
- Web：`npm test` 9/9 通过，覆盖地区/缓存代次、旧 IndexedDB open/cursor、播放暂停/恢复/停止、播放中换肤且不重建 source。日志：`/tmp/jtm-refactor-node-final.log`。
- CSS：独立评审发现并关闭窄屏 docked 双 ID 选择器覆盖无障碍偏好的遗漏；没有使用 `!important`。真实浏览器 computed-style 验证因 CUA Safari 卡住中断，尚未完成，不以静态复核替代。
- `npm run lint` 无法启动：现有 package script 引用缺失的 `app/scripts/validation/check-source.mjs`。未删除检查或改为无操作；日志：`/tmp/jtm-web-theme-lint-20260907.log`。

## 最终验收（2026-09-07）

| 验证 | 实际结果 |
| --- | --- |
| `SCRATCH=/tmp/jtm-refactor-integrated/build ./ios/verify.sh` | 通过；fixture 一致，RailCore 315 + RailPresentation 207 = 522，应用构建和源码契约通过 |
| iPhone 实际 UI（smoke 脚本相同目标集合） | 20/20 通过，无跳过 |
| iPad 实际宽屏 UI | 既有地图开关可点击性断言失败，见上述 HEAD 对照 |
| Python railway unittest discover | 566/566 通过 |
| `cd app && npm test` | 9/9 通过 |
| `git diff --check` | 通过 |
| `npm run lint` | 无法启动：现有检查脚本缺失 |
| Web CSS 浏览器计算样式 | 未完成：浏览器工具阻塞；静态独立复核通过 |

最终 gate 日志：`/tmp/jtm-refactor-verify-final.log`。Swift 完整日志：`/tmp/jtm-refactor-integrated/build.log`。Python 日志：`/tmp/jtm-refactor-python-final.log`。

本轮 UI 命令增加 `-collect-test-diagnostics never`，避免本机失败后的系统诊断收集挂起；仍执行全部选定断言并保留 xcodebuild 日志和 xcresult，未修改测试门槛。未提交工作区，未修改铁路发布数据或 fixture。
