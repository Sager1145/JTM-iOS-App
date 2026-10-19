# JR 北海道ライラック 8 逐日核验（2026-09-30）

优先核验的ライラック 4 未出现在 [JR 北海道 2026 年 9 月 30 日上行时刻表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111)：该日 3002M ライラック 2 后列出 2004M カムイ 4、2006M カムイ 6，下一班同系列为 3008M ライラック 8。因此选用尚未收录的ライラック 8。所选列印出旭川 07:55 发、札幌 09:20 着，共 7 站；札幌到着番线为 `(2)`。中途站只印发车时刻，到达侧保留空值。

[候选](/Users/sager/Documents/GitHub/JTM-iOS-App/app/data/train-service-history/candidates/jr-hokkaido-lilac8-20260930.json)、[规范化脚本](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-hokkaido-lilac8-20260930.py)和独立后缀 `hokkaido-lilac8-20260930` 数据仅覆盖当日一趟班次。复用已有 `lilac` 服务身份和名称期，不推断其他日期或未印出的时刻、线路分段。来源只用于核验，未确证再分发许可。

[专属测试](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/tests/test_hokkaido_lilac8_20260930_source_pinned.py)的 3 项通过；全库校验通过，共 11,135 条规范记录（含其他并行改动）。未触碰共享 rebuild、SQLite 或主报告。剩余缺口为有序线路 ID、运营者分段和再分发授权。
