import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// The region picker, a row of the Journey section when more than one
/// region is enabled.
struct EditorRegionRow: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    @Bindable var model: TripDraftModel

    var body: some View {
        Picker(text("region", fallback: "Region"), selection: $model.region) {
            ForEach(Region.enabledOrdered) { region in
                Text(localization.text(region.localizationKey, fallback: region.fallbackName))
                    .tag(region)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("newTripRegion")
    }
}

/// Region, From, the stops along the way, and To. Swap sits beside the two
/// ends instead of on a row of its own; stations near the reader are offered
/// under an empty From.
struct EditorStationsSection: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    @Bindable var model: TripDraftModel

    var body: some View {
        Section {
            if Region.enabledOrdered.count > 1 {
                EditorRegionRow(model: model)
            }
            if model.catalog == nil, !model.loadFailed {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                stationButton(
                    title: text("from", fallback: "From"),
                    station: model.origin,
                    line: model.originLine,
                    source: model.filledBy[.origin],
                    identifier: "newTripOrigin") { model.picking = .origin }
                Button(action: model.swapStations) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("newTripSwap")
                .accessibilityLabel(text("swap", fallback: "Swap stations"))
                .disabled(model.origin == nil && model.destination == nil)
            }
            if model.origin == nil, !model.nearbyStations.isEmpty {
                nearbyRow
            }
            ForEach(Array(model.vias.enumerated()), id: \.element.id) { index, via in
                viaRow(via, index: index)
            }
            if model.origin != nil, model.destination != nil, model.timetableTrain == nil {
                Button {
                    model.picking = .via
                } label: {
                    Label(text("addVia", fallback: "Add a stop along the way"), systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(model.catalog == nil)
                .accessibilityIdentifier("newTripAddVia")
            }
            stationButton(
                title: text("to", fallback: "To"),
                station: model.destination,
                line: model.destinationLine,
                source: model.filledBy[.destination],
                identifier: "newTripDestination") { model.picking = .destination }
        } header: {
            Text(text("journey", fallback: "Journey"))
        }
    }

    /// Up to three stations near the reader's last known position.
    private var nearbyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Image(systemName: "location")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                ForEach(Array(model.nearbyStations.enumerated()), id: \.element.id) { index, nearby in
                    Button {
                        model.assign(nearby.station, to: .origin, reduceMotion: true)
                    } label: {
                        Text(text("nearbyStation", fallback: "{station} · {distance} m",
                                  ["station": .string(stationTitle(nearby.station)),
                                   "distance": .string(String(Int(nearby.meters.rounded())))]))
                            .font(.footnote)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("newTripNearby-\(index)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text("nearby", fallback: "Stations near you"))
    }

    private func viaRow(_ via: TripDraftModel.ViaStop, index: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text("viaTitle", fallback: "Via"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(stationTitle(via.station))
                if let subtitle = stationSubtitle(via.station, line: nil) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Button {
                model.clearTimetable()
                model.vias.removeAll { $0.id == via.id }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text("removeVia", fallback: "Remove stop"))
            .accessibilityIdentifier("newTripRemoveVia-\(index)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newTripVia-\(index)")
    }

    private func stationButton(
        title: String,
        station: CatalogStation?,
        line: CatalogLine?,
        source: TripDraftModel.FillSource? = nil,
        identifier: String,
        choose: @escaping () -> Void
    ) -> some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    FillSourceBadge(source: source)
                }
                Text(stationTitle(station))
                    .font(.body)
                    .foregroundStyle(station == nil ? Color.secondary : Color.primary)
                if let station, let subtitle = stationSubtitle(station, line: line) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.catalog == nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(stationAccessibility(title: title, station: station, line: line))
        .accessibilityIdentifier(identifier)
        .contextMenu {
            if let station {
                let full = copyText(for: station, line: line)
                Button {
                    StationQualifierCopy.copy(full)
                } label: {
                    Label(localization.text("ios.editor.copyStation", fallback: "Copy"), systemImage: "doc.on.doc")
                }
                ShareLink(item: full) {
                    Label(localization.text("ios.share", fallback: "Share"), systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
