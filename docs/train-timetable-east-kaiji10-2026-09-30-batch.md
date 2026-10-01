# JR 东日本かいじ 10 逐日核验（2026-09-30）

优先核验的「かいじ 8」未出现在同系列官方时刻表中，因此选用邻近班次「かいじ 10」。[JR 东日本かいじ 10 官方列车详情](https://timetables.jreast.co.jp/2610/train/075/076171.html)的 `2026年9月` 日历表把 `30` 标为 `td.ok`，同页印出 `5110M / 特急かいじ 10号`、平日运行、甲府 08:45 发至東京 10:42 着，共 9 个乘客停站。各站到发和 8 个印出的站台均照页保存；石和温泉站台格为空，保留 `null`。终点发车侧为空。

[候选](/Users/sager/Documents/GitHub/JTM-iOS-App/app/data/train-service-history/candidates/jr-east-kaiji10-20260930.json)和[规范化脚本](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-east-kaiji10-20260930.py)只生成 9 月 30 日一趟 trip、9 条乘客停站及独立后缀的来源和规范文件。复用现有 `kaiji` 服务身份与 9 月 30 日日文名称期。没有从“平日運転”推广到其他日期，也未推断有序物理线路或运营者分段。来源只用于核验，未确证再分发许可。

[专属测试](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/tests/test_east_kaiji10_20260930_source_pinned.py)的 3 项通过，覆盖列车号、全部 9 站到发与站台、来源、日期边界及未知分段。全库校验通过，共 10,969 条规范记录（含并行工作）。未改共享 rebuild、SQLite、主报告或其他批次。

剩余缺口为逐日有序物理线路 ID、运营者分段及再分发授权。页面仅确定预定时刻，不证明当日实际运行事件。
