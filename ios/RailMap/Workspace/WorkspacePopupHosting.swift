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
extension EnvironmentValues {
    @Entry var popupHost: WorkspaceSurfaceHost = .systemSheet

    /// Non-nil only inside a panel-hosted surface: sets the workspace's sheet
    /// to nil, which restores the tabs.
    @Entry var closePanelSurface: (() -> Void)?

    /// Non-nil only in the docked panel: opens the group picker for a trip id
    /// in the panel, because the row that asks lives in the hidden tabs.
    @Entry var presentGroupPicker: ((String) -> Void)?
}
