# ひたち 26 号当日席别补录审计（2026-09-30）

[JR 东日本逐班页](https://timetables.jreast.co.jp/2610/train/095/098731.html)将 2026 年 9 月 30 日标为 `td.ok`，印有 `26M`、いわき 18:17 发至品川 20:53 到的 14 个停站、4 处有值站台及「座席未指定券／グリーン車指定席／普通車全車指定席」。原有 `jr-east.hitachi.26.2026-09-18` trip 的本日停站、到发和站台与该页一致，原规范层缺少本日计划席别记录。

[专属候选](../app/data/train-service-history/candidates/jr-east-hitachi26-equipment-20260930.json)和[规范化脚本](../ios/tools/normalize-reviewed-east-hitachi26-equipment-20260930.py)只给现有 trip 添加 2026-09-30 的 `planned` 席别：普通车全车指定席、绿色车厢指定席；车型、辆数、逐车厢席位与实际派车未知。来源 ID 沿用该页既有的 `jr-east-hitachi26-202609`，未新建重复 trip。[专属测试](../ios/tools/tests/test_east_hitachi26_20260930_source_pinned.py)核对全部 14 站、来源 URL 和席别字段。

[闭集清单](train-timetable-east-hitachi-2026-09-30-inventory.md)覆盖已观察两张常磐线平日整线表所列 1–30 号；本次核得 30 个唯一当日 trip、30 条计划席别，无已观察号数或端点支线缺录。未发现新车次须另建 trip。其他入口仍未知；未运行共享 rebuild 或改动 SQLite、主报告。
