# JR 特急时刻表冲突审计（2026-09-28）

## 结论

本次把生产 canonical 数据与研究候选分开审计。生产数据没有可复现的重复运行实例、日历重叠或时刻冲突：validator 接受 4,082 条 canonical 记录，SQLite 含 95 个 trip template、66 个日历、984 条明确日期例外及 363 条停站时刻，`fact_completeness.status=conflict` 为 0。这个 **0 只描述已进入 canonical 的事实，不能解释为候选目录没有冲突，也不能解释为六家 JR 已完整覆盖**。

生产层唯一重复的公开身份是あずさ1号（列车番号 1M）的两套模板。两套日历分别覆盖 2026-09-18、22–25、27、28 日，以及 2026-09-19–21、26 日，交集为空；两套时刻在上諏訪以后的差异由各自官方列车页和明确日期支持。这是合法的日期快照切分，不是同日重复实例。

候选层有一项明确的原始来源时刻冲突：JR 西日本 2026 年夏季公告内，サンダーバード95号在京都的发车时刻，第 7 页两处为 09:23，第 8 页为 09:22。逐日核对 JR おでかけネット列车级页面后，公告列出的五个运行日全部显示列车 9095M、京都 09:20 着／09:22 发。候选现在以单独的 `resolved_clock` 记录五日期均适用的 09:22，同时保留原 PDF 的 09:22／09:23 观测值和冲突说明；没有覆盖原始观测，也没有提升为 canonical。**若以后提升，京都发车时刻应采用 09:22，并继续保留这条来源分歧与逐日列车页出处。** 未找到 JR 西日本单独发布的正式勘误，故本报告不把逐日页面称为公告勘误。

当前 app 的生产数据库不含サンダーバード95号，候选 JSON 也不被运行时直接读取，所以这项候选冲突不会使现有查询产生两个班次或错误时刻；用户侧结果是该班次目前不可选，而不是显示一个猜测值。生产 SQLite 与 RailCore 资源副本字节相同且快照对齐，数据层可加载。主任务已完成隔离模拟器的三项真实UI检查，详情见[应用内检查](train-timetable-app-usability.md)；本报告的数据层审计不替代全部交互回归。

## 范围与判定规则

审计范围为：

- `app/data/train-service-history/manifest.json` 选中的全部 canonical JSONL，以及由其生成的生产 SQLite；
- `app/data/train-service-history/candidates/` 中 10 个 JSON；
- `app/data/train-service-history/sources/candidates/` 中 6 个 JSON；
- 生产审计报告、运行时 SQLite 资源副本和官方日期特定页面。

重复身份按 `(service_id, train_number/public_number, origin, destination, direction)` 审查。同一身份可以有多个模板，但同一日本服务日期只能物化一个未建立 relation/operation group 的实例。日历使用半开区间并以实际 `add` 例外为准，不能只比较 edition envelope。时刻冲突要求同一身份、同一站、同一字段和同一适用日期存在不同来源值；未知值或未列值不算冲突，也不能用相邻时间反推。

## 生产 canonical 审计

### 身份与日历

生产 validator 会拒绝 canonical 主键重复、时刻表版本与日历不相交，以及同一公开身份在同一天物化两次。本次全部通过。对 95 个模板按公开身份聚合后，仅有以下需要人工解释的一组：

| 身份 | 模板 | 明确运行日 | 结论 |
|---|---|---|---|
| あずさ1号／1M／新宿→松本 | `jr-east.azusa.1.base.2026-09-18` | 09-18、22、23、24、25、27、28 | 与另一模板无交集；松本 09:38 着 |
| あずさ1号／1M／新宿→松本 | `jr-east.azusa.1.selected-saturday-holiday.2026-09-19` | 09-19、20、21、26 | 与上一模板无交集；松本 09:43 着 |

`test_azusa_variants_partition_every_date_through_cutoff`、官方 URL/hash 固定测试和变体时刻测试均通过，证明这 11 天被不重不漏地分配，而不是用星期规律推断。

未编号但名称相同的往返模板也没有形成歧义：ニセコ号、フラノラベンダーエクスプレス及 WEST EXPRESS 銀河均由不同端点或方向区分。数据库中没有サンダーバード95号模板。

### 时刻与来源

canonical 中没有 `conflict` completeness 行；所有 stop time 的 `(trip_id, stop_sequence)` 唯一。来源固定测试还覆盖了跨午夜 separate day offsets、合并日期栏、节假日 override 及未印中间时刻保持为空等易误判场景。没有发现同一 canonical occurrence 的同站同字段多值。

需要保留两个边界条件：

1. `conflicts=0` 不扫描未进入 manifest 的候选，也不证明缺失字段正确。
2. `coverageComplete=false`；当前只有 1,577 个有日期证据的 occurrence。覆盖矩阵仍有 2,451 个 missing、45 个 partial/blocked 单元，六家 JR 完整覆盖为 0/6。

## 候选层审计

16 个候选 JSON 均可解析。候选保留在仓库中有三种不同含义，不能把“文件仍存在”当作 app 会重复载入：

| 候选范围 | 文件及处置 | 冲突结论 |
|---|---|---|
| 已审查、作为 normalizer 输入 | JR East 三模板、JR Central しなの1号、JR East ひたち26号、JR 北海道 2026-04-03 两模板、北海道夏季 12 模板、JR 九州指宿のたまて箱六模板、JR 四国いしづち 26 模板、WEST EXPRESS 銀河昼夜模板 | 与对应 canonical 身份重合是来源层→规范层的预期关系，不会双重装载；来源固定/golden 测试未发现同日或时刻分歧。超出 `as_of_date` 的日期按 manifest 截断，而不是改写为运行。 |
| 仍被阻塞的列车候选 | サンダーバード1号单日候选、1926/1934/1959 历史候选、历史边界假设 | 无同日 canonical 冲突。サンダーバード1号受来源条款和单日范围阻塞；历史候选缺明确日历、完整停站或历史站点身份。1926 年后续复核通过 `related_candidate_id` 明确关联原候选，时刻没有改写，不是第二个班次。 |
| 研究证据而非时刻实例 | route cooperation、reviewed route evidence、历史 source candidates | 不产生 trip occurrence。跨年份路线证据被明确禁止拼接，因而没有把 2020 年线路说明倒推到 2013 年班次。 |
| 未发布的合作候选 | `daily-cooperation-20260928.json` | 四个模板、两组各五个明确日期；唯一原始来源冲突为サンダーバード95号京都 09:22／09:23，已由五个日期特定列车页裁决为 09:22，并保留原冲突。其余日期组内两个衔接列车共享日期格有明确版面依据，不是日历复制错误。 |

候选与 canonical 的重复身份主要来自“候选是 normalizer 的经审查输入”这一仓库契约。运行时只读取 bundle 内 SQLite，不读取上述两个候选目录；搜索运行时代码未发现候选路径引用。

### サンダーバード95号五日期核验

原始公告是 [JR 西日本 2026 年夏季临时列车公告](https://www.westjr.co.jp/press/article/2026/05/15/items/260515_00_press_2026einjiunten.pdf)。公告第 7 页上方接续表和下方所需时间表写 09:23，第 8 页详细表写 09:22。没有按“二对一多数”选择，也没有按大阪 08:51、敦賀 10:20 回推。

逐日从京都站在来线特急时刻页点击“サンダーバード95号”进入列车级页面，结果如下：

| 日本服务日期 | 官方列车级页面 | 列车 | 京都 |
|---|---|---|---|
| 2026-07-18 | [train-timetable/382721?date=20260718](https://timetable.jr-odekake.net/train-timetable/382721?date=20260718) | 9095M | 09:20 着／09:22 发 |
| 2026-08-08 | [train-timetable/387131?date=20260808](https://timetable.jr-odekake.net/train-timetable/387131?date=20260808) | 9095M | 09:20 着／09:22 发 |
| 2026-08-09 | [train-timetable/387131?date=20260809](https://timetable.jr-odekake.net/train-timetable/387131?date=20260809) | 9095M | 09:20 着／09:22 发 |
| 2026-09-19 | [train-timetable/385171?date=20260919](https://timetable.jr-odekake.net/train-timetable/385171?date=20260919) | 9095M | 09:20 着／09:22 发 |
| 2026-09-20 | [train-timetable/385171?date=20260920](https://timetable.jr-odekake.net/train-timetable/385171?date=20260920) | 9095M | 09:20 着／09:22 发 |

月度页面 ID 并不稳定：7 月运行日为 `382721`，8 月为 `387131`，9 月为 `385171`。复核时应从 `https://timetable.jr-odekake.net/station-timetable/2784076002?date=YYYYMMDD` 的京都日期页进入；把 9 月 ID 直接换成 7 月日期会落到另一列车。上述五页不需要 cookie 才能读取。本次还检查了发布页，没有看到标题或正文标示“訂正”；所以证据结论限于“每个指定日期的官方列车时刻表支持 09:22”。

## App 可用性风险

| 风险 | 状态 | 用户影响 |
|---|---|---|
| 候选冲突污染生产查询 | PASS | 候选不在 manifest/SQLite，サンダーバード95号查询不会返回冲突值或重复 occurrence。 |
| 候选裁决状态一致性 | PASS | 模板状态、缺证清单、全局 gap 与汇总均区分“原 PDF 分歧保留”和“五日期 `resolved_clock=09:22`”；原始 stop observation 仍为 null，避免覆盖来源。 |
| 生产资源可读性与副本一致性 | PASS | SQLite `integrity_check=ok`、无外键错误；生成物与 RailCore 资源副本 SHA-256 均为 `3222ceee7d6539ab4970ca9897601b57c02b69673ec86c40d20c13b307027f6b`；snapshot alignment 通过。 |
| 日期身份歧义 | PASS | 生产 duplicate guard 通过；あずさ1号日历不重叠。 |
| サンダーバード95号可用性 | WARNING | 当前生产模板数为 0，app 不会提供这个日期班次。五日期 09:22 证据已进入候选审查链；完整停站、来源许可、线路证据等其他维度仍未完成，因此不得仅凭时刻裁决提升。内部列车番号 9095M 只由这五个日期特定页面支持。 |
| 全 JR 覆盖 | INCOMPLETE | 仅 95 个模板／1,577 个 occurrence；`coverageComplete=false`，不能把“无冲突”理解为完整 inventory。 |
| 精确班次直接写入路线编辑器 | INCOMPLETE | 路线审计 267 个 passenger leg 全部 unverified，solver 未运行；历史对齐 105 项 unverified、0 aligned、0 error，publishable route trip 为 0。详情查询可用不等于路线可应用。 |
| 真实 UI 交互 | PASS（限定范围） | 主任务三项UI测试通过：只读详情、日期变更保留手填内容、あずさ12站与来源入口。未覆盖全部班次及保存／地图应用流程。 |

## 验证

执行并核对：

```sh
python3 ios/tools/validate-train-timetable.py
python3 ios/tools/verify-train-timetable-artifact.py
python3 -m unittest -v \
  ios/tools/tests/test_east_next_batch_source_pinned.py \
  ios/tools/tests/test_ishizuchi_next_batch_source_pinned.py \
  ios/tools/tests/test_kyushu_next_batch_source_pinned.py \
  ios/tools/tests/test_reviewed_timetable_golden.py
python3 ios/tools/test_jreast_trip_parser.py
sqlite3 app/data/train-service-history/derived/train-service-timetable.sqlite \
  'PRAGMA integrity_check; PRAGMA foreign_key_check;'
cmp app/data/train-service-history/derived/train-service-timetable.sqlite \
  ios/RailKit/Sources/RailCore/Resources/train-service-timetable.sqlite
```

结果：canonical validator 通过 4,082 条记录；24 项来源固定/golden 测试及 3 项 JR East parser 测试通过；artifact `snapshotAligned=true`；SQLite integrity 为 `ok` 且无外键行；资源副本逐字节一致。五日期时刻核验后，主任务只在现有 daily candidate 中追加 `resolved_clock`、页面定位、访问时间和哈希；没有修改 normalized、SQLite 或运行时代码，也没有把候选提升到生产。

最终结果：生产冲突审计 **PASS**；候选冲突隔离与状态一致性 **PASS**；サンダーバード95号的五日期 09:22 时刻裁决 **PASS**；该候选的其他证据维度及许可为 **WARNING**；本轮三项真实UI为 **PASS（限定范围）**；全量覆盖与路线发布仍为 **INCOMPLETE**。
