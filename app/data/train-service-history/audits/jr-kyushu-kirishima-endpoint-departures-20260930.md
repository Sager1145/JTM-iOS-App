# JR Kyushu きりしま — 2026-09-30 endpoint departure audit

Scope: the official date-selected [宮崎駅 southbound departure list](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2890301/) and [鹿児島中央駅 northbound departure list](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2900702/). Both pages displayed **2026年09月30日 (水)** when inspected. This counts trains departing these two endpoints; it does not establish a full inventory of trains that begin or end at intermediate stations.

| Direction | Departure | Public number | Official selected-date detail | Current candidate |
| --- | --- | --- | --- | --- |
| 宮崎 south | 05:46 | 1 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0006/00064501.html?t=2890301&d=20260930) | Prior `jr-kyushu-kirishima1-20260930` (6001M) |
| 宮崎 south | 07:07 | 3 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0006/00064701.html?t=2890301&d=20260930) | This batch (6003M) |
| 宮崎 south | 09:20 | 5 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0004/00047401.html?t=2890301&d=20260930) | This batch (6005M) |
| 宮崎 south | 10:20 | 7 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0006/00064801.html?t=2890301&d=20260930) | This batch (6007M) |
| 宮崎 south | 12:20 | 9 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0004/00047601.html?t=2890301&d=20260930) | This batch (6009M) |
| 宮崎 south | 14:20 | 11 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0006/00064901.html?t=2890301&d=20260930) | Missing |
| 宮崎 south | 16:20 | 13 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0004/00047801.html?t=2890301&d=20260930) | Missing |
| 宮崎 south | 17:20 | 15 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0006/00066201.html?t=2890301&d=20260930) | Missing |
| 宮崎 south | 19:00 | 17 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0008/00087101.html?t=2890301&d=20260930) | Missing |
| 鹿児島中央 north | 05:49 | 2 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0004/00047201.html?t=2900702&d=20260930) | Missing |
| 鹿児島中央 north | 07:40 | 4 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0004/00047301.html?t=2900702&d=20260930) | Missing |
| 鹿児島中央 north | 08:49 | 6 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0006/00065101.html?t=2900702&d=20260930) | Missing |
| 鹿児島中央 north | 10:00 | 8 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0004/00047501.html?t=2900702&d=20260930) | Missing |
| 鹿児島中央 north | 11:50 | 10 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0006/00065201.html?t=2900702&d=20260930) | Missing |
| 鹿児島中央 north | 13:57 | 12 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0004/00047701.html?t=2900702&d=20260930) | Missing |
| 鹿児島中央 north | 16:18 | 14 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0006/00065301.html?t=2900702&d=20260930) | Missing |
| 鹿児島中央 north | 18:40 | 16 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0006/00066401.html?t=2900702&d=20260930) | Missing |
| 鹿児島中央 north | 20:20 | 18 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0008/00088101.html?t=2900702&d=20260930) | Missing |
| 鹿児島中央 north | 22:17 | 82 | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0006/00065001.html?t=2900702&d=20260930) | Missing |

These two endpoint lists contain **19** dated departure columns: 9 southbound and 10 northbound. At assignment start the derived database had only 1号. The new 3/5/7/9 source-pinned candidate raises reviewed candidate coverage to **5/19**, leaving **14** specific columns listed as missing above. Internal train numbers for the other 14 columns have not been verified and are intentionally absent from this audit.

The four new details print 41 passenger calls in total. Every printed clock side and platform is retained; 3/5 are marked `毎日運転`, while 7/9 explicitly note suspension on several November dates, none of which is the selected 2026-09-30 occurrence. All four print `グリーン車指定席` and `普通車一部指定席`. The source pages do not establish consist length, vehicle series or dated ordered physical line segments for these trips.
