import RailCore
import SwiftUI

/// What a share is about.
enum ShareScope: String, CaseIterable, Identifiable {
    /// One journey: the card's own.
    case journey
    /// The Journeys list exactly as its search and filter show it.
    case list
    /// The statistics composer's cards.
    case statistics

    var id: String { rawValue }
    var localizationKey: String { "ios.share.scope." + rawValue }
    /// A film is a recording of a playback run, so only journeys have one.
    var offersVideo: Bool { self != .statistics }
}

enum ShareFormat: String, CaseIterable, Identifiable {
    case image, video
    var id: String { rawValue }
    var localizationKey: String { "ios.share.format." + rawValue }
}

/// One request to open the composer: where it was opened from decides the
/// scope and format it starts on; the reader can change both inside it.
struct ShareRequest: Identifiable {
    let id = UUID()
    var scope: ShareScope
    var format: ShareFormat = .image
    /// The journey in context, when the composer was opened from one.
    var journey: Train?
}

/// Builds the one share composer. The workspace supplies it, so a journey
/// card anywhere in the hierarchy (resident panel, detail sheet, Duo)
/// presents the same composer over itself — and the card, with its
/// selection, is still there when the composer closes.
struct OpenShareAction {
    let composer: (ShareRequest) -> AnyView
}

extension EnvironmentValues {
    @Entry var openShare: OpenShareAction?
}

/// The video half's inputs: the workspace owns the recorder and the map it
/// films, so it hands over the settings and the numbers the form quotes.
struct ShareVideoInputs {
    let settings: VideoExportSettings
    let sourceRect: CGRect
    let displayScale: CGFloat
    /// The run length for these journeys (``PlaybackController/estimate``).
    let estimateSeconds: ([Train]) -> Double
    /// Dismiss the composer and film these journeys.
    let film: ([Train]) -> Void
}

/// Sharing, as one feature (UI reorganization pass 3).
///
/// Before this there were three share surfaces with three renderers and three
/// file writers: a journey poster sheet on the card, the statistics composer
/// in the Stats header, and a video options sheet in the playback bar. Each
/// context still has exactly one Share entry, and every entry opens this:
///
/// - **scope** — this journey · the filtered journey list · statistics;
/// - **format** — image or video (video only for journeys: a film is a
///   recording of a playback run).
///
/// Journey and list images come from the one poster renderer
/// (``JourneyPoster``), statistics from the card renderer; every file goes
/// through ``ShareArtifactWriter``.
struct ShareComposer: View {
    let request: ShareRequest
    @Bindable var itineraries: ItineraryStore
    @Bindable var riddenRoutes: RiddenRouteStore
    let statistics: MileageStatisticsStore
    let region: Region?
    let area: StatisticsArea?
    let colorScheme: ColorScheme
    /// The Journeys list as currently filtered, and the words for that filter.
    let listTrains: [Train]
    let listTitle: String
    let video: ShareVideoInputs

    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @State private var scope: ShareScope
    @State private var format: ShareFormat
    @State private var videoSeconds = 0.0

    init(
        request: ShareRequest,
        itineraries: ItineraryStore, riddenRoutes: RiddenRouteStore,
        statistics: MileageStatisticsStore,
        region: Region?, area: StatisticsArea?, colorScheme: ColorScheme,
        listTrains: [Train], listTitle: String, video: ShareVideoInputs
    ) {
        self.request = request
        self.itineraries = itineraries
        self.riddenRoutes = riddenRoutes
        self.statistics = statistics
        self.region = region
        self.area = area
        self.colorScheme = colorScheme
        self.listTrains = listTrains
        self.listTitle = listTitle
        self.video = video
        _scope = State(initialValue: request.scope)
        _format = State(initialValue: request.scope.offersVideo ? request.format : .image)
    }

    /// The scopes this opening can offer: the journey only when there is one.
    private var scopes: [ShareScope] {
        ShareScope.allCases.filter { $0 != .journey || request.journey != nil }
    }

    /// The journeys a film of this scope would play: hidden journeys and
    /// single-call records have no run, the same rule as the play button.
    private var filmedTrains: [Train] {
        let trains = scope == .journey ? request.journey.map { [$0] } ?? [] : listTrains
        return trains.filter { scope == .journey || ($0.visible != false && $0.stops.count > 1) }
    }

    var body: some View {
        NavigationStack {
            content
                .safeAreaInset(edge: .top, spacing: 0) { pickers }
                .navigationTitle(localization.text("ios.share.title", fallback: "Share"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(localization.text("ios.cancel", fallback: "Cancel")) { dismiss() }
                            .accessibilityIdentifier("shareCloseButton")
                    }
                }
        }
        .accessibilityIdentifier("shareComposerRoot")
        .onChange(of: scope) { _, scope in
            if !scope.offersVideo { format = .image }
        }
        .task(id: "\(scope.rawValue)|\(format.rawValue)") {
            guard format == .video else { return }
            videoSeconds = video.estimateSeconds(filmedTrains)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch (scope, format) {
        case (.statistics, _):
            ShareComposerView(
                itineraries: itineraries, riddenRoutes: riddenRoutes, statistics: statistics,
                region: region, area: area, colorScheme: colorScheme)
        case (.journey, .image):
            if let journey = request.journey {
                JourneyShareContent(subject: .journey(journey))
                    .id("journey:\(journey.id)")
            }
        case (.list, .image):
            JourneyShareContent(subject: .list(listTrains, title: listTitle))
                .id("list")
        case (_, .video):
            VideoExportOptionsView(
                settings: video.settings, sourceRect: video.sourceRect,
                displayScale: video.displayScale, seconds: videoSeconds
            ) {
                let trains = filmedTrains
                dismiss()
                video.film(trains)
            }
        }
    }

    private var pickers: some View {
        VStack(spacing: 8) {
            if scopes.count > 1 {
                Picker(localization.text("ios.share.scope"), selection: $scope) {
                    ForEach(scopes) { scope in
                        Text(localization.text(scope.localizationKey)).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("shareScopePicker")
            }
            if scope.offersVideo {
                Picker(localization.text("ios.share.format"), selection: $format) {
                    ForEach(ShareFormat.allCases) { format in
                        Label(localization.text(format.localizationKey),
                              systemImage: format == .image ? "photo" : "video")
                            .tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("shareFormatPicker")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
