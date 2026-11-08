# Time-zone audit — 2026-11-07 (static, main 3313613ab)

Rule (user): recorded train times use the trip region's zone, never the phone's; changing the phone zone must not change stored or displayed values; overnight trains roll correctly.

## Storage — correct
- `Train` date (`YYYY-MM-DD`), stop arrival/departure/actual_* (`HH:MM`, may exceed 24:00), `list_by_date`: zone-free strings. No epoch fields; JSON round-trips unchanged.
- `RegionClock` (RailCore/Utilities/RegionClock.swift) already maps jp/tw/hk/mo/kr/cn → zone + pinned Gregorian calendar; reached via `Region.clock` / `Train.journeyClock`.
- `TripListRules` (upcoming/overdue/initialMembership), filing, `RegionToday`, map era "today", statistics reference date, history/timetable date checks, ticket parsers: correct.

## Wrong — phone-zone dependent
1. **Journey editor header** — `JourneyEditorSeed.swift:48-65` (`timeZone = .current`), `TripDraftModel.swift:1016, 1084-1101`, `EditorDateTimeFields.swift:329, 367` (`Calendar.current`, unpinned graphical DatePicker).
   - New trip defaults to the phone's today/time: phone in Los Angeles 18:00 → JP trip dated a day early, filed **past**, Ridden **on**.
   - DST gaps in the phone zone shift times (`25:30` on a London DST night → ~02:00); departure moves shift arrival by raw interval (`TripDraftModel.swift:241-247`, `JourneyEditorView.swift:332-336`).
   - Phone zone change while editing shifts saved times; also `pendingPickerDate/Time`, `TransferGuideImport.Draft.date`.
   - Non-Gregorian phone calendar (Japanese/Buddhist) can corrupt typed years (`EditorDateTimeFields.swift:61, 400-424`; inferred).
2. **Stats/share display (cosmetic)** — `StatisticsScopePicker.swift:15, 68, 238, 310-313`, `PassportWorkspaceView.swift:140`, `StatisticsFormatting.swift:224`.

## Fix plan
- Extend `RegionClock`: `instant(serviceDate:clock:)` (handles 25:10), `serviceClock(of:serviceDate:)`, `civilDate(of:)`, pinned POSIX formatter.
- Switch the call sites above to `model.region.clock`; `TypedDateTimeField` takes an injected clock/calendar; `RecordDate.carrierCalendar` takes a clock.
- Pin every DatePicker (`EditorDateTimeFields.swift:28, 136, 158, 367`, `TransferGuideImportView.swift:317`) with `.environment(\.timeZone)` and `.environment(\.calendar)` — must ship together with the call-site switch (see `RecordDate.swift:30-37` comment).
- Region change mid-draft keeps wall-clock time.

## Guards
- Device-zone matrix (helper `underDeviceZone` in `RegionClockTests.swift:37-46`): UTC, Tokyo, Los Angeles, London, New York, Kiritimati, Kathmandu, St Johns × region midnights and DST dates; record → seed → save byte-identical incl. `25:30`, `31:27`; new-trip date = region today; zone change between seed and save changes nothing.
- Japanese/Buddhist calendar injection tests for `TypedDateTimeField`.
- Source-scan guard (pattern: `StationLabelTests.swift`): no `Calendar.current` / `TimeZone.current` / `.autoupdatingCurrent` in record code; no `DatePicker(` without `.environment(\.timeZone`; allowlist Diagnostics, backup timestamps, subscription.

## Open
- Ambiguous: `TrainServicePatterns` uses Japan's day for all regions (sort only); no day/zone-change listener for overdue markers; historical DST in region zones (JP 1948-51, KR 1987-88).
