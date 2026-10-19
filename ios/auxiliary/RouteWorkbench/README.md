# Physical route workspace

Mac Catalyst 辅助工作台，复用 Japan Train Map 的生产线路解析与打包数据库。

这是 RailDiagnostics 内部工作区，不再有独立 app/工程。构建与请求入口见 [RailDiagnostics](../RailDiagnostics/README.md)。

导入标准行程 JSON，运行批量解析，选中行程查看部分结果和物理连接缺口。取消保留已经返回的结果。导出菜单提供行程文件与状态报告；不会覆盖导入文件。

行程搜索无匹配时显示空结果提示。重新导入后，若原选中行程不在新文件中，会清除该选择及「仅当前行程」筛选，避免把新批次的检查结果隐藏。

行程导出仅补入完整、当前轨道、有可靠区段来源且能按端点回放方向的有序 `section_codes`。已有显式选择保持，重复经过次数保持。历史几何、部分结果、待确认路线和无法对应规范区段的记录保留导入内容。iOS 导入后继续执行自身物理验证。

列表使用结果 ID 索引；多地区导出按 scope 分组，避免逐行反复构建地区网络。批量解析仍使用生产求解器及其并发限制，现已接入同一 RailCore 的数据库子路线证据、停站 run 推断缓存、走廊请求复用、snapshot 区段/跨图物理证明缓存及共享冷请求。数据库只提供经验证的完整物理证据；其选择仍经过生产拓扑与日期验证。报告包含 processLifetime 共享任务、合并请求及缓存命中计数。

2026-10-10 用户已授权执行检查和修复。已有 61 项针对性测试通过；批量失败报告修复后，17 项检查核心测试通过。Catalyst 增量构建和实际启动通过，原生工具栏崩溃已修复。完整 201 条 JP 行程批次约 408.8 秒；更新显示资源并修复 930 项提示的辅助功能遍历卡顿后，新批次约 392.1 秒。同一新进程的暖缓存复跑约 0.338 秒，201 条状态与 930 项提示完全一致，未新增共享求解任务。计时为线路加载，不包括导入和后续检查/导出；这不是优化前后首次求解的加速对照。197 条几何已解析、4 条部分解析，0 项一致性失败、930 项证据待审阅；几何解析不等于所有物理区段已被证明。

设计与后续优化见 `../../../docs/superpowers/specs/2026-10-10-route-workbench-design.md` 和 `../../../docs/superpowers/specs/2026-10-10-route-resolution-rethink.md`（相对于仓库根目录的 `docs/`）。

## 检查工具

解析完成或失败后自动检查当前批次并写出报告，失败原因单列；取消后可手动选择「检查结果」，保留已返回的结果。检查输入/结果 ID、区段覆盖、multipart 一致性、几何有效性、物理缺口、显式区段顺序、网络方向回放和数据库来源，并实际回读导出 JSON，比较行程元数据与已提供选择。失败表示一致性错误；待审阅表示证据不足或部分结果，不自动认定线路数据错误。提示列表按可见区域加载，可筛选失败项并定位行程；完整报告仍保留全部提示。

单批次本地调用：向 RailDiagnostics 提交 `workspace: "route"`、`action: "solve"`、`inputPath` 和独立 `sessionDirectory` 的请求（见统一请求文档）。读取指定输入，运行生产求解及检查，原文件不变；检查结束后原子写入报告，窗口保持可查看。不提供全库自动流水线。

详细报告使用 schemaVersion 2，保留原来的 rows.id/number/status。每条行程另记录期望/已解析区段数、编号是否可靠、未解决区段端点及边界标志、物理缺口、每个显示分段的身份、方向有序的 interval、来源和数据库班次/运营日/版本。报告不复制几何坐标。未知覆盖不会用期望数填成已解析数；sectionIndex/segmentIndex/partIndex 从 0 开始，界面从 1 显示。timingScope 为 routeLoad，导入和检查耗时单列；检查耗时不包括最后的报告写盘。

左侧可搜索行程、编号和端点。选中行程后，详情位于全局提示之前，可展开区段身份与来源。提示可按失败/待审阅、文字或当前行程筛选；筛选只影响界面，导出始终保留全部结果与提示。批次阶段与失败原因进入报告，取消后的未返回行程保持未知覆盖。

历史 Logo 位于 App/Assets.xcassets/RouteWorkbenchIcon.appiconset/logo.png；它不再对应独立 app。当前产品图标与入口由 RailDiagnostics 工程负责。设计提示见 LOGO.md。

当前检查计划和实际结果记录在 docs/superpowers/completed/2026-10-10-route-workbench-inspection.md。源码检查和实际测量分开记录，报告中的共享计数是 processLifetime。

新一轮工具完善和仓库分类记录在 docs/superpowers/completed/2026-10-10-workbench-diagnostics-and-repository-organization.md；全仓库分类入口见 docs/repository-organization.md。
