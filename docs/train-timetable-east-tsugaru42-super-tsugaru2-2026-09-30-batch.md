# JR 东日本つがる 42／スーパーつがる 2 逐班核验（2026-09-30）

[つがる 42](https://timetables.jreast.co.jp/2610/train/005/008181.html)与[スーパーつがる 2](https://timetables.jreast.co.jp/2610/train/095/098671.html)的 2026 年 9 月 30 日日历格均为 `td.ok`。原页分别印出「つがる 42号／2042M」和「スーパーつがる 2号／2022M」，因此记录为 `tsugaru`、`super-tsugaru` 两个独立服务身份；两班均为青森→秋田。

| 班次 | 端点时刻 | 刊载停站 | 原页刊载站台 |
|---|---|---:|---|
| つがる 42／2042M | 青森 09:04 发→秋田 11:45 到 | 13 | 青森 ５、新青森 ２、秋田 ４ |
| スーパーつがる 2／2022M | 青森 12:40 发→秋田 15:12 到 | 8 | 青森 ３、新青森 ２、秋田 ４ |

两页设备栏均为「グリーン車指定席／普通車一部指定席」，支持计划绿色车厢及普通车部分指定席，故规范层 `green_car_available=true`、`all_reserved=false`。两页备注还刊载青森—新青森区间限定的乘车券搭乘普通车自由席规则；候选保留原文。页面没有逐车厢图、车型、辆数或实际派车证据。未刊载站台保留为 `null`，物理线路与运营者区段保留未知。逐班页写「碇ケ関」，现行 N02 目录写「碇ヶ関」；前者原样保存在候选与站名快照，后者用于解析同一站点 ID。

[候选](../app/data/train-service-history/candidates/jr-east-tsugaru42-super-tsugaru2-20260930.json)经[专属规范化脚本](../ios/tools/normalize-reviewed-east-tsugaru42-super-tsugaru2-20260930.py)生成 2 个服务、2 条单日 trip、21 个停站、2 条计划席别及独立来源。[专属测试](../ios/tools/tests/test_east_tsugaru42_super_tsugaru2_20260930_source_pinned.py)3 项通过，覆盖原页全部停站、时刻、站台、服务身份、席别、相邻日期与未知路线。未运行共享 rebuild，未修改 SQLite 或主报告。
