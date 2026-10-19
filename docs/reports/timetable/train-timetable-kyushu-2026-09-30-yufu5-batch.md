# 2026-09-30 JR Kyushu: Yufu 5

## Source and reviewed occurrence

The [official date-qualified ゆふ5号 train detail](https://www.jrkyushu-timetable.jp/sp/2610/0016/00167301.html?t=2828302e&d=20260930), reached from the [博多駅 September 30 limited-express departure list](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2828302e/), prints train number `85D` and fifteen passenger calls from 博多 18:30 to 大分 21:43. 大分 is its printed destination; this train is not extended to 別府. The candidate retains every printed arrival/departure side and platform, with unprinted values null. The timetable spells 天ケ瀬 while the current station directory spells 天ヶ瀬; both resolve to `jp.n02.009457`.

The already normalized ゆふ1号 through 4号 have different train IDs. This batch reuses the existing `yufu` service identity and creates one exact-date trip. The official detail is registered under `jr-kyushu-yufu5-20260930` for verification; no page bytes are stored.

## Output and validation

- Candidate: `app/data/train-service-history/candidates/jr-kyushu-yufu5-20260930.json`.
- Script: `ios/tools/normalize-reviewed-kyushu-yufu5-20260930.py`.
- Output suffix: `reviewed-kyushu-yufu5-20260930` (1 trip, 15 stop times, 1 source registry row, 1 one-day calendar, 0 new services).
- Focused test: `python3 -m unittest ios.tools.tests.test_kyushu_yufu5_20260930_source_pinned -v` passed 3 tests.

## Evidence still missing

The official page establishes passenger calls and clocks for September 30 but does not establish ordered physical line IDs or operator segment boundaries; neither is emitted. Its `毎日運転` label is not extended to other dates. No automated extraction or redistribution grant was identified, so the source remains verification only.
