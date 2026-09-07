import Foundation

/// The workspace compositions supported by the available window.
///
/// These are content-fit decisions, not device categories: rotation, Split
/// View, Stage Manager, and future window sizes all follow the same policy.
public enum WorkspaceLayoutMode: Equatable, Sendable {
    case compactOverlay
    case sideBySide
    case threeColumn
}

/// Pure scalar policy for choosing the workspace composition and reading
/// column width. The SwiftUI layer adapts `CGSize` and Dynamic Type into these
/// inputs; keeping the decision here makes every breakpoint independently
/// testable without SwiftUI or CoreGraphics.
public struct WorkspaceLayoutPolicy: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var isAccessibilitySize: Bool

    private static let minimumPanelWidth = 300.0
    private static let idealPanelFraction = 0.34
    private static let tallWindowPanelWidth = 360.0
    private static let maximumPanelWidth = 440.0
    private static let minimumMapWidth = 360.0
    private static let splitViewSeparatorAllowance = 1.0
    private static let minimumThreeColumnHeight = 560.0
    private static let threeColumnWidth = 1_180.0
    private static let accessibleThreeColumnWidth = 1_260.0

    public init(width: Double, height: Double, isAccessibilitySize: Bool) {
        self.width = width
        self.height = height
        self.isAccessibilitySize = isAccessibilitySize
    }

    public var mode: WorkspaceLayoutMode {
        let threeColumnThreshold = isAccessibilitySize
            ? Self.accessibleThreeColumnWidth
            : Self.threeColumnWidth

        if width >= threeColumnThreshold, height >= Self.minimumThreeColumnHeight {
            return .threeColumn
        }

        let twoColumnThreshold =
            Self.minimumPanelWidth
            + Self.minimumMapWidth
            + Self.splitViewSeparatorAllowance
        if width >= twoColumnThreshold {
            return .sideBySide
        }

        return .compactOverlay
    }

    public var sidePanelWidth: Double {
        // Portrait iPad windows need the reading width the former regular-size
        // layout provided. Wide windows instead scale the column until its
        // content maximum, preserving the rest for the map.
        if height > width {
            return min(Self.tallWindowPanelWidth, Self.maximumPanelWidth)
        }
        return min(
            max(width * Self.idealPanelFraction, Self.minimumPanelWidth),
            Self.maximumPanelWidth)
    }
}
