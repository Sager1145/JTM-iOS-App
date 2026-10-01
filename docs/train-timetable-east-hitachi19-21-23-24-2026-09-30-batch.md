# JR 东日本ひたち 19／21／23／24 逐班核验（2026-09-30）

[ひたち 19](https://timetables.jreast.co.jp/2610/train/095/098681.html)、[21](https://timetables.jreast.co.jp/2610/train/095/098691.html)、[23](https://timetables.jreast.co.jp/2610/train/045/048411.html)及[24](https://timetables.jreast.co.jp/2610/train/045/048611.html)的 2026 年 9 月 30 日日历格均为 `td.ok`。只录入这些当日适用页的全部客运停站。

| 班次／内部号 | 端点时刻 | 站数 | 原页刊载站台 |
|---|---|---:|---|
| ひたち 19／19M | 品川 15:45 发→いわき 18:11 到 | 12 | 品川 ９、東京 ７、上野 ８、水戸 ４ |
| ひたち 21／21M | 品川 16:45 发→仙台 21:32 到 | 23 | 品川 ９、東京 ７、上野 ８、水戸 ４、仙台 １ |
| ひたち 23／23M | 品川 17:45 发→いわき 20:15 到 | 13 | 品川 ９、東京 ７、上野 ８、水戸 ４ |
| ひたち 24／24M | いわき 17:21 发→品川 19:51 到 | 10 | 水戸 ７、上野 ９、東京 ９、品川 ９ |

24 号所选原页另印「平日運転」；其東京到达 19:42、品川到达 19:51，和另一日别版本不同。四页均列「座席未指定券／グリーン車指定席／普通車全車指定席」。未刊载站台为 `null`；车型、编组辆数、逐车厢安排及实际调度没有据此推定。

[候选](../app/data/train-service-history/candidates/jr-east-hitachi19-21-23-24-20260930.json)、[专属规范化脚本](../ios/tools/normalize-reviewed-east-hitachi19-21-23-24-20260930.py)及后缀 `east-hitachi19-21-23-24-20260930` 生成 4 条单日 trip、58 条客运停站、4 条计划席别及逐事实来源。物理线路与运营者分段仍为 `unknown`；事实再分发许可未确证。另有[30 班链接清单](train-timetable-east-hitachi-2026-09-30-inventory.md)，其未逐站核对条目只标 `inventory_link_verified`。

运行 `python3 ios/tools/normalize-reviewed-east-hitachi19-21-23-24-20260930.py` 后，[专属测试](../ios/tools/tests/test_east_hitachi19_21_23_24_20260930_source_pinned.py)的 3 项通过，覆盖全数据集校验、完整当日印刷站时与站台对照、相邻日期隔离及席别范围。未运行共享全库 rebuild，未修改 SQLite 或主报告。
