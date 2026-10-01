# JR 东日本ときわ 63–66 逐班核验（2026-09-30）

[63](https://timetables.jreast.co.jp/2610/train/075/076311.html)、[64](https://timetables.jreast.co.jp/2610/train/060/064261.html)、[65](https://timetables.jreast.co.jp/2610/train/045/048371.html)及[66](https://timetables.jreast.co.jp/2610/train/050/050321.html)号的 2026 年 9 月 30 日日历格均为 `td.ok`。

| 班次／内部号 | 端点时刻 | 站数 | 原页刊载站台 |
|---|---|---:|---|
| ときわ 63／63M | 品川 13:15 发→勝田 14:50 到 | 9 | 品川 ９、東京 ８、上野 ８、水戸 ４ |
| ときわ 64／64M | 高萩 10:16 发→品川 12:22 到 | 14 | 水戸 ７、上野 ９、東京 １０、品川 ９ |
| ときわ 65／65M | 品川 14:15 发→勝田 15:51 到 | 9 | 品川 ９、東京 ８、上野 ８、水戸 ４ |
| ときわ 66／66M | 勝田 11:47 发→品川 13:22 到 | 9 | 水戸 ７、上野 ９、東京 ９、品川 ９ |

四页均列「座席未指定券／グリーン車指定席／普通車全車指定席」。未刊载站台保留为 `null`。这些字样仅支持计划席别；车型、编组辆数、逐车厢安排及实际编组仍未知。

[候选](../app/data/train-service-history/candidates/jr-east-tokiwa63-66-20260930.json)由[专属规范化脚本](../ios/tools/normalize-reviewed-east-tokiwa63-66-20260930.py)生成 4 条单日 trip、41 条客运停站、4 条计划席别和对应来源记录；物理线路与运营者分段保持 `unknown`。[专属测试](../ios/tools/tests/test_east_tokiwa63_66_20260930_source_pinned.py)的 3 项通过，覆盖全数据集校验、完整印刷站时／站台、相邻日期隔离及席别范围。

[闭集清单](train-timetable-east-tokiwa-2026-09-30-inventory.md)共 36 班；目前已逐站录入 16 班，尚缺 20 班。未运行共享全库 rebuild，未修改 SQLite 或主报告。
