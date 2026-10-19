import SwiftUI

/// System tab hosting only. Page state and content belong to the workspace.
struct WorkspaceTabs: View {
    @Binding var selection: PrimaryTab
    let page: (PrimaryTab) -> WorkspacePage
    @Environment(AppLocalization.self) private var localization

    var body: some View {
        if #available(iOS 18.0, *) {
            modernTabs
        } else {
            legacyTabs
        }
    }

    @available(iOS 18.0, *)
    private var modernTabs: some View {
        TabView(selection: $selection) {
            Tab(title(.upcoming), systemImage: PrimaryTab.upcoming.systemImage,
                value: PrimaryTab.upcoming) { page(.upcoming) }
            Tab(title(.stats), systemImage: PrimaryTab.stats.systemImage,
                value: PrimaryTab.stats) { page(.stats) }
            Tab(title(.all), systemImage: PrimaryTab.all.systemImage,
                value: PrimaryTab.all) { page(.all) }
            Tab(title(.search), systemImage: PrimaryTab.search.systemImage,
                value: PrimaryTab.search, role: .search) { page(.search) }
        }
        // The system search role reproduces the reference's trailing circle.
        // Its exact bar height and margins belong to the running iOS version.
        .tabViewStyle(.tabBarOnly)
        .railPersistentTabBar()
        .modifier(SystemSheetTabSurface())
        .environment(\.locale, localization.locale)
    }

    private var legacyTabs: some View {
        TabView(selection: $selection) {
            page(.upcoming)
                .tabItem { Label(title(.upcoming), systemImage: PrimaryTab.upcoming.systemImage) }
                .tag(PrimaryTab.upcoming)
            page(.stats)
                .tabItem { Label(title(.stats), systemImage: PrimaryTab.stats.systemImage) }
                .tag(PrimaryTab.stats)
            page(.all)
                .tabItem { Label(title(.all), systemImage: PrimaryTab.all.systemImage) }
                .tag(PrimaryTab.all)
            page(.search)
                .tabItem { Label(title(.search), systemImage: PrimaryTab.search.systemImage) }
                .tag(PrimaryTab.search)
        }
        .modifier(SystemSheetTabSurface())
        .environment(\.locale, localization.locale)
    }

    private func title(_ tab: PrimaryTab) -> String {
        localization.text(tab.tabLocalizationKey, fallback: tab.tabFallbackName)
    }
}

/// One native TabView owns Duo's bar region; each page owns its navigation stack.
/// The map is a stable background; changing tabs only selects card content.
@available(iOS 27.1, *)
struct DuoWorkspaceShell<MapContent: View, Panel: View, Controls: ToolbarContent>: View {
    @Binding var selection: PrimaryTab
    @ViewBuilder var map: () -> MapContent
    var usesKeyboardMenu: Bool
    var preservesMenuBounds: Bool
    var containerWidth: CGFloat
    @ViewBuilder var panel: (PrimaryTab, CGSize, EdgeInsets) -> Panel
    @ToolbarContentBuilder var controls: () -> Controls
    @Environment(AppLocalization.self) private var localization
    @State private var menuBounds: CGRect?
    @State private var measuredContainerWidth: CGFloat?
    @State private var menuSafeInsets = EdgeInsets()

    var body: some View {
        TabView(selection: $selection) {
            Tab(title(.upcoming), systemImage: PrimaryTab.upcoming.systemImage,
                value: PrimaryTab.upcoming) { contentPage(.upcoming) }
            Tab(title(.stats), systemImage: PrimaryTab.stats.systemImage,
                value: PrimaryTab.stats) { contentPage(.stats) }
            Tab(title(.all), systemImage: PrimaryTab.all.systemImage,
                value: PrimaryTab.all) { contentPage(.all) }
            Tab(title(.search), systemImage: PrimaryTab.search.systemImage,
                value: PrimaryTab.search, role: .search) { contentPage(.search) }
        }
        .tabViewStyle(.tabBarOnly)
        .railPersistentTabBar()
        .railDuoTabPriority()
        .toolbar(usesKeyboardMenu ? .hidden : .visible, for: .tabBar)
        .background { map() }
        .environment(\.locale, localization.locale)
    }

    private func contentPage(_ tab: PrimaryTab) -> some View {
        NavigationStack {
            ZStack {
                Color.clear
                    .background(TabHostTransparency())
                    .allowsHitTesting(false)
                // The field and toolbar belong to the selected tab's native
                // navigation controller, which owns keyboard compression.
                GeometryReader { safeGeometry in
                    let vertical = safeGeometry.safeAreaInsets.trailing > WorkspaceMenuMetrics.touchSide
                    GeometryReader { geometry in
                        let current = geometry.frame(in: .global)
                        let preserves = preservesMenuBounds && measuredContainerWidth == containerWidth
                        let bounds = preserves ? menuBounds ?? current : current
                        panel(tab, bounds.size, preserves
                              ? menuSafeInsets : geometry.safeAreaInsets)
                            .frame(width: bounds.width, height: bounds.height)
                            .offset(x: bounds.minX - current.minX,
                                    y: bounds.minY - current.minY)
                            .onChange(of: current, initial: true) { _, frame in
                                guard tab == selection, !preserves else { return }
                                menuBounds = frame
                                menuSafeInsets = geometry.safeAreaInsets
                                measuredContainerWidth = containerWidth
                            }
                            .onChange(of: containerWidth) { _, width in
                                guard tab == selection else { return }
                                menuBounds = current
                                menuSafeInsets = geometry.safeAreaInsets
                                measuredContainerWidth = width
                            }
                    }
                        .ignoresSafeArea(.container, edges: vertical ? .bottom : [])
                        .padding(.bottom, vertical ? 0 : max(0, BottomChromeMetrics.compactTabBand
                            - safeGeometry.safeAreaInsets.bottom))
                }
                // Keep the docked menu's geometry independent of keyboard
                // avoidance; the native navigation toolbar still compresses.
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .toolbar { controls() }
            .navigationBarTitleDisplayMode(.inline)
            .railDuoTabPriority()
        }
    }

    private func title(_ tab: PrimaryTab) -> String {
        localization.text(tab.tabLocalizationKey, fallback: tab.tabFallbackName)
    }
}

private struct PanelHeaderStacksActionsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var railPanelHeaderStacksActions: Bool {
        get { self[PanelHeaderStacksActionsKey.self] }
        set { self[PanelHeaderStacksActionsKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func railDuoTabPriority() -> some View {
#if targetEnvironment(macCatalyst)
        self
#else
        if #available(iOS 27.1, *) {
            toolbarVerticalCompressionBehavior(.prefersTabBar)
        } else {
            self
        }
#endif
    }

    /// Detect the display capability once. Container geometry, rather than
    /// hinge angle or pose, continues to determine all layout dimensions.
    @ViewBuilder
    func railObserveHingedDisplay(_ available: @escaping () -> Void) -> some View {
#if targetEnvironment(macCatalyst)
        self
#else
        if #available(iOS 27.1, *) {
            onHingeChange { _, context in
                if context.hinge != nil { available() }
            }
        } else {
            self
        }
#endif
    }
}

/// A workspace destination's page, mounted rather than composed.
///
/// Deliberately NOT generic, and that is the whole of it: a generic wrapper
/// would still name the page in its own type, and it is the type that costs.
/// The closure is what defers the page, and `AnyView` is what stops the tab
/// bar's type from naming it. See `RailWorkspaceView.page(_:stage:headerExpansion:content:)`
/// for the crash both halves answer.
struct WorkspacePage: View {
    let build: () -> AnyView

    var body: some View { build() }
}
