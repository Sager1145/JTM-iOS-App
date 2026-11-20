import Foundation

/// Where a focus fit may put its content: the free map area between the
/// docked menu card and the column of map control buttons.
///
/// Pure scalars in the map view's own coordinates (points, x from the view's
/// left edge), so the rule is testable without MapKit or SwiftUI. The app
/// measures the two frames and asks this type; `RailMapController` hands the
/// answer to every fit through `framingInsets` and `fitPadding`.
///
/// The rule:
/// - **Menu docked beside the map** (`dockedMenu` is set — Mac and the
///   side-by-side layouts): the free area runs horizontally from the menu's
///   inner edge plus `sideMargin` to the control column's inner edge minus
///   `sideMargin`. A side with nothing on it keeps `bareEdgeInset`. Which side
///   a frame is on is read from the frame itself, so a right-to-left layout
///   (menu at the right, controls at the left) mirrors with no flag.
/// - **Menu not docked** (`dockedMenu` is nil — the phone's sheet, a hidden
///   menu, the hinged layouts): `fallback`, the rule those layouts already
///   had, unchanged. The control column is not counted there.
/// - **Vertical**: always `fallback`'s top and bottom. The docked card and the
///   control column are side columns; the horizontal rule already keeps the
///   content clear of both, so there is no vertical overlap left to solve.
/// - **Too narrow**: when the free width would be under `minimumFreeWidth`,
///   the control column is dropped first (content may pass under the
///   buttons, but stays beside the menu); if it is still too narrow both
///   sides fall back to `bareEdgeInset` and the content is centred in the
///   whole view.
public struct FocusFramePolicy: Equatable, Sendable {
    /// Distances from the map view's four edges.
    public struct Insets: Equatable, Sendable {
        public var top: Double
        public var left: Double
        public var bottom: Double
        public var right: Double

        public init(top: Double, left: Double, bottom: Double, right: Double) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }
    }

    /// A horizontal extent in the map view's coordinates.
    public struct Span: Equatable, Sendable {
        public var minX: Double
        public var maxX: Double

        public init(minX: Double, maxX: Double) {
            self.minX = Swift.min(minX, maxX)
            self.maxX = Swift.max(minX, maxX)
        }

        var midX: Double { (minX + maxX) / 2 }
    }

    /// A rectangle in the map view's coordinates.
    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public var midX: Double { x + width / 2 }
        public var maxX: Double { x + width }

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// Breathing room between an obstruction's edge and the content. The
    /// app's `RailSpacing.s20`.
    public static let sideMargin = 20.0
    /// The inset of a side nothing covers — the margin every fit already had.
    public static let bareEdgeInset = 40.0
    /// Below this free width the rule gives up on an obstruction (see the
    /// type's comment for the order).
    public static let minimumFreeWidth = 160.0

    public var mapWidth: Double
    public var mapHeight: Double
    /// The docked menu card's horizontal extent, or nil when no menu is
    /// docked beside the map.
    public var dockedMenu: Span?
    /// The control button column's horizontal extent, or nil when it is not
    /// laid out.
    public var controlColumn: Span?
    /// The insets the layout had before this rule; used whole when no menu is
    /// docked, and for top and bottom always.
    public var fallback: Insets

    public init(
        mapWidth: Double, mapHeight: Double,
        dockedMenu: Span?, controlColumn: Span?, fallback: Insets
    ) {
        self.mapWidth = mapWidth
        self.mapHeight = mapHeight
        self.dockedMenu = dockedMenu
        self.controlColumn = controlColumn
        self.fallback = fallback
    }

    /// Whether the free-area rule (rather than `fallback`) decides the sides.
    public var usesFreeArea: Bool { dockedMenu != nil && mapWidth > 0 }

    /// The free area as insets from the map view's edges.
    public var insets: Insets {
        guard usesFreeArea, let dockedMenu else { return fallback }
        let full = sides(covering: [dockedMenu, controlColumn])
        if mapWidth - full.left - full.right >= Self.minimumFreeWidth {
            return Insets(top: fallback.top, left: full.left, bottom: fallback.bottom, right: full.right)
        }
        let menuOnly = sides(covering: [dockedMenu])
        if mapWidth - menuOnly.left - menuOnly.right >= Self.minimumFreeWidth {
            return Insets(
                top: fallback.top, left: menuOnly.left, bottom: fallback.bottom, right: menuOnly.right)
        }
        return Insets(
            top: fallback.top, left: Self.bareEdgeInset,
            bottom: fallback.bottom, right: Self.bareEdgeInset)
    }

    /// The free area itself. Width and height never go below zero.
    public var freeRect: Rect {
        let insets = insets
        return Rect(
            x: insets.left, y: insets.top,
            width: max(0, mapWidth - insets.left - insets.right),
            height: max(0, mapHeight - insets.top - insets.bottom))
    }

    /// The edge padding to hand MapKit so the content lands in `insets`.
    ///
    /// MapKit does not fit into the whole view: it fits into an inner area
    /// (the view less its layout margins, which the docked layout sets to the
    /// menu's width so the Legal label clears the card). Padding is measured
    /// from that inner area, so handing it insets measured from the view's
    /// edge counts the menu twice and pushes the content far to the right.
    /// `fittingArea` is that inner area's horizontal extent, measured from
    /// the live map; the sides returned are the remainder.
    ///
    /// Top and bottom are passed through: the vertical rule is unchanged, and
    /// so is everything about a layout with no docked menu.
    public func mapPadding(fittingArea: Span) -> Insets {
        let insets = insets
        guard usesFreeArea else { return insets }
        let left = max(0, insets.left - fittingArea.minX)
        let right = max(0, insets.right - (mapWidth - fittingArea.maxX))
        // No room left inside the inner area: give the content all of it
        // rather than hand MapKit padding wider than the area it pads.
        guard fittingArea.maxX - fittingArea.minX - left - right >= 1 else {
            return Insets(top: insets.top, left: 0, bottom: insets.bottom, right: 0)
        }
        return Insets(top: insets.top, left: left, bottom: insets.bottom, right: right)
    }

    private func sides(covering spans: [Span?]) -> (left: Double, right: Double) {
        var left = Self.bareEdgeInset
        var right = Self.bareEdgeInset
        for span in spans.compactMap({ $0 }) {
            if span.midX < mapWidth / 2 {
                left = max(left, span.maxX + Self.sideMargin)
            } else {
                right = max(right, mapWidth - span.minX + Self.sideMargin)
            }
        }
        return (left, right)
    }
}
