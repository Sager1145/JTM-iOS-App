import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// The editor's map: the trip's stations and routes, the tapped station's
/// From / Via / To card, and the one-line hint above it.
struct EditorMapPanel: View, JourneyEditorLabelling {
    @Environment(AppLocalization.self) var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: TripDraftModel

    var body: some View {
        TripMapView(
            regionCode: model.region.code,
            stations: model.mapStations,
            content: mapContent,
            reduceMotion: reduceMotion,
            onStation: { station in
                withAnimation(RailMotion.animation(RailMotion.spring, reduceMotion: reduceMotion)) {
                    model.tappedStation = station
                }
            },
            onRoute: { id in
                if id.hasPrefix(TripDraftModel.repairRoutePrefix) {
                    if let index = Int(id.dropFirst(TripDraftModel.repairRoutePrefix.count)) { model.chooseRepair(index, text: repairText) }
                    return
                }
                // A grey line is one of the active section's candidates.
                let parts = id.split(separator: "|", maxSplits: 2).map(String.init)
                guard parts.count == 3, parts[0] == TripDraftModel.alternativePrefix,
                      let index = Int(parts[1]) else { return }
                model.choose(parts[2], inSection: index)
            },
            onBackground: {
                guard model.tappedStation != nil else { return }
                withAnimation(RailMotion.animation(RailMotion.enter, reduceMotion: reduceMotion)) {
                    model.tappedStation = nil
                }
            },
            onZoomChange: { model.mapZoomedIn = $0 })
            .overlay(alignment: .top) { mapHint }
            .overlay(alignment: .bottom) {
                if let tappedStation = model.tappedStation {
                    stationActionCard(tappedStation)
                        .transition(RailMotion.anchoredTransition(reduceMotion: reduceMotion, anchor: .bottom))
                }
            }
            .containerRelativeFrame(.vertical) { height, _ in
                // Large text needs the room for the form below the map.
                dynamicTypeSize.isAccessibilitySize
                    ? min(max(height * 0.28, 180), 300)
                    : min(max(height * 0.42, 240), 460)
            }
            .clipShape(RoundedRectangle(cornerRadius: RailRadius.card, style: .continuous))
            .padding(.horizontal, RailSpacing.s12)
            .padding(.bottom, RailSpacing.s4)
            .sensoryFeedback(.selection, trigger: model.selectedCorridorID) { old, new in
                old != nil && new != nil
            }
    }

    /// One short line telling the reader what the map will do next.
    @ViewBuilder private var mapHint: some View {
        let hint: String? = {
            if model.tappedStation != nil { return nil }
            if model.catalog == nil { return nil }
            if !model.mapZoomedIn, model.origin == nil || model.destination == nil {
                return text("mapZoomHint", fallback: "Zoom in to tap stations, or search below")
            }
            if model.origin == nil { return text("mapOriginHint", fallback: "Tap a station to start from") }
            if model.destination == nil { return text("mapDestinationHint", fallback: "Tap where the trip ends") }
            if model.timetableTrain != nil { return nil }
            if model.searching { return text("searching", fallback: "Searching routes") }
            if model.drawnRoutes.count > 1 {
                return text("mapAlternativesHint",
                            fallback: "{count} routes · tap a grey line, or add a stop",
                            ["count": .string(String(model.drawnRoutes.count))])
            }
            return nil
        }()
        if let hint {
            Text(hint)
                .font(.footnote.weight(.medium)) // ui-token-ok: map overlay hint, primary colour
                .foregroundStyle(.primary)
                .padding(.horizontal, RailSpacing.s12)
                .padding(.vertical, RailSpacing.s8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, RailSpacing.s8)
                .padding(.horizontal, RailSpacing.s12)
                .allowsHitTesting(false)
                .accessibilityIdentifier("newTripMapHint")
                .id(hint)
                .transition(.opacity)
                .animation(RailMotion.crossfade, value: hint)
        }
    }

    private func stationActionCard(_ station: CatalogStation) -> some View {
        let role = model.mapRole(of: station)
        return VStack(alignment: .leading, spacing: RailSpacing.s8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stationTitle(station))
                        .font(.headline)
                        .lineLimit(2)
                    if let subtitle = stationSubtitle(station, line: nil) {
                        Text(subtitle)
                            .railText(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: RailSpacing.s8)
                Button {
                    withAnimation(RailMotion.animation(RailMotion.enter, reduceMotion: reduceMotion)) {
                        model.tappedStation = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .railMinimumTouchTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localization.text("ios.close", fallback: "Close"))
                .accessibilityIdentifier("newTripMapStationClose")
            }
            HStack(spacing: RailSpacing.s8) {
                if let role {
                    actionButton(text("mapRemove", fallback: "Remove"), systemImage: "minus.circle",
                                 identifier: "newTripMapRemove", prominent: false) {
                        model.removeFromTrip(station, role: role, reduceMotion: reduceMotion)
                    }
                } else {
                    actionButton(text("from", fallback: "From"), systemImage: "circle.fill",
                                 identifier: "newTripMapSetOrigin", prominent: model.origin == nil) {
                        model.assign(station, to: .origin, reduceMotion: reduceMotion)
                    }
                    if model.origin != nil, model.destination != nil, model.timetableTrain == nil {
                        actionButton(text("mapVia", fallback: "Via"), systemImage: "plus",
                                     identifier: "newTripMapAddVia", prominent: false) {
                            model.assign(station, to: .via, reduceMotion: reduceMotion)
                        }
                    }
                    actionButton(text("to", fallback: "To"), systemImage: "flag.fill",
                                 identifier: "newTripMapSetDestination",
                                 prominent: model.origin != nil && model.destination == nil) {
                        model.assign(station, to: .destination, reduceMotion: reduceMotion)
                    }
                }
            }
        }
        .padding(RailSpacing.s12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: RailRadius.control, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(RailSpacing.s8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newTripMapStationCard")
    }

    private func actionButton(
        _ title: String, systemImage: String, identifier: String, prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if prominent {
                Button(action: action) {
                    Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
                }
                .buttonStyle(.railPrimary(fillsWidth: true))
            } else {
                Button(action: action) {
                    Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
                }
                .buttonStyle(.railSecondary(fillsWidth: true))
            }
        }
        .labelStyle(.titleAndIcon)
        .accessibilityIdentifier(identifier)
    }

    private var mapContent: TripMapContent {
        var marks: [TripMapContent.Mark] = []
        func mark(_ station: CatalogStation, role: TripMapContent.Role, id: String) {
            let coordinate = AppleMapDatum.display(
                Coordinate(lon: station.longitude, lat: station.latitude), country: model.region.code)
            marks.append(.init(id: id, role: role, station: station, coordinate: coordinate.clLocation))
        }
        if let origin = model.origin { mark(origin, role: .origin, id: "origin") }
        for (index, via) in model.vias.enumerated() {
            mark(via.station, role: .via(index), id: "via-\(via.id.uuidString)")
        }
        if let destination = model.destination { mark(destination, role: .destination, id: "destination") }
        return TripMapContent(
            routes: model.drawnRoutes, marks: marks, arrows: directionArrows, fitRevision: model.mapFitRevision)
    }

    /// One arrow per leg, at the middle of that leg's line on the chosen
    /// route, pointing the way the trip runs.
    private var directionArrows: [TripMapContent.Arrow] {
        guard !model.directionLegs.isEmpty,
              let route = model.drawnRoutes.first(where: \.isSelected) else { return [] }
        let pieces = route.pieces.filter { !$0.isConnector && $0.coordinates.count >= 2 }
        var arrows: [TripMapContent.Arrow] = []
        var used = 0
        for (index, leg) in model.directionLegs.enumerated() where leg.direction != nil {
            guard used < pieces.count else { break }
            let piece = pieces[used]
            used += 1
            let coordinates = piece.coordinates
            let middle = coordinates.count / 2
            let a = coordinates[max(0, middle - 1)]
            let b = coordinates[min(coordinates.count - 1, max(middle, 1))]
            var label = directionWord(leg.direction)
            if index == model.directionLegs.count - 1, let boundFor = model.boundFor { label += " · " + boundForText(boundFor) }
            arrows.append(.init(id: String(index), coordinate: a, bearing: bearing(a, b), label: label))
        }
        return arrows
    }

    private func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }
}
