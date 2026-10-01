# JR 东日本ひたち 25／27／28／30 逐班核验（2026-09-30）

[ひたち 25](https://timetables.jreast.co.jp/2610/train/045/048421.html)、[27](https://timetables.jreast.co.jp/2610/train/045/048431.html)、[28](https://timetables.jreast.co.jp/2610/train/045/048631.html)及[30](https://timetables.jreast.co.jp/2610/train/060/064251.html)的 2026 年 9 月 30 日日历格均为 `td.ok`。只录入这些当日适用页的全部客运停站。

| 班次／内部号 | 端点时刻 | 站数 | 原页刊载站台 |
|---|---|---:|---|
| ひたち 25／25M | 品川 18:45 发→いわき 21:17 到 | 14 | 品川 ９、東京 ７、上野 ８、水戸 ４ |
| ひたち 27／27M | 品川 19:45 发→いわき 22:16 到 | 13 | 品川 ９、東京 ７、上野 ８、水戸 ４ |
| ひたち 28／28M | いわき 19:18 发→品川 21:54 到 | 13 | 水戸 ７、上野 ９、東京 １０、品川 ９ |
| ひたち 30／30M | 仙台 18:02 发→品川 22:52 到 | 25 | 仙台 ６、水戸 ７、上野 ９、東京 ９、品川 ９ |

四页均列「座席未指定券／グリーン車指定席／普通車全車指定席」。未刊载站台为 `null`；车型、编组辆数、逐车厢安排及实际调度没有据此推定。

[候选](../app/data/train-service-history/candidates/jr-east-hitachi25-27-28-30-20260930.json)、[专属规范化脚本](../ios/tools/normalize-reviewed-east-hitachi25-27-28-30-20260930.py)及后缀 `east-hitachi25-27-28-30-20260930` 生成 4 条单日 trip、65 条客运停站、4 条计划席别及逐事实来源。物理线路与运营者分段仍为 `unknown`；事实再分发许可未确证。

运行 `python3 ios/tools/normalize-reviewed-east-hitachi25-27-28-30-20260930.py` 后，[专属测试](../ios/tools/tests/test_east_hitachi25_27_28_30_20260930_source_pinned.py)的 3 项通过，覆盖全数据集校验、完整当日印刷站时与站台对照、相邻日期隔离及席别范围。[30 班闭集测试](../ios/tools/tests/test_east_hitachi_20260930_closed_inventory.py)另按[官方链接清单](train-timetable-east-hitachi-2026-09-30-inventory.md)断言 9 月 30 日每个 1–30 车次号恰有一条规范化 trip；该测试只证明车次覆盖，不证明已有 18 班的逐站准确性。未运行共享全库 rebuild，未修改 SQLite 或主报告。
