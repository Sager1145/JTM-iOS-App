import Foundation

/// Discrete, hysteretic lane-offset level of detail for the North America
/// continuous strokes.
///
/// Ported from `app/public/railmap-style.js`'s `LANE_LOD_BUCKETS` /
/// `laneScaleForZoom`. `laneGapPx` (railmap.js `_applyContinuousStrokes`,
/// `ios/RailMap/RailMapView.swift`'s counterpart) is a pure screen constant —
/// `railwayScaleAt(zoom) * (railWidthPx + parallelGapPx)` — with no low-zoom
/// collapse of its own, so a lane-1 line sits 156 m off its track at z10 and
/// roughly 12 km off it at z6, where a hub throat's lane index can reach 7.
///
/// The fix is not a continuous ramp: the continuous-stroke engine's rules
/// contract allows changing offsets or visibility but never lane MEMBERSHIP
/// or ORDER, and an offset that keeps sliding under the reader's eye would
/// read as the railway itself drifting. Three DISCRETE bands read instead as
/// "lanes gone" / "lanes half-spread" / "lanes full width":
///
///   - below z9: `scale == 0` — no offset at all.
///   - z9 ..< z12: `scale == 0.5` — half the resolved gap.
///   - z12 and above: `scale == 1` — the full resolved gap.
///
/// A camera resting exactly on a boundary would otherwise rebuild every near
/// part on every frame its zoom control's rounding jitters across it, so each
/// boundary carries `hysteresis` (0.25 zoom levels): a bucket only advances
/// past a boundary once zoom clears it by that much, and only retreats once
/// zoom falls short of its OWN boundary by that much. From bucket 1 the map
/// must reach z12.25 to reach bucket 2, and must fall back under z11.75 to
/// return to bucket 1.
///
/// Must equal `app/public/railmap-style.js`'s `LANE_LOD_BUCKETS` /
/// `LANE_LOD_HYSTERESIS` / `laneScaleForZoom` — `LaneLODTests` asserts the two
/// agree over a table generated from the JavaScript function.
public enum LaneLOD {
    /// The zoom at which each bucket after the first takes over: bucket 1
    /// (half gap) begins at z9, bucket 2 (full gap) begins at z12. Bucket 0
    /// (no offset) has no lower boundary of its own.
    public static let boundaries: [Double] = [9, 12]

    /// The band, in zoom levels, a bucket must clear past its neighbour's
    /// boundary before the resolved bucket moves again.
    public static let hysteresis: Double = 0.25

    /// The lane-gap multiplier for each bucket, indexed by bucket number.
    public static let scales: [Double] = [0, 0.5, 1]

    /// Resolves the lane-offset LOD bucket and its gap-scale multiplier for
    /// `zoom`, given the bucket the stroke was last built at
    /// (`previousBucket`, or `nil` on the first build).
    ///
    /// Without a previous bucket the plain boundaries apply. With one, the
    /// bucket only moves up once zoom clears the NEXT bucket's own boundary
    /// by `hysteresis`, and only moves down once zoom falls short of the
    /// CURRENT bucket's own boundary by `hysteresis` — checked repeatedly, so
    /// a zoom change spanning more than one boundary still lands on the
    /// correct bucket rather than stopping one hop short.
    public static func resolve(zoom: Double, previousBucket: Int?) -> (bucket: Int, scale: Double) {
        let lastIndex = boundaries.count // == scales.count - 1

        func plainIndex() -> Int {
            for i in 0..<boundaries.count {
                if zoom < boundaries[i] { return i }
            }
            return lastIndex
        }

        guard let previousBucket, scales.indices.contains(previousBucket) else {
            let index = plainIndex()
            return (index, scales[index])
        }

        var index = previousBucket
        // Move up only once zoom clears the NEXT bucket's own boundary.
        while index < lastIndex, zoom >= boundaries[index] + hysteresis {
            index += 1
        }
        // Move down only once zoom falls short of THIS bucket's own boundary.
        while index > 0, zoom < boundaries[index - 1] - hysteresis {
            index -= 1
        }
        return (index, scales[index])
    }
}
