# Japan rail alignment inspector

**Goal:** A separate Swift Mac Catalyst app for manual comparison of Japan railway geometry and centreline smoothing with tracks drawn on Apple's basemap.

**Architecture:** SwiftUI controls around one north-up, flat MKMapView. Read the existing Japan package and use RailCore's decoder, DisplayParts and ContinuousStroke; include the existing RailStyle source for identical style tokens. No changes to the main app, packages or source geometry.

**Scope:** Search/select a railway, navigate stations/intervals, switch between basemap, decoded package geometry, display parts, smooth centreline and an overlay comparison. Opacity adjustment and metadata export support manual inspection. Clamp Dynamic Type to xSmall...xLarge. No automatic basemap accuracy verdicts. The centreline preview excludes main-app corridor lanes/follows/joins/family collapse and is labelled accordingly.

**Implementation:**

- [x] Create an independent XcodeGen Catalyst project under `ios/auxiliary/RailAlignmentInspector`, linking the existing local RailKit package and bundling only `jp-2025.json`.
- [x] Load package/topology once; use seam-aware canonical decoding and separate display parts. Preserve station anchors when invoking the existing screen-space smoothing.
- [x] Add line search, station/interval navigation, fixed-camera comparison modes, opacity, and a JSON view record that distinguishes preview geometry from basemap evidence.
- [x] Review dependencies and build only this Catalyst scheme, with one heavy job at a time. Observe an actual Japanese station approach and toggle to bare basemap. Record results here. No retired verification runners, dataset rebuilds, commits or pushes.

**Review focus:** Never weld branches or separate parts; decoded geometry already snaps endpoints to station anchors. UIKit points govern smoothing, not Retina pixels. Rebuild after zoom changes. Do not interpret POI position, coincident anchors or interpolation bounds as actual track alignment proof. Hidden overlays must leave the camera unchanged. Missing package/load errors must be visible.

## Evidence/result ledger

Initial review: `CompactPackage.decodeIntervals` reconstructs seam flags and anchors endpoints; `DisplayParts.parts` performs station approach grooming and branch splitting. `ContinuousStroke.buildStroke` is the production interpolation/fillet implementation. `AppleMapDatum` excludes Japan. The repository hotspot list is empty; existing North America capture workflow is outside scope. Grok read-only review reached its turn limit without a final result; no conclusions adopted.

ChatGPT Pro consulted in Chat mode: https://chatgpt.com/c/6aca9dff-fc70-83ea-b715-70b3c2f90899 (complete answer captured; owned consultation tab closed). Adopted single flat north-up map, unchanged camera across modes, logical-point scale, geometry-stage isolation and partial-parity label. Its unsupported generic claim that a false storage seam flag implies a physical break was not adopted: the actual decoder repeats endpoints for those rows; branch topology is owned by DisplayParts. A bounded Sol medium source review found no important defects. It noted synchronous model status publication from updateUIView as a lifecycle concern, without an observed failure; no speculative change made.

Built using the README Catalyst command and `/tmp/jtm-rail-alignment-inspector` DerivedData. First build succeeded, but first native launch exposed a missing JSON resource: XcodeGen's target-level `resources` entry had not created a copy phase. Corrected to a source entry with `buildPhase: resources`; incremental build succeeded and `cmp` confirmed the bundled Japan JSON equals its source. One inherited build warning: AppIntents metadata extraction skipped because no AppIntents framework is used.

Native observation on 2026-10-10: actual Catalyst app loaded **657 lines**, package **2025.5.2**, selected 山手線/品川. At native zoom **15.88**, **2.10 m/point**, one display part produced **1,527 smoothed vertices**. Blue decoded and pink smoothed overlays were visible against the loaded Apple basemap. Basemap peek removed the custom marker and overlays, preserved center **35.628135, 139.738535** and camera distance **3083**, and changed smoothed vertex count to zero. Restoring and navigating next selected 大崎 (**004135**) at **35.619945, 139.728245** with the same scale. Export UI saved `/tmp/jtm-inspector-osaki-view.json`; inspected JSON contains the correct station/line, camera, mode, package version, `unreviewed` result and partial-scope disclaimer.

Outcome: auxiliary app built, running, and usable for manual comparison. No measured basemap residual, nationwide alignment result, full main-renderer parity, geometry repairs, performance claim or screenshot export is established. Broader line/branch and zoom review remains manual user work with this tool.
