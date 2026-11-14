import RailPresentation
import SwiftUI

/// Where the popup a view belongs to is presented, and how it closes.
///
/// `WorkspaceSurfacePolicy` decides the host; the workspace writes the answer
/// into the environment so a popup's own views never test the platform. Views
/// shown by a system sheet read `.systemSheet` and close with `dismiss`; views
/// filling the docked panel read `.panel` and close through
/// `closePanelSurface`, because `dismiss` called from a view that is not in a
/// presentation can close a Catalyst window.
/// True while a panel-hosted popup shows a surface of its own over the card
/// (ride details, a trip note, a save in flight). The workspace's Esc closes the
/// whole popup, so it stands down while this is up and lets that surface answer.
struct PanelNestedSurfaceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    func panelNestedSurface(_ isUp: Bool) -> some View {
        preference(key: PanelNestedSurfaceKey.self, value: isUp)
    }
}

/// An action handed down through the environment. Closures are never equal, so
/// a bare closure would invalidate every reader on each workspace update; these
/// compare by `key` alone, and the closure acts on state storage that outlives
/// each evaluation of the workspace body.
struct PanelCloseAction: Equatable {
    let key: String
    let run: () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    func callAsFunction() { run() }
}

struct PanelGroupPickerAction: Equatable {
    let key: String
    let run: (String) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    func callAsFunction(_ trainID: String) { run(trainID) }
}

extension EnvironmentValues {
    @Entry var popupHost: WorkspaceSurfaceHost = .systemSheet

    /// Non-nil only inside a panel-hosted surface: sets the workspace's sheet
    /// to nil, which restores the tabs.
    @Entry var closePanelSurface: PanelCloseAction?

    /// Non-nil only in the docked panel: opens the group picker for a trip id
    /// in the panel, because the row that asks lives in the hidden tabs.
    @Entry var presentGroupPicker: PanelGroupPickerAction?
}
