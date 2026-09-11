import Foundation

/// The workspace compositions supported by the available window.
///
/// These are content-fit decisions, not device categories: rotation, Split
/// View, Stage Manager, and future window sizes all follow the same policy.
public enum WorkspaceLayoutMode: Equatable, Sendable {
    case compactOverlay
    case sideBySide
}

/// Pure scalar policy for choosing the workspace composition and reading
/// column width. The SwiftUI layer adapts `CGSize` into these inputs; keeping
/// the decision here makes every breakpoint independently testable without
/// SwiftUI or CoreGraphics.
public struct WorkspaceLayoutPolicy: Equatable, Sendable {
    public var width: Double
    public var height: Double

    private static let minimumPanelWidth = 300.0
    private static let idealPanelFraction = 0.34
    private static let tallWindowPanelWidth = 360.0
    private static let maximumPanelWidth = 440.0
    private static let minimumMapWidth = 360.0
    /// A short landscape phone cannot leave any map above a resident sheet.
    /// Docking may spend the final 60 points of the normal map allowance while
    /// still leaving a useful touch surface beside the fixed reading column.
    private static let minimumLandscapeMapWidth = 300.0

    /// The docked card's margin from the window's edges, in the `.sideBySide`
    /// composition — owned here, rather than duplicated as a private constant
    /// in the SwiftUI layer, so the breakpoint below and the composition that
    /// draws the card cannot drift apart on what "the card's gutter" means.
    public static let dockInset = 16.0

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// A tall/narrow window gets the phone's resident sheet. A landscape
    /// window may dock once it fits the 300 pt reading column, both gutters
    /// and a 300 pt map; this keeps the map reachable on the 667 × 375 point
    /// iPhone canvas, where a full-height resident sheet covers it completely.
    /// Other windows retain the 360 pt map allowance and therefore the 692 pt
    /// breakpoint. There is no third, wider composition any more — a native
    /// `NavigationSplitView` sidebar used to take over above 1,180 pt, but it
    /// drew iPadOS's own top tab capsule where every other width shows the
    /// phone's bottom tab bar, and it disagreed with the phone sheet about how
    /// many of the reader's destinations were mounted at once. One docked
    /// composition now covers every normal window from 692 pt up, plus
    /// landscape windows from 632 pt up.
    ///
    /// The threshold spends `dockInset` twice, not once: the card sits
    /// `dockInset` in from the window's leading edge AND the map needs
    /// `dockInset` of daylight past the card's trailing edge before it counts
    /// as a usable map, or the reader gets a sliver wedged against the
    /// card with no gutter of its own.
    public var mode: WorkspaceLayoutMode {
        let twoColumnThreshold =
            Self.minimumPanelWidth
            + minimumMapWidthForComposition
            + Self.dockInset * 2
        if width >= twoColumnThreshold {
            return .sideBySide
        }

        return .compactOverlay
    }

    public var sidePanelWidth: Double {
        // Portrait iPad windows need the reading width the former regular-size
        // layout provided. Wide windows instead scale the column until its
        // content maximum, preserving the rest for the map.
        let preferred = height > width
            ? Self.tallWindowPanelWidth
            : min(
                max(width * Self.idealPanelFraction, Self.minimumPanelWidth),
                Self.maximumPanelWidth)
        // The breakpoint and the actual column must spend the same width.
        let available = width - minimumMapWidthForComposition - Self.dockInset * 2
        return min(preferred, max(Self.minimumPanelWidth, available))
    }

    private var minimumMapWidthForComposition: Double {
        width > height ? Self.minimumLandscapeMapWidth : Self.minimumMapWidth
    }
}
