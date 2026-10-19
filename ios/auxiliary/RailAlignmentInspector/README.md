# Rail Alignment Inspector

SwiftUI / MapKit workspace for manually comparing **Japan** railway geometry with the railway tracks drawn on Apple's basemap. Runs on macOS through **Mac Catalyst**. The inspector reads the bundled railway data and never edits it. Evidence-backed data repairs are applied separately at their owning source.

This is now an internal workspace of **RailDiagnostics**, not a standalone app. Build the single unified target and create a task or pass a scoped request with the required zoom, viewport, appearance and output modes. See [the current request/result contract](../RailDiagnostics/README.md). Existing recorded app names below describe historical evidence.

Search by line/company/ID. In the **线路** tab, Return selects the line only when the filtered result is unique. `⇧⌘C` captures the complete current interval; `⌥⇧⌘C` captures the complete current line. Select a station, move to the next station or fit the next station interval. Switch modes without moving the camera; **只看底图** (⌘B) hides all custom geometry and the selected station marker. Opacity changes only the custom geometry. Drag and zoom the map for detailed bends and approaches; smoothing is recomputed at the new screen scale. The map remains north-up and flat.

Queue search also accepts station names; its counter shows matching intervals. **下一待检** skips intervals with current detailed coverage within the search results, continues from the selected interval even after it leaves the pending filter, and wraps at the end. A saved viewport verdict alone does not remove an interval from the pending queue.

- **包几何 / blue:** `CompactPackage.decodeIntervals`, including reconstructed seams and authoritative station endpoint anchors. This is decoded canonical geometry, not untouched survey data.
- **显示几何 / teal:** actual `DisplayParts.parts`, with topology, grooming and station approaches, keeping separate branches/parts separate.
- **平滑 / pink:** these display parts processed independently through production `ContinuousStroke.buildStroke` with shared `RailStyle` tokens, zero lane offsets and protected station vertices. No secondary simplification.
- **叠加对照:** teal display input plus pink smoothed geometry.
- **底图:** Apple basemap only.

Use actual track drawn on the basemap as the reference. A station symbol, entrance, POI or platform centroid does not establish track position. Where the basemap hides/omits track (including tunnels), this tool cannot determine alignment. A discrepancy records disagreement with Apple's depiction, not which source is correct.

This is **isolated centreline smoothing with partial production parity**. Main-app corridor lanes, canonical follows, neighboring joins, withheld spans, family collapse, LOD and ridden-route composition are outside this preview. No package coordinates, routing topology or smoothing parameters are edited. Japan uses WGS84 with no datum shift.

**导出视点记录** writes a JSON file chosen through the system save UI: package version, line/station IDs, mode, opacity, center, logical-point viewport, zoom/scale and timestamp. It includes the saved viewport verdict, exact interval inputs, renderer contract and review scope. It contains no measured Apple track-pixel residual or automatic geographic verdict. Loading and rendering the basemap requires network access.

Focused build/observation results are recorded in `docs/superpowers/completed/2026-10-10-rail-alignment-inspector.md`. Do not run retired nationwide verification or capture pipelines for this tool.

## Full checking plan and review workflow

The **检查队列** enumerates every Japan station interval, including loop closure and missing geometry. In the observed package there are **657 lines and 9,579 intervals**, with no extra-edge fields. Both source and effective display geometry contribute cheap triage signals: invalid/missing coordinates, long chords, substantial turns, reversals, sparse intervals and display overrides. A long straight track or switchback is a candidate, never an error or a pass. Search also accepts station names and the stable `lineID#intervalIndex` key.

1. Select a queue item. Compare decoded, final display and real smoothing against actual drawn railway track, including approaches and both attachment boundaries.
2. Start **从首个详细视点开始**, then move through the interval's camera targets approximately every 350 metres at z17. The final short tail is retained; targets do not change rail geometry. z17/z18 buttons set a reproducible detailed scale.
3. Save a scoped verdict and a nonempty note. Use **底图证据不足** for missing/ambiguous track. A conclusion about one viewport does not certify a long interval. Repeated observations are retained rather than replacing earlier camera coverage.
4. **导出同视点证据** exports a folder containing one MapKit basemap snapshot, separate display/smooth overlays, an optional reference overlay, and `view.json`. Batch capture accepts `captureSettings.basemapStyle`: `standard` (default) or `imagery`, also exposed by the task composer’s Basemap picker. Both use the same snapshot and evidence path; imagery receipts have a distinct style contract. Camera, geometry and style are frozen before the asynchronous snapshot. Every overlay uses the returned snapshot coordinate mapping. Evidence images use opaque overlays, independently of the UI opacity. This is a native MapKit snapshot, not a screenshot of the live view.
5. **导出完整计划** exports all queued items, current reviews, observation history, stale count and per-line summaries. Actual exported paths are attached only after save succeeds.

Reviews live in `~/Library/Application Support/RailAlignmentInspector/reviews.json`. Freshness checks exact source/display coordinates, endpoint station IDs, actual full-line DisplayParts output, the inspector's explicit renderer contract and any matching loaded reference. Older incomplete records remain readable but stale. Increment the contract when changing projection or smoothing semantics. A custom reference is scoped to the selected interval when it lacks scope metadata; re-import it in a later session to restore that reference-dependent validity.

Counters distinguish viewport conclusions from **detailed spatial coverage**. The latter requires current non-pending/non-insufficient observations at z17 or closer covering 20m samples along the effective interval within a 20m viewport margin. This describes observed extent, not proof that all basemap detail was visible or that every renderer branch aligned. The pending filter retains partially covered intervals.

The viewport diagnostic is a **one-sided sampled nearest-polyline distance**, not a certified maximum or an Apple pixel residual. Chords are densified, sampling is capped, and exported diagnostics report candidate/sample counts, included part indexes, spacing bound and whether the cap reduced sampling. External-reference comparison is restricted to the intersection of the viewport and reference bounds; it cannot certify track identity or unrepresented reference tails. Source/display plan statistics precede final DisplayParts grooming.

**导入轨道 GeoJSON** accepts a single scoped WGS84 LineString/MultiLineString reference. Orange tracks are independent evidence, not automatic snapping or routing topology. The bundled Tabata example identifies the OSM outer-direction representative track and retained cache date; inspect directional track identity before treating a nearest match as alignment.

## Resumable automatic capture

RailDiagnostics owns automatic capture requests. Specify the exact line (plus optional interval/station intersection), zoom, viewport, appearance and output modes. The app plans overlapping complete-interval camera targets, retains endpoints and short tails, captures one native snapshot at a time and returns `run-status.json`, `result.json` and `capture-index.json`. Resume the same immutable request; incompatible settings or inputs require a new session and leave original evidence intact. Failed views require explicit scoped retry.

Snapshots are isolated centreline evidence. Native production lanes, neighboring joins, family collapse and station circles remain separate Main questions. Source/display diagnostics do not measure Apple pixel residuals. See the unified README for supported settings, launch syntax and human controls. Historical z17/1024×768 captures retain their original fixed-scale contract; they are not silently promoted to the new requested-scale contract.

## Logo

`Assets.xcassets/InspectorLogo.imageset/logo.png` is the generated source logo. `AppIcon.appiconset/icon-1024.png` is its 1024px app-icon rendition. It is used in the native app icon and header.

Generated with the built-in `image_gen.imagegen` tool using the brief: “production app icon, a flowing railway curve with two parallel luminous strokes and sleepers under an inspection lens/focus ring; deep navy, teal and a small coral accent; full-bleed opaque square, no baked outer corners, no text.” The source image and the generated native `AppIcon.icns` were visually inspected; resizing with `sips` only prepares the platform icon asset.

## Observed results (2026-10-10)

The 10 focused InspectionKit tests passed, along with the four existing Tabata repair tests. The final incremental Catalyst build succeeded and its bundled Japan package equals the current source. Native observation confirmed queue selection, detailed viewpoint navigation, reference scoping, evidence-folder export, verdict persistence/relaunch and the logo. The complete exported queue is `docs/reports/integration/japan-rail-inspection-plan-2026-10-10.json`; it has two scoped conclusions and one interval with detailed spatial coverage, not nationwide acceptance. Main-app lanes/joins remain outside this evidence.
