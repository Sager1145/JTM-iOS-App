# 2026-09-30 JR Kyushu: Huis Ten Bosch 11

## Source and reviewed occurrence

The [official date-qualified combined train detail](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0008/00085801.html?c=28283&ym=202609&d=30) prints separate みどり11号 (`4011M`) and ハウステンボス11号 (`6011H`) columns. Its note says they are coupled from 博多 to 早岐. This batch records only the ハウステンボス11号 column: ten passenger calls from 博多 08:39 to ハウステンボス 10:22. At 早岐, that column prints 10:07 arrival and 10:16 departure. The 佐世保 row belongs to the みどり column; the ハウステンボス column marks it `||`, so it is excluded.

The exact-date source ID `jr-kyushu-huis-ten-bosch11-20260930` was already present in `source-registry-discovery-kyushu-2026.jsonl`. The new candidate pins every published passenger arrival/departure side and printed platform, leaving absent values null. No previously normalized trip with this ID was found.

## Output and validation

- Candidate: `app/data/train-service-history/candidates/jr-kyushu-huis-ten-bosch11-20260930.json`.
- Script: `ios/tools/normalize-reviewed-kyushu-huis-ten-bosch11-20260930.py`.
- Output suffix: `reviewed-kyushu-huis-ten-bosch11-20260930` (1 trip, 10 stop times, 1 new service, 1 one-day calendar). The suffix's source-registry file is empty because the source was already registered.
- Focused check: `python3 -m unittest ios.tools.tests.test_kyushu_huis_ten_bosch11_20260930_source_pinned -v` passed 3 tests.

## Evidence still missing

The page establishes the train's published stops and clocks for September 30, but does not establish dated ordered physical line IDs or operator segment boundaries. The batch therefore emits no trip-line or trip-operator-segment rows. Its `毎日運転` label is not expanded into a recurring calendar; only the exact September 30 occurrence is recorded. The page is verification evidence only; no grant for automated extraction or redistribution of its content was identified.
