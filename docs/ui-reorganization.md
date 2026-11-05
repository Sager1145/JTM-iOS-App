# iOS UI reorganization — feature map and proposal

Date: 2026-11-05. Scope: the iOS app only (`ios/RailMap/`). The new-trip editor
(`ios/RailMap/JourneyEditor/`), data loading and caching internals, and bundled
sample data are owned by other work and are not changed here.

Paths below are relative to `ios/RailMap/`. `RWV` = `Workspace/RailWorkspaceView.swift`.

## 1. Feature map (before)

The app is one map with one resident bottom sheet. The sheet holds four tabs
(`PrimaryTab`): **Upcoming**, **Stats**, **All**, **Search**. Each tab's header row
(`Workspace/WorkspacePanelActions.swift`) carries that tab's scope buttons and a
trailing gear menu (`utilityMenuButton`, "Data and settings").

| Feature | Where it lives | How you reach it |
|---|---|---|
| Upcoming journeys | Upcoming tab (`RWV upcomingPanel`) | Default tab |
| Passport statistics | Stats tab (`Statistics/PassportWorkspaceView.swift`) | Stats tab |
| All journeys list | All tab | All tab |
| Search journeys | Search tab (`RWV searchPanel`) | Search tab (system search role) |
| **New journey** | `presentJourneyEditor(... isNew: true)` | **Search header `+` only**; empty-state "Add" action; ⌘N |
| Edit journey | `RideEditorView` | Journey card → Edit; journey details → Edit |
| Journey card / details | `Journeys/JourneyMenuView.swift`, `RideDetailView` | Tap a row or a ride on the map |
| Row actions | `Journeys/JourneyListRow.swift` | Context menu (ridden, group, play, info, duplicate, hide, move, delete) and swipes |
| Journey share image | `JourneyShareView` | Card header share; details toolbar share |
| Date filter (+ Add date, Remove empty dates, map follows date, auto-focus) | `RWV journeyDateMenu` | Upcoming/All header calendar button; on Search, inside the gear menu |
| Region scope | `RWV regionMenu` | Upcoming/All/Stats header globe |
| Statistics date / group scope | `Statistics/StatisticsScopePicker.swift` | Stats header calendar |
| Statistics share composer | `Sharing/ShareComposerView.swift` | Stats header share |
| Playback | `Playback/` | All header play; row menu "Play"; card "Play"; Stats "Replay" |
| Video export | `Playback/VideoExportOptionsView.swift` | Playback transport bar → video |
| Map rail (compass, network, routes, layers, legend, locate) | `Map/MapControlBar.swift` | Always on the map |
| Map layers | `Map/MapLayersView.swift` | Rail → layers |
| Legend and sources | `Map/MapInfoView.swift` | Rail → info; gear menu on hinged layouts |
| Station card / line card | `Map/StationCardView.swift`, `RailwayLineCardView.swift` | Tap a station |
| Ride chooser | `Journeys/RideChooserView.swift` | Tap overlapping rides |
| Route repair | Route guide sheet | Card → Repair route |
| Timetable match / train research | `Timetable/` | Only from inside the journey editor |
| **Save as my rides / Restore my rides** | `RWV rideSourceSection` | **Gear menu on Upcoming/All/Search** — *and* Data Library → My rides |
| Clear selection | `RWV rideSourceSection` | Gear menu, when a ride is selected |
| Data Library | `Import/DataManagerView.swift` | Gear → Data Library; Stats "Export JSON" |
| Import (file, paste, transfer guide) | Data Library | Data Library (top Import button *and* Import section); empty-state Import |
| Export / copy JSON, samples, backup, danger zone | Data Library | Data Library |
| Settings | `Settings/SettingsView.swift` | Gear → Settings |

### Settings before

One flat Form of eleven sections, in this order: Language · Journey card names ·
Station names · Appearance · Opening view · Map content (rail-network toggle,
"Frame loaded network" button, Renderer = Apple Maps, Network era) · Train routes
(2 sliders) · Station markers (4 sliders) · Selection & focus (2 sliders + toggle)
· Reset · Diagnostics (package status, decode time, failures).

### Overlaps and problems found

1. **Data-changing actions in the gear menu.** "Save as my rides" and "Restore my
   rides" sit in the gear menu and again in Data Library → My rides. `SettingsView`
   states the rule this breaks: an operation that changes data lives in the Data
   workspace and is not mirrored. "Restore my rides" also replaces the working
   set from a menu that otherwise holds navigation.
2. **The rail-network toggle exists three times**: the map rail button, the Duo
   toolbar, and Settings → Map content.
3. **"Frame loaded network" is an action, not a setting.** It moves the map
   *behind* a modal Settings sheet, so the reader never sees it happen. On iPhone
   it has no other touch entry (the rail dropped it; only ⌘ remains).
4. **The Renderer row** ("Apple Maps") is a constant, not a choice, and sits
   between two real controls.
5. **Nine sliders on the first Settings screen.** Line width, opacity, four marker
   sizes, focus boost and dimming are fine-tuning most readers never touch, yet they
   push Diagnostics and Reset far below the fold. Apple's simplicity rule: show the
   common path first, advanced options one level deeper.
6. **Diagnostics on the main Settings screen.** Package status and decode time are
   for troubleshooting, not preferences.
7. **Adding a journey is only on the Search tab** (plus the empty state). Upcoming,
   the default tab and the place planned trips appear, has no add button.
8. Data Library has two Import entries (top button with Open/Paste dialog, and the
   Import section with Open/Paste/Transfer guide). *Noted, not changed here.*
9. Journey share has two entries with the same identifier (card header and details
   toolbar). They are on different surfaces and both reasonable. *Not changed.*

## 2. Proposal

The documented intent at the top of `SettingsView.swift` is kept unchanged: every
Settings control answers "the map" or "the interface"; nothing on it edits data;
every toggle explains itself where it stands. The changes below apply that rule
more strictly rather than relaxing it.

### Settings — regroup into a short first screen plus two drill-downs

Main screen, ordered from most to least used:

1. **Language** — interface language.
2. **Appearance** — theme.
3. **Journey card names** and **Station names** — how names are written (unchanged).
4. **Map** — Opening view (+ region) and Network era. One section for "what map you
   see", where Opening view and Map content used to be two.
5. **Map style ›** (drill-down) — Train routes, Station markers, Selection & focus.
6. **Reset to defaults** — still resets every display preference; footer unchanged.
7. **About & diagnostics ›** (drill-down) — Renderer, display network, package
   status, decode time, failures.

Moved out of Settings:

- **Rail-network toggle** → removed from Settings. The map rail button (and the Duo
  toolbar) already own it; three switches for one layer is two too many.
- **Frame loaded network** → Map layers sheet, under "All railways". That sheet is a
  half-height sheet over the map, so the reader sees the map move.

### Gear menu ("Data and settings")

- Remove **Save as my rides** and **Restore my rides**. They remain in Data Library →
  My rides, which is the documented home of data-changing operations.
- Keep **Clear selection** (a view-state action), the Search-only date filter, Data
  Library, Settings, and the hinged-only Legend entry.

### Header actions

- Add the **New journey `+`** button to the **Upcoming** header (leading slot, before
  the date and region buttons). The Search `+`, the empty-state action and ⌘N stay.
  Same handler, same editor launch; only the entry is added. The editor itself is
  not touched.

### Not changed (deliberately)

- Four tabs and their order (UI tests and muscle memory depend on them).
- Date/region scope buttons (already moved out of the gear by earlier work).
- Map layers vs. Settings split: the layers sheet owns *visibility*, Settings owns
  *style and sizing*. That split is sound; only the duplicate network toggle and the
  misplaced framing action moved.
- Data Library contents (item 8 above is a follow-up).

## 3. Implementation notes

- `Settings/SettingsView.swift` — new section order, `NavigationLink`s to
  `SettingsMapStyleView` and `SettingsDiagnosticsView` (same file). Identifiers:
  `settingsMapStyleLink`, `settingsDiagnosticsLink`.
- `Map/MapLayersView.swift` — "Frame loaded network" button (`layerFrameNetwork`).
- `Workspace/RailWorkspaceView.swift` — `rideSourceSection` keeps Clear selection only.
- `Workspace/WorkspacePanelActions.swift`, `Workspace/PrimaryTab.swift` — `+` on
  Upcoming (`newJourneyButton`), header action count 3 → 4.
- `Localization/ShellStrings.swift` — new `ios.*` keys in en / ja / zh-Hant / zh-Hans.
- UI tests: `ConsoleSweepTests` now opens the two Settings drill-downs so the
  diagnostics rows are still mounted by the sweep.

Before/after screenshots: `docs/screenshots/ui-reorganization/`.

## 4. Verification (2026-11-05)

- One incremental simulator build (iPhone 17, iOS 27.2): succeeded.
- Before/after screenshots taken with `simctl` and the app's `RAILMAP_UI_TEST_SHEET`/`_TAB`
  launch hooks: Upcoming header (`+` added), Settings first screen (General section),
  Map layers (framing button).
- `JourneyTranslationUITests/testOriginalNamesAreDefaultAndTranslationChoicePersists`
  passed (opens Settings through the gear menu and toggles a Settings row).
- `ConsoleSweepTests/testWalkEverySurface` fails before reaching Settings, at the
  statistics share composer (`shareComposerAppearance` not found). Neither that code nor
  that part of the test changed here. With that one step skipped locally (the skip was not
  committed), the sweep passed and tapped `settingsMapStyleLink` and `settingsDiagnosticsLink`.
- The screenshots show only the first Settings screen, because `simctl` cannot scroll or tap.
  The drill-down pages were exercised by the sweep, but no screenshot of them was taken.
