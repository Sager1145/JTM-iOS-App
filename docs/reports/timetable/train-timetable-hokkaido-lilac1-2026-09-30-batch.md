# JR 北海道ライラック 1 逐日核验（2026-09-30）

[JR 北海道 2026 年 9 月 30 日下行表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110)的日期选择器显示 `2026年9月30日(水)`。第一列印出 `3001M / ライラック 1`、札幌 06:29 发、旭川 07:56 着，以及岩見沢、美唄、砂川、滝川、深川共 7 个乘客停站。札幌站台格印 `(9)`；其他站台未印。中途站只有发车时刻，到达侧保留 `null`。页脚注明依据《JR時刻表》令和 8 年 10 月号。

候选 [jr-hokkaido-lilac1-20260930.json](/Users/sager/Documents/GitHub/JTM-iOS-App/app/data/train-service-history/candidates/jr-hokkaido-lilac1-20260930.json) 与 [normalizer](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-hokkaido-lilac1-20260930.py)只为这一天生成一趟 trip、7 条乘客停站及独立来源／规范文件，复用已有 `lilac` 服务身份，并增添 9 月 30 日日文名称期。没有从“毎日”推导其他日期，没有补造逐日物理线路或运营分段。官方页面仅用于核验，未确证再分发许可。

[专属测试](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/tests/test_hokkaido_lilac1_20260930_source_pinned.py)的 3 项通过，覆盖列车号、全部 7 站时刻、札幌站台、来源、日期边界及未知分段。全量校验通过，执行时共 10,637 条规范记录（含并行工作）。未改共享 rebuild、SQLite、主报告或其他批次。

现有共享 `services-root.jsonl` 的 `lilac.last_verified_date` 仍为 `2026-05-16`；主任务整合时应依据本批 9 月 30 日证据更新该服务元数据。本批独立作业未改它。中途到达侧、其余站台、逐日有序物理线路／运营分段及再分发授权仍待证实。
