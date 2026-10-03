# Offline line service catalog

`ios/RailKit/Sources/RailCore/Resources/line-service-catalog.json` inventories all 657 physical line IDs in the shipped JP compact package. It records **train service classes** (普通, 快速, 新快速, 特急, etc.), not vehicle series. The bundled artifact contains 51 lines with partial researched evidence and 606 explicit unknowns, plus 16 dated train-number sections with 62 verified calls. Partial coverage never asserts that the list is exhaustive.

Rebuild: `python3 ios/tools/build-line-service-catalog.py`. Verify derivation: append `--check`. The builder opens `train-service-timetable.sqlite` using SQLite `mode=ro`; it never modifies the timetable database. `LineServiceCatalog(data:)` is the executable Swift JSON importer and validates identities, source URLs, dates and chronological stop times. `loadBundled()` uses that same importer.

## Sources reviewed on 2026-10-02

- [JR West 2026 Kansai timetable revision](https://www.westjr.co.jp/press/article/items/251212_00_press_daiyakaisei_kinkiarea_1.pdf), published 2025-12-12, effective 2026-03-14. Pages 3, 9–10 identify local/rapid/new rapid service and the marketed 琵琶湖/JR京都/JR神戸 sections. New station 手柄山平和公園 is served by all three classes. Catalog evidence ends exclusively at 2026-10-03 because a later revision is known. This document's advance timetable proposals are **not** imported as confirmed scheduled trips.
- [JR West station timetable](https://timetable.jr-odekake.net/station-timetable/2789011001?date=20260807) confirms 普通 on a reviewed JR京都 section and 快速/新快速 labels. Its evidence is restricted to that observed service day, not extrapolated to other dates.
- [JR West JR A/JR B stop guide](https://www.jr-odekake.net/station/pdf/teisya_07.pdf) identifies 琵琶湖/北陸/湖西 service classes. No published effective date was established, so these are undated class evidence and excluded from queries for a specific service date. A current route diagram does not establish a historical timetable. The 2026 spring revision removes 北陸線 temporary rapid trains; the seed does not add 快速 to that line.
- [Toei Asakusa weekday northbound timetable](https://www.kotsu.metro.tokyo.jp/subway/timetable/asakusa/A18ND.html) confirms 普通, アクセス特急 and エアポート快特 labels. アクセス特急 stops at every station within the subway portion; labels/stopping rules change across operator boundaries.
- [Toei Asakusa weekend southbound timetable](https://www.kotsu.metro.tokyo.jp/subway/timetable/asakusa/A18SH.html) confirms 快特 with all stops in the subway portion. Toei evidence is restricted to 浅草線; this catalog does not infer that every connected 京成/京急 line has these classes.
- Existing reviewed timetable facts: import only high-confidence `current_n02` `trip_line_segments` with exact compact IDs, their original HTTPS source locator, and the enclosing timetable version's validity interval. Historical and unresolved line references are excluded. A line segment indicates class evidence somewhere within that section and version; calendars can limit the days on which particular trains run. This class catalog is not a substitute for the existing calendar-aware database.

## Small timetable excerpts

The initial import includes two manually researched excerpts of **published scheduled** services for **2026-10-04 only**:

- [普通 102C](https://timetable.jr-odekake.net/train-timetable/173421?date=20261004): 大阪 arrival 06:10/departure 06:12; 新大阪 arrival 06:15/departure 06:16.
- [新快速 3408M](https://timetable.jr-odekake.net/train-timetable/173041?date=20261004): 大阪 arrival 07:28/departure 07:30; 新大阪 07:33/07:34; 高槻 07:45/07:46; 京都 07:59/08:00.

These are short factual excerpts, not complete timetable reproductions or reports of actual operation. The source carries timetable reproduction restrictions; bulk automated extraction and a full source timetable copy are not part of this importer. Omitted stops are unknown, never pass-through symbols. These entries cannot establish a complete itinerary. Other chats own wider official timetable research.

## Version 1 JSON contract

Top level: `schemaVersion` (1), `inventoryVersion` (compact package version), `observedOn` (ISO date), `lines`, `trips`.

A line contains `lineID`, `operatorName`, `lineName`, `aliases`, `coverage` (`partial` or `unknown`), `kinds`, and `note`. Empty kinds require unknown coverage. Service kinds contain stable evidence ID, `displayName`, `trainType`, `sourceURL`, nullable `validFrom`/exclusive `validUntil`, `scope`, optional physical section station codes and `observedOn`. Multiple evidence periods may share a train type; the editor should deduplicate labels while retaining provenance. A kind with no established complete date interval is discoverable in an undated picker but is excluded from dated applicability.

A trip contains unique `id`, `trainNumber`, `trainType`, `operatorName`, exact physical `lineIDs`, explicit `serviceDates`, `sourceURL`, `coverage`, `note`, and ordered `stops`. Each stop stores exact compact `stationCode`, a display `stationName`, and nullable arrival/departure seconds from Japanese service-day midnight. At least one time is required per stop; times must be chronological, including arrival before departure at a station. Values above 86400 preserve midnight crossings. No weekday/holiday extrapolation is performed: `timetableTrips(lineID:serviceDate:trainType:)` matches only explicit researched dates.

## Identity and scope limits

Compact `東海道線` includes the marketed 琵琶湖線/JR京都線/JR神戸線; compact `山陽線` includes a much longer physical corridor than JR神戸線. Evidence carries section scope and station boundaries so a rapid service in Kansai is not asserted for the whole western 山陽 corridor. Branches such as 東海道線-2 (大阪–福島) are not assigned 京都新快速 merely because the physical line name matches.

JK/JS and other operating corridors crossing overlapping physical lines require a separate reviewed corridor identity layer. [JR East's official Tokyo map](https://www.jreast.co.jp/map/pdf/map_tokyo.pdf) and [the 2026 Keikyu/Toei/Keisei/Hokuso joint notice](https://www.kotsu.metro.tokyo.jp/pickup_information/news/pdf/2026/sub_i_2026030212434_h_01.pdf) provide corridor evidence; this catalog alone does not prove a particular single-seat service, calendar or full stop chain across those lines.

## Licensed ODPT offline expansion pipeline

The [official ODPT developer portal](https://developer.odpt.org/) and [ODPT usage instructions](https://www.odpt.org/) require developer registration and compliance with the provider's data conditions. No registered API credential is available in this task. No account was registered, credential searched for, or private API called; **no ODPT timetable coverage is claimed in the bundled artifact**.

`ios/tools/import-odpt-line-services.py` accepts an offline licensed `odpt:TrainTimetable` JSON array and explicit reviewer-authored identity/calendar mappings. It rejects unmapped or ambiguous identities, operator mismatches, stations outside mapped physical lines, missing types, invalid times, duplicate trips and dates outside the effective interval. Train number suffixes never establish service type.

Required mapping JSON objects:

- `railways`: ODPT railway ID → `{ "lineIDs": ["exact compact IDs"], "operatorName": "exact compact operator", "scope": "reviewed physical section" }`.
- `operators`: ODPT operator ID → `{ "operatorName": "exact compact operator" }`.
- `stations`: ODPT station ID → `{ "stationCode": "exact compact code", "stationName": "reviewed display name" }`.
- `trainTypes`: ODPT train-type ID → `{ "displayName": "official class", "trainType": "official class" }`.
- `calendars`: ODPT calendar ID → `{ "serviceDates": ["YYYY-MM-DD"] }`. A weekday calendar label alone is insufficient; operating days, holidays and exceptions must be researched and enumerated.

Required provenance JSON: HTTPS `sourceURL`, `observedOn`, `validFrom`, exclusive `validUntil`. Example invocation (paths refer to locally supplied licensed/reviewed files):

```sh
python3 ios/tools/import-odpt-line-services.py \
  --export /path/to/licensed-odpt-export.json \
  --mapping /path/to/reviewed-identity-map.json \
  --provenance /path/to/reviewed-source-period.json \
  --output /path/to/reviewed-overlay.json
python3 ios/tools/build-line-service-catalog.py \
  --reviewed-input /path/to/reviewed-overlay.json
```

The builder accepts repeatable `--reviewed-input` overlays, verifies the compact inventory version and rejects conflicting identities or malformed normalized times before writing the bundled artifact. Unknown lines outside the imported scope remain unknown. Imported row IDs remain `owl:sameAs` identities; `previousTrainIDs`/`nextTrainIDs` preserve original ODPT references even when the referenced trip belongs to another operator or is missing from this export. `sourceOperatorID`, `sourceRailwayID`, `sourceTrainTypeID`, and `sourceCalendarID` retain the original explicit source identities. These references permit later through-service reconciliation; a reference alone does not establish a complete operating-day chain.

Arrival/departure calls become ordered seconds from Japanese service-day midnight. `00:04` after `23:58` becomes 86640; already extended `24:04` is accepted. The importer rejects a second midnight crossing. It imports published calls, not guessed pass-through stations or actual-operation events. `LineServiceCatalog(data:)` accepts normalized overlays directly for inspection, and optional ODPT fields are backward compatible with the original bundled JSON.

`ios/tools/test_import_odpt_line_services.py` uses synthetic identities and dates solely to test the ingestion path. Those fixtures are never bundled or represented as verified operator facts. Run when the performance sampling window is clear:

```sh
python3 -m unittest discover -s ios/tools -p 'test_import_odpt_line_services.py'
```

## Regional and operating-service expansion reviewed 2026-10-02

Before the reviewed public inputs below, the base inventory contains **45 partially researched physical lines** and **612 unknowns**. Curated class rows use exact section anchors from the independently reviewed 40-corridor inventory. Each class also has independent official label evidence; shared physical membership alone never creates 普通 or 快速. These new rows have no established effective-date interval and remain undated class evidence.

- [JR Hokkaido Airport service](https://www.jrhokkaido.co.jp/airport/index.html) explicitly labels 普通, 快速, 特別快速 and 区間快速 in its Sapporo–New Chitose stop guide. These classes cover 函館線 **札幌–白石**, 千歳線 **白石–南千歳**, and airport branch **南千歳–新千歳空港**. Only 快速 is additionally seeded along the reviewed 小樽–白石 through corridor; the source does not justify assigning every Airport class to 小樽.
- [JR Shikoku Marine Liner](https://www.jr-shikoku.co.jp/01_trainbus/vehicle-info/marine.html) explicitly identifies 快速 between 岡山 and 高松. Anchored evidence spans JR West 宇野線 **岡山–茶屋町**, JR West 本四備讃線 **茶屋町–児島**, JR Shikoku 本四備讃線 **児島–宇多津**, and 予讃線 **宇多津–高松**.
- [JR East Haranomachi October 2026 timetable](https://timetables.jreast.co.jp/2610/timetable/tt1259/1259010.html) explicitly defines unmarked trains as 普通 with Sendai destinations. Evidence covers the reviewed 常磐線 **原ノ町–岩沼** and 東北線 **岩沼–仙台** sections. No additional line is assigned local service just because it is regional.
- [Sendai Airport Transit FAQ](https://www.senat.co.jp/question) explicitly identifies 普通列車 and enumerates the Sendai–airport calls. Anchors are 東北線 **仙台–名取** and 仙台空港線 **名取–仙台空港**.
- [JR East Shinjuku October 2026 timetable](https://timetables.jreast.co.jp/2610/timetable/tt0866/0866080.html) explicitly defines 普通, 快速 and 特別快速. [Ordinary 2520Y's published stop list](https://timetables.jreast.co.jp/2610/train/110/113271.html) and [special rapid 4820Y's stop list](https://timetables.jreast.co.jp/2610/train/035/036581.html) corroborate the shared **大船–大宮** core via 武蔵小杉、大崎、新宿、池袋、赤羽. The physical evidence rows include 東海道線、西大井/武蔵小杉 corridor 総武線-3、大崎支線、山手線、赤羽線、東北線. They do **not** add 特別快速 to the 宇都宮–逗子 branch or claim that these trains call at every physical inventory station. Train labels can change by section.
- [JR East Tokyo JK October 2026 timetable](https://timetables.jreast.co.jp/2610/timetable/tt1039/1039140.html) explicitly defines 普通 and 快速 for 京浜東北線・根岸線. Both are attached to the reviewed **大宮–大船** operating corridor with exact anchors; rapid skipped stops occur in its central section and are not inferred for the entire physical line.
- [Sanyo through-express timetable](https://www.sanyo-railway.co.jp/railway/express.html) explicitly identifies **直通特急** between 山陽姫路 and 阪神大阪梅田. Evidence is anchored across 山陽本線、阪神神戸高速線 and 阪神本線. It does not create ordinary service or other class labels.

The Tokushima station PDF and Nippo/Miyazaki Airport PDF were inspected but do not provide an explicit 普通 label in the extracted material, so blank ordinary-looking columns and ワンマン annotations were not used to manufacture class evidence. The catalog's missing regional/private classes remain unknown until explicit labels or licensed timetable mappings are available.


## Reviewed public timetable inputs

`app/data/conventional-timetable/manifest.json` lists the approved overlays loaded by the builder by default. The bundled total is **51 partial lines, 606 unknown lines, 16 dated train-number sections, 62 verified calls**. These are small sourced sections, not sixteen complete end-to-end timetables.

- `hokkaido-chubu-public-reviewed.json`: five Meitetsu weekday trains for 2026-10-02, plus separately undated JR Central and Hokkaido class evidence. The accompanying source note records the current timetable PDF and Japanese holiday-calendar check.
- `jr-west-20261004-reviewed-sections.json`: five number sections from four actual published services for 2026-10-04. Rapid-to-ordinary class changes are scoped to the reviewed stations. The official 3438M→3138M number change retains reciprocal continuation IDs and the same Imazu boundary.
- `kanto-public-reviewed.json`: four JR East dated ordinary/rapid/special-rapid snippets for 2026-10-02, checked against the explicit operating-calendar cell on each train page.

Each input has its own adjacent `.sources.md` with exact primary URLs, station calls, date evidence and remaining gaps. The database retains train-number section boundaries; mere membership in a through-running corridor never creates an unstated schedule or continuation.

The explicitly paired northbound 大崎支線-p1 row shares the reviewed corridor class evidence with 大崎支線. Direction permissions remain separate; corridor selection uses each surveyed row only in its permitted direction.
