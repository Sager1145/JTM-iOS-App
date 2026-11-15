import Foundation

/// The numbers the stroke engine is driven with, in one place.
///
/// They used to live in the app target's `RailStyle`, which a host tool cannot
/// link. `RailStyle` now aliases them, so there is one source: changing a value
/// here changes what the app draws and what the bake writes, and
/// `RailBakeKit`'s input hash covers this file, so a changed token forces a
/// rebake.
///
/// Doubles throughout. `RailStyle` converts to `CGFloat` at its boundary, which
/// is the identity on every platform this app ships on.
public enum RailStrokeTokens {

    /// Diameter of an ordinary network station dot, in points at full scale.
    public static let stationDiameter: Double = 6
    /// Rail stroke = a quarter of the dot. Derived, never set independently.
    public static let railWidthToStationDiameter: Double = 0.25
    public static let railWidth: Double = stationDiameter * railWidthToStationDiameter

    /// The clear map between two DISTINCT railways sharing one corridor, edge to edge.
    public static let parallelGap: Double = 1.2
    /// Centre-to-centre spacing for distinct display lanes. It follows the same scale
    /// ramp as the stroke, so the clear gap stays constant relative to the railway.
    public static let parallelLaneCentreDistance: Double = railWidth + parallelGap

    /// The smallest radius a corner may PRESENT on screen: two stroke widths.
    public static let minCornerRadius: Double = railWidth * 2
    /// Absolute screen-space floor, including the widest zoom's weight ramp.
    public static let minimumScreenCornerRadius: Double = 1

    public static func minimumCornerRadius(atScale scale: Double) -> Double {
        max(minimumScreenCornerRadius, minCornerRadius * scale)
    }

    /// How far rounding a SHARP surveyed corner may move the drawn line off its vertex:
    /// half the rail width at this scale, so the stroke still covers the surveyed corner.
    public static func hardCornerMaxDeviation(atScale scale: Double) -> Double {
        railWidth * scale / 2
    }

    /// The radius a continuous stroke rounds its corners to where the surveyed polyline
    /// turns on a vertex (the web app's `RAILWAY_STYLE.strokeCornerRadiusPx`).
    public static let strokeCornerRadius: Double = stationDiameter * 0.6
    /// A lane change drifts over at least this many points, whatever the zoom makes of the
    /// 300 m ramp (railmap.js's STROKE_MIN_RAMP_PX).
    public static let strokeMinRamp: Double = 24

    /// `SEGMENT_SIMPLIFY_TOLERANCE_PX`: how far the drawn line may leave the surveyed one,
    /// in points of the zoom it is drawn for (1/16 point).
    public static let simplifyTolerance: Double = 0.0625

    /// How far a stored pack vertex may leave the engine's stroke, in points of the level it is
    /// stored for: 4 quanta (1/4 point), the largest step the size rule allows (limits record,
    /// docs/maintenance/2026-11-13-rail-pack-limits.md). Loosening it is a visible change that needs
    /// the user. The pack bake thins every finished stroke to this (`NetworkStrokeBake.thinned`); see docs/maintenance/2026-11-13-rail-pack-size-design.md.
    public static let packThinTolerance: Double = 0.25

    // MARK: - the weight ramp

    /// The app zoom at which a stroke reaches full weight (one level above MapLibre's 7).
    public static let fullWeightZoom: Double = 8
    /// Below the anchor the weight halves every TWO zoom levels.
    public static let weightZoomBase: Double = 2.0.squareRoot()
    /// …and it stops thinning at a third of token weight.
    public static let minWeightScale: Double = 1.0 / 3.0

    /// The shared factor every weight and every offset is multiplied by:
    /// `clamp(2^((z - anchor) / 2), 1/3, 1)`. `zoom` is this app's own zoom.
    public static func scale(atZoom zoom: Double) -> Double {
        guard zoom.isFinite else { return 1 }
        let raw = pow(2, (zoom - fullWeightZoom) / 2)
        return min(max(raw, minWeightScale), 1)
    }
}
