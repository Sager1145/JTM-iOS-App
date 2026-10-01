# 2026-09-30 JR Kyushu: Yufu 2

## Source and reviewed occurrence

The [official date-qualified ゆふ2号 train detail](https://www.jrkyushu-timetable.jp/sp/2610/0016/00167401.html?t=2881400&d=20260930), reached from the [由布院駅 September 30 departure list](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2881400/), prints the train family, number `82D`, and fifteen passenger calls from 大分 08:20 to 博多 11:20. The candidate pins every published arrival/departure side and platform; unprinted values remain null. The page spells 天ケ瀬 while the current station directory spells 天ヶ瀬. Both resolve to `jp.n02.009457`, with the official spelling retained in the candidate.

The previously normalized ゆふ1号 has a different train ID and direction. This batch reuses the existing `yufu` service identity and creates one new exact-date trip. The official page is registered under `jr-kyushu-yufu2-20260930` for verification; no page bytes are stored.

## Output and validation

- Candidate: `app/data/train-service-history/candidates/jr-kyushu-yufu2-20260930.json`.
- Script: `ios/tools/normalize-reviewed-kyushu-yufu2-20260930.py`.
- Output suffix: `reviewed-kyushu-yufu2-20260930` (1 trip, 15 stop times, 1 source registry row, 1 one-day calendar, 0 new services).
- Focused test: `python3 -m unittest ios.tools.tests.test_kyushu_yufu2_20260930_source_pinned -v` passed 3 tests.

The [佐世保駅 September 30 outbound list](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2849000/) did not show みどり12号 in its inspected morning departures. The [ハウステンボス駅 outbound list](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2854800/) did not show ハウステンボス12号 in its inspected morning or afternoon departures. Neither candidate was promoted on that evidence.

## Evidence still missing

The train-detail page establishes passenger calls and clocks for September 30 but does not establish ordered physical line IDs or operator segment boundaries, so neither is emitted. The `毎日運転` label is not extended to other dates; only the exact September 30 occurrence is recorded. No automated extraction or redistribution grant was identified, so the source is verification only.
