# JTM iOS App

Native SwiftUI edition of Japan Train Map. The application uses Apple Maps as
its basemap and ships the railway, station, sample itinerary, localization and
parity data required to build and test independently from the web repository.

## Open and verify

- Open `ios/RailMap.xcodeproj` in Xcode.
- Run `ios/verify.sh` for the RailKit parity tests and app build checks.
- The project has no remote Swift package dependencies; `ios/RailKit` is a
  local package.

The reduced `app/` tree is intentional. It contains the JavaScript reference
implementation and source data used by the port-parity harness and Xcode's
resource-copy build phase. It is not a second application to deploy.

## Repository origin

Extracted from `Sager1145/Japan-Train-Map`, branch `swift-ios-port`, while its
tip was `811286e4`. The branch's iOS-related commits are replayed here in their
original order, followed by the working-tree changes present during extraction.

