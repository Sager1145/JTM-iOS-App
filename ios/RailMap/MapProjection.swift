import MapKit
import RailCore
import UIKit

/// The arithmetic that turns an `MKMapView`'s camera into the numbers the
/// ported style tables speak.
///
/// Pure functions of a map view's geometry and nothing else — no overlays, no
/// annotations, no state. They lived as `static`s on the map coordinator, which
/// made them unreachable from anything that was not that coordinator: the first
/// thing a map layer split out of it needs is `metresPerPixel`, and a sibling
/// file reaching for `RailMapView.Surface.Coordinator.metresPerPixel` is not a
/// dependency anyone can see. Here they are one name.
enum MapProjection {

    /// Web-Mercator zoom for the map view's current span, in the
    /// Google/Leaflet convention: 256-point tiles, so the world is
    /// `256 × 2^zoom` points wide.
    ///
    /// **This is one level above MapLibre's**, and the comment that used to
    /// stand here — "so the ported LOD thresholds mean the same thing here
    /// as they do in MapLibre" — was wrong. MapLibre's tiles are 512 px, so
    /// the same ground scale reports one level LOWER there:
    ///
    ///     78271.52 × cos35° / 2⁷  = 500.9 m per MapLibre pixel
    ///     156543.03 × cos35° / 2⁸ = 500.9 m per point here
    ///
    /// The web app confirms its own side of that: `app-map-fit.js` computes
    /// its longitude-per-pixel as `360 / (512 × 2^minZoom)`.
    ///
    /// So every threshold ported out of the web app is a MapLibre number
    /// and **must be converted before it is read against this zoom**, or
    /// it fires one level early — one step wider than the web app fires
    /// it. Both places that got this wrong have been fixed and measured:
    /// the station gate (jp drew 3,963 dots at a city view where the web
    /// app draws 348) and `NetworkLOD.minZoom` (652 lines at a national
    /// view against 431). Weights and the ride label tiers convert too.
    ///
    /// The conversion is `RailStyle.zoom(fromMapLibre:)` and its inverse.
    /// Anything new that compares a ported number against this value
    /// without one of them is a bug of the same shape.
    @MainActor
    static func zoomLevel(of mapView: MKMapView) -> Double {
        let width = max(mapView.bounds.width, 1)
        let longitudeDelta = max(mapView.region.span.longitudeDelta, 1e-9)
        return log2(360 * (width / 256) / longitudeDelta)
    }

    /// The widest mark ``RailStyle/scale(atZoom:)`` is ever multiplied into, in
    /// points at full weight.
    ///
    /// A bound rather than a measurement, and deliberately generous: it only
    /// decides how finely the shared factor is rounded, and being too large
    /// costs a redraw nobody needed while being too small costs a visible step.
    /// A station bead is 6 pt, a ride stroke with the reader's 線路粗細 at its
    /// widest and the focus boost on top is under 10, and a playback head is a
    /// multiple of the bead's radius.
    private static let widestScaledMark: CGFloat = 12

    /// The shared factor, rounded to the finest step the screen can actually
    /// show on ``widestScaledMark``.
    @MainActor
    static func quantised(_ scale: CGFloat, on mapView: MKMapView) -> CGFloat {
        let pixel = 1 / max(mapView.traitCollection.displayScale, 1)
        let step = pixel / widestScaledMark
        return (scale / step).rounded() * step
    }

    static func metresPerPixel(zoom: Double, latitude: Double) -> Double {
        156_543.03392 * cos(latitude * .pi / 180) / pow(2, zoom)
    }

    /// The box that holds every stroke of these lines, with the margin the
    /// framing convention wants.
    static func region(covering lines: [RailNetworkStore.DrawnLine]) -> MKCoordinateRegion? {
        var minLat = Double.infinity, maxLat = -Double.infinity
        var minLon = Double.infinity, maxLon = -Double.infinity
        for line in lines {
            for interval in line.intervals {
                for point in interval {
                    minLat = min(minLat, point.lat)
                    maxLat = max(maxLat, point.lat)
                    minLon = min(minLon, point.lon)
                    maxLon = max(maxLon, point.lon)
                }
            }
        }
        guard minLat <= maxLat, minLon <= maxLon else { return nil }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.25, 0.01),
                longitudeDelta: max((maxLon - minLon) * 1.25, 0.01))
        )
    }

    /// The box that holds these strokes — ``RailMapController/region(covering:)``.
    ///
    /// The controller owns it because the workspace frames strokes as well now
    /// (the journeys the opening view is for), and two copies of a bounding box
    /// with a margin in it is two framings waiting to disagree by a factor
    /// nobody meant to change.
    static func region(covering strokes: [[Coordinate]]) -> MKCoordinateRegion? {
        RailMapController.region(covering: strokes)
    }
}
