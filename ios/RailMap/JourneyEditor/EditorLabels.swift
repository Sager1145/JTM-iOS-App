import RailApplication
import RailCore
import RailPresentation
import SwiftUI

/// The journey editor's views: they read and write one `TripDraftModel`
/// and share its wording and station labels.
@MainActor
protocol JourneyEditorLabelling {
    var localization: AppLocalization { get }
    var model: TripDraftModel { get }
}

extension JourneyEditorLabelling {
    func repairText(_ key: String, _ params: [String: Localization.Param]) -> String {
        if key == "ios.journey.repairInterrupted" {
            return localization.journeyText(key, fallback: "Ride changed while repairing; run Repair again")
        }
        return localization.text(key, params: params)
    }

    func visitName(_ id: UUID) -> String {
        guard let stop = model.draft.stops.first(where: { $0.routeEditing?.visitID == id }) else { return "" }
        return localization.stationName(stop.name, code: stop.n02StationCode, region: model.region)
    }

    func trainTypeLabel(_ type: String) -> String {
        if TripDraftModel.serviceTypes.contains(type) { return localization.text("ios.editor.serviceType.\(type)") }
        return type.isEmpty ? text("trainTypeNotSet", fallback: "Not set") : type
    }

    func missingText(_ missing: MissingTripDetails) -> String {
        var parts: [String] = []
        if missing.vehicleType { parts.append(localization.text("ios.editor.vehicleType")) }
        if missing.platformCount > 0 {
            parts.append(text("missingPlatforms", fallback: "{count} platforms",
                              ["count": .string(String(missing.platformCount))]))
        }
        return text("needsDetails", fallback: "Still missing: {items}",
                    ["items": .string(parts.joined(separator: " · "))])
    }

    func directionWord(_ direction: TravelDirection.Direction?) -> String {
        switch direction {
        case .up: localization.text("ios.direction.up")
        case .down: localization.text("ios.direction.down")
        case nil: text("directionUnknown", fallback: "Direction not known")
        }
    }

    func boundForText(_ name: String) -> String {
        text("boundFor", fallback: "Toward {name}", ["name": .string(name)])
    }

    func regionName(_ code: String) -> String {
        guard let region = Region(rawValue: code) else { return code.uppercased() }
        return localization.text(region.localizationKey, fallback: region.fallbackName)
    }

    func copyText(for station: CatalogStation, line: CatalogLine?) -> String {
        guard let catalog = model.catalog else {
            return StationLabel.countryOnly(
                name: station.name, countryCode: station.key.regionCode.uppercased()).full
        }
        return StationReferenceResolution.copyLabel(
            for: station, catalog: catalog, preferredLineID: line?.id)
    }

    func copyText(
        code: String?, fallbackName: String, contextLineIDs: Set<String> = []
    ) -> String {
        let country = model.region.code.uppercased()
        guard let catalog = model.catalog, let code, !code.isEmpty,
              let station = catalog.station(StationKey(regionCode: model.region.code, sourceCode: code))
        else { return StationLabel.countryOnly(name: fallbackName, countryCode: country).full }
        return StationReferenceResolution.copyLabel(
            for: station, catalog: catalog, contextLineIDs: contextLineIDs)
    }

    func stationTitle(_ station: CatalogStation?) -> String {
        guard let station else { return text("chooseStation", fallback: "Choose station") }
        return BracketedStationText.title(
            officialName: station.name,
            localizedTitle: localization.stationName(
                station.name, code: station.key.sourceCode, region: model.region),
            regionCode: station.key.regionCode, localization: localization)
    }

    /// Bracket qualifier for the chosen station. A picked line names that line.
    func stationQualifier(_ station: CatalogStation, line: CatalogLine?) -> String {
        guard let catalog = model.catalog else {
            return StationLabel.caption(countryCode: station.key.regionCode.uppercased(), detail: nil)
        }
        let labels = model.lineLabelByID.isEmpty
            ? StationLabel.lineLabels(in: catalog, regionCode: station.key.regionCode) : model.lineLabelByID
        return StationLabel.text(
            for: station, catalog: catalog, labels: labels, preferredLineID: line?.id).qualifier
    }

    func stationSubtitle(_ station: CatalogStation, line: CatalogLine?) -> String? {
        let qualifier = stationQualifier(station, line: line)
        return BracketedStationText.secondary(
            officialName: station.name, regionCode: station.key.regionCode,
            qualifier: qualifier, localization: localization)
    }

    func stationAccessibility(title: String, station: CatalogStation?, line: CatalogLine?) -> String {
        guard let station else { return title }
        let qualifier = stationQualifier(station, line: line)
        return title + "，" + StationQualifierCopy.spoken(
            name: station.name, countryCode: station.key.regionCode.uppercased(),
            qualifier: qualifier, localization: localization)
    }

    func recordedQualifier(code: String?) -> String {
        let country = model.region.code.uppercased()
        guard let catalog = model.catalog, let code, !code.isEmpty,
              let station = catalog.station(StationKey(regionCode: model.region.code, sourceCode: code))
        else { return StationLabel.caption(countryCode: country, detail: nil) }
        let labels = model.lineLabelByID.isEmpty
            ? StationLabel.lineLabels(in: catalog, regionCode: model.region.code) : model.lineLabelByID
        return StationLabel.text(for: station, catalog: catalog, labels: labels).qualifier
    }

    func visitQualifier(
        _ visit: RailwayRouteChoices.Visit, corridor: TripRoutePlanner.Corridor
    ) -> String {
        let country = model.region.code.uppercased()
        if let change = lineChangeCaption(for: visit, junctions: corridor.junctions) {
            let detail = change.replacingOccurrences(of: "\n", with: " · ")
            return StationLabel.caption(countryCode: country, detail: detail)
        }
        guard let catalog = model.catalog,
              let station = catalog.station(StationKey(regionCode: model.region.code, sourceCode: visit.code))
        else {
            if corridor.lineNames.count == 1, let name = corridor.lineNames.first {
                return StationLabel.caption(countryCode: country, detail: name)
            }
            return StationLabel.caption(countryCode: country, detail: nil)
        }
        let labels = model.lineLabelByID.isEmpty
            ? StationLabel.lineLabels(in: catalog, regionCode: model.region.code) : model.lineLabelByID
        return StationLabel.text(
            for: station, catalog: catalog, labels: labels,
            contextLineIDs: Set(corridor.choice.lineIDs)).qualifier
    }

    func stationCountText(_ corridor: TripRoutePlanner.Corridor) -> String {
        let count = String(corridor.passStationCount)
        guard model.plannedIdentity == model.routeIdentity,
              model.physicallyResolvedCorridorIDs.contains(corridor.id),
              let kilometers = model.kilometerString(corridor.distanceKm) else {
            return text("stationCount", fallback: "{count} stations", ["count": .string(count)])
        }
        return text(
            "stationCountDistance",
            fallback: "{count} stations · {km} km",
            ["count": .string(count), "km": .string(kilometers)])
    }

    func junctionBadge(_ junction: TripRoutePlanner.Junction) -> String? {
        let station = localization.stationName(junction.stationName, code: junction.stationCode, region: model.region)
        switch junction.link {
        case .throughService:
            return text(
                "throughService",
                fallback: "Through service at {station}",
                ["station": .string(station)])
        case .none:
            return text("unverifiedConnection", fallback: "Unverified connection at {station}",
                        ["station": .string(station)])
        case .sameLine, .physicalJunction:
            return nil
        }
    }

    func lineChangeCaption(
        for visit: RailwayRouteChoices.Visit,
        junctions: [TripRoutePlanner.Junction]
    ) -> String? {
        let captions = junctions.filter { $0.stationCode == visit.code }.map { junction in
            text(
                "lineChange",
                fallback: "{from} → {to}",
                ["from": .string(junction.fromLineName), "to": .string(junction.toLineName)])
        }
        guard !captions.isEmpty else { return nil }
        return captions.joined(separator: "\n")
    }

    func disconnectedMessage(_ junctions: [TripRoutePlanner.Junction]) -> String {
        let changes = junctions.map { junction in
            text(
                "changeAt",
                fallback: "{station} ({from} → {to})",
                [
                    "station": .string(localization.stationName(
                        junction.stationName, code: junction.stationCode, region: model.region)),
                    "from": .string(junction.fromLineName),
                    "to": .string(junction.toLineName),
                ])
        }.joined(separator: "\n")
        let lead = text(
            "disconnected",
            fallback: "These lines are not connected — one train cannot run this way. Change trains at: {changes}",
            ["changes": .string(changes)])
        return lead + "\n" + text("addLegs", fallback: "Add each leg as its own trip.")
    }

    func text(
        _ key: String,
        fallback: String,
        _ params: [String: Localization.Param]? = nil
    ) -> String {
        localization.text("ios.newTrip.\(key)", params: params, fallback: fallback)
    }
}
