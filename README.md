# JTM — Japan Train Map

**English** · [简体中文](README.zh-CN.md)

**Keep a railway travel journal, trace your journeys on the map, and see how much of the network you have ridden.**

JTM is a native SwiftUI app for iPhone and iPad, with a Mac Catalyst development destination. It brings journey records, railway maps, timetable lookup, travel statistics, and sharing into one workspace. Bundled networks cover **Japan, Taiwan, Hong Kong, Macao, and Korea**.

Your journey library is stored on your device. Core recording, route calculation, statistics, and JSON exchange use local data. Apple Maps and optional ChatGPT features use online services.

[User guide](docs/guides/user-guide.md) · [Build from source](#build-from-source) · [Developer documentation](docs/README.md)

## Record a journey

Start with a region, origin, destination, and travel date. Choose the service type, enter departure and arrival times, and mark the trip as ridden or planned. The new-journey form finds railway corridors between your stations so you can review the route before saving.

For detailed records, the journey editor lets you:

- Add intermediate stops, arrival and departure times, platforms, and notes.
- Record operators, lines, train numbers, and service names for individual sections, including changes during a through-running journey.
- Choose a route through intermediate stations, fill stops from a local railway route, and correct an unresolved section.
- Edit, duplicate, reorder, hide from the map, or delete saved journeys.

Browse upcoming trips, revisit the complete journey list, or search by journey, service, and station information. Add empty dates when planning a future travel day. Date filters keep the list and map focused on the period you want to explore; overnight journeys retain their calendar-day boundaries.

## Look up trains and fill missing details

### Bundled timetables and service patterns

For Japan, search the bundled timetable by the journey's identifying details, or browse service patterns with date, operator, and line filters. Inspect a train's calls and registered sources, then use the selected timetable or stop pattern to populate an editable journey draft.

Historical service patterns can be browsed alongside date-specific results. Coverage depends on the bundled sources and their operating dates: this is a source-backed catalog, not a live departure board or a complete timetable for every railway.

### Optional ChatGPT assistance

Ask about a train by name, number, route, and operating date, or compare a published timetable against its registered sources. Research answers remain separate from your saved journey.

The editor also offers AI completion for missing service details, scheduled calls, platforms, and section-level operators, lines, and train numbers. Review the proposed additions and sources before applying them to the draft; existing non-empty facts are preserved.

You can use an account-provided model through the experimental ChatGPT subscription integration, or share the completion prompt with ChatGPT and paste its JSON response. Direct sign-in displays **Codex** during authorization and depends on account availability. Requests send the displayed journey context and your research remarks to OpenAI.

## Explore your railway map

All five regional networks share an Apple Maps workspace. Select a journey to highlight its route, tap overlapping rides to choose between them, or open a station card for names, readings, operator information, and an Apple Maps link.

- Show or hide railway lines, stations, terminals, pass markers, and ridden-route categories.
- Adjust route and marker styling, selection emphasis, and off-date dimming.
- Display the current network, the network for the selected journey's date, or a historical overlay where bundled history is available.
- Follow your location, frame a network or selection, zoom, and reset the compass.
- Choose whether overnight journeys appear in full or distinguish the portion on another day.

Routes follow bundled physical railway topology. A nearby platform, shared station name, passenger transfer, or through-service label alone does not prove a track connection. When the available evidence cannot resolve a journey, its route can remain pending and its precise mileage incomplete.

## Review your travel statistics

The statistics workspace summarizes your ridden journeys with:

- Journey, travel-day, stop, and travel-time totals.
- Mileage by railway or service category.
- Network coverage and per-line details.
- Station, operator, route, and frequently ridden section rankings by count or distance.
- Travel patterns by year, month, and weekday.
- Distance and time for the selected day.

Scope the view to a region or all regions, with additional area choices for Japan. Mileage and coverage depend on the journeys' route results and the bundled network used for that scope.

## Replay and share

Play journeys on the map with pause and resume, speed controls, previous and next journey navigation, optional focus zoom, completed-route trails, and a closing overview. Export playback as a video with configurable frame shape, quality, and bitrate.

Share an individual journey as an image, or use the share composer to arrange journey, map, and statistics cards on a canvas. Move and resize cards, choose date and region scopes, switch appearance, and export in square, landscape, or portrait formats, including 16:9 and 9:16.

## Bring your records with you

The Data Library handles imports, exports, samples, and recovery:

| Task | Supported workflow |
| --- | --- |
| Import JSON | Open a file or paste a canonical store, train array, or single train object; review validation before appending or replacing the library. |
| Import screenshots | Read supported Japanese route-planner images with on-device Vision OCR; review parsed legs, station matches, times, platforms, and fares before saving. |
| Try sample journeys | Load bundled regional samples and special itineraries, then edit them as your own records. |
| Export records | Save or copy canonical JSON using `schema_version` and `trains`. |
| Recover a library | Restore the recovery backup created before supported destructive operations. |

Journey storage uses local JSON with serialized, atomic writes. The app's state directory is excluded from iCloud backup; export JSON when you want a portable copy of your records.

## Languages and device support

The interface supports **Traditional Chinese, Simplified Chinese, Japanese, and English**. Station naming follows regional data, with optional kana, romaji, and Chinese readings where available. Journey translations can be enabled separately from the interface language.

iPhone uses portrait orientation; iPad supports portrait and landscape. The app currently bounds Dynamic Type to `.xSmall ... .xLarge`.

## Build from source

### Requirements

- macOS with Xcode. The documented development toolchain is **Xcode 27.0 beta, Swift 6.4, and the iOS 27 SDK**; the app deployment target is **iOS 17.0**. See [native engineering notes](ios/README.md) for toolchain details.
- Git LFS for `app/data/rail.db`, the derived database used for network queries and cross-checking.
- Node.js **26.4.0** from `.node-version` only when working on JavaScript reference code, fixtures, or data builders.

From an existing checkout:

```sh
git lfs install
git lfs pull
open ios/JTM.xcworkspace
```

Select the **RailMap** scheme, choose an iPhone or iPad simulator, and run. For a physical device, configure signing with your development team. For Mac development, choose **My Mac (Mac Catalyst)**. You can also open `ios/RailMap.xcodeproj` directly for the main app.

The app uses the repository's built railway packages and runtime resources. Raw GIS downloads and source-research inputs are kept locally and are unnecessary for running the bundled app. Rebuilding those artifacts requires the corresponding retained inputs; see the [railway source center](railway-sources/README.md).

### Diagnostic apps

The workspace also includes three separate Mac Catalyst tools:

| Scheme | Purpose |
| --- | --- |
| `RouteWorkbench` | Inspect physical route solving and saved journey evidence. |
| `ThroughWorkbench` | Review historical through-service validity and patches. |
| `RailAlignmentInspector` | Compare display geometry with native basemap snapshots. |

See [diagnostic app setup](ios/auxiliary/README.md) for their projects and usage.

## How the repository fits together

The native app owns SwiftUI, MapKit, Vision OCR, playback and video encoding, persistence, and account integration. Its local Swift package separates reusable logic into three modules:

| Module | Responsibility |
| --- | --- |
| `RailCore` | Journey models, validation, dates, routing, geometry, timetable access, imports, statistics, and serialization. Uses Foundation, with SQLite3 scoped to read-only timetable access. |
| `RailApplication` | Import staging, draft validation, and route/mileage use cases over snapshots; depends on Core. |
| `RailPresentation` | Search and display policies, interaction decisions, clocks, and map links; depends on Core independently of Application. |

The `app/` directory retains JavaScript reference behavior and railway data builders. Committed `port-fixtures/` record expected results for shared Swift/JavaScript logic.

```text
ios/
  RailMap/              Native app and feature surfaces
  RailKit/              Core, Application, Presentation, and package tests
  RailMapTests/         App regression tests
  RailMapUITests/       Native UI regression tests
  auxiliary/            Diagnostic apps
  JTM.xcworkspace       Main app and diagnostic projects
app/
  data/                 Built databases, station tables, and journey samples
  public/rail/          Built railway packages and attribution
  scripts/              Retained builders and supporting tools
port-fixtures/          Shared behavior fixtures
docs/                   Guides, references, decisions, and dated evidence
railway-sources/        Source catalog; raw inputs remain local
```

### Development and verification

Start with a review of the changed code or data and its affected dependencies. For shared behavior, examine the relevant Swift and JavaScript implementations together; for railway identities, inspect the affected bundled references. Run a focused existing test, targeted data query, or incremental build only when it resolves a concrete correctness question.

The opt-in `ios/verify.sh` exposes independent `swift`, `build`, `route`, and `alignment` modules; running it without arguments prints help. It does not launch an automatic full verification pipeline. Follow [the current verification policy](ios/VERIFICATION.md), reuse applicable evidence, and coordinate one heavy job at a time.

Feature descriptions here identify implemented surfaces. Current acceptance questions and dated results remain in the [scope ledgers](ios/refactor-parallel/) and [reports](docs/reports/).

## Further reading

- [User guide](docs/guides/user-guide.md) — detailed recording, import, map, playback, and recovery workflows.
- [Current feature reference](ios/docs/features.md) — feature areas and their source owners.
- [Source structure](ios/docs/source-structure.md) and [RailKit API reference](docs/reference/api-reference.md) — code organization and package interfaces.
- [Build and release runbook](docs/guides/runbook.md) — signing, archiving, release, and recovery procedures.
- [Railway source center](railway-sources/README.md) — retained inputs, published artifacts, provenance, and attribution locations.
- [Architecture decisions](docs/decisions/) and [porting guide](ios/docs/porting.md) — durable choices and shared behavior contracts.
- [Documentation index](docs/README.md) — the complete guide to references and historical reports.

North American datasets are retired; their offline archives are not bundled or loaded by the app. Data-source attribution and license notices remain alongside the published railway packages and source-derived artifacts.

This repository originated from `Sager1145/Japan-Train-Map`, branch `swift-ios-port`, at commit `811286e4`.
