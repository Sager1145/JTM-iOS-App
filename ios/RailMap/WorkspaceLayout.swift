import RailPresentation
import SwiftUI

/// Centralises the breakpoints and column widths for `RailWorkspaceView`.
///
/// SwiftUI owns only the environment adaptation. All content-fit decisions are
/// delegated to `WorkspaceLayoutPolicy`, where they are covered by fast unit
/// tests without importing SwiftUI or CoreGraphics.
struct WorkspaceLayoutMetrics: Equatable {
    var containerSize: CGSize

    private var policy: WorkspaceLayoutPolicy {
        WorkspaceLayoutPolicy(
            width: Double(containerSize.width),
            height: Double(containerSize.height))
    }

    var mode: WorkspaceLayoutMode {
        policy.mode
    }

    var sidePanelWidth: CGFloat {
        CGFloat(policy.sidePanelWidth)
    }
}
