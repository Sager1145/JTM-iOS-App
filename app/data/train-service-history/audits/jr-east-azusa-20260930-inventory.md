# JR East あずさ, 2026-09-30: official inventory and next batch

The official [weekday down timetable](https://timetables.jreast.co.jp/2610/timetable-v/223d1.html) and [weekday up timetable](https://timetables.jreast.co.jp/2610/timetable-v/223u1.html) give the public-number inventory below. These are weekday table columns, not a claim that every train marked `◆` ran on September 30. A train becomes date-confirmed here only when its individual page marks September 30 `td.ok`.

| Direction | Weekday table public numbers | Table status |
| --- | --- | --- |
| Down | 1, 3, 5, 9, 13, 17, 21, 25, 29, 33, 37, 41, 45, 49, 53, 55 | 全日 or 平日 |
| Down extras | 83, 91, 93 | ◆; date unresolved |
| Up | 4, 8, 12, 16, 18, 22, 26, 30, 34, 38, 42, 44, 46, 50, 54, 60 | 平日 |

Thus the official weekday public-number envelope is **1–60**, with gaps. The three down extras sit outside that envelope and require their own operating-day review. The table does not prove a closed September 30 set; notably an indexed [9号 page](https://timetables.jreast.co.jp/2610/train/050/054671.html) describes a weekend variant although the weekday grid also lists 9号. The correct weekday date-selected page remains to be found before staging 9号.

This batch stages four individually confirmed down trains:

| Public no. | Internal no. | Official date-selected page | Printed calls | Notes |
| --- | --- | --- | ---: | --- |
| 3 | 5003M | [千葉–松本](https://timetables.jreast.co.jp/2610/train/050/054761.html) | 20 | 2103M 富士回遊 coupled 千葉–大月; only the あずさ column is staged |
| 5 | 5M | [新宿–白馬](https://timetables.jreast.co.jp/2610/train/110/111361.html) | 14 | Printed arrival/departure and platforms retained |
| 13 | 13M | [新宿–松本](https://timetables.jreast.co.jp/2610/train/050/054701.html) | 10 | Printed arrival/departure and platforms retained |
| 17 | 17M | [新宿–松本](https://timetables.jreast.co.jp/2610/train/050/054721.html) | 11 | Printed arrival/departure and platforms retained |

Each selected page marks September 30 `td.ok` and prints `座席未指定券`, `グリーン車指定席`, and `普通車全車指定席`. The normalized planned formation records only the seat and green-car claims. Car count, vehicle series, ordered physical lines, and operator segments remain open. The batch is exact-day, with calendar exceptions only for September 30.

The first batch materialized 1, 3, 5, 13, and 17 on September 30. The rest of the weekday columns were pending individual page checks at that point.

## Second reviewed batch: 8, 12, 21, 29

All four selected pages mark September 30 `td.ok`. All printed stop arrivals, departures, platforms, train numbers, and equipment are held in the [candidate](../candidates/jr-east-azusa8-12-21-29-20260930.json) and staged exact-day records.

| Public no. | Internal no. | Official date-selected page | Printed calls |
| --- | --- | --- | ---: |
| 8 | 5008M | [松本–東京](https://timetables.jreast.co.jp/2610/train/075/076231.html) | 10 |
| 12 | 5012M | [松本–東京](https://timetables.jreast.co.jp/2610/train/075/076251.html) | 14 |
| 21 | 21M | [新宿–松本](https://timetables.jreast.co.jp/2610/train/050/054681.html) | 10 |
| 29 | 29M | [新宿–松本](https://timetables.jreast.co.jp/2610/train/025/025711.html) | 10 |

The [indexed 9号 page](https://timetables.jreast.co.jp/2610/train/050/054671.html) marks September 30 `td.none` and prints a weekend timetable; it is excluded. A [29号 weekend variant](https://timetables.jreast.co.jp/2610/train/025/025721.html) is likewise excluded in favor of the date-confirmed weekday page above. The 25号 individual page has not yet been pinned, so 25 remains pending despite its `全日` weekday-grid label. The remaining weekday columns and all `◆` columns still require individual checks. After the second batch, the source dataset materializes **1, 3, 5, 8, 12, 13, 17, 21, 29** on September 30; this is not a closed inventory.

Shared rebuild output, SQLite, and the main report were not changed by either batch.

## Third reviewed batch: 26, 33, 44

The individual [26号 weekday page](https://timetables.jreast.co.jp/2610/train/060/063761.html), [33号 page](https://timetables.jreast.co.jp/2610/train/020/020261.html), and [44号 weekday page](https://timetables.jreast.co.jp/2610/train/060/063781.html) each mark September 30 `td.ok` and print the internal numbers 26M, 33M, and 44M. This batch stages all 38 printed あずさ-column calls, including every printed platform and the three printed seat-equipment items. The 44号 page additionally prints `大月－新宿は2144Mを併結`, which is held as a source-pinned fact and trip note. It does not supply a car count or vehicle series.

The published [44号 weekend variant](https://timetables.jreast.co.jp/2610/train/060/063782.html) and [26号 weekend variant](https://timetables.jreast.co.jp/2610/train/060/063771.html) are not used. A located [4号 weekend page](https://timetables.jreast.co.jp/2610/train/060/063751.html) marks September 30 `td.none`; its weekday variant is pending. The 25号 individual page is still unlocated despite its `全日` weekday-grid entry. Neither train is staged from a mismatched variant or from the grid's partial times.

After this batch, the source dataset materializes **1, 3, 5, 8, 12, 13, 17, 21, 26, 29, 33, 44** on September 30. This remains an open inventory. Shared rebuild output, SQLite, manifest, schema, and the main report were not changed by this batch.
