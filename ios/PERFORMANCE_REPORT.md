# iOS performance pass — what was measured, what moved, what did not

## 0. What this report can and cannot claim

Read this first, because it decides how every number below should be taken.

**No physical device was available.** `xctrace list devices` reported this
Mac's two paired iPhones as offline for the whole session, and the simulator
control panel was unavailable. So there is **no Instruments trace in this
report** — no Time Profiler, no Hangs, no Animation Hitches, no Allocations, no
Energy Log. Every claim is labelled with what actually backs it:

| Label | Means |
| --- | --- |
| **benchmark-backed** | measured by `ios/tools/bench`, release, on real repository data, median of ≥5 runs on this Mac |
| **code-backed** | derived from reading the code and from counts that are exact (how many `MKMapView.convert` calls a tap makes), but whose *time* on a device is not measured |
| **instrumented** | signposts are in place and the phase can now be recorded, but the recording has not been taken |

Nothing in this report is trace-backed. Where the prompt's acceptance criteria
ask for a device-measured percentage, §7 says so plainly and names the exact
trace to take.

The host benchmarks are a lower bound and a statement about *proportion*. They
cannot see MapKit, SwiftUI, storage or the memory system — which is why the
work below is split into "the arithmetic, measured" and "the frame, instrumented".

### 2026-08-28 revalidation

The finished working tree was revalidated on `too-simple.local` (Apple
silicon, macOS 27.0 build 26A5421a, Xcode 26.6) with the shipped data and a
Release `RailBench` build. Each benchmark line is nine measured runs after two
warm-ups; the table reports median / p95. These are host measurements, not a
replacement for the device matrix requested below.

| Scenario | Baseline | Optimized | Current p50 / p95 |
| --- | ---: | ---: | ---: |
| Map tap, city z15, 9 taps | full projection | chunk cull | 15.660 / 15.705 ms → **0.086 / 0.090 ms** |
| Map tap, national z5, 9 taps | full projection | chunk cull | 15.776 / 15.842 ms → **0.067 / 0.075 ms** |
| Route-cache read, 201 files / 6,962 KB | sequential | four-wide, ordered | 56.295 / 57.241 ms → **19.931 / 21.900 ms** |
| Statistics matching, 201 journeys | full reload | one changed journey | 480.691 / 523.147 ms → **1.897 / 1.927 ms** matching |
| Editor validation, 217 stops | authoritative path | deliberately unchanged | **3.605 / 3.633 ms** |

`swift test --scratch-path /tmp/jtm-performance-railkit` passed 403 tests in
41 suites. The end-to-end `verify.sh` gate passed 405 parameterized cases,
built `RailMap.app`, and reported zero warnings in `RailCore`,
`RailPresentation`, and `RailMap`. One pre-existing test-only warning found by
the prescribed command was removed by making an immutable counter a `let`;
the parity assertion and runtime behavior are unchanged.

**The working tree was being edited concurrently by another process during
this session.** Files that are none of this pass's business (`MapControlBar`,
`RideChooserView`, `StationCardView`, `docs/`, a UI-test probe) appeared and
changed while it ran; one of them broke the app build for a few minutes at
02:28 and then fixed itself. Nothing here was reset, stashed or reverted.

**A pre-existing gate failure was left alone, and resolved itself.** For most
of the session `./verify.sh` stopped at

    FAIL: an Apple Maps link is built outside StationPlaceLink
      ios/RailKit/Sources/RailCore/AppleMapsLink.swift

`AppleMapsLink.swift` is untracked, in-flight work that predates this session
(it is in the session's opening `git status`), and the check is a contract
whose intent belongs to whoever is writing that port — not this pass's to
change. While it was open, the app half of the gate was run separately, command
for command, from the same file. The concurrent editor cleared it before the
end, and the final run is green from `== JavaScript ==` to `OK`; see §6.

---

## 1. The five that mattered

### 1 — A tap on the map cost the whole store, not the finger

**Root cause.** `RailMapView.Coordinator.handleMapTap` built its candidate list
by projecting **every vertex of every ride** into screen space:

```swift
let candidates = rides.map { ride in
    RideTapResolver.Candidate(id: ride.id, strokes: ride.strokes.map { stroke in
        stroke.map { mapView.convert($0.clLocation, toPointTo: mapView) } })
}
```

On the shipped national sample that is **180,447 `MKMapView.convert` calls and
2,303 freshly allocated point arrays, per tap** — including the taps that land
on open sea and the ones whose only job is to clear the selection. The cost is
a function of how much the reader has ridden, not of what is under their
finger.

**Fix.** `RailMap/RideTapIndex.swift`. Each stroke is cut into 64-segment
chunks, each chunk keeps the bounding box of its vertices in `MKMapPoint`
space, and a tap projects only the chunks whose box is within the tolerance of
it. The index is built once per ride generation and survives every pan and
zoom, because the boxes are in map space and the camera is not.

**Why the answer cannot change.** Three facts, and all three are load-bearing:

1. A box contains every vertex of its chunk and a box is convex, so no point of
   any segment between two of those vertices is nearer to the tap than the box
   is. A rejected chunk could not have won.
2. `RideTapResolver.hits` scores a ride by the **minimum** distance over its
   segments, and only ever reads that minimum when it is within the tolerance.
   Dropping segments that are further away than the tolerance cannot move it.
3. The comparison happens in one linear space. While the camera is unpitched,
   `MKMapPoint` → view point is a similarity — one rotation, one uniform scale,
   one translation — so a tolerance converted once is exact everywhere on
   screen. A **pitched** camera, or a view straddling the antimeridian, has no
   single scale; both decline the cull and project everything, exactly as
   before.

**Numbers** (benchmark-backed; `RailBench tap`, release, 201 rides / 2,303
strokes / 180,447 vertices, projection modelled as plain arithmetic):

| | projections per tap | 9 taps, median | per tap |
| --- | ---: | ---: | ---: |
| city z15, project everything | 180,447 | 17.48 ms | 1.94 ms |
| city z15, cull then project | **≤ 674** | **0.085 ms** | **0.009 ms** |
| national z5, project everything | 180,447 | 17.59 ms | 1.95 ms |
| national z5, cull then project | **≤ 253** | **0.065 ms** | **0.007 ms** |
| index build, once per ride generation | — | 0.31 ms | — |

The modelled projection is *much* cheaper than MapKit's, which crosses into
VectorKit and takes the map view's own lock — so the 206–270× ratio understates
the device. The **projection count** carries over exactly and is the honest
headline: a tap does 0.37 % of the MapKit conversions it used to.

The index build was 10.5 ms until the boxes stopped being computed by
projecting every vertex: Mercator is monotone on each axis independently, so
the corners of a run's lon/lat box are the corners of its map-point box, and
two projections per chunk replace one per vertex.

**Checked by** `RideTapCullTests` — chunk coverage (every segment in exactly
one chunk, for every length 0…300 at four chunk sizes), the box distance metric
including the corner case a `max(dx, dy)` version gets wrong, and a
thousand-tap property test over generated geometry asserting the culled answer
equals the full-scan answer exactly.

---

### 2 — The playhead rebuilt the entire workspace, sixty times a second

**Root cause.** Two compounding defects.

`PlaybackController.progress` is `@Observable` and written on every display-link
tick. The transport that read it was **eleven computed properties on
`RailWorkspaceView`** — `playbackProgress`, `playbackIdentity`, `speedReadout`,
`videoControl` and the rest — so those reads were attributed to
`RailWorkspaceView.body`. Every tick therefore invalidated that body: the map's
inputs, the journey list and all its rows, every derived summary, the whole
sheet's content.

`stationName` made it worse: `@Observable`'s generated setter does not compare,
so writing the same station name sixty times a second invalidated every reader
sixty times a second for a value that changes a few times a minute.

**Fix.**

- `RailMap/PlaybackTransportBar.swift` — the transport is a view of its own.
  The reads happen in its body, so the invalidation stops there. Nothing about
  what is drawn changed; the three decisions it cannot own (stop and restore
  the selection, open the export options, what "play" currently means) arrive
  as closures.
- `progress` publishes on a **20 Hz ladder**, with 0 and 1 forced so a run
  always ends on a full bar. `exactProgress` carries the per-frame value for
  the renderer and is `@ObservationIgnored`.
- `stationName` is written only when it changes.
- `exportFrameSerial` is `@ObservationIgnored` — it was write-only, and leaving
  it observable was a 60 Hz rebuild waiting for its first reader.

20 Hz is chosen against what the value drives: a `ProgressView` at most 540
points wide, which interpolates nothing, advancing in steps narrower than the
rounded cap already drawn on its end.

**Status: code-backed.** The mechanism is certain — SwiftUI's observation
tracks reads per body, and the reads moved — but "how many body updates per
second, before and after" needs the SwiftUI instrument on a device. §7 names
the trace.

---

### 3 — One body evaluation asked the same expensive question three times

**Root cause.** `RailWorkspaceView` is one struct and everything it shows is a
computed property on it, so a single body pass calls `filteredDays` up to three
times: the header's count (`panelSubtitle`), the list itself
(`journeyListState`), and `playbackScope`, which the play button's `.disabled`
reads. With a query in the search field each of those is a locale-aware
substring search over every field of every journey.

`todayByRegion()` builds five `Calendar`s and reads five time zones per call,
and is called twice by `launchRegion` alone. `mapRides` rebuilt a `Set` of the
statistics scope's ids on every pass. `rideIDs` and `riddenCountries` were two
separate walks over every drawn ride.

A body pass is not a rare event: a sheet drag is one per frame.

**Fix.** `RailMap/WorkspaceDerived.swift` — a plain reference type held in
`@State`, memoising each answer against the **generation** of its inputs
(array buffer identity plus count, the same O(1) trick `RailMapView` already
uses) rather than against a summary of them. It is not observable and nothing
observes it, so filling a cache during a body evaluation invalidates nothing;
every entry is a pure function of its key, which is the whole correctness
argument.

`todayByRegion` is held for one second — long enough to make a drag free, short
enough that being late to notice midnight is not observable, and still one
`Date()` for all five regions within a call, which is the property the original
was written for.

**Numbers** (benchmark-backed; `RailBench search`, 201 journeys / 4,112
searchable strings): `filteredDays` with a query is **4.9 ms** per call on this
Mac. Three calls per pass became one.

The search predicate itself was measured and left alone. A flat ICU scan over
the same 4,112 strings costs 77.4 ms for 16 keystrokes — *more* than the
matcher's 73.5 ms, because the matcher short-circuits. The cost is
`localizedCaseInsensitiveContains`, three spellings of which measured within
8 % of each other, and the contract is written in it. What did change is that
`JourneySearchMatcher.matches` no longer re-trims the query per journey or
materialises the field array before the first comparison: 77.7 → 74.3 ms
(−4.4 %), pinned to `fields(of:)` by a new parity test over the real store so
the two spellings of the field list cannot drift.

---

### 4 — The station picker sorted 9,039 stations on every keystroke

**Root cause.** `RideEditorView.StationPickerView.filteredStations` did three
things in one computed property — de-duplicate by station code, sort by
`localizedStandardCompare`, filter by the query — and SwiftUI re-evaluated all
three per character. Only the third depends on the query.

Separately, `RailNetworkStore.stations(in:)` filtered all ~20,000 platforms of
five regions per call, and it is called from inside a `NavigationLink`'s
destination — which SwiftUI builds on every body evaluation of the stop editor,
i.e. on every character typed into the station-name field above it.

**Numbers** (benchmark-backed; `RailBench stations`, jp: 10,217 rows / 9,039
distinct codes):

| | per keystroke |
| --- | ---: |
| de-duplicate + `localizedStandardCompare` sort | 46.6 ms |
| filter (three locale-aware searches × 9,039) | 22.9 ms |
| **total, as shipped** | **≈ 70 ms** |

Seventy milliseconds of main thread per character, on a machine several times
faster than the phone.

**Fix.** The sort moved to where its input changes — once per station list, off
the main actor. The filter moved off the main actor behind a **120 ms
debounce**, cancellable, with the previous query's task cancelled on each
change. Clearing the field is answered synchronously and immediately, because
its answer is already in hand and "I deleted my query" is owed on the same
frame. `stations(in:)` groups once per generation of `stations` instead of
filtering per call; grouping preserves relative order, so the answer is the one
`filter` gave.

Main-thread work per keystroke: **≈ 70 ms → the text field's own update.**
The predicate is unchanged — same three fields, same order, same locale-aware
search. What changed is when it runs.

---

### 5 — Every statistics reload re-matched every journey

**Root cause.** The numbers reload whenever the record changes — the shell's
route key is the whole `[Train]`, so that is *every* edit — and
`MileageStatisticsStore.matchRides` ran `collectTrainStatsEntry` over every
journey each time, walking every vertex of every segment against the edge
index.

**Numbers** (benchmark-backed; `RailBench statistics`, jp sections 11 MB →
377,620 edges / 27,263 km, 201 journeys):

| phase | median |
| --- | ---: |
| read + index `rail-sections.json` | 1,598.5 ms (once per region, already cached) |
| **match all 201 journeys** | **425.0 ms** |
| match one journey | 1.96 ms |
| aggregate (`buildMileageStatsView`) | 21.6 ms |

**Fix.** An entry cache keyed on a digest of exactly the four things
`collectTrainStatsEntry` reads — the drawn geometry (via the ride's existing
`geometryDigest`), each section's `from`/`to`, the stop fields `isRideSegment`
consults, and which index it was matched against. A key built from fewer would
reuse an entry the reader's edit had invalidated, which is a mileage figure
that silently does not move. The cache is rebuilt from the journeys each load
actually saw, so a deleted journey's entry leaves with it.

An edit now costs **1.96 ms of matching + 21.6 ms of aggregation ≈ 24 ms**
instead of **447 ms** — 18× on the reload path.

---

## 2. The rest of the changes

**Concurrent region index builds** — `EdgeIndexCache.merged(countries:)`
awaited one region before starting the next, so the first 全部 statistics of a
launch paid five reads and five index builds back to back for five files that
share nothing. They now build in a task group and are merged in the order they
were asked for, because `merge` is order-sensitive (edge offsets index into the
arrays they are laid beside, and which region's spelling of a shared line name
wins is decided by position). Unbounded over five is bounded in fact: Japan is
12.1 MB of sections and the other four are 1.7 MB together, so the peak is
Japan's decode either way.

The same file had an in-flight bookkeeping defect: the entry was cleared in a
`defer` on the *awaiting caller*, so a caller cancelled mid-wait removed a build
that was still running and the next ask started a second one over the same
12 MB. It is now cleared by the build's own completion, and only if it is still
that build.

**Concurrent route-cache reads** — `loadCached` read and decoded one journey's
cache file at a time. Benchmark-backed over the shipped sample's 201 parts
(same count, same shape, 6,962 KB): **58.4 ms sequentially, 25.3 ms four at a
time**, against 4.7 ms for all 201 cache digests. Four rather than "as many as
there are" for memory: each task holds one file's bytes and its decoded
coordinates at once. **The order is the sequential version's** — results are
placed by index and read back in order, because that order reaches the map as
the order overlays are added in, and therefore which line is drawn over which.

**The map's marker cache key** — `markerRecords` keyed its cache on
`rides.map(rideSignature).joined(separator: "|")`: 201 freshly built strings
and a join of them, on every rebuild, i.e. every zoom tier crossed and every
pan out of the built rect — inside the gesture. It is now an integer digest of
the same fields, kept field-for-field in step with `rideSignature` so the two
cannot come to disagree about what a change is.

**The measurement layer** — `RailMap/RailSignpost.swift`. `OSSignposter`
rather than `NSLog` because the interesting build is a *release* build during a
gesture, and when no tool is recording a begin/end pair is a load, a branch and
a return. Two gates: the tool's `isEnabled`, and `RAILMAP_SIGNPOSTS=0`, so the
instrumentation's own cost can be measured against the same binary. Intervals
are `begin`/`end` paired through `defer`, which is the one spelling that
survives every early return a `guard` can take. Named intervals now in place:

    map.rebuild            map.rebuild.geometry     map.rebuild.teardown
    map.rebuild.networkOverlays                     map.rebuild.rideOverlays
    map.rebuild.markers    map.tap                  map.tap.projected (count)
    map.tapIndex.build     playback.tick
    data.package.decode    data.edgeIndex.build
    route.cacheRead        route.datasetLookup
    stats.readNetwork      stats.matchRides         stats.aggregate
    itinerary.group        video.frame              ocr.recognize

**The benchmark harness** — `ios/tools/bench`, a separate SwiftPM package
depending on RailKit by path so it measures the shipped sources, reading the
real fixtures. It is not a test target on purpose: the gate has to answer pass
or fail quickly, and what is wanted from a benchmark is a number.

---

## 3. Two things measurement said not to do

This is the more useful half of a benchmark, and both were on the plan.

**Moving the map rebuild's geometry off the main actor.** The obvious P0. But
the geometry — level of detail, Douglas–Peucker, the vertex budget — is
benchmark-backed at **6.7 ms at a national zoom, 13.1 ms regional and 24.2 ms
at a city zoom** over the *whole* Japanese network (652 lines, 9,568 intervals,
394,285 vertices), before the visible-rect cull that normally removes most of
it. Against a rebuild this repository's own README records at 150–460 ms, that
is at most a sixth of the cost, and it is the only part that could move:
`MKPolyline` construction, `removeOverlays`/`addOverlays` and the annotation
work are MapKit objects that may not cross an actor boundary. Building the
machinery — a `Sendable` build plan, a generation token, a diffing apply — for
a sixth of a cost that is not the bottleneck is exactly the "possibly faster,
definitely more complex" this pass was told to refuse. The phases are
instrumented instead; §7 names the trace that would settle it.

**Debouncing the editor's validation.** `RideEditorView` re-runs the whole of
`TrainValidation.validateTrain` on every draft change. Measured on the longest
real journey in the store — 217 stops — encode plus validate is **3.9 ms**.
Inside a frame, on the worst record that exists. A debounce plus a
"revalidate synchronously before save" path is real complexity bought with
nothing.

Two more were looked at and left: the video exporter's per-frame path is
already caching its context, caption layout and colours, throttling to the
frame interval and honouring `isReadyForMoreMediaData` (with `verify.sh`
contracts pinning all of it), and its autorelease growth is already bounded by
the run loop's own pool once per display-link callback; and duplicated
`normalizeExportTrain` calls in the route store are 2.7 ms per 201 journeys
against 58 ms of file I/O in the same path — under 5 % of it.

---

## 4. Results by operation

Host benchmarks, release, real data. **Not device numbers** — see §0.

| Operation | Before | After | Backing |
| --- | ---: | ---: | --- |
| Map tap, MapKit conversions | 180,447 | ≤ 674 | benchmark |
| Map tap, arithmetic (9 taps) | 17.5 ms | 0.085 ms | benchmark |
| Tap index build (per ride generation) | — | 0.31 ms | benchmark |
| Station picker, main thread per keystroke | ≈ 70 ms | text field only | benchmark |
| Journey search, `filteredDays` calls per body pass | 3 | 1 | code |
| Journey search, per keystroke | 4.9 ms | 4.6 ms | benchmark |
| Statistics reload after one edit | 447 ms | 24 ms | benchmark |
| Warm route cache read, 201 journeys | 58.4 ms | 25.3 ms | benchmark |
| First 全部 statistics, five region indexes | sequential | concurrent | code |
| Playback, workspace body invalidation | 60 Hz, whole view | 20 Hz, transport only | code |
| Map rebuild marker-cache key | 201 strings + join | one integer | code |
| Map rebuild, geometry phase | 6.7–24.2 ms | unchanged | benchmark |
| Editor validation, 217 stops | 3.9 ms | unchanged | benchmark |

Not measured, and not claimed: cold and warm launch, sustained pan and pinch,
sheet-drag hitches, 1 MB import, OCR, video export, memory peaks, CPU and
energy. Every one of those needs the device that was not available.

---

## 5. Files, and the new boundaries

**New**

| File | What it owns |
| --- | --- |
| `RailMap/RideTapIndex.swift` | the tap cull; a **generation boundary** (invalidated when `rides` changes) and a **fallback boundary** (declines on pitch or an antimeridian view) |
| `RailMap/WorkspaceDerived.swift` | the workspace's memoised answers; **generation boundaries** keyed on array buffer identity, plus `ArrayGeneration`, the shared O(1) generation test |
| `RailMap/PlaybackTransportBar.swift` | §5.6's transport; an **observation boundary** — the playhead is read here and nowhere above |
| `RailMap/RailSignpost.swift` | the measurement layer |
| `ios/tools/bench/` | the benchmark harness and its README |
| `RailKit/Tests/RailPresentationTests/RideTapCullTests.swift` | the cull's correctness property |

**Changed**

| File | Change |
| --- | --- |
| `RailKit/Sources/RailPresentation/RideTapResolver.swift` | `Bounds`, `chunkRanges` — the pure arithmetic the cull rests on |
| `RailKit/Sources/RailPresentation/JourneySearchMatcher.swift` | `matches(_:trimmed:)`, the short-circuiting field walk |
| `RailMap/RailMapView.swift` | tap goes through `RideTapIndex`; marker cache key is a digest; rebuild phases instrumented |
| `RailMap/ContentView.swift` | derived answers memoised; transport extracted |
| `RailMap/PlaybackController.swift` | 20 Hz published progress, `exactProgress`, guarded `stationName`, non-observable `exportFrameSerial` |
| `RailMap/MileageStatisticsStore.swift` | per-journey entry cache; **cache-invalidation boundary** on the index key |
| `RailMap/EdgeIndexCache.swift` | concurrent region builds; **cancellation boundary** fixed so one cancelled waiter cannot drop a live build |
| `RailMap/RiddenRouteStore.swift` | `loadCachedConcurrently` — bounded 4-wide, order preserved, cancellation-checked |
| `RailMap/RideEditorView.swift` | station picker: sort hoisted, filter debounced and cancellable |
| `RailMap/RailNetworkStore.swift` | `stations(in:)` grouped once per generation |
| `RailMap/ItineraryStore.swift`, `PlaybackVideoExporter.swift`, `TransferGuideOCR.swift` | signposts only |
| `ios/README.md` | the performance section brought up to date |

Nothing was added to `RailCore`. `RailPresentation` gained pure arithmetic
only, and still imports nothing but Foundation and `RailCore`. No third-party
dependency. `ContentView.page(...)`'s `AnyView` and the `WorkspacePage`
boundary are untouched.

---

## 6. Gates

    cd ios/RailKit && swift test --scratch-path /tmp/jtm-performance-railkit
    → 403 tests in 41 suites passed

    ios/verify.sh
    → OK

Green end to end on the final run — JavaScript fixtures, the Swift package, and
all seventeen app contracts:

    fixtures match the code that generated them · RailCore and RailPresentation build ·
    405 parameterized cases pass · no warnings in RailCore or RailPresentation ·
    RailCore imports nothing but Foundation ·
    RailPresentation imports nothing but Foundation and RailCore ·
    both renderers decimate to the same 0.0625 pt ·
    the annotation layer is used by the map and nothing else ·
    Taiwan, Hong Kong, Macao and Korea enter Apple Maps in GCJ-02 ·
    every station link is built by StationPlaceLink

(`verify.sh` counts parameterized cases individually and reports 405;
`swift test` reports 403 tests. Same suite, two counting conventions.)

    RailMap.app builds · no warnings in RailMap · 476 popup badge paths resolve ·
    the app icon composes 2 layers · every surface that edits a journey persists it ·
    a sample loads into its own region · editing a journey reloads what the map draws ·
    playback survives a tab switch · playback frames retain completed overlays ·
    playback camera and basemap opacity use narrow invalidation ·
    every package read is single-pass · a dataset is scanned once ·
    the route cache is swept once per launch · saved stores are atomic and canonical ·
    journeys group in one pass · the working set has one writer ·
    the video exporter stays on the main actor

The three performance contracts this pass could have tripped still hold: the
two `douglasPeuckerIndices(…epsilonMeters: epsilon)` call sites are still in
`RailMapView.swift`, the epsilon is still derived from
`RailStyle.simplifyTolerance`, and the annotation classes are still named only
by the map.

**Simulator smoke test.** A Debug build was installed on the iPhone 17 Pro
simulator (iOS 26.5) and launched twice: once empty, and once with the
201-journey national store seeded into its container. Both launch, the map
draws, and the national store's routes render across Japan (screenshot taken).
One rebuild reported `z=3.99 … overlays=201 ridedots=403 209ms`. That is a
Debug build on a simulator and is a smoke test, not a measurement.

---

## 7. What is left, and the exact traces to take

Every item here needs the device that was unavailable.

**1. The map rebuild's real distribution.** The single most valuable trace.
Record `os_signpost` filtered to `com.jtm.railmap` / `map`, on a release build,
while panning across LOD thresholds and pinching through several zoom tiers
over the Japanese network with the complete-network layer on:

    xcrun xctrace record --template 'Blank' --instrument 'os_signpost' \
        --device-name '<device>' --attach RailMap --output map.trace

Read `map.rebuild` against the sum of `map.rebuild.geometry`,
`.teardown`, `.networkOverlays`, `.rideOverlays` and `.markers`. The hypothesis
this pass could not test is that `.networkOverlays` (`MKPolyline` construction)
and `.teardown` dominate. If they do, the next move is incremental overlay
diffing rather than a background build plan, and `map.rebuild.geometry` should
be left where it is.

**2. SwiftUI body updates during playback and a sheet drag.** Instruments'
SwiftUI template, "View Body Updates". The claim to check is that
`RailWorkspaceView`'s body no longer appears at the playhead's cadence, and
that `JourneySummaryRow` rows other than the playing one do not update per
frame. `presentation(for:)` still reads `playback.progress` for the *current*
journey inside the parent's body — the value is discarded by the resolver, so
if the trace shows this still costing, the honest fix is to drop the unused
associated value from `JourneyWorkspacePhase.playing` rather than to read a
stale one.

**3. Cold and warm launch.** App Launch template, plus `data.package.decode`
and `route.cacheRead` signposts, cold after a reboot and warm. The question the
concurrent route-cache read raises: does 4-wide reading contend with the five
concurrent package decodes at launch, and would 2-wide be better under that
contention? The host has neither the flash nor the thermal envelope to answer.

**4. Memory.** Allocations plus Leaks across: five concurrent package decodes,
five concurrent edge-index builds (the new one), a long video export, and an
OCR run near the pixel ceiling. The edge-index change is the one that raised a
peak; the reasoning that Japan dominates it either way is written down in the
code and has not been checked against a device.

**5. Hitches.** Animation Hitches during sustained pan, pinch and sheet drag,
before and after. This pass removed work from those paths by argument, not by
measurement.

**6. Untouched by this pass**, and each named in the original plan: the OCR
pipeline's decode/scale/recognise/stitch split (instrumented only), the import
preflight and commit, `ItineraryStore`'s save coalescing, and `StationPlaceStore`'s
cancellation behaviour. None had a benchmark that could be built without a
device or a live network, and none was changed on a hunch.
