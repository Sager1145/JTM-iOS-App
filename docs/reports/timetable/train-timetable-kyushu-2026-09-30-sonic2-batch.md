# 2026-09-30 JR Kyushu: Sonic 2

The [JR Kyushu exact-day ソニック2号 detail](https://www.jrkyushu-timetable.jp/sp/2610/0001/00013301.html?t=2874200e&d=20260930), reached from [大分駅 September 30 日豊本線 limited-express departures](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2874200e/), prints limited express `ソニック2号`, internal number `3002M`, and 17 passenger calls from 大分 05:12 to 博多 07:37. The expanded information lists `グリーン車指定席`, `普通車一部指定席`, and `毎日運転`. The seat labels are retained in the candidate as source snapshots; no vehicle formation or additional operating dates are inferred.

Printed platform numbers are 大分 1, 小倉 4, 折尾 3, and 博多 4. Blank platforms and unprinted terminal time sides remain null. The source spelling `柳ケ浦` resolves to the current station directory's `柳ヶ浦`. The existing `sonic` service identity is reused; this trip is distinct from the previously normalized ソニック1号.

## Output and validation

- Candidate: `app/data/train-service-history/candidates/jr-kyushu-sonic2-20260930.json`.
- Script: `ios/tools/normalize-reviewed-kyushu-sonic2-20260930.py`.
- Output suffix: `reviewed-kyushu-sonic2-20260930` (1 exact-day trip, 17 stop times, 1 source registry row, 1 one-day calendar, 0 new services).
- Focused test: `python3 -m unittest ios.tools.tests.test_kyushu_sonic2_20260930_source_pinned -v` passed 3 tests.

The timetable does not prove ordered physical line IDs or operating-company segment boundaries. Both remain `unknown`, with no trip-line or operator-segment rows. The official page is linked for verification without storing its bytes or claiming redistribution or automated-extraction permission. This suffix awaits shared integration; no global rebuild, SQLite output, manifest, or master report was changed.
