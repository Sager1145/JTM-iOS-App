import Foundation

/// The zoom ladder of a `.railpack` file and the rule that picks a level for a camera.
///
/// The ladder is data in the file header (one `mapPointsPerPoint` per level); the
/// default is the half-zoom ladder z4.0 to z17.0 (27 levels, level `k` = zoom `k / 2`).
/// Level `k` has `mapPointsPerPoint = 2^(19 - k/2)`, the 512-point convention of the
/// stroke engine.
public struct RailPackLadder: Equatable, Sendable {
    /// Zoom of each level, strictly ascending.
    public let zooms: [Double]

    /// Map-lock's 0.25 zoom hysteresis plus 0.2: the camera must be farther than this
    /// from the installed level's zoom before another level is chosen.
    public static let switchDistance: Double = 0.25 + 0.2

    public init(zooms: [Double]) {
        precondition(!zooms.isEmpty && zip(zooms, zooms.dropFirst()).allSatisfy { $0 < $1 }, "zooms must be ascending")
        self.zooms = zooms
    }

    /// Half-zoom levels `k = 8...34`, zoom 4.0 to 17.0.
    public static let `default` = RailPackLadder(zooms: (8...34).map { Double($0) / 2 })

    /// Rebuilds the ladder from the per-level `mapPointsPerPoint` stored in a file.
    public init(mapPointsPerPoint: [Double]) {
        self.init(zooms: mapPointsPerPoint.map { 19 - log2($0) })
    }

    public var levelCount: Int { zooms.count }

    public static func mapPointsPerPoint(forZoom zoom: Double) -> Double { pow(2, 19 - zoom) }

    public func mapPointsPerPoint(level: Int) -> Double { Self.mapPointsPerPoint(forZoom: zooms[level]) }

    /// The level whose zoom is nearest the camera; the lowest or highest level outside the ladder.
    public func nearestLevel(cameraZoom: Double) -> Int {
        var best = 0
        for index in zooms.indices where abs(zooms[index] - cameraZoom) < abs(zooms[best] - cameraZoom) {
            best = index
        }
        return best
    }

    /// Keeps `installed` until the camera is more than ``switchDistance`` zoom levels from
    /// it, then takes the nearest level. The end levels absorb every camera beyond them.
    public func chooseLevel(cameraZoom: Double, installed: Int?) -> Int {
        guard let installed, zooms.indices.contains(installed) else {
            return nearestLevel(cameraZoom: cameraZoom)
        }
        if installed == 0 && cameraZoom <= zooms[0] { return installed }
        if installed == zooms.count - 1 && cameraZoom >= zooms[zooms.count - 1] { return installed }
        if abs(zooms[installed] - cameraZoom) <= Self.switchDistance { return installed }
        return nearestLevel(cameraZoom: cameraZoom)
    }
}
