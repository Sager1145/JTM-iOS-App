# JR 东日本ひたち 14／18 逐班核验（2026-09-30）

JR 东日本 [ひたち 14](https://timetables.jreast.co.jp/2610/train/095/098711.html)和[ひたち 18](https://timetables.jreast.co.jp/2610/train/045/048591.html)的逐班页均将 **2026 年 9 月 30 日**日历格标为 `td.ok`。各页独立印有内部列车号、13 个客运停站的到发、站台与「座席未指定券／グリーン車指定席／普通車全車指定席」设备。只登记该日计划版本，不外推到其他日期或实际开行记录。

| 班次／内部号 | 端点时刻 | 页面刊载的站台 |
|---|---|---|
| ひたち 14／14M | いわき 12:18 发→品川 14:51 到 | 水戸 ７、上野 ９、東京 **１０**、品川 ９ |
| ひたち 18／18M | いわき 14:18 发→品川 16:51 到 | 水戸 ７、上野 ９、東京 **９**、品川 ９ |

两张官方页的东京站台不同，故分别绑定来源。其余未刊载站台保留 `null`；席别只证明逐车计划设备，车型、编组辆数、车厢安排和实际调度未知。

[候选](../app/data/train-service-history/candidates/jr-east-hitachi14-18-20260930.json)、[专属规范化脚本](../ios/tools/normalize-reviewed-east-hitachi14-18-20260930.py)与后缀 `east-hitachi14-18-20260930` 生成 2 条单日 trip、26 条客运停站、2 条计划席别记录及逐事实 provenance。复用已有 `hitachi` 服务身份；线路和运营者区段保持 `unknown`。官方页面仅作核验来源，事实再分发许可未确证。

运行 `python3 ios/tools/normalize-reviewed-east-hitachi14-18-20260930.py` 后，[专属测试](../ios/tools/tests/test_east_hitachi14_18_20260930_source_pinned.py)的 3 项通过，包含全数据集校验、逐站印刷值比对、相邻日期隔离及席别范围。未运行共享全库 rebuild，未修改 SQLite 或主报告。
