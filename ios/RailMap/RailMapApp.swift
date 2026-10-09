import Observation
import SwiftUI
import UIKit

/// The user-selected text-size bounds apply to every app and test surface.
enum AppTypographyPolicy {
    static let supportedSizes: ClosedRange<DynamicTypeSize> = .xSmall ... .xLarge

    static func preferredFont(forTextStyle style: UIFont.TextStyle) -> UIFont {
        let requested = UIFont.preferredFont(forTextStyle: style)
        let minimum = UIFont.preferredFont(forTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraSmall))
        let maximum = UIFont.preferredFont(forTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraLarge))
        return requested.withSize(min(maximum.pointSize, max(minimum.pointSize, requested.pointSize)))
    }
}

/// Japan Train Map, native.
///
/// The app shell owns exactly the three things the pure tier is forbidden to
/// touch: the window, Apple Maps, and the file system. Everything it draws it
/// gets from `RailCore`, which is verified line by line against the JavaScript
/// implementation by `port-fixtures/` — so a disagreement between this app and
/// the web app is a test failure before it is a bug report.
@main
struct RailMapApp: App {
    @AppStorage("appearance") private var appearance = "system"
    @State private var localization = AppLocalization()

    var body: some Scene {
        WindowGroup {
            testableContent
                .overlay(alignment: .topLeading) {
#if DEBUG
                    if ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_TYPOGRAPHY"] == "1" {
                        AppTypographyUITestProbe()
                    }
#endif
                }
                .dynamicTypeSize(AppTypographyPolicy.supportedSizes)
                .preferredColorScheme(preferredColorScheme)
        }
        .commands { RailMapCommands() }
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
        if let mode = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_LONG_DETAIL"] {
            LongJourneyDetailTestView(mode: mode)
                .environment(localization)
        } else {
            ContentView(localization: localization)
        }
#else
        ContentView(localization: localization)
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
    var canPerform = false
    /// New Journey and Search. False while a sheet with its own editor or
    /// search is up, so ⌘N and ⌘F do not run on the workspace underneath.
    var canCreateOrSearch = false

    @ObservationIgnored var performNewJourney: (@MainActor () -> Void)?
    @ObservationIgnored var performSearch: (@MainActor () -> Void)?
    @ObservationIgnored var performZoomIn: (@MainActor () -> Void)?
    @ObservationIgnored var performZoomOut: (@MainActor () -> Void)?
    @ObservationIgnored var performTogglePanel: (@MainActor () -> Void)?

    func newJourney() { performNewJourney?() }
    func search() { performSearch?() }
    func zoomIn() { performZoomIn?() }
    func zoomOut() { performZoomOut?() }
    func togglePanel() { performTogglePanel?() }
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
        }
    }
}

#if DEBUG
private struct AppTypographyUITestProbe: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(" ")
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityIdentifier("appTypographySize")
            .accessibilityLabel("App text size")
            .accessibilityValue(Text(verbatim: "size:\(dynamicTypeSize);subtitleRow:\(BottomChromeMetrics.subtitleRow)"))
    }
}
#endif
