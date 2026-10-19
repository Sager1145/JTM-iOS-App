import SwiftUI

/// §2.2's two Utility destinations, and the rules that keep them from becoming
/// tabs again.
///
/// > `Data Library` 是数据所有权与迁移任务，从 Journeys/Passport 顶部的数据库
/// > 按钮进入。`Settings` 是全局偏好，从顶部头像/齿轮入口进入。
/// > Tab Bar 不放 `Editor`、`Playback`、`Import` 等临时任务。
///
/// The distinction is not about frequency. Both of these are *tasks*: the
/// reader arrives with something to do, does it, and leaves. A tab is a place
/// they browse and come back to. Making a task a tab costs a browsing slot and
/// tells the reader the app has five subjects when it has three.
enum UtilityDestination: String, Identifiable, CaseIterable {
    case data
    case settings

    var id: String { rawValue }

    /// The catalog key for this destination's name. Shared with the web app —
    /// the same two entries `i18n-strings.js` spells for its Utility group.
    var localizationKey: String {
        switch self {
        case .data: "nav.dataLibrary"
        case .settings: "nav.settings"
        }
    }

    var fallbackName: String {
        switch self {
        case .data: "Data Library"
        case .settings: "Settings"
        }
    }

    /// §4.1: "Data 使用 `externaldrive`/`tray.full` 一类数据库语义符号,
    /// Settings 使用头像或 `gearshape`".
    var systemImage: String {
        switch self {
        case .data: "externaldrive"
        case .settings: "gearshape"
        }
    }
}

// The `ToolbarContent` that used to sit here is gone, and the note is here so
// it is not re-invented: the panel header owns this entry now. §4.1 asks for
// the Utility entry in the same place on every primary workspace, and the
// resident sheet's header IS that place — a `.topBarTrailing` toolbar item
// would have to belong to a navigation bar the sheet layout does not have.
// `RailWorkspaceView.destinationMenu(for:)` builds the same menu, off the same
// `UtilityDestination` cases above, where the reader can actually reach it.

/// A Utility destination, presented over whichever workspace opened it.
///
/// §4.1: "Data/Settings 被关闭后必须返回原 Tab、原导航路径与原滚动位置." A sheet
/// gives that for nothing — the tab underneath is never torn down, so closing
/// restores it exactly. A fourth tab would not have: switching away and back
/// is a navigation event, and the workspace would have to remember its own
/// state to survive one.
struct UtilityDestinationView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss

    let destination: UtilityDestination
    @Bindable var itineraries: ItineraryStore
    @Bindable var library: RideLibrary
    @Binding var appearance: String
    @Bindable var network: RailNetworkStore
    @Bindable var controller: RailMapController

    var body: some View {
        NavigationStack {
            Group {
                switch destination {
                case .data:
                    DataManagerView(itineraries: itineraries, library: library)
                case .settings:
                    SettingsView(
                        appearance: $appearance,
                        network: network,
                        controller: controller,
                        itineraries: itineraries,
                        library: library)
                }
            }
            .toolbar {
                // §14.4: a modal must be closable without a swipe, or Switch
                // Control and keyboard readers cannot leave it.
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label(
                            localization.text("utility.close", fallback: "Back"),
                            systemImage: "xmark")
                    }
                    // The sweep's fallback for a sheet it cannot close by name
                    // is a swipe, and a swipe over a Form scrolls the Form
                    // instead — so a harness that misses this button does not
                    // fail, it just carries the Data Library over every screen
                    // it visits afterwards. See `utilityDataButton`.
                    .accessibilityIdentifier("utilityCloseButton")
                }
            }
        }
    }
}

// The workspace menu uses the system tab bar: transparent on iOS 26+, solid
// before that. Utility sheets have no tab bar and keep the system's own
// bottom inset. Do not add a second one.
