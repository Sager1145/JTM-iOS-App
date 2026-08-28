# RailKit API Reference

RailKit contains the portable logic and presentation decisions used by JTM iOS App. This reference describes the public surface of the local Swift package at `ios/RailKit` and is intended for maintainers, tests, and other clients that import `RailCore` or `RailPresentation`.

This document was checked against Swift symbol graphs generated on 2026-08-28. The current graphs contain 1,591 public symbols in `RailCore` and 220 in `RailPresentation`, including nested types and members. The catalog below lists every top-level public type and then focuses on the operations most likely to be called directly.

## Package contract

| Product | Dependencies | Platform minimum | Responsibility |
| --- | --- | --- | --- |
| `RailCore` | Foundation only | iOS 17, macOS 14 | Domain models, parsing, validation, routing, geometry, import, statistics, and serialization |
| `RailPresentation` | Foundation, `RailCore` | iOS 17, macOS 14 | Search, presentation priority, interaction resolution, regional clocks, panel motion, and Apple Maps links |

Import only the product you need:

```swift
import RailCore
import RailPresentation
```

The app target owns SwiftUI, MapKit, Vision, AVFoundation, storage, and other platform integrations. Adding those frameworks to either package target violates the package contract and fails `ios/verify.sh`.

## Core value types

### `Coordinate`

A WGS84 position stored in rail-package order: longitude first, latitude second.

```swift
let tokyo = Coordinate(lon: 139.7671, lat: 35.6812)
let shinagawa = Coordinate(lon: 139.7387, lat: 35.6285)
let distance = Geometry.distanceMeters(tokyo, shinagawa)
```

Coordinates remain WGS84 throughout `RailCore`. Any datum correction required by Apple Maps belongs at the app's MapKit presentation boundary.

### Journey model

| Type | Purpose |
| --- | --- |
| `TrainStore` | Canonical `{ "schema_version": "1.3", "trains": [...] }` store |
| `Train` | One itinerary or recorded journey |
| `Stop` | One station call on a journey |
| `RouteSection` | Constraints for one adjacent stop pair |
| `RoutePolicy` | Rules controlling route solving for a train |
| `TrainStyle` | Per-train display values that survive serialization |
| `RouteFeature` | One solved path with its line and operator evidence |
| `CanonicalRoute` | Canonicalized route output |
| `RouteHints` | Line and operator hints read by the solver |

These are value types. Mutating user data normally happens through `StoreOperations` or the app's stores so ID, ordering, validation, persistence, and route reload behavior stay coordinated.

## RailCore top-level catalog

### Data, identity, and compatibility

| Symbol | Kind | Purpose |
| --- | --- | --- |
| `Grid` | enum | Five-decimal coordinate identity and segment keys |
| `JSNumber` | enum | ECMAScript-compatible number spelling and rounding |
| `JSMath` | enum | JavaScript-compatible math primitives used by the port |
| `CompactPackage` | struct | Decoded `compact-v1` railway package |
| `Localization` | struct | Shared four-language catalog and regional variants |
| `OperatorBranding` | enum | Operator display name, logo, and badge rules |

### Journey data and validation

| Symbol | Kind | Purpose |
| --- | --- | --- |
| `TrainStore`, `Train`, `Stop` | structs | Canonical journey store and records |
| `RouteSection`, `RoutePolicy`, `TrainStyle` | structs | Route constraints, solver policy, and display metadata |
| `RouteFeature`, `RouteHints`, `CanonicalRoute` | structs | Solved geometry, routing evidence, and canonical route output |
| `TrainValidation` | enum | JSON decoding, schema validation, and model conversion |
| `StoreOperations` | enum | Add, duplicate, move, hide, delete, import, and export operations |
| `Dates` | enum | Date normalization, cross-day rules, sorting, and filtering |
| `ImportEngine` | enum | Progressive manifest and part import behavior |
| `TransferGuide` | enum | Route-screenshot text parsing and journey construction |
| `AppleMapsJourney` | enum | Journey construction from an ordered station plan |
| `AppleMapsLink` | enum | Parsing of Apple Maps journey links |

### Railway geometry and stations

| Symbol | Kind | Purpose |
| --- | --- | --- |
| `Coordinate` | struct | WGS84 longitude and latitude |
| `Geometry` | enum | Haversine distance and Douglas-Peucker decimation |
| `Grooming` | enum | Removal of display-only micro-kinks |
| `DisplayParts` | enum | Visible branch and trunk parts derived from package intervals |
| `Visibility` | enum | Line visibility thresholds by rank and length |
| `RideMarkerVisibility` | enum | Visibility policy for stations attached to journeys |
| `StationDisplay` | enum | Station marks, labels, and popup display data |
| `Stations` | enum | Low-level station features, queries, and resolution |
| `StationIndex` | struct | High-level station place, line, nearest, and between-stations lookup |
| `StationRouteResolver` | protocol | Station-to-route resolution seam used by portable route logic |

### Routing and statistics

| Symbol | Kind | Purpose |
| --- | --- | --- |
| `RouteGeometry` | enum | GeoJSON line and multiline shapes |
| `RouteNetwork` | struct | Railway network indexes consumed by canonicalization |
| `RouteGraph` | enum | Routable graph, spatial index, edges, and graph store |
| `RouteSolver` | enum | Deterministic interval and graph routing kernel |
| `RouteProjectionCache` | struct | Caller-owned memo for point-to-part projection |
| `OverlapLanes` | enum | Parallel corridor geometry used by overlap visualization |
| `StationJoinSmoothing` | enum | Geometry smoothing at station joins |
| `Statistics` | enum | Mileage, coverage, categories, service groups, and top sections |
| `Playback` | enum | Timeline planning and playback interpolation |

## Frequently used RailCore operations

### Geometry

```swift
let meters = Geometry.distanceMeters(origin, destination)
let keptIndices = Geometry.douglasPeuckerIndices(
    surveyedCoordinates,
    epsilonMeters: 4.0
)
```

`distanceMeters` returns meters. `douglasPeuckerIndices` returns indexes into the original array, preserving caller ownership of the coordinate data.

### Dates

Important operations include:

```swift
Dates.normalizeDateString(_:) -> String?
Dates.parseTimeToMinutes(_:) -> Double?
Dates.daySpan(_:) -> Dates.DaySpan
Dates.availableDates(_:manualDates:) -> [String]
Dates.sortByDateAndDeparture(_:) -> [Dates.Train]
Dates.trains(_:inBucket:) -> [Dates.Train]
Dates.reconcileSelectedDate(_:trains:manualDates:) -> String
```

Date strings use the canonical date-only form expected by the journey store. Cross-day times remain explicit and are mapped to calendar dates through `DaySpan` and `segmentDate`.

Invalid or absent values return `nil` where the signature is optional. Sorting and filtering functions are deterministic and do not mutate their input arrays.

### Store operations

`StoreOperations.Workspace` owns the mutable store and selection used by the pure operations.

```swift
@discardableResult
StoreOperations.addTrain(_:in:) -> StoreOperations.MutationResult?

@discardableResult
StoreOperations.duplicateTrain(_:in:) -> StoreOperations.MutationResult?

@discardableResult
StoreOperations.moveTrain(_:by:in:) -> StoreOperations.MutationResult?

@discardableResult
StoreOperations.toggleTrainVisibility(_:in:) -> StoreOperations.MutationResult?

@discardableResult
StoreOperations.deleteTrain(_:in:) -> StoreOperations.MutationResult?

StoreOperations.exportTrainStore(_:stations:) -> String
```

Passing an unknown or missing train ID to an ID-based mutation returns `nil`. `appendImportedTrain` is the notable throwing operation; it validates and converts incoming JSON before insertion.

### Station lookup

Build a `StationIndex` from entries, then use its search operations:

```swift
let index = StationIndex(entries)

let tokyoMatches = index.places(named: "東京")
let exact = index.place(code: "JR-EAST-TOKYO")
let nearest = index.nearest(to: coordinate, within: 2_000)
let corridor = index.stationsBetween(origin, destination, limit: 80)
```

`place(code:)`, `nearest`, and `stationsBetween` return `nil` when no match satisfies the request. `places(named:)` can return multiple platforms or operator records for one station name.

### Route solving

The normal route order is:

1. Try `solveOfficialInterval` when the stop pair maps to a surveyed official interval.
2. Fall back to `solveSectionOnDemand` with a `RouteGraph.RouteGraphStore`.
3. Use `completeRouteEndpointCoordinates` to retain exact station endpoints.
4. Persist only canonical WGS84 output.

Key signatures are:

```swift
RouteSolver.solveOfficialInterval(
    _:segmentIndex:train:country:allowedCodes:intervalIndex:stations:continuityAnchor:
) -> RouteSolver.SolvedSection?

RouteSolver.solveSectionOnDemand(
    _:segmentIndex:train:country:graphStore:stations:continuityAnchor:
) -> RouteSolver.SolvedSection?

RouteSolver.dijkstra(
    graph:sourceCandidates:targetKeys:train:allowedCodes:hints:
) -> [RouteSolver.SolvedTarget]
```

A `nil` solved section means the requested section could not be resolved under the supplied stations, policy, and hints. Do not replace it with a straight line; the app exposes the failure for that journey.

### Import and screenshot routes

`ImportEngine` handles canonical manifest and part loading. Its `acceptPart`, `acceptedManifest`, and related optional results reject shapes that are not valid import units.

`TransferGuide` turns OCR text boxes into a route, then builds canonical journeys:

```swift
let parsed = TransferGuide.parse(textLines)
let result = TransferGuide.build(
    route: parsed,
    options: buildOptions,
    stations: stationIndex
)
```

The parser does not read pixels. The app target performs Vision OCR and passes positioned text into `RailCore`, which keeps the parsing and station-resolution behavior testable.

### Statistics

Statistics first require an edge index for the relevant network:

```swift
let index = Statistics.buildEdgeIndex(sections: sections, country: "jp")
let entry = Statistics.collectTrainStatsEntry(features: features, index: index)
let totals = Statistics.aggregateMileageStats(
    index: index,
    entries: [entry],
    country: "jp"
)
```

Other public operations provide service-group totals, route-category visibility, coverage view models, ride time, and most-ridden sections. Country codes select the category rules and must match the network used to build the index.

### Apple Maps import helpers

`AppleMapsLink.parse(_:)` returns an optional parsed link. `AppleMapsJourney.plan` expands an origin and destination through `StationIndex` when possible, and `AppleMapsJourney.train` turns the plan into a canonical `Train`.

These types parse and construct data only. Opening URLs and invoking MapKit remain app responsibilities.

## RailPresentation top-level catalog

| Symbol | Kind | Purpose |
| --- | --- | --- |
| `JourneyFailure` | enum | User-visible failure categories |
| `JourneyRouteState` | enum | Route loading and failure state |
| `RouteLoadPhase` | enum | Presentation form of route-store loading |
| `JourneyWorkspacePhase` | enum | Workspace loading, empty, content, and failure phases |
| `PresentationText` | struct | Text still requiring localization by the app |
| `StatusPresentation` | struct | Optional status badge presentation |
| `SecondaryAction` | enum | Non-primary journey actions |
| `JourneyPresentation` | struct | One resolved surface with one primary task |
| `JourneyPresentationResolver` | enum | Priority resolver for overlapping journey states |
| `JourneySearchMatcher` | enum | Search field extraction, matching, and filtering |
| `PanelDetent` | enum | Compact, medium, and expanded semantic panel stops |
| `PanelDetentResolver` | enum | Projection, rubber-banding, and release destination |
| `RideTapResolver` | enum | Candidate hit testing for ridden routes |
| `JourneyClock` | struct | One journey's regional date and time semantics |
| `RegionClock` | struct | Region-specific civil-date calculations |
| `StationPlaceLink` | enum | Station query ranking and Apple Maps URLs |

## Frequently used RailPresentation operations

### Resolve one primary journey task

```swift
let presentation = JourneyPresentationResolver.selected(
    train: train,
    route: routeState,
    phase: workspacePhase
)
```

Use the resolver rather than recomputing priority inside a view. Route failure, hidden state, and playback can overlap; the resolver is tested across their combinations and returns one primary presentation.

### Search journeys

```swift
let results = JourneySearchMatcher.filter(trains, query: "Tokyo Osaka")
```

The matcher searches normalized fields derived from the full train record. An empty query returns the unfiltered semantic result defined by the matcher.

### Resolve regional dates

```swift
let clock = RegionClock.forRegionCode("jp")
let today = clock.today(at: Date())
let upcoming = clock.isUpcoming(train.date, at: Date())
```

Use `RegionClock` instead of the device's current calendar when deciding whether a journey is today, past, or upcoming for a region.

### Build an Apple Maps station link

```swift
let url = StationPlaceLink.placeURL(placeID: placeID)
    ?? StationPlaceLink.pinURL(
        name: stationName,
        latitude: latitude,
        longitude: longitude
    )
```

`placeURL` returns `nil` for an unusable place ID. The pin URL is the explicit fallback.

## Failure and side-effect conventions

| Convention | Meaning |
| --- | --- |
| Optional result | The input could not be normalized, parsed, matched, or solved under the supplied constraints |
| Empty collection | The operation completed and found no matching items or paths |
| `throws` | Validation or conversion failed with an error the caller should surface or translate |
| `inout Workspace` | The pure operation mutates caller-owned working state |
| Static pure operation | No file, network, UI, or MapKit side effect |

RailKit does not authenticate, perform network requests, rate-limit clients, or own persistent storage. Those HTTP-oriented concerns do not apply to this local Swift package.

## Regenerate the mechanical reference

Generate fresh public symbol graphs after changing a public declaration:

```bash
cd ios/RailKit
swift package \
  --scratch-path /tmp/jtm-railkit-symbols \
  dump-symbol-graph \
  --minimum-access-level public \
  --skip-synthesized-members
```

The JSON files appear below the scratch path in an architecture-specific `symbolgraph/` directory. Use them as the source for symbol names, declarations, relationships, and doc comments. Do not hand-maintain a second signature that disagrees with the compiler.

Then run the package gate:

```bash
cd ios
SCRATCH=/tmp/jtm-railkit-verify ./verify.sh --core
```

Update this reference when a top-level symbol is added, removed, renamed, or changes its failure contract. For detailed parity requirements and fixtures, see [the porting guide](../ios/PORTING.md).
