import MapKit
import RailCore
import RailPresentation
import SwiftUI

/// One station, as the sheet presents it.
///
/// The map used to answer a tap on a station bead with an `MKAnnotationView`
/// callout: a bubble anchored to the bead, carrying the readings and every
/// railway through the complex. It had to stay small enough not to cover the
/// map it pointed at, which put as many as a dozen badge rows into a fixed
/// 280-point box that could neither scroll nor grow with the reader's type
/// size — and the bubble's tail moved the map under it every time one opened
/// near an edge.
///
/// The sheet adds the complete names and station metadata to the railways
/// supplied by `StationDisplay.buildPopupModel`.
///
/// What the card carries is the ANSWER rather than the network row it usually
/// comes out of. The dots a recorded ride puts on its own stops open this same
/// card, and a ride's stop is resolved back to a network platform by code and
/// then by name (`Coordinator.rideStationCard`) — a resolution that can fail,
/// on a store written by hand or against a package that has no such station.
/// Holding a `DrawnStation` would make that failure unpresentable, and a
/// station the reader can see on the map but cannot tap is the fault this card
/// exists to fix.
struct StationCard: Identifiable {
    /// What the sheet is keyed on: the network platform's own id where the tap
    /// resolved to one, and the place itself where it did not.
    var id: String
    /// The station's own surveyed position — where the pin goes when this card
    /// is shared or opened in Maps.
    var coordinate: Coordinate
    /// The header, in the reader's language — see `StationAnnotation`.
    var displayName: String
    /// The package's own spelling, whatever the reader has the app set to.
    ///
    /// It is the name the local map service holds the station under, so it is
    /// the one `StationPlaceStore` searches with — a card opened by a reader
    /// using the app in English must still ask Apple Maps for 東京 rather than
    /// for Tokyo.
    var rawName: String
    /// Which regional package the station came out of.
    var region: Region
    /// One line per enabled reading. `nil` is "no localisation at all", `[]`
    /// is "every reading toggle off", and the two are different answers.
    var readings: [String]?
    /// `PopupModel.nameRoma`, which is the subline the standalone case — no
    /// localisation engine at all — falls back to.
    var nameRoma: String
    /// Every railway through the station complex, as
    /// `StationDisplay.buildPopupModel` deduped and badged them. Empty is a
    /// real answer: a stop that resolved to no platform lists no line rather
    /// than guessing at one.
    var lines: [StationDisplay.PopupRow]
    /// Keep the source identity separate from the presentation id, including
    /// for a journey stop that could not be resolved to a network platform.
    var stationCode: String? = nil
    var validFrom: String? = nil
    var validTo: String? = nil
    var temporalKind: RouteGraph.TemporalKind = .current
}

extension StationCard {
    /// A network platform's card, whose popup model was built once when the
    /// package was decoded.
    init(
        station: RailNetworkStore.DrawnStation, displayName: String,
        readings: [String]?
    ) {
        self.init(
            id: station.id,
            coordinate: station.coordinate,
            displayName: displayName,
            rawName: station.name,
            region: station.region,
            readings: readings,
            nameRoma: station.popup.nameRoma,
            lines: station.popup.lines,
            stationCode: station.stationCode,
            validFrom: station.validFrom,
            validTo: station.validTo,
            temporalKind: station.temporalKind)
    }

    /// Every spelling of this station worth asking Apple Maps about, the
    /// package's own first.
    ///
    /// The readings are included because they are the station's name in
    /// another script rather than a gloss on it: Hong Kong, Macao, Taiwan and
    /// Korea carry official ja/en/zh names in the same table Japan uses for
    /// kana and romaji, and a device answering in any of those languages
    /// answers with one of them. `nil` readings — the standalone build with no
    /// localisation engine — contribute nothing rather than an empty string.
    var searchNames: [String] {
        [rawName, displayName, nameRoma] + (readings ?? [])
    }
}

struct StationCardView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var card: StationCard
    var network: RailNetworkStore
    var controller: RailMapController
    var onLinePreview: (RailwayLinePreview?) -> Void = { _ in }

    /// The Apple Maps place this station is, once `StationPlaceStore` has
    /// found it. `nil` while the search is in flight and `nil` for good when
    /// the service has no such station — the two are deliberately the same
    /// state here, because the answer to both is the same link.
    @State private var place: StationPlaceStore.Place?
    @State private var detailDetent: PresentationDetent = .medium
    @State private var lineIsShown = false
    @State private var sheetHeight: CGFloat = 0
    @State private var sheetContentHeight: CGFloat = 0
    @State private var pendingLineFocus: MKMapRect?

    /// Recomputed as readings tables arrive. Detail content is independent
    /// of the switches that choose the map's annotation sublines.
    private var names: [Localization.StationNameField] {
        localization.stationNameFields(
            card.rawName, code: card.id, alternateCode: card.stationCode, region: card.region)
    }

    /// The link this card sends.
    ///
    /// The station's own Apple Maps place where one was found — a link that
    /// arrives at the other end as 東京駅, with its exits, its platforms and
    /// its departures — and the captioned pin where none was. The fallback is
    /// what this card sent for every station before places were resolved at
    /// all, so a service that cannot answer costs the reader nothing.
    private var appleMapsURL: URL {
        place?.url ?? StationPlaceLink.pinURL(
            name: card.displayName,
            latitude: card.coordinate.lat, longitude: card.coordinate.lon)
    }

    /// Hand the reader over to Apple Maps.
    ///
    /// The resolved map item rather than its URL, because opening the ITEM is
    /// the one path that cannot be wrong: Maps is handed the place it already
    /// agreed this station is, on the same device and the same map service,
    /// with no URL to parse and no identifier to re-resolve.
    private func openInMaps() {
        if let item = place?.item {
            _ = item.openInMaps()
        } else {
            openURL(appleMapsURL)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.displayName)
                            .font(.title2.weight(.semibold))
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    // The other half of the hand-off the share button starts:
                    // the same station, opened here instead of sent. Apple Maps
                    // knows what is around a station — the exits, the streets,
                    // the walk to it — and this map deliberately does not.
                    Button(action: openInMaps) {
                        Label(
                            localization.text("ios.openInMaps", fallback: "Open in Maps"),
                            systemImage: "map")
                    }
                    .accessibilityIdentifier("stationOpenInMaps")
                }

                Section {
                    detailRow("original", value: card.rawName)
                    ForEach(names) { field in
                        detailRow("name.\(field.kind.rawValue)", value: field.text)
                    }
                    if !card.nameRoma.isEmpty, card.nameRoma != card.rawName,
                        !names.contains(where: { $0.text == card.nameRoma }) {
                        detailRow("alternateName", value: card.nameRoma)
                    }
                } header: {
                    Text(localization.text("ios.station.names"))
                }

                if !card.lines.isEmpty {
                    Section {
                        ForEach(card.lines, id: \.lineID) { row in
                            NavigationLink {
                                RailwayLineCardView(
                                    row: row, region: card.region,
                                    network: network,
                                    onPreview: { preview in
                                        lineIsShown = preview != nil
                                        onLinePreview(preview)
                                        if preview == nil {
                                            detailDetent = .medium
                                            pendingLineFocus = nil
                                            controller.journeyMenuBottomObstruction = nil
                                        }
                                    },
                                    onLocate: requestLineFocus)
                            } label: {
                                StationCardLineRow(row: row)
                            }
                            .accessibilityIdentifier("stationLine.\(row.lineID)")
                        }
                    } header: {
                        // The catalog's own word for this (路線 / Line). The
                        // web popup heads the rows with nothing at all — it
                        // has the name directly above them and no section
                        // chrome between — but a grouped list needs a header,
                        // and inventing a string when the catalog already
                        // carries the word would be a fifth translation to
                        // keep true.
                        Text(localization.countryText("popup.line", fallback: "Line"))
                    }
                }

                Section {
                    detailRow(
                        "region",
                        value: localization.text(
                            card.region.localizationKey, fallback: card.region.fallbackName))
                    if let code = card.stationCode, !code.isEmpty {
                        detailRow("code", value: code)
                    }
                    detailRow(
                        "latitude",
                        value: String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"),
                                      card.coordinate.lat))
                    detailRow(
                        "longitude",
                        value: String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"),
                                      card.coordinate.lon))
                    if card.temporalKind != .current {
                        detailRow(
                            "recordType",
                            value: localization.text("ios.station.\(card.temporalKind.rawValue)"))
                    }
                    if let date = card.validFrom, !date.isEmpty {
                        detailRow("validFrom", value: date)
                    }
                    if let date = card.validTo, !date.isEmpty {
                        detailRow("validTo", value: date)
                    }
                } header: {
                    Text(localization.text("ios.station.info"))
                }
            }
            // Deliberately no title: the card's own header carries the
            // station's name at reading size, and a navigation bar repeating
            // it two lines above would print the same word twice. The bar is
            // still there for the close button, which is where a sheet's
            // dismissal belongs.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(
                        item: appleMapsURL,
                        subject: Text(card.displayName),
                        message: Text(card.displayName)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(localization.text("ios.share", fallback: "Share"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton(
                        accessibilityLabel: Text(
                            localization.text("ios.close", fallback: "Close")),
                        action: { dismiss() })
                    .accessibilityIdentifier("stationCardClose")
                }
            }
        }
        // Keyed on the station rather than run once, because one sheet is
        // reused for the next station the reader taps: the card is a value the
        // presentation swaps, and a `task` with no id would hold the first
        // station's place under every card after it.
        .task(id: card.id) {
            place = await StationPlaceStore.shared.place(
                for: card,
                aliases: names.map(\.text))
        }
        #if !targetEnvironment(macCatalyst)
        .presentationDetents(
            lineIsShown && !dynamicTypeSize.isAccessibilitySize
                ? [.height(WorkspaceMenuMetrics.journeyCompactHeight), .medium, .large]
                : [.medium, .large], selection: $detailDetent)
        #endif
        .onGeometryChange(for: SheetMeasurements.self) { proxy in
            SheetMeasurements(height: proxy.size.height, bottomInset: proxy.safeAreaInsets.bottom)
        } action: { measurements in
            sheetContentHeight = measurements.height
            sheetHeight = measurements.height + measurements.bottomInset
            if lineIsShown { controller.journeyMenuBottomObstruction = sheetHeight }
            focusLineIfReady()
        }
        .onDisappear { controller.journeyMenuBottomObstruction = nil }
        // §9.5.6's no-Pull-Bar rule is the app's, not the resident sheet's —
        // this card was the one bottom surface still drawing a grabber. As
        // with the resident sheet, hiding it is only affordable next to
        // `.resizes`: without that, a sheet with no grabber and a scrolling
        // list inside it cannot be dragged between its stops at all.
        .presentationDragIndicator(.hidden)
        .presentationContentInteraction(.resizes)
    }

    private struct SheetMeasurements: Equatable {
        var height: CGFloat
        var bottomInset: CGFloat
    }

    private func requestLineFocus(_ rect: MKMapRect) {
        pendingLineFocus = rect
        #if !targetEnvironment(macCatalyst)
        withAnimation(RailMotion.spring) {
            detailDetent = dynamicTypeSize.isAccessibilitySize ? .large
                : .height(WorkspaceMenuMetrics.journeyCompactHeight)
        }
        #endif
        focusLineIfReady()
    }

    private func focusLineIfReady() {
        guard let rect = pendingLineFocus, sheetHeight > 0 else { return }
        #if !targetEnvironment(macCatalyst)
        guard dynamicTypeSize.isAccessibilitySize
            || sheetContentHeight <= WorkspaceMenuMetrics.journeyCompactHeight + 1 else { return }
        #endif
        pendingLineFocus = nil
        controller.journeyMenuBottomObstruction = sheetHeight
        controller.fit(rect)
    }

    private func detailRow(_ key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localization.text("ios.station.\(key)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stationDetail.\(key)")
    }
}

/// One railway through this station: its badge, then its name.
///
/// `railmap-popup.js` draws the operator's mark where there is one and a
/// colour swatch where there is not — never both, and never a bare name.
/// `OperatorBranding` decides which, through `StationDisplay.buildPopupModel`.
///
/// The one thing this does NOT port is the badge's BOX. The web rule
/// (`.rp-line-logo`) is 16 points tall with a width derived from the artwork's
/// own aspect ratio and capped at 48, which a browser renders happily and a
/// list renders badly: an interchange lists a dozen railways, and a column of
/// marks that are each a different width starts every row at a different
/// optical weight. Every mark in this app is drawn in ``RouteLogoSquare``
/// instead — the artwork keeps its ratio, the box never varies — which is what
/// lets the names beside them share a left edge.
private struct StationCardLineRow: View {
    var row: StationDisplay.PopupRow

    var body: some View {
        HStack(spacing: 8) {
            badge
            VStack(alignment: .leading, spacing: 4) {
                Text(row.label)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let operatorName = row.operatorName, !operatorName.isEmpty {
                    Text(operatorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !row.company.isEmpty {
                    Text(row.company)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stationLine.\(row.lineID)")
    }

    /// No glyph in the fallback: the line's own name is spelled out directly
    /// beside this square, so a tram symbol on every unbranded row would be a
    /// second thing saying "railway" and nothing saying WHICH. The colour is
    /// what distinguishes two lines the reader can already read.
    private var badge: some View {
        RouteLogoSquare(
            path: row.logo,
            color: Color(hex: row.color) ?? Color(.systemGray),
            systemImage: nil,
            side: 28)
    }
}
