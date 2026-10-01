# JR 东海／JR 西日本日期页补录（2026-09-30 服务日）

本分工只增补独立候选、来源、规范化脚本与测试；未修改共享 manifest、重建脚本、SQLite、运行资源或共享审计，也未运行全量 rebuild。以下是**计划时刻表证据**，不证明实际开行或全国列车库存完整。

## 本批新增

| Trip ID | 直接日期证据 | 本批保留的事实 | 证据边界 |
| --- | --- | --- | --- |
| `jr-central.shinano.10.2026-09-30` | [JR 东日本刊载的しなの 10 选中版本](https://timetables.jreast.co.jp/2610/train/000/000241.html)；9 月 30 日在该版本日历中 | `1010M`；長野 11:00 发至名古屋 14:01 到，10 个乘降站，逐站印出的到发侧与站台 | 仅 9 月 30 日；长野的到达和名古屋的发车为空；运营者分段、物理线路 ID 未证明 |
| `jr-west.thunderbird.1.2026-09-30` | [JR 西日本 9 月 30 日列车页](https://timetable.jr-odekake.net/train-timetable/257651?date=20260930) | `4001M`；大阪 06:30 发至敦賀 07:54 到，5 个乘降站，逐站印出的到发侧与站台；「レ」通过站未录入 | 原页「毎日運転」仅保存为来源标签，入库日历只限 9 月 30 日；端点未印的时刻侧为空；运营者分段、物理线路 ID 未证明 |
| `jr-west.sunrise-izumo.5031m-4031m.2026-09-29` | [JR 西日本 9 月 29 日サンライズ两车合页](https://timetable.jr-odekake.net/train-timetable/38492?date=20260929) | `5031M` 东京—冈山，`4031M` 冈山—出雲市；17 个乘降站，冈山 06:27 到／06:34 发；东京—冈山与已录 `jr-west.sunrise-seto.5031m.2026-09-29` 双向 `couples_with` | 9 月 29 日服务日、次日到达；官方出雲列自身列出的时刻与合编说明，未借瀬戸时刻复制；运营者分段和物理线路 ID 未证明 |
| `jr-west.yakumo.16.2026-09-27` | [JR 西日本 9 月 27 日やくも 16 列车页](https://timetable.jr-odekake.net/train-timetable/278911?date=20260927) | `1016M`；出雲市 11:44 发至岡山 14:47 到，11 个乘降站、逐站印出的到发及站台 | 只录 9 月 27 日；「毎日運転」没有扩展入库日历；「レ」通过站未录；运营者分段、物理线路 ID 未证明 |
| `jr-west.yakumo.12.2026-09-27` | 从[玉造温泉站 9 月 27 日页](https://timetable.jr-odekake.net/station-timetable/3280024002?date=20260927)进入的[官方列车页](https://timetable.jr-odekake.net/train-timetable/278901?date=20260927) | `1012M`；出雲市 09:40 发至岡山 12:47 到，11 个乘降站，逐站印出的到发及站台 | 只录 9 月 27 日；「毎日運転」未扩展日历，通过站未录；运营者分段、物理线路 ID 未证明 |
| `jr-west.kuroshio.1.2026-09-30` | [JR 西日本 9 月 30 日くろしお 1 列车页](https://timetable.jr-odekake.net/train-timetable/38921?date=20260930) | `51M`；新大阪 07:34 发至新宮 11:59 到，15 个乘降站，保留印出的到发侧及站台 | 只录 9 月 30 日；「土曜・休日運休」未扩展日历；「レ」通过站未录；运营者分段、物理线路 ID 未证明 |
| `jr-central.nanki.1.2026-09-30` | 从[新宮站 9 月 30 日页](https://timetable.jr-odekake.net/station-timetable/3105070001?date=20260930)进入的[南紀 1 列车页](https://timetable.jr-odekake.net/train-timetable/28011?date=20260930) | `3001D`；名古屋 08:02 发至紀伊勝浦 11:56 到，13 个乘降站，保留印出的到发侧及站台 | 只录 9 月 30 日；「毎日運転」未扩展日历；「レ」通过站未录；运营者分段、物理线路 ID 未证明 |

东海原页的 9 月 30 日日历格在 `000241` 选中版本中为普通文本；相邻 `000243` 页面将该日期列为可点击的另一版本，不能把 `000243` 的时刻用于当日。西日本页在 `date=20260930` 下直接显示 9 月 30 日的选中日历、车次和时刻表。9 月 29 日サンライズ合页明确出雲在冈山换用 `4031M`，并写明东京—冈山与瀬戸併結。各页只保留人工核对事实，未打包原始 HTML；再分发授权仍待解决。

## 专属文件与检查

- 东海：[候选](../app/data/train-service-history/candidates/jr-central-shinano10-20260930.json)、[normalizer](../ios/tools/normalize-reviewed-central-shinano10-20260930.py)、[测试](../ios/tools/tests/test_central_shinano10_20260930_source_pinned.py)，以及以 `reviewed-central-shinano10-20260930` 命名的专属来源和规范化 JSONL。
- 西日本：[候选](../app/data/train-service-history/candidates/jr-west-thunderbird1-20260930.json)、[来源](../app/data/train-service-history/sources/source-registry-west-thunderbird1-20260930.jsonl)、[normalizer](../ios/tools/normalize-reviewed-west-thunderbird1-20260930.py)、[测试](../ios/tools/tests/test_west_thunderbird1_20260930_source_pinned.py)，以及以 `west-thunderbird1-20260930` 命名的专属规范化 JSONL。
- 出雲：[候选](../app/data/train-service-history/candidates/jr-west-sunrise-izumo-20260929.json)、[normalizer](../ios/tools/normalize-reviewed-west-sunrise-izumo-20260929.py)、[测试](../ios/tools/tests/test_west_sunrise_izumo_20260929_source_pinned.py)，以及以 `west-sunrise-izumo-20260929` 命名的专属规范化 JSONL。该批引用已登记的同日 [西日本官方来源](../app/data/train-service-history/sources/source-registry-west-sunrise-seto-20260929.jsonl)，未复制来源登记条目。
- やくも 16：[候选](../app/data/train-service-history/candidates/jr-west-yakumo16-20260927.json)、[来源](../app/data/train-service-history/sources/source-registry-west-yakumo16-20260927.jsonl)、[normalizer](../ios/tools/normalize-reviewed-west-yakumo16-20260927.py)、[测试](../ios/tools/tests/test_west_yakumo16_20260927_source_pinned.py)，以及以 `west-yakumo16-20260927` 命名的专属规范化 JSONL。
- やくも 12：[候选](../app/data/train-service-history/candidates/jr-west-yakumo12-20260927.json)、[来源](../app/data/train-service-history/sources/source-registry-west-yakumo12-20260927.jsonl)、[normalizer](../ios/tools/normalize-reviewed-west-yakumo12-20260927.py)、[测试](../ios/tools/tests/test_west_yakumo12_20260927_source_pinned.py)，以及以 `west-yakumo12-20260927` 命名的专属规范化 JSONL。日文服务名称时段已由同日 16 号批次覆盖，不重复生成。
- くろしお 1：[候选](../app/data/train-service-history/candidates/jr-west-kuroshio1-20260930.json)、[来源](../app/data/train-service-history/sources/source-registry-west-kuroshio1-20260930.jsonl)、[normalizer](../ios/tools/normalize-reviewed-west-kuroshio1-20260930.py)、[测试](../ios/tools/tests/test_west_kuroshio1_20260930_source_pinned.py)，以及以 `west-kuroshio1-20260930` 命名的专属规范化 JSONL。
- 南紀 1：[候选](../app/data/train-service-history/candidates/jr-central-nanki1-20260930.json)、[来源](../app/data/train-service-history/sources/source-registry-central-nanki1-20260930.jsonl)、[normalizer](../ios/tools/normalize-reviewed-central-nanki1-20260930.py)、[测试](../ios/tools/tests/test_central_nanki1_20260930_source_pinned.py)，以及以 `central-nanki1-20260930` 命名的专属规范化 JSONL；复用现有 `nanki` 服务身份。
- 七个 normalizer 已单独运行。`train_timetable.validate_dataset` 对当前可见规范化输入返回 0 错误；新两班的专属测试 4 项通过，本分工七个测试文件共 15 项。未对共享 SQLite 与运行资源做重建或对齐声明。

## 继续核验的缺口

1. JR 东海现有 2013 年临时「しなの／ひだ／南紀」候选仍主要只有公告端点与运行日；缺逐班中途停站、到发侧、明确的运营者边界和当年有效的物理线路身份。
2. JR 西日本旧搜索结果中的 `280171?date=20260610` 确是「やくも 16」，但将同一数字路径改为 `date=20260930` 后，官方站点实际显示普通 `6927D` 早岐→佐世保；数字路径不能跨日期沿用。9 月 27 日已改用当日确认的 `278911`。9 月 30 日「やくも 16」仍须从该日站点或线路页重新取得链接。
3. 已查到 [9 月 26 日サンダーバード 2 官方页](https://timetable.jr-odekake.net/train-timetable/257951?date=20260926)，该页标「土曜・休日運転」，不能据此推至 9 月 29／30 日。9 月 27 日其它やくも班次可沿当天站页链接逐班核对；数字路径随日期变化，不能把邻日页当作当天来源。
4. 共享重建已将 `yakumo` 的 `first_verified_date` 自动更新至 2026-09-27；本分工没有编辑共享服务记录。
5. 旧 `ひだ 1` 数字路径 `77451` 改用 `date=20260930` 后实际显示普通 `2531M`，不能作为当日ひだ证据。仍须从 9 月 30 日站点页获取该车次的直接链接。
6. 七班新增 trip 都没有可发布的完整线路证明；`route_lines=unknown`，未推断线路 ID。全国特急库存和逐日全量仍未证明。
