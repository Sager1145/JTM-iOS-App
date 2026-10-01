# JR 东日本ひたち 2／20 逐班核验（2026-09-30）

JR 东日本[ひたち 2](https://timetables.jreast.co.jp/2610/train/045/048451.html)及[ひたち 20 的当前时刻变体](https://timetables.jreast.co.jp/2610/train/045/048601.html)均把 **2026-09-30** 日历格标为 `td.ok`。20 号的[另一时刻变体](https://timetables.jreast.co.jp/2610/train/045/048602.html)把同一日标为 `td.other`，且上野—品川时刻不同；本批只采用 `048601` 页对该日适用的分钟。

| 班次／内部号 | 端点时刻 | 官方印刷站台 | 客运停站数 |
|---|---|---|---:|
| ひたち 2／2M | いわき 05:53 发→品川 08:50 到 | 水戸 ７、上野 ９、東京 ９、品川 ９ | 14 |
| ひたち 20／20M | いわき 15:18 发→品川 17:52 到 | 水戸 ７、上野 ９、東京 １０、品川 ９ | 12 |

两张当日页均印「座席未指定券／グリーン車指定席／普通車全車指定席」。未刊载站台保留 `null`；官方设备栏只支持逐车**计划席别**，不证明车型、编组辆数、车厢安排或实际调度。

[候选](../app/data/train-service-history/candidates/jr-east-hitachi2-20-20260930.json)、[专属规范化脚本](../ios/tools/normalize-reviewed-east-hitachi2-20-20260930.py)及后缀 `east-hitachi2-20-20260930` 生成 2 条单日 trip、26 条客运停站、2 条计划席别和逐事实来源。沿用 `hitachi` 服务身份；未能独立证明逐区段物理线路和运营者身份，故保持 `unknown`。官方时刻表用作核验，事实再分发许可未确证。

运行 `python3 ios/tools/normalize-reviewed-east-hitachi2-20-20260930.py` 后，[专属测试](../ios/tools/tests/test_east_hitachi2_20_20260930_source_pinned.py)的 3 项通过，包含全数据集校验、当日完整站时与站台对照、相邻日期隔离和席别范围。未运行共享全库 rebuild，未修改 SQLite 或主报告。
