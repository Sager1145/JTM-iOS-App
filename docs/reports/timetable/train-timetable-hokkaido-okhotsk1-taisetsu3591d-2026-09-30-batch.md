# JR 北海道下行逐日核验：オホーツク 1／大雪 3591D（2026-09-30）

## 官方日期与列车列

[JR 北海道 2026 年 9 月 30 日下行时刻表](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=110)的选择器显示 `2026年9月30日(水)`，页脚注明依据《JR時刻表》令和 8 年 10 月号。本批只录入该页第二列 `71D / オホーツク 1` 与第九列 `3591D / 大雪`，不按“毎日”字样推广到相邻日期。已有 9 月 30 日上行 `72D / オホーツク 2` 和 `3592D / 大雪` 是不同列车，未重复入库或修改。

| Trip ID | 区间 | 乘客停站 | 始发／终到 | 站台 |
|---|---|---:|---|---|
| `jr-hokkaido.okhotsk.1.exact-2026-09-30` | 札幌→網走 | 17 | 06:52／12:17 | 札幌 `(10)` |
| `jr-hokkaido.taisetsu.3591d.exact-2026-09-30` | 旭川→網走 | 11 | 12:38／16:32 | 本列无印出的站台 |

`71D` 在旭川印出 `08:28 着／08:31 発`；其他中途站只印发车时刻，到达侧保留 `null`。`3591D` 的公开号格为空，保留 `null`，起点旭川的站台格也为空。页标题将大雪标为 `［特快］`，规范服务类别为 `special_rapid`。所有 28 个乘客停站至少有本列印出的到达或发车时刻。未将旁列普通列车的时刻或站台移入这两列。

候选文件为 `app/data/train-service-history/candidates/jr-hokkaido-okhotsk1-taisetsu3591d-20260930.json`，转换器为 `ios/tools/normalize-reviewed-hokkaido-okhotsk1-taisetsu3591d-20260930.py`。转换器只生成后缀为 `hokkaido-okhotsk1-taisetsu3591d-20260930` 的来源及规范文件，并引用已有的オホーツク、大雪服务身份与站组，不生成重复服务或站组。来源登记用途为核验，未声称取得再分发许可。

## 验证与缺口

`python3 -m unittest ios/tools/tests/test_hokkaido_okhotsk1_taisetsu3591d_20260930_source_pinned.py -v` 的 3 项测试通过，覆盖两列逐站时刻、札幌站台、空白公开号、官方链接、日期边界和未知分段。`python3 ios/tools/validate-train-timetable.py` 通过；执行时校验 10,372 条当前规范记录，其中包括并行工作产生的记录。本批新增 2 趟、28 条乘客停站，没有修改共享 rebuild、SQLite 或其他批次。

未印出的中途到达侧、`3591D` 的起点站台，以及两班的逐日有序物理线路 ID 与运营者分段仍待证实。官方页的再分发授权也未确证，均列入研究队列。
