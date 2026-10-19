# 2026-09-30 JR Kyushu: Kasasagi 101 and Yufu 1

## Sources and scope

This batch records two distinct exact-date train occurrences from the JR Kyushu October 2026 timetable's September 30 train-detail pages:

| Trip | Official detail | Passenger calls | Published endpoints |
| --- | --- | ---: | --- |
| `jr-kyushu.kasasagi.101.2026-09-30` | [かささぎ101号, 1001M](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0019/00194101.html?c=28283&ym=202609&d=30) | 15 | 門司港 06:40 → 肥前鹿島 08:58 |
| `jr-kyushu.yufu.1.2026-09-30` | [ゆふ1号, 81D](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0016/00167101.html?c=28283&ym=202609&d=30) | 15 | 博多 07:43 → 別府 11:04 |

Both source IDs were already present in `source-registry-discovery-kyushu-2026.jsonl`. The candidate files pin the train numbers, each published passenger call, every printed arrival and departure side, and only the platform numbers printed in the official table. A blank side or platform remains null. The official `天ケ瀬` spelling is mapped to the current station directory's `天ヶ瀬` identity (`jp.n02.009457`); the candidate retains the official spelling.

The separate, already normalized かささぎ103号 occurrence is not duplicated. The shared `kasasagi` service identity is reused; this batch introduces the `yufu` service identity. `ゆふ` is kept distinct from `ゆふいんの森`.

## Output and validation

- Script: `ios/tools/normalize-reviewed-kyushu-kasasagi101-yufu1-20260930.py`.
- Candidate files: `jr-kyushu-kasasagi101-20260930.json` and `jr-kyushu-yufu1-20260930.json`.
- Output suffix: `reviewed-kyushu-kasasagi101-yufu1-20260930` (2 trips, 30 stop times, 1 new service, 2 one-day calendars). Its source-registry file is empty because the sources are already registered.
- Focused test: `python3 -m unittest ios.tools.tests.test_kyushu_kasasagi101_yufu1_20260930_source_pinned -v` passed 3 tests.

## Evidence still missing

The official train details establish displayed passenger calls and clocks for the September 30 occurrence. They do not establish dated ordered physical line identities or operator segment boundaries, so the batch emits no trip-line or trip-operator-segment rows. The daily-operation label is not promoted to other dates; only a September 30 calendar exception is emitted. The publisher's reuse terms do not grant automated extraction or redistribution of page contents, so the page is linked as verification evidence and no source page is stored.
