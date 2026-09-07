# 0001: Keep RailCore Foundation-only

- Status: Accepted
- Date: 2026-09-01
- Decision owners: Project maintainers
- Supersedes: None

## Context

The native app ports routing, geometry, validation, import, statistics, and
serialization behavior from a JavaScript reference implementation. The port
must be testable against committed cross-language fixtures without requiring an
iOS runtime or MapKit.

## Decision

Keep `RailCore` limited to Foundation. Keep presentation policy that needs no
platform framework in `RailPresentation`, which may depend only on Foundation
and `RailCore`. SwiftUI, UIKit, MapKit, persistence, and device services remain
in the app target. Enforce these imports in `ios/verify.sh`.

## Consequences

- Pure behavior can build and test on macOS through Swift Package Manager.
- JavaScript and Swift can consume the same fixtures and data formats.
- Platform-specific conveniences must be adapted at the app boundary.
- Some app orchestration remains outside unit-testable package targets until a
  platform-free policy is extracted deliberately.

## Alternatives considered

- Put all Swift code in the app target: simpler initially, but removes the
  compiler-enforced portability and parity boundary.
- Let `RailCore` import MapKit or SwiftUI: reduces adapter code, but makes the
  domain behavior platform-dependent and harder to compare with JavaScript.
- Split every domain area into its own package: rejected until build time or
  ownership pressure justifies the additional public boundaries.

## Validation

`SCRATCH=/tmp/jtm-rail-core ./ios/verify.sh --core` must pass, including the
import allowlist and the RailCore/RailPresentation tests.
