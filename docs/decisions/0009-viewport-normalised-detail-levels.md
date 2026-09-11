# 0009: Viewport-normalised detail levels

- Status: Accepted
- Date: 2026-09-10
- Decision owners: Project maintainers
- Supersedes: The 2026-09-08 "same scale, same detail" rule in
  `docs/MAP_DETAIL_LEVELS_2026-09-08.md` (0006's LOD work)

## Context

The phone-tuned railway detail ladder (`NetworkVisibilityPolicy.lineMinZoomMapLibre`,
mirrored in `app/public/rail-network.js`) was authored and validated against an
iPhone-class viewport. Three versions of the cross-device rule shipped within a few
days in September 2026:

1. An explicit per-device allowance (iPad/large window got 0.5–1 extra levels of
   delay before showing more lines).
2. A delay table keyed by device class.
3. None: the 2026-09-08 revision removed the allowance outright, so the ladder
   compared the raw camera zoom on every device.

Version 3's problem is geometric, not aesthetic: at a fixed map *scale* (say,
Web Mercator zoom 6), a larger viewport shows more geography than a phone does at
the same scale, so "the country fills the screen" happens at a higher zoom on an
iPad or a desktop browser than on a phone. A ladder tuned so a phone shows the
right amount of detail when a country fills its screen therefore shows too much
detail when the same content fills a tablet's or desktop's larger screen, because
the ladder never learns that more of the world is visible per pixel.

## Decision

Normalise the zoom the detail ladder sees to a 390-point (iOS) / 390 CSS-pixel
(Web) phone-class reference short edge, continuously rather than by device
bucket:

```
referenceShortEdge = 390
shortEdge          = min(viewportWidth, viewportHeight)
adjustment         = clamp(log2(referenceShortEdge / shortEdge), -1.5, +0.5)
visibilityZoom     = cameraZoom + adjustment
```

`visibilityZoom` replaces the raw camera zoom in every line and station min-zoom
comparison, on both platforms, for the complete network's lines and station
dots. Ride/journey markers are unchanged — this policy governs railway
eligibility, not what a traveller is following.

The two clamp bounds and the reference short edge are spelled identically in
`app/public/rail-network.js` (`VIEWPORT_REFERENCE_SHORT_EDGE`,
`VIEWPORT_ZOOM_ADJUST_MIN`, `VIEWPORT_ZOOM_ADJUST_MAX`) and
`NetworkVisibilityPolicy.swift` (`viewportReferenceShortEdge`,
`viewportZoomAdjustmentRange`); `ios/verify.sh` greps both files for the three
numbers so a change to one side without the other fails the build.

A degenerate viewport (`shortEdge <= 0`, non-finite) applies no adjustment.

## Consequences

- iPad and desktop browsers see phone-equivalent detail once the same geography
  fills their screen, instead of the extra lines version 3 exposed: iPhone
  (390–440 pt) adjustment ≈ 0; iPad 11" (834 pt) −1.10; iPad 13" (1024 pt)
  −1.39; a 1400×900 desktop browser −1.21; 1920×1080 −1.47 (clamped at −1.5); a
  320 px embed +0.29.
- Fewer lines are eligible per frame on large screens at a given content fit,
  which is also fewer lines the loader has to request and decode there.
- The adjustment is continuous in viewport size, so there is no device-class
  table to keep in sync as new device sizes ship, and no seam at a bucket
  boundary.
- `NetworkVisibilityPolicy` stays Foundation-only; the formula uses only
  `log2`, `min`, `max` and the two stored dimensions already on the struct.
- The struct's construction site (`RailMapView.networkVisibility(on:)`)
  already builds a fresh policy from `mapView.bounds.size` on every call, so
  no cache invalidation was needed for this change.

## Alternatives considered

- A per-device allowance or delay table (versions 1 and 2 above): requires
  maintaining a table as new device sizes ship, and produces a seam between
  table entries; the continuous formula covers every current and future
  viewport size with three constants.
- Per-pixel density (points vs. physical pixels): the geometric effect being
  corrected is content fit (how much geography an edge in points spans), not
  display density; UIKit and CSS already normalise density away from point/CSS
  measurements.
- Doing nothing (version 3, same scale on every device): rejected because it
  is the bug this decision fixes — a tablet or desktop shows more of the
  phone-tuned ladder's detail than its content fit warrants.

## Validation

- `cd ios/RailKit && swift test --filter NetworkVisibilityPolicyTests`
- `SCRATCH=/tmp/x ./ios/verify.sh --core`
- `cd app && node --test tests/viewport-zoom-adjustment.test.mjs`
- Full `./ios/verify.sh`
- Simulator: iPhone 17 Pro vs iPad Pro 13-inch at the same camera
  (`RAILMAP_UI_TEST_CAMERA="35.9,139.7,2"`, network on): iPad shows the
  phone's line set for that content fit, not more.
