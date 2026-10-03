# 特急时刻数据库核验与修复（2026-09-29—30）

## 已验证快照与核验范围

下文计数与缺口固定于 2026-09-30 续接完成的已测 SQLite／审计快照（数据库 `af8568aa…96f4`），不是目前仍在变化的工作树现状。各波次新增数保留为历史阶段记录；验证段列明该快照的完整数据库／来源哈希及实际完成的检查。后续东京线路、播放与车站英文资料修改不属于这些测试结果，当前工作树不能据此称为冻结或已通过验证。全国库存、逐日线路和实际运营也不因资源快照对齐而获得证明。

本报告最初核对库中的 **95 个列车模板**，不是六家 JR 的完整特急清单。后续逐班扩充并将部分北海道班次按精确证据日期拆版，现有 **882 个模板**。`app/data/train-service-history/manifest.json` 的 `as_of_date` 为 **2026-09-30（日本服务日期）**。从已审查来源重建后的数据库含 **2,403 个有日历证据的计划班次实例、8,520 条模板停站记录**；9 月 29 日和 9 月 30 日分别有 25、769 个获来源支持的实例。`as_of_date` 只限定已审查计划资料的日期，不证明列车实际开行，也不证明当天清单完整。

旧快照曾有 1,577 个实例；按 [JR 东海 2013 年原公告](https://jr-central.co.jp/news/release/_pdf/000018518.pdf) 删除四班「しなの」错误复制的 52 个日期，并逐批加入后续有明确日历证据的班次。公告逐行列出的 2013 年 JR 东海 12 个具名模板共有 **165** 个日期实例。原审计的“9 月 29 日缺班”“2013 しなの多出 52 班”等描述均指修复前快照，现不再是当前数据库问题。

## 结果判定与剩余工作

本库记录的是**有来源支持的计划时刻**。模板数是日期或版本化的列车定义数；实例数是这些模板在有日历证据的服务日期上展开的次数，两者不能相加，也不能用实例数推断全国当日车次数。`coverageComplete=false` 表示六家 JR 的完整车次清单和逐日覆盖尚未得到证明。逐站时刻结构检查通过，只说明已录记录内部一致；路线审计尚未执行全库逐日求解，当前 N02 线路标识不能直接充当班次日期的线路有效期证据。实际开行和实际到发另需运营记录或用户实测。

| 优先级 | 待完成的核验 | 完成判据与可用证据 |
|---|---|---|
| 1 | 六家 JR 各日期的特急清单与运行日 | 按运营商整线时刻表、逐日列车页和临时列车公告逐班盘点，记录缺班与不运行符号；各运营商和目标日期的覆盖单元全部有证据后，再重新判定 `coverageComplete` |
| 2 | 已收录班次的停站、到发与跨天时刻 | 对照适用日期的逐站原页补齐真正刊载的格；原页未印的到达或发车侧继续留空，并在逐日空白审计中保留待核项 |
| 3 | 逐日有序线路与运营者区段 | 核对换线界点、历史车站身份、线路开通与结束日期及运营者边界；将通过站作为路线节点处理，再运行逐日线路求解 |
| 4 | 更早历史特急 | 继续寻找可逐列核验的原始时刻表、运行日图例及当期线路资料；早于 H1 建设范围的班次也允许查询有证据的路线，未证实的线路维持未核实 |
| 5 | 加入行程与 AI 补全 | 用最小输入和连续改日期场景复核真实界面；对来源不完整、重名车站及跨天停站维持明确的审核提示 |

发布前需重新生成审计并确认**班次盘点、停站时刻、逐日线路与来源授权**均达到目标覆盖范围。当前报告只证明已经逐条核对的记录；未验证的班次、日期和路线继续保留待核状态。

## 已修复的来源字段

| 车种或班次 | 当前已证实并写入的内容 | 保留的边界 |
|---|---|---|
| 2013 年 しなの 81／82／84／85 | 按 [JR 东海原公告第 3 页](https://jr-central.co.jp/news/release/_pdf/000018518.pdf) 的各班运行日逐行重建，移除 52 个无行级证据的实例 | 公告没有完整中途停站；2013 年英文名称不能用现行名称倒填 |
| WEST EXPRESS 銀河纪南昼行／夜行 | [昼行 9 月 30 日列车页](https://timetable.jr-odekake.net/train-timetable/193801?date=20260930) 证实内部号 `8078M`；[夜行列车页](https://timetable.jr-odekake.net/train-timetable/193791?date=20260925) 证实 `8077M`。公开号保持空值；昼行 9 月 30 日已入库 | 线路物理身份和实际运营未证实 |
| しおかぜ 5–28 | [JR 四国特别运行公告](https://www.jr-shikoku.co.jp/03_news/press/assets/2026/06/24/20260624.pdf) 与四个特别运行日的 96 个[精确日期列车页示例](https://timetable.jr-odekake.net/train-timetable/292?date=20260808)核对一致。24 个模板现有 335 条客运停站及所公布的到发时刻、内部号 `5M`–`28M`；`レ` 通过站未录成停站 | 只覆盖 8 月 8、9、15、16 日的特别版本；运营商边界、物理线路仍未核实 |
| 石鎚 3–28 | [JR 四国特别运行公告](https://www.jr-shikoku.co.jp/03_news/press/assets/2026/07/15/20260515%20.pdf)和 9 月 18–23 日逐日列车页核实 154 个特别运行实例、26 个模板的 102 条客运停站。9 月 18 日 3／4 号仍是普通 `1003M`／`1004M`，未列入特别版本；其余日期按各页的 `9003M`–`9028M` 内部号、到发时刻和站台录入，通过站未当作客运停站 | 只覆盖公告和逐日列车页支持的六日；运营商区段、物理线路仍未核实 |
| サロベツ 3／4 | [6063D](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=2890) 与 [6064D](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=2891) 的 9 月 30 日视图证实内部号、各 11 站顺序及页面显示的时刻；未显示的到发格保持空值 | 完整停站和内部号只属于 9 月 30 日版本；7 月 1 日至 9 月 29 日保留公告可证明的端点，物理线路身份未证实 |
| カムイ 9／15／26／36、北斗 84／91、ニセコ双向 | [9 月 27 日カムイ下行](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260927&s=110)与[上行](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260927&s=111)页面支持 9／26 号的内部号、各 7 站和显示时刻；[9 月 20 日北斗 84](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260920&s=151)／[91](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260920&s=150)、[9 月 23 日札幌发ニセコ](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260923&s=681)及[9 月 26 日函館发ニセコ全线页](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260926&s=680)支持各自日期的内部号与逐站印刷时刻，新增 53 条仅限这些日期的时刻覆盖 | カムイ 15／36 的旧 8 月页面不能重取，撤回其未经留证的详细停站和内部号，仅保留公告端点；其余运行日不继承单日细节。四班逐日页未印的到达或发车侧继续留空 |
| フラノラベンダーエクスプレス双向 | [JR 北海道公告第 5 页](https://www.jrhokkaido.co.jp/CM/Info/press/pdf/260325_KO_Furano-Biei.pdf) 给出双向各五站的方向性时刻，已逐格写入 | 原表未印的反向到发格保持空值 |
| ゆふいんの森 1–6 | [JR 九州 2026 年 3 月 14 日版日文时刻表](https://www.jrkyushu.co.jp/trains/yufuinnomori/) 的 **46 个时刻及到发侧别**逐格核实；1／3／5 下行、2／4／6 上行。[8 月修订计划](https://www.jrkyushu.co.jp/trains/yufuinnomori/__icsFiles/afieldfile/2026/08/18/20260818_yuhuin_no_mori_train_plan_0919_1.pdf) 支持至 9 月 30 日的入库日期 | 有名称和顺序证据的线路片段仍是 `partial`；缺各时期物理线路直接证明 |
| 指宿のたまて箱 1–6 | [JR 九州时刻页](https://www.jrkyushu.co.jp/trains/ibusukinotamatebako/) 支持六班端点；[9 月 18–30 日适用的 5 号列车页](https://www.jrkyushu-timetable.jp/jr_k_time/2610/0016/00167901.html?c=29007&d=20&ym=202609)将鹿児島中央发车从 13:56 改为 13:57，已录为 13 个指定运行日的覆盖时刻。[D&S 列表](https://www.jrkyushu.co.jp/trains/)列出指宿枕崎線，[公司线路资料](https://www.jrkyushu.co.jp/company/info/data/line_km.html)证实鹿児島中央起的该线属 JR 九州。六班的运营商区段现为 `verified`，并关联当前 N02 线路标识 | 当前 N02 标识没有历史有效期，`route_lines` 仍为 `partial`；单日列车页所示内部号尚未推广至整季模板 |
| あずさ 1 两种日期版本 | [JR 东日本列车页](https://timetables.jreast.co.jp/2610/train/005/008041.html)、[列车路线说明](https://www.jreast.co.jp/multi/traininformation/azusa_kaiji/)及[2026 年线路区段公告](https://www.jreast.co.jp/press/2026/nagano/20260507_na01.pdf)支持新宿至盐尻 10 个客运站间片段、盐尻至松本 1 个片段；两种版本共 22 条有序区间现对应当前 N02 的中央線／篠ノ井線物理线路 ID | 运营商归属及线路逐日有效期仍未完全证明，路线保持 `partial` |
| ときわ 55 | [JR 东日本服务页](https://www.jreast.co.jp/multi/traininformation/hitachi/) 与[关东线路图](https://www.jreast.co.jp/map/pdf/kanto.pdf) 支持列车走廊；品川→东京→上野及柏→勝田的区间现记录当前 N02 物理线路 ID | 上野→柏跨未停靠的日暮里，需将两条物理线路作为 route-only 界线链接；逐日有效期仍未证明，路线保持 `partial` |
| あかぎ 3／6／9 | [3 号](https://timetables.jreast.co.jp/2610/train/030/034771.html)、[6 号](https://timetables.jreast.co.jp/2610/train/075/076101.html)和[9 号](https://timetables.jreast.co.jp/2610/train/065/068071.html)日文列车页的 2026 年 9 月 30 日运行格均为 `ok`，分别证实 `4003M`／`4006M`／`4009M`、11／12／13 个客运停站及逐站到发；[官方英文 6 号页](https://timetables.jreast.co.jp/en/2610/train/075/076101.html)支持该日英文名称 `Akagi` | 目前只录这一天的三班；其他车次、日期和有序物理线路仍需逐项核对，页面数据的再分发授权未确认 |

[9月19日北斗84](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260919&s=151)／[91](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260919&s=150)与[9月27日ニセコ札幌发](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260927&s=681)／[函館发](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260927&s=680)另经四张指定日期原页逐格核对，分别建立指定日期模板与共53条时刻覆盖。四趟已知内部号只属于各自日期，未复制到基础模板或8月运行日；四页所标刊号均为《JR時刻表》令和8年10月号。[9月22日双向ニセコ](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260922&s=681)另有当日独立原页（[函館发](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260922&s=680)），逐站与已审查对应列一致，新增两个指定日期模板和25条仅限当天的时刻覆盖。

9 月 30 日目前有 769 个单日来源支持的计划实例，涉及北海道、东日本、东海、西日本、四国和九州。东日本 [あずさ 1](https://timetables.jreast.co.jp/2610/train/005/008041.html)、[ひたち 26](https://timetables.jreast.co.jp/2610/train/095/098731.html) 和 [しなの 1](https://timetables.jreast.co.jp/2610/train/000/000041.html) 的当日运行格已按官方列车页核对。先前的四国特别运行班次未被延伸到 9 月 30 日；新入库的南風车次有独立当日证据。

三条并行核验分工又补入 20 个精确日期模板和 238 条停站记录，包括[北海道／东日本批次](train-timetable-east-hokkaido-2026-09-30-batch.md)的宗谷、カムイ与ひたち，[东海／西日本批次](train-timetable-central-west-assignment-2026-09-30.md)的しなの、サンダーバード、やくも及サンライズ出雲，以及[四国／九州批次](train-timetable-shikoku-kyushu-2026-09-30-batch.md)的南風、しまんと、うずしお、ソニック等。サンライズ出雲与瀬戸在东京—冈山的双向合编关系及出雲在冈山的内部号切换已记录。所有新增班次均只用于其原页支持的日期；物理线路未证实的仍保持未知。

下一批又补入 8 个 9 月 30 日模板和 102 条停站：[北海道北斗 1／2 与すずらん 2／5](train-timetable-hokkaido-hokuto-suzuran-2026-09-30-batch.md)、[东海南紀 1 与西日本くろしお 1](train-timetable-central-west-assignment-2026-09-30.md)、[九州にちりん 2 与きりしま 1](train-timetable-shikoku-kyushu-2026-09-30-batch.md)。独立复核逐站对照了上述八班的官方原页，发现北海道四班各有一个札幌站台号漏录，现已修正；其他已录停站、时刻、车次和站台未发现差异。线路与运营者区段仍未证实。

再补入オホーツク2、大雪3592D、宇和海1、はるか1、ひだ1、かささぎ101及ゆふ1，共 7 个 9 月 30 日模板、82 条停站。两轮独立复核对照了这些列车的官方逐日页面，逐格检查站名、到发、站台、车次和日期，未发现已录字段的差异。大雪3592D 的官方类别为「特快」，数据库明确记作 `special_rapid`。这些批次只覆盖其来源印出的日期。

再加入 [オホーツク1／大雪3591D](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110)、[みどり11](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0008/00085801.html?c=28283&ym=202609&d=30) 和 [きのさき1](https://timetable.jr-odekake.net/train-timetable/114351?date=20260930)，共 4 个指定日期模板、49 条停站。北海道与九州两组经独立逐格来源复核；みどり11 与ハウステンボス11 在博多—早岐合编，并保存双向关系。きのさき1 的 10 个站间区间仅有当前 N02 山陰線身份，逐日物理线路有效期仍待证明。

随后又补入 [ライラック1](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110)、[かいじ2](https://timetables.jreast.co.jp/2610/train/085/087651.html)、[きのさき2](https://timetable.jr-odekake.net/train-timetable/90831?date=20260930) 与 [ゆふ2](https://www.jrkyushu-timetable.jp/sp/2610/0016/00167401.html?t=2881400&d=20260930)，合计 4 个 9 月 30 日模板、39 条乘客停站。四班经独立来源逐格复核未发现差异；きのさき2 的 6 个当前 N02 山陰線区间仍为部分核实。ライラック1 的服务证据时段按新增精确日期扩展，未推断中间每一天都开行。

下一批加入 [ライラック2](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111)、[かいじ6](https://timetables.jreast.co.jp/2610/train/075/076151.html)、[サンダーバード2](https://timetable.jr-odekake.net/train-timetable/257941?date=20260930) 与 [ゆふ3](https://www.jrkyushu-timetable.jp/sp/2610/0016/00167201.html?t=2828302e&d=20260930)，共 4 个当日模板、39 条乘客停站。未找到かいじ4的可靠当日详情，故只录已核实的6号；四班经独立逐格来源复核未发现已录字段差异。サンダーバード2 的近江塩津、山科是原页标注的通过站，仅作为 route-only 线路界点；7 个当前 N02 区间的逐日有效期仍未证实。

再加入 [ライラック3](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110)、[かいじ10](https://timetables.jreast.co.jp/2610/train/075/076171.html)、[サンダーバード3](https://timetable.jr-odekake.net/train-timetable/257661?date=20260930) 与 [ゆふ4](https://www.jrkyushu-timetable.jp/sp/2610/0016/00167501.html?t=2881400&d=20260930)，共 4 个 9 月 30 日模板、38 条乘客停站。かいじ8 未找到当日官方详情，因此只录有当日运行格的10号；サンダーバード3 的山科、近江塩津是仅供线路链的通过界点。六段当前 N02 线路身份仍缺 2026-09-30 的物理线路有效期证明。

又加入 [ライラック8](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111)、[かいじ11](https://timetables.jreast.co.jp/2610/train/050/054801.html)、[サンダーバード4工作日版](https://timetable.jr-odekake.net/train-timetable/257961?date=20260930)和[ゆふ5](https://www.jrkyushu-timetable.jp/sp/2610/0016/00167301.html?t=2828302e&d=20260930)，共 4 个 9 月 30 日模板、37 条乘客停站。ライラック4、かいじ12未出现在当日适用的官方列表；かいじ14详情为周末版，未用于平日数据。サンダーバード4周末版时刻不同，本批只采用9月30日工作日页面。[JR西日本线路证据复核](train-timetable-west-thunderbird234-route-validity-2026-09-30.md)补充了2026年营业线区与近江塩津／山科界点资料，仍不足以把当日物理线路及个别车次运营区段标为已验证。かいじ11与富士回遊11在大月前合编的线索在该阶段尚待对应车次核实；本次稳定快照已保存两班新宿—大月的双向合编关系，未据此复制另一车未刊载的时刻。[ゆふ1–5线路证据报告](train-timetable-kyushu-2026-09-30-yufu1-5-route-evidence-gap.md)将鹿児島線／久大線／日豊線与久留米、大分换线点列为当前N02快照的匹配候选；运营商资料尚未证明2026年9月30日五班的完整有序物理线及运营者区段，故未提升为已核实。

另有 12 趟已录列车的 116 个乘客站间区间取得当前 N02 物理线路 ID，完整链与站序经过复核；线路状态仍为 `partial`，因为 2025 年底的 N02 快照不证明 2026 年逐日有效期。[ライラック／かいじ线路证据审计](train-timetable-lilac-kaiji-route-evidence-2026-09-30.md)又确认了八趟列车的运营商路线走廊，但未找到完整逐日物理线路及运营者区段证明；N02中央線在神田结束，与官方「中央本線东京—盐尻」的命名范围不同，东京端线路未据此推填。[JR东日本设施边界与北海道当日整线表补充调查](train-timetable-lilac-kaiji-formal-line-boundaries-2026-09-30.md)给出东京—神田正式设施分类及四趟ライラック在函館本線当日计划表上的直接证据，但不构成各趟完整逐日轨道与运营者区段证明。成田エクスプレス5号的[官方双分支页](https://timetables.jreast.co.jp/2610/train/030/031141.html)证实在东京合编，但新宿支线合编后的独立时刻格为空，未复制另一支线的时刻。[中央线平日列表](https://timetables.jreast.co.jp/2610/timetable-v/223d1p.html)未列出「かいじ3号」，因此没有生成缺少当日原页的 3 号班次。

随后又登记[ハウステンボス11号的逐日页](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0008/00085801.html?c=28283&ym=202609&d=30)及成田エクスプレス5号两条支线，共 3 个模板、26 条停站记录。成田 2005M 大船支线完整印出 9 个客运站时刻；2205M 新宿支线在东京后缺独立时刻，其下游停站与时刻保持部分核实，东京—成田空港的双向合编关系另行保存。独立来源复核未发现已录时刻及站台差异。[南紀1 与 ひだ1 线路核对](train-timetable-central-west-assignment-2026-09-30.md)又补入 24 个当前 N02 物理线片段，河原田是只供线路链使用的界点；两班仍缺逐日线路有效期，保持 `partial`。

本轮进一步加入了按日期限定的来源：[JR 东海夏季补充公告](https://jr-central.co.jp/news/release/_pdf/000045605.pdf)明确 8 班临时「ひだ／南紀」的端点时刻和合计 80 个运行日；[JR 西日本临时列车公告](https://www.westjr.co.jp/press/article/2026/05/15/items/260515_00_press_2026einjiunten.pdf)支持 9 月 27 日双向「いにしへ」；[JR 东日本わかしお 17](https://timetables.jreast.co.jp/2610/train/095/098781.html)及[踊り子 1](https://timetables.jreast.co.jp/2610/train/095/098901.html)页面支持 9 月 29／30 日的逐站版本。踊り子修善寺支未印出的共同区间时刻保持空值。

另外，[JR 北海道とかち 1 的 29 日](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260929&s=130)与[30 日](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=130)页面支持两日各 11 站；[JR 九州ソニック 1](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0001/00013201.html?c=28283&ym=202609&d=29)和[かささぎ 103 的 29 日](https://www.jrkyushu-timetable.jp/jr_k_time/2610/0019/00194501.html?c=08291&d=29&ym=202609)／[30 日](https://www.jrkyushu-timetable.jp/jr_k_time/2610/0019/00194501.html?c=08291&d=30&ym=202609)页面分别支持 16 站和每日 7 站。[南風 2](https://timetable.jr-odekake.net/train-timetable/30871?date=20260930)与[南風 4](https://timetable.jr-odekake.net/train-timetable/59421?date=20260930)的 9 月 30 日页面各支持 13 个乘降停站，通过站未录入。

最新北海道整线批次又从[9 月 30 日札幌方向表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=150)与[带广方向表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=130)逐列转录并交叉复核北斗 3／5／7、すずらん 1／3／7、おおぞら 3／5／7、とかち 3／5／7，共 12 个指定日期模板、155 条停站记录。对应[候选列数据](../app/data/train-service-history/candidates/jr-hokkaido-line-columns-20260930.json)和标准化脚本保留了原列与入库转换的追溯关系；这些停站、时刻、列车号和站台仅适用于已选的 9 月 30 日列。

同一[候选列数据](../app/data/train-service-history/candidates/jr-hokkaido-line-columns-20260930.json)随后从[旭川方向下行表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110)核对ライラック 5／11／13，并从[上行表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111)核对カムイ 6／10、ライラック 12／14／16，先增 8 个仅限 9 月 30 日的模板和 56 条停站。再由札幌、带广、旭川方向的原列补入北斗 9、すずらん 9、おおぞら 9、とかち 9、ライラック 17、カムイ 19，共 6 个模板和 69 条停站；随后又逐列核对北斗 11、すずらん 11、おおぞら 11，增加 3 个模板和 42 条停站；候选文件现保留 29 个逐列复核过的选定列。29 列批次完成时，数据库版本 1.1.0 已有 48 条指定日期计划编组与席别事实、2 条指宿车厢记录；更多设备资料仍在逐班核对。编组资料与计划时刻一样，不能作为实际运行车辆的证明。

[JR 北海道 2025 年 12 月发布的 2026 年 3 月改正公告及附表](https://www.jrhokkaido.co.jp/CM/Info/press/pdf/20251212_KO_kaisei.pdf)另列出北斗、すずらん的主要站基准时刻，可与上述逐日原列交叉核对。公告注明只刊主要列车和主要车站，且时刻属于发布时的计划，可能变更；它自身不能证明 9 月 30 日的全部停站或逐日运行事实，因此未替代指定日期列车页。

新一批又按[北海道 9 月 30 日上行整线页](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=131)补入おおぞら 2／4／6／8／10／12 和 とかち 2／4／6／8／10，共 11 个指定日期版本；来源与逐站转录分别保存在[おおぞら 2](../app/data/train-service-history/candidates/jr-hokkaido-ozora2-20260930.json)、[とかち 2／4](../app/data/train-service-history/candidates/jr-hokkaido-tokachi2-4-20260930.json)及[其余八班](../app/data/train-service-history/candidates/jr-hokkaido-ozora-tokachi-up-rest-20260930.json)候选。另将[ゆふいんの森 1–6 的六张指定日期列车页](../app/data/train-service-history/candidates/jr-kyushu-yufuin-no-mori-six-20260930.json)逐班对应到 9 月 30 日版本；[指宿のたまて箱六班](../app/data/train-service-history/candidates/jr-kyushu-ibusuki-six-20260930-details.json)补入该日列车号与站台，[WEST EXPRESS 銀河昼行](../app/data/train-service-history/candidates/jr-west-ginga-8078m-platforms-20260930.json)补入五处刊载站台。当前数据库有 684 条有日期来源的计划编组记录、786 条车厢明细、217 条指定日期停站时刻覆盖和 6 条指定日期列车号覆盖；其中 236 条编组有车数、128 条有车型、56 条有定员席数，2,517 条模板停站有站台，834 个模板有内部列车号。缺来源的车型或车厢数仍留空。

第二波指定日期列车又补入[北斗 13／15／17／19](../app/data/train-service-history/candidates/jr-hokkaido-hokuto13-15-17-19-20260930.json)、[ライラック 25／27](../app/data/train-service-history/candidates/jr-hokkaido-lilac25-27-20260930.json)、[カムイ 18 与ライラック 20／22／24](../app/data/train-service-history/candidates/jr-hokkaido-s111-kamui18-lilac20-22-24-20260930.json)；北海道候选保留所选原列、停站、时刻和当日证据。[ひたち 4／6](../app/data/train-service-history/candidates/jr-east-hitachi4-6-20260930.json)、[サンダーバード 5](../app/data/train-service-history/candidates/jr-west-thunderbird5-20260930.json)、[はるか 3](../app/data/train-service-history/candidates/jr-west-haruka3-20260930.json)、[ゆふ 6](../app/data/train-service-history/candidates/jr-kyushu-yufu6-20260930.json)、[ソニック 2](../app/data/train-service-history/candidates/jr-kyushu-sonic2-20260930.json)及[しおかぜ 1](../app/data/train-service-history/candidates/jr-shikoku-shiokaze1-20260930.json)也各有指定日期候选。しおかぜ 1 的[当日逐班页](https://timetable.jr-odekake.net/train-timetable/18541?date=20260930)还列出宇多津—松山与 いしづち 1 的计划併结；两班内部号分别为 `1M`、`1001M`。该阶段关联班次尚未入库，只保存证据和待核任务；本次稳定快照已包含 いしづち 1，并保存宇多津—松山的双向车次关系。新增席别只在来源确切对应班次和日期时入库；这些批次不构成 9 月 30 日全国特急全量清单，线路仍按逐日审计标记。

第三波又以 9 月 30 日逐班来源补入[ひたち 8／10／12](../app/data/train-service-history/candidates/jr-east-hitachi8-10-12-20260930.json)、[サンダーバード 7 与 はるか 2](../app/data/train-service-history/candidates/jr-west-thunderbird7-haruka2-20260930.json)、[宇和海 3](../app/data/train-service-history/candidates/jr-shikoku-uwakai3-20260930.json)／[5](../app/data/train-service-history/candidates/jr-shikoku-uwakai5-20260930.json)及[ソニック 4](../app/data/train-service-history/candidates/jr-kyushu-sonic4-20260930.json)，共八个指定日期模板。宇和海 3 的「アンパンマン列車」标识按当日来源保存；新增席别仅代表计划设备，不证明实际派车。上述候选不证明逐日物理线路或运营者区段，相关状态仍按线路审计保留待核。

第四波补入[ひたち 14／18](../app/data/train-service-history/candidates/jr-east-hitachi14-18-20260930.json)、[サンダーバード 8 与 はるか 4](../app/data/train-service-history/candidates/jr-west-thunderbird8-haruka4-20260930.json)、[ソニック 6](../app/data/train-service-history/candidates/jr-kyushu-sonic6-20260930.json)／[8](../app/data/train-service-history/candidates/jr-kyushu-sonic8-20260930.json)及[宇和海 7](../app/data/train-service-history/candidates/jr-shikoku-uwakai7-20260930.json)，共七个 9 月 30 日指定日期模板。ソニック 6 的当日列车页印有「白いソニック」及席别，已作为该日计划标识保存；未据此推定其他日期的车型或实际派车。各班未证实的逐日线路与运营者区段继续留空。

第五波继续补入[ひたち 2／20](../app/data/train-service-history/candidates/jr-east-hitachi2-20-20260930.json)、[はるか 5／6](../app/data/train-service-history/candidates/jr-west-haruka5-6-20260930.json)、[ソニック 10](../app/data/train-service-history/candidates/jr-kyushu-sonic10-20260930.json)和[宇和海 9](../app/data/train-service-history/candidates/jr-shikoku-uwakai9-20260930.json)，共六个 9 月 30 日指定日期模板。ソニック 10 的「白いソニック」与宇和海 9 的「アンパンマン列車」标识，以及所刊席别，均只按对应日期和来源保存；未据此推定实际派车或其他日期的编组。物理线路与运营者区段仍按逐日审计保留待核。

第六波新增 30 趟 9 月 30 日指定日期列车：北海道下行的[カムイ 31／35／43／45](../app/data/train-service-history/candidates/jr-hokkaido-s110-kamui31-35-43-45-20260930.json)、[カムイ 29／ライラック 37／39／41](../app/data/train-service-history/candidates/jr-hokkaido-s110-kamui29-lilac37-39-41-20260930.json)及[サロベツ 1／オホーツク 3／ライラック 33](../app/data/train-service-history/candidates/jr-hokkaido-s110-sarobetsu1-okhotsk3-lilac33-20260930.json)共 11 趟；东日本[ひたち 1／29](../app/data/train-service-history/candidates/jr-east-hitachi1-29-20260930.json)、[3／5](../app/data/train-service-history/candidates/jr-east-hitachi3-5-20260930.json)、[7／9](../app/data/train-service-history/candidates/jr-east-hitachi7-9-20260930.json)共 6 趟；西日本[サンダーバード 6／9／10](../app/data/train-service-history/candidates/jr-west-thunderbird6-9-10-20260930.json)、[はるか 7／8](../app/data/train-service-history/candidates/jr-west-haruka7-8-20260930.json)及[はるか 9／10、サンダーバード 11／12](../app/data/train-service-history/candidates/jr-west-haruka9-10-thunderbird11-12-20260930.json)共 9 趟；另有[ソニック 12](../app/data/train-service-history/candidates/jr-kyushu-sonic12-20260930.json)／[14](../app/data/train-service-history/candidates/jr-kyushu-sonic14-20260930.json)和[宇和海 11](../app/data/train-service-history/candidates/jr-shikoku-uwakai11-20260930.json)／[13](../app/data/train-service-history/candidates/jr-shikoku-uwakai13-20260930.json)。另按班次日期补录 24 趟席别；[ソニック编组与来源记录](../app/data/train-service-history/normalized/trip-formations/reviewed-kyushu-shikoku-seat-equipment-20260930/seeds.jsonl)区分 883 系七辆与 885 系六辆的有来源计划，[はるか九辆计划](../app/data/train-service-history/candidates/jr-west-haruka-planned-nine-car-20260930.json)及サンダーバード 5／7／8 的女性专用席亦只按相应日期保存。车型、车数与席别均为刊载计划，不能证明实际派车。

限定在[JR 北海道 9 月 30 日下行整线表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110)的 29 列，26 列特急的车次号与数据库当日实例 **26／26 对齐**，无缺班或多班；另两列特快「大雪」和一列快速「きたみ」不计入特急闭集，`レ` 通过站也不作乘降停站。这项闭集只覆盖该表当日下行车次，不证明反向或其他走廊的库存、所有逐站时刻和物理线路。

### 第七波逐日车次盘点

第七波再加入 60 个 9 月 30 日模板。下表的分母只来自对应**指定日期、指定方向或服务**的官方表；“闭集对齐”核对的是列车身份与车次号，并不自动证明全程停站、车辆实际派出或全国特急库存。

| 9 月 30 日来源范围 | 已核对的车次身份 | 尚待核对的部分 |
|---|---:|---|
| [北海道札幌方向表 s111](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111) | 26／26 特急列 | 两列特快大雪和一列快速きたみ不计入特急；其他方向表另计 |
| [北海道帯広／釧路方向表 s130](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=130)、[s131](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=131) | おおぞら／とかち 22／22 | 仅限这两张表的当日车次身份 |
| [东日本ひたち上下行清单](train-timetable-east-hitachi-2026-09-30-inventory.md) | 30／30 | 其他常磐线特急系列另计 |
| [西日本はるか／サンダーバード站表链接盘点](../app/data/train-service-history/audits/jr-west-haruka-thunderbird-20260930-inventory.json) | はるか 60／60、サンダーバード 50／50；110 张当日逐班页已审 | 此闭集限于两系列的官方始发站日期链接和对应逐班页，不能代表其他西日本特急 |
| [九州ソニック／四国宇和海闭集盘点](../app/data/train-service-history/sources/candidates/sonic-uwakai-closed-inventory-20260930.json) | 当前库中ソニック 64／64、宇和海 32／32 | 候选盘点文件的 `inventory_status` 是较早快照；现状以当日 SQLite 实例为准 |

[北海道北斗 21／4／6／8 候选](../app/data/train-service-history/candidates/jr-hokkaido-s150-s151-hokuto21-4-6-8-20260930.json)和すずらん 4／6／8／10／12 的 s150／s151 来源仍属部分盘点。西日本新增[はるか 11–20 与サンダーバード 13–22 的逐班候选](../app/data/train-service-history/audits/jr-west-haruka-thunderbird-20260930-inventory.json)；[サンダーバード九辆与 546 席的官方标准编组](../app/data/train-service-history/candidates/jr-west-thunderbird-planned-nine-car-20260930.json)、[はるか九辆计划](../app/data/train-service-history/candidates/jr-west-haruka-planned-nine-car-20260930.json)及北斗 21／4／6／8 的车型均只记录来源所述计划或标准配置，不能据此断言实际派车。所有新增到发、站台、车次和席别均保留逐班来源与日期范围。

### 第八至十七波当前状态

后续批次继续把逐班来源转成指定日期模板；上方各波次的新增数是当时的阶段记录，当前总数以本报告开头和下方审计快照为准。[JR 东海三系列研究盘点](../app/data/train-service-history/audits/jr-central-shinano-hida-nanki-20260930-inventory.json)证明了 9 月 30 日的しなの 26、ひだ 22、南紀 8 个具名车次，当前库内当日实例分别为 26／26、22／22、8／8。该盘点自称“已证明集合”，不排除范围外的临时或区间班次；文件内的旧 `comparison_database` 数字是入库前只读快照。[东日本ときわ逐班盘点](train-timetable-east-tokiwa-2026-09-30-inventory.md)确认 36 班当日运行格，当前库中 36／36。[西日本くろしお盘点](../app/data/train-service-history/audits/jr-west-kuroshio-20260930-inventory.json)有 32 个当日逐班身份，当前库中 32／32。两份盘点文件保留当时的数据库比较值，现状以本次统一 SQLite 的日历展开为准。

[成田エクスプレス已观察逐班盘点](../app/data/train-service-history/audits/jr-east-narita-express-observed-20260930-inventory.json)逐页确认 54 个 9 月 30 日运行的公开号，当前库 **54／54 公开号、84 条 trip**；多于公开号的 trip 对应合编支线或车次号分段，不能按 trip 数推断另有 30 个公开号。另有 5 个所见链接是当天不运行的东京终到变体，未录作运行班次。[候选与规范化记录对账](../app/data/train-service-history/audits/jr-east-nex-candidate-normalized-parity-20260930.json)核对 54 个公开号、84 条 trip、665 条停站、308 个印出站台和 44 个列车号分段，无差异；这是候选到入库的字段对照，不是对所有原页时钟的第二次独立观察。はるか 60／60、サンダーバード 50／50、ソニック 64／64、宇和海 32／32、くろしお 32／32 与ときわ 36／36 也仅表示各自已观察范围对齐，不能据此宣称全国特急清单完整。

全国服务族[定日确证缺口审计](../app/data/train-service-history/audits/jr-limited-express-family-gaps-exact-20260930.json)列出 15 个有指定日期证据的候选服务族；[较广的官方目录缺口审计](../app/data/train-service-history/audits/jr-limited-express-family-gaps-20260930.json)列出 42 个研究缺口。两份非 canonical 审计均以较早的 577 模板库为比较基线，故“缺口”是当时发现任务，不代表本次稳定快照中仍全部缺席，也不证明目录覆盖全国。应逐族核对当日运行、车种分类与现库服务身份后再补录。

北海道补入的[ライラック／カムイ](../app/data/train-service-history/candidates/jr-hokkaido-lilac-kamui-standard-formations-20260930.json)、[おおぞら／とかち](../app/data/train-service-history/candidates/jr-hokkaido-ozora12-tokachi10-standard-formations-20260930.json)等编组事实来自官方标准编成或当日页面图示；车型、车数及席别均按各自证据范围记录，不证明当日实际派车。北斗 10／12／14／16 的[来源登记](../app/data/train-service-history/sources/source-registry-hokkaido-s151-hokuto10-12-14-16-20260930.jsonl)记录了版期差异：指定日期的实时页面刷新显示《JR時刻表》令和 8 年 10 月号，早先搜索缓存显示 9 月号且未显出所选日期；本批以实时逐日页为日期证据，缓存不作日期证明。其他页面也需保留所见版期与抓取语境，不能由 URL 中的日期单独推断刊物版本。

跨天样本使用[JR 西日本 9 月 29 日「サンライズ瀬戸」列车页](https://timetable.jr-odekake.net/train-timetable/38492?date=20260929)：`5031M` 东京 21:26 发，浜松起 6 个乘降站落在次日，高松 9 月 30 日 07:27 到。数据库将这 6 站记为 `day_offset=1`，整趟列车仍归属于 9 月 29 日服务日期；未用次日到达时间另造一趟 9 月 30 日发车实例。

[ときわ 85 的当日逐班记录](train-timetable-east-tokiwa83-86-2026-09-30-batch.md)原页将友部、水戸、勝田印为 `24:xx`；候选保留原始写法，规范化停站写为次日 `00:xx` 且 `day_offset=1`，服务日期仍为 9 月 30 日。跨天规范化只改变时钟表示，不新增另一趟次日发车实例。

## 六家 JR 的官方来源扩展

本轮将六家 JR 的列车系列入口、单列车指南、修订公告与指定日期时刻表分开登记；可重建的来源索引目前收录 **1,216 条研究来源**。新增的官方目录包括 [JR 北海道列车指南](https://www.jrhokkaido.co.jp/train/)、[JR 东日本列车信息](https://www.jreast.co.jp/multi/traininformation/)、[JR 东海在来线特急资料](https://railway.jr-central.co.jp/zairai/)、[JR 西日本列车信息](https://www.westjr.co.jp/global/en/train/)、[JR 四国主要特急清单](https://www.jr-shikoku.co.jp/01_trainbus/vehicle-info/)及 [JR 九州列车目录](https://www.jrkyushu.co.jp/english/train/)。各目录的收录范围不同，不能把目录项数直接当成全国特急总数。 [北海道／东日本整线来源审计](train-timetable-hokkaido-east-2026-09-30-coverage-source-audit.md)已确认北海道三个方向表实际显示9月30日，并找到东日本常磐与中央平日整线表；逐列运行日、特殊符号、反向和其他走廊仍待核对，不能据此宣布当日全量。另找到[JR九州官方主要列车时刻表](https://www.jrkyushu.co.jp/english/pdf/timetable_20260314_20270228.pdf)，封面范围为2026年3月14日至2027年2月28日、内页编制注记为2025年12月且自称仅列常设班次，可作候选盘点，不能覆盖临时车和9月调整后的逐日差异。

单日来源已用于补充 [おおぞら1号](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=130)、[しおさい6号](https://timetables.jreast.co.jp/2610/train/095/098821.html)、[しなの3号](https://timetables.jreast.co.jp/2610/train/000/000081.html)、[やくも15号](https://timetable.jr-odekake.net/train-timetable/681?date=20260930)和 [九州横断特急5号](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0030/00308301.html?c=28742&d=30&ym=202609)。这些只生成已查证日期的实例；目录页和运行频率说明未用于推导其他日期。

### 早期特急原始资料线索

历史资料检索找到可公开查看的 [国立国会图书馆《九州線汽車時間表》第 80 号第 8 画面](https://dl.ndl.go.jp/pid/914814/1/8)：版面标注“大正十五年四月一日補訂”，东京—下关主要列车表列有 1 号一、二等特急东京 08:15 发、下关次日 08:05 到，以及 3 号三等特急东京 08:45 发、下关次日 08:30 到。两条记录已保存于[已审查历史候选](../app/data/train-service-history/sources/candidates/reviewed-historical-batch.json)。这是可核对的**版本日期与端点时刻线索**，不是已证明的逐日运行日历或完整停站表。该表为当时商业出版物，尚未定位对应的铁道省官方原表。

[国立国会图书馆《鉄道の知識・旅客及手小荷物篇》第 122 画面](https://dl.ndl.go.jp/pid/1212739/1/122)还载有注明 1934-12-01 的东京—下关主要列车表，出现「富士」「櫻」「燕」的车次与部分端点时刻；八条起站时刻已存为[已审查历史候选](../app/data/train-service-history/sources/candidates/reviewed-historical-next-batch.json)。“主要列车／主要站”表不能证明所有停站。[JACAR 外交档案行程原件](https://www.jacar.archives.go.jp/acv/contents/pub/pdf/B25/B25090979800.BAdash_0035.RAdash-0869.00000131.pdf)记录 1959-10-18 搭乘「つばめ」的两处发车时刻，但不构成该列车完整时刻表。[国会图书馆 1912 年时刻表目录](https://ndlsearch.ndl.go.jp/books/R100000039-I14603552)仅有书目、数字页须馆内查阅；[1986 年国铁末期时刻表重印本目录](https://books.google.com/books/about/1986%E5%B9%B411%E6%9C%88%E5%8F%B7_%E5%9B%BD%E9%89%84%E6%9C%80%E5%BE%8C%E3%81%AE%E3%83%80%E3%82%A4%E3%83%A4.html?hl=ja&id=-UVhsvTHm1EC)只给出北陆本线页码，均未用于推断车次时刻。这些来源将作为历史研究候选，须继续核对运行日、车站历史身份和当时线路；1926 年东京—下关线路尚无相应已构建历史 overlay，因此不会仅凭端点时刻生成可应用路线。

另找到可直接查看的同期 [1988 年 3 月《交通公社の時刻表》北陆线第 358–359 页](https://books.google.co.jp/books?id=_ExN2yimM0gC&pg=PA359&hl=ja)及[信越线第 428 页](https://books.google.co.jp/books?id=_ExN2yimM0gC&pg=PA428&hl=ja)，两表均印有 1988-03-13 改正。可读出「雷鳥 1」`4001M` 的大阪 07:25、金沢 10:20／10:22、富山 11:05，以及「あさま 1」`3001M` 的上野 07:00、軽井沢 08:55／08:58、直江津 11:06 等部分站时刻。已保存[逐格审查候选与后续核对事项](../app/data/train-service-history/sources/candidates/reviewed-historical-1988-batch.json)，并登记来源和研究任务。改正起始日不等于全部后续运行日，已抄列的格子也不是完整客运停站表；与库中历史线路 ID 的对应仍是待核查假设，因此尚未生成正式班次或把线路标为已核实。

另有[高山本线历史转录目录](https://www2u.biglobe.ne.jp/~m-wata/special8.html)链接到[1973 年下行表](https://www2u.biglobe.ne.jp/~m-wata/special8-tkym_s48_1.html)和[1980 年下行表](https://www2u.biglobe.ne.jp/~m-wata/special8-tkym_s55_1.html)：页面分别列出「ひだ」`3011D` 名古屋 15:15，以及「ひだ 1」`1031D` 名古屋 08:00、岐阜 08:30、下呂 10:02／10:03、高山 10:58。这是私人后期转录，且目录说明仅载主要列车；尚未找到相应原刊页像和运行日图例，不据此生成正式班次。[JTB 出版社 1978 年 10 月复刻本页面](https://books.jtbpublishing.co.jp/e-book/60001-19781001122-000/)可作为追查当期「くろしお」的书目入口，但未提供可逐列核验的时刻；页面文案还混写 1975 年，须回到原刊核对。

## 已测快照仍缺的证据

### 历史线路时间边界

线路时间边界按各条已构建线路的 `service_validity` 判断，结束日不包含在可通行区间内；没有明确起点的 `null` 只表示模型尚未设置起点，不能当作早期运营证据。H1 历史线路计划的 1993-04-01 是资料建设范围，并非禁止更早特急查路线的全局开关。有直接历史线路身份与运行日期证据的早期班次仍可核对线路；未能对齐的班次继续可查时刻，但线路保持未核实。现代线路的开放结束时间不因 N02 最近快照或本库 `as_of_date` 而截断，未来班次仍须有自己的时刻表来源。超出已核实时间跨度的线路和班次资料保留在库中，不据此扩大可证实范围。

本轮还让时刻表线路审计读取**覆盖整条当前 N02 线路**的历史开通／结束标记：若班次日期越界，报告为线路错误；若日期在界内，仍保留“未核实”，直到有完整的物理线路证据。只覆盖线路一部分的标记不会误用于整条线，车站专用标记也不作线路判定。现有 882 个模板中尚无班次命中此类整线标记，因此本次没有把既有未核实线路提升为已核实。

目前已构建的线路时间事件并不构成完整的 1993 年以来全国网络：最早的精确编译变更是 1993-08-12，1993–1996 年几何仍有缺口；N02-05 的年份是来源快照而非所有线路的精确开通日。东叶高速线已有 1996-04-27 起的明确服务区间，札沼线北海道医療大学—新十津川段则以 2020-04-18 为服务结束日，晚于该日的法律废止日不能延长乘车线路。这些边界用于解释匹配结果，不能替代每趟特急的停站、运行日及线路身份来源。

数据库的事实记录中，停站有 **56 个 `partial`**、时刻有 **195 个 `partial`**；按已入库列车模板计算，线路有 43 个 `partial`、839 个 `unknown`。线路审计仍有 7,607 个未核实站间区间，历史线路对齐审计为 0 个已对齐、1,114 个未核实。43 个模板记录了 275 个当前线路身份片段，但有班次日期有效期证据的片段为 0；另 839 个模板没有线路片段，逐日线路求解尚未运行。覆盖审计的 `unresolvedRoutes=883` 还包含一条不属于这 882 个模板的服务级未知线路事实。日期限定版本会增加按模板统计的未核实项，却不会增加未经证实的计划运行日。覆盖审计 `coverageComplete=false`，缺 2,448 个覆盖单元，另有 48 个部分覆盖或受阻单元；`operatorsCovered=0/6`，六家 JR 的全年、逐日全量清单均未得到证实。已存字段通过核验不等于未列出的停站、班次或历史有效期也正确。

逐日时刻审计的709次“双侧时刻均空白”现在可[按列车、运行日和停站序号追查](../app/data/train-service-history/audits/train-timetable-stop-chronology.json)：其中605次来自北斗84／91及ニセコ双向在多个运行日重复出现的模板空格。该计数按班次实例计算，不能理解成709个不同车站需要一次性补写同一个时刻。

已核实 26 条运营商英文名称时段记录，覆盖 21 种服务。[JR 北海道双语列车指南](https://www.jrhokkaido.co.jp/train/tr036_01.html)使用「Niseko express」，[2026 年特设页](https://www.jrhokkaido.co.jp/travel/niseko/index.html)证实同名服务，因此补入 2026 年「ニセコ」英文名称。本轮又以各运营商英文页补入 [Ozora](https://www.jrhokkaido.co.jp/global/english/train/guide/obihiro.html)、[Shiosai](https://traininfo.jreast.co.jp/train_info/e/express.aspx?group=shiosai)、[Yakumo](https://www.westjr.co.jp/global/en/train/yakumo/) 与 [KYUSHU ODAN TOKKYU](https://www.jrkyushu.co.jp/english/train/odan.html)。2013 年「しなの」「ひだ」「南紀」仍缺相应时段的运营商英文证据，继续留空；当前英文页面不能证明当年也使用同一名称。

覆盖审计另列出 **69 个未解决车站引用、2 个未解决来源项**；来源索引有记录不等于每项引用、历史身份或再分发许可都已核实。这些缺口与停站时钟、物理线路缺口分别保留，不能因结构测试通过而清除。

`actual_operation_events` 仍为 **0**。计划时刻表和延误通告不能证明某班在某站的实际到发；应用中的提前／延误比较继续以用户手动记录的实际时刻为准。部分时刻表来源仅准用于核验，重新分发授权也尚未解决。历史车站应用、完整有序物理线路、分合编组、1987 年以来各版时刻表与更早历史资料仍在研究队列中。

## 重建与验证

### 加入行程界面

2026-09-30 续接复核重新运行 `JourneyCompletionTests`，**30 项全部通过**；可复现命令与能力范围见[AI 补全文档](journey-ai-completion.md)。当前应用请求门槛是命名停站、可补字段，以及至少一个站库确认站点和该站的合法时刻，不再用核心默认提示生成器的“两项检索线索”规则描述应用入口。途中停站可凭具备日期证据的时刻表插入；响应不能更改既有站点身份、填入实际运营记录或宣称线路已核实。原生 UI 续接已将本地检索改为输入就绪后自动启动（300 毫秒防抖），保留明确选用结果的步骤；编辑器 AI 提示复用全部已载入站库的共同门槛。订阅补全请求仍可使用实时网络搜索但不先查本地库。自动检索与过期结果清除已通过隔离模拟器测试（299.285 秒）；来源符号和端点的加强可见截图检查也已在该已测快照上通过。背景资料更新维持用户的每周偏好，本续接不创建自动任务。

按 SwiftUI 界面设计与状态稳定性检查，新行程依次选择地区、路线、车次、日期并确认；日期页的本地时刻表查询会先用已载入站库解析唯一匹配的两端站名，再检查日期和两端时间，不要求用户另行输入站码。发现查询中修改日期或特急名称时，旧的异步结果仍可能回写、搜索按钮也可能保持忙碌；现已在输入变化或离开页面时取消查询并清空过期状态。AI 补全也会自动解析唯一匹配的站名，重名车站仍需明确选择，避免把「桂川」等同名站填错；日期、两站名称与时间、车辆类型及特急名称仍作为检索线索进入补全流程。有逐站时刻表来源时，AI 可在两端站之间建议途中停站；合并会校验插入位置、时刻顺序和来源，保留原有字段，审核页按完整停站顺序展示，未能唯一对应站库的站名标记为待选站点。标准风格静态扫描对本地查询视图和 AI 补全视图均无高、中风险提示；编辑器中的六处中等提示经逐项检查为测试专用延迟、只读列表索引、小尺寸标记及已有取消条件的搜索节流，未据此改动交互。iOS 模拟器构建通过；现有「日期／跨天停站」和「覆盖不完整提示」两项 XCUITest 在隔离模拟器上通过，AI 补全的 30 项 Swift 测试通过，覆盖最小输入、途中停站插入、错误时刻及原子合并。快速连续改日期的竞态除代码路径与取消条件核对外，续接专项 XCUITest 已验证旧结果清除；有效日期恢复匹配，无效特急名清空匹配，恢复北斗名称后再得到匹配。

原生 UI 续接最终在隔离 iPhone 17 Pro／iOS 27 模拟器上完成 **8 个不同专项用例的通过记录**，分布在多次运行中，不是完整 UI 套件或一次八项全通过的运行：未填车次号推进日期页（61.492 秒）、共享日期／跨天停站（90.090 秒）、浅色／深色地图及统计分享（105.428 秒）、无效／空 AI 回复（340.065 秒）、途中停站审核与 Apply 到草稿（725.040 秒）、自动匹配与日期／服务名变化后的清除／恢复（299.285 秒），以及加强后的可见端点标签（16.741 秒）和可见来源符号（327.551 秒）。后两项 VisibleEvidence 运行退出码 0，确认北斗 `レ`、ハウステンボス `||` 在屏幕中可见；端点测试使用紧凑面板与关闭线路的测试设置，完整选中路线另有截图检查。分享保留日本及 2026-07-03 范围，车票明确展示全时段 Totalled 汇总。途中停站 fixture 只验证审核／应用到草稿，不证明原始时刻来源或持久保存。

早期三次组合分别为 2／5、1／6 和 4／5 通过，包含长列表滚动、面板展开、文本框聚焦和可访问性定位的测试失败，以及真正的 AI 空回复缺陷：空 `{"trains":[]}` 在预览层触发唯一站名解析、补入站码后错误启用 Apply。已测修复只对合并确实改变的行程解析站名；隔离复测确认无效 JSON 被拒绝、空回复保持 Apply 禁用。后续 QuickMatch 与加强可见性运行均通过，旧失败及可访问行／框架断言的较窄范围仍保存在[原生验证清单](native-ui-integration-validation-2026-09-30.json)。此前未送达的最终交接已由协调 chat 从持久证据读取，不再将这些专项结果标为待完成。

文档续接独立核对原生清单中 **14 个持久摘要／PNG 的 SHA-256 全部一致**，读取其中最终通过摘要，并检查ハウステンボス非行经符号及紧凑地图端点截图。五个临时日志、五个 `.xcresult` 与已构建应用中的 SQLite 均已不存在，无法重新打开原始运行产物；清单记录的应用数据库仍是下文 `af8568aa…96f4`／来源 `9b67f995…a5d0` 快照。复核时七个登记原生文件中五个哈希已变化，当前 canonical SQLite 也与已测哈希不同；这不是新的测试失败，而是旧结果不能覆盖后续工作树修改。此文档更新没有重跑 UI，也没有修改产品、数据或 Git。

从候选资料运行 `python3 ios/tools/rebuild-reviewed-train-timetable.py`，依次生成 canonical JSONL、SQLite、应用资源和审计文件。本次统一快照验证了 40,005 条规范化记录，数据库包含 68 种服务、882 个模板、2,403 个计划实例、8,520 条客运停站、24 条独立时刻表符号记录和 88 条班次关系。`||`／`レ` 符号单独保存，不计作客运停站，也不以符号代造乘降时刻。新增五个来源批次已由数据 owner 注册；あずさ 44 先于富士回遊 44 规范化，使该合编关系能在统一重建时建立，不能据此复制另一支线未印出的时刻。

[独立来源符号复核](train-timetable-symbol-source-audit-2026-09-30.md)仅检查北斗 1／2 与ハウステンボス 11 的三个指定日期列，确认 15 个 `レ`、9 个 `||`，不代表全国符号覆盖。前一快照漏存北斗两列各四个分支 `||`；现已补回，并使北斗 2 的伊達紋別／洞爺 `レ` 排在分支行之后，保持原表顺序。此修复新增八条非客运记录，不增加停站或班次；转换器可从候选重建符号，不依赖保留旧产物。原始网页／图像未保存于仓库，已留 URL、日期与选列定位；逐页事实观察仍不解决来源再分发许可。

该已测快照的 SQLite SHA-256 为 `af8568aa8b5ecadee80ec335891d9d0a7f7b0edb918b421bd7436088d07996f4`，规范化来源哈希为 `9b67f9950604dc43eee861bbc48d0661ebb58033fac963f4775dda71b7a5a5d0`。该快照的覆盖审计当时保存同一数据库／来源哈希；当时的应用打包 SQLite 与 canonical 库一致，数据 owner 在临时路径重复构建得到逐字节一致的 SQLite。逐日时刻结构审计检查 2,403 个计划实例的 21,549 个已知时钟格，未发现结构性时序错误；709 次乘客停站双侧时钟空白仍保留在审计中，不能由结构通过推断其原页已补齐。线路审计的 solver 仍未运行，历史对齐有 0 个已对齐、1,114 个未核实、0 个错误。

第十七波的历史固定 SQLite SHA-256 为 `37e5f389f93422511ed10338a35300303aca538dece4ebb2908f9715cf74c9ad`（770 模板、2,291 实例、7,339 停站）。其后候选写入曾导致 `snapshotAligned=false`；该差异已由本次统一重建消除。第七波 Python 455 项、RailKit 23 项以及第十七波报告一致性通过均属于旧快照，不能代替本次完整回归。

修复八条分支符号后，数据 owner 在冻结快照上运行 `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s ios/tools/tests -v`，**1,005／1,005 通过**，耗时 704.542 秒、退出码 0；报告 owner 同时读取了最终日志的测试总数与 `OK`。这次包含更新后的符号、批次、合编、车次盘点及报告一致性测试。

最终 `./ios/verify.sh --core` 以临时构建及模块缓存路径运行，**退出码 0、最终 `OK`**。RailKit 全量验证为 **926／926 通过**：611 项 core（67 个套件，1,004.678 秒）及 315 项 presentation（29 个套件，0.839 秒）；包含更新后的符号断言和 298 个服务模式的线路比较。门槛还通过 35 个生产编辑器校验场景、18 个保存／回滚场景、10 个订阅授权及 9 个订阅 HTTP fixture；JR 东日本列车页解析器另有 3／3 通过。这些 fixture 不联网、不使用真实凭据，也不构建或运行 iOS 应用，不能代替模拟器重试或逐页来源确证。确切命令与各次失败／中断的边界见[数据交接](train-timetable-data-handoff-2026-09-30.md)，产物与测试日志哈希见[最终验证检查点](../app/data/train-service-history/audits/train-timetable-validation-checkpoint-20260930.json)；报告 owner 在该阶段独立复核其中 8 个产物与 3 个日志的哈希一致，并读取 Swift 日志的 611／315 项及门槛最终 `OK`；这不是对后来修改的产物重新验证。

2026-09-30 报告续接独立运行 `python3 -m unittest ios.tools.tests.test_timetable_report_parity -v`，**1／1 通过**；`python3 ios/tools/verify-train-timetable-artifact.py` 返回 `snapshotAligned=true`、无错误，包含 SQLite 完整性、外键、历史线路／车站资源及求解器版本一致性检查。另从 canonical 数据重新展开 9 月 29／30 日，确认 25／769 个实例，复算来源指纹并核对两个 SQLite 的完整 SHA-256；两份报告的 **88 个本地链接当时均存在**。这些是当时报告与已测快照一致的记录，不替代逐页来源核验、全国覆盖或真实设备验证，也不是当前工作树的一致性检查。本次补完文档另检查两份报告的 **90 个本地链接均存在**；未重跑旧报告计数测试或数据／UI 回归。

该已测快照的固定计数、缺口和验证结果以数据交接与最终验证检查点为准。工作区的[覆盖审计](../app/data/train-service-history/audits/train-timetable-coverage.json)和其他产物可能随后续修改更新，不能再默认与该快照一致；[停站时刻与线路复核](train-timetable-stop-route-audit-2026-09-29.md)及[数据库说明](train-timetable-database.md)保留来源边界、时间语义和重建流程。
