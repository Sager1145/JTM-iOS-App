# JR 东日本ひたち 11／15／16／17 逐班核验（2026-09-30）

[ひたち 11](https://timetables.jreast.co.jp/2610/train/045/048341.html)、[15](https://timetables.jreast.co.jp/2610/train/045/048361.html)、[16](https://timetables.jreast.co.jp/2610/train/045/048561.html)及[17](https://timetables.jreast.co.jp/2610/train/045/048381.html)的 2026 年 9 月 30 日日历格均为 `td.ok`。只录入这些当日适用页的全部客运停站。

| 班次／内部号 | 端点时刻 | 站数 | 原页刊载站台 |
|---|---|---:|---|
| ひたち 11／11M | 品川 11:45 发→いわき 14:09 到 | 10 | 品川 ９、東京 ７、上野 ８、水戸 ４ |
| ひたち 15／15M | 品川 13:45 发→いわき 16:11 到 | 10 | 品川 ９、東京 ８、上野 ８、水戸 ４ |
| ひたち 16／16M | いわき 13:23 发→品川 15:51 到 | 10 | 水戸 ７、上野 ９、東京 ９、品川 ９ |
| ひたち 17／17M | 品川 14:45 发→いわき 17:14 到 | 13 | 品川 ９、東京 ７、上野 ８、水戸 ４ |

四页均列「座席未指定券／グリーン車指定席／普通車全車指定席」。未刊载站台为 `null`；车型、编组辆数、逐车厢安排及实际调度没有据此推定。

[候选](../app/data/train-service-history/candidates/jr-east-hitachi11-15-16-17-20260930.json)、[专属规范化脚本](../ios/tools/normalize-reviewed-east-hitachi11-15-16-17-20260930.py)及后缀 `east-hitachi11-15-16-17-20260930` 生成 4 条单日 trip、43 条客运停站、4 条计划席别及逐事实来源。物理线路与运营者分段仍为 `unknown`；事实再分发许可未确证。另有[30 班链接清单](train-timetable-east-hitachi-2026-09-30-inventory.md)，其未逐站核对条目只标 `inventory_link_verified`。

运行 `python3 ios/tools/normalize-reviewed-east-hitachi11-15-16-17-20260930.py` 后，[专属测试](../ios/tools/tests/test_east_hitachi11_15_16_17_20260930_source_pinned.py)的 3 项通过，覆盖全数据集校验、完整当日印刷站时与站台对照、相邻日期隔离及席别范围。未运行共享全库 rebuild，未修改 SQLite 或主报告。
