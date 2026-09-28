# 特急与历史线路任务协作（2026-09-28）

用户授权两任务合作后，双方已互发消息确认分工。

- 「搭建 JR 特急历史数据库」：`01a0e454-616a-71a1-985e-a933bd95d0c7`，负责 `app/data/train-service-history/`、时刻表工具、SQLite／资源副本、特急运行时及界面。
- 「扩展铁路时态数据库」：`01a0e46e-0471-7780-9611-c9c1418207cf`，负责 rail-history 来源、overlay、历史站点／线路时态、预计算及地图。28.2已完成双方交接；本轮28.3源事件／overlay通过证据、几何、导入、canonical gate和2713生产边界验证，完整Web／native验收已通过并最终冻结。
- 双方只提交自己负责的文件。历史任务完成首次时刻依赖重建后，已把SQLite及相应审计交回特急任务，不再覆盖或提交这些产物。

## 当前共同输入快照

- 历史候选最终版本：`2026-09-28.3`。
- 历史内容SHA-256：`c6feed755ece7a664434592e0b910386493611e62b4d82b5e5aede98c3e99cb3`。
- solver版本：24；日本服务日期语义不变。
- SQLite SHA-256：`3222ceee7d6539ab4970ca9897601b57c02b69673ec86c40d20c13b307027f6b`。
- 当前输入fingerprint：`a20604eb383516b7340cf851dda685ed2084c7bc1cd7c579dd0acd21166a71b2`。
- 数据量为95个模板、1577日期班次、363停站行。105指未确认历史对齐审计项，不能称105个模板。

本轮特急任务重新生成覆盖、来源清单、兼容投影、路线和迁移审计，使其绑定共同输入；快照核验、55项Python及3项parser、28.3资源上的19项Swift专项测试、iOS模拟器构建及bundle字节一致性通过。独立临时SQLite构建也与正式产物字节一致。历史任务确认保留该SQLite；其203项bundle和Native provenance 2项验证已PASS，298模式全部通过（6项测试，909.835秒）；93组双求解器验收已全部通过，实际生成93组boundary、5组pins及284项answers，均为solver 24／revision 28.3；最后Native 25项及191个generated日期对照全部通过（415.272秒），已求解里程差均小于0.1米；历史任务已发送最终冻结交接。对方确认这些剩余门禁不读取特急SQLite，允许本轮整合95模板／1577班次。历史数据本身不在特急提交内，使用旧历史输入时应重新构建时刻产物，不能手改metadata。

## 线路身份接口

直接线路身份引用 `sections[].properties.history_id`，不能拿事件ID或名称匹配代替。双方核对了当前overlay的以下ID（同一ID可能有多段feature）：

| history_id | 已知服务截止边界 | 本轮feature数 |
|---|---|---:|
| jp.jrh.sassho.iryodaigaku-shintotsukawa | 2020-04-18，基础设施另至2020-05-07 | 33 |
| jp.jrh.sekisho.yubari-branch | 2019-04-01 | 10 |
| jp.jrh.rumoi.ishikarinumata-rumoi | 2023-04-01 | 17 |
| jp.jrh.nemuro.furano-shintoku | 2024-04-01 | 15 |

这些边界支持局部日期排除，不证明任意更早日期的完整线路。根室段编译几何仍有缺口；feature数量不能换算成完整经由链证明。当前N02缺少日期边界也不等于取得可信历史有效期。

优先合作取证：1926东京—下关端点及运行日、2013しなの／ひだ／南紀站点与线路映射、2026北海道临时特急及銀河经由链。历史任务的H1范围始于1993-04-01，不覆盖1926端点证明；现有资料也未证明这些特急的完整有序线路／运营边界。本轮不新增verified路线，0项可发布、105项未确认、0错误。新增东日本及九州班次的运营边界和线路证据同样保持unknown。

后续历史版本／hash变更由历史任务回传；特急任务重建SQLite、资源及审计，核验快照。缺失字段继续保留research状态。最新数据和验证记录见 [后续补齐报告](train-timetable-next-report.md)，前一批见 [并行补齐报告](train-timetable-parallel-report.md)。双方不会使用共享index提交另一任务文件。

## 最终历史交接

历史任务确认完整验收通过：93条路线、93组boundary与5组pins双求解器fixture；201份实际预计算；203项历史依赖资源字节对照；2项provenance测试；298模式路线；25项statistics；808项Python及84项Web／lint。主任务直接复核了`/tmp/jtm-native-history-5.log`的25项PASS及其[验收记录](jp-history-h1-plan.md)，并再次执行特急快照核验，`snapshotAligned=true`、错误0。历史验收不等同于全部JR时刻或路线证据完成；特急路线仍为0可发布、105项未确认。特急产物没有因交接而重建或更改hash。

## 下一轮有界取证

已保存[南紀路线合作候选](../app/data/train-service-history/candidates/route-cooperation-20260928.json)。2013年官方公告只证明日期约束下的「関西・紀勢線」发布分组；2020年三重县官方页虽然列明河原田、津、新宮边界，但没有2013适用性，故不提升为canonical有序线路。候选不在manifest事实输入内，生产SQLite和105项未确认路线审计保持不变。缺失目标已回传历史任务：同年代经由表／运行图、历史站点和物理线路身份。

另保存[JR西日本日期合作候选](../app/data/train-service-history/candidates/daily-cooperation-20260928.json)：[2026夏季官方公告](https://www.westjr.co.jp/press/article/2026/05/15/items/260515_00_press_2026einjiunten.pdf)物理第7／8页提供2个在来线特急与2个新干线接续模板，共20个明确日期候选实例（在来线10、新干线接续10），10个不同日期。サンダーバード95号京都发在第7页为09:23、第8页为09:22，主任务也独立查阅同一PDF文本确认；保留冲突及null选定值，不选择其中一个值入库。サンダーバード32号所列5个接续日不代表完整全年运行日。JSON语法、20实例计数、半开边界及截止日验证通过；本轮新增生产记录为0，95／1577快照保持不变。

## 冲突与应用检查后续

サンダーバード95号的五个目标日期官方列车页均支持9095M、京都09:20着／09:22发。已在日期合作候选中追加逐日期URL、hash及resolved_clock，原公告的09:23／09:22观测仍保留，不称为正式勘误。candidate仍不进入manifest事实输入；生产95／1577和3222ceee哈希不变。详见[冲突审计](train-timetable-conflict-audit.md)及[应用内检查](train-timetable-app-usability.md)。
