# JR 北海道ライラック 3 逐日核验（2026-09-30）

[JR 北海道 2026 年 9 月 30 日下行表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110)的日期选择器显示 `2026年9月30日(水)`。第三列印出 `3003M / ライラック 3`、札幌 07:13 发、旭川 08:40 着，共 7 个乘客停站：札幌、岩見沢、美唄、砂川、滝川、深川、旭川。札幌发车站台格印 `(9)`；其他站台未印。中途站只印发车时刻，到达侧保留 `null`。页脚注明依据《JR時刻表》令和 8 年 10 月号。

[候选](/Users/sager/Documents/GitHub/JTM-iOS-App/app/data/train-service-history/candidates/jr-hokkaido-lilac3-20260930.json)和[规范化脚本](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-hokkaido-lilac3-20260930.py)只为这一天生成一趟 trip、7 条乘客停站及独立后缀的来源和规范文件。复用现有 `lilac` 服务身份与 9 月 30 日日文名称期。没有从“毎日”推导其他日期，没有补造逐日物理线路或运营分段。官方页面仅用于核验，未确证再分发许可。

[专属测试](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/tests/test_hokkaido_lilac3_20260930_source_pinned.py)的 3 项通过，覆盖列车号、全部 7 站时刻、札幌站台、来源、日期边界及未知分段。全库校验通过，共 10,969 条规范记录（含并行工作）。未改共享 rebuild、SQLite、主报告或其他批次。

中途到达侧、其余站台、逐日有序物理线路／运营分段及再分发授权仍待证实。共享 `lilac.last_verified_date` 应由主任务整合时核对更新。
