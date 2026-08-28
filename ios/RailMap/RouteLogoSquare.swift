import RailCore
import SwiftUI

// =========================================================================
//  RouteLogoSquare.swift — the one square every route mark is drawn in, and
//  the branding lookup that decides which mark that is.
//
//  Two surfaces used to answer this question separately. The journey row
//  fitted artwork into a fixed tile; the station card gave each badge a
//  width derived from its own aspect ratio (`min(48, 16 * ratio)`, the web
//  app's `.rp-line-logo` rule). The second is what a browser does well and a
//  list does badly: a column of mixed marks — a round metro roundel, a long
//  operator wordmark, a square JR logo — starts every row at a different
//  optical weight, and the text beside them stops sharing a left edge.
//
//  So the rule is the square, and it is the same square everywhere: the
//  ARTWORK keeps its own aspect ratio inside it, and the BOX never varies.
//  Nothing in a row is positioned from a logo's proportions, which is why a
//  wordmark and a roundel align identically.
//
//  Two things the square did not do, and now does. It is one SHAPE as well as
//  one size — the corner was a constant clamped against a proportion, so a
//  badge was rounded four different ways between the station card's 28 points
//  and the list's 52. And it fits the artwork's INK rather than its canvas:
//  the badge files are padded inconsistently and 70 of them are padded
//  ASYMMETRICALLY, so fitting the file centred the padding and left every
//  mark in a column nudged a different way. Neither ever crops.
// =========================================================================

/// A journey's own mark, colour and route wording, resolved once.
///
/// These four answers used to be private computed properties on the journey
/// row, which was fine while the row was the only surface with a logo in it.
/// It is not: the selected-journey card and the pushed detail screen show the
/// same journey, and a reader who taps a row must not find a different mark
/// (or no mark) on the screen it opens. One lookup, three surfaces.
enum JourneyBranding {

    /// Passenger-facing route hints, in the order they were recorded, without
    /// the repeats a multi-section journey produces.
    static func lineNames(of train: Train) -> [String] {
        uniqueNonEmpty(
            (train.routeSections ?? []).flatMap { $0.lineNames ?? [] }
                + (train.routePolicy?.preferredLineNames ?? []))
    }

    /// The operators a journey names, spelled the way the RECORD spells them.
    ///
    /// Two spellings reach this list and both have to stay: a route section
    /// carries the operator's full legal name (`東日本旅客鉄道`) because that
    /// is what the rail package's line ids are built from, and the itinerary's
    /// own `company` field carries the short one (`JR東日本`). Nothing here
    /// shortens either, because ``logoPath(of:)`` looks a mark up by this
    /// exact string — `lineLogos` is keyed `jp-東日本旅客鉄道-東北新幹線`, so a
    /// list that had already been through `companyLabel` would find nothing.
    ///
    /// What a reader SEES is ``operatorLabels(of:)``.
    static func operatorNames(of train: Train) -> [String] {
        uniqueNonEmpty(
            (train.routeSections ?? []).flatMap { $0.operatorNames ?? [] }
                + (train.routePolicy?.preferredOperatorNames ?? [])
                + [train.company].compactMap { $0 })
    }

    /// The same operators, as a passenger names them: 「JR東日本」, not
    /// 「東日本旅客鉄道 / JR東日本」.
    ///
    /// `OperatorBranding.companyLabel` is the web app's own shortener — the
    /// four regional label tables, then the legal-suffix strip — so this is
    /// not a second opinion about what a railway is called. It also does the
    /// deduplication that matters: the legal name and the brand name are two
    /// strings for one company, and they collapse to one only AFTER both have
    /// been through the table, which is why the unique pass runs here rather
    /// than on the raw list above.
    static func operatorLabels(of train: Train) -> [String] {
        let labelled = uniqueNonEmpty(operatorNames(of: train).map(OperatorBranding.companyLabel))
        // One more collapse, and it is not the table's job. The table maps a
        // LEGAL name to a short one (京浜急行電鉄 → 京急); a record whose own
        // `company` field is already half-short (京急電鉄, 都営地下鉄) is left
        // exactly as written, and the row then prints 「京急 / 京急電鉄」 —
        // one company, twice, which is the thing the shortening was for. So a
        // label that merely extends another label is dropped in favour of the
        // shorter one, which is the 简称 by definition.
        return labelled.filter { label in
            !labelled.contains { other in other != label && label.hasPrefix(other) }
        }
    }

    /// 「東海道本線 · JR東海」 — the line, then who runs it.
    static func routeText(of train: Train) -> String {
        [lineNames(of: train).joined(separator: " / "),
         operatorLabels(of: train).joined(separator: " / ")]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// The mark this journey wears — the loaded network's answer first.
    ///
    /// Route sections carry passenger names rather than internal line ids, so
    /// this used to CONSTRUCT one: `<region>-<operator>-<line>`, which is the
    /// packages' canonical spelling and matches for most railways. It cannot
    /// match for the ones that matter most here. A subway's id is built from
    /// the administrative name (`jp-東京地下鉄-3号線銀座線`) while its `operator`
    /// field and its passenger-facing name are the brand ones (東京メトロ,
    /// 銀座線) — the two disagree on 19 of Japan's 652 railways and all 19 are
    /// subways. So the constructed id missed exactly the lines whose route
    /// symbol is the most recognisable thing about them, and every Tokyo Metro
    /// journey fell through to the one 東京メトロ company badge.
    ///
    /// ``RouteBadgeIndex`` is the loaded package's own answer, keyed by both
    /// spellings of the operator and both of the name. Consulting it is also
    /// what makes this surface agree with the station card, which has always
    /// resolved through the network (`StationDisplay.buildPopupModel`): one
    /// railway, one mark, whichever screen a reader is looking at.
    static func logoPath(of train: Train, in badges: RouteBadgeIndex?) -> String? {
        let region = Region.resolved(train).code
        let lines = lineNames(of: train)
        let operators = operatorNames(of: train)
        if let badges {
            // Line-major: the first recorded line is the journey's primary
            // route, and a through-running record must not be identified by
            // its second section merely because that section's operator was
            // listed first.
            for lineName in lines {
                for operatorName in operators {
                    if let hit = badges.logo(
                        region: region, operatorName: operatorName, lineName: lineName) {
                        return hit
                    }
                }
            }
        }
        let lineName = lines.first
        let operatorName = operators.first
        let lineID: String?
        if let lineName, let operatorName {
            lineID = "\(region)-\(operatorName)-\(lineName)"
        } else {
            lineID = nil
        }
        return OperatorBranding.logoForLine(
            OperatorBranding.Line(lineId: lineID, operator: operatorName))
    }

    /// The journey's recorded colour, which is what a mark falls back to.
    static func color(of train: Train) -> Color {
        if let color = train.style?.color, let resolved = Color(hex: color) {
            return resolved
        }
        return Color(hex: TrainValidation.defaultTrainColor) ?? .accentColor
    }

    private static func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Which mark each railway in a loaded package wears, under every spelling a
/// recorded journey might name it by.
///
/// One dictionary rather than a search, because the answer is asked for once
/// per drawn row and a journeys list scrolls. It is built where the package is
/// decoded (`RailNetworkStore.decode`) and off the main actor, which is also
/// the only place the package's `logo` flag is in scope.
///
/// The keys are deliberately redundant. A railway is named four ways between
/// the package and an itinerary — the id's administrative operator (東京地下鉄)
/// or the brand one (東京メトロ), crossed with the full name (3号線銀座線) or the
/// passenger one (銀座線) — and a record may carry any pairing of them. Storing
/// all four costs about 2,600 entries for all five countries and removes the
/// entire class of "the mark is right on one screen and wrong on the next".
struct RouteBadgeIndex: Sendable {
    private var pathByKey: [String: String] = [:]

    init() {}

    init(region: Region, package: CompactPackage) {
        // Two passes, and the order is the point: a railway with its own
        // published art claims a shared key before one that would only bring
        // its operator's company mark to it. 名城線 is in the package twice
        // (2号線 and 4号線) under one passenger name, and the reader should get
        // the route symbol from whichever of the two carries it.
        add(package: package, region: region, withPackageArt: true)
        add(package: package, region: region, withPackageArt: false)
    }

    private mutating func add(package: CompactPackage, region: Region, withPackageArt: Bool) {
        for line in package.lines where line.hasLogo == withPackageArt {
            let packageLogo = line.hasLogo
                ? "/rail/logos/\(StationDisplay.Network.badgeIDForLine(line.id)).png"
                : nil
            guard let logo = OperatorBranding.logoForLine(
                OperatorBranding.Line(
                    lineId: line.id, operator: line.operator, logo: packageLogo))
            else { continue }
            claim(line.id, logo)
            let operators = [line.operator, Self.operatorComponent(of: line.id)]
                .compactMap { $0 }
            let names = [line.name, line.nameNorm].compactMap { $0 }
            for operatorName in operators where !operatorName.isEmpty {
                for name in names where !name.isEmpty {
                    claim(Self.key(region: region.code, operatorName, name), logo)
                }
            }
        }
    }

    /// First writer wins, so that package order decides a tie rather than
    /// dictionary order. A split part (`-2`) resolves to its parent's art
    /// anyway, so the loser is the same answer in every case seen today.
    private mutating func claim(_ key: String, _ logo: String) {
        if pathByKey[key] == nil { pathByKey[key] = logo }
    }

    mutating func merge(_ other: RouteBadgeIndex) {
        pathByKey.merge(other.pathByKey) { existing, _ in existing }
    }

    func logo(region: String, operatorName: String, lineName: String) -> String? {
        pathByKey[Self.key(region: region, operatorName, lineName)]
    }

    func logo(lineID: String) -> String? { pathByKey[lineID] }

    /// NUL, for the reason `StationDisplay` gives where it builds its own
    /// composite key: it cannot occur in either half, so no name can forge a
    /// key belonging to a different operator.
    private static func key(region: String, _ operatorName: String, _ line: String) -> String {
        "\(region)\u{0000}\(operatorName)\u{0000}\(line)"
    }

    /// `jp-東京地下鉄-3号線銀座線` → `東京地下鉄`. The country prefix is a fixed
    /// two letters and the rest of the id is the name, so one split at each of
    /// the first two hyphens is the whole rule.
    private static func operatorComponent(of lineID: String) -> String? {
        let parts = lineID.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return String(parts[1])
    }
}

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
        self.side = side
    }

    private var path: String? {
        guard let train else { return explicitPath }
        return JourneyBranding.logoPath(of: train, in: network?.badges)
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
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? .systemGray3 : .tertiarySystemBackground
        })
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
