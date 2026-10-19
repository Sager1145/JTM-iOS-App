# JR 东日本かいじ 11 逐日核验（2026-09-30）

优先核验的かいじ 12 未出现在 [JR 东日本中央本线上行平日时刻表](https://timetables.jreast.co.jp/2610/timetable-v/223u1.html)。邻近的かいじ 14 官方详情显示周末运行，9 月 30 日日历格为 `td.none`，不能作为当日版本。选用尚未收录的[かいじ 11 官方列车详情](https://timetables.jreast.co.jp/2610/train/050/054801.html)：9 月 30 日为 `td.ok`，同页印出平日运行的 3111M，从新宿 09:30 至甲府 11:15，共 9 个乘客停站。新宿至大月与富士回遊 11（2111M）併結；本批只记录 3111M 的かいじ停站。胜沼ぶどう郷和石和温泉站台未印，保留空值。

[候选](/Users/sager/Documents/GitHub/JTM-iOS-App/app/data/train-service-history/candidates/jr-east-kaiji11-20260930.json)、[规范化脚本](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-east-kaiji11-20260930.py)和独立后缀 `east-kaiji11-20260930` 数据仅覆盖 9 月 30 日。复用已有 `kaiji` 服务身份和名称期，不推广至其他平日或推断有序线路、运营者分段。来源只用于核验，未确证再分发许可。

[专属测试](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/tests/test_east_kaiji11_20260930_source_pinned.py)的 3 项通过；全库校验通过，共 11,135 条规范记录（含其他并行改动）。未触碰共享 rebuild、SQLite 或主报告。剩余缺口为有序线路 ID、运营者分段和再分发授权。
