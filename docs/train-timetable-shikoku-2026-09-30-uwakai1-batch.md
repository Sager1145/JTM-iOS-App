# JR 四国 宇和海1号：2026-09-30 单日核验

## 已核验并生成

从 [JR 西日本 2026-09-30 予讃線・内子線下行区间表](https://timetable.jr-odekake.net/line-timetable/2469?day=30&month=9&year=2026) 的 `1051D` 列车详情按钮进入[同日宇和海1号全程页面](https://timetable.jr-odekake.net/train-timetable/1221?date=20260930)。详情印 `特急 宇和海1号`、`1051D`、`毎日運転` 和松山 05:48 发至宇和島 07:12 到的全部 8 个乘降站。`レ` 通过行没有录为停站；起点未印到时、终点未印发时及空白站台保持 `null`。

| 项目 | 结果 |
| --- | --- |
| trip ID | `jr-shikoku.uwakai.1.2026-09-30` |
| 候选 | `app/data/train-service-history/candidates/jr-shikoku-uwakai1-20260930.json` |
| 来源 ID | `jr-odekake-uwakai1-20260930-train`、`jr-odekake-uwakai1-20260930-line` |
| 规范化脚本与后缀 | `ios/tools/normalize-reviewed-shikoku-uwakai1-20260930.py`；`reviewed-shikoku-uwakai1-20260930` |
| 已生成 | 1 条单日 trip、8 条停站时刻、1 条日期例外；七个星期位均为 0，没有推定复发日 |

两条新来源只登记人工核验所需的页面指针，未捆绑网页原始内容。站名仅匹配唯一的现行四国站代码；没有从时刻表发布主体推定运营者边界或物理线路 ID。`operator`、`route_lines` 保持 `unknown`，没有生成 `trip-lines` 或 `trip-operator-segments`。共享 rebuild、manifest、SQLite、其他运营者文件均未修改。

## 检查与未入库证据

`python3 ios/tools/normalize-reviewed-shikoku-uwakai1-20260930.py` 成功。`python3 -m unittest ios.tools.tests.test_shikoku_uwakai1_20260930_source_pinned -v` 三项通过，核对官方 URL、单日 calendar、8 条时刻、空值及未定线路／运营者区段。本批仍需共享整合方登记脚本和执行全量校验。

[JR 西日本 2026-09-30 あしずり1号详情](https://timetable.jr-odekake.net/train-timetable/103922?date=20260930)虽可从[同日土佐くろしお铁道下行区间表](https://timetable.jr-odekake.net/line-timetable/2475?day=30&month=9&year=2026)复取，但明确写有“９月２９日～１０月１日は須崎－窪川間運休・同区間バス代行輸送”。详情在须崎只印到达、窪川只印发车，中间不是列车运行。故未创建跨该区间的单一列车 trip；需要日期适用的分段运行与代行巴士证据后再建模。旧日期搜索所得 `train-timetable/104381` 在 9 月 30 日指向另一列车，也未用作证据。
