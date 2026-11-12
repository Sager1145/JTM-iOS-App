import Foundation
import RailCore

/// The fixed set of geometry levels the map bakes lane gaps, corner rounding
/// and simplification at, replacing the 0.25-zoom bucket step of
/// ``MapRebuildPolicy``. Levels sit half a zoom apart; the camera moves
/// between them with hysteresis so a zoom hovering near a boundary never
/// flaps. Pure and map-free so every rule is testable on the host.
public struct GeometryZoomLevels: Equatable, Sendable {
    /// Zoom distance between adjacent levels.
    public static let spacing: Double = 0.5
    /// Extra zoom past the midpoint between two levels a camera must travel
    /// before the wanted level moves.
    public static let hysteresis: Double = 0.2
    /// During a gesture the installed level is swapped only once the camera
    /// has drifted further than this from it (and the wanted level is ready).
    public static let gestureSwapDrift: Double = 0.5

    public init() {}

    /// The level whose nominal zoom is nearest `zoom`.
    public static func nearestLevel(zoom: Double) -> Int {
        Int((zoom / spacing).rounded())
    }

    /// The zoom a level's geometry is computed at, whatever the camera does.
    public static func nominalZoom(level: Int) -> Double {
        Double(level) * spacing
    }

    /// Lane LOD resolved at the level's nominal zoom with no history, so the
    /// geometry for a level is deterministic.
    public static func laneLOD(level: Int) -> (bucket: Int, scale: Double) {
        LaneLOD.resolve(zoom: nominalZoom(level: level), previousBucket: nil)
    }

    /// (a) The level `zoom` wants. With an installed level it is kept until
    /// the camera is more than half a spacing plus ``hysteresis`` away from
    /// its nominal zoom, then the nearest level is wanted.
    public static func wantedLevel(zoom: Double, installed: Int?) -> Int {
        guard let installed else { return nearestLevel(zoom: zoom) }
        let limit = spacing / 2 + hysteresis
        return abs(zoom - nominalZoom(level: installed)) > limit
            ? nearestLevel(zoom: zoom) : installed
    }

    /// (b) The levels to pre-build while idle: one below and one above.
    public static func neighbourLevels(of level: Int) -> [Int] {
        [level - 1, level + 1]
    }

    /// (c) Whether to swap the installed level now during a gesture.
    public static func shouldSwapDuringGesture(
        zoom: Double, installed: Int, wanted: Int, wantedIsReady: Bool
    ) -> Bool {
        wanted != installed
            && wantedIsReady
            && abs(zoom - nominalZoom(level: installed)) > gestureSwapDrift
    }

    /// Whether a preparation for `level` is still worth keeping when the
    /// camera is at `zoom` with `installed` on screen: it is the wanted level
    /// or one of its idle neighbours.
    public static func isStillWanted(level: Int, zoom: Double, installed: Int?) -> Bool {
        let wanted = wantedLevel(zoom: zoom, installed: installed)
        return level == wanted || neighbourLevels(of: wanted).contains(level)
    }
}

/// Cache identity of one line's geometry at one level.
public struct GeometryLevelCacheKey: Hashable, Sendable {
    public var lineID: String
    public var level: Int
    public var strokeGeneration: Int

    public init(lineID: String, level: Int, strokeGeneration: Int) {
        self.lineID = lineID
        self.level = level
        self.strokeGeneration = strokeGeneration
    }
}
