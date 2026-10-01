# JR 东日本ひたち 1／29 逐班核验（2026-09-30）

在 JR 东日本[ひたち 1 初始检索页](https://timetables.jreast.co.jp/2610/train/045/047843.html)，2026-09-30 的日历格为 `td.other`，该格链接至[当日适用版本](https://timetables.jreast.co.jp/2610/train/045/047841.html)，后者为 `td.ok`。初始页含友部停站、适用页不含；本批只录入适用页的 **12** 个客运停站。[ひたち 29 官方页](https://timetables.jreast.co.jp/2610/train/045/048441.html)对目标日直接显示 `td.ok`，印有 **14** 个客运停站。

| 班次／内部号 | 端点时刻 | 原页刊载站台 |
|---|---|---|
| ひたち 1／1M | 品川 06:45 发→いわき 09:18 到 | 品川 ９、東京 ７、上野 ８、水戸 ４ |
| ひたち 29／29M | 品川 20:45 发→いわき 23:19 到 | 品川 ９、東京 ８、上野 ８、水戸 ４ |

两张当日页均列「座席未指定券／グリーン車指定席／普通車全車指定席」。未刊载站台保留 `null`；逐车计划席别并不证明车型、编组辆数、逐车厢安排或实际调度。另查到的[ひたち 24 周末页](https://timetables.jreast.co.jp/2610/train/045/048621.html)对 9 月 30 日为 `td.none`，没有当作目标日候选。

[候选](../app/data/train-service-history/candidates/jr-east-hitachi1-29-20260930.json)、[专属规范化脚本](../ios/tools/normalize-reviewed-east-hitachi1-29-20260930.py)及后缀 `east-hitachi1-29-20260930` 生成 2 条单日 trip、26 条客运停站、2 条计划席别及逐事实来源。复用已有 `hitachi` 服务身份；[官方常磐线上下行时刻表](https://timetables.jreast.co.jp/2610/timetable-v/240d1.html)提供服务走廊名称，但未唯一证明这两趟每段的物理线路 ID 与正式运营者界点，故 `route_lines`／`operator` 仍为 `unknown`。官方页面仅供核验，事实再分发许可未确证。

运行 `python3 ios/tools/normalize-reviewed-east-hitachi1-29-20260930.py` 后，[专属测试](../ios/tools/tests/test_east_hitachi1_29_20260930_source_pinned.py)的 3 项通过，包含全数据集校验、完整当日印刷站时和站台对照、相邻日期隔离及席别范围。未运行共享全库 rebuild，未修改 SQLite 或主报告。
