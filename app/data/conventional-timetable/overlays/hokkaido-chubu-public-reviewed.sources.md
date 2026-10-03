# Hokkaido and Chubu public timetable evidence

The accompanying JSON is a reviewed partial overlay for `LineServiceCatalog`, against JP compact package version `2025.5.2`. It adds five numbered Meitetsu timetable excerpts and scoped class evidence for four exact physical rows. It does not replace the catalog, establish complete journeys, or report actual operation. Review date: 2026-10-03.

## Meitetsu scheduled excerpts

[Current timetable index](https://www.meitetsu.co.jp/train/timetable/) links the [weekday Nagoya main line PDF](https://www.meitetsu.co.jp/train/timetable/__icsFiles/afieldfile/2026/06/22/kai_20260314_NH_W1.pdf), effective 2026-03-14. Printed pages 3 and 4 were rendered and visually checked. Each record retains two timed calls from one numbered column:

| Number | Class | First call | Second call |
| --- | --- | --- | --- |
| 695 | 普通 | 東岡崎 dep 05:49 | 新安城 arr 05:59, dep 06:00 |
| 611 | 急行 | 豊橋 dep 05:53 | 東岡崎 arr/dep 06:19 |
| 645B | 準急 | 神宮前 arr 06:50, dep 06:51 | 金山 arr 06:53, dep 06:54 |
| 71 | 特急 | 豊橋 dep 06:12 | 東岡崎 arr 06:33, dep 06:34 |
| 77 | 快速特急 | 豊橋 dep 06:51 | 東岡崎 arr/dep 07:11 |

The index defines weekdays as Monday through Friday and expands 快特 to 快速特急. Train 645B changes to 普通 after 須ヶ口; its imported scope ends at 金山.

`serviceDates: ["2026-10-02"]` is a calendar derivation: that date is Friday and is absent from the [Cabinet Office 2026 holiday and substitute-holiday list](https://www8.cao.go.jp/chosei/shukujitsu/gaiyou.html). No additional dates are imported. The published weekday schedule establishes scheduled service; temporary alterations, cancellations and actual operation are unverified. Equal printed arrival/departure minutes are retained as printed, rather than inventing dwell times.

## JR Central class evidence

The [current Nagoya weekday departure PDF](https://railway.jr-central.co.jp/time-schedule/srch/_pdf/data/202603/tokaido_Nagoya_A_w_d.pdf) explicitly prints 普通, 区間快速, 快速, 新快速, 特別快速, ホームライナー and 特急. Evidence is anchored to compact 東海道線 名古屋 `005451`–岐阜 `004788`. The [official station timetable page](https://railway.jr-central.co.jp/time-schedule/search/) describes these as station-posted conventional timetables.

These are class facts, not dated trips: ordinary departure columns do not establish unique train numbers or matched arrival calls. No effective end was established, so both validity bounds remain null and the importer excludes these kinds from dated applicability. The JSON does not stitch similar departure times from different station boards into invented trains.

## JR Hokkaido class evidence

The [official Furano and Biei brochure](https://www.jrhokkaido.co.jp/travel/furanobiei/pdf/furanobiei2026.pdf), timetable page 1, identifies 普通列車 on 旭川–富良野 and 滝川–富良野. Its printed snapshot is 2026-04-01. Exact compact rows are 富良野線 (`000095`–`000137`) and 根室線-2 (`000117`–`000137`); this does not assign ordinary service to other 根室線 rows.

The brochure provides no numbered ordinary-train identity or October 2 calendar. No Hokkaido timed trip was imported and neither validity bound was inferred. The formerly indexed June 2026 multilingual Furano PDF returned the operator's 404 page and was excluded. Airport class facts already present in the catalog are not duplicated here.

## Identity and validation

Every station code, name, operator and line ID was matched directly to `app/public/rail/jp-2025.json`. JSON syntax, exact line/station membership and monotonic call times were checked with a small Python extraction. The overlay has four lines, fourteen service-kind facts and five trips. Each trip has precisely two timed calls; all omitted stops remain unknown. It is ready for the parent's unified importer gate; no Swift build, resource write, database mutation or full-timetable extraction was performed.
