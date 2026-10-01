# JR 東日本／北海道逐班核验分工记录（2026-09-30）

## 本批有证据的增补

本分工新增 2026-09-30 精确日期候选，不修改共享重建入口、manifest、SQLite 或共享审计。官方[ひたち13号页面](https://timetables.jreast.co.jp/2610/train/060/064241.html)和[ひたち22号页面](https://timetables.jreast.co.jp/2610/train/095/098721.html)的 9 月 30 日格属于所显示时刻的日历变体；页面分别印出 13M、22M、各 21 个乘客停站及其分钟到发。两个始发站未印到达侧、终到站未印发车侧，候选及规范行均保留 `null`。仅给 9 月 30 日添加 calendar exception，不从相邻日期推断运行。

| Trip ID | 内部号 | 区间 | 乘客停站 | 官方原页 |
|---|---|---|---:|---|
| `jr-east.hitachi.13.exact-2026-09-30` | `13M` | 品川→仙台 | 21 | [列车页](https://timetables.jreast.co.jp/2610/train/060/064241.html) |
| `jr-east.hitachi.22.exact-2026-09-30` | `22M` | 仙台→品川 | 21 | [列车页](https://timetables.jreast.co.jp/2610/train/095/098721.html) |
| `jr-hokkaido.soya.51d.exact-2026-09-30` | `51D`（公开号未印） | 札幌→稚内 | 17 | [逐日列车表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110) |
| `jr-hokkaido.soya.52d.exact-2026-09-30` | `52D`（公开号未印） | 稚内→札幌 | 15 | [逐日列车表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111) |
| `jr-hokkaido.kamui.7.exact-2026-09-30` | `2007M`／7号 | 札幌→旭川 | 7 | [逐日列车表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110) |
| `jr-hokkaido.kamui.4.exact-2026-09-30` | `2004M`／4号 | 旭川→札幌 | 7 | [逐日列车表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111) |

候选为 `app/data/train-service-history/candidates/jr-east-hitachi13-22-20260930.json`；专属转换器为 `ios/tools/normalize-reviewed-east-hitachi13-22-20260930.py`；来源登记为 `app/data/train-service-history/sources/source-registry-east-hitachi13-22-20260930.jsonl`。转换器只写带 `east-hitachi13-22-20260930` 后缀的规范文件与专属子目录。源网页用途记为核验，未声称获得时刻事实再分发授权。

后续通过浏览器核对 [北海道 9 月 30 日下行表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110)：日期选择器明确为 `2026年9月30日(水)`，`51D / 宗谷` 所在列印出 17 个乘客停站的时刻，号数格空白。旭川印有 `08:58 着／09:00 発`；比布、剣淵显示 `レ`，因此没有作为停站入库。其余只印发车的中途站保留到达侧为空。专属候选、转换器和来源登记分别是 `app/data/train-service-history/candidates/jr-hokkaido-soya51d-20260930.json`、`ios/tools/normalize-reviewed-hokkaido-soya51d-20260930.py`、`app/data/train-service-history/sources/source-registry-hokkaido-soya51d-20260930.jsonl`。

[同日上行表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111)的 `52D / 宗谷` 列也不印公开号，印出 15 个乘客停站；剣淵、比布、砂川、美唄为 `レ`。其候选及专属转换器是 `app/data/train-service-history/candidates/jr-hokkaido-soya52d-20260930.json` 与 `ios/tools/normalize-reviewed-hokkaido-soya52d-20260930.py`。上行来源登记、停站与事实文件只使用 `hokkaido-soya52d-20260930` 后缀。两个方向均未把未印到达格补成推断值。

[下行表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110)同时核实 `2007M / カムイ7` 的 7 站与分钟发车／终到时刻，保存于 `app/data/train-service-history/candidates/jr-hokkaido-kamui7-20260930.json`，由 `ios/tools/normalize-reviewed-hokkaido-kamui7-20260930.py` 生成专属规范文件。专属日文名称期只覆盖 9 月 30 日；共享 `kamui` 服务记录的 `last_verified_date` 仍为 9 月 27 日，候选中的 `service_metadata_extension` 明确要求主分工审核后延长到 9 月 30 日。此处不复制共享服务记录，也不将 9 月 30 日列扩展到相邻日期。

[上行表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=111)同时核实第二列 `2004M / カムイ4`：旭川 06:46、深川 07:05、滝川 07:19、砂川 07:25、美唄 07:37、岩見沢 07:48、札幌 08:26。候选与转换器分别为 `app/data/train-service-history/candidates/jr-hokkaido-kamui4-20260930.json` 和 `ios/tools/normalize-reviewed-hokkaido-kamui4-20260930.py`。中途站只印发车时刻，故到达侧为空；本趟沿用カムイ7同日名称期，不写重复名称期或服务记录。

## 核验与边界

- 执行五个转换器后，本分工新增 6 趟、88 条停站行；最近一次 `python3 ios/tools/validate-train-timetable.py` 通过，共校验 8,574 条当前规范记录（含并行分工已写入的规范文件）。
- `python3 -m unittest ios/tools/tests/test_east_hitachi13_22_20260930_source_pinned.py -v` 的 2 项测试通过：比较逐站到发、内部号及来源 URL，并验证 9 月 29 日／10 月 1 日不出现这些精确日期模板。
- `python3 -m unittest ios/tools/tests/test_hokkaido_soya51d_20260930_source_pinned.py -v` 的 2 项测试通过：比较逐站到发、`51D`、来源、通过站排除及日期边界。
- `python3 -m unittest ios/tools/tests/test_hokkaido_soya52d_20260930_source_pinned.py -v` 的 2 项测试通过：比较逐站到发、`52D`、公开号空格、通过站排除及日期边界。
- `python3 -m unittest ios/tools/tests/test_hokkaido_kamui7_20260930_source_pinned.py -v` 的 2 项测试通过：比较 7 站顺序、`2007M`／7号、来源、日期边界以及未知线路／运营分段。
- `python3 -m unittest ios/tools/tests/test_hokkaido_kamui4_20260930_source_pinned.py -v` 的 2 项测试通过：比较 7 站顺序、`2004M`／4号、来源、日期边界以及未知线路／运营分段。五个测试文件合计 10 项通过。
- 本批未运行全量重建或修改应用资源。manifest 现有 glob 能读入专属规范文件，但 SQLite 尚未由本分工重建。
- 没有逐日期的有序物理线路 ID 与运营分段证据；六趟的两项都保留 `unknown`，没有把发布者身份当成运营区段证明。当前 N02 站组只用于车站身份，其中东京采用既有核对过的 `003766` 组。

## 北海道及下一步未解决清单

- 复核了 [9 月 27 日北海道下行逐日表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260927&s=110)：カムイ9号的 `8009M` 列与现有精确日期模板的全部已印发车格一致；未印到达格仍未知。本批未重复增补该趟。
- 北海道 9 月 30 日上下行表均可在浏览器中核验，本批据此新增宗谷 `51D`／`52D`。既有サロベツ3／4号的未印到发侧仍缺直接证据；宗谷两列也没有补造这些未印侧。
- 搜索缓存中的 [北海道 8 月 7 日下行 URL](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260807&s=110)及[上行 URL](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260807&s=111)曾显示 `8015M`／`8036M`。实际重新打开时，网站把两个旧日期 URL 转到 9 月 29 日，日期选择器最早为 8 月 25 日。因此不能把缓存视为目前可复核的 8 月 7 日原页；未提升这两趟的内部号、停站或时刻。原公告模板覆盖 8 月 7–9 日且仅有端点；将来若取得可复核的 8 月 7 日列，日期切分须先从原模板排除 8 月 7 日，再新建该日详细模板，8 月 8–9 日保持公告粒度。本分工未改共享 `north-shikoku-batch` 文件，也未创建同日重复班次。
- 主分工需要把重建入口中的旧脚本名 `normalize-reviewed-hokkaido-soya1-20260930.py` 换成 `normalize-reviewed-hokkaido-soya51d-20260930.py`，并登记 `normalize-reviewed-hokkaido-soya52d-20260930.py`、`normalize-reviewed-hokkaido-kamui7-20260930.py`、`normalize-reviewed-hokkaido-kamui4-20260930.py`。同批还需核定共享 `kamui` 服务 `last_verified_date` 从 9 月 27 日延长到 9 月 30 日；不改变已有 8 月／9 月运行日证据。
- 东日本其余特急列车、两家完整逐日班次清单、历史版本、物理线路及运营边界尚未逐班穷尽；仍须逐页确认具体日期变体及车站格。当前未把 131 模板基础库存或本批两个候选解释成全量覆盖。
