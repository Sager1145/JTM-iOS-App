# 0002: Use native SwiftUI and MapKit

- Status: Accepted
- Date: 2026-09-01
- Decision owners: Project maintainers
- Supersedes: None

## Context

The iOS app needs native navigation, Dynamic Type, accessibility, file import,
Vision OCR, playback video, device location, and a railway overlay aligned with
Apple Maps. The existing WebUI remains valuable as a behavioral reference, but
embedding it would make native interaction and platform integration indirect.

## Decision

Build the interface in SwiftUI and use an `MKMapView` bridged through
`UIViewRepresentable` for the map. Retain the JavaScript implementation only as
the reference for portable behavior and fixture generation.

## Consequences

- The app can use native lifecycle, accessibility, localization, and system UI.
- MapKit-specific rendering and datum behavior are explicit app responsibilities.
- Web style JSON cannot be reused directly; renderer tokens must stay aligned by
  tests and textual contracts.
- UIKit interoperability remains necessary for MapKit performance and control.

## Alternatives considered

- Embed the WebUI in `WKWebView`: reuses rendering code but weakens native UI,
  accessibility, file handling, and platform integration.
- Use SwiftUI `Map` only: simpler bridge, but lacks the batching and renderer
  control required by the national network datasets.
- Use MapLibre Native: closer to the WebUI style model, but adds a dependency and
  moves the app away from the basemap its railway styling is measured against.

## Validation

The full Swift gate must build `RailMap.app` without warnings. UI smoke tests
must cover the native workspace, map controls, and accessibility identifiers.
