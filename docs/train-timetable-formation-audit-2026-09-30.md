# 2026-09-30 特急编组与席别证据

第 17 波固定快照（SQLite SHA256 `37e5f389f93422511ed10338a35300303aca538dece4ebb2908f9715cf74c9ad`）的 `schema_version=1.2.0` 有 572 条 2026-09-30 计划编组与 786 条有来源的逐号车记录，其中 236 条有计划辆数、126 条有标准车型、56 条有计划定员。每条记录绑定车次、**运行日期**、来源与 `planned` / `actual` 证据类型；未证实的实际车型、辆数或车厢布局留空。列车号由 `trips.train_number`、必要时的 `trip_number_segments` 或日期覆盖保存；站台由 `stop_times.platform` 或指定日期的覆盖保存，印出的到发侧由 `stop_times` 及日期覆盖保存。后续批次会改变计数，当前值以[生成的覆盖审计](../app/data/train-service-history/audits/train-timetable-coverage.json)与 SQLite 为准。

## 已入库的日期事实

| 范围 | 可确认并入库 | 未据此确认 |
| --- | --- | --- |
| [JR 北海道全车指定席政策](https://www.jrhokkaido.co.jp/zensha/)与 2026-09-30 [北斗／すずらん下行](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=150)、[上行](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=151)、[おおぞら／とかち下行](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=130)、[上行](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=131)、[旭川方向下行](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110)、[上行](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111) | 第17波库内 110 趟 JR 北海道特急的 `all_reserved=true`；其中 76 趟有逐列绿车图标，其余 34 趟保持未知。计划标准车型与辆数只在官方列车指南有相应证据时填写。 | 当天实际投入的车型、车厢数、逐号车配置；标准计划不等于实际派车证明。 |
| [JR 九州 2026-09-28 编组日历](https://www.jrkyushu.co.jp/trains/ibusukinotamatebako/__icsFiles/afieldfile/2026/09/28/calendar202609_202611.pdf)第 1、2 页与[官方车次页](https://www.jrkyushu.co.jp/trains/ibusukinotamatebako/) | 2026-09-30「指宿のたまて箱」1–6 号均记录计划 `C` 编成、2 辆、指定席定员 63；方向不同则逐号车顺序反转。 | 服务级日历并未逐号印出六班实际调度；号码与编组的关联标为计划推断，临时换车仍未知。 |
| [JR 九州ゆふいんの森逐班时刻](https://www.jrkyushu-timetable.jp/sp/2610/0016/00166501.html?t=2828302e&d=20260930)及官方当日编组日历、编成图 | 1–6 号的计划 I 世／III 世编组，4／5 辆，合计 28 条逐号车资料；每一班绑定 9 月 30 日。 | 实际投入车辆可能与计划不同。 |
| [JR 九州 SONIC 车次配置](https://www.jrkyushu.co.jp/english/train/sonic.html)、[设备与辆数](https://www.jrkyushu.co.jp/train/kids/guardian/train_equipment/index.html)及当日逐班页 | 当日官方闭集64／64班均有计划席别；其中46班有按车次可证实的计划车型与辆数。逐号车席别按独立图示来源填写。 | 实际调度及未刊载的逐号车席别；“白いソニック”与编组表冲突的16、101等班次没有填入车型或辆数。 |
| [JR 西日本はるか现行车辆页](https://www.jr-odekake.net/railroad/train/haruka/)与[全部9辆的改正公告](https://www.westjr.co.jp/press/article/items/231215_00_press_daiyakaisei_kinto.pdf) | 当日闭集はるか1–60全部保存逐班计划9辆及已刊载席别。 | 2026-09-30实际车组、281／271系分配及逐号车席别。 |
| [JR 西日本サンダーバード标准车内图](https://www.jr-odekake.net/railroad/train/thunderbird/)与当日逐班页 | 当日闭集1–50全部保存计划9辆、标准图指定席、1号车绿车及2–9号车普通车的逐号车资料；女性专用席文字与位置分开记录来源。 | 标准图不证明2026-09-30实际派车、车型或每一座位的当日分配。 |

JR 北海道 s=110／111 页日期控件选中 2026-09-30 后，已审阅列的「編成」行中的 `greensiteidai0.png` 与 `zensekisitei0.png` 图标逐列绑定内部列车号及该页来源。其余 34 趟没有据此判定为无绿车，`green_car_available` 保持未知。逐日表图标可证明对应列的席别标记，但没有给出可以识别每一号车的文字资料。JR 北海道 2026 年全车指定席政策也提示基本编组可能变化。JR 四国的网页虽有按车次的车型/辆数分组，但没有能把该网页确定到 2026-09-30 的有效日期，因此暂未入库为当天事实。

另据 [ゆふ6号逐班页](https://www.jrkyushu-timetable.jp/sp/2610/0016/00167601.html?t=2880501e&d=20260930)、[ソニック10号](https://www.jrkyushu-timetable.jp/sp/2610/0006/00068901.html?t=2874200e&d=20260930)、[しおかぜ1号](https://timetable.jr-odekake.net/train-timetable/18541?date=20260930)及[宇和海9号](https://timetable.jr-odekake.net/train-timetable/1301?date=20260930)等当日逐班页，已记录普通车部分指定席、绿车指定席及列车标识；具体证据逐班保存在候选和 `fact_sources`。另外对 24 趟已有四国／九州特急补齐原页刊载的计划席别与设备文字，包括 DX 绿车、四人绿车包厢和アンパンマン列车标识。未印出的车型、辆数和实际车底保持未知。サンダーバード1–50原页的女性专用席文字已补入来源记录及编组备注；3号车位置来自独立的官方标准车内图。

9 月 30 日 [成田エクスプレス5号](https://timetables.jreast.co.jp/2610/train/030/031141.html)及同系列逐班页已为观察集合中的 84 条分支车次保存计划指定席设备；页面未给出逐班当日 6／12 辆分配，因此车型、辆数与实际车底均为空。[ひたち13号](https://timetables.jreast.co.jp/2610/train/060/064241.html)／[22号](https://timetables.jreast.co.jp/2610/train/095/098721.html)等其他逐班席别资料也按来源入库。运行时可通过 `TrainTimetableDatabase.formation(for:)` 读取指定 `Trip` 的当日编组；查询其他日期不会继承 9 月 30 日的计划。`planned` 表示计划编组，不表示已核实的实际运行编组。
