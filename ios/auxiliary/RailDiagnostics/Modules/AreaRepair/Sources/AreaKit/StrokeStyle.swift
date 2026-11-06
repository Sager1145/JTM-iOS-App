import Foundation

/// The stroke metrics the diagnostics smoother renders with, in points at
/// one zoom. Mirrors ios/RailMap/Design/RailStyle.swift (railWidth 1.5 =
/// station 6 × 0.25; lane gap = railWidth + 1.2; corner radius 6 × 0.6;
/// minimum corner radius max(1, 2 × railWidth × w); minimum ramp 24 pt),
/// with the weight ramp w = clamp(2^((z − 8) / 2), 1/3, 1).
public struct StrokeStyle: Codable, Equatable, Sendable {
    public var railWidth: Double
    public var laneGap: Double
    public var cornerRadius: Double
    public var minCornerRadius: Double
    public var minRamp: Double

    public init(railWidth: Double, laneGap: Double, cornerRadius: Double, minCornerRadius: Double, minRamp: Double) {
        self.railWidth = railWidth; self.laneGap = laneGap; self.cornerRadius = cornerRadius
        self.minCornerRadius = minCornerRadius; self.minRamp = minRamp
    }

    public static let fullWeightZoom = 8.0
    public static let minimumWeight = 1.0 / 3.0

    /// RailStyle.scale(atZoom:).
    public static func weight(atZoom zoom: Double) -> Double {
        guard zoom.isFinite else { return 1 }
        return min(max(pow(2, (zoom - fullWeightZoom) / 2), minimumWeight), 1)
    }

    /// RailStyle's tokens scaled for `zoom`.
    public static func diagnosticsDefault(zoom: Double) -> StrokeStyle {
        let w = weight(atZoom: zoom)
        let railWidth = 1.5
        return StrokeStyle(railWidth: railWidth * w, laneGap: (railWidth + 1.2) * w, cornerRadius: 3.6 * w,
                           minCornerRadius: max(1, railWidth * 2 * w), minRamp: 24)
    }

    /// MapKit map points per screen point at a 256-point-tile zoom.
    public static func mapPointsPerPoint(zoom: Double) -> Double { 268_435_456 / (256 * pow(2, zoom)) }

    public var contract: String {
        "w=\(railWidth);lane=\(laneGap);r=\(cornerRadius);rmin=\(minCornerRadius);ramp=\(minRamp)"
    }
}
