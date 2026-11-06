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

/// Sharing, as one feature (UI reorganization pass 3, share page redesigned).
///
/// Every Share entry opens this. Three decisions — scope (this journey · the
/// journey list · statistics), format (image · video), and for an image its
/// shape and look — over a live preview that IS the card: ``ShareCardView``,
/// the same view the export renders. See docs/maintenance/ui-reorganization.md.
///
/// Phone budget: the card content is plain strings built from values the
/// statistics store already computed; the route map is one `MKMapSnapshotter`
/// image made off the main thread at the preview's own scale; the full-size
/// bitmap exists only between Share and its PNG landing on disk.
struct ShareComposer: View {
    let request: ShareRequest
    @Bindable var itineraries: ItineraryStore
    @Bindable var riddenRoutes: RiddenRouteStore
    let statistics: MileageStatisticsStore
    /// The statistics scope in words (region · period), the card's title.
    let statisticsTitle: String
    let colorScheme: ColorScheme
    /// The Journeys list as currently filtered, and the words for that filter.
    let listTrains: [Train]
    let listTitle: String
    let video: ShareVideoInputs

    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var scope: ShareScope
    @State private var format: ShareFormat
    @State private var aspect: ShareCardAspect = .story
    @State private var look: ColorScheme
    @State private var stopsMode: ShareStopsMode = .key
    @State private var videoSeconds = 0.0
    /// The map at preview scale for the current scope, shape and look.
    @State private var mapImage: UIImage?
    @State private var exporting = false
    @State private var exportFailed = false
    @State private var sharedFile: SharedFile?

    struct SharedFile: Identifiable {
        let url: URL
        let text: String
        var id: URL { url }
    }

    init(
        request: ShareRequest,
        itineraries: ItineraryStore, riddenRoutes: RiddenRouteStore,
        statistics: MileageStatisticsStore, statisticsTitle: String, colorScheme: ColorScheme,
        listTrains: [Train], listTitle: String, video: ShareVideoInputs
    ) {
        self.request = request
        self.itineraries = itineraries
        self.riddenRoutes = riddenRoutes
        self.statistics = statistics
        self.statisticsTitle = statisticsTitle
        self.colorScheme = colorScheme
        self.listTrains = listTrains
        self.listTitle = listTitle
        self.video = video
        _scope = State(initialValue: request.scope)
        _format = State(initialValue: request.scope.offersVideo ? request.format : .image)
        _look = State(initialValue: colorScheme)
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

    private var builder: ShareCardBuilder {
        ShareCardBuilder(
            localization: localization,
            passport: statistics.passport.flatMap { $0.isEmpty ? nil : $0 },
            drawnKm: drawnKm)
    }

    private var content: ShareCardContent? {
        switch scope {
        case .journey: request.journey.map { builder.journey($0, stops: stopsMode) }
        case .list: builder.list(listTrains, title: listTitle)
        case .statistics: builder.statistics(store: statistics, scopeTitle: statisticsTitle)
        }
    }

    /// Route geometry for the card's map; statistics cards carry none.
    private var mapRides: [RiddenRouteStore.DrawnRide] {
        let ids: Set<String>
        switch scope {
        case .journey: ids = Set(request.journey.map { [$0.id] } ?? [])
        case .list: ids = Set(listTrains.map(\.id))
        case .statistics: return []
        }
        // The map's trip cap applies to a shared map too.
        let rides = riddenRoutes.rides.filter { ids.contains($0.id) }
        guard rides.count > MapTripCap.limit else { return rides }
        return MapTripCap.capped(
            rides, id: \.id, selectedID: nil,
            dates: MapTripCap.dates(listTrains))
    }

    private var showsMap: Bool { scope != .statistics }

    /// The drawn route's length per journey, for cards opened before the
    /// statistics have matched a journey's mileage. Only the scope's rides.
    private var drawnKm: [String: Double] { Self.drawnKm(mapRides) }

    /// Sections drawn from guard-rejected track (`.unproven`, ADR 0007
    /// option B) are left out, as Stats leaves them out of every km figure.
    static func drawnKm(_ rides: [RiddenRouteStore.DrawnRide]) -> [String: Double] {
        Dictionary(rides.map { ride in
            let unproven = ride.unprovenSegmentIndices
            return (ride.id, ride.segments.reduce(0) { total, segment in
                guard !unproven.contains(segment.segmentIndex) else { return total }
                return zip(segment.coordinates, segment.coordinates.dropFirst()).reduce(total) {
                    $0 + Self.kilometres($1.0, $1.1)
                }
            })
        }, uniquingKeysWith: { first, _ in first })
    }

    private static func kilometres(_ a: Coordinate, _ b: Coordinate) -> Double {
        let r = 6_371.0, d = Double.pi / 180
        let dLat = (b.lat - a.lat) * d, dLon = (b.lon - a.lon) * d
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.lat * d) * cos(b.lat * d) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    private var footer: String {
        StatisticsFormat.ticketIssued(localization: localization)
    }

    var body: some View {
        NavigationStack {
            Group {
                if format == .video {
                    VideoExportOptionsView(
                        settings: video.settings, sourceRect: video.sourceRect,
                        displayScale: video.displayScale, seconds: videoSeconds
                    ) {
                        let trains = filmedTrains
                        dismiss()
                        video.film(trains)
                    }
                } else {
                    imageComposer
                }
            }
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
        .task(id: mapKey) {
            guard format == .image, showsMap else { mapImage = nil; return }
            // Let a burst of route publishes settle; a newer key cancels this.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let image = await renderMap(scale: displayScale)
            guard !Task.isCancelled else { return }
            mapImage = image
        }
        .sheet(item: $sharedFile) { file in
            ActivitySheet(items: [file.url, file.text])
        }
    }

    private var mapKey: String {
        // Only the rides this card draws, not the store's generation: a bulk
        // load publishes partial routes every ~750 ms, and a key on the whole
        // store re-rendered the snapshot on each of them.
        var hasher = Hasher()
        for ride in mapRides { hasher.combine(ride.id); hasher.combine(ride.geometryDigest) }
        return "\(scope.rawValue)|\(format.rawValue)|\(aspect.rawValue)|\(look == .dark)|\(hasher.finalize())"
    }

    // MARK: image

    private var imageComposer: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let content {
                    preview(content)
                } else {
                    ProgressView(localization.text("ios.stats.calculating"))
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
                options
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if exportFailed {
                    Text(localization.text("ios.journeyShare.failed"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    Task { await export() }
                } label: {
                    Label(localization.text("ios.share.shareImage", fallback: "Share image"),
                          systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(content == nil || exporting)
                .accessibilityIdentifier("shareImageButton")
            }
            .padding(16)
            .background(.bar)
        }
    }

    /// The card itself, scaled to the width. Not an image of it: what the
    /// reader sees is the view the export will render.
    private func preview(_ content: ShareCardContent) -> some View {
        let size = aspect.size
        return Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .frame(maxWidth: 400)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    card(content, map: mapImage)
                        .scaleEffect(proxy.size.width / size.width, anchor: .topLeading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            .animation(.smooth(duration: 0.25), value: aspect)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localization.text("ios.journeyShare.preview"))
            .accessibilityValue(content.spokenText)
            .accessibilityIdentifier("sharePreview")
    }

    private func card(_ content: ShareCardContent, map: UIImage?) -> some View {
        ShareCardView(content: content, aspect: aspect, mapImage: map,
                      footer: footer, showsMap: showsMap)
            .environment(\.colorScheme, look)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 14) {
            optionRow(localization.text("ios.share.shape", fallback: "Shape")) {
                Picker(localization.text("ios.share.shape", fallback: "Shape"), selection: $aspect) {
                    ForEach(ShareCardAspect.allCases) { aspect in
                        Text(localization.text(aspect.localizationKey)).tag(aspect)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("shareAspectPicker")
            }
            optionRow(localization.text("ios.share.look", fallback: "Look")) {
                Picker(localization.text("ios.share.look", fallback: "Look"), selection: $look) {
                    Text(localization.text("ios.share.look.light", fallback: "Light")).tag(ColorScheme.light)
                    Text(localization.text("ios.share.look.dark", fallback: "Dark")).tag(ColorScheme.dark)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("shareLookPicker")
            }
            if scope == .journey {
                optionRow(localization.text("ios.share.stops", fallback: "Stops")) {
                    Picker(localization.text("ios.share.stops", fallback: "Stops"), selection: $stopsMode) {
                        ForEach(ShareStopsMode.allCases) { mode in
                            Text(localization.text(mode.localizationKey)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("shareStopsPicker")
                }
            }
        }
        .frame(maxWidth: 400)
    }

    private func optionRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            control()
        }
    }

    // MARK: export

    private func renderMap(scale: CGFloat) async -> UIImage? {
        let rides = mapRides
        guard !rides.isEmpty else { return nil }
        let width = aspect.size.width - 44
        return await StatisticsMapSnapshot.render(
            rides: rides, fallback: nil, colorScheme: look,
            size: CGSize(width: width * scale, height: aspect.mapHeight * scale),
            minimumSpan: 30_000)
    }

    /// Render once at export scale, write, release. The full-size map and
    /// bitmap live only for the length of this function.
    private func export() async {
        guard let content, !exporting else { return }
        exporting = true
        exportFailed = false
        defer { exporting = false }
        let map = showsMap ? await renderMap(scale: ShareCardAspect.exportScale) : nil
        let renderer = ImageRenderer(content: card(content, map: map ?? mapImage))
        renderer.scale = ShareCardAspect.exportScale
        renderer.isOpaque = true
        guard let image = renderer.uiImage,
              let url = await ShareArtifactWriter.writePNG(image, kind: scope == .statistics ? .statistics : .journey)
        else {
            exportFailed = true
            return
        }
        sharedFile = SharedFile(url: url, text: content.spokenText)
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
