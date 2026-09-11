# Parallel railway zoom repair and platform validation

## Implemented behavior

- Continuous strokes retain significant surveyed bends through simplification and rounding. Inner offsets are constrained before they reverse curvature; lane recovery is gradual. Short edges that cannot fit a valid fillet retain a corner instead of producing a reversed arc or a shortcut.
- Native constructed fillets have an absolute 1 pt radius floor, increasing to 3 pt at full railway weight. This is a construction constraint at the settled drawing scale; MapKit transforms the retained geometry while the camera moves.
- Value geometry is prepared off the main actor. Native overlays are materialized only after accepting the current request generation. Stable 129-vertex chunks and geometry/overlay reuse limit repeated work.
- Interior chain-measure lookup uses binary search, with regression coverage against the former interpolation semantics across duplicate measures, subranges, endpoints and 40,001 vertices.
- Pinch, pan and rotation defer geometry rebuilds and style mutations. Camera quiet-period scheduling also covers wheel and inertial movement. Playback continues to apply its own frame style.
- Map replacement preserves the camera and cancels outgoing geometry, camera, resize and matching tasks. Narrow landscape phones use a docked panel from 632 pt wide, preserving at least 300 pt for the map.

## Geometry validation

The production native geometry audit examined all seven shipped regions at app zooms 10–16: **zero skipped-bend chord candidates**. Orange was additionally checked at 33 fractional zooms from 12–16: **zero chord or crossing candidates**.

The broad audit retained 30 crossing review locations. These were reviewed as source loops, existing source touches/grade separation or subpixel closures; this result does not assert that every geographic crossing is erroneous or that all source data is perfect.

## Runtime coverage

The representative suite contains five cases: Japan network zoom, Hoboken/Newport dense branches, device rotation followed by Hudson zoom, landscape Orange, and two-finger map rotation followed by zoom. Each case performs five alternating pinches. Assertions cover camera progress, visible railway colors, nonempty geometry, viewport coverage, zero vertex-budget drops, zero gesture-time rebuilds and a 150 ms maximum display-link delivery gap.

| Simulator | Runtime | Recorded result | Maximum gap in passing representative runs |
| --- | --- | --- | --- |
| iPhone SE (3rd generation) | iOS 26.5 | Final five-case suite passed | 35 ms |
| iPhone 17 Pro Max | iOS 27.0 | Five-case suite passed | 83 ms |
| iPad Pro 13-inch (M5) | iPadOS 27.0 | Five-case suite passed | 115 ms |
| iPad Pro 11-inch | iPadOS 26.5 | Four cases passed; separate rotation repetitions passed twice, then XCTest event synthesis timed out | 83 ms |

Earlier iOS 26.5 runs recorded intermittent 203–319 ms gaps. The gate was not increased. Isolated Hoboken repetitions included 203 ms, 37 ms and 42 ms; a separate profiled cold launch passed at 58 ms. The passing profile spent 84.5% of main-thread samples idle, with most active rendering samples in VectorKit/Metal. It did not establish the cause of the failed runs. Annotation layout was not changed on the basis of that profile.

**Performance acceptance remains incomplete:** passing representative runs do not establish zero stutter on every supported device. The unresolved intermittent timing failures remain in the validation record. Display-link delivery measures main-run-loop gaps, not GPU frame presentation.

## Build and execution scope

- Final core and architecture gate on the shared source: 551 tests passed.
- Unsigned Release builds: generic iOS device and Mac Catalyst (arm64 and x86_64).
- Minimum supported iOS version remains 17. Installed simulator runtimes were 26.5 and 27.0. Older OS runtime behavior and physical-device performance were not verified; Catalyst was compile-checked, not interactively profiled.
- The small SE landscape screenshots confirm that the map remains exposed and the Orange bend retains its curved alignment.

Reproduce geometry checks with `ios/tools/audit-zoom-chords.py --check-orange --fail-on-candidates`. Run selected simulator cases serially with `ios/tools/verify-zoom-platforms.py`; see `ios/README.md` for invocation and the `--full` option. Use idle simulators and avoid concurrent builds during timing measurements.

Local diagnostic evidence from this session: `/tmp/jtm-platform-final-chords.json`, `/tmp/jtm-platform-screen-matrix/summary.json`, `/tmp/jtm-platform-layout-final/summary.json`, `/tmp/jtm-final-se-suite/summary.json`, `/tmp/jtm-ipad-rotation-repetitions.xcresult`, and `/tmp/jtm-se-hoboken-profile.sample.txt`. The `.xcresult` bundles retain screenshots and assertion details.
