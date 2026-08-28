import SwiftUI

/// 已乘坐行程, drawn the way the app icon draws it.
///
/// The rail's routes toggle used `point.topleft.down.to.point.bottomright
/// .curvepath`, which is a smooth curve — and the app's own icon is a
/// polyline with two hard, filleted bends. Both stand for the same thing, and
/// a reader sees them within seconds of each other: the icon on the Home
/// Screen, this control the moment the map opens. So this is the icon's
/// geometry, read out of `ios/tools/gen-route-svg.py`, and the two can only
/// drift if someone edits one file and not the other.
///
/// Three things the icon does are deliberately NOT done here:
///
///   - **The stations are solid discs when the layer is on.** The icon
///     punches its station centres out so the tile's own gradient shows
///     through them. A 21-point glyph has no background of its own to show,
///     and at that size the hole closes up into a smudge. The hole is the OFF
///     state instead — which is the fill-is-the-state rule the rest of the
///     rail already follows (see `tram` / `tram.fill` in `MapControlBar`),
///     and it means the off state is the icon's mark exactly.
///   - **The line is a stroked centreline, not an outline.** The icon has to
///     emit an offset outline because its glass pass renders the sharp inner
///     miter of a stroked corner as a spike with a specular sliver down it.
///     Nothing here is glassed, so stroking the same filleted centreline the
///     script offsets gives the same shape for a tenth of the code.
///   - **The weights are the control's, not the icon's.** The icon's line is
///     96 units wide because it has a 1024-unit tile to fill; scaled to 21
///     points it would be a 2.8-point stroke sitting next to 2-point SF
///     Symbols in the same capsule, and the rail would read as one bold glyph
///     among three. `RouteMark` carries both numbers, so what changed from
///     the icon is on the page rather than in someone's head.
struct RouteGlyph: View {
    /// Stations solid rather than ringed — the layer is on.
    var isFilled: Bool
    /// The square the mark is fitted into. 21 rather than the 20 the SF
    /// Symbols beside it are set at: those 20 points are a font size, and the
    /// glyph inside it is smaller than its em.
    var size: CGFloat = 21

    var body: some View {
        ZStack {
            RouteMark.Line()
            RouteMark.Stations(hole: isFilled ? 0 : RouteMark.stationHole)
                // The ring is a hole in the disc, not a stroke around it, so
                // that filling it in is one number moving to zero and the
                // two states are the same shape throughout the animation.
                .fill(style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
    }
}

/// The mark's geometry, in the icon's 1024-unit space.
///
/// Kept in icon units rather than points so it can be read straight against
/// `gen-route-svg.py`: the numbers that are shared with the icon are
/// identical there, and the numbers that are not say so.
enum RouteMark {

    /// Two stations, two bends. Verbatim from the script.
    static let points = [
        CGPoint(x: 247, y: 781), CGPoint(x: 382, y: 547),
        CGPoint(x: 643, y: 477), CGPoint(x: 778, y: 243),
    ]
    /// Centreline bend radius; must exceed half the line width. Verbatim.
    static let fillet: CGFloat = 100

    /// The line, and the station it ends inside. All four are the control's
    /// numbers rather than the icon's (96 / 95 / 49 / 60 there) — see the
    /// third note on `RouteGlyph`. The disc is wider relative to the line
    /// than the icon draws it, because at this size a station has to survive
    /// being 6 points across; the hole keeps the icon's own proportion,
    /// a little over half the disc, so the ring at rest reads as the icon's
    /// ring rather than as a dot with a pinprick in it.
    static let lineWidth: CGFloat = 72
    static let stationRadius: CGFloat = 110
    static let stationHole: CGFloat = 56
    /// Where the line stops short of a station centre. It has to clear the
    /// hole, or the line shows through it, and stay inside the disc, or its
    /// flat end pokes out — the same two bounds the script asserts.
    static let trim: CGFloat = 74

    /// What the mark occupies, discs included.
    static let bounds = CGRect(
        x: points.map(\.x).min()! - stationRadius,
        y: points.map(\.y).min()! - stationRadius,
        width: points.map(\.x).max()! - points.map(\.x).min()! + 2 * stationRadius,
        height: points.map(\.y).max()! - points.map(\.y).min()! + 2 * stationRadius)

    /// Icon units to a view's coordinates, fitted and centred.
    static func fit(in rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        return CGAffineTransform(
            translationX: rect.midX - bounds.width * scale / 2,
            y: rect.midY - bounds.height * scale / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)
    }

    /// The route: three segments, two filleted bends, both ends pulled back
    /// into their station.
    struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            RouteMark.stroke.applying(RouteMark.fit(in: rect))
        }
    }

    /// The two stations. `hole` is the radius of the centre left empty — the
    /// icon's ring at rest, zero when the layer is on — and is what animates
    /// between the two states.
    struct Stations: Shape {
        var hole: CGFloat

        var animatableData: CGFloat {
            get { hole }
            set { hole = newValue }
        }

        func path(in rect: CGRect) -> Path {
            var path = Path()
            for centre in [RouteMark.points.first!, RouteMark.points.last!] {
                path.addEllipse(in: disc(centre, RouteMark.stationRadius))
                if hole > 0 { path.addEllipse(in: disc(centre, hole)) }
            }
            return path.applying(RouteMark.fit(in: rect))
        }

        private func disc(_ centre: CGPoint, _ radius: CGFloat) -> CGRect {
            CGRect(x: centre.x - radius, y: centre.y - radius,
                   width: radius * 2, height: radius * 2)
        }
    }

    /// The line as an area rather than a stroke, so it fills like the discs
    /// do and needs no width of its own once it has been scaled.
    private static let stroke: Path = centreline.strokedPath(
        StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round))

    private static var centreline: Path {
        var ends = points
        ends[0] = pull(ends[0], toward: ends[1])
        ends[ends.count - 1] = pull(ends[ends.count - 1], toward: ends[ends.count - 2])

        var path = Path()
        path.move(to: ends[0])
        // `addArc(tangent1End:tangent2End:)` draws the run up to each corner
        // and then rounds it, which is the fillet the script computes an
        // offset outline for.
        for corner in 1..<(ends.count - 1) {
            path.addArc(tangent1End: ends[corner], tangent2End: ends[corner + 1],
                        radius: fillet)
        }
        path.addLine(to: ends[ends.count - 1])
        return path
    }

    private static func pull(_ end: CGPoint, toward next: CGPoint) -> CGPoint {
        let run = CGPoint(x: next.x - end.x, y: next.y - end.y)
        let length = (run.x * run.x + run.y * run.y).squareRoot()
        return CGPoint(x: end.x + run.x / length * trim,
                       y: end.y + run.y / length * trim)
    }
}
