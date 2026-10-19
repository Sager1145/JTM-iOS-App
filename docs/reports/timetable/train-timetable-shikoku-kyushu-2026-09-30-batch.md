# JR 四国／九州 2026-09-30 逐班核验批次

## 已核验并生成的独立规范化批次

脚本 `ios/tools/normalize-reviewed-shikoku-kyushu-20260930-pair.py` 读取四份人工核对的候选，仅为 2026-09-30（日本服务日）生成四条加班日期实例、40 条乘降停站行。新文件统一使用后缀 `reviewed-shikoku-kyushu-20260930-pair`。未改共享 manifest、全量 rebuild 或 SQLite；因此这批尚未进入应用数据库。

| 班次 / trip ID | 官方直接证据 | 核验结果 |
| --- | --- | --- |
| きらめき2号 `jr-kyushu.kirameki.2.2026-09-30` | [JR 九州 9 月 30 日列车详情](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0008/00086001.html?c=28283&ym=202609&d=30)，既有来源 `jr-kyushu-kirameki2-20260930` | 特急、内部号 `52M`；博多 07:11 发至小倉 08:12 到，10 个乘降站。页面显示 `毎日運転`，本批仍只发出 9 月 30 日实例。起终点未印一侧保持空值。 |
| かいおう2号 `jr-kyushu.kaio.2.2026-09-30` | [JR 九州 9 月 30 日列车详情](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0019/00192701.html?c=28283&ym=202609&d=30)，既有来源 `jr-kyushu-kaio2-20260930` | 特急、内部号 `1092H`；博多 21:37 发至直方 22:29 到，6 个乘降站。未印的平台及到发侧保持空值。 |
| 南風6号 `jr-shikoku.nanpu.6.2026-09-30` | [JR 西日本逐日列车详情](https://timetable.jr-odekake.net/train-timetable/162031?date=20260930)及[同日土讃線上行区间表](https://timetable.jr-odekake.net/line-timetable/2473?day=30&month=9&year=2026)，新来源 `jr-odekake-nanpu6-20260930-train`、`jr-odekake-nanpu6-20260930-line` | 特急、内部号 `36D`；高知 08:01 发至岡山 10:33 到，12 个乘降站。逐日区间表确认 9 月 30 日存在；列车页 `レ` 行没有录为停站。起终点未印一侧保持空值。 |

| 南風8号 `jr-shikoku.nanpu.8.2026-09-30` | [JR 西日本逐日列车详情](https://timetable.jr-odekake.net/train-timetable/59411?date=20260930)及[同日土讃線上行区间表](https://timetable.jr-odekake.net/line-timetable/2473?day=30&month=9&year=2026)，新来源 `jr-odekake-nanpu8-20260930-train`、`jr-odekake-nanpu8-20260930-line` | 特急、内部号 `38D`；高知 09:13 发至岡山 11:40 到，12 个乘降站。`レ` 行没有录为停站；起终点未印一侧保持空值。 |

JR 九州两页已有来源登记，未复制该来源行；南風6号和8号的四条新来源登记在 `source-registry-reviewed-shikoku-kyushu-20260930-pair.jsonl`。来源页面用于人工核验，没有捆绑原始网页内容或声称获得转载授权。

## 检查与未解决项

运行 `python3 ios/tools/normalize-reviewed-shikoku-kyushu-20260930-pair.py` 成功，针对性 `python3 -m unittest ios.tools.tests.test_shikoku_kyushu_20260930_pair_source_pinned -v` 三项通过。还检查了四条 trip、40 条有时刻的乘降站和四条单日 `calendar-exceptions`。由于未修改共享 manifest，未声称全库结构校验或应用 SQLite 已包含这批。

四班的有序运营者区段、逐段物理线路 ID 及 2026 年适用期仍缺直接证据，`operator` 和 `route_lines` 保持 `unknown`，未生成 `trip-lines` 或 `trip-operator-segments`。官方页面版权说明没有提供转载或自动提取许可，`provenance` 保持 `partial`。现有 131 模板之外的六家 JR 全量特急库存、四国及九州其他班次与其他日期也未因这四张逐日页面得到证明。下一步需继续逐班取得对应日期的列车详情与可适用日期的运营／线路原始文件，再由共享整合方审阅是否纳入 manifest。

## 第二批：リレーかもめ1号、みどり7号、しまんと2号

专用脚本 `ios/tools/normalize-reviewed-shikoku-kyushu-20260930-next.py` 生成后缀 `reviewed-shikoku-kyushu-20260930-next` 的 3 条单日 trip 和 29 条有时刻的乘降停站记录。未改共享 manifest、全量 rebuild、SQLite 或其他运营者文件；新批次需要整合方单独登记。

| 班次 / trip ID | 官方直接证据 | 核验结果 |
| --- | --- | --- |
| リレーかもめ1号 `jr-kyushu.relay-kamome.1.2026-09-30` | [JR 九州 9 月 30 日列车详情](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0018/00189101.html?c=28283&ym=202609&d=30)，既有来源 `jr-kyushu-relay-kamome1-20260930` | 在双列接续表中仅取特急 `2001H` 博多 06:00 发至武雄温泉 07:00 到，7 站；排除新干线 `2001G` かもめ1号。 |
| みどり7号 `jr-kyushu.midori.7.2026-09-30` | [JR 九州 9 月 30 日列车详情](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0008/00085901.html?c=28283&ym=202609&d=30)，既有来源 `jr-kyushu-midori7-20260930` | 特急 `4007M` 博多 07:28 发至佐世保 09:27 到，10 站。 |
| しまんと2号 `jr-shikoku.shimanto.2.2026-09-30` | [JR 西日本逐日列车详情](https://timetable.jr-odekake.net/train-timetable/90141?date=20260930)及[同日土讃線上行区间表](https://timetable.jr-odekake.net/line-timetable/2473?day=30&month=9&year=2026)，新来源 `jr-odekake-shimanto2-20260930-train`、`jr-odekake-shimanto2-20260930-line` | 特急 `2002D` 高知 04:51 发至高松 07:02 到，12 站；`レ` 通过行未录为停站。高松使用四国侧当前站代码，避开七尾线同名高松站。 |

三页标示 `毎日運転`，仍只发出可直接核验的 2026-09-30 实例；起点未印到时、终点未印发时及空白站台保持 `null`。九州两条来源已在 discovery registry，未重登；四国两条新来源在本批 source registry。没有捆绑网站原始内容或推定转载许可。

检查：`python3 ios/tools/normalize-reviewed-shikoku-kyushu-20260930-next.py` 成功；`python3 -m unittest ios.tools.tests.test_shikoku_kyushu_20260930_next_source_pinned -v` 三项通过。检查涵盖来源 URL、单日 calendar、29 个停站时刻、`2001G` 排除、空值和线路／运营边界维持未定。未运行共享全量校验。四国宇和海1号直达 2026-09-30 页面曾返回站点错误，故没有将其作为本批时刻证据。

## 第三批：ソニック1号、うずしお1号

专用脚本 `ios/tools/normalize-reviewed-shikoku-kyushu-20260930-sonic-uzushio.py` 生成后缀 `reviewed-shikoku-kyushu-20260930-sonic-uzushio` 的 2 条单日 trip 和 27 条有时刻的乘降停站记录。仍需整合方登记，未改共享 manifest、全量 rebuild 或 SQLite。

| 班次 / trip ID | 官方直接证据 | 核验结果 |
| --- | --- | --- |
| ソニック1号 `jr-kyushu.sonic.1.2026-09-30` | [JR 九州 9 月 30 日列车详情](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0001/00013201.html?c=28283&ym=202609&d=30)，既有来源 `jr-kyushu-sonic1-20260930` | 特急 `3001M` 博多 06:21 发至大分 08:44 到，16 站。朽網 07:23/07:24 带 `★＝臨時停車`，候选保留原记号；页面写 `毎日運転`，本批只登记 9 月 30 日实例。页面印 `柳ケ浦`，当前站目录作 `柳ヶ浦`，按既有别名定位。 |
| うずしお1号 `jr-shikoku.uzushio.1.2026-09-30` | [JR 西日本逐日列车详情](https://timetable.jr-odekake.net/train-timetable/75661?date=20260930)及[同日高徳線下行区间表](https://timetable.jr-odekake.net/line-timetable/2479?day=30&month=9&year=2026)，新来源 `jr-odekake-uzushio1-20260930-train`、`jr-odekake-uzushio1-20260930-line` | 特急 `3001D` 高松 06:10 发至徳島 07:29 到，11 站；`レ` 通过行未录为停站。 |

两班起点未印到时、终点未印发时及空白站台保持 `null`。九州来源已在 discovery registry；四国两条新来源在本批 source registry。ソニック服务身份已由 9 月 29 日独立批次建立，所以本批仅新增 `うずしお` 服务身份，没有重复登记 `sonic`。

检查：`python3 ios/tools/normalize-reviewed-shikoku-kyushu-20260930-sonic-uzushio.py` 成功；`python3 -m unittest ios.tools.tests.test_shikoku_kyushu_20260930_sonic_uzushio_source_pinned -v` 三项通过。检查涵盖来源 URL、单日 calendar、27 个停站时刻、临时停站记号、柳ヶ浦别名、空值和线路／运营边界维持未定。没有生成 `trip-lines` 或运营者区段，也没有运行共享全量校验。

## 第四批：にちりん2号、きりしま1号

专用脚本 `ios/tools/normalize-reviewed-kyushu-south-20260930.py` 生成后缀 `reviewed-kyushu-south-20260930` 的 2 条单日 trip 和 27 条有时刻的乘降停站记录。两条来源已经在九州 discovery registry，无须重复登记；本批 source registry 为空。仍需整合方登记新脚本，未改共享 manifest、全量 rebuild 或 SQLite。

| 班次 / trip ID | 官方直接证据 | 核验结果 |
| --- | --- | --- |
| にちりん2号 `jr-kyushu.nichirin.2.2026-09-30` | [JR 九州 9 月 30 日列车详情](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0007/00075401.html?c=28903&ym=202609&d=30)，来源 `jr-kyushu-nichirin2-20260930` | 特急 `5002M`，南宮崎 05:41 发至大分 09:09 到，全程 13 站。页面写 `毎日運転`；只生成 9 月 30 日实例。 |
| きりしま1号 `jr-kyushu.kirishima.1.2026-09-30` | [JR 九州 9 月 30 日列车详情](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0006/00064501.html?c=28903&ym=202609&d=30)，来源 `jr-kyushu-kirishima1-20260930` | 特急 `6001M`，宮崎 05:46 发至鹿児島中央 08:10 到，全程 14 站。页面写 `平日運転`；9 月 30 日是星期三，只生成当日实例。 |

起点未印到时、终点未印发时和空白站台均保持 `null`。`operator` 与 `route_lines` 未因页面发布主体而推定，仍为 `unknown`，没有生成物理线路或有序运营者区段。官方页面供人工核对，不捆绑网页原始内容。

检查：`python3 ios/tools/normalize-reviewed-kyushu-south-20260930.py` 成功；`python3 -m unittest ios.tools.tests.test_kyushu_south_20260930_source_pinned -v` 三项通过，核对来源、单日 calendar、27 个停站时刻和空值。没有运行共享全量校验。

四国缺口：曾尝试将旧日付搜索结果 `train-timetable/104381` 切到 2026-09-30，但网站当日返回的是 `はやぶさ1号／こまち1号`，并非あしずり1号；该 URL 有跨日期复用风险，因此未用于四国候选。宇和海1号当日列车详情此前返回站点错误。两班需从 9 月 30 日对应的区间表重新导航到列车详情，证实完整停站和运行日后方可入库。
