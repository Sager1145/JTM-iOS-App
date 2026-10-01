# JR 东日本ひたち 7／9 逐班核验（2026-09-30）

[ひたち 7 初始检索页](https://timetables.jreast.co.jp/2610/train/045/047852.html)把 9 月 30 日标为 `td.other`，其日期链接进入[当日适用版本](https://timetables.jreast.co.jp/2610/train/045/047851.html)，后者为 `td.ok`。当日版本没有初始页所列的東海停站，因此仅录入适用页的 **10** 站。[ひたち 9 官方页](https://timetables.jreast.co.jp/2610/train/045/048321.html)对目标日直接显示 `td.ok`，录入全部 **14** 站。

| 班次／内部号 | 端点时刻 | 原页刊载站台 |
|---|---|---|
| ひたち 7／7M | 品川 09:45 发→いわき 12:07 到 | 品川 ９、東京 ７、上野 ８、水戸 ４ |
| ひたち 9／9M | 品川 10:45 发→いわき 13:15 到 | 品川 ９、東京 ８、上野 ８、水戸 ４ |

两张当日页均列「座席未指定券／グリーン車指定席／普通車全車指定席」。未刊载站台为 `null`；车型、编组辆数、逐车厢安排和实际调度未据此推定。

[候选](../app/data/train-service-history/candidates/jr-east-hitachi7-9-20260930.json)、[专属规范化脚本](../ios/tools/normalize-reviewed-east-hitachi7-9-20260930.py)及后缀 `east-hitachi7-9-20260930` 生成 2 条单日 trip、24 条客运停站、2 条计划席别及逐事实来源。物理线路与运营者分段仍为 `unknown`。官方页面仅供核验，事实再分发许可未确证。

运行 `python3 ios/tools/normalize-reviewed-east-hitachi7-9-20260930.py` 后，[专属测试](../ios/tools/tests/test_east_hitachi7_9_20260930_source_pinned.py)的 3 项通过，覆盖全数据集校验、完整当日印刷站时与站台对照、相邻日期隔离及席别范围。未运行共享全库 rebuild，未修改 SQLite 或主报告。
