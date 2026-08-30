//
//  LongitudeArc.swift — folding longitudes on a circle instead of a line.
//

import Foundation

/// The narrowest band of longitude that contains a set of boxes.
///
/// **This is not a port**, and it is not geometry the drawn map needs: it
/// decides where a CAMERA opens when the subject is more than one network.
/// It lives one tier down from the app's region catalog for the reason
/// ``RegionClock`` and ``RegionScopeRule`` do — the app target has no test
/// target under it, and "which way round the world is the short way from
/// Vancouver to Wakkanai" is arithmetic that has to be checked rather than
/// reviewed.
///
/// ## Why a circle
///
/// With five Asian packages a plain `min`/`max` over longitudes was exactly
/// right: they run from 113°E to 146°E and nothing wraps. The North American
/// packages made it wrong. They run from 130°W to 63°W, so `min` is −130 and
/// `max` is +146, and the box that describes is 276° wide and centred over
/// Africa. It does contain every network — nothing was ever *missing* from it
/// — the reader was simply shown the Atlantic in the middle of a view of the
/// Pacific rim.
///
/// Taking the smallest arc that covers every box instead centres the view on
/// the Pacific, which is the map somebody with journeys in Tokyo and Chicago
/// is asking for.
public enum LongitudeArc {

    /// One box's western and eastern edges, in degrees. A box whose east edge
    /// is numerically west of its west edge is one that already straddles the
    /// antimeridian, and is read as reaching to its own east edge the long way
    /// round.
    public struct Edges: Sendable, Equatable {
        public let west: Double
        public let east: Double

        public init(west: Double, east: Double) {
            self.west = west
            self.east = east
        }
    }

    /// The band, as the centre and width MapKit wants.
    public struct Band: Sendable, Equatable {
        /// In the range MapKit expects (−180…180). A band that runs across the
        /// antimeridian is centred there, which is exactly the case this
        /// exists for.
        public let center: Double
        /// Degrees of longitude, never more than 360.
        public let span: Double

        public init(center: Double, span: Double) {
            self.center = center
            self.span = span
        }
    }

    /// The narrowest band of longitude containing every one of these boxes.
    ///
    /// Each box is tried as the band's western end and the widest eastward
    /// reach from it is measured; the best of those is the answer. That is the
    /// whole of it — with seven regions there is nothing to be gained from
    /// anything cleverer, and the closed form for "smallest enclosing arc" is
    /// the same loop with the corners filed off.
    ///
    /// No boxes at all answers the whole circle, because a camera has to be
    /// pointed somewhere and "everything" is the only honest answer to
    /// "nothing".
    public static func smallest(_ boxes: [Edges]) -> Band {
        guard !boxes.isEmpty else { return Band(center: 0, span: 360) }
        func normalised(_ degrees: Double) -> Double {
            var value = degrees.truncatingRemainder(dividingBy: 360)
            if value < 0 { value += 360 }
            return value
        }
        var best: (start: Double, span: Double) = (0, 360)
        for candidate in boxes {
            let start = normalised(candidate.west)
            var span = 0.0
            for box in boxes {
                // How far east of `start` each box's own edges lie. A box that
                // begins behind the candidate wraps forward rather than
                // producing a negative reach.
                let boxWest = normalised(box.west - candidate.west)
                let boxEast = normalised(box.east - candidate.west)
                // A box whose east edge wraps to before its west edge is one
                // that already straddles the antimeridian; it reaches to its
                // own east edge the long way round.
                let reach = boxEast >= boxWest ? boxEast : boxEast + 360
                span = max(span, reach)
            }
            if span < best.span { best = (start, span) }
        }
        let span = min(best.span, 360)
        var center = best.start + span / 2
        center = center.truncatingRemainder(dividingBy: 360)
        if center > 180 { center -= 360 }
        if center < -180 { center += 360 }
        return Band(center: center, span: span)
    }
}
