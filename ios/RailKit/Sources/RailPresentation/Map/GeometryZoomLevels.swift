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

    /// The level a zoom-out to the overview lands on (measured). A frame at or
    /// below it is held resident, see ``GeometryFrameResidency``.
    public static let overviewLevel = 11

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

    /// Whether a running prebuild's rect still covers enough of the rect a
    /// fresh target would use that restarting it would only throw work away.
    /// The target follows the camera, so exact equality would cancel a
    /// multi-second prebuild on every idle pan or settle; at least half of
    /// the wanted rect inside the running one keeps it (the foreground
    /// builds whatever is still missing).
    public static func prebuildStillCovers(
        running: MapBuildArea.Rect, wanted: MapBuildArea.Rect
    ) -> Bool {
        let width = min(running.x + running.width, wanted.x + wanted.width) - max(running.x, wanted.x)
        let height = min(running.y + running.height, wanted.y + wanted.height) - max(running.y, wanted.y)
        guard width > 0, height > 0 else { return false }
        return width * height >= 0.5 * wanted.width * wanted.height
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

/// Smoothed zoom speed of the camera, in zoom levels per second (negative
/// zooming out). Fed from every camera change; reads 0 once the last zoom
/// change is older than ``staleAfter``.
public struct ZoomTravel: Equatable, Sendable {
    public static let staleAfter: Double = 0.3
    /// Zoom changes smaller than this are noise, not travel.
    public static let noise: Double = 0.001

    private var lastZoom: Double?
    private var lastChangeAt: Double?
    private var smoothed: Double = 0
    /// Which way the zoom last moved (1 in, -1 out, 0 none yet). Unlike
    /// ``rate(at:)`` it survives the camera coming to rest.
    public private(set) var direction = 0
    private var hasRate = false

    public init() {}

    public mutating func note(zoom: Double, at now: Double) {
        guard let lastZoom, let lastChangeAt else {
            self.lastZoom = zoom
            self.lastChangeAt = now
            return
        }
        guard abs(zoom - lastZoom) > Self.noise else { return }
        let elapsed = max(now - lastChangeAt, 0.01)
        let instant = (zoom - lastZoom) / elapsed
        // The first interval seeds the rate: averaging it with the initial 0
        // would halve it and aim the first preparation too short.
        smoothed = elapsed > Self.staleAfter || !hasRate ? instant : 0.5 * smoothed + 0.5 * instant
        hasRate = true
        direction = zoom > lastZoom ? 1 : -1
        self.lastZoom = zoom
        self.lastChangeAt = now
    }

    /// The camera is zooming right now: the last zoom change is at most
    /// ``travellingWindow`` old and the rate is non-zero. The window stays
    /// below the 120 ms settle timer, so the settled rebuild reads "stopped".
    public static let travellingWindow: Double = 0.1

    public func isTravelling(at now: Double) -> Bool {
        guard let lastChangeAt, now - lastChangeAt <= Self.travellingWindow else { return false }
        return rate(at: now) != 0
    }

    public func rate(at now: Double) -> Double {
        guard let lastChangeAt, now - lastChangeAt <= Self.staleAfter else { return 0 }
        return smoothed
    }
}

extension GeometryZoomLevels {
    /// The level to prepare ahead of a zoom-out: where the camera will be
    /// when a preparation that takes `prepareSeconds` lands, with a margin of
    /// half again, at most three zoom levels ahead. nil unless the camera is
    /// zooming out fast enough to cross more than one spacing in that time.
    public static func travelLevel(
        zoom: Double, rate: Double, prepareSeconds: Double, minimumLevel: Int
    ) -> Int? {
        guard rate < 0, -rate * prepareSeconds > spacing else { return nil }
        let aimed = zoom + max(rate * prepareSeconds * 1.5, -3)
        return max(nearestLevel(zoom: aimed), minimumLevel)
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
