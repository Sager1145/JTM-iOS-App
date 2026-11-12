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

    /// Zoom the camera must move away from the installed level, towards a neighbour, before
    /// another level is chosen: half the gap to that neighbour plus 0.2. For half-zoom spacing this
    /// is 0.45 (map-lock's 0.25 hysteresis plus 0.2), and it grows with the spacing so a wider gap
    /// still has hysteresis.
    public func switchDistance(from installed: Int, towards zoom: Double) -> Double {
        let neighbour = zoom > zooms[installed] ? installed + 1 : installed - 1
        guard zooms.indices.contains(neighbour) else { return 0.2 }
        return abs(zooms[neighbour] - zooms[installed]) / 2 + 0.2
    }

    /// Throws ``RailPackError/badLevel(_:)`` (the offending level) unless every zoom is finite and
    /// each is at least ``RailPackFormat/minZoomGap`` above the one before.
    public init(zooms: [Double]) throws {
        guard !zooms.isEmpty else { throw RailPackError.corrupt("empty ladder") }
        for (index, zoom) in zooms.enumerated() {
            guard zoom.isFinite else { throw RailPackError.badLevel(index) }
            if index > 0, zoom - zooms[index - 1] < RailPackFormat.minZoomGap - 1e-9 { throw RailPackError.badLevel(index) }
        }
        self.zooms = zooms
    }

    /// Half-zoom levels `k = 8...34`, zoom 4.0 to 17.0.
    public static let `default` = try! RailPackLadder(zooms: (8...34).map { Double($0) / 2 })

    /// Rebuilds the ladder from the per-level `mapPointsPerPoint` stored in a file.
    public init(mapPointsPerPoint: [Double]) throws {
        try self.init(zooms: mapPointsPerPoint.map { 19 - log2($0) })
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

    /// Keeps `installed` until the camera is more than ``switchDistance(from:towards:)`` zoom levels from
    /// it, then takes the nearest level. The end levels absorb every camera beyond them.
    public func chooseLevel(cameraZoom: Double, installed: Int?) -> Int {
        guard let installed, zooms.indices.contains(installed) else {
            return nearestLevel(cameraZoom: cameraZoom)
        }
        if installed == 0 && cameraZoom <= zooms[0] { return installed }
        if installed == zooms.count - 1 && cameraZoom >= zooms[zooms.count - 1] { return installed }
        if abs(zooms[installed] - cameraZoom) <= switchDistance(from: installed, towards: cameraZoom) { return installed }
        return nearestLevel(cameraZoom: cameraZoom)
    }
}
