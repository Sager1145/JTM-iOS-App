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

# Pass 3: one composer, one filter, one home for the rest

Branch `claude/ui-reorg-pass3`, from `main` at 11376411c. The goal is the same as pass 2:
group features logically and never have two big features doing one job. Out of scope:
`JourneyEditor/`, the route repair flow and trip auto-fill / timetable research, which the
add-trip session is merging.

## Tab model: Upcoming · History · Stats · Add trip

Pass 2's single Journeys tab, with an Upcoming/All segmented control, has been reversed by the
user's correction: Upcoming and History are different questions and get their own tabs.

| Tab | Holds | Header |
|---|---|---|
| **Upcoming** | Trips dated today or later, on each trip's own region clock | share · filter · ⚙︎ |
| **History** | Everything before today, plus undated records (replaces "All") | ▶ · share · filter · ⚙︎ |
| **Stats** | Statistics | share · filter · ⚙︎ |
| **Add trip** | Not a page: the system's separate search-role button at the end of the bar | — |

- Each list has its own search field at the top. Typing searches **that list**: results are
  partitioned by the same today line. The shared filter button sits in each header.
- Playback (▶) is on History only. It plays what has been ridden; an upcoming trip has no run
  yet.
- The Upcoming/History line comes from one memoised set (`WorkspaceDerived.aheadIDs`, the
  unfiltered `WorkspaceJourneyRules.upcomingScope`), so the two lists can't overlap or drop a
  trip between them.
- `RAILMAP_UI_TEST_TAB` accepts `upcoming`, `history` (or the old `all`/`journeys`), `stats` and
  `search` (Upcoming's search state).

### Add trip: the one home for adding trips

The prominent search-role tab button is now **Add trip**. Selecting it opens a menu and leaves
the current tab selected. The menu has four items:

| Item | Why it is here |
|---|---|
| New trip | Opens the map-first editor (entry point only; the editor is the add-trip session's) |
| Import from file | A JSON export, from this app or the web app |
| Paste journey data | The same, from the clipboard |
| Transfer guide screenshot | Reads a route planner screenshot into a trip (`TransferGuideImportView`) |

This is the minimal set: each item is a different *source* a trip comes from, and dropping any of
them would remove a feature. With the Add trip menu in place, the other homes were removed:

- the `+` in the list header;
- Data Library's Import section. Data Library now manages the data already in the app (export,
  samples, package availability, recovery, deletion).

The empty-state Import button and ⌘N remain, as shortcuts. The empty-state Import opens this
menu, and ⌘N opens New trip directly.

## Sharing is one feature

Before this pass there were three share surfaces, each with its own renderer and file writer:

| Before | Renderer | File |
|---|---|---|
| Journey card → poster sheet (`JourneyShareView`) | CoreGraphics poster | `rail-journey-<UUID>.png`, **never removed** (audit A19) |
| Stats header → statistics composer | `ImageRenderer` cards | `SharePNGWriter`, retired earlier launches' files |
| Playback bar → video options sheet (`WorkspaceSheet.videoOptions`) | `AVAssetWriter` | `RailMap-<UUID>.mp4`, earlier launches' files kept |

Now there is one **Share composer** (`Sharing/ShareComposer.swift`). It is a full-screen cover
owned by the workspace, with two segmented controls:

- **Scope:** This journey · Journey list (the Journeys list as its search and filter show it) ·
  Statistics. "This journey" appears only when the composer was opened from a journey.
- **Format:** Image · Video. Video is offered for journeys only, because a film is a recording of
  a playback run. Statistics is image-only.

| Scope × format | What it shows |
|---|---|
| Journey · image | The journey poster with Full/Basic (`JourneyShareContent`) |
| List · image | A list poster: one card per journey with date, service, endpoints, times and operator. Same renderer, different blocks (`JourneyPoster.listBlocks`) |
| Journey/List · video | The frame, quality and bitrate form. Start dismisses the composer and films those journeys |
| Statistics · image | The existing card composer, now hosted inside the shell |

Each context has one entry, and every entry opens this composer:

| Context | Entry | Opens on |
|---|---|---|
| Journey card | Share (`journeyShareButton`) | This journey · Image |
| Upcoming and History headers | Share (`journeysShareButton`, new) | Journey list (that tab's list) · Image |
| Stats header | Share (`statisticsShareButton`) | Statistics |
| Playback bar while a run plays | Video (`playbackVideoButton`) | Video, scoped to the run's journey or the list |

The playback bar's share of a *finished* film stays where it is. It hands over the file that
was just made; it is not another way to compose one.

**One writer.** `Sharing/ShareArtifactWriter.swift` names every share file (journey, statistics,
video) and writes the PNGs off the main actor. On the next write of a kind it removes that kind's
files from earlier launches, and when a newer image of the same kind lands it removes the one it
replaces. This fixes the A19 leak: each kind switch, language change or retry on a journey poster
used to leave another PNG in `tmp/`.

**One renderer per medium.** Journey and list images share `JourneyPoster.render(blocks:)`.
Statistics cards keep `ImageRenderer`, because they are SwiftUI layouts the reader arranges on a
canvas. Porting them to CoreGraphics, or the poster's measured multi-column text to
`ImageRenderer`, would be a rewrite with real regression risk (long journeys reach a 20,000 pt
bitmap). Both now meet at the same writer.

### Phone CPU and memory

The composer is built for a phone's limited CPU and memory:

- **Previews render at screen scale and off the main thread.** The journey and list poster
  preview is rasterised in a detached task at about the width it is drawn at (420 pt × display
  scale), not at the export's 3×.
- **The full-size image is made only on Share (or zoom).** It is rendered off the main actor,
  written straight to disk by `ShareArtifactWriter`, and the bitmap is released; only the URL
  is kept. The zoom view decodes that file while it is open and drops it on close.
- **The statistics confirm sheet keeps a thumbnail.** It shows a 1,200 px copy; the full-size
  composite lives only until it has been written. The statistics cards still render on the main
  actor, because SwiftUI's `ImageRenderer` requires it. Their map snapshots come from
  `MKMapSnapshotter`, which works off the main thread.
- **Video frames are streamed.** The exporter appends one frame at a time from the writer's
  `CVPixelBuffer` pool and drops a frame rather than queueing it when the writer is busy. No
  frames are buffered.
- **Temporary files are retired** as described above (A19).

Measured on the shared iPhone 17 simulator (iOS 27.2) by sampling the app process's resident
memory every 0.25 s during a temporary probe test (not committed):

| Share | Before opening | Peak while previewing | Peak overall |
|---|---|---|---|
| Image: the 217-row synthetic long journey, Full | 692 MB | 744 MB | **785 MB** (export written, share sheet up), +93 MB |
| Video: Taiwan sample run, 540p, small bitrate | 617 MB | 743 MB (options open; includes the run-length estimate) | **813 MB** while recording, +196 MB |

Over 240 s of recording, memory stayed between 743 and 813 MB with no upward trend, which is
consistent with frames being streamed. The run had not finished by the end of the probe. These
are simulator RSS figures on a Mac host. They show the relative cost and the absence of growth,
not a device jetsam footprint. The Japanese `train-store` sample still does not load through the
test hook in this tree (0 rides), so the video probe used the Taiwan sample.

The station card's share (a station name for the system share sheet) is not a journey or
statistics share. It stays as it was.

## The share page, redesigned from scratch

The first composer reused the statistics canvas editor for statistics. That is a grid of share
widgets the reader arranges by hand, and it rendered a Taiwan-only log as five empty Japanese
maps. The user asked for a new share page. The design:

**One screen, three decisions, live preview.**

```
┌ Cancel            Share                        ┐
│ [ This journey | Journey list | Statistics ]   │  scope (only the ones this opening has)
│ [ Image | Video ]                               │  format (video: journeys only)
│ ┌───────────────────────────────┐              │
│ │      live card preview        │  ← the real  │
│ │   (the SwiftUI card itself,   │    card view │
│ │    scaled to fit the width)   │    at 1:1    │
│ └───────────────────────────────┘              │
│ Shape   [ Story 9:16 | Portrait 4:5 | Square ]  │
│ Look    [ Light | Dark ]                        │
│ (Journey) Stops [ Key stops | All stops ]       │
│ ─────────────────────────────────────────────  │
│ [        Share image        ]                   │  renders full size once, writes, shares
└────────────────────────────────────────────────┘
```

The preview *is* the card: one SwiftUI view, `ShareCardView`, laid out on a fixed 360 pt
design canvas (Story 360 × 640, Portrait 360 × 450, Square 360 × 360). On screen it is
drawn scaled to fit. On Share, `ImageRenderer` draws the same view at 3× (1080 px wide),
`ShareArtifactWriter` writes it, and the bitmap is released. One renderer and one layout serve
every scope, so the preview and the file can't disagree. Text inside the card uses fixed sizes:
it is an image, not reading UI. The route map is an `MKMapSnapshotter` image made off the main
thread. The preview gets one at screen scale, the export one at export scale, and only the
current one is kept.

**The cards: one key number each, then supporting detail.**

*Journey card*:
- Header band in the journey's line colour, with the operator and train type.
- The train number as the title, and the date.
- Origin → destination as the hero, each with its time.
- A fact row: distance (km), time on board, number of stops.
- The route map.
- The stops: key stops (endpoints, passenger stops and service changes) or all stops. On a Story
  card the stops fill whatever room the map leaves; any that don't fit end in "+N more".
- A footer with the app mark.

*Journey list card*:
- The filter as the title (for example "History · Taiwan, All dates"), with the date span.
- A totals row: journeys, km, time.
- One map with every journey's route.
- A dated list of journeys (date · number · A → B · km), as many as the shape fits, then
  "+N more".

*Statistics card*:
- The scope (region, period) as the title.
- The hero: distance ridden (the deduped total the Stats ticket prints) and the ride count.
- A 2 × 2 grid: time on board, stations, operators, network coverage %.
- A 12-month ride rhythm bar chart: one hue, each bar's value printed, the busiest month called
  out.
- The top three operators with bars.

No map on the statistics card: on a Story card the numbers fill it. The list and journey cards
carry the map.

On every card, the detail section (stops, journeys, chart and operator bars) shows as much as
fits *whole*. `ViewThatFits` picks the longest list that fits the shape, and the rest is counted
in "+N". Nothing is cut at the card's edge.

**Video** keeps the existing recorder settings (frame, quality, bitrate, length and size
estimate). Start dismisses the composer and films the journey or the list.

**Data.** Everything comes from values computed once:
- statistics: `MileageStatisticsStore.view` and `.passport`;
- per-journey distance: the new `PassportStatistics.journeyKm` map, built in the same pass as
  the tallies;
- route geometry: `RiddenRouteStore.rides`.

The card model is built once per scope and option change, never per frame.

**Stats tab.** On the user's instruction, the Stats page itself stays as it was before this
overhaul (as at `10001a4be`), including the Replay and export card that pass 2 had removed.
The one exception is the merged region and period filter in its header, which is the shared
filter decision. data-perf's memoised `availableYears` is kept: it calls the same
`StatisticsMembership.availableYears` with the same inputs, so nothing shown changes.

**What it replaces.** `ShareComposerView`, `ShareComposerModel`, `ShareComposerCanvas`,
`ShareComposerDrag` and `ShareCardRendering` (the hand-arranged widget canvas), and the
CoreGraphics journey poster (`JourneyPoster`). The Stats tab's own cards (`StatsWidgetView`)
stay as they were.

## Map trip cap and hiding by country, year or month

**Cap.** `MapTripCap.limit = 500` (`Workspace/TripHideFilter.swift`) is the one hard-coded limit.
It is applied at the single point where the scoped trips feed the map:
`RailWorkspaceView.mapRides` → `WorkspaceDerived.cappedRides`, memoised per scope and selection.
That is upstream of data-perf's map update batching, and nothing is capped per layer.

- **Which 500:** the selected trip first, then the most recent; drawing order among them is
  kept.
- **The notice:** when more trips match, a small capsule at the top of the map says "Showing
  500 of 1,284 trips. Narrow by country or month." Tapping it opens the hide sheet.
- **Lists** still scroll through every trip.
- **Playback** takes its queue through the same cap.
- **The share card's map** uses the same cap.

**Hiding by country, year or month.** This is the second half of the one scope filter, not a
new feature: every tab's filter menu gets **Hide trips…** and, while something is hidden,
**Show all**. The filter button carries a badge with the hidden count. The sheet has:
- multi-select toggles for the countries and regions present in the data;
- a toggle per year, with that year's months under it. Turning one month back on inside a
  hidden year hides that year's other months individually instead.

Choices persist across launches (`UserDefaults`; UI tests are scoped by storage id).

- **Where it applies:**
  - the map;
  - Upcoming, History and search;
  - Stats (the statistics load is given the visible trips, and its load key includes the
    choices);
  - playback and share, which follow the lists.

  One scope everywhere.
- **The per-trip Hide** (`Train.visible`) stays a separate action. It takes one trip off the map
  and keeps it in the lists. The two compose: a trip is drawn only when it is neither switched
  off itself nor in a hidden region or month.
- **Cost:** `TripHideFilter` builds a trip → (region, `YYYY-MM`) index once per store
  generation. It derives the hidden set and the visible trips and days once per index or choice
  change, and returns the same arrays until either changes, so every memoised derivation
  downstream keeps its key.
- **Tests:** `RailMapTests/TripScopeTests`:
  - the cap's size, order and drawing order;
  - hiding by region, year and month;
  - one month inside a hidden year;
  - persistence and per-storage isolation;
  - stable answers.

## One text-size cap

`AppTypographyPolicy.maximumSize = .xLarge` is the app's one hard-coded text-size ceiling. Every
other limit derives from it:

- the SwiftUI range applied once at the scene root;
- `UIWindow.maximumContentSizeCategory`;
- the window scene's `traitOverrides.preferredContentSizeCategory`. This is what reaches
  presented sheets, popovers and full-screen covers: they take their text size from UIKit
  traits, not from the root's SwiftUI environment. Before this, the resident sheet's journey
  list grew to accessibility sizes while the root stopped at the cap;
- the clamped `UIFont`s that the map's UIKit annotations and `BottomChromeMetrics` measure with.

The cap is re-applied when the reader changes their setting, so every size at or below it still
follows them. The header dock toggle's separate `.xxxLarge` ceiling now uses the policy too.

Why `.xLarge`: it is the largest size at which the densest rows still lay out on a 402 pt
iPhone:
- the sheet header (title, subtitle, up to four 44 pt actions);
- Upcoming and History rows (date, number and endpoints, one line each);
- the Stats ticket artboard.

From `.xxLarge` up, those rows wrap into the next row or truncate station names.

Share cards are pictures with fixed type sizes, so they don't scale with the setting at all.
`AppTypographyPolicyTests` now also asserts that the window carries the cap.

## One scope control on both tabs

Stats had two header buttons for its scope: a globe for region and a calendar for period.
Journeys had one filter menu. Now both tabs have the same filter button
(`line.3.horizontal.decrease`). It contains:

- **Region:** the same `regionMenuItems` and the same shared region value on both tabs.
- **Date / period:** each tab keeps its own value, as §5.3.1 requires; the statistics period
  stays independent of the list filter. On Journeys this is the date list. On Stats it is a
  **Period and groups…** item that opens the existing period/group picker.

The Japan area choice (Hokkaidō, Honshū and its areas, Shikoku, Kyūshū, Okinawa) is in this
shared control, but only on Stats. The list has no way to place a journey in an island until its
route is solved. Offering Honshū on Journeys would be a choice that silently does nothing.

The headers are now one shape, each in this order: the destination's own actions, then Share,
then the filter, then the gear.

| Tab | Before (pass 2) | After |
|---|---|---|
| Journeys → Upcoming | `+ ▶ filter ⚙︎` | `share filter ⚙︎` |
| Journeys → History | `+ ▶ filter ⚙︎` | `▶ share filter ⚙︎` |
| Stats | `share calendar globe ⚙︎` | `share filter ⚙︎` |

`PrimaryTab.headerActionCount` is updated to match (3 / 4 / 3).

## Sweep: other features with two homes

I checked the audit's §1 and §2 tables (UI-level rows) and walked the app.

| Feature | Before | After |
|---|---|---|
| Legend and sources | Map rail info button on most layouts; the gear menu on hinged/Duo layouts | Map chrome everywhere: the Duo map toolbar gets the same `mapInfoButton`, and the gear holds only Data Library and Settings |
| Rail package status | Settings › About & diagnostics listed every package's lines and failures; Data Library's availability section listed the same, with Retry | Data Library only. Diagnostics keeps the decode time, which Data Library does not show |
| Import | Data Library's Import section, plus the empty state's Import, which opened a paste-only import sheet | The tab bar's Add trip menu (file · paste · transfer guide, next to New trip). The empty state opens that menu |
| Dead second homes | `WorkspaceRideDetailView` (no callers), `JourneyListRow.play` (unused since pass 2), `PassportWorkspaceView.openSettings` (unused) | Removed |

Checked and kept:

- **Playback.** Starts come only from the Journeys header play button (the list), the journey
  card's Play (one journey) and Space. There is no third home.
- **Map layers vs Settings.** No toggle is repeated; Settings › Map says so in its footer.
- **Keyboard and menu commands** (⌘N, ⌘F, zoom, layers and so on). These are shortcuts, not
  homes. The phone layout re-declares some of them in code; that is code duplication, not UI
  (follow-up).
- **Save failure messages** come in five styles (audit A16). Several live in the editor and
  repair flows that this pass may not touch, so this is a follow-up.

## Files changed in pass 3

- New: `Sharing/ShareComposer.swift`, `Sharing/ShareArtifactWriter.swift`.
- `Sharing/JourneyShareImage.swift`:
  - `JourneyShareView` is now `JourneyShareContent`, a journey or list subject with no
    navigation bar of its own.
  - `JourneyPoster.render(blocks:)` replaces the per-journey render, and `listBlocks` is added.
  - Files go through the writer.
- `Sharing/ShareComposerView.swift`: hosted by the composer; it no longer owns a navigation
  stack or Cancel.
- `Sharing/ShareCardRendering.swift`: `SharePNGWriter` is removed in favour of the shared writer.
- `Playback/VideoExportOptionsView.swift`: now the composer's Video format, with Start at the
  bottom. `Playback/PlaybackVideoExporter.swift`: the film URL comes from the writer.
- `Workspace/RailWorkspaceView.swift`:
  - `shareRequest` and `openShare` are new, and the `\.openShare` environment value is provided.
  - `shareListTrains` replaces the private list rule in `playbackScope`.
  - `statisticsFilterMenu` replaces the calendar and globe buttons.
  - Also: the Journeys Share button, empty-state Import → Data Library, and the Duo legend.
- `Workspace/WorkspacePanelActions.swift`, `PrimaryTab.swift`, `WorkspaceSheetContent.swift`
  (`.videoOptions` removed).
- `Map/MapControlBar.swift` (Duo info button), `Journeys/RideCard.swift`, `Journeys/RideDetailView.swift`,
  `Journeys/JourneyListRow.swift`, `Statistics/PassportWorkspaceView.swift`, `Settings/SettingsView.swift`.
- Tab model:
  - `Workspace/PrimaryTab.swift`: `WorkspaceTab` is now upcoming · history · stats · add.
  - `Workspace/WorkspaceTabs.swift`: three tabs plus the search-role Add trip, in the modern,
    legacy and Duo variants.
  - `Workspace/WorkspaceDerived.swift`: the `aheadIDs` memo.
  - `App/AppShell.swift`: the tab hook.
  - `Import/DataManagerView.swift`: the Import section is removed.
- Strings, in en/ja/zh-Hans/zh-Hant:
  - `ios.share.*`, `ios.stats.filter`, `ios.stats.periodItem`;
  - `ios.tab.history`, `ios.tab.addTrip`, `ios.addTrip.*`, `ios.journey.noHistory`,
    `ios.search.noneHere`.
- UI tests (tab model): tab indices and labels (Upcoming 0, History 1, Stats 2, Add trip 3) and
  the removed `journeyListScope` segments. The transfer-guide test opens the Add trip menu.
  Affected files: `ConsoleSweepTests`, `MenuStressUITests`, `RailMapUITests`,
  `RefactorReleaseMemoryUITests`, `MapCameraIntentTests`, `PlaybackLayoutTests`, and comments in
  three editor tests. The `search` tab hook now opens History's search, because that list holds
  the past sample trips the tests look up.
- UI tests (sharing and filter):
  - `regionScopeButton` / `statisticsDateButton` → `statisticsFilterButton` (+ `statisticsPeriodItem`).
  - `journeyShareCloseButton` → `shareCloseButton`.
  - Affected files: `IntegratedSharingUITests`, `JourneyGroupUITests`, `StatisticsCalendarUITests`,
    `RefactorReleaseMemoryUITests`, `JourneySharingUITests`.

## Journey editing: one editor (2026-11-05)

Branch `claude/journey-editor-unify`. Paths are relative to `ios/RailMap/`.

| Before | After |
|---|---|
| `NewTripView` (map-first, new trips only) and `RideEditorView` (2,108 lines, existing trips): two editors for one `Train` | `JourneyEditor/JourneyEditorView.swift`. A new trip is an empty draft. A saved trip opens with its saved route drawn on the editor's map, its end stations found in the catalog, and its stops editable. Picking another station or a via on the map or in search replans the route there, with alternatives and via stops. `JourneyEditorDetails.swift` holds the record fields that the route and timetable never set: stops, English name, direction, vehicle, section services, notes, visibility, group, colour and identifier. |
| Route repair in the workspace card (`RailWorkspaceView`, about 200 lines, persisting each step) and again in `RideEditorView`; the `RouteRepairGuide` and `RepairContinuation`/`RouteGuideRequest` pause types; `RouteRepairSession`; `RailwayRouteGuideView` and `RailwayRouteCorrectionView`; `RouteSectionEditorView`; `RoutePolicyEditorView` | One `JourneyEditor/RouteRepairController.swift`, with one pause type, over the editor's draft. The card's Repair route opens the editor in repair mode (`JourneyEditorLaunch.repairsRoute`). A span the package decides alone is applied. An ambiguous span shows its tracks as alternative routes on the editor's map and as buttons, and tapping one applies it. Nothing is saved until Save, so Undo is Cancel. `RouteRepair.Gap.init(SectionGap)` replaces the two copies of the gap mapping. `RouteRepairSession` and its tests are deleted. Manual range correction, route-section editing and route-policy editing are replaced by choosing the route on the map. |
| Filling details from `LocalJourneyFillView`, `JourneyCompletionView` and the timetable research (`Timetable/`), each with its own entry | One **Fill in trip details** entry (`newTripFillDetails`) opens one sheet with every source: timetable matches for the trip, the full timetable browser, the line's service types, and ChatGPT or pasted text. What was applied stays shown in the editor. `LocalJourneyFillView` is deleted, because the map planner already offers the physical routes it searched. |
| `StationPickerView` was a list picker. `StopEditorView`, `RouteSectionEditorView` and `LocalJourneyFillView` each opened it differently. | One picker: a map above the search (`stationPickerMap`; zoom in and tap a station), used by the editor's From/Via/To and by `StopEditorView`. The other two callers were deleted. |

The saved record format is unchanged. A saved trip that is opened and saved without edits writes back the same record, except that an empty direction is inferred, as the old editor did. A header field (time, number, type, operator, ridden) is written back only when the reader changed it (`JourneyEditorSeed.swift`). A replanned route keeps the saved visits the new route still passes, with their clocks (`LocalJourneyAutofill.proposal` over the full saved stops).

Removed with the second editor: manually adding, deleting and reordering stops (the route now comes from the map, and a stop along the way is a via), free-text origin and destination, the typed date field, the preferred-lines search, and the region and route-policy rows of the record section. The main map's draft pins are no longer published (`pins: []`), because the editor has its own map. The detail sections (English name, section services, notes, visibility, group, colour, identifier) sit under one collapsed **More details** row.

**Direction.** Travel direction (上り/下り) is read from the route, never typed:
`TravelDirection.legs` (RailCore) gives each line stretch of a trip its own direction and the
terminal it runs toward. It is computed for display and not stored. The editor shows it per
leg in the Route section and as arrows on the map. The 方面 label is the reader's choice. It
is stored in the record's existing `direction` field, which saved data already uses for such
labels (for example "和光市・池袋"). The editor offers the line terminals and the trip's
last stop as suggestions, and saves nothing until the reader picks one. A stored `up`/`down`
value is treated as a direction, not a 方面, and is never rewritten. The manual Direction
field and the inference on save are removed.

Per-leg 方面 and platform letter suffixes are not stored. The record format has no per-section
bound-for field, and `platform_number` is an integer. The importer's strict key check
(`assertOnlyKeys`) is shared with the website, so a new key needs a website format change
first.

**Manual entry.** What no source filled is entered by hand in the editor's Trip details
section, which counts what is still missing ("Still missing: vehicle type · 3 platforms").
Vehicle type opens a picker that lists the applied timetable's own vehicle, then vehicle types
the reader used on the same lines or the same train, then free text. Platforms are set with a
badge on each stop row and on the departure and arrival rows. The badge opens a number pad
(1–20, any other whole number, or Clear), with no screen per stop. The Fill in trip details
sheet lists what is still missing after its sources and hands off to this entry.

Identifiers: the editor keeps the `newTrip*` names for its chrome (`newTripForm`, `newTripSave`, `newTripCancel`), and kept detail controls keep their `rideEditor*` names. A changed draft now asks before Cancel, for new trips too.
