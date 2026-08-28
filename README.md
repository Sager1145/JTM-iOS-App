# JTM iOS App

**A native SwiftUI journey ledger that turns railway travel across East Asia into a live Apple Maps record.**

JTM iOS App is the native iPhone and iPad edition of Japan Train Map. It records journeys, resolves them against bundled railway networks, draws ridden routes over Apple Maps, and turns the same local data into statistics, playback, and shareable JSON.

The repository also retains the reduced JavaScript reference implementation used to prove that the Swift port produces the same results for dates, geometry, routing, imports, statistics, and other pure logic.

## What you can do

- Explore the railway networks of Japan, Taiwan, Hong Kong, Macao, and Korea on one map.
- Add, edit, search, import, export, duplicate, reorder, hide, and delete journey records.
- Import supported route-planner screenshots through Vision OCR and review the result before saving.
- Resolve recorded stops onto real railway geometry instead of drawing straight-line fallbacks.
- Review mileage, coverage, service mix, travel time, and frequently ridden sections.
- Play journeys on the map and export playback as video.
- Use the interface in Traditional Chinese, Simplified Chinese, Japanese, or English.

Journey data stays on the device. Import, export, routing against bundled data, and statistics do not require an application server.

## Quick start

### Requirements

| Requirement | Project value | Notes |
| --- | --- | --- |
| macOS | Current Xcode-supported release | Required to build the iOS app |
| Xcode | Xcode 27 toolchain recommended | The project is developed against Swift 6.4 |
| Deployment target | iOS 17 or later | iPhone and iPad are enabled |
| Node.js | `26.4.0` | Required only for parity-fixture regeneration and checks |

Open `ios/RailMap.xcodeproj`, select the `RailMap` scheme, choose an iOS Simulator or signed device, and run the app.

To run the repository verification gate from Terminal:

```bash
cd ios
./verify.sh
```

The full gate verifies that the JavaScript fixtures are current, builds both Swift package targets, runs their tests, enforces module boundaries, builds the simulator app, and checks app-specific invariants.

Faster focused modes are available:

```bash
cd ios
./verify.sh --core    # Swift package build/tests and static contract checks; no app build
./verify.sh --swift   # Swift package, tests, and simulator app build
./verify.sh --js      # JavaScript fixture freshness only
```

If the repository is stored in an iCloud-backed folder, keep build products outside it:

```bash
cd ios
SCRATCH=/tmp/jtm-railkit-verify ./verify.sh --swift
```

## Architecture

The compiler enforces three layers:

```text
RailMap app
  SwiftUI, MapKit, Vision, AVFoundation, persistence
                         |
                         v
RailPresentation
  display state and interaction resolution
                         |
                         v
RailCore
  Foundation-only portable domain logic
                         |
                         v
JavaScript reference + port-fixtures
  cross-language expected behavior
```

| Layer | Location | Responsibility |
| --- | --- | --- |
| App | `ios/RailMap/` | SwiftUI shell, MapKit rendering, files, OCR, playback video, and device preferences |
| Presentation | `ios/RailKit/Sources/RailPresentation/` | Search, journey-state priority, panel motion decisions, taps, clocks, and Apple Maps links |
| Core | `ios/RailKit/Sources/RailCore/` | Models, validation, routing, geometry, dates, import, statistics, and serialization |
| Reference | `app/` and `port-fixtures/` | JavaScript behavior and committed parity answers |

`RailCore` may import Foundation only. `RailPresentation` may import Foundation and `RailCore` only. `ios/verify.sh` fails when those boundaries drift.

## Documentation

| Document | Use it when you need to |
| --- | --- |
| [User guide](docs/USER_GUIDE.md) | Use the app, manage journey data, or solve a common problem |
| [RailKit API reference](docs/API_REFERENCE.md) | Integrate with or maintain the public Swift package interfaces |
| [Build and release runbook](docs/RUNBOOK.md) | Verify, archive, release, troubleshoot, or roll back a build |
| [Documentation strategy](docs/DOCUMENTATION_STRATEGY.md) | Find the canonical document, assign ownership, or record a decision |
| [Feature parity matrix](ios/FEATURES.md) | Check whether a web feature is implemented, adapted, or intentionally omitted |
| [Porting guide](ios/PORTING.md) | Port another pure function from JavaScript to Swift |
| [iOS engineering notes](ios/README.md) | Understand historical design and performance decisions |

## Repository layout

```text
.
├── ios/
│   ├── RailMap.xcodeproj/       # Native app project
│   ├── RailMap/                 # SwiftUI and platform integration
│   ├── RailMapUITests/          # UI and console regression tests
│   ├── RailKit/                 # Local Swift package and unit tests
│   ├── Resources/               # Bundled raster artwork and localization
│   └── verify.sh                # Required local verification gate
├── app/                         # Reduced JavaScript reference and rail data
├── port-fixtures/               # Cross-language parity fixtures
├── docs/                        # User, API, operations, and governance docs
└── .github/workflows/           # Port-parity CI
```

## Development workflow

1. Make the smallest coherent change in the owning layer.
2. Add or update Swift tests for native behavior.
3. When reference behavior changes, regenerate the relevant fixtures with Node `26.4.0` and review the JSON diff.
4. Run the narrow gate while iterating, then run `cd ios && ./verify.sh` before handoff.
5. Update the canonical document listed in [the documentation strategy](docs/DOCUMENTATION_STRATEGY.md) when behavior, commands, or public interfaces change.

Do not treat a fixture change as an automatic fix. Fixtures record what the JavaScript returns; a changed answer must be reviewed before the Swift implementation is updated to match it.

## Project status

The app target is version `0.1` with build number `1`. The feature-by-feature implementation status lives in [ios/FEATURES.md](ios/FEATURES.md), which is the canonical parity ledger.

## Repository origin

This repository was extracted from `Sager1145/Japan-Train-Map`, branch `swift-ios-port`, at commit `811286e4`. The branch's iOS commits were replayed in order, followed by the working-tree changes present during extraction.
