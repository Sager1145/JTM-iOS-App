# JR 东日本ときわ 83–86 逐班核验（2026-09-30）

[83](https://timetables.jreast.co.jp/2610/train/075/076381.html)、[84](https://timetables.jreast.co.jp/2610/train/050/050351.html)、[85](https://timetables.jreast.co.jp/2610/train/050/050291.html)及[86](https://timetables.jreast.co.jp/2610/train/050/050361.html)号的 2026 年 9 月 30 日日历格均为 `td.ok`。86 号页印「１１月２５日は運休」，不影响本日判定。

| 班次／内部号 | 端点时刻 | 站数 | 原页刊载站台 |
|---|---|---:|---|
| ときわ 83／83M | 品川 22:15 发→土浦 23:18 到 | 9 | 品川 ９、東京 ８、上野 ８ |
| ときわ 84／84M | 勝田 20:47 发→品川 22:22 到 | 9 | 水戸 ７、上野 ９、東京 ９、品川 ９ |
| ときわ 85／85M | 品川 22:45 发→勝田 24:26 到 | 13 | 品川 ９、東京 ８、上野 ８、水戸 ４ |
| ときわ 86／86M | 勝田 21:47 发→品川 23:23 到 | 9 | 水戸 ７、上野 ９、東京 ９、品川 １０ |

85 号的友部、水戸、勝田时刻在候选中照原页保留 `24:xx` 写法；规范化停站使用 `00:xx` 和 `day_offset=1`，均归属 9 月 30 日开行班次。四页均列「座席未指定券／グリーン車指定席／普通車全車指定席」。未刊载站台保留为 `null`。这些字样仅支持计划席别；车型、编组辆数、逐车厢安排及实际编组仍未知。

[候选](../app/data/train-service-history/candidates/jr-east-tokiwa83-86-20260930.json)由[专属规范化脚本](../ios/tools/normalize-reviewed-east-tokiwa83-86-20260930.py)生成 4 条单日 trip、40 条客运停站、4 条计划席别和对应来源记录；物理线路与运营者分段保持 `unknown`。[专属测试](../ios/tools/tests/test_east_tokiwa83_86_20260930_source_pinned.py)的 3 项已通过，覆盖全数据集校验、完整印刷站时／站台、相邻日期隔离及席别范围。

[闭集清单](train-timetable-east-tokiwa-2026-09-30-inventory.md)共 36 班，现已逐站录入 36/36。未运行共享全库 rebuild，未修改 SQLite 或主报告。
