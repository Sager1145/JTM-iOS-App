import Foundation

/// ADR 0011: overlay stations as a pickable directory. One entry per
/// (station_name, line_name, operator); periods keep every member's validity.
public struct RetiredStation: Hashable, Sendable, Identifiable {
    public struct Period: Hashable, Sendable {
        public let validFrom: String?
        public let validTo: String?
    }

    public let id: String
    public let name: String
    public let lineName: String
    public let operatorName: String
    public let longitude: Double
    public let latitude: Double
    public let periods: [Period]
    /// n02_station_code only when the builder certified it
    /// (`station_code_basis == "exact_current_geometry_identity"` on a
    /// member); never the history id. This is the code a ride stop may store.
    public let certifiedCode: String?

    /// The period open on `date` (half-open `[valid_from, valid_to)`), or nil.
    /// nil/empty/non-ISO date never sees a retired station.
    public func period(on date: String?) -> Period? {
        guard let date, !date.isEmpty, RouteGraph.isPlainISODay(date) else { return nil }
        return periods.first { period in
            // A period with no `validTo` is current, never retired — this
            // API must never surface it for a dated ride.
            guard period.validTo != nil else { return false }
            return RouteGraph.RailValidity.isValid(
                validFrom: period.validFrom, validTo: period.validTo, on: date)
        }
    }

    public func isOpen(on date: String?) -> Bool { period(on: date) != nil }
}

public enum RailHistoryStations {
    public static let codePrefix = "history:"

    /// Grouped directory, sorted by name then lineName then operatorName then
    /// id. Features missing a station_name are skipped.
    public static func directory(_ overlay: RailHistoryOverlay) -> [RetiredStation] {
        struct Group {
            var historyId: String
            var longitude: Double
            var latitude: Double
            var periods: [RetiredStation.Period]
            var certifiedCode: String?
        }

        var order: [String] = []
        var groups: [String: Group] = [:]

        for feature in overlay.stations {
            guard let name = Stations.stationName(feature) else { continue }
            let lineName = Stations.stationLineName(feature)
            let operatorName = Stations.stationOperator(feature)
            let key = "\(name)\u{0}\(lineName)\u{0}\(operatorName)"

            let validFrom = Stations.stationValidFrom(feature)
            let validTo = Stations.stationValidTo(feature)
            let period = RetiredStation.Period(validFrom: validFrom, validTo: validTo)

            let certifiedCode: String? = {
                guard feature.properties["station_code_basis"]?.jsString
                    == "exact_current_geometry_identity"
                else { return nil }
                return Stations.stationCode(feature)
            }()

            if var existing = groups[key] {
                if !existing.periods.contains(period) {
                    existing.periods.append(period)
                }
                if existing.certifiedCode == nil {
                    existing.certifiedCode = certifiedCode
                }
                groups[key] = existing
            } else {
                let historyId = feature.properties["history_id"]?.jsString ?? ""
                let coordinate = Stations.displayCoordinate(feature)
                    .flatMap(Coordinate.init(pair:))
                order.append(key)
                groups[key] = Group(
                    historyId: historyId,
                    longitude: coordinate?.lon ?? 0,
                    latitude: coordinate?.lat ?? 0,
                    periods: [period],
                    certifiedCode: certifiedCode)
            }
        }

        var entries: [RetiredStation] = order.map { key in
            let group = groups[key]!
            let parts = key.components(separatedBy: "\u{0}")
            return RetiredStation(
                id: codePrefix + group.historyId,
                name: parts[0], lineName: parts[1], operatorName: parts[2],
                longitude: group.longitude, latitude: group.latitude,
                periods: group.periods, certifiedCode: group.certifiedCode)
        }

        entries.sort { a, b in
            if a.name != b.name { return a.name < b.name }
            if a.lineName != b.lineName { return a.lineName < b.lineName }
            if a.operatorName != b.operatorName { return a.operatorName < b.operatorName }
            return a.id < b.id
        }
        return entries
    }

    /// Entries open on `date`; `[]` for nil/empty/non-plain-ISO dates.
    public static func open(_ stations: [RetiredStation], on date: String?) -> [RetiredStation] {
        guard let date, !date.isEmpty, RouteGraph.isPlainISODay(date) else { return [] }
        return stations.filter { $0.isOpen(on: date) }
    }

    public static func isHistoryCode(_ code: String?) -> Bool {
        guard let code else { return false }
        return code.hasPrefix(codePrefix)
    }
}
