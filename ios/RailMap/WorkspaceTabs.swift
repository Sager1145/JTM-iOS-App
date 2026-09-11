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
                value: PrimaryTab.search) { page(.search) }
        }
        // Search stays a named destination with its own field. A search-role
        // tab changes shape across OS versions and conflicts with the fixed bar.
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
