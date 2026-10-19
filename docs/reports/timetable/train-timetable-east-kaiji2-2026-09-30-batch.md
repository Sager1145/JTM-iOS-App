# JR 东日本かいじ 2 逐日核验（2026-09-30）

[JR 东日本かいじ 2 官方列车详情](https://timetables.jreast.co.jp/2610/train/085/087651.html)的 9 月 30 日是本页时刻的 `td.ok` 日历格。详情印出 `5102M / かいじ 2号`、平日运行、竜王 06:58 发至東京 08:59 着，途中 8 站，共 10 个乘客停站。各站到发与竜王、甲府、山梨市、塩山、大月、八王子、立川、新宿、東京站台均按本页保存；石和温泉站台格为空，保留 `null`。终点发车侧为空。

候选 [jr-east-kaiji2-20260930.json](/Users/sager/Documents/GitHub/JTM-iOS-App/app/data/train-service-history/candidates/jr-east-kaiji2-20260930.json) 与 [normalizer](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-east-kaiji2-20260930.py)只生成 9 月 30 日一趟 trip、10 条乘客停站及独立来源／规范文件。服务 `kaiji` 为新建的名称身份。来源只用于核验，未确证再分发许可；没有从“平日運転”推广到其他日期，也未推断有序物理线路或运营者分段。

[专属测试](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/tests/test_east_kaiji2_20260930_source_pinned.py)的 3 项通过，覆盖列车号、全部 10 站到发与站台、来源、日期边界及未知分段。全量校验通过，执行时共 10,637 条规范记录（含并行工作）。未改共享 rebuild、SQLite、主报告或其他批次。

剩余缺口为逐日有序物理线路 ID、运营者分段及再分发授权。页面仅确定预定时刻，不证明当日实际运行事件。
