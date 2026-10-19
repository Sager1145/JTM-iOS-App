import RailPresentation
import MapKit
import Observation
import SwiftUI
import UIKit

/// Native app entry point. AppShell owns platform stores and the shared map workspace.
/// RailKit supplies portable domain, presentation and application rules.
#if !RAIL_DIAGNOSTICS
@main
struct RailMapApp: App {
    @AppStorage("appearance") private var appearance = "system"
    @State private var localization = AppLocalization()

    init() {
        BundledRegistry.install()
    }

    var body: some Scene {
        WindowGroup {
#if ROUTE_WORKBENCH
            RouteWorkbenchView()
                .dynamicTypeSize(AppTypographyPolicy.supportedSizes)
#else
            testableContent
                .overlay(alignment: .topLeading) {
#if DEBUG
                    if UITestLaunchConfiguration.current[.typography] == "1" {
                        AppTypographyUITestProbe()
                    }
#endif
                }
                .dynamicTypeSize(AppTypographyPolicy.supportedSizes)
                .preferredColorScheme(preferredColorScheme)
#endif
        }
#if ROUTE_WORKBENCH
        .commands { RouteWorkbenchCommands() }
#else
        .commands { RailMapCommands() }
#endif
    }

    // There is no `RAILMAP_UI_TEST_REDUCE_MOTION` hook, and there cannot be
    // one shaped like the others.
    //
    // `EnvironmentValues.accessibilityReduceMotion` is declared `{ get }`, so
    // its key path is a `KeyPath` and not a `WritableKeyPath` — the same
    // `.environment(_:_:)` call that installs `AppLocalization` simply does not
    // typecheck against it. It is the SYSTEM's answer about the reader, not a
    // value the app is allowed to assert.
    //
    // A screenshot harness sets it where it actually lives, before launching:
    //
    //     xcrun simctl spawn <udid> defaults write com.apple.Accessibility \
    //         ReduceMotionEnabled -bool true
    //     xcrun simctl spawn <udid> notifyutil -p com.apple.accessibility.cache.app.ax
    //
    // That drives every `@Environment(\.accessibilityReduceMotion)` in the app
    // at once, which a shadowed app-level flag would not: the tokens in
    // `RailMotion` are read by views that would still be looking at the real
    // setting, so half the interface would degrade and half would not — and a
    // review run on that is worse than no review run at all.
    @ViewBuilder private var testableContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
           NSClassFromString("XCTestCase") != nil {
            // Hosted unit tests construct their own isolated owners. Avoid
            // starting the map or reading the reader's saved working set.
            Color.clear
        } else if let mode = UITestLaunchConfiguration.current[.longDetail] {
            LongJourneyDetailTestView(mode: mode)
                .environment(localization)
        } else {
            AppShell(localization: localization, appearance: $appearance)
        }
#else
        AppShell(localization: localization, appearance: $appearance)
#endif
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

#endif

/// Actions the workspace publishes for the menu bar and the hardware keyboard.
///
/// A class, held once by the workspace and handed up with `focusedSceneValue`,
/// so a scene command can call the live handler without a new value on every
/// frame of a sheet drag. Titles are copied when the stage or language changes.
///
/// `@Observable` because `Commands` keeps this same instance for the life of
/// the scene. A plain class mutated in place never re-evaluates that body, so
/// the items stayed disabled at their launch values and the panel title stayed
/// on whatever was copied first. The closures are not menu state.
@MainActor
@Observable
final class RailCommandBridge {
    var newJourneyTitle = "New journey"
    var searchTitle = "Search"
    var zoomInTitle = "Zoom in"
    var zoomOutTitle = "Zoom out"
    var togglePanelTitle = "Expand panel"
    var toggleNetworkTitle = "Toggle railway network"
    var previousDateTitle = "Previous date"
    var nextDateTitle = "Next date"
    var routesTitle = "Train routes"
    var stationsTitle = "Stations"
    var stationNamesTitle = "Station names"
    var layersTitle = "Map layers"
    var addDateTitle = "Add date"
    var allDatesTitle = "All dates"
    var followDateTitle = "Map shows the selected date only"
    var mapMenuTitle = "Map"
    var dateMenuTitle = "Date"
    var northUpTitle = "North up"
    var fitSelectionTitle = "Fit selected route"
    var fitNetworkTitle = "Fit railway network"
    var panLeftTitle = "Pan left"
    var panRightTitle = "Pan right"
    var panUpTitle = "Pan up"
    var panDownTitle = "Pan down"
    var canPerform = false
    /// New Journey and Search. False while a sheet with its own editor or
    /// search is up, so ⌘N and ⌘F do not run on the workspace underneath.
    var canCreateOrSearch = false
    var canStepDate = false
    var canPresentPanels = false

    @ObservationIgnored var performNewJourney: (@MainActor () -> Void)?
    @ObservationIgnored var performSearch: (@MainActor () -> Void)?
    @ObservationIgnored var performZoomIn: (@MainActor () -> Void)?
    @ObservationIgnored var performZoomOut: (@MainActor () -> Void)?
    @ObservationIgnored var performTogglePanel: (@MainActor () -> Void)?
    @ObservationIgnored var performToggleNetwork: (@MainActor () -> Void)?
    @ObservationIgnored var performPreviousDate: (@MainActor () -> Void)?
    @ObservationIgnored var performNextDate: (@MainActor () -> Void)?
    @ObservationIgnored var performToggleRoutes: (@MainActor () -> Void)?
    @ObservationIgnored var performToggleStations: (@MainActor () -> Void)?
    @ObservationIgnored var performToggleStationNames: (@MainActor () -> Void)?
    @ObservationIgnored var performShowLayers: (@MainActor () -> Void)?
    @ObservationIgnored var performResetNorth: (@MainActor () -> Void)?
    @ObservationIgnored var performFitSelection: (@MainActor () -> Void)?
    @ObservationIgnored var performFitNetwork: (@MainActor () -> Void)?
    @ObservationIgnored var performPan: (@MainActor (CGFloat, CGFloat) -> Void)?
    @ObservationIgnored var performAddDate: (@MainActor () -> Void)?
    @ObservationIgnored var performAllDates: (@MainActor () -> Void)?
    @ObservationIgnored var performToggleDateFollow: (@MainActor () -> Void)?

    func newJourney() { performNewJourney?() }
    func search() { performSearch?() }
    func zoomIn() { performZoomIn?() }
    func zoomOut() { performZoomOut?() }
    func togglePanel() { performTogglePanel?() }
    func toggleNetwork() { performToggleNetwork?() }
    func previousDate() { performPreviousDate?() }
    func nextDate() { performNextDate?() }
}

private struct RailCommandBridgeKey: FocusedValueKey {
    typealias Value = RailCommandBridge
}

extension FocusedValues {
    var railCommandBridge: RailCommandBridge? {
        get { self[RailCommandBridgeKey.self] }
        set { self[RailCommandBridgeKey.self] = newValue }
    }
}

/// App-level shortcuts. They have to live on the scene: a hidden button inside
/// the journey list never runs from Passport, and it never appears in the Mac
/// menu bar or the iPad ⌘ overlay.
private struct RailMapCommands: Commands {
    @FocusedValue(\.railCommandBridge) private var bridge

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(bridge?.newJourneyTitle ?? "New journey") {
                bridge?.newJourney()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(bridge?.canPerform != true || bridge?.canCreateOrSearch != true)
        }
        CommandGroup(after: .toolbar) {
            Button(bridge?.searchTitle ?? "Search") {
                bridge?.search()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(bridge?.canPerform != true || bridge?.canCreateOrSearch != true)

            // "+" is Shift-"=" on most layouts, so both are bound. One menu
            // title, two key equivalents — the same pair the hidden buttons used.
            Button(bridge?.zoomInTitle ?? "Zoom in") {
                bridge?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(bridge?.canPerform != true)
            Button(bridge?.zoomInTitle ?? "Zoom in") {
                bridge?.zoomIn()
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(bridge?.canPerform != true)

            Button(bridge?.zoomOutTitle ?? "Zoom out") {
                bridge?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(bridge?.canPerform != true)

            Divider()

            Button(bridge?.togglePanelTitle ?? "Expand panel") {
                bridge?.togglePanel()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(bridge?.canPerform != true)

            Button(bridge?.toggleNetworkTitle ?? "Toggle railway network") {
                bridge?.toggleNetwork()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(bridge?.canPerform != true)

            Divider()

            Button(bridge?.previousDateTitle ?? "Previous date") {
                bridge?.previousDate()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(bridge?.canPerform != true || bridge?.canStepDate != true)
            Button(bridge?.nextDateTitle ?? "Next date") {
                bridge?.nextDate()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(bridge?.canPerform != true || bridge?.canStepDate != true)
        }
        mapCommands
        dateCommands
    }

    private var canReviewMap: Bool {
        bridge?.canPerform == true && bridge?.canCreateOrSearch == true
    }

    private var mapCommands: some Commands {
        CommandMenu(bridge?.mapMenuTitle ?? "Map") {
            Button(bridge?.routesTitle ?? "Train routes") { bridge?.performToggleRoutes?() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!canReviewMap)
            Button(bridge?.stationsTitle ?? "Stations") { bridge?.performToggleStations?() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!canReviewMap)
            Button(bridge?.stationNamesTitle ?? "Station names") { bridge?.performToggleStationNames?() }
                .keyboardShortcut("p", modifiers: [.command, .option, .shift])
                .disabled(!canReviewMap)
            Button(bridge?.layersTitle ?? "Map layers") { bridge?.performShowLayers?() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(bridge?.canPresentPanels != true)
            Divider()
            Button(bridge?.northUpTitle ?? "North up") { bridge?.performResetNorth?() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!canReviewMap)
            Button(bridge?.fitSelectionTitle ?? "Fit selected route") { bridge?.performFitSelection?() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!canReviewMap)
            Button(bridge?.fitNetworkTitle ?? "Fit railway network") { bridge?.performFitNetwork?() }
                .keyboardShortcut("f", modifiers: [.command, .option, .shift])
                .disabled(!canReviewMap)
            Divider()
            Button(bridge?.panLeftTitle ?? "Pan left") { bridge?.performPan?(-0.25, 0) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
                .disabled(!canReviewMap)
            Button(bridge?.panRightTitle ?? "Pan right") { bridge?.performPan?(0.25, 0) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
                .disabled(!canReviewMap)
            Button(bridge?.panUpTitle ?? "Pan up") { bridge?.performPan?(0, -0.25) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .control])
                .disabled(!canReviewMap)
            Button(bridge?.panDownTitle ?? "Pan down") { bridge?.performPan?(0, 0.25) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .control])
                .disabled(!canReviewMap)
        }
    }

    private var dateCommands: some Commands {
        CommandMenu(bridge?.dateMenuTitle ?? "Date") {
            Button(bridge?.addDateTitle ?? "Add date") { bridge?.performAddDate?() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(bridge?.canPresentPanels != true)
            Button(bridge?.allDatesTitle ?? "All dates") { bridge?.performAllDates?() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(!canReviewMap)
            Button(bridge?.followDateTitle ?? "Map shows the selected date only") {
                bridge?.performToggleDateFollow?()
            }
            .keyboardShortcut("d", modifiers: [.command, .option, .shift])
            .disabled(!canReviewMap)
        }
    }
}

#if DEBUG
private struct AppTypographyUITestProbe: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let item = DraftStopAnnotation(
            occurrenceID: UUID(), coordinate: CLLocationCoordinate2D(latitude: 35, longitude: 135),
            index: 1, name: "Draft station", stopType: "origin", timeText: "08:00",
            stopTypeLabel: "Departure", timeLabel: "08:00")
        let pin = DraftStopAnnotationView(annotation: item, reuseIdentifier: nil)
        pin.configure(item)
        let draftFont = pin.subviews.compactMap { ($0 as? UILabel)?.font.pointSize }.first ?? 0
        return Text(" ")
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityIdentifier("appTypographySize")
            .accessibilityLabel("App text size")
            .accessibilityValue(Text(verbatim: "size:\(dynamicTypeSize);subtitleRow:\(BottomChromeMetrics.subtitleRow);draftFont:\(draftFont);draftHeight:\(pin.bounds.height)"))
    }
}
#endif
