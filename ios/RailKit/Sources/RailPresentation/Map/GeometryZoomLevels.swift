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

    /// The one neighbour worth pre-building while idle: the level in the
    /// direction of the last zoom (`lastZoomDirection` > 0 zooming in, < 0
    /// out; 0, no zoom seen yet, takes the finer level).
    public static func prebuildNeighbour(of level: Int, lastZoomDirection: Int) -> Int {
        lastZoomDirection < 0 ? level - 1 : level + 1
    }

    /// The visible rect a prebuild of `level` should cover at camera `zoom`.
    /// A level coarser than the camera shows a larger area when the camera
    /// reaches it, so the rect grows about its centre by
    /// `2^(zoom - nominalZoom(level))`; a finer (or equal) level keeps the
    /// rect as is. Without this, an adopted prebuild still left a ring of
    /// missing work for the foreground to build.
    public static func prebuildVisibleRect(
        visible: MapBuildArea.Rect, zoom: Double, level: Int
    ) -> MapBuildArea.Rect {
        let factor = exp2(zoom - nominalZoom(level: level))
        guard factor > 1 else { return visible }
        let width = visible.width * factor
        let height = visible.height * factor
        return MapBuildArea.Rect(
            x: visible.x + (visible.width - width) / 2,
            y: visible.y + (visible.height - height) / 2,
            width: width, height: height)
    }

    /// (c) Whether to swap the installed level now during a gesture.
    public static func shouldSwapDuringGesture(
        zoom: Double, installed: Int, wanted: Int, wantedIsReady: Bool
    ) -> Bool {
        wanted != installed
            && wantedIsReady
            && abs(zoom - nominalZoom(level: installed)) > gestureSwapDrift
    }

    /// Whether a freshly landed, ready level should be installed even though
    /// the camera has already moved on to a later wanted level. Preparations
    /// take longer than the camera needs to cross a level, so "latest wins"
    /// alone never installs anything while zooming: a landed level is
    /// installed when it is nearer the camera than the installed one.
    public static func installsLanded(
        landed: Int, installed: Int?, zoom: Double, ready: Bool
    ) -> Bool {
        guard ready, let installed, landed != installed else { return false }
        return abs(zoom - nominalZoom(level: landed)) < abs(zoom - nominalZoom(level: installed))
    }

    /// What a landed preparation does.
    public enum LandingInstall: Equatable, Sendable {
        /// Rebuild as usual: the wanted level installs through the ordinary
        /// path (when it is ready) or the landing is simply discarded.
        case ordinary
        /// Install the landed level now, on the rect it was prepared for.
        case installLanded
    }

    /// The landing rule. `installsLanded(ready:)` checks a landed level against
    /// the CURRENT camera's padded build rect, and every 0.25 zoom step out
    /// widens that rect by about 19%, so on the way down no landed level was
    /// ever "ready": the installed level never moved and each landing started
    /// another preparation (map-lock run 3, finding A). The landed level is
    /// installed when (a) the wanted level is not itself ready, (b) the landed
    /// level is nearer the camera than the installed one, and (c) its own
    /// prepared rect still contains what is on screen (`landedUsable`: the
    /// landed level has no missing work for that rect and the rect contains
    /// the visible rect). The padding is then added by a later preparation.
    public static func landingInstall(
        landed: Int, installed: Int?, zoom: Double, wantedReady: Bool, landedUsable: Bool
    ) -> LandingInstall {
        guard !wantedReady, landedUsable,
              installsLanded(landed: landed, installed: installed, zoom: zoom, ready: true)
        else { return .ordinary }
        return .installLanded
    }

    /// Whether a preparation for `level` is still worth keeping when the
    /// camera is at `zoom` with `installed` on screen: it is the wanted level
    /// or one of its idle neighbours.
    public static func isStillWanted(level: Int, zoom: Double, installed: Int?) -> Bool {
        let wanted = wantedLevel(zoom: zoom, installed: installed)
        return level == wanted || neighbourLevels(of: wanted).contains(level)
    }

    /// Whether the idle neighbour prebuild of `levels` survives the camera
    /// moving to `zoom`. A prebuild whose level the camera has just reached is
    /// the wanted level itself, not one of its neighbours, so it must be kept
    /// (and adopted) rather than thrown away: every level passes
    /// ``isStillWanted(level:zoom:installed:)``.
    public static func keepsNeighbourPrebuild(
        levels: [Int], zoom: Double, installed: Int?
    ) -> Bool {
        levels.allSatisfy { isStillWanted(level: $0, zoom: zoom, installed: installed) }
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
