# 2026-09-30 JR Kyushu: Midori 11 and Huis Ten Bosch coupling

## Exact-date source

The [official combined train detail for September 30](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0008/00085801.html?c=28283&ym=202609&d=30) displays みどり11号 (`4011M`) and ハウステンボス11号 (`6011H`) in separate train columns. Its note states that the ハウステンボス cars are coupled to みどり11号 between 博多 and 早岐. Both columns list 早岐 arrival at 10:07; the みどり column departs at 10:12 toward 佐世保, while the ハウステンボス column departs at 10:16 toward ハウステンボス. The station sequence used for the reciprocal `couples_with` relations ends at sequence 9, 早岐 arrival. The distinct departures are retained in their own trips.

This batch records only the independently printed みどり11号 column: ten passenger calls from 博多 08:39 to 佐世保 10:22. The ハウステンボス terminal row is absent from that column. The previously reviewed ハウステンボス11号 trip stays in its own output suffix; the script checks that its shared first eight calls, 早岐 station identity and arrival agree before emitting the relationship. The existing `midori` service identity is reused. The official page is registered under a new source ID for this Midori occurrence; no page bytes are stored.

## Output and checks

- Candidate: `app/data/train-service-history/candidates/jr-kyushu-midori11-20260930.json`.
- Script: `ios/tools/normalize-reviewed-kyushu-midori11-coupling-20260930.py`.
- Output suffix: `reviewed-kyushu-midori11-coupling-20260930` (1 trip, 10 stop times, 2 reciprocal coupling rows, 1 exact-day calendar, 1 source registry row, 0 new services).
- Focused command: `python3 ios/tools/normalize-reviewed-kyushu-midori11-coupling-20260930.py && python3 -m unittest ios.tools.tests.test_kyushu_midori11_coupling_20260930_source_pinned -v` passed, including four tests.

## Evidence boundary

The `毎日運転` label is not expanded into other dates. The official train detail does not establish ordered physical line IDs or operator segment boundaries, so neither is emitted. The source is retained for verification only; permission for automated extraction or redistribution was not established.
