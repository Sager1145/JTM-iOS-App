# 大阪地下站线路核对与きのさき1号有限批次（2026-09-30）

## はるか1号、くろしお1号：大阪地下站仍未解

两张精确日期列车页分别为[はるか1号 1001M](https://timetable.jr-odekake.net/train-timetable/91?date=20260930)与[くろしお1号 51M](https://timetable.jr-odekake.net/train-timetable/38921?date=20260930)。两页均显示新大阪→大阪地下 **21 番站台**→西九条通过→天王寺的顺序；「レ」表示通过，不是乘降停站。

[JR 西日本 2022 年开业运转公告](https://www.westjr.co.jp/press/article/items/221209_00_press_unkoutaikei.pdf)将新大阪至大阪环状线的接入线路称为「東海道線支線」，并明确はるか、くろしお停靠新增地下站。[JR 西日本线路改接公告](https://www.westjr.co.jp/press/article/items/221209_00_press_senrokirikae.pdf)指出施工切换在新大阪～西九条之间的两处进行。[大阪市竣工资料](https://www.city.osaka.lg.jp/kensetsu/page/0000298160.html)确认东海道线支线地下化于 2023-02-13 切换、项目于 2025-03-31 完成。[JR 西日本西九条配线改良说明](https://www.westjr.co.jp/press/article/2019/09/page_14939.html)证明はるか、くろしお使用西九条站线，但该资料是改良前说明，不能决定 2026 年具体接轨点。

当前 [`jp-2025.json`](../app/public/rail/jp-2025.json) 中可找到 `jp-西日本旅客鉄道-東海道線`（有新大阪、大阪）、`jp-西日本旅客鉄道-東海道線-2`（仅大阪、福島两个站锚点）及 `jp-西日本旅客鉄道-大阪環状線`（大阪、福島、野田、西九条等）。官方资料并未把实际支线接轨点唯一定位为 N02 的福島站锚点，也未证明地下站北侧进路等同于 N02 主线新大阪→大阪的几何。因此**不能**将新大阪→大阪→天王寺逐段强配到这些 ID，亦不能把大阪→天王寺写成普通环状线大阪→福島→野田的站序。两班的大阪段保持未知；待获取现行配线图或 N02 原始区间级拓扑与官方接轨点可相互定位的证据后再编码。

[国土交通省 N02-25 目录](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html)的基准日是 2025-12-31，单独也不能证明 2026-09-30 的逐日物理线有效期。本研究没有改动两班路线候选、共享 rebuild 或 SQLite。

## 独立候选：きのさき1号

从[京都站 2026-09-30 嵯峨野线 07:32 链接](https://timetable.jr-odekake.net/station-timetable/2784055001?date=20260930)进入[きのさき1号精确列车页](https://timetable.jr-odekake.net/train-timetable/114351?date=20260930)，列车编号 `5001M`，京都 07:32 发、城崎温泉 09:52 到。共 11 个计时乘降站；全部「レ」通过站排除。该页标注「毎日運転」，候选仅收录 9 月 30 日一次，不推展运行日历。JR 西日本[2026 年 9 月票价规则](https://www.jr-odekake.net/ticket/guide/ebook/pages/pageindices/index15.html)明确称京都～城崎温泉为「山陰本線経由」；当前 N02 对应单一连续 `jp-西日本旅客鉄道-山陰線`，11 个乘降站在该线的顺序唯一。10 个乘降站间片段的 `reference_kind=current_n02`，`route_lines=partial`，逐日有效期研究保持 `open`。

产物：独立[候选](../app/data/train-service-history/candidates/jr-west-kinosaki1-20260930.json)、[来源登记](../app/data/train-service-history/sources/source-registry-west-kinosaki1-20260930.jsonl)、[normalizer](../ios/tools/normalize-reviewed-west-kinosaki1-20260930.py)和专属测试；规范化文件后缀 `west-kinosaki1-20260930`。原始 HTML 未保存。列车时刻来源注明禁止无授权转载或加工，登记限于证据核验用途。
