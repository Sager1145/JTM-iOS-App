# JR 西日本はるか1号／JR 东海ひだ1号逐日核对（2026-09-30）

本批仅新增独立候选、来源登记、normalizer、规范化 JSONL 和 source-pinned 测试。候选本身标记 `canonical=false`，通过专属 normalizer 进入规范化时刻表；只提升 2026-09-30 一个服务日。以下为计划时刻表证据，不证明实际开行或全国库存完整。

| Trip ID | 官方日期证据 | 已核对的乘降停站 | 时刻边界 |
| --- | --- | --- | --- |
| `jr-west.haruka.1.2026-09-30` | 从[京都站 9 月 30 日在来线特急页](https://timetable.jr-odekake.net/station-timetable/2784076001?date=20260930)的 05:45 链接进入[はるか1号列车页](https://timetable.jr-odekake.net/train-timetable/91?date=20260930) | `1001M`；京都 05:45 发、関西空港 07:10 到；京都、高槻、新大阪、大阪、天王寺、関西空港，共 6 站 | 原页「土曜・休日運休」未扩展入库日历；只录印出的到发侧和站台；通过站「レ」未录 |
| `jr-central.hida.1.2026-09-30` | 从[9 月 30 日高山本线下行区间表](https://timetable.jr-odekake.net/line-timetable/2363?day=30&month=9&year=2026)的 `21D` 详细按钮进入[ひだ1号列车页](https://timetable.jr-odekake.net/train-timetable/77261?date=20260930) | `21D`；名古屋 07:43 发、高山 10:16 到；12 个乘降站 | 原页「毎日運転」未扩展入库日历；只录印出的到发侧和站台；通过站「レ」未录 |

两班起点未刊载的到达时刻与终点未刊载的发车时刻均保留 `null`。官方列车页未印的中间站站台也保留 `null`。未推断逐段运营者、物理线路 ID、全国完整线路或邻日时刻。官方页声明时刻数据禁止无授权转载或加工，来源登记限于核验用途，未保存原始 HTML。

## 专属产物

- はるか1号：[候选](../app/data/train-service-history/candidates/jr-west-haruka1-20260930.json)、[来源登记](../app/data/train-service-history/sources/source-registry-west-haruka1-20260930.jsonl)、[normalizer](../ios/tools/normalize-reviewed-west-haruka1-20260930.py)、[测试](../ios/tools/tests/test_west_haruka1_20260930_source_pinned.py)，规范化 JSONL 后缀 `west-haruka1-20260930`。新建 `haruka` 服务身份与同日名称时段。
- ひだ1号：[候选](../app/data/train-service-history/candidates/jr-central-hida1-20260930.json)、[来源登记](../app/data/train-service-history/sources/source-registry-central-hida1-20260930.jsonl)、[normalizer](../ios/tools/normalize-reviewed-central-hida1-20260930.py)、[测试](../ios/tools/tests/test_central_hida1_20260930_source_pinned.py)，规范化 JSONL 后缀 `central-hida1-20260930`。复用现有 `hida` 服务身份。

两个 normalizer 已单独运行。两份专属测试共 4 项通过，测试中的 `train_timetable.validate_dataset` 对当前可见规范化输入返回 0 错误，并核对仅 9 月 30 日 materialize。未运行共享 rebuild，未编辑共享 manifest、rebuild 脚本、SQLite、运行资源或其他既有文件。

现有共享 `hida` 服务记录的 `last_verified_date` 仍为 2026-09-23；主重建方需按本次 9 月 30 日证据协调该服务日期边界。本批仅引用该服务身份，没有改写共享记录。
