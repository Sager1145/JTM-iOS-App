# 时刻表与历史线路时间对齐

> 本文保留前一阶段的验证快照。2026-09-28 的新增数据、最新数量及验证结果见 [补齐报告](train-timetable-fill-report.md)。

本轮实现日期契约与接入修复，仍不表示全部 JR 历史数据库完成。

- 运行日统一使用日本服务日。跨午夜 25:03 保留次日时间含义，车次与线路有效期查询仍用原运行日。
- 历史有效期统一为起日包含、止日不包含；service_validity 优先，legacy 字段按键存在判断，不能因 null 改用基础设施有效期。
- 编辑器日期变化现在同步到地图预览，包括只修改日期、选择精确车次、清除日期；取消后回到已保存车次。
- 精确车次应用保留每一对停站的明确线路/运营商约束；不能证明边界、隐藏中间经由区段或运营商区间不匹配时继续只读。
- SQLite 快照核验检查历史线路版本和内容哈希、车站包、规范数据、Web/iOS 求解器版本、时区及资源副本。已接入 ios/verify.sh；求解器元数据已更新到 24。
- 路线缓存使用历史内容哈希。同版本号的内容变化也会使旧缓存失效；预计算路线缺少哈希证据时改为现场求解。

本轮审计展开 10 个车次的 77 个日期班次：0 个已证实历史站点检查、0 条已录入线路区段、10 个线路证据缺口、0 个已发现时间冲突。全部仍未核实，complete=false。没有把“没有发现冲突”当成线路验证通过。

验证：26 项 Python 管线/快照测试与 3 项来源解析测试通过；15 项时刻表/服务日 Swift 测试、8 项草稿地图/历史哈希测试、19 项既有历史线路测试通过。iOS 模拟器应用编译 BUILD SUCCEEDED；最终增量编译 BUILD SUCCEEDED，应用中的历史线路与 SQLite 资源逐字节匹配此次核验快照。未重跑上一轮 874 项完整 gate 或长 UI 测试。

当前历史线路 revision 为 2026-09-27.2，内容 SHA-256 为 `ccdc5b5dc1d328a74cef27f8bf91c6bf6e8b42c0128b6ec660ed7ed8e25dfb5a`。SQLite SHA-256 为 `a8ef436f63ede608ffc07e4eb80cacf2663e85be80b3b8870e2e63be33c16a15`。它们绑定本轮验证时的工作树快照；并行历史线路改动保留，未纳入本任务提交。

下一步仍需将六 JR 原始日表及按日期的线路、运营商区段证据逐条入库。预计算生成器与 201 个样本分片需要共同重算并添加 history_hashes；当前旧分片可能触发首轮较慢的现场求解。本轮不伪造预计算来源，不直接给旧几何补哈希。

使用命令：

```sh
python3 ios/tools/build-train-timetable-db.py
python3 ios/tools/verify-train-timetable-artifact.py
python3 ios/tools/audit-train-timetable-history-alignment.py
```

审计明细：`app/data/train-service-history/audits/train-timetable-history-alignment.json`。

发布门控限制：历史对齐审计目前是独立报告，尚未进入运行时 canApply 门控；未来加入线路区段前，应接入已验证审计结果。当前 10 个车次都没有线路区段，因而均保持不可应用。
