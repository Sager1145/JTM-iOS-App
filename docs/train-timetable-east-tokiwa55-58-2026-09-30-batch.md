# JR 东日本ときわ 55–58 逐班核验（2026-09-30）

[55](https://timetables.jreast.co.jp/2610/train/075/076291.html)、[56](https://timetables.jreast.co.jp/2610/train/075/076421.html)、[57](https://timetables.jreast.co.jp/2610/train/045/048311.html)及[58](https://timetables.jreast.co.jp/2610/train/050/050301.html)号的 2026 年 9 月 30 日日历格均为 `td.ok`。55／56／58 页另印「平日運転」。

| 班次／内部号 | 端点时刻 | 站数 | 原页刊载站台 |
|---|---|---:|---|
| ときわ 55／55M | 品川 09:15 发→勝田 10:53 到 | 9 | 品川 ９、東京 ７、上野 ８、水戸 ４ |
| ときわ 56／56M | 高萩 05:48 发→品川 08:19 到 | 17 | 水戸 ７、上野 ９、東京 ９、品川 ９ |
| ときわ 57／57M | 品川 10:14 发→勝田 11:53 到 | 9 | 品川 ９、東京 ８、上野 ８、水戸 ４ |
| ときわ 58／58M | 高萩 06:56 发→品川 09:21 到 | 17 | 水戸 ７、上野 ９、東京 ９、品川 ９ |

四页均列「座席未指定券／グリーン車指定席／普通車全車指定席」。未刊载站台保留为 `null`。这些字样仅支持计划席别；车型、编组辆数、逐车厢安排及实际编组仍未知。

[候选](../app/data/train-service-history/candidates/jr-east-tokiwa55-58-20260930.json)由[专属规范化脚本](../ios/tools/normalize-reviewed-east-tokiwa55-58-20260930.py)生成 4 条单日 trip、52 条客运停站、4 条计划席别和对应来源记录；物理线路与运营者分段保持 `unknown`。[专属测试](../ios/tools/tests/test_east_tokiwa55_58_20260930_source_pinned.py)的 3 项通过，覆盖全数据集校验、完整印刷站时／站台、相邻日期隔离及席别范围。

[闭集清单](train-timetable-east-tokiwa-2026-09-30-inventory.md)共 36 班；目前已逐站录入 8 班，尚缺 28 班。未运行共享全库 rebuild，未修改 SQLite 或主报告。
