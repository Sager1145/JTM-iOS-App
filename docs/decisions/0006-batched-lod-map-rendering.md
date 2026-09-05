# 0006: Bound MapKit rendering work

- Status: Accepted
- Date: 2026-09-01
- Decision owners: Project maintainers
- Supersedes: None

## Context

The largest railway packages contain thousands of intervals and hundreds of
thousands of vertices. One overlay per interval exceeded Metal resource limits
and stalled gestures. MapKit does not provide MapLibre's vector-tile
simplification automatically.

## Decision

Render same-color line work through batched `MKMultiPolyline` overlays. Select
network detail with explicit level-of-detail rules, cull outside a padded
viewport, decimate at the shared Web/iOS tolerance, and enforce a final vertex
budget. Rebuild only when the zoom bucket or built viewport changes.

## Consequences

- National views remain interactive and have a bounded rendering cost.
- The final iOS renderer owns behavior not covered by pre-render parity fixtures.
- Visibility, station markers, labels, and route overlays must remain consistent
  across zoom transitions.
- Performance changes require measurement at representative national and city views.

## Alternatives considered

- One SwiftUI `MapPolyline` per interval: rejected after measured Metal pruning
  and multi-second gesture stalls.
- Draw every stored vertex: visually unnecessary at wide zoom and unbounded as
  regions grow.
- Use a fixed coarse package: reduces cost but permanently discards close-zoom
  geometry and weakens the shared-data contract.

## Validation

Renderer tolerance and import contracts in `ios/verify.sh` must pass. Release
profiling should compare rebuild time, overlay count, drawn vertices, frame
stalls, and memory at both national and city zooms.
