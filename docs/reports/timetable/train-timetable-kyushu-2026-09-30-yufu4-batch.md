# 2026-09-30 JR Kyushu: Yufu 4

## Source and reviewed occurrence

The [official date-qualified ゆふ4号 train detail](https://www.jrkyushu-timetable.jp/sp/2610/0016/00167501.html?t=2881400&d=20260930), reached from the [由布院駅 September 30 departure list](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2881400/), prints train number `84D` and seventeen passenger calls from 別府 13:13 to 博多 16:31. The candidate records each printed arrival/departure side and platform; unprinted values remain null. The page spells 天ケ瀬 while the current station directory spells 天ヶ瀬. Both resolve to `jp.n02.009457`, with the official spelling retained in the candidate.

The already normalized ゆふ1号, 2号 and 3号 have different train IDs. This batch reuses the existing `yufu` service identity and creates one exact-date trip. Its official detail is registered under `jr-kyushu-yufu4-20260930` for verification; no page bytes are stored.

## Output and validation

- Candidate: `app/data/train-service-history/candidates/jr-kyushu-yufu4-20260930.json`.
- Script: `ios/tools/normalize-reviewed-kyushu-yufu4-20260930.py`.
- Output suffix: `reviewed-kyushu-yufu4-20260930` (1 trip, 17 stop times, 1 source registry row, 1 one-day calendar, 0 new services).
- Focused test: `python3 -m unittest ios.tools.tests.test_kyushu_yufu4_20260930_source_pinned -v` passed 3 tests.

## Evidence still missing

The official page establishes passenger calls and clocks for September 30 but does not establish ordered physical line IDs or operator segment boundaries; neither is emitted. Its `毎日運転` label is not extended to other dates. No automated extraction or redistribution grant was identified, so the source remains verification only.
