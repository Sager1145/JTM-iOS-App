# 全 JR 历史特急数据库实施报告

> 本文保留前一阶段的验证快照。2026-09-28 的新增数据、最新数量及验证结果见 [补齐报告](train-timetable-fill-report.md)。

截至 2026-09-27。本次完成数据库基础架构、经出处核对的少量数据录入及运行时接入，**未完成全部 JR 历史特急数据搜集**。`coverageComplete=false`；不能据此宣称 100% 完整。

1. **架构**：canonical JSONL → 字段来源与日期验证 → 确定性 SQLite → 懒加载逐日查询。来源候选、规范事实、派生兼容投影和覆盖审计分开。
2. **修改文件**：`app/data/train-service-history/` 为数据与审计；`ios/tools/*train*timetable*` 及解析、规范化工具为管线；RailCore 的 `TrainTimetableDatabase.swift`、`TrainServicePatterns.swift`、Package.swift 为运行时；`ServicePatternPickerView.swift`、`RideEditorView.swift` 为界面接入；Python/Swift 测试及本报告为验证。
3. **Schema**：25 张表，涵盖 operators、services、service_name_periods、timetable_versions、trips、stop_times、calendars、calendar_exceptions、trip_stop_time_overrides、trip_number_segments、trip_operator_segments、trip_line_segments、trip_relations、source_documents、fact_sources、station_identities、覆盖/完整度、研究任务、节日和实际运行事件。
4. **JR services**：5 个已录入身份（カムイ、ライラック、しなの、ひたち、ゆふいんの森）；不等于全部 JR 特急。
5. **历史身份**：1 个 1912 年新桥—下关特別急行身份，只有首次运行日期及端点出处，尚无精确车次时刻表。
6. **时刻表版本**：10。
7. **车次模板**：10。
8. **按日期代表的班次**：77。仅计算已录入、日历明确的样本。
9. **停站记录**：86。缺失的中间站到达/发车时刻保持 null。
10. **按公司覆盖**：见下表。六家运营商成立日期均有官方出处；没有一家全量日表覆盖。

| 范围 | missing 单元 | partial 单元 | verified no-service 单元 |
|---|---:|---:|---:|
| jr-ancestral-national-railways | 576 | 0 | 32 |
| jr-central | 313 | 7 | 0 |
| jr-east | 313 | 7 | 0 |
| jr-hokkaido | 314 | 6 | 0 |
| jr-kyushu | 314 | 6 | 0 |
| jr-shikoku | 320 | 0 | 0 |
| jr-west | 320 | 0 | 0 |

每个单元是公司/年份/事实维度，不能换算为班次数完整率。

11. **年份/时代覆盖**：1912–1987 缺少连续原始时刻表；1987–2025 六 JR 历史时刻表未完整录入。2026 仅四家公司少量日期样本。1945–1948 的全年单元为有出处的无特急运营；这不是有车次的时刻表覆盖。1944/1949 只有保守区间证据，全年仍缺失。
12. **最早核实身份**：1912-06-15 新桥—下关特別急行。最早精确停站时刻表样本为 2026-05-16；不能将身份日期当成完整时刻表日期。
13. **当前覆盖**：77 个日期班次；数据库最后一个样本服务日期为 2026-09-27。JR 西日本、四国尚无规范化精确车次。
14. **历史来源缺失**：历次改正的原始《時刻表》、铁路省/国铁原表、临时列车运行日表、合并拆分与改号证据。NDL 目录只是定位材料，不证明未读取内容。
15. **车站映射**：42 个样本车站身份；研究队列有 1 个未解决映射项目（历史首班相关）。这不是全部历史车站已解决。
16. **历史线路**：研究队列有 11 个路线项目；全部样本尚缺完整、按日期的线路与运营区段证据。历史专属站可查询，但旧编辑器暂不能应用。
17. **来源/许可**：登记 31 个研究来源。明确限制来源为 JR 西日本时刻表门户及 Thunderbird 1 页面；12 个来源仅供核对。其余 unknown 许可不能理解为允许批量再发布。未提交受限制原始数据库或整页扫描件。
18. **测试**：17 项 Python 管线及原始出处 golden 测试、3 项 JR East 解析测试通过；SQLite integrity_check=ok、foreign_key_check 为空；重复构建字节相同；3512 个旧站点引用及 298 个有效期迁移检查通过。最终数据库资源上的 Swift 运行时 12 项专项测试与 iOS 27 模拟器应用编译已通过；数据库冷启动打开及按日查询小样本实测约 3 ms，最终资源在并行构建负载下约 98 ms，`./ios/verify.sh --core` 输出 OK：874 项 Swift 测试及编辑/持久化/订阅 harness、导入边界检查通过。此全量 gate 启动于最后的直通策略修改之前，该修改已在最终 12 项专项测试中单独编译验证；新增跨午夜 day_offset 回归验证 01:03 + 次日保存、重开后仍为 25:03，最终专项冷查询约 10 ms。
19. **Route audit**：76 段样本乘客停站之间的路线前置条件未验证，solver 未运行；报告 `complete=false`，不把缺乏 route/operator 的样本开放为可靠路线选择。
20. **UI regression**：专用 iOS 27 设备上，草稿丢弃（86.962 s）、保存后重启（55.827 s）、日期变更保留编辑（37.269 s）分别输出通过。只读精确车次用例单独运行通过（29.161 s，TEST SUCCEEDED），验证しなの的 07:00、名古屋、未确认状态及无应用按钮；结果位于 `/tmp/jtm-runtime-readonly-agent-2.xcresult`。用例补齐既有“置き換える”确认步骤，未因此修改产品行为。这四个用例来自分别运行的结果，不能理解为同一批全套 UI 测试通过。共享设备首轮受另一测试任务并发影响；失败断言与运行器异常没有计作通过。旧 298 Pattern 全部保留，派生的 8 个 Pattern 不能替换旧目录。精确车次不可简单反转；日期改变保留用户编辑并提示重核。
21. **生成产物哈希（SHA-256）**：

- `derived/train-service-timetable.sqlite`：`a8ef436f63ede608ffc07e4eb80cacf2663e85be80b3b8870e2e63be33c16a15`
- `derived/train-service-patterns.json`：`edb460d0661d9862297df42d4a5dbaac091925446cf9188ad97aa3e3faaa8b6f`
- `audits/train-timetable-coverage.json`：`42dbbcc0fa46d3f829ee766c4299c618a91cf2795cdedd74027ac53d11135c3a`
- `migration/legacy-pattern-map.json`：`f71474289ce37c84162aa5556295f98c3286ecb038d086e45f96cd4b64c9516d`

Canonical source hash：`3b9b1e8b369b4848aecb5a7f5a45c482afb20ad17bee02d5c0c5d1317029ddcc`。SQLite 为 417792 bytes；RailCore 资源副本字节相同。

22. **100% 完整之前的明确剩余门槛**：六 JR 当前全车次清单、每条停站时刻和运行日；1987 至今所有改正版本与临时班次；1912–1987 原始日表和服务身份；历史站点/线路/运营区段、改号/合并拆分及路线求解；历史节假日证据；来源冲突审理和许可处理；历史站点在用户编辑器中的应用；改号区段、合并拆分关系及实际事件的运行时查询界面；完整站站时刻详情页；所有旧 Pattern 的经证据迁移与完整界面回归。当前 2470 个覆盖单元 missing、26 个 partial；冲突计数 0 只描述现有小样本。

状态含义：**verified** 必须有对应字段证据；**partial** 表示仅部分字段或日期；**missing source** 是未取得事实资料；**license blocked** 是明确使用限制；**verified no-service** 需证明无运行；**conflict** 需保留争议与处理记录。当前没有伪造全量 complete。

复现步骤见 [数据库架构](train-timetable-database.md) 与 `ios/tools/train_timetable.py --help`。覆盖明细见 `app/data/train-service-history/audits/train-timetable-coverage.json`。

本次验证期间其他任务更新了 `rail-history.json` 至 2026-09-27.2。产物元数据已重建，绑定当前工作树的历史线路哈希 `ccdc5b5dc1d328a74cef27f8bf91c6bf6e8b42c0128b6ec660ed7ed8e25dfb5a`；这些历史线路改动不属于本次提交。

阶段提交：`405851d` 为数据库、来源管线、种子数据和运行时基础；`e44ae8d` 包含日期车次界面、跨午夜时钟修复及最终验证报告。

后续时间对齐工作见 [历史线路时间对齐报告](train-timetable-alignment-report.md)。
