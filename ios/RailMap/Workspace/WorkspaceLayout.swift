import RailPresentation
import SwiftUI

struct PlaybackBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Shared compact panel headers, with smaller visuals inside 44 pt targets.
enum WorkspaceMenuMetrics {
    static let titleSize: CGFloat = 20
    static let titleRowHeight: CGFloat = 24
    static let iconSize: CGFloat = 18
    static let buttonSide: CGFloat = 32
    static let touchSide: CGFloat = 44
    static let horizontalInset: CGFloat = 16
    static let contentTopInset: CGFloat = 8
    static let contentSpacing: CGFloat = 12
    static let listRowVerticalInset: CGFloat = 6
    static let fieldHorizontalInset: CGFloat = 12
    static let compactButtonVerticalInset: CGFloat = 4
    static let topInset: CGFloat = 12
    static let bottomInset: CGFloat = 8
    static let actionSpacing: CGFloat = 4
    static let titleActionSpacing: CGFloat = 8
    static let stackedActionSpacing: CGFloat = 8
    static let subtitleSpacing: CGFloat = 2
    static let cardCornerRadius: CGFloat = 28
    static let journeyHeaderHeight: CGFloat = 64
    static let journeyLogoSide: CGFloat = 28
    static let journeyActionWidth: CGFloat = 48
    static let journeyCompactHeight: CGFloat = 280

    /// Every tab reserves the same title and subtitle slots, including empty subtitles.
    static func headerTextHeight(titleRow: CGFloat, stacked: Bool, drawsSubtitle: Bool) -> CGFloat {
        let lines: CGFloat = stacked ? 2 : 1
        return titleRow * lines + (drawsSubtitle
            ? BottomChromeMetrics.subtitleRow * lines + subtitleSpacing : 0)
    }

    static func headerContentHeight(titleRow: CGFloat, stacked: Bool, drawsSubtitle: Bool) -> CGFloat {
        let text = headerTextHeight(titleRow: titleRow, stacked: false, drawsSubtitle: drawsSubtitle)
        return stacked ? text + stackedActionSpacing + touchSide : max(text, touchSide)
    }
}

/// Shared inputs let every tab use the same fitted title font.
struct WorkspacePanelHeading {
    let title: String
    let hasSubtitle: Bool
    let actionCount: Int
}

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
            height: Double(containerSize.height),
            isMacCatalyst: isMacCatalyst)
    }

    private var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    var mode: WorkspaceLayoutMode {
        policy.mode
    }

    var sidePanelWidth: CGFloat {
        CGFloat(policy.sidePanelWidth)
    }
}
