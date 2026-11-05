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

### Not changed in pass 1 (superseded by pass 2 below)

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

---

# Pass 2: one home per feature

Date: 2026-11-05. Rule: every feature gets **one logical home and one entry point**. The
only extras allowed are a keyboard shortcut, and an empty-state button when the home is
blank. Where a verb applies to two different things (the whole list, or one journey), it
appears once for each thing, never twice for the same thing.

## Tab model: two destinations

| Before (4 tabs) | After (2 tabs) |
|---|---|
| Upcoming | **Journeys**: search field → `Upcoming │ All` segmented control → list |
| All | (same Journeys list, `All` segment) |
| Search (system search role) | (same Journeys list, active while the field has text) |
| Stats | **Stats** (unchanged content, minus the Replay/Export card) |

Why: Upcoming, All and Search showed the same records in the same row, with the same
actions and the same map scope. Upcoming is a date rule, All is no rule, and Search is a
text query. Those are filters on one list, and a tab per filter forced people to remember
which tab held which slice. The tab bar now answers the app's two real questions: *what
have I travelled* and *what does it add up to*. The map itself is the third question and
was never a tab.

Implementation: the tab bar binds to `WorkspaceTab { journeys, stats }`. Internally,
`PrimaryTab` keeps `.upcoming`, `.all` and `.search` as the list mode, because the map
scope, playback scope and date rules already depend on them. Typing in the field switches
to `.search`, and clearing it goes back to the chosen segment. The `RAILMAP_UI_TEST_TAB`
launch hook still accepts `upcoming`, `all`, `search` and `stats`.

## Feature grouping: old → new

| Feature | Before (entry points) | After (one home) | Why |
|---|---|---|---|
| New journey | Search `+`; Upcoming `+` (pass 1); empty state; ⌘N | **Journeys header `+`**; empty state; ⌘N | One persistent button on the one journey destination |
| Search | Search tab; ⌘F | **Journeys search field**; ⌘F focuses it | Search is a filter on the list, not a place |
| Upcoming / All | Two tabs | **Segmented control** under the field | One question about one list, so one control |
| Date filter | Calendar button on Upcoming and All; gear submenu on Search | **Journeys filter button** (`journeyFilterButton`), *Date filter* section | One scope control for the list |
| Region scope | Globe button on Upcoming, All and Stats | Journeys filter button, *Region* section; Stats globe | The region value is shared. Stats keeps its own button because its Japan area submenu is a statistics-only choice |
| Statistics period | Stats calendar popover | Unchanged | §5.3.1: the statistics period is deliberately independent of the list filter |
| Playback of a list | All header ▶; Stats "Replay" card | **Journeys header ▶** (plays what the filter and search show) | One home, and it follows the list's scope |
| Playback of one journey | Row context menu "Play"; journey card Play | **Journey card Play** | The card is that journey's home. The row menu copy was the same verb twice |
| Video export | Playback transport → video | Unchanged | A video is a recording of a playback run, so it only exists while one is running |
| Journey share image | Card header share; details toolbar share | **Card header share** | The details sheet opens from the card, so this was the same verb twice |
| Statistics share image | Stats header share → composer | Unchanged | It shares statistics cards, which is a different object |
| Export JSON | Data Library; Stats "Export JSON" card | **Data Library** | Exporting data belongs with data |
| Import | Data Library hero button (dialog: file/paste); Data Library Import section (file/paste/guide); empty state | **Data Library → Import section** (file, paste, transfer guide: one tap each); empty state | The hero button was a slower second door to two of the same three options |
| Save / restore my rides | Gear menu; Data Library (pass 1 removed the gear copy) | **Data Library** | Data operations live with data |
| Clear selection | Gear menu; journey card ✕ | **Journey card ✕** | Closing the card is clearing the selection |
| Data Library, Settings | Gear menu | Gear menu (now holds only these two, plus Legend on hinged displays) | The gear is for utilities only |

## Considered and kept

- **One composer for every share (image, statistics, video).** A single Share entry for
  every format would need a new composer that takes a scope (one journey, a list, the
  statistics) and a format (image or video). The three objects already share in different
  places: the card, the Stats header, and the transport bar. None of them repeats another
  now. Building one combined composer is a separate project and is listed as a follow-up.
- **Train research / timetable lookup only inside the editor.** This is correct. The
  research fills in the train on the journey being edited, and without a journey there is
  nothing to write its answer into. The editor (`JourneyEditor/`) is owned by the map-based
  add-trip work.
- **Legend in the gear menu on hinged displays.** On those layouts the map rail (and its
  info button) is replaced by the Duo toolbar, so this is still the only entry there, not a
  duplicate.
- **Map toggles in the rail and the Duo toolbar.** Each appears in only one of these layouts
  at a time, so the two never duplicate each other on screen.
- **"All journeys" button on an empty Upcoming list.** This is the empty-state shortcut to
  the segment directly above it, so it is a hint rather than a second home.

## Files changed in pass 2

- `Workspace/PrimaryTab.swift`: `WorkspaceTab` (tab bar) plus `PrimaryTab.workspaceTab` / `isJourneyList`.
- `Workspace/WorkspaceTabs.swift`: two tabs in the phone, legacy and Duo shells.
- `Workspace/RailWorkspaceView.swift`: `journeysPanel` (field, segmented control, list), tab
  binding, query ↔ mode sync, `journeyFilterMenu` (region + date), gear menu reduced to
  utilities, ⌘F focuses the Journeys field, Stats no longer gets `openData`.
- `Workspace/WorkspacePanelActions.swift`: Journeys header `+ ▶ filter ⚙︎`, Stats header `share date region ⚙︎`.
- `Map/MapControlBar.swift`: the Duo "More" menu lists the two tabs.
- `Statistics/PassportWorkspaceView.swift`: Replay/Export card removed.
- `Journeys/JourneyListRow.swift`: row menu Play removed. `Journeys/RideDetailView.swift`: duplicate share removed.
- `Import/DataManagerView.swift`: hero Import button and its dialog removed.
- `Localization/ShellStrings.swift`: `ios.tab.journeys`, `ios.journey.filter`, `ios.journey.listScope` (en/ja/zh-Hans/zh-Hant).
- UI tests updated where tab indices, the filter button or removed entries were used.

Screenshots: `docs/screenshots/ui-reorganization/pass2-before-*.png` and `pass2-after-*.png`
(Journeys All, Upcoming and search results; Stats). There is no after screenshot of Data
Library: the shared simulator kept getting other sessions' builds installed over this one,
and the shot was lost. The single Import section was checked by eye on an earlier capture
and by the sweep below.

## Pass 2 verification (2026-11-05)

- Incremental app build and `build-for-testing` (all UI tests compile): succeeded.
- `ConsoleSweepTests/testWalkEverySurface`: passed with the statistics share step skipped
  locally (that step's `shareComposerAppearance` failure predates this work, and the skip was
  not committed). The run tapped the Journeys tab, the `Upcoming` and `All` segments, the
  search field, the gear → Data Library and Settings (both drill-downs), the map rail and
  layers, and a journey card.
- `MapCameraIntentTests/testRegionSelectionFramesWholeCountryWithAutoFocusDisabled` and
  `JourneySaveUITests/testSavedJourneyIsStillPresentAfterRelaunch` failed **before any changed
  navigation ran**. The camera test never loaded the JP `train-store` sample (`rides:0`); the
  pass-2 "before" screenshot of the old UI shows the same zero journeys. The save test fails
  inside the new-trip editor's station search, which is owned by the add-trip session. Both
  should be re-run once the JP sample loads and the editor work has landed.
- Not run: the other updated UI tests (tab indices and filter-button changes in
  `RailMapUITests`, `RefactorReleaseMemoryUITests`, `MenuStressUITests` and the Duo tests).
  They compile but have not been executed.

## Journey editing: one editor (2026-11-05)

Branch `claude/journey-editor-unify`. Paths are relative to `ios/RailMap/`.

| Before | After |
|---|---|
| `NewTripView` (map-first, new trips only) and `RideEditorView` (2,108 lines, existing trips): two editors for one `Train` | `JourneyEditor/JourneyEditorView.swift`. A new trip is an empty draft. A saved trip opens with its saved route drawn on the editor's map, its end stations found in the catalog, and its stops editable. Picking another station or a via on the map or in search replans the route there, with alternatives and via stops. `JourneyEditorDetails.swift` holds the record fields that the route and timetable never set: stops, English name, direction, vehicle, section services, notes, visibility, group, colour and identifier. |
| Route repair in the workspace card (`RailWorkspaceView`, about 200 lines, persisting each step) and again in `RideEditorView`; the `RouteRepairGuide` and `RepairContinuation`/`RouteGuideRequest` pause types; `RouteRepairSession`; `RailwayRouteGuideView` and `RailwayRouteCorrectionView`; `RouteSectionEditorView`; `RoutePolicyEditorView` | One `JourneyEditor/RouteRepairController.swift`, with one pause type, over the editor's draft. The card's Repair route opens the editor in repair mode (`JourneyEditorLaunch.repairsRoute`). A span the package decides alone is applied. An ambiguous span shows its tracks as alternative routes on the editor's map and as buttons, and tapping one applies it. Nothing is saved until Save, so Undo is Cancel. `RouteRepair.Gap.init(SectionGap)` replaces the two copies of the gap mapping. `RouteRepairSession` and its tests are deleted. Manual range correction, route-section editing and route-policy editing are replaced by choosing the route on the map. |
| Filling details from `LocalJourneyFillView`, `JourneyCompletionView` and the timetable research (`Timetable/`), each with its own entry | One **Fill in trip details** entry (`newTripFillDetails`) opens one sheet with every source: timetable matches for the trip, the full timetable browser, the line's service types, and ChatGPT or pasted text. What was applied stays shown in the editor. `LocalJourneyFillView` is deleted, because the map planner already offers the physical routes it searched. |
| `StationPickerView` was a list picker. `StopEditorView`, `RouteSectionEditorView` and `LocalJourneyFillView` each opened it differently. | One picker: a map above the search (`stationPickerMap`; zoom in and tap a station), used by the editor's From/Via/To and by `StopEditorView`. The other two callers were deleted. |

The saved record format is unchanged. A saved trip that is opened and saved without edits writes back the same record, except that an empty direction is inferred, as the old editor did. A header field (time, number, type, operator, ridden) is written back only when the reader changed it (`JourneyEditorSeed.swift`). A replanned route keeps the saved visits the new route still passes, with their clocks (`LocalJourneyAutofill.proposal` over the full saved stops).

Removed with the second editor: manually adding, deleting and reordering stops (the route now comes from the map, and a stop along the way is a via), free-text origin and destination, the typed date field, the preferred-lines search, and the region and route-policy rows of the record section. The main map's draft pins are no longer published (`pins: []`), because the editor has its own map.

Identifiers: the editor keeps the `newTrip*` names for its chrome (`newTripForm`, `newTripSave`, `newTripCancel`), and kept detail controls keep their `rideEditor*` names. A changed draft now asks before Cancel, for new trips too.
