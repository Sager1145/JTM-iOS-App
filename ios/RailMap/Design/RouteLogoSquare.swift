import RailCore
import RailPresentation
import SwiftUI

/// A single square contract for every route mark in the app.
///
/// Artwork keeps its original aspect ratio inside the square; it never gets a
/// width derived from that ratio, which is the rule that prevents long
/// operator wordmarks from shifting the column beside them. A route without
/// published artwork still starts at the same square, using its recorded
/// colour and — where the neighbouring text does not already name it — a
/// redundant glyph, so the mark is never colour alone (§6.2).
///
/// The side is a fixed number of points and deliberately not a
/// `@ScaledMetric`. A mark is an identifier rather than reading text: at an
/// accessibility size the row's WORDS have to grow, and a badge that grew with
/// them would take the width they need to grow into.
struct RouteLogoSquare: View {
    /// The mark, where the caller already resolved it — the station card, whose
    /// rows come out of `StationDisplay.buildPopupModel`.
    private var explicitPath: String?
    /// The journey whose mark this is, where the caller did not.
    ///
    /// Held rather than resolved in `init` because the answer depends on the
    /// loaded network, and the network arrives after the first rows are drawn:
    /// Macao's package lands in milliseconds and Japan's 9.5 MB does not.
    /// Resolving in `body` is what lets a row that drew a company mark at
    /// launch redraw with its line's own symbol when the package finishes.
    private var train: Train?
    var color: Color
    /// The glyph drawn over the fallback colour. `nil` leaves the colour
    /// alone, which is right only where the text beside it already spells the
    /// line out — a station card's row, where the swatch distinguishes two
    /// named lines rather than identifying one on its own.
    var systemImage: String? = "tram.fill"
    var side: CGFloat = 52

    /// The loaded packages, which is where a journey's mark comes from.
    ///
    /// Optional for the same reason `DataManagerView` declares it optional: a
    /// preview installs no store, and a badge that cannot be looked up falls
    /// back to the operator rule rather than to nothing.
    @Environment(RailNetworkStore.self) private var network: RailNetworkStore?
    @Environment(ItineraryStore.self) private var itineraries: ItineraryStore?
    @Environment(TraversedLineDetector.self) private var traversedLines: TraversedLineDetector?
    @Environment(\.colorScheme) private var colorScheme

    init(path: String?, color: Color, systemImage: String? = "tram.fill", side: CGFloat = 52) {
        self.explicitPath = path
        self.color = color
        self.systemImage = systemImage
        self.side = side
    }

    /// The mark for a journey — the same one on every surface that shows it.
    init(train: Train, side: CGFloat = 52) {
        self.train = train
        self.color = JourneyBranding.color(of: train)
        self.systemImage = TrainServiceBranding.isLimitedExpress(train)
            ? "train.side.front.car" : "tram.fill"
        self.side = side
    }

    private var path: String? {
        guard let train else { return explicitPath }
        return JourneyBranding.logoPath(
            of: train, in: network?.badges,
            detected: traversedLines?.lines(
                forTrainID: train.id,
                pendingConfirmationIDs: itineraries?.pendingConfirmationIDs ?? []) ?? [])
    }

    /// The proportion the old 52-point tile used (36 of 52), kept as a ratio
    /// so a smaller square reads as the same tile rather than as a different
    /// treatment.
    private var artworkSide: CGFloat { (side * 0.69).rounded() }
    private var corner: CGFloat { Self.cornerRadius(side: side) }

    /// The square the artwork's ink is fitted into.
    ///
    /// A block fills the tile. It paints its own ground out to its own
    /// corners, so insetting it would draw a box inside a box — which is what
    /// made every JR line row read as a small logo lost in a big frame before
    /// `fillsItsBox` existed. A glyph gets the 0.69 the tile was built around.
    ///
    /// One exception, and the artwork is what earns it: JR East draws its
    /// conventional-line route symbols with a WHITE INNER BORDER already
    /// inside the coloured square. Filled to the tile's edge that inner border
    /// becomes the badge and the colour around it reads as a frame the tile
    /// put there rather than as part of the mark. Given a margin it reads as
    /// the badge it is. No other operator's route square is drawn that way —
    /// JR Central's CA and JR West's S are solid colour with the letters
    /// knocked out — so the exception is exactly these files, and the
    /// company's Shinkansen rows are not among them: those resolve to the
    /// pictogram in `line-logos` and never reach this prefix.
    private func inkBox(isBlock: Bool) -> CGFloat {
        guard isBlock else { return artworkSide }
        return isJREastConventionalLine ? (side * 0.84).rounded() : side
    }

    private var isJREastConventionalLine: Bool {
        path?.hasPrefix("/rail/logos/jp-東日本旅客鉄道-") ?? false
    }

    /// One rounded rectangle, at every size a mark is drawn at.
    ///
    /// `min(controlCornerRadius, side * 0.3)` gave the app four different
    /// shapes — 8.4 at the station card's 28 points, 10.8 at the collapsed
    /// hero's 36, 12 at 44 and 52 — because a constant clamped against a
    /// proportion is a proportion only until it clamps. A reader sees three of
    /// those within one tap of each other (list row, hero card, detail header)
    /// and the mark changes shape between them.
    ///
    /// 0.2237 is the ratio iOS's own app-icon superellipse uses, which is what
    /// `.continuous` is drawing anyway; at the list's 52 points it comes to
    /// 11.6 against the 12 that was already there, so the size the app shows
    /// most is unchanged to the eye and the smaller ones come into line with
    /// it. Deliberately not rounded to whole points: the hero card animates
    /// its side between 36 and 46, and a rounded radius would step through the
    /// integers while the square grew smoothly.
    static func cornerRadius(side: CGFloat) -> CGFloat { side * 0.2237 }

    /// The shape itself, for the surfaces that draw the same square without an
    /// image in it — see `RideEditorView`'s colour preview.
    static func shape(side: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius(side: side), style: .continuous)
    }

    /// Derived rather than passed in: `StationDisplay` computes the same
    /// answer from the same function for its popup rows, and a caller that
    /// forwarded its own copy would be a second place for the two to disagree.
    private var needsDarkMatte: Bool { OperatorBranding.logoNeedsDarkMatte(path) }

    /// The gap between a matted mark and the edge of its matte. Zero for the
    /// marks that need no matte, which is all but three of them.
    private var matteInset: CGFloat { needsDarkMatte ? artworkSide * 0.11 : 0 }

    /// Whether the artwork is a block that should fill this square rather
    /// than sit inset on it, and what colour its own edge is — see
    /// ``OperatorBadge/Shape``.
    private var artwork: OperatorBadge.Shape { OperatorBadge.shape(path) }

    /// The ground a glyph sits on.
    ///
    /// Brighter in the dark appearance than `tertiarySystemBackground` was.
    /// That fill is two points of luminance above the row it is drawn on, so
    /// an unbranded mark read as a hole in the card rather than as a tile; and
    /// a good number of the badges that are NOT blocks are dark artwork on
    /// transparency, which needs a ground with some light in it. In the light
    /// appearance the system fill is already right — white artwork is the case
    /// `OperatorBadge.matte` handles, and it handles it in both.
    private var tileFill: Color {
        // SwiftUI can resolve colours on its asynchronous renderer. Read the
        // appearance here instead of handing UIKit a MainActor-isolated closure.
        Color(uiColor: colorScheme == .dark ? .systemGray3 : .tertiarySystemBackground)
    }

    var body: some View {
        ZStack {
            if let image = OperatorBadge.image(path) {
                // Bound once: two of its fields are read below and each read
                // is a cache lookup keyed by the path.
                let mark = artwork
                let box = inkBox(isBlock: mark.fillsItsBox)

                // A mark that fills the tile sits on its own edge colour, so
                // the bar its aspect leaves on the short axis is invisible; a
                // mark that is inset sits on the tile, which is what makes the
                // inset read as a margin rather than as a mistake.
                Self.shape(side: side)
                    .fill(box < side ? tileFill
                        : (mark.edgeColor.map(Color.init(uiColor:)) ?? tileFill))

                InkFittedArtwork(
                    image: image, ink: mark.inkBounds, box: box - 2 * matteInset)
                    // A few operators' current mark is drawn in white for
                    // their own dark header; `OperatorBadge.matte` is the
                    // ground that keeps that artwork legible in both
                    // appearances without repainting it.
                    .padding(matteInset)
                    .background {
                        if needsDarkMatte {
                            RoundedRectangle(cornerRadius: corner * 0.4, style: .continuous)
                                .fill(Color(uiColor: OperatorBadge.matte))
                        }
                    }
            } else if let systemImage {
                Self.shape(side: side)
                    .fill(color)
                Image(systemName: systemImage)
                    .font(.system(size: artworkSide * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                // No artwork and no glyph: the line's own colour is the mark,
                // and it fills the square for the same reason a block does.
                Self.shape(side: side)
                    .fill(color)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Self.shape(side: side))
        .overlay {
            Self.shape(side: side).strokeBorder(Color(.separator), lineWidth: 0.5)
        }
        // The mark is never the only thing saying which route this is — every
        // surface that draws it spells the line, the operator or both beside
        // it — so it is decoration to a screen reader (§6.2 again, from the
        // other side).
        .accessibilityHidden(true)
    }
}

/// Artwork mounted by its INK rather than by its canvas.
///
/// `scaledToFit` fits the file, which is the right answer only when the file
/// is trimmed — and across 515 badges it is usually not. 464 of them have ink
/// touching at least one canvas edge and 70 touch some edges and not others,
/// so fitting the canvas hands a differently-sized, differently-centred mark
/// to every row: 立山黒部貫光 sits low because the top 40 % of its file is
/// empty, the twelve 西武鉄道 badges sit high, the seven 名古屋市 subway badges
/// sit low by 14 %. Fitting the measured ink instead gives every mark the same
/// optical size and the same centre, which is the whole reason the square is
/// a fixed size in the first place.
///
/// Nothing is cropped. The frame is the box the ink was fitted to, so the only
/// thing `clipped()` can remove is the transparent canvas around it — and it
/// has to remove that, or a badge with a wide empty margin would report a size
/// bigger than the tile and push the text beside it.
private struct InkFittedArtwork: View {
    var image: UIImage
    /// Unit rectangle, from ``OperatorBadge/Shape/inkBounds``.
    var ink: CGRect
    /// The side of the square the ink is fitted into.
    var box: CGFloat

    var body: some View {
        let canvas = image.size
        // `max(…, 1)` rather than a guard: a zero would only arise from a
        // degenerate image, and a view is not a place to fail. One point is
        // small enough that such a file draws as a speck rather than as a
        // division by zero.
        let inkWidth = max(ink.width * canvas.width, 1)
        let inkHeight = max(ink.height * canvas.height, 1)
        let scale = box / max(inkWidth, inkHeight)
        let width = canvas.width * scale
        let height = canvas.height * scale
        Image(uiImage: image)
            .resizable()
            .frame(width: width, height: height)
            // `offset` is deliberately outside the frame and inside the next
            // one: it moves what is drawn without moving what was laid out, so
            // the box below still centres on the canvas and this slides the
            // ink's own centre onto that centre.
            .offset(
                x: width * (0.5 - ink.midX),
                y: height * (0.5 - ink.midY))
            .frame(width: box, height: box)
            .clipped()
    }
}
