# JR 东日本ひたち 3／5 逐班核验（2026-09-30）

[ひたち 3 官方页](https://timetables.jreast.co.jp/2610/train/075/076491.html)和[ひたち 5 官方页](https://timetables.jreast.co.jp/2610/train/050/050251.html)的 2026 年 9 月 30 日日历格均为 `td.ok`。本批只录入这两张当日适用页的全部客运停站，分别为 **21** 和 **13** 站。

| 班次／内部号 | 端点时刻 | 原页刊载站台 |
|---|---|---|
| ひたち 3／3M | 品川 07:43 发→仙台 12:27 到 | 品川 ９、東京 ８、上野 ８、水戸 ４、仙台 １ |
| ひたち 5／5M | 品川 08:43 发→いわき 11:24 到 | 品川 ９、東京 ８、上野 ８、水戸 ４ |

两页均列「座席未指定券／グリーン車指定席／普通車全車指定席」。未刊载站台保留 `null`；车型、编组辆数、逐车厢安排和实际调度没有据此推定。

[候选](../app/data/train-service-history/candidates/jr-east-hitachi3-5-20260930.json)、[专属规范化脚本](../ios/tools/normalize-reviewed-east-hitachi3-5-20260930.py)及后缀 `east-hitachi3-5-20260930` 生成 2 条单日 trip、34 条客运停站、2 条计划席别及逐事实来源。物理线路与运营者分段仍为 `unknown`。官方页面仅供核验，事实再分发许可未确证。

运行 `python3 ios/tools/normalize-reviewed-east-hitachi3-5-20260930.py` 后，[专属测试](../ios/tools/tests/test_east_hitachi3_5_20260930_source_pinned.py)的 3 项通过，包含全数据集校验、完整当日印刷站时和站台对照、相邻日期隔离及席别范围。未运行共享全库 rebuild，未修改 SQLite 或主报告。
