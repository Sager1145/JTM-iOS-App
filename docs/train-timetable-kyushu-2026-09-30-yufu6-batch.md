# 2026-09-30 JR Kyushu: Yufu 6

## Source and reviewed occurrence

The [JR Kyushu exact-day ゆふ6号 detail](https://www.jrkyushu-timetable.jp/sp/2610/0016/00167601.html?t=2880501e&d=20260930), reached from the [別府駅 September 30 日豊本線 limited-express departures](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2880501e/), prints limited express `ゆふ6号`, internal number `86D`, and fourteen passenger calls from 別府 18:09 to 博多 21:34. The expanded train information prints `普通車一部指定席` and `毎日運転`. The candidate records the seat description as a source snapshot; it does not infer a vehicle formation, car count, or unrestricted recurrence from those labels.

Every printed arrival/departure side and platform is retained. The page prints platforms 大分 7, 久留米 4, 鳥栖 1, and 博多 2; blank platforms and the unprinted terminal time sides remain null. Its `天ケ瀬` spelling is reconciled to the current directory's `天ヶ瀬` (`jp.n02.009457`). The existing `yufu` service identity is reused.

## Output and validation

- Candidate: `app/data/train-service-history/candidates/jr-kyushu-yufu6-20260930.json`.
- Script: `ios/tools/normalize-reviewed-kyushu-yufu6-20260930.py`.
- Output suffix: `reviewed-kyushu-yufu6-20260930` (1 exact-day trip, 14 stop times, 1 source registry row, 1 one-day calendar, 0 new services).
- Focused test: `python3 -m unittest ios.tools.tests.test_kyushu_yufu6_20260930_source_pinned -v` passed 3 tests.

The official detail documents the planned 2026-09-30 passenger timetable. It does not establish ordered physical line IDs or operating-company segment boundaries; both remain `unknown`, and no trip-line or operator-segment rows are emitted. The source is linked for verification without storing page bytes or claiming redistribution or automated-extraction permission. This suffix awaits shared integration; no global rebuild, SQLite output, manifest, or master report was changed.
