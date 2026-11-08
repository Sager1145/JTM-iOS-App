# UI consistency audit, 2026-11-07

Scope: the iOS app under `ios/RailMap/**` (SwiftUI, iPhone and Mac Catalyst), except
`Diagnostics/` (developer tools). Base: `main` at `3313613ab`, branch
`claude/ui-consistency-audit`. **Nothing is fixed here.** Fixes wait until
"Add-trip quick-add layout" (`JourneyEditor/*`) and "Trip event notes" (trip detail
and map) are merged and the user has chosen among the options in §4.

What the audit checked: spacing, button size and placement, element heights, title
bars, type, icons, corner radii, materials, light and dark mode, and Catalyst.

Method:

- **Static pass.**
  - A scripted inventory of every literal `.padding`, `spacing:`, `.frame`,
    `.font`, `cornerRadius:`, `.buttonStyle`, toolbar placement, title mode and
    sheet detent. Its raw counts are in §5.
  - Three read-only area reviews:
    - Workspace and Journeys
    - JourneyEditor, Timetable and Import
    - Stats, Settings, Map, Sharing and Playback
  - Hand checks of each finding cited below.
- **Runtime pass.** Screenshots through app-control `launch` on the iPhone 17
  simulator `0DBE2488`, with an isolated UUID store loaded with the `train-store` and
  `train-store-tw` samples, in light and dark mode. The files are in
  `docs/maintenance/screenshots/ui-consistency-audit/`, cited as `[shot: name]`.
- **Skills.**
  - Used: `apple-design` (Familiarity: "things that look the same must behave the
    same and live in the same place"; Craft: "every spacing … value is a deliberate
    choice you can defend") and `emil-design-eng` (its Before/After review format,
    used in §4).
  - Searched for, not installed: no iOS/SwiftUI HIG audit skill exists in the
    catalog. The nearest are Anthropic's **Design** plugin (`design-critique`,
    `design-system`, `accessibility-review`) and the community **design-skills**
    plugin (`design-systems`, `accessibility-audit`). Both are web or Figma oriented.
    They are listed for the user to decide on.

## 1. What already exists (the tokens are there, they are just not used everywhere)

| Token | Where | Value |
|---|---|---|
| `WorkspaceMenuMetrics.horizontalInset` | `Workspace/WorkspaceLayout.swift:18` | 16 |
| `.contentSpacing` / `.contentTopInset` / `.topInset` / `.bottomInset` | `WorkspaceLayout.swift:19-25` | 12 / 8 / 12 / 8 |
| `.listRowVerticalInset` / `.fieldHorizontalInset` / `.compactButtonVerticalInset` | `WorkspaceLayout.swift:21-23` | 6 / 12 / 4 |
| `.buttonSide` / `.touchSide` / `.iconSize` / `.titleSize` | `WorkspaceLayout.swift:13-17` | 32 / 44 / 18 / 20 (title scaled by `@ScaledMetric`) |
| `.cardCornerRadius` (the docked panel and sheets) | `WorkspaceLayout.swift:30` | 28 |
| `RailStyle.cardCornerRadius` / `controlCornerRadius` / `chromeCornerRadius` | `Design/RailStyle.swift` (§6.4) | 20 / 12 / 20 |
| `RailStyle.minimumTouchTarget`, `.railMinimumTouchTarget()` | `RailStyle.swift`, `Design/ControlSizing.swift:43` | 44 |
| `RailCapsuleButtonStyle(prominent:visualHeight:)` | `Design/ControlSizing.swift:3` | capsule, horizontal 12, min height 32 |
| `SheetIconButton` | `Journeys/RideSheet.swift:177` | 32 pt circle, 18 pt semibold glyph, 44 pt hit area |
| `railHalfSheetDetents()` | `Design/GlassStyle.swift:184` | `[.medium, .large]`, none on Catalyst |
| `RailType` roles, `AppTypographyPolicy` | `Design/RailType.swift`, `Design/AppTypographyPolicy.swift` | Dynamic Type capped at `.xLarge` |
| `MapControlBar.side` / `iconSize` | `Map/MapControlBar.swift:48-49` | 50 / 20 medium |

**The project already has a UI spec:** `docs/specs/JRM_FLIGHTY_UI_REFACTOR_SPEC.md`.

- §6.3 sets the type roles.
- §6.4 sets:
  - the spacing scale 4/8/12/16/20/24/32
  - radii: control 12, card 18–20, sheet 28–32, pill full
  - card padding 16–20
  - minimum list row height 44
  - map-edge controls 48
- §6.5 sets materials.
- §14.2 is the visual acceptance checklist.

The code never turned §6.4's spacing scale into a Swift token. Name clashes in the
existing tokens:

- `WorkspaceMenuMetrics.cardCornerRadius` (28) is really the spec's *sheet* radius, but
  it has the same name as `RailStyle.cardCornerRadius` (20).
- `touchSide` (44) duplicates `RailStyle.minimumTouchTarget` (44).

Token adoption by feature folder:

- Journeys uses the tokens most.
- JourneyEditor uses only `RailRowPressStyle`.
- Import uses only `railMinimumTouchTarget`.
- Timetable, Settings and Sharing use none.

The comment on `RailStyle.cardCornerRadius` already states the rule this audit
enforces: 同层组件只从 Token 取值，不临时发明 13、17、19 等随机间距 (components on the
same layer take their values only from tokens and never improvise one-off spacings
such as 13, 17 or 19). The gap is that most of the app does not route through these
tokens. In particular:

- Only one stock `.bordered` button in the app gets `.railMinimumTouchTarget()`
  (`Workspace/RailWorkspaceView.swift:2704`).
- About 25 rows in the editor spell `minHeight: 44` as a literal.
- `RailType` is used by Stats and the panel. It is not used by the editor, Import or
  the sheets.

## 2. Findings, ranked by user impact

Ranking: **P1** is something a reader sees or touches on every visit, or a
convention break between screens. **P2** is visible drift within a screen family.
**P3** is code hygiene that causes the next drift.

### P1. Every sheet dismisses differently (title bar convention)

There are 26 toolbar items in the app. The ones that only *leave* a sheet, with no
save, use five different conventions:

| Pattern | Where |
|---|---|
| **"Done"** text, trailing (`.confirmationAction`) | Map Layers `Map/MapLayersView.swift:170`, Map Info `Map/MapInfoView.swift:61`, Hide trips `Workspace/TripHideSheet.swift:62`, Stats scope `Statistics/StatisticsScopePicker.swift:61`, Line search `JourneyEditor/EditorLineSearchView.swift:203` |
| **"Done"** text, **leading** (`.cancellationAction`) | Fill details `JourneyEditor/EditorFillDetailsSheet.swift:73` |
| **"Close"** text, trailing | Timetable trip `Timetable/TimetableTripDetailView.swift:157`, Train research `Timetable/TrainResearchView.swift:144` |
| **xmark** icon, leading, labelled "Close" | Journey menu `Journeys/JourneyMenuView.swift:96` |
| **xmark** icon, leading, labelled **"Back"** | Settings and Data Library `Workspace/UtilityDestination.swift:90` (key `utility.close`). The icon says *close* and the spoken label says *back*. |
| **xmark circle** (`SheetCloseButton`), trailing | Line card `Map/RailwayLineCardView.swift:159`, Station card `Map/StationCardView.swift` (custom header) |
| No dismiss button; swipe only | Ride detail `Journeys/RideDetailView.swift:65` (it has only "Edit") |

Sheets that edit something are consistent: "Cancel" leading and "Save"/"Apply"
trailing. That covers `JourneyGroupPicker.swift:118/122`, `ShareComposer.swift:219`,
`DataImportView.swift:30`, `TransferGuideImportView.swift:91`,
`StationPickerView.swift:254`, `ServicePatternPickerView.swift:268`,
`TicketScanView.swift:45`, `JourneyEditorManualEntry.swift:172` and
`ServiceRangeEditorView.swift:133`. **The exception is the main trip editor.** It hides
the navigation bar (`JourneyEditorView.swift:68`) and draws its own header: Cancel,
a `.headline` title and a semibold Save, with literal padding 16/10
(`JourneyEditorView.swift:257-279`). Its title therefore sits at a different height
and weight from every other sheet title. [shot: light-editor-new, light-editor-edit]

### P1. Title size differs between sheets

All 30 pushed pages and sheets set `.inline`, except two:

- The Settings root (`Settings/SettingsView.swift:62`)
- The Data Library (`Import/DataManagerView.swift:77`)

These two leave the default, so they show a **large** title. They are the only large
titles in the app, and they are reached from the same gear menu as sheets that use
inline titles. [shot: light-settings, light-data]

There are three custom headers that are not navigation bars:

- The docked panel (`Workspace/BottomChrome.swift:310`: 20 pt bold, `@ScaledMetric`)
- `PopupMenuHeader` (`Journeys/RideSheet.swift:291`: the same 20 pt bold)
- The editor header (`.headline`, about 17 pt semibold)

The first two match each other. The editor's does not.

### P1. Sheet heights and grabbers are set per sheet

Sheets are presented in 16 places. They have three different detent behaviours:

- **Half sheet (`.medium`/`.large`) through the token:** Map Layers
  (`MapLayersView.swift:178`), Map Info (`MapInfoView.swift:69`), ride chooser
  (`RideChooserView.swift:82`).
- **Detents written out by hand:** station card (`StationCardView.swift:289`), journey
  menu (`JourneyMenuView.swift:123`, skipped on Catalyst), the resident panel
  (`BottomChrome.swift:528`). Each of these also hides the drag indicator.
- **Nothing set, so a full-height page sheet:** Settings, Data Library, Hide trips,
  Stats scope (a popover), ride detail, the editor and every editor sub-sheet
  (`JourneyEditorView.swift:128/131/136`, `EditorFillDetailsSheet.swift:80/96`),
  Timetable (`ServicePatternPickerView.swift:274/277`,
  `TimetableTripDetailView.swift:172`), and Import (`TransferGuideImportView.swift:80`).

As a result, small pickers such as Hide trips open full height while the larger Map
Info opens half height. Nothing hides the grabber on a sheet that has `.medium`, and
nothing shows one on the custom panels. [shot: light-layers, light-info, light-station]

### P1. Primary buttons come in four shapes

- **Capsule** (`RailCapsuleButtonStyle`, 32 pt visual inside a 44 pt hit area): the
  journey card's primary and secondary actions (`Journeys/JourneyComponents.swift:671/716`)
  and ride detail when it is given a height (`RideDetailView.swift:13`).
- **Stock `.borderedProminent`**: the ride detail fallback (`RideDetailView.swift:17`,
  plus `.frame(minHeight: 44)`) and its actions at `:1267/:1281`, ticket scan
  (`TicketScanView.swift:128`), the editor map panel (`EditorMapPanel.swift:172`),
  Import (`DataImportView.swift:354/378/398`, `TransferGuideImportView.swift:544/569/580`
  with literal `.padding(.vertical, 10)`), passport (`PassportWorkspaceView.swift:212`)
  and share (`ShareComposer.swift:285`, the only `.controlSize(.large)`).
- **Stock `.bordered`**: the empty and search-miss states (`RailWorkspaceView.swift:1777`,
  `:2704`, `:2758`), which do have `.railMinimumTouchTarget()`. The overdue-trip actions
  (`JourneyListRow.swift:244`, `.controlSize(.small)`) do not.
- **`.borderless` / `.plain` text** for inline actions: `EditorDateTimeFields.swift:363`,
  `JourneyEditorManualEntry.swift:53`, `ServicePatternPickerView.swift:235/311`, and
  about 17 `.plain` sites.

The same kind of action, such as "the one thing to do next on this card", is a 32 pt
capsule on the journey card and a stock ~34 pt rounded rectangle in Import and ticket
scan. [shot: light-upcoming-expanded, light-selected]

### P1. Touch targets under 44 pt

| Where | Size | Note |
|---|---|---|
| Map trip-cap notice pill `Workspace/RailWorkspaceView.swift:3491-3497` | about 30 pt tall (footnote and vertical padding 7) | A `Button(.plain)` with no `railMinimumTouchTarget`. It also uses a literal `.padding(.top, 54)`. |
| Platform keypad `JourneyEditor/JourneyEditorManualEntry.swift:69,81` | 44 × **40**, gap 6 | It sits in a popover. A height of 44 would also need the grid spacing to change. |
| Overdue-trip actions `Journeys/JourneyListRow.swift:244-245` | `.bordered` + `.controlSize(.small)`, about 28 pt | No min height. |
| Remove-via icon `JourneyEditor/EditorStationsSection.swift:85-93` | `.title3` glyph, `.plain`, no frame, about 24 pt wide | The row is 44 tall, but the button's own width is the glyph's. |

The empty and search-miss state buttons (`RailWorkspaceView.swift:1777`, `:2758`) do
carry `.railMinimumTouchTarget()`. A first-pass report said they did not; the source
shows they do.

Everything else checked meets 44:

- `SheetIconButton`
- the search field (`JourneySearchField.swift:75`)
- the playback transport (`PlaybackTransportBar.swift:122…397`)
- the scope picker rows
- the editor rows (`minHeight: 44`, about 25 sites)
- the map control bar (50 pt)

### P2. Horizontal margins: 12, 14 and 16 are all used for "the edge of the content"

- **16:**
  - Through the token: panel, search field, passport.
  - As a literal: ride detail (`RideDetailView.swift:230`, `.padding(16)` on cards at
    `:272/:360/:465/:841/:869/:978/:1023/:1182`), editor header
    (`JourneyEditorView.swift:276`), station picker (`StationPickerView.swift:578/638`),
    scope picker (`StatisticsScopePicker.swift:35/48/55`), share (`ShareComposer.swift:269/290/419`).
- **12:**
  - Journey cards (`JourneyComponents.swift:121/421`, `.padding(12)`)
  - Map chrome (`WorkspaceMapChrome.swift:80/92/125/132`)
  - Editor map panel (`EditorMapPanel.swift:57/87/91`)
  - Passport rows (`PassportCardStyle.swift:486`)
- **14:**
  - Stats year bar (`StatisticsYearBar.swift:36`)
  - Editor map callout and manual entry (`EditorMapPanel.swift:155`, `JourneyEditorManualEntry.swift:107`)
- **18:** passport card (`PassportCardStyle.swift:263`)

Card *inner* padding is 12 on the journey card and 16 on the ride-detail card.
These are the same trip, seen as a card and then opened, so the content shifts by
4 pt on open. [shot: light-selected vs light-detail]

### P2. Stack spacing uses 16 distinct values

The 291 literal `spacing:` values in the app take these values:

| Spacing | Uses |
|---|---|
| 8 | 40 |
| 6 | 36 |
| 2 | 34 |
| 10 | 33 |
| 4 | 31 |
| 12 | 26 |
| 3 | 22 |
| 0 | 19 |
| 5 | 15 |
| 14 | 12 |
| 16 | 8 |
| 1 | 7 |
| 9 | 3 |
| 7 | 2 |
| 18 | 2 |
| 24 | 1 |

Odd values (1, 3, 5, 7, 9) make up 49 of them. The same role gets different values:

- **Label over value, two-line field:**
  - 3 at `EditorFields.swift:19`, `EditorDateTimeFields.swift:20/127`, `EditorLineSearchView.swift:120/250`
  - 2 at `StopEditorView.swift:17`, `EditorStationsSection.swift:72/109`, `StationPickerView.swift:335/805/839`
  - 5 at `LocalLineServicesSection.swift:22`, `JourneyCompletionView.swift:160`, `TimetableTripDetailView.swift:66/106/120/141`
- **Card stacks:**
  - 7 at `JourneyComponents.swift:97`
  - 9 at `JourneyComponents.swift:443`
  - 5 at `RideDetailView.swift:413`, `RideCard.swift:343/479`
- **Empty states:**
  - 10 at `JourneyWorkspaceStates.swift:18` and `RailWorkspaceView.swift:1765/2699/2752`
  - 8 at `JourneyWorkspaceStates.swift:59`

### P2. Chips and badges: five paddings for one shape

| Element | Padding (horizontal / vertical) |
|---|---|
| Journey chip `JourneyComponents.swift:44-45` | 9 / 5 |
| Ride detail badge `RideDetailView.swift:792-793` | 5 / 1 |
| Timetable badges `ServicePatternPickerView.swift:347-369` | 6 / 2 |
| Station suggestion chip `StationPickerView.swift:650-654` | 12 / 7, min height 44 |
| Auto-filled source tag `AutoFilledStationLabel.swift:11-12` | 8 / 4 |
| Sheet badge `RideSheet.swift:266` | 5, digits at a fixed 11 pt bold (`:263`) |

Corner radii for small blocks are 8 (`JourneyEditorManualEntry.swift:84`), 12
(the scope picker literals `StatisticsScopePicker.swift:37/50/162`, which equal the
token but are typed in), 14 (`EditorMapPanel.swift:156`) and 16
(`EditorMapPanel.swift:56`). The share composer card is 18 (`ShareComposer.swift:308`).
The tokens are 12, 20 and 28.

### P2. Element heights

- **Multi-line text editors:** min height 120 (`JourneyCompletionView.swift:123`),
  160 (`:334`), 140 (`DataImportView.swift:92`), and a fixed 220
  (`StationPickerView.swift:320`).
- **Progress and track bars in Stats:** 7 (`StatisticsComponents.swift:122`), 8
  (`:397`) and 5 (`PassportCardStyle.swift:604`) for the same "share of total" bar.
- **Rows:** editor rows say `minHeight: 44`. Transfer-guide rows have none
  (`TransferGuideImportView.swift:212/285/425`). Map Info rows use vertical 4
  (`MapInfoView.swift:246`) against the token's 6.
- **Segmented pickers:** all ten are stock `.segmented` (consistent).

### P2. Captions: three styles for one secondary-line role

The type scale in use is:

| Style | Uses |
|---|---|
| caption | 136 |
| footnote | 105 |
| subheadline | 55 |
| caption2 | 41 |
| headline | 27 |
| body | 11 |
| title3 | 6 |
| title2 | 5 |
| callout | 3 |
| largeTitle | 2 |

A secondary line under a row title is:

- `.caption` in the editor (`EditorFields.swift:21`, `LocalLineServicesSection.swift:31/49`,
  `EditorRouteSection.swift:265/331`, `StationPickerView.swift:813/817`)
- `.footnote` for section hints (`EditorTimeSection.swift:25`, `EditorTripDetailsSection.swift:23/57`,
  `JourneyEditorDetails.swift:76`)
- `.caption` again two blocks lower in the same file (`JourneyEditorDetails.swift:165`)

Every fixed `.system(size:)` font in interactive UI is either scaled through
`@ScaledMetric` (both panel titles) or is an icon. The only fixed text is the sheet
badge digits (`RideSheet.swift:263`, 11 pt). The share card and widget artwork use
fixed sizes on purpose, because they render to bitmaps.

### P2. Icon weights: three specs for "a glyph in a round control"

| Control | Glyph |
|---|---|
| Map control bar `MapControlBar.swift:327` | 20 pt **medium**, in a 50 pt control |
| Sheet header buttons `RideSheet.swift:189` | 18 pt **semibold**, in a 32 pt circle |
| Search field and journey row icon `JourneySearchField.swift:26/65`, `JourneyComponents.swift:760` | 18 pt **regular** |

The scale and weight differences are visible side by side when the panel is at
medium over the map. [shot: light-map-medium]

### P2. Dark mode

There are no hard-coded light-only backgrounds in interactive UI.

White text on the accent fill is fine: the platform keypad
(`JourneyEditorManualEntry.swift:85`) and the selected suggestion chip
(`StationPickerView.swift:652`) use it, and the app has no asset accent colour, so the
accent is system blue in both modes.

The places to check are:

- **Gray and orange opacity fills behind badges:** `ServicePatternPickerView.swift:349-369`.
  These are not semantic fills, so their contrast against dark grouped backgrounds is
  unverified.
- **A shadow at black 0.12:** `EditorMapPanel.swift:157`. It disappears in dark mode,
  which is harmless.

[shot: dark-*]

### P2. Empty, loading and error states: four treatments

- **Loading:** `ProgressView` plus `.headline`, spacing 10 (`Journeys/JourneyWorkspaceStates.swift:16-28`).
- **Unavailable:** the only `ContentUnavailableView` (`:55-76`).
- **Upcoming empty:** hand-built, with a `.largeTitle` tertiary glyph, a `.subheadline`
  message, a `.bordered` button and padding 24 (`RailWorkspaceView.swift:1766-1790`).
- **Search miss:** text only, no glyph (`:2748-2760`).
- **Search spinner:** a bare `ProgressView` (`:2740`).
- **Detail loading:** `ProgressView(title).padding()` (`RideDetailView.swift:196`).

### P2. Same list, different rows and headers

- **Row insets:** every list uses `JourneySummaryRow`. The ride chooser insets it
  `EdgeInsets(5, 12, 5, 12)` (`RideChooserView.swift:109`), while the lists use the
  tokens 6/16 (`JourneyListRow.swift:95-98`).
- **Date headers:** History groups by date with stock `Section(day.date)` headers
  (`RailWorkspaceView.swift:2721`). Upcoming has no headers and shows the date inside
  each row.
- **Card titles:** the ride card uses `.subheadline.semibold` for section titles and the
  ride detail page uses `.headline` (`RideDetailView.swift:453`). The ride detail header
  is `.title2.bold` (`:252`) and the line card header is `.title2.semibold`
  (`RailwayLineCardView.swift:114`).

### P2. Stats cards are one family, but a different density

Every dashboard card goes through one container, `statisticsCard()` →
`passportCard(.plain)` (`Statistics/StatisticsComponents.swift:17`,
`PassportCardStyle.swift:251-263`). That container uses `RailStyle.cardCornerRadius`
and glass, with padding **18**, which is within the spec's 16–20. The journey card is
12 (`JourneyComponents.swift:421`) and the ride detail is 16. So the three card
surfaces are 12/16/18, and only the journey card is outside the spec.

There are further splits inside Stats:

- **Card stacks:** sibling cards use stack spacing 14 and 16 (`StatisticsDashboardContent.swift`).
- **Metric grid:** columns 16 and rows 18 (`PassportCardStyle.swift:567-570`).
- **Card titles:** `.headline` vs `.subheadline.semibold` vs `.subheadline.bold`.

### P2. Editor copy and labels

- **Cancel keys:** Cancel comes from four localization keys: `ios.cancel`,
  `ios.newTrip.cancel`, `ios.ticket.cancel` and `pickerText("cancel")`.
- **Unlabelled field:** the service section's train-number `TextField` has a placeholder
  but no label (`EditorServiceSection.swift:20`). `EditorFields.swift:6-14` documents
  this as the pattern to avoid, because the label disappears once the field is filled.

### P3. Mac Catalyst

Layout is decided by window size, not idiom (`WorkspaceLayout.swift:72`). There are
Catalyst branches that change presentation:

- `railHalfSheetDetents` is empty, so every half sheet is a form sheet.
- The journey menu drops its detents (`JourneyMenuView.swift:122`).
- The station card has five branches (`StationCardView.swift:288/299/343/354/359`).
- Map toolbar items are hidden (`MapControlBar.swift:427/435/452/468`).

On Mac, Settings and the Data Library would show an xmark at leading with the spoken
label "Back", where Mac users expect Close or ⌘W. **This pass did not run Catalyst.**
Only one heavy job may run machine-wide, so the Catalyst findings are static only.

### P3. Literal 44s and 16s where tokens exist

- Literal `44` touch sizes: about 40 sites (`frame(minHeight: 44)` 21, `width: 44, height: 44` 12, `minWidth: 44, minHeight: 44` 4, and others).
- Literal horizontal 16: 8 sites, plus 12 bare `.padding(16)`.
- Literal 12 corner radii: 3 sites.

Each one is correct today and is how the next drift starts.

## 3. Screens captured

These are from the iPhone 17 simulator through app-control `launch`, using an isolated UUID store loaded with the `train-store` and `train-store-tw` samples (229 trips). The **before** set is `main` at 3313613ab, built from a clean worktree. The **after** set is this branch after D10 steps 1–5. The files are under `docs/maintenance/screenshots/ui-consistency-audit/{before,after}/<name>.jpg`, downscaled to 600 px.

| Screen | Names |
|---|---|
| Map with the panel at medium | light-map-medium, dark-map-medium |
| Journeys: Upcoming, History and search | light-upcoming-expanded, dark-upcoming-expanded, light-history-expanded, light-search |
| Selected trip (ride card) | light-selected |
| Stats | light-stats-expanded, dark-stats-expanded |
| Settings, Data Library, Import | light-settings, dark-settings, light-data, light-import |
| Map Layers, Map Info, video export, new trip | light-layers, light-info, light-video, light-editor-new |

Two screens were not captured:

- **Station card.** The `RAILMAP_UI_TEST_SHEET=station` hook did not open it in either build, so the before and after shots both show the map. This is a limit of the hook, not a regression.
- **Stats cards.** Stats showed only the replay card in both builds, because statistics were still computing when the shot was taken.

## 4. Decisions, with options (for the user, through the main chat)

An architect pass drafted these options. It worked from the code findings above, the project spec, the Apple HIG, other apps and open-source design systems (§6). Each decision lists 2–4 options with examples, trade-offs, fit with the spec, and a recommendation. **The user chooses.** Nothing is applied.

Facts that constrain every decision:

- Deployment target is iOS 17.0; iOS 26 APIs are already gated with `#available` (14 sites, e.g. `GlassStyle.swift:76` `.glass`). Any iOS 26-only chrome needs an iOS 17–25 fallback (spec §6.5 last bullet).
- Spec §6.4 is the token source of truth: spacing 4/8/12/16/20/24/32; radius control 12 / card 18–20 / sheet 28–32 / pill full; card padding 16–20; row min 44; map-edge control 48. **The draft audit §4 contradicts it three times**: a 2/4/8/12/16/24 scale (drops 20 and 32, adds 2), card padding 12 (spec says 16–20), and it leaves `MapControlBar.side` at 50 (spec and §7.7 say 48).
- Spec §0.1/§6.5: resident sheet has **no grabber**, large top-left title, top-right actions; §5.2.1 Network header `[Data] [Settings] [完成]`; §5.1.4 copy `保存旅程` not `完成`; §7.6 one filled primary per group, destructive never paired as primary.
- HIG (synthesis): Done pairs with Cancel; "Back" is not for dismissing a sheet; use the standard Close button, not text "Close"/"Back"; resizable sheets include a grabber; ≥44 pt hit regions.
- Two other sessions edit `JourneyEditor/*` (`claude/goofy-haibt-1f061c`, adds a `.toolbar` but keeps the custom `header`) and trip detail/map (`claude/trip-notes`). D10 keeps those files for last.

---

### D1 Title size

| Option | Definition | Who does it | Changes here | Pros / cons | Spec fit |
|---|---|---|---|---|---|
| A | Inline everywhere; Settings/Data get `.inline` | Google Maps 2025 sheets (compact headers) [9to5google](https://9to5google.com/2025/03/07/google-maps-iphone-sheet-redesign/) | 2 lines: `SettingsView.swift:62`, `DataManagerView.swift:77` | + Matches the other 28 pages. − Two Form roots lose the scroll-collapsing large title that HIG assigns to the top of a stack | Neutral: spec is silent on Utility title size |
| B | Large on the two Utility roots (they are standalone `NavigationStack`s per spec §4.1:463), inline on every other push/sheet | HIG nav-bars: large title at the top of a stack, standard elsewhere (synthesis, unverified snippet) | 0 lines; document the rule | + HIG-literal; Utility roots are real stack roots. − Reached from the same gear menu as inline sheets, so the reader sees two sizes from one menu | Fits §4.1 (independent stacks) |

**Recommendation: A.** The resident panel already owns the only "large title" in the product (spec §0.1, `BottomChrome.swift:310`); Utility sheets are satellites of it, and one inline rule has no exceptions to drift from.

### D2 View-only sheet dismissal (and ride detail)

| Option | Definition | Who does it | Changes here | Pros / cons | Spec fit |
|---|---|---|---|---|---|
| A | System Close: `Button(role: .close)` in `.topBarTrailing`; iOS 17–25 fallback = `SheetCloseButton` (xmark circle), same placement, same identifier | HIG sheets/toolbars ("use the standard Back and Close buttons"); iOS 26 renders Close as X glyph [MacStories](https://www.macstories.net/stories/ios-and-ipados-26-the-macstories-review/3/); Google Maps X trailing "matches Apple Maps" [9to5google](https://9to5google.com/2025/03/07/google-maps-iphone-sheet-redesign/) | ~12 toolbar sites (Layers, Info, Hide, Scope, Line search, Fill details, Timetable ×2, JourneyMenu, Utility, Line/Station cards); one `railSheetClose()` helper in `Design/`; Utility label "Back" → "Close" | + HIG-aligned, one-handed trailing reach, Catalyst ⌘W/Esc via `.keyboardShortcut(.cancelAction)` already on `SheetCloseButton`. − Rendering of `.close` on iOS 26 unverified; 4 UI-test ids change | Matches §14.4 (closable without swipe) |
| B | "Done" text trailing everywhere | Current majority (5 sheets) | ~7 sites | + Smallest diff. − HIG: Done implies a completed task and pairs with Cancel; 5.1.4 says avoid `完成` for actions | §5.2.1 shows `[完成]` on the Network header, so Done is tolerated there only |
| C | Keep custom `SheetCloseButton` (32 pt circle, 18 semibold xmark) everywhere incl. iOS 26 | Line/Station cards today | ~10 sites | + Visually identical on all OS versions. − Diverges from the system glass Close on iOS 26, which the spec's "use system Liquid Glass" bullet (§14.2) discourages | Weak |
| D | Swipe-only, no button | Transit 5.0 swipe-down [iPhoneInCanada](https://www.iphoneincanada.ca/2018/08/31/transit-app-gets-major-redesign/) | remove ~12 | − Fails §14.4 and the UI-test harness comment at `UtilityDestination.swift:96` | Fails |

**Ride detail:** add the same trailing Close and keep "Edit" as the only other item; a page sheet with no button fails §14.4. **Exception:** the Network-mode header keeps the spec's `[完成]`.

**Recommendation: A**, because it is the only option that satisfies both HIG and the spec's "system first" rule while remaining a single helper with an iOS 17 fallback.

### D3 Editing-sheet chrome (trip editor header) — chrome only

| Option | Definition | Who does it | Changes here | Pros / cons | Spec fit |
|---|---|---|---|---|---|
| A | System navigation bar: inline title, `.cancellationAction` Cancel, `.confirmationAction` `保存旅程` (prominent on iOS 26 via `.buttonStyle(.glassProminent)` gated); delete the custom `header` | HIG toolbars (".prominent style for key actions such as Done or Submit"); all 9 other editing sheets in this app | `JourneyEditorView.swift:68,257-279` (~30 lines), identifiers `newTripCancel/newTripSave` kept | + Same title height/weight as every sheet; ⌘S stays. − Collides with the editor relayout branch which keeps `header`; must land after merge | §5.1.4 copy rule |
| B | Keep custom header, restyle to match `PopupMenuHeader` metrics (20 pt bold scaled, 16/12 insets, `SheetIconButton` sizes) | Resident panel + `RideSheet.swift:291` | ~15 lines in the same file | + No dependency on nav-bar behaviour under `.scrollDismissesKeyboard`. − Third header implementation; Save never gets the system prominent treatment | Neutral |
| C | Shared `railEditingChrome(title:save:)` modifier used by the trip editor **and** the 9 other editing sheets (Cancel-key unification: 4 keys → `ios.cancel`) | Backpack-style single component [backpack-ios](https://github.com/Skyscanner/backpack-ios) | A + ~10 toolbars touched, 3 localization keys removed | + One place for Cancel/Save/discard-confirm. − Larger blast radius into Import/Timetable now | §5.1.4 |

**Recommendation: A now, C as the follow-up** once the editor branch merges; the chrome should be the system bar because every sibling sheet already is.

### D4 Sheet heights and grabber

| Option | Definition | Who does it | Changes here | Pros / cons |
|---|---|---|---|---|
| A | Rule by content class: pickers/info/menus → `railHalfSheetDetents()` + grabber visible; editing flows, Utility, Timetable research, Import → `.large`; resident panel + Station/Line cards keep hand-built detents with hidden grabber (spec §0.1) | HIG sheets ("Include a grabber in a resizable sheet"); iOS 26 inset half sheets [MacStories](https://www.macstories.net/stories/ios-and-ipados-26-the-macstories-review/3/) | Hide trips, Stats scope, Journey menu → half+grabber (3); editor sub-sheets stay full; `railSheet(.half/.full)` modifier in `GlassStyle.swift` (~25 lines) | + Height follows a rule. − Catalyst still no-op (documented at `GlassStyle.swift:175`) |
| B | Everything half+grabber except editing flows | — | ~8 sites | − Settings/Data at medium hide half a Form; §14.2 wants Full to fill |

**Recommendation: A.** It is the smallest rule that leaves the spec's no-grabber surfaces untouched and makes the three small pickers behave like Map Info.

### D5 Primary/secondary button system

| Option | Definition | Who does it | Changes here | Pros / cons | Spec fit |
|---|---|---|---|---|---|
| A | `RailCapsuleButtonStyle` everywhere via statics `.railPrimary / .railSecondary / .railTertiary` (ButtonStyle extension); 44 pt touch built in | Fluent ButtonStyle enum accent/outline/subtle [fluentui-apple](https://github.com/microsoft/fluentui-apple); Backpack primary/secondary/link | `ControlSizing.swift` +30 lines; 14 `.borderedProminent` + 11 `.bordered` sites (RideDetail, TicketScan, EditorMapPanel, DataImport ×3, TransferGuide ×3, Passport, Share, JourneyListRow, RailWorkspaceView ×3) | + One shape, SwiftUI-idiomatic call sites, no wrapper view to thread labels through. − Custom fill, not system glass on iOS 26 | §7.6 (one filled primary) |
| B | Stock `.borderedProminent`/`.bordered` + `.railMinimumTouchTarget()` | Current majority (25 sites) | journey card ×2, ride detail ×1 switch to stock; add touch modifier at ~6 sites | + System look for free, incl. Liquid Glass. − Journey card loses its 32 pt capsule that aligns with `SheetIconButton` circles | Neutral |
| C | iOS 26 `.glassProminent`/`.glass`, iOS 17–25 falls back to A's capsule | Apple "adopting Liquid Glass" (use `.glass`/`.glassProminent`, not custom glass) | A + `#available` switch inside the statics (~15 lines) | + Future-proof and system-material. − Two renderings to QA; glass on a solid Form background can look odd (spec §6.5 says content cards are not glass) | §6.5 ambiguous |
| D | Backpack-style `RailButton(style:size:)` wrapper view | [backpack-ios](https://github.com/Skyscanner/backpack-ios) `BPKButton`; Fluent size categories 52/40/28 | New view + 27 call-site rewrites incl. label plumbing | + Lintable (`bpk_button` flags bare `Button(`). − Breaks `Button(role:)`, `.keyboardShortcut`, menus; largest diff | Neutral |

**API shape:** ButtonStyle statics (A/C), not a wrapper (D): every site keeps `Button {}` with its roles, shortcuts and identifiers.

**Recommendation: A**, with C's `#available` glass branch deferred until one screen is QA'd on iOS 26 — the capsule is already the app's signature control and gives 44 pt by construction.

### D6 Spacing scale, naming, card padding

| Option | Definition | Who does it | Changes here | Pros / cons | Spec fit |
|---|---|---|---|---|---|
| A | Spec scale, value-encoded names: `RailSpacing.s4/s8/s12/s16/s20/s24/s32` + `s2` hairline; semantic aliases `screenInset=s16`, `cardPadding=s16`, `rowVertical=6` (kept as an explicit exception token), `labelValueGap=s2` | Kickstarter `Spacing.unit_01…` + semantic radii aliases [ios-oss](https://github.com/kickstarter/ios-oss); Fluent GlobalTokens size20… [fluentui-apple](https://github.com/microsoft/fluentui-apple) | New `Design/RailSpacing.swift`; absorb `WorkspaceMenuMetrics` generic members (`horizontalInset`, `contentSpacing`, `listRowVerticalInset`, `fieldHorizontalInset`, `subtitleSpacing`); 291 spacings + 165 paddings migrate screen by screen | + Value in the name prevents the "is `m` 12 or 16?" question; aliases carry meaning. − Odd values 1/3/5/7/9 (49 sites) must round, visible 1-pt shifts | **Exact spec §6.4** |
| B | T-shirt names `xxs…xl` as in draft §4 (2/4/8/12/16/24) | Backpack `BPKSpacing` [backpack-ios](https://github.com/Skyscanner/backpack-ios) | same files | − Drops spec's 20 and 32; readers must memorise the mapping | **Contradicts §6.4** |
| C | Semantic-only (`inset/gap/sectionGap…`) from `@Environment` | Adevinta Spark `LayoutSpacing` (synthesis) | same + environment plumbing | − Every new role needs a new token; environment indirection is overkill for a one-theme app | Neutral |

**Card padding:** spec says 16–20. Journey card at 12 (`JourneyComponents.swift:121/421`) is the off-spec one; ride-detail at 16 is on-spec. Unify at **16** (`cardPadding = s16`), not the draft's 12. Stats card 18 → 16 too, so `.padding(cardPadding)` is one value. Map chrome edge stays 12 (spec §6.4 "partial-sheet-edge-margin visually 12–16", a different role: `mapChromeInset = s12`). Map control side 50 → **48** (`MapControlBar.swift:48`, spec §7.7).

**Recommendation: A at 16**, because it is the spec's own scale and the two readers of a token (human and lint) both get the value without a lookup.

### D7 Radius set

| Option | Definition | Changes here | Pros / cons |
|---|---|---|---|
| A | `RailRadius.control 12 / card 20 / sheet 28` + `.pill` (Capsule); rename `WorkspaceMenuMetrics.cardCornerRadius` → `RailRadius.sheet`; `chromeCornerRadius` (Playback only) → `card` (both 20) | 8/14/16/18 literals → `control` (8,14 at `ManualEntry:84`, `EditorMapPanel:156`) or `card` (16,18 at `EditorMapPanel:56`, `ShareComposer:308`); ~10 sites + 3 typed-in 12s | + Three values, depth order preserved (§6.4). − 8 → 12 on the keypad keys is visible; they may want `.pill` instead |
| B | Keep both names, alias `WorkspaceMenuMetrics.cardCornerRadius = RailRadius.sheet` | 1 line | − Clash survives; the next author picks the wrong "card" |

**Recommendation: A.** The clash is a naming bug (28 is the sheet radius by the spec's own table), and 20 vs 20 for chrome/card is a duplicate, not a distinction.

### D8 Type roles for secondary text, card titles, glyph weights

| Option | Definition | Who does it | Changes here | Pros / cons |
|---|---|---|---|---|
| A | Secondary line = `.subheadline` + `.secondary` (spec §6.3 "元数据 .subheadline/.caption"); tertiary tag/badge = `.caption`; drop `.footnote` (105 sites) | Spec §6.3 | Editor hints (`EditorTimeSection:25`, `EditorTripDetailsSection:23/57`, `JourneyEditorDetails:76`) and 100 others | + Two roles, both in spec. − Secondary lines grow 13→15 pt; dense editor rows get taller (acceptable: §10.1 prefers wrap over shrink) |
| B | Secondary = `.footnote`, tertiary = `.caption`; `.subheadline` only for status/semibold | HIG typography (Footnote 13 / Caption 12) | ~55 `.subheadline` metadata sites | − Footnote is not in the spec's metadata row |
| C | Add `RailType.Role.secondary/.tertiary` carrying both font and lineLimit, extending the existing contract in `RailType.swift` | Fluent/Backpack text-style tokens | `RailType.swift` +2 cases; call sites use `.railText(.secondary)` | + Greppable like `railType`. − Adds font to a modifier that today sets only bounds; coordinate with its "roles not sizes" doc |

**Card titles:** `.headline` for card/row titles (17 semibold), `.title3.bold` for station names (spec), `.title2.bold` for train numbers and the sheet-card headers (Line card `.title2.semibold` → bold).

**Glyphs:** one family — `18 semibold` in 32 pt circles (today's `SheetIconButton`), `20 semibold` in the 48 pt map control (`MapControlBar.swift:327` medium → semibold), 18 regular only for inline list glyphs (search field, row icon). Exposed as `WorkspaceMenuMetrics.iconSize` + a `.railGlyph(.control/.mapControl)` modifier.

**Recommendation: A for roles, C for the API** (extend the existing contract rather than invent a second), because the spec names exactly those two metadata styles and the repo already has the role-based type modifier.

### D9 Enforcement guard

| Option | Definition | Who does it | Changes here | Pros / cons |
|---|---|---|---|---|
| A | `ios/tools/check-ui-tokens.sh` (bash + embedded `python3 -I`, baseline file `ios/tools/ui-token-baseline.txt`, fails on growth), wired as a `step` in `run-regression-guards.sh` | This repo's `check-ui-test-identifiers.sh` pattern; Kickstarter: "No need for custom rules (yet)" [ios-oss](https://github.com/kickstarter/ios-oss) | 1 script (~120 lines), 1 baseline, 1 line in the runner | + Zero new toolchain, same shape as the existing guard, regex over lines is enough for `.padding(` / `spacing:` / `cornerRadius:` / `.frame(…44` / `.buttonStyle(.bordered` / `.font(.system(size:`. − No editor inline warnings |
| B | SwiftLint `custom_rules` with `--baseline`, as Backpack does | [backpack-ios](https://github.com/Skyscanner/backpack-ios) `.backpack-ios-rules.yml`; SwiftLint 0.65.1 baseline support | `.swiftlint.yml`, Homebrew dependency, Xcode build phase or runner step | + `match_kinds: number` skips strings/comments; IDE feedback. − New tool for a repo with none; `Diagnostics/`, ShareCard, widget exclusions must be expressed twice (lint + build phase) |
| C | A now, B later if the team adopts SwiftLint for other reasons | — | A | + No commitment |

**Recommendation: A.** The repo's rule is "every fix gets a permanent guard" in the existing runner, and the token checks are line-regex problems that do not need an AST.

### D10 Rollout order

Constraints: `JourneyEditor/*` (editor relayout) and trip detail/map (trip notes) are open in other sessions; the baseline guard lets cleanup land per screen; each commit updates UI-test ids it touches and lowers the baseline.

| Option | Order | Pros / cons |
|---|---|---|
| A | **Tokens first, untouched screens next, contested screens last.** 1) `Design/RailSpacing.swift`, `RailRadius`, button statics, `railSheetClose`, `railSheet`, guard + baseline (no call-site changes; baseline = today). 2) Map chrome + Settings + Data (D1, D2, D6 map inset, D7 rename, control 48). 3) Stats/Passport + Sharing (padding 16, bar heights, button statics). 4) Journeys list/card/menu/Hide/Scope (card padding 16, capsule statics, half+grabber). 5) Timetable + Import (Close, buttons, rows). 6) after merges: trip detail (Close, padding) then editor (D3, 25× `minHeight: 44`, label/value gap, Cancel key). | + No file overlap with the two live sessions until step 6; each step is one screen family = one commit + one UI-test id update. − Editor, the worst offender, is last |
| B | Worst-first: editor and ride detail now, on top of the other branches | − Guaranteed merge conflicts with two sessions |
| C | Horizontal: one modifier across the whole app per commit (all Close buttons, then all paddings…) | + Each commit is one rule. − Every commit touches the editor and detail files; blocks until both merge |

**Recommendation: A.** File ownership per step is disjoint, the guard baseline makes partial progress safe, and the two contested families get the shared tokens already in place when they merge.

---

### Where the earlier draft §4/§6 must change

1. Spacing scale → spec's 4/8/12/16/20/24/32 (+2), value-encoded names (D6-A).
2. Card padding 12 → 16 (D6).
3. Map control 50 → 48 (D6, §7.7).
4. Dismiss convention "Done" → system Close with iOS 17 fallback; Network header keeps `完成` (D2).
5. Add the grabber rule's exceptions explicitly: resident panel, Station/Line cards (D4).
6. Guard file name/shape: bash + python like the existing guard, not a bare `.py` (D9).

### Permanent guard (ships with the first fix commit)

Add `ios/tools/check-ui-tokens.sh` (bash with embedded `python3 -I`, the same shape as `check-ui-test-identifiers.sh`). Wire it in as a `step` in `run-regression-guards.sh`. It scans `ios/RailMap/**/*.swift` and skips `Diagnostics/`, `Design/` token files, the bitmap renderers (`Sharing/ShareCard.swift`, `Sharing/StatsWidgetView.swift`, `Statistics/PassportTicketFace.swift`) and `* 2.swift` files. It flags these patterns:

- a numeric literal in `.padding(` or `spacing:`
- a numeric literal in `cornerRadius:`
- `.frame(` with `44`
- `.buttonStyle(.bordered…)`
- `.font(.system(size:` outside `@ScaledMetric`
- a `ToolbarItem` dismiss that does not use the shared helper

Literals 0, 1 and 2 are exempt as hairlines, and `// ui-token-ok: <reason>` opts a line out. The baseline lists `file`, `pattern` and `normalized line` with no line numbers, so it survives edits. The check fails only on growth. Each cleanup commit lowers the baseline and updates the UI-test identifiers it touches in the same commit.

## 5. Raw inventory (literal counts, non-Diagnostics)

| Literal | Count | Distinct values |
|---|---|---|
| `.padding(...)` | 165 | 77 |
| `spacing:` | 291 | 16 |
| `.frame(...)` | 250 | 113 |
| `.font(.system(...))` | 69 | 45, 60 of them in share/widget artwork |
| text-style fonts | 391 | |
| `cornerRadius:` | 18 | 11 |
| `.buttonStyle` | 62 | 10 |
| `ToolbarItem` placements | 27 | `.cancellationAction` 12, `.confirmationAction` 9, `.topBarTrailing` 6 |
| `.navigationBarTitleDisplayMode(.inline)` | 28 | |
| `presentationDetents` | 4 | plus 3 `railHalfSheetDetents` |

Breakdown of the `.buttonStyle` values:

| Style | Count |
|---|---|
| `.plain` | 17 |
| `.borderedProminent` | 14 |
| `.bordered` | 11 |
| `RailPressStyle` | 8 |
| `RailRowPressStyle` | 6 |
| `.borderless` | 4 |
| `RailCapsuleButtonStyle` | 2 |

## 6. Sources

- **Project spec:** `docs/specs/JRM_FLIGHTY_UI_REFACTOR_SPEC.md` §0.1, §4.1, §5.1.4, §5.2.1, §6.3–6.5, §7.6–7.7, §14.2/14.4.
- **Apple HIG**, read through the JSON data endpoints of the developer site:
  - [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets): Done pairs with Cancel, Cancel leading and Done trailing, Back does not dismiss a sheet, and a resizable sheet includes a grabber.
  - [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): one primary action on the trailing side, and use the standard Back and Close buttons rather than text labels.
  - [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons): hit region at least 44×44 pt.
  - [Typography](https://developer.apple.com/design/human-interface-guidelines/typography): Footnote is 13 pt, Caption 1 is 12 pt and Caption 2 is 11 pt at the default size.
  - [ButtonRole](https://developer.apple.com/documentation/swiftui/buttonrole) has `.close` and `.confirm`.
  - [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass): use `.glass` and `.glassProminent`.
  - The navigation-bar title guidance comes from a search snippet only and is unverified.
- **Apps:**
  - [Google Maps 2025 sheets](https://9to5google.com/2025/03/07/google-maps-iphone-sheet-redesign/): Close as an X on the trailing side, "matches Apple Maps".
  - [MacStories iOS 26 review](https://www.macstories.net/stories/ios-and-ipados-26-the-macstories-review/3/): Done and Close become glyphs, and half sheets are inset.
  - Flighty: [case study](https://www.verenaortlieb.com/projects/flighty/), [Apple Behind the Design](https://developer.apple.com/news/?id=970ncww4), [search-first add](https://flighty.com/help/using-search). The [third-party SwiftUI reinterpretation](https://blakecrosley.com/guides/design/flighty) is not official.
  - [Transit 5.0](https://www.iphoneincanada.ca/2018/08/31/transit-app-gets-major-redesign/)
  - [Things Magic Plus](https://culturedcode.com/things/support/articles/2803582/)
  - [NAVITIME renewal](https://note.com/navitime_tech/n/n33bb56598235): the renewal was driven by inconsistent UI parts and was solved with a shared component vocabulary.
  - [Strava record redesign](https://press.strava.com/articles/strava-launches-redesigned-record-experience)
- **Design systems:**
  - [Skyscanner Backpack iOS](https://github.com/Skyscanner/backpack-ios): `BPKSpacing` sm 4, md 8, base 16, lg 24, xl 32; a `BPKButton(style:size:)` view; SwiftLint `custom_rules` that ban literal padding, spacing and frames and a bare `Button(`.
  - [Microsoft FluentUI Apple](https://github.com/microsoft/fluentui-apple): value-encoded `size80`-style tokens, and `ButtonStyle` × size category.
  - [Kickstarter ios-oss](https://github.com/kickstarter/ios-oss): `Spacing.unit_01…` on a 4-pt step, plus semantic radius aliases, and no lint.
  - [Adevinta Spark iOS](https://github.com/adevinta/spark-ios): semantic theme spacing.
  - [SwiftLint custom rules](https://realm.github.io/SwiftLint/custom_rules.html), with baseline support since 0.55.
- **Skills:**
  - Used: `apple-design` and `emil-design-eng`.
  - Not installed, for the user to decide: Anthropic **Design** plugin, community **design-skills**. Neither is iOS-specific.

## 7. Rollout status (D10)

The user accepted every recommendation in §4. Steps 1–5 are on branch `claude/ui-consistency-audit`:

| Step | Commit | Scope |
|---|---|---|
| 1 | 655ad421c | `RailSpacing` / `RailRadius` / `RailSize`; `.railPrimary` / `.railSecondary` / `.railTertiary`; `railSheetClose` (the system Close on iOS 26, `SheetCloseButton` fallback); `railSheet(.half/.full)`; `railText` / `railGlyph`. The old tokens alias the new ones. Guard `ios/tools/check-ui-tokens.sh` with a shrink-only baseline, wired into `run-regression-guards.sh`. |
| fix | a1d286402 | `--update` path normalization |
| 2 | 30f2e73bc | Map chrome (control 48 pt), Layers/Info/line/station cards, Settings, Data, playback |
| 3 | 1a34cbbce | Stats/Passport (card padding 16, bar height 6), scope picker Close, share composer |
| 4 | b71c0eb11 | Journey card padding 16, list rows, chooser, Hide trips, overdue actions, sheet heights |
| 5 | d8cef8896 | Timetable sheets Close, Import action bars, Dynamic-Type-safe columns |
| review | 7f2bf329a | Fixes from the independent review: a syntax error, a duplicate detent on the journey menu, two label-based UI tests, and a hardened guard |

The token baseline went from 389 literal violations (112 entries) to 182 (53 entries), and the guard fails on any increase.

**Step 6 is not started.** It waits for the add-trip and trip-notes branches to merge. It covers:

- trip detail: `RideDetailView`, `RideCard`, `JourneyMenuView`
- the trip editor (`JourneyEditor/**`): D3 system navigation bar, Cancel / 保存旅程, the shared editing chrome and Cancel-key unification
- `RailWorkspaceView` (the trip-cap pill, empty states, a half sheet for the scope picker's popover)
- `Localization/**`
