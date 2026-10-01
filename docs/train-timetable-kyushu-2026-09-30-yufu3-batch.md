# 2026-09-30 JR Kyushu: Yufu 3

## Source and reviewed occurrence

The [official date-qualified ゆふ3号 train detail](https://www.jrkyushu-timetable.jp/sp/2610/0016/00167201.html?t=2828302e&d=20260930), reached from the [博多駅 September 30 limited-express departure list](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2828302e/), prints train number `83D` and sixteen passenger calls from 博多 12:14 to 別府 15:46. The candidate records every published arrival/departure side and platform, leaving unprinted values null. The page spells 天ケ瀬; the current station directory's 天ヶ瀬 identity is `jp.n02.009457`, and the candidate keeps the official spelling.

The existing ゆふ1号 and ゆふ2号 trips have different public numbers and train numbers. This batch reuses their `yufu` service identity and creates only the September 30 occurrence. The official page is registered under `jr-kyushu-yufu3-20260930` for verification; no page bytes are stored.

## Output and validation

- Candidate: `app/data/train-service-history/candidates/jr-kyushu-yufu3-20260930.json`.
- Script: `ios/tools/normalize-reviewed-kyushu-yufu3-20260930.py`.
- Output suffix: `reviewed-kyushu-yufu3-20260930` (1 trip, 16 stop times, 1 source registry row, 1 one-day calendar, 0 new services).
- Focused test: `python3 -m unittest ios.tools.tests.test_kyushu_yufu3_20260930_source_pinned -v` passed 3 tests.

## Evidence still missing

The official page establishes passenger calls and clocks for September 30 but does not establish ordered physical line IDs or operator segment boundaries; neither is emitted. Its `毎日運転` label is not extended to other dates. No automated extraction or redistribution grant was identified, so the source remains verification only.
