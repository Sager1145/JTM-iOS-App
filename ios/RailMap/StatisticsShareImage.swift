import RailCore
import RailPresentation
import SwiftUI
import UIKit

/// §5.3.5's share, for the statistics rather than for the film.
///
/// The passport already had one share entry point and it exported a *video* of
/// a replay. What the reader asked for is the other half: a picture of the
/// numbers, which is the thing somebody actually posts at the end of a year of
/// travelling — and §6.1 has always listed "share images" beside statistics and
/// replay covers as the surfaces the Memory personality is written for.
///
/// ## It is the page, not a poster invented beside it
///
/// The image is drawn from ``StatisticsDashboardContent`` — the same cards, in
/// the same order, with the same figures and the same wording. A second layout
/// that summarised the same numbers would be a second place for them to be
/// rendered wrong, and it would drift the first time a card was added here and
/// not there.
///
/// What the poster drops is only what a picture cannot carry: the two segmented
/// pickers that choose an axis and the disclosure that folds the tail of a
/// ranked list. See ``SwiftUI/EnvironmentValues/passportPoster``.
///
/// ## Nothing leaves the device by itself
///
/// The button renders a PNG into the app's temporary directory and hands the
/// URL to the system share sheet. Where it goes from there is the reader's
/// choice, made in the system's own UI — the same contract
/// `PlaybackVideoExporter` states for the film: a recording, not a broadcast.
enum StatisticsPoster {

    /// One rendered image, and the file it was written to.
    ///
    /// Both, because the two consumers want different things: `ShareLink`
    /// wants a file the system can hand to another app, and the preview above
    /// it wants the bitmap that is already in memory rather than a second
    /// decode of a picture that is thousands of pixels tall.
    struct File: Identifiable, Equatable {
        var url: URL
        var image: UIImage
        var id: String { url.absoluteString }
    }

    /// How wide the page is laid out before it is rasterised.
    ///
    /// A phone's own width, near enough. The cards were designed against it —
    /// `ViewThatFits` decisions, the ranked rows' inline-versus-stacked
    /// layout, the two-column headline — so laying them out at 400 points
    /// gives a picture of the screen the reader is looking at rather than a
    /// wide-format re-flow of it nobody has ever seen.
    private static let pageWidth: CGFloat = 400

    /// Render the statistics page and write it out as a PNG.
    ///
    /// Returns `nil` only if the renderer produced nothing or the file could
    /// not be written; the caller shows no sheet in that case rather than an
    /// empty one.
    @MainActor
    static func render(
        itineraries: ItineraryStore,
        statistics: MileageStatisticsStore,
        region: Region?,
        scope: String,
        title: String,
        localization: AppLocalization,
        journeyPresentation: @escaping (Train) -> JourneyPresentation,
        colorScheme: ColorScheme
    ) -> File? {
        let page = StatisticsPosterPage(
            itineraries: itineraries,
            statistics: statistics,
            region: region,
            scope: scope,
            title: title,
            journeyPresentation: journeyPresentation
        )
        .frame(width: pageWidth)
        .environment(localization)
        .environment(\.colorScheme, colorScheme)
        .environment(\.passportPoster, true)

        let renderer = ImageRenderer(content: page)
        // The page is drawn on paper, not over a map: a transparent PNG of
        // white text would arrive in a chat app as an unreadable rectangle.
        renderer.isOpaque = true
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rail-statistics.png")
        // Down the scales rather than at one of them. The budget below is a
        // guess at what the bitmap will cost; `uiImage` is the answer, and a
        // renderer that declines to allocate must not leave the reader with a
        // button that did nothing. Every step is a smaller picture of the same
        // page, so the fallback is a worse image and never a wrong one.
        for scale in scales(for: renderer) {
            renderer.scale = scale
            guard let image = renderer.uiImage, let data = image.pngData() else { continue }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                return nil
            }
            return File(url: url, image: image)
        }
        return nil
    }

    /// The tallest bitmap the renderer will actually hand back, in pixels.
    ///
    /// Measured rather than assumed. A passport with a year of travel in it
    /// lays out around 4,700 points tall; asked for 2× — a 9,462-pixel image —
    /// `ImageRenderer.uiImage` returns `nil` and the reader gets a button that
    /// did nothing. 8,000 sits just under the 8,192-pixel edge that rasteriser
    /// stops at, with room for the page to grow by a journey between the
    /// measurement and the draw.
    private static let heightBudget: CGFloat = 8000

    /// The scales to try, best first.
    ///
    /// **Not an integer.** Stepping 3 → 2 → 1 would put a 4,700-point passport
    /// on 1× — a 400-pixel-wide picture of a phone screen, which is the width
    /// of the LAYOUT and half the width of anything anybody has looked at
    /// since 2010. The rasterisation scale is a `CGFloat`, so the page is
    /// drawn at exactly the scale its own height affords: about 1.7× here,
    /// which is a 676 × 8,000 image, and the full 3× for a shorter passport
    /// that can carry it.
    ///
    /// The height is measured first — the closure below lays the page out and
    /// simply does not draw it. The two smaller steps after the first are
    /// there because the budget is an estimate of what the rasteriser will
    /// accept and `uiImage` is the answer; each is a softer picture of the
    /// same page, never a different one.
    @MainActor
    private static func scales(for renderer: ImageRenderer<some View>) -> [CGFloat] {
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        guard height > 0 else { return [3, 2, 1] }
        let best = min(3, heightBudget / height)
        return [best, best * 0.75, best * 0.5]
    }
}

/// The page the image is a picture of: the statistics, with one line above
/// them saying what they are scoped to.
///
/// The scope line is the whole reason this wrapper exists. On screen the region
/// and the date are the two round buttons in the panel header, and they are
/// still on screen while the reader reads the numbers. An image travels without
/// them — so a passport that says 78 % coverage has to say 78 % **of what**, or
/// it is a figure with no denominator being posted to people who cannot ask.
private struct StatisticsPosterPage: View {
    var itineraries: ItineraryStore
    var statistics: MileageStatisticsStore
    var region: Region?
    var scope: String
    var title: String
    /// The picture draws the same journey rows the screen does, so it needs
    /// the same resolved surfaces — see ``StatisticsDashboardContent``. What
    /// it does NOT get is a way to open one: `passportPoster` makes those
    /// blocks inert, because a control in a picture is furniture.
    var journeyPresentation: (Train) -> JourneyPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            StatisticsDashboardContent(
                itineraries: itineraries,
                statistics: statistics,
                // A picture cannot be re-scoped, so the binding it is handed
                // is one that refuses the write rather than one that would
                // silently move the live screen behind it.
                region: .constant(region),
                journeyPresentation: journeyPresentation,
                openJourney: { _ in })
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }

    /// The title row, and the app's mark in the space to its right.
    ///
    /// The mark used to be a banner along the foot. It reads better up here
    /// and it costs nothing: this row is one short line of type over a page
    /// four thousand points long, so its right half was empty on every poster
    /// this app will ever draw — and a picture's provenance belongs where the
    /// eye starts rather than after a scroll nobody makes.
    ///
    /// `ViewThatFits` rather than a plain `HStack`, because the two halves are
    /// both text at the reader's own size: a long destination name, an
    /// accessibility type size, or an app whose display name is not one word
    /// can want more width than the row has. The mark then goes under the
    /// title instead of being squeezed beside it.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 0) {
                titleBlock
                Spacer(minLength: 16)
                StatisticsPosterMark()
            }
            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                StatisticsPosterMark()
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            PassportEyebrow(scope)
            Text(title)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The mark beside the picture's title: which app drew it.
///
/// An image is the one thing this app makes that is looked at by people who do
/// not have it, so it is the one place a line naming the app is information
/// rather than advertising — somebody who wants their own passport has to be
/// able to find out what to go and get.
///
/// Two facts and no more. The NAME is taken from the bundle rather than from a
/// string table, so it is the name under the icon on the reader's own home
/// screen and the one a stranger would search for; a mark that called the app
/// something not written on it anywhere would be worse than no mark. The ICON
/// is the app's own, read out of `CFBundleIcons` — not a glyph chosen to stand
/// in for it, which would be a second identity to keep in step with the first.
///
/// It is drawn ONLY on the poster: `StatisticsPosterPage` is the only thing
/// that mounts it, and the statistics on screen are already inside the app
/// they would be naming.
private struct StatisticsPosterMark: View {
    @Environment(AppLocalization.self) private var localization

    /// The icon's drawn side. Sized to the two lines beside it rather than to
    /// the 44-point row the rest of the app's controls stand in: this is a
    /// mark, not something to press.
    private static let iconSide: CGFloat = 38

    /// iOS' own superellipse is about 0.2237 of the side, and
    /// `.continuous` is the corner that approximates it — so the icon reads as
    /// the app's icon rather than as a rounded photograph of it.
    private static var iconRadius: CGFloat { iconSide * 0.2237 }

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(localization.statsText("ios.stats.shareTagline"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Its natural width on both axes, and no wrapping. Whether the row
            // has room for this is `ViewThatFits`' decision in
            // ``StatisticsPosterPage/header``, and it can only make it if the
            // mark reports the width it actually wants.
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = appIcon {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSide, height: Self.iconSide)
                .clipShape(
                    RoundedRectangle(cornerRadius: Self.iconRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.iconRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .accessibilityHidden(true)
        }
    }

    /// The name the reader has this app under.
    ///
    /// `CFBundleDisplayName` when the build sets one, `CFBundleName` when it
    /// does not — which is the same order the home screen resolves it in.
    private var appName: String {
        let info = Bundle.main.infoDictionary
        if let display = info?["CFBundleDisplayName"] as? String, !display.isEmpty {
            return display
        }
        return info?["CFBundleName"] as? String ?? "RailMap"
    }

    /// The app's own icon, as a `UIImage`.
    ///
    /// Asked of `CFBundleIcons` rather than hard-coded, because the file's
    /// name is a build product: an Icon Composer `.icon` bundle is flattened
    /// into `AppIcon60x60@2x.png` at the bundle root, and the plist is what
    /// says so. The last entry is the largest. `nil` — a build whose icon
    /// cannot be read — drops the glyph and leaves the two lines, rather than
    /// drawing a placeholder square that is not this app's mark.
    private var appIcon: UIImage? {
        let names =
            (Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
            .flatMap { $0["CFBundlePrimaryIcon"] as? [String: Any] }
            .flatMap { $0["CFBundleIconFiles"] as? [String] } ?? []
        for name in names.reversed() {
            if let image = UIImage(named: name) { return image }
        }
        return UIImage(named: "AppIcon60x60")
    }
}

/// What the reader sees before anything is shared: the picture itself, and the
/// system's own share button under it.
///
/// A preview rather than going straight to the share sheet, for the reason
/// §5.6 gives the video export its options screen — sharing is the irreversible
/// half, and the reader should have seen what they are about to send before
/// they choose where it goes.
struct StatisticsShareView: View {
    @Environment(AppLocalization.self) private var localization

    var file: StatisticsPoster.File
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: file.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: RailStyle.cardCornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: RailStyle.cardCornerRadius, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    }
                    .padding(16)
                    .accessibilityLabel(
                        Text(
                            localization.statsText(
                                "ios.stats.shareImageLabel")))
            }
            .navigationTitle(localization.statsText("ios.stats.shareTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                ShareLink(item: file.url) {
                    Label(
                        localization.text("ios.share", fallback: "Share"),
                        systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .railMinimumTouchTarget()
                .padding(16)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.done", fallback: "Done"), action: onClose)
                        .accessibilityIdentifier("statisticsShareCloseButton")
                }
            }
            // Identified rather than found by label: `ConsoleSweepTests` walks
            // this surface, and the label is the reader's language.
            .accessibilityIdentifier("statisticsShareSheet")
        }
    }
}
