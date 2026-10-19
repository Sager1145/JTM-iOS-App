import SwiftUI

/// 地紋 — the security print a ticket's stock already carries before a single
/// figure is printed onto it.
///
/// A Japanese 乗車券 is not issued on blank paper. The stock reaches the
/// machine carrying a 字模様: one continuous fine wave, the issuer's
/// identifying letters set small enough to read as texture rather than as
/// words, and guilloche rings whose only job is to moiré when someone
/// photocopies the ticket. 《旅客営業規則》第186条 is the practice this
/// imitates.
///
/// §6.1 hands Statistics, replay covers and share images to the **Memory**
/// personality — "ticket-and-map metaphors / editorial / souvenir-like" — and
/// until now the passport's data page stood in for the stock with a 120-point
/// `train.side.front.car` at a tenth of white. That was a placeholder saying
/// "decorative texture belongs here". This is the texture.
///
/// ## Three layers, in the order a press lays them down
///
///   - **波線** — a 34-point sine at 0.7 point, repeated every 4.6 points. It
///     is the layer that makes the stock look tinted from arm's length: the
///     paper underneath is not dyed at all, the density of the line is what
///     the eye reads as colour.
///   - **字紋** — 「JRM」 in a brick course, half a step offset per row so no
///     vertical or horizontal channel forms through the field.
///   - **単位図形** — a 120-point checker alternating the app icon's own route
///     symbol, ringed, with a bare set of concentric rings. Both rings are
///     12.5 points, which is what keeps the checker reading as one lattice
///     rather than as two patterns sharing a page.
///
/// All three share one lattice turned 15° off the horizontal. That rotation is
/// the reason this is drawn rather than shipped as a tiled PNG: a raster tile
/// has to be pre-rotated, and a pre-rotated tile no longer repeats seamlessly
/// against a rectangle's edges.
///
/// ## Scale
///
/// The design's own note is 「アプリ内では 1:1 で敷き、拡大は避ける」 — lay it
/// at 1:1, never enlarge it. Enlarged, lines drawn to defeat a photocopier
/// stop being security print and start being wallpaper. So every measurement
/// below is a literal point value and nothing here is scaled to the card, to
/// Dynamic Type, or to anything else.
///
/// Colours live in `TicketPalette`, not here — this file is geometry, that one
/// is the hues the geometry is inked in, which is the same split
/// `PassportCardStyle` keeps.
struct TicketJimon: View {

    /// Which stock is being printed.
    ///
    /// A stock is a paper AND an ink together: the design draws 「JRM」 in the
    /// brand blue when the face is white, and in a lightened blue when the
    /// face is not. Picking one of these is therefore picking both, and
    /// `PassportCardStyle` picks by the appearance — which is the only axis
    /// left once the print goes on one card and no other.
    enum Stock {
        /// 私鉄共通 + RM — 「JRM」 in the brand blue, on white ticket paper.
        case jrm
        /// 暗色 A・ブランド青 — the same print lightened, for a face that is
        /// not white paper: a screen, or the back of a magnetic ticket.
        case darkA

        var onDarkStock: Bool { self == .darkA }

        /// How hard the letters are pressed. The dark stock takes them
        /// stronger because a light ink loses more to its ground than a dark
        /// ink does to white.
        var letterOpacity: Double { self == .darkA ? 0.47 : 0.34 }
    }

    @Environment(\.colorSchemeContrast) private var contrast
    let stock: Stock

    var body: some View {
        Canvas { context, size in
            // One lattice for all three layers, turned once. Rotating the
            // context rather than each layer is what keeps them registered to
            // each other — the checker's rings sit on the wave's crests
            // because they were turned by the same matrix.
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .degrees(Self.slant))

            // The un-turned square that still covers the card once it is
            // turned. Half of (width + height) is never smaller than the
            // rectangle's own circumradius, so this cannot leave a bare
            // corner, and Canvas clips whatever falls outside the card.
            let reach = (size.width + size.height) / 2
            let field = CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)

            let ink = TicketPalette.jimonInk(onDarkStock: stock.onDarkStock)

            context.stroke(
                Self.waves(over: field),
                with: .color(ink.opacity(0.5 * damping)),
                style: StrokeStyle(lineWidth: Self.hairline))

            press(letters: ink, into: &context, over: field)

            context.stroke(
                Self.motifs(over: field),
                with: .color(ink.opacity(0.38 * damping)),
                style: StrokeStyle(lineWidth: Self.hairline, lineCap: .round))
        }
        // Security print is not information, and it is the one thing on these
        // cards a reader gains nothing from being told about.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// §6.5 asks a surface to gain an EDGE under Increase Contrast rather than
    /// more colour, and the passport card obeys that by stroking a keyline.
    ///
    /// This layer moves the other way, which is the same instruction read
    /// correctly rather than the opposite of it: everything else on the card
    /// is asking to stand further out of its ground, and the 地紋 IS the
    /// ground. Printing it harder under Increase Contrast would be the only
    /// change on the screen that makes the figures harder to read.
    private var damping: Double { contrast == .increased ? 0.55 : 1 }

    // MARK: - 波線

    /// The stroke every layer is drawn at — 0.06 mm on a press, which is the
    /// finest line a ticket printer holds.
    private static let hairline: CGFloat = 0.7
    /// 15°, and the reason the whole context is rotated once.
    private static let slant: Double = -15

    private static let waveWidth: CGFloat = 34
    private static let waveHeight: CGFloat = 4.6

    /// Every wave row of the field, as ONE path.
    ///
    /// A card this covers takes on the order of two thousand curve segments,
    /// and the difference between one `stroke` of one path and two thousand
    /// strokes of one segment each is the difference between this being free
    /// and this being the reason the statistics screen drops frames.
    private static func waves(over field: CGRect) -> Path {
        var path = Path()
        // The curve's own extremes, from the design: the control points reach
        // 6% and 94% of the row and the ends sit on its middle, so a row never
        // touches the row above it.
        let middle = waveHeight / 2
        let crest = waveHeight * 0.06
        let trough = waveHeight * 0.94
        var top = field.minY
        while top < field.maxY {
            path.move(to: CGPoint(x: field.minX, y: top + middle))
            var x = field.minX
            while x < field.maxX {
                path.addCurve(
                    to: CGPoint(x: x + waveWidth, y: top + middle),
                    control1: CGPoint(x: x + waveWidth * 0.25, y: top + crest),
                    control2: CGPoint(x: x + waveWidth * 0.75, y: top + trough))
                x += waveWidth
            }
            top += waveHeight
        }
        return path
    }

    // MARK: - 字紋

    private static let letters = "JRM"
    private static let letterSize: CGFloat = 8.2
    private static let letterTileWidth: CGFloat = 78.75
    private static let letterTileHeight: CGFloat = 45.5
    /// The two positions in a tile, as the design gives them: a baseline near
    /// the top left, and a second one dropped almost to the foot of the tile
    /// and pushed just past its middle. That offset is what breaks the course.
    private static let letterOrigins = [CGPoint(x: 1.5, y: 18.2), CGPoint(x: 40.95, y: 41.86)]

    private func press(letters ink: Color, into context: inout GraphicsContext, over field: CGRect) {
        // Resolved once and stamped many times. `Text(verbatim:)` because
        // 「JRM」 is an issuer's mark and not a string anyone translates, and a
        // fixed size because §10.1's Dynamic Type contract is about text a
        // reader reads — this is texture that happens to be made of letters.
        let mark = context.resolve(
            Text(verbatim: Self.letters)
                .font(.system(size: Self.letterSize, weight: .bold))
                .foregroundStyle(ink.opacity(stock.letterOpacity * damping)))

        // SVG places type on its baseline and `GraphicsContext` places it by
        // the bounding box, so the baseline is met by dropping four fifths of
        // an em from the top. At 8.2 points under a third of an alpha the
        // fraction of a point this is out by is not a thing that can be seen.
        let toBaseline = Self.letterSize * 0.8

        var top = field.minY
        while top < field.maxY {
            var left = field.minX
            while left < field.maxX {
                for origin in Self.letterOrigins {
                    context.draw(
                        mark,
                        at: CGPoint(x: left + origin.x, y: top + origin.y - toBaseline),
                        anchor: .topLeading)
                }
                left += Self.letterTileWidth
            }
            top += Self.letterTileHeight
        }
    }

    // MARK: - 単位図形

    private static let motifTile: CGFloat = 120
    /// Both marks in the checker are ringed at this radius. Holding the two
    /// radii equal is what makes the alternation read as one lattice.
    private static let ringRadius: CGFloat = 12.5
    private static let innerRings: [CGFloat] = [5.5, 9]

    /// The app icon's route symbol, at the size it was drawn — two stations
    /// and the line that steps between them.
    ///
    /// Nested into the ring at 0.58, where its own 1.21 stroke lands back on
    /// the 0.7 hairline every other line here is drawn at. That is why this is
    /// one path with one stroke width and not a group carrying its own.
    private static let routeMark: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 4.15, y: 18.73))
        path.addLine(to: CGPoint(x: 6.35, y: 14.61))
        path.addQuadCurve(to: CGPoint(x: 8.35, y: 12.97), control: CGPoint(x: 7.01, y: 13.37))
        path.addLine(to: CGPoint(x: 13.77, y: 11.35))
        path.addQuadCurve(to: CGPoint(x: 15.75, y: 9.7), control: CGPoint(x: 15.11, y: 10.95))
        path.addLine(to: CGPoint(x: 18.01, y: 5.3))
        path.addEllipse(in: CGRect(x: 0.65, y: 18.96, width: 4.4, height: 4.4))
        path.addEllipse(in: CGRect(x: 17.06, y: 0.65, width: 4.4, height: 4.4))
        return path
    }()

    /// The whole checker over the field, as one path — same reason as
    /// ``waves(over:)``.
    private static func motifs(over field: CGRect) -> Path {
        var path = Path()
        var top = field.minY
        while top < field.maxY {
            var left = field.minX
            while left < field.maxX {
                // The checker: the route symbol on one diagonal, bare rings on
                // the other.
                route(into: &path, at: CGPoint(x: left + 30, y: top + 30))
                route(into: &path, at: CGPoint(x: left + 90, y: top + 90))
                rosette(into: &path, at: CGPoint(x: left + 90, y: top + 30))
                rosette(into: &path, at: CGPoint(x: left + 30, y: top + 90))
                left += motifTile
            }
            top += motifTile
        }
        return path
    }

    private static func route(into path: inout Path, at centre: CGPoint) {
        ring(into: &path, at: centre, radius: ringRadius)
        // Scale first, then translate — the order SVG's `translate(…) scale(…)`
        // applies, and `scaledBy` on a translation is exactly that composition.
        path.addPath(
            routeMark,
            transform: CGAffineTransform(
                translationX: centre.x - 6.41, y: centre.y - 6.96
            ).scaledBy(x: 0.58, y: 0.58))
    }

    private static func rosette(into path: inout Path, at centre: CGPoint) {
        for radius in innerRings { ring(into: &path, at: centre, radius: radius) }
        ring(into: &path, at: centre, radius: ringRadius)
    }

    private static func ring(into path: inout Path, at centre: CGPoint, radius: CGFloat) {
        path.addEllipse(
            in: CGRect(
                x: centre.x - radius, y: centre.y - radius,
                width: radius * 2, height: radius * 2))
    }
}
