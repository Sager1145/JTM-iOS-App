import Foundation

/// Native railway detail follows the basemap scale, normalised to a
/// phone-class reference viewport: on a larger viewport the same camera zoom
/// shows more geography, so the phone-tuned ladder is shifted to match the
/// content fit rather than the raw zoom. Viewport culling and the renderer's
/// vertex budget bound work separately from this eligibility policy.
public struct NetworkVisibilityPolicy: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// iPhone-class short edge, in points, that the phone-tuned detail
    /// ladder was authored against.
    public static let viewportReferenceShortEdge = 390.0

    /// Clamp bounds for the viewport adjustment, in zoom levels: at most a
    /// half level more detail on a smaller-than-reference viewport, at most
    /// one and a half levels less on a larger one.
    public static let viewportZoomAdjustmentRange = -1.5...0.5

    /// How many zoom levels to add to the raw camera zoom so that the
    /// phone-tuned detail ladder sees the same content fit on any viewport.
    public static func viewportZoomAdjustment(width: Double, height: Double) -> Double {
        let shortEdge = min(width, height)
        guard shortEdge > 0, shortEdge.isFinite else { return 0 }
        let adjustment = log2(viewportReferenceShortEdge / shortEdge)
        guard adjustment.isFinite else { return 0 }
        return min(max(adjustment, viewportZoomAdjustmentRange.lowerBound),
            viewportZoomAdjustmentRange.upperBound)
    }

    public func visibilityZoom(cameraZoom: Double) -> Double {
        cameraZoom + Self.viewportZoomAdjustment(width: width, height: height)
    }

    public func visibilityBucket(cameraZoom: Double) -> Int {
        Int(floor(visibilityZoom(cameraZoom: cameraZoom)))
    }

    /// Below even a world fitted into one logical point (app z=-8). This
    /// finite sentinel keeps high-speed corridors eligible at every usable
    /// MapKit camera distance, including the globe overview.
    public static let overviewMinZoomMapLibre = -30

    /// Operators whose every line stays in the overview regardless of rank:
    /// the intercity networks a reader zoomed out to a whole continent still
    /// expects to see, the way every Shinkansen and the THSR (rank 0) already
    /// do. Amtrak's 36 rank-1 corridors and VIA Rail's four are the reason
    /// this table exists — without it North America was empty below z4.
    public static let overviewOperatorsByRegion: [String: Set<String>] = [
        "us": ["Amtrak"],
        "ca": ["Amtrak", "Via Rail Canada"],
    ]

    /// Shipped packages use rank 0 for high-speed rail except Korea, whose
    /// three dedicated high-speed lines use rank 1. Restrict that compatibility
    /// rule to Korea: rank 1 in Hong Kong includes ordinary urban metro lines.
    /// Beyond rank, a line is a backbone when its operator is listed for its
    /// region in ``overviewOperatorsByRegion``, or when it is a Japanese line
    /// named 新幹線 (belt and braces: the nine shipped Shinkansen are rank 0).
    public static func isOverviewBackbone(
        rank: Int?, region: String?, operator: String? = nil, name: String? = nil
    ) -> Bool {
        if rank == 0 || (region == "kr" && rank == 1) { return true }
        if region == "jp", let name, name.contains("新幹線") { return true }
        if let region, let `operator`,
           overviewOperatorsByRegion[region]?.contains(`operator`) == true {
            return true
        }
        return false
    }

    /// Native thresholds in the 512-point MapLibre convention. The MapKit
    /// boundary converts once to the app's 256-point scale (+1). Length is
    /// the complete visibility group's length, so administrative pieces enter
    /// together. Editorial importance sets the base tier; length may delay a
    /// ranked line by at most one level. Short airport connectors and urban
    /// trunks therefore remain useful at regional scale instead of all waiting
    /// for the shortest-line tier. These are app policy, not Apple thresholds.
    public static func lineMinZoomMapLibre(
        portedMinZoom: Int, rank: Int?, visibilityLengthKm: Double,
        region: String? = nil, operator: String? = nil, name: String? = nil
    ) -> Int {
        if isOverviewBackbone(rank: rank, region: region, operator: `operator`, name: name) {
            return overviewMinZoomMapLibre
        }
        let byLength: Int
        switch visibilityLengthKm {
        case 300...: byLength = 3
        case 120...: byLength = 4
        case 50...: byLength = 5
        case 20...: byLength = 6
        default: byLength = 7
        }
        let lengthFloor = max(portedMinZoom, byLength)
        guard let rank, (1...4).contains(rank) else { return lengthFloor }
        let importanceFloor = rank + 2
        return max(importanceFloor, min(lengthFloor, importanceFloor + 1))
    }
}
