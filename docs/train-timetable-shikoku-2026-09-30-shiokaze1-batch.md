# 2026-09-30 しおかぜ1号 reviewed candidate

The [date-qualified 岡山駅 timetable](https://timetable.jr-odekake.net/station-timetable/3449041001?date=20260930) links its 07:22 departure to the [official train detail](https://timetable.jr-odekake.net/train-timetable/18541?date=20260930). The latter identifies 特急しおかぜ1号 as 1M, 岡山 07:22 to 松山 10:06, every day, with ordinary class partly reserved. Its first train column provides 15 passenger calls, preserved in `jr-shikoku-shiokaze1-20260930.json`. Passing rows marked レ are excluded; blank arrival, departure, and platform cells remain null.

The page also identifies a coupling with 1001M (いしづち1号) from 宇多津 to 松山. This is retained in the candidate equipment note. The coupled counterpart and a machine-readable trip relation are outside this one-train seed. Physical line identities and ordered operator segments remain unknown.

`ios/tools/normalize-reviewed-shikoku-shiokaze1-20260930.py` writes only the dedicated `reviewed-shikoku-shiokaze1-20260930` registry and normalized seed files. It does not modify the shared manifest, database, or master report. The source registry records verification use only and no automated extraction permission.
