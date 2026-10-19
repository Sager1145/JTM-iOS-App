# Route Workbench：Mac Catalyst 辅助 app

状态：辅助 app 源码已实现，尚未编译或运行。用户已授权编写 Mac Catalyst 辅助 app，随后明确要求本轮「先完成源码，暂不运行」。按导入、批量解析和导出工作台的默认范围完成。

## 使用方式

独立 Route Workbench app、独立 bundle identifier 和应用容器。导入与 iOS 相同的行程 JSON。运行批量解析，显示已返回结果/总数、截至最近结果发布的耗时、每条行程的 resolved/partial/unavailable/待确认状态；可取消。「已返回结果」不等于成功数量或全部已处理数量。只导出新文件，不写回输入文件或 iOS 用户库。

第一版复用生产 RiddenRouteStore、RailCore、RailPresentation、RailApplication 与已打包地区数据。用独立 Xcode target/scheme 和编译条件进入工作台界面；生产 app 的界面和行为继续使用原入口。这样同一份源码负责日期、物理连通、历史路线和线路方向，不维护第二套求解器。

输出标准行程 JSON：只把完整、有序且已确认的 physicalRoute intervals 补入尚无显式区段的 route_sections。原来已有明确选择时保留；partial/unavailable、历史轨道、空 intervals 或无法确认索引对应时保留导入记录。只接受生产 explicit/stationSequence 来源，拒绝 matchedGeometry；合并同一 section 的 multipart 时要求所有部分选择一致，只写一次区段序列。逐索引匹配端点、覆盖全部 section，并用 network.directedIntervals 回放方向与重复经过次数，确保旧 JSON 格式能重建选择。导出不宣称免验证：iOS 仍按其自身资源版本和物理连通规则验证。另导出每条行程的处理状态报告；暂未提供求解器阶段耗时或缓存命中统计。

此版本的作用是提供真实批量工作台并固化已有结果。它不会仅因使用 Mac 就宣称已解决旧求解的计算复杂度；后续优化以 route-resolution-rethink.md 的区段缓存/证明复用设计为依据。

## 交互与状态

一个窗口：工具栏导入、运行/取消、导出；左侧行程列表，右侧结果/失败详情。空、已导入、运行、完成、取消和失败状态由 @MainActor @Observable 工作台 model 持有。文件读取、解析、导出编码及生产求解使用现有后台流程；界面接收结果快照。导入记录独立保存，不把东京线路默认偏好提前写入输出。取消前保存结果快照再清空生产 store。列表与报告共用 ID 索引，多地区导出按 scope 分组、保留原顺序，避免 DisplayNetworkCache 单 scope 缓存反复重建。列表保持稳定身份；重复导入 id 使用现有 import 规则。大字体仍限制 .xSmall ... .xLarge。使用系统控件、键盘快捷键和可访问文本状态，无额外动画或地图渲染负担。

## 技术边界与检查

资源复制继续使用生产 builder 和数据；构建脚本中对已退役 verifier 的失效调用需要移除或在辅助 target 使用没有该调用的等价资源阶段，不能复活 verifier。保留实际数据 builder、物理拓扑限制和美国/加拿大退役边界。

已写纯逻辑回归：已确认区段补齐、显式选择不被覆盖、部分/待确认/错误索引/端点/方向/约束拒绝、重复经过保留顺序。用户要求暂不运行，因此测试尚未执行。下一轮若恢复运行，仅执行相关回归和一次协调后的 Catalyst 构建，观察小规模导入、取消与导出。没有性能跑分或改善倍数结论。

生产 load 仍包含现有 traversed line 检测；资源阶段仍会执行现有 display 数据 builder。这版先复用其行为，未实施独立的无地图求解入口。随后用户要求开始修复生产重复计算，已在共享 RailCore 写入停站 run 推断缓存、走廊请求复用和图内物理证明缓存，见 route-resolution-rethink.md 第一批记录；跨图共享和数据库子段匹配仍未实现。源码审阅已检查相关 Swift/JS 区段格式、共享包引用与资源脚本路径；独立审阅发现的未证明偏好泄漏、O(N²) 状态查询及跨地区网络重建问题已修正。工程 plist/scheme 格式检查通过，不代表 Swift 编译通过。

## 实施文件

新增辅助 Xcode 工程/scheme 与工作台 SwiftUI 文件；生产入口只增加编译条件路由；必要的纯导出函数放在可测试的 RailCore 或辅助包。保存设计和执行结果说明。不提交、不推送、不发布。
