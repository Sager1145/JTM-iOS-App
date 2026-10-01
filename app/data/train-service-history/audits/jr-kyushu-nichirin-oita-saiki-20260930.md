# JR Kyushu にちりん — 2026-09-30 大分・佐伯 corridor audit

Scope: all **ordinary にちりん** shown on the selected-date [大分 southbound departure list](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2874201/) and [佐伯 northbound departure list](https://www.jrkyushu-timetable.jp/cgi-bin/sp/sp-tt_dep.cgi/2876000/). Both station pages displayed 2026年09月30日 (水) when inspected. `にちりんシーガイア` 5 and 14 are separately named services and excluded. This is a corridor inventory, not a claim about any train operating only outside 大分–佐伯.

| Direction | Public number / train number | Official selected-date train detail | Candidate state |
| --- | --- | --- | --- |
| North | 102 / 5092M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0011/00117001.html?t=2876000&d=20260930) | Staged in `kyushu-nichirin102-20260930` |
| North | 2 / 5002M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0007/00075401.html?t=2876000&d=20260930) | Prior candidate `jr-kyushu-nichirin2-20260930` |
| North | 4 / 5004M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0016/00165901.html?t=2876000&d=20260930) | Prior `kyushu-nichirin4-6-8-20260930` batch |
| North | 6 / 5006M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0031/00310201.html?t=2876000&d=20260930) | Prior `kyushu-nichirin4-6-8-20260930` batch |
| North | 8 / 5008M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0008/00087401.html?t=2876000&d=20260930) | Prior `kyushu-nichirin4-6-8-20260930` batch |
| North | 10 / 5010M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0019/00193701.html?t=2876000&d=20260930) | Staged in `kyushu-nichirin10-12-16-20260930` |
| North | 12 / 5012M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0008/00087501.html?t=2876000&d=20260930) | Staged in `kyushu-nichirin10-12-16-20260930` |
| North | 16 / 5016M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0019/00193801.html?t=2876000&d=20260930) | Staged in `kyushu-nichirin10-12-16-20260930` |
| South | 1 / 5001M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0006/00068601.html?t=2874201&d=20260930) | Staged in `kyushu-nichirin1-3-7-9-20260930` |
| South | 3 / 5003M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0008/00087201.html?t=2874201&d=20260930) | Staged in `kyushu-nichirin1-3-7-9-20260930` |
| South | 7 / 5007M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0019/00193201.html?t=2874201&d=20260930) | Staged in `kyushu-nichirin1-3-7-9-20260930` |
| South | 9 / 5009M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0009/00094101.html?t=2874201&d=20260930) | Staged in `kyushu-nichirin1-3-7-9-20260930` |
| South | 11 / 5011M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0009/00094201.html?t=2874201&d=20260930) | Staged in `kyushu-nichirin11-13-15-17-20260930` |
| South | 13 / 5013M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0019/00193501.html?t=2874201&d=20260930) | Staged in `kyushu-nichirin11-13-15-17-20260930` |
| South | 15 / 5015M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0019/00193301.html?t=2874201&d=20260930) | Staged in `kyushu-nichirin11-13-15-17-20260930` |
| South | 17 / 5017M | [JR Kyushu](https://www.jrkyushu-timetable.jp/sp/2610/0019/00193601.html?t=2874201&d=20260930) | Staged in `kyushu-nichirin11-13-15-17-20260930` |

The selected-date station lists show **8 northbound and 8 southbound** ordinary にちりん columns through this corridor. The reviewed normalized seed slices now contain **all 16 unique train numbers** and source-pinned complete passenger stop, printed clock-side, platform, operating-day and seat-category facts for every southbound train. This closes the selected-date *candidate inventory* through 大分–佐伯; it does not assert that a shared SQLite rebuild has already incorporated every slice or that other にちりん services outside this corridor have been inventoried.

For the newly staged columns, source-pinned tests check every printed passenger call and time side, printed platforms, operating-day text, train number and seat-category text. Consist lengths, individual car allocation, dated line segments and operator boundaries remain unknown in these official train-detail pages and are recorded as such in the research queue.
