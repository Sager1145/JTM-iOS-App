# Apple UI source index — native SwiftUI railway and journey app

STATUS: READY — research handoff, not an app audit result.

Research date: 2026-10-13. Sources are official Apple HIG, documentation, Tech Talks, and WWDC pages. No local application was inspected, built, tested, or modified. No hardware dimensions or performance characteristics are assumed.

## Use and evidence boundaries

Use the current Duo Tech Talks alongside the HIG. Older foundational sessions remain useful for the specific mechanisms cited; they do not override current SDK declarations. “Reference page located” means the official page was identified, not that every declaration or its current availability was verified. Resolve overloads and availability in the actual installed SDK before implementation.

Some Apple documentation pages are JavaScript-rendered. The listed JSON URLs were readable during this research and can be useful for downloading the relevant text and reference metadata. They are web publishing endpoints, not a promised stable public API. This package is a link index, not an offline archive of Apple documentation. It contains no complete copied Apple documents.

## Product constraints and proposed audit order

Preserve the app's existing font families, typography hierarchy, numeric bounds, Dynamic Type policy, supported-orientation declarations, and established orientation-dependent product behavior. Those exact values were not supplied. Codex must read and record them before changing layout. A conflict with accessibility guidance is a finding to report, not permission to silently alter product policy.

Proposed order (application-specific inference):

1. Record the local Xcode build, build SDK, simulator runtime, product constraints, and map renderer.
2. Correct actual-window geometry, independent safe-area edges, bars, keyboard avoidance, and any custom reserved-region handling.
3. Preserve map lifetime, selected station/journey, draft inputs, navigation history, focus, and panel semantic state through resizing.
4. Audit typography reflow, target bounds, VoiceOver task equivalence, contrast, and reduced-motion/transparency behavior.
5. Exercise loading, no-results, no-route, denied-location, offline, retry, and cancellation paths separately.
6. Profile the same representative dense map and journey workflows before and after changes; do not infer hardware performance from simulator timing alone.

The source links below provide the documented basis. Railway-specific architecture and test choices are recommendations, not Apple mandates.


## Human Interface Guidelines

### [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)

Use: Current platform design context.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/designing-for-iphone-duo.json)

### [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

Use: Available-window layout, safe areas, reflow.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/layout.json)

### [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)

Use: Text hierarchy and Dynamic Type.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/typography.json)

### [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

Use: Contrast, settings, inclusive interaction.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/accessibility.json)

### [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)

Use: Stable top-level navigation.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/tab-bars.json)

### [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)

Use: Presentation, detents, dismissal.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/sheets.json)

### [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

Use: Readable native navigation and content layers.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/materials.json)

### [Motion](https://developer.apple.com/design/human-interface-guidelines/motion)

Use: Purposeful motion and accessibility.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/motion.json)

### [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)

Use: Control semantics and presentation.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/buttons.json)

### [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)

Use: Station, result, and journey rows.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/lists-and-tables.json)

### [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)

Use: Interruptive feedback and decisions.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/alerts.json)

### [Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators)

Use: Truthful task status and cancellation.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/progress-indicators.json)

### [UI Design Dos and Don’ts](https://developer.apple.com/design/tips/)

Use: 44 × 44 point touch controls.

Review status: Relevant official content reviewed.


## Current iPhone Duo Tech Talks

### [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)

Use: SDK, scene sizing, orientation caveats, asymmetric safe areas.

Review status: Relevant official transcript reviewed.

### [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/)

Use: Adaptive system bars and semantic toolbar items.

Review status: Relevant official transcript reviewed.

### [Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/)

Use: ReservedRegion and ArrangementView; layout rather than navigation.

Review status: Relevant official transcript reviewed.

### [Leverage multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/)

Use: Hinge interactions versus layout; scene capabilities.

Review status: Relevant official transcript reviewed.


## WWDC implementation guidance

### [Meet MapKit for SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10043/)

Use: Camera, selection, safe-area overlays, map updates.

Review status: Relevant official transcript reviewed.

### [Demystify SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10022/)

Use: Identity, lifetime, dependencies.

Review status: Relevant official transcript reviewed.

### [Discover Observation in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10149/)

Use: Observable ownership and update dependencies.

Review status: Relevant official transcript reviewed.

### [Discover concurrency in SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10019/)

Use: Main actor, asynchronous work, view-associated tasks.

Review status: Relevant official transcript reviewed.

### [Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/)

Use: Measuring updates and identity costs.

Review status: Relevant official transcript reviewed.

### [Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/)

Use: Long updates, invalidation causes, profiling.

Review status: Relevant official transcript reviewed.

### [SwiftUI Accessibility: Beyond the basics](https://developer.apple.com/videos/play/wwdc2021/10119/)

Use: Custom controls, grouping, rotors, accessibility focus.

Review status: Relevant official transcript reviewed.

### [Perform accessibility audits for your app](https://developer.apple.com/videos/play/wwdc2023/10035/)

Use: Automated audits and manual-testing limits.

Review status: Relevant official transcript reviewed.


## API references for local SDK lookup

### [ArrangementView](https://developer.apple.com/documentation/swiftui/arrangementview)

Use: Verify exact declaration, style options, and availability.

Review status: Official reference page located; complete declaration not independently verified.

### [ReservedRegion](https://developer.apple.com/documentation/swiftui/reservedregion)

Use: Verify division and occlusion handling.

Review status: Official reference page located; complete declaration not independently verified.

### [GeometryProxy](https://developer.apple.com/documentation/swiftui/geometryproxy)

Use: Local geometry, safe areas, and reserved regions.

Review status: Official reference page located; complete declaration not independently verified.

### [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)

Use: Adaptive navigation implementation lookup.

Review status: Official reference page located; complete declaration not independently verified.

### [NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack)

Use: Navigation path implementation lookup.

Review status: Official reference page located; complete declaration not independently verified.

### [AnyLayout](https://developer.apple.com/documentation/swiftui/anylayout)

Use: Alternative layouts with stable subview structure.

Review status: Official reference page located; complete declaration not independently verified.

### [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits)

Use: Content-fitting alternatives.

Review status: Official reference page located; complete declaration not independently verified.

### [ScaledMetric](https://developer.apple.com/documentation/swiftui/scaledmetric)

Use: Scaling custom metrics within product constraints.

Review status: Official reference page located; complete declaration not independently verified.

### [FocusState](https://developer.apple.com/documentation/swiftui/focusstate)

Use: Text-input focus implementation lookup.

Review status: Official reference page located; complete declaration not independently verified.

### [AccessibilityFocusState](https://developer.apple.com/documentation/swiftui/accessibilityfocusstate)

Use: Assistive-technology focus implementation lookup.

Review status: Official reference page located; complete declaration not independently verified.

### [ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase)

Use: Scene activation and lifecycle lookup.

Review status: Official reference page located; complete declaration not independently verified.

### [SceneStorage](https://developer.apple.com/documentation/swiftui/scenestorage)

Use: Scene restoration lookup; verify persistence guarantees.

Review status: Official reference page located; complete declaration not independently verified.

### [ContentUnavailableView](https://developer.apple.com/documentation/swiftui/contentunavailableview)

Use: Empty and unavailable-state composition lookup.

Review status: Official reference page located; complete declaration not independently verified.

### [scrollDismissesKeyboard(_:)](https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:))

Use: Keyboard dismissal policy lookup.

Review status: Official reference page located; complete declaration not independently verified.


## Accessibility environment

### [accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)

Use: Read the current Reduce Motion preference.

Review status: Official reference and indexed description reviewed.

### [accessibilityReduceTransparency](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency)

Use: Read the current Reduce Transparency preference.

Review status: Official reference and indexed description reviewed.


## MapKit reference

### [MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)

Use: Map, camera, controls, annotations, overlays.

Review status: Official API index reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/documentation/mapkit/mapkit-for-swiftui.json)


## State and feedback reference

### [ProgressView](https://developer.apple.com/documentation/swiftui/progressview)

Use: Determinate and indeterminate progress.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/documentation/swiftui/progressview.json)


## Performance reference

### [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)

Use: Expensive and excessively frequent view updates.

Review status: Relevant official content reviewed.

[Official readable JSON representation](https://developer.apple.com/tutorials/data/documentation/xcode/understanding-and-improving-swiftui-performance.json)


## Toolchain reference

### [Xcode 27.1 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes)

Use: Compare installed Xcode build and SDK; do not infer local toolchain version.

Review status: Official indexed result located; complete release notes not reviewed.


## Accessibility testing reference

### [Accessibility Inspector](https://developer.apple.com/documentation/accessibility/accessibility-inspector)

Use: Inspect labels, traits, target bounds, and audit findings.

Review status: Supplemental official link referenced by HIG; full page not reviewed.

### [Performing accessibility testing for your app](https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app)

Use: Testing workflow and coverage.

Review status: Supplemental official link referenced by HIG; full page not reviewed.
