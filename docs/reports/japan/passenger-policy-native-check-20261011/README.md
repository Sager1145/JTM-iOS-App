# 客运代表走廊政策：Mac App 实际复核（进行中）

依据 [客运代表显示政策](../passenger-representative-display-policy-2026-10-11.md)，使用重新构建的 Rail Alignment Inspector 和 RouteWorkbench 实际检查。两个 App 的包内容与本轮源包一致。平滑证据版本为 `inspector-centreline-v5-preserve-small-survey-curves`，旧版本截图不作为新版通过证据。

## 当前结果

- RouteWorkbench：201/201 条既有行程返回，解析耗时 380.807 秒；0 项一致性失败、929 项待审阅。时间属于本次真实批量解析，不表示性能提升；全部物理连接未证明。
- Rail Alignment Inspector：全量队列 658 条线路、9,580 个区间、92,218 个视点。已启动“自动检查全部区间”，按风险排序，单个快照串行进行；本轮结束时继续运行。实际采集数量见 `review.json` 和批量报告快照。
- 人工逐图复核：箱根 18 个、木次线 38 个、京叶线 35 个，共 91 个 z17 视点，覆盖六个完整区间；图像采集成功不等于地理判定通过。
- 大平台与三井野原：现场 z18 隐藏/恢复叠加比较。代表站点看起来位于蓝色站区内部，并落在苹果原有铁路走廊、靠近平台中部；未测量像素残差。车站周围的整个区间仍待复核。

## 仍需调查

箱根保留了真实小弯和独立折返支线，长区段仍有苹果/源几何差异。木次线出云坂根折返上游、三井野原—油木连续交替弯道仍有位置差异。京叶线东西分岔分别保留，但北侧咽喉、南側弯道及平台走廊仍需调查，不能判全段通过。大鰐温泉—大館物理路径和大館—鷹ノ巣入口仍未证明，实际行程 `スーパーつがる2号` 为 4/6 部分完成。

本轮没有仅凭底图差异移动源铁路；箱根此前独立地理院证据仍须参与判断。所有待调查项按客运连接和独立位置证据修复，之后重新采集受影响区段。

## 验收边界

原生批量队列覆盖整个输入库存；停运、替代巴士、非客运区段不作为所选日期当前客运线路验收。通过站仍可属于运营客运线路。Inspector 当前预览是独立中心线，不包含主产品公司平行线与 family 合成；截图不能证明这些政策项已全部满足。站点数量、跨公司共线、日期有效性和主产品合成仍有待审阅项。全线路人工复核尚未完成。

## 证据

`route-workbench-report.json` 是实际 App 导出的完整处理报告。`alignment-full-plan.json` 与 `alignment-batch-report-snapshot.json` 是实际原生计划/报告的快照。完整实时截图与恢复记录保留在 `~/Library/Application Support/RailAlignmentInspector/BatchEvidence/`。逐视点与站点观察见 `review.json`；本目录联系图仅用于人工阅读，原生 PNG 保留。

## 多实例与并行分析

一个子代理负责 native 截图，另外两个并行分析箱根、木次与京叶，分别写入 `parallel-hakone-analysis.md`、`parallel-kisuki-keiyo-analysis.md`。独立复核同一批91视点，不重复计算为新增验收覆盖。

Inspector 支持包内 `JTMInspectorBatchOutput` 绝对路径，CLI `--batch-output` 仍优先。显式输出目录同时隔离人工 `reviews.json`；未指定时保留原默认历史。没有改动几何、拓扑、平滑或源数据。默认实例执行唯一全量采集，Hakone / Kisuki Keiyo 实例用于不同地点的手动比较。

统一版本与图标后的实例状态见 `parallel-instance-status.json`、`capture-owner.md`。版本为0.1、build2；三个实例保持不同bundle ID与证据目录，来自同一增量构建。版本设置也已写入工程Debug/Release，工程plist语法检查通过。完整地理验收仍进行中。
