import MapKit
import RailPresentation

/// Which drawn network lines lie under a tap, over the line builds the map
/// already retained for drawing. No geometry is copied: the polylines are the
/// ones MapKit draws, rejected by bounding rect first and then measured with
/// the same point-to-segment distance the trip tap uses.
///
/// The reach is `MapTapPolicy.networkLineReach` view points, supplied by the
/// caller as map points; this file does not define it.
enum NetworkLineHitTest {
    /// Canonical line ids within `reach` map points of `tap`, nearest first.
    /// A historical overlay line is not a railway the line card can load, so
    /// it never answers.
    static func lineIDs(at tap: MKMapPoint, reach: Double, in builds: [LineBuild]) -> [String] {
        let point = RideTapResolver.Point(x: tap.x, y: tap.y)
        var nearest: [String: Double] = [:]
        for build in builds where !build.line.id.hasPrefix("hist|") {
            var best = nearest[build.line.lineID] ?? .infinity
            func scan(_ polyline: MKPolyline) {
                let box = polyline.boundingMapRect.insetBy(dx: -reach, dy: -reach)
                guard box.contains(tap), polyline.pointCount >= 2 else { return }
                let points = polyline.points()
                var previous = RideTapResolver.Point(x: points[0].x, y: points[0].y)
                for index in 1..<polyline.pointCount {
                    let next = RideTapResolver.Point(x: points[index].x, y: points[index].y)
                    best = min(best, RideTapResolver.distance(from: point, to: previous, next))
                    previous = next
                }
            }
            build.polylines.forEach(scan)
            for family in build.familyPolylines.values { family.polylines.forEach(scan) }
            if best <= reach { nearest[build.line.lineID] = best }
        }
        return nearest.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }.map(\.key)
    }
}
