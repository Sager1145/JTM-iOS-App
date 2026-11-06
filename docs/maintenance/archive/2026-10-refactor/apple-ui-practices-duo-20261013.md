# Apple UI guidance for adaptive map and docked-card layouts

Research date: 2026-10-13. This is a focused primary-source note, not a complete HIG inventory or a runtime audit. **Documented** means Apple states the behavior; **application** means a recommendation inferred for JTM. No builds, device tests, performance measurements, or code changes were performed for this note.

## Container layout and safe areas

**Documented:** Layout must adapt to available window space, including when orientation support is restricted. Respect safe areas and layout guides; preserve recognizable relationships between controls and content as space changes. [Apple HIG: Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

**Documented:** Prefer the surrounding view's available size over screen bounds. Size classes describe coarse layout constraints; local view geometry supplies finer control. Device idiom and interface orientation are unreliable layout proxies in resizable iPhone environments. [Modernize your UIKit app, 2:51–7:55](https://developer.apple.com/videos/play/wwdc2026/278/)

**Documented:** Building with the iOS 27.1 SDK enables Duo's full-screen experience and vertically arranged standard bars. Place foreground controls in safe areas; backgrounds can extend beyond them. Insets and margins can be asymmetric, so handle each edge separately. Duo's inner display does not honor supported interface orientations in the usual way. [Prepare your app for iPhone Duo, 0:30, 2:46, 6:06](https://developer.apple.com/videos/play/tech-talks/111461/)

**Application:** A narrow docked card needs its own content-width decisions even inside a regular-size-class scene. Use its usable width after insets to stack crowded summary content. Preserve the repository's portrait-only iPhone declaration and iPad orientation support; do not change those product settings to obtain a layout result. Resizing still needs support within that policy.

## Tabs, toolbars, and the narrow card

**Documented:** Tabs represent top-level destinations; toolbars perform actions. Keep destination labels understandable and empty destinations available with explanatory content. [Apple HIG: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)

**Documented:** Duo navigation, toolbar, and tab controls can share a vertical region. Use standard navigation containers for adaptation. Vertical toolbar participation depends on a container meeting the display edge; split views use the detail column. Centered inner-display sheets retain horizontal items. Apple describes `toolbarVerticalBehavior` as the SwiftUI opt-out for layouts where a vertical bar reduces useful space. [Raise the bar with iPhone Duo, 2:00–4:29, 14:21](https://developer.apple.com/videos/play/tech-talks/111462/)

**API boundary:** [`defaultTabBarPlacement(_:)`](https://developer.apple.com/documentation/swiftui/view/defaulttabbarplacement(_:)) chooses sidebar versus tab-bar representation in the `sidebarAdaptable` style. Its documentation does not promise a horizontal axis. [`toolbarVerticalBehavior(_:)`](https://developer.apple.com/documentation/swiftui/view/toolbarverticalbehavior(_:)) has an official page, but this research tool could not retrieve its full declaration/discussion. The integrating chat independently confirmed `.toolbarVerticalBehavior(.disabled)` and `@available(anyAppleOS 27.1, *)` in the installed RC SDK. Applicability and resulting layout in the embedded `TabView` still need a focused runtime check.

**Application:** The observed vertical strip and truncated summaries in JTM's narrow card justify a local horizontal-layout investigation. The cited public material does not specify an exact narrow-card width threshold or guarantee where tabs in this custom embedding appear. Avoid extrapolating full-window Duo placement into that card; validate the resulting layout directly.

## Maps and foreground readability

**Documented:** Maps should support familiar interaction. Noninteractive overlays can obstruct expected map gestures. Keep Apple's logo and legal link visible, and ensure custom controls remain distinct from map content. [Apple HIG: Maps](https://developer.apple.com/design/human-interface-guidelines/maps)

**Application:** Keep the map expansive while giving route and station information a clear foreground surface. Preserve JTM's full-viewport basemap dimming above the basemap and below railway drawing, and its physical-topology routing policy. A docked card must not cover attribution or make controls unreachable.

## Typography and accessibility

**Documented:** System text styles provide hierarchy and Dynamic Type behavior. Constrained horizontal layouts may need stacking as text grows; meaningful symbols should scale with text. [Apple HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)

**Project constraint:** Every JTM surface, including debug UI and UIKit measurements, keeps `AppTypographyPolicy.supportedSizes` at `.xSmall ... .xLarge`. Apply wrapping and reflow within that range. This is a project restriction, not Apple's general recommendation for larger accessibility text sizes. See `ios/AGENTS.md`.

**Documented:** Current Accessibility HIG lists **44 × 44 pt as the default iOS/iPadOS control size**, and 28 × 28 pt as its minimum. The [Buttons HIG](https://developer.apple.com/design/human-interface-guidelines/buttons) separately gives a general rule of at least 44 × 44 pt for button hit regions. These are distinct recommendations. Controls also need separation, readable contrast, non-color status cues, and meaningful accessibility descriptions. [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

**Application:** Use 44 × 44 pt touch areas as JTM's practical target for card controls. Allow the visual glyph to be smaller. Expose destination selection, station names, route state, and button purpose to VoiceOver; don't make railway color the sole identifier.

## Reduced effects, states, and performance

**Documented:** Use Liquid Glass sparingly and preserve legibility over changing backgrounds. System material appearance responds to settings including reduced transparency and increased contrast. [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

**Documented:** Motion should communicate purpose, remain optional, and avoid unnecessary delay during frequent interactions. Reduce Motion should reduce automatic/repetitive movement. [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

**Documented:** Display useful content promptly, let people continue other work during loading, and communicate ongoing progress. Use determinate progress when completion can be measured, indeterminate otherwise. [Apple HIG: Loading](https://developer.apple.com/design/human-interface-guidelines/loading)

**Application:** Distinguish loading, empty results, missing permission, and failure. Give each an explanation and relevant next action; do not present a blank destination or an endless spinner as a complete state.

**Documented:** SwiftUI responsiveness depends on both body-computation cost and update frequency. Instruments identifies long updates and their causes; expensive body calculations and unnecessary dependencies can cause hitches. [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)

**Application:** Review card-local geometry and state ownership before adding optimization. Avoid letting unrelated frequent map updates recompute static card summaries. Code review alone establishes neither smoothness nor a performance improvement. Follow `ios/VERIFICATION.md`: resolve concrete questions with focused existing evidence, then stop; don't recreate retired verification matrices.

## Official source index for this scope

This set covers the topics in this note; it is not an inventory of every Apple UI document.

| Topic | Official source |
| --- | --- |
| Adaptive layouts and safe areas | [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) |
| Duo-specific patterns | [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) and [Duo developer hub](https://developer.apple.com/iphone-duo/) |
| Navigation destinations | [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) |
| Navigation hierarchy | [Navigation and search](https://developer.apple.com/design/human-interface-guidelines/navigation-and-search), [NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack), [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) |
| Content actions | [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) |
| Buttons and secondary actions | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Menus](https://developer.apple.com/design/human-interface-guidelines/menus) |
| Search and text input | [Searching](https://developer.apple.com/design/human-interface-guidelines/searching), [Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields), [Virtual keyboards](https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards), [SwiftUI focus](https://developer.apple.com/documentation/swiftui/focus) |
| Symbols and appearance | [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols), [Color](https://developer.apple.com/design/human-interface-guidelines/color) |
| Maps | [Maps](https://developer.apple.com/design/human-interface-guidelines/maps) |
| Text | [Typography](https://developer.apple.com/design/human-interface-guidelines/typography) |
| Accessibility and targets | [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) |
| Surface effects | [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) |
| Animation | [Motion](https://developer.apple.com/design/human-interface-guidelines/motion) |
| Pending content | [Loading](https://developer.apple.com/design/human-interface-guidelines/loading) |
| Error and confirmation presentation | [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) |
| Contextual presentation | [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets) |
| Runtime efficiency | [SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) |
| Empty-state presentation | [ContentUnavailableView](https://developer.apple.com/documentation/swiftui/contentunavailableview) |
| State and lifecycle | [Model data](https://developer.apple.com/documentation/swiftui/model-data), [Managing model data](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app), [ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase) |

The Duo Tech Talk transcripts linked above supplied directly readable, current guidance. Several HIG/API pages return a JavaScript shell to this research tool; source existence alone is not a claim that their full current text was downloaded. General HIG facts were cross-checked with the installed Apple HIG reference and official search extracts where readable.

## Additional task-relevant review checklist

These are applications of the indexed guidance, not claims that JTM currently passes them.

- Navigation: preserve selected destinations and back context across resizing; use a stack for hierarchy and multiple columns only when useful space exists. Keep map actions distinct from destinations.
- Sheets: use a focused task with predictable dismissal. Distinguish Cancel/Close, Done, and Back; avoid making a Back button dismiss a sheet. Keep edits and unsaved changes consistent.
- Buttons and menus: make actions recognizable, provide pressed/disabled states, and prefer semantic roles. Group related secondary actions; keep common actions easy to reach and menu labels clear about actions versus current state.
- Search and keyboard: expose search prominently with an explicit scope. Label fields beyond disappearing placeholders, use appropriate keyboards, preserve logical focus order, and keep the active field and results reachable when the keyboard appears. Explain no-result states and retain the entered query.
- Symbols and colors: use familiar SF Symbols with suitable weight and scale. Prefer semantic UI colors while retaining reviewed railway brand identities; check contrast over actual map/material backgrounds in both appearances. Add text or shape cues to color-coded selection/status.
- Errors and empty states: reserve interrupting alerts for essential, actionable information. Explain absent content in context and provide a relevant recovery action. Separate empty data from failure, loading, and missing permissions.
- State: keep one source of truth; own transient local UI state with private `@State`, share mutation with bindings, and observe model properties actually needed by each view. Preserve selection and presentation meaning across view reconstruction.
- Lifecycle: distinguish active, inactive, and background scene phases. Tie visible work and persistence to their appropriate lifecycle without treating every body recomputation as a new launch. Avoid restarting route/search work merely because layout changes.

## Downloaded source set and API boundary confirmation

The source set was downloaded from Apple's published HIG navigator index to `/private/tmp/jtm-apple-ui-guidance-20261013`: all 40 selected documents returned valid JSON. The accompanying ZIP includes original documents, their official URLs/status manifest, and this guide. This covers the selected iOS/UI topics; it does not claim to contain every Apple document.

The rendered [toolbarVerticalBehavior API documentation](https://developer.apple.com/documentation/swiftui/view/toolbarverticalbehavior(_:)) confirms `.disabled` returns bars to horizontal top/bottom positions, with `TabView` as an explicit example. The preference resolves at the window or presented sheet/form boundary; it is not a purely local geometric switch. The initial horizontal-card trial was superseded by the user's requested unified right sidebar. The workspace uses one root native TabView, with each destination owning its NavigationStack and card content. The map and presentation boundary remain shared. A single ToolbarItemGroup with vertical-preferred axis and visible shared background groups network, route, and layer actions above the native navigation sidebar. Current location remains a separate native circular control. The adjacent menu card retains visited content pages without adding a second tab bar. The API is marked beta and requires the iOS 27.1 SDK; the build uses `/Applications/Xcode-27.1-RC.app` without changing the machine-wide Xcode selection.

## Requested Duo arrangement

The user selected a right sidebar with the menu card beside it. Expanded mode has a hide/show option; folded mode can collapse the card to its header. Network, route, and layer controls form one continuous native toolbar group above the navigation group, with a separate circular current-location control in the native bar. Settings stays in the menu card header. On the expanded display the native sidebar contains the hide/show command; the card offers half and full heights. On the folded display no hide command is shown, and dragging the header can collapse the card to its header alone. Shared header metrics use a 20-point base title, 32-point control visuals, and 44-point touch targets. The information/legend entry lives in the Settings menu; current location, network, routes, and layers remain in the sidebar. Hinge availability selects this device-capability-specific workspace once, while actual container width, height, and safe areas determine dimensions. No hinge-angle thresholds or hardware dimensions are assumed. The hidden card remains mounted; hiding clears search focus, and selecting a sidebar destination restores the card. Native observations and the build result are recorded in the existing UI scope ledger, not inferred from this research.

Final native rendering note: Duo toolbar controls use native SF Symbols, including the route control. The menu keeps a 12-point bottom gutter beside vertical bars; when the system uses horizontal bottom navigation, the existing tab-bar band remains reserved. These placements were observed on the Duo simulator; broader performance and accessibility conformance were not measured.

Keyboard space: Apple's [Duo bars talk](https://developer.apple.com/videos/play/tech-talks/111462/) describes the competition between toolbars, tabs, and keyboards. [toolbarVerticalCompressionBehavior(_:)](https://developer.apple.com/documentation/swiftui/view/toolbarverticalcompressionbehavior(_:)) with [.prefersTabBar](https://developer.apple.com/documentation/swiftui/toolbarverticalcompressionbehavior/preferstabbar) expresses the navigation priority, but native RC testing showed that the full destination bar could still remain behind the software keyboard. Priority, container rearrangement and an explicit SwiftUI height alone did not resolve that observation.

While folded Search owns input focus, RailMap keeps the native TabView mounted and hides its full tab bar. Its existing native toolbar instead shows a compact More menu and the separate current-location control. More presents the other three destinations directly and a Map submenu containing the same network, route and layer actions used by the normal toolbar. Search is already the active page, so it does not consume a redundant menu row. This bounds the competing sidebar chrome without introducing a custom navigation bar. Choosing a page updates the shared selection, clears focus, retains the query and restores the full native sidebar; submission also restores it. Expanded Search retains the full sidebar. Menu opening and page-switch evidence belongs to the UI scope ledger; this change makes no general simulator or physical-device performance claim.
