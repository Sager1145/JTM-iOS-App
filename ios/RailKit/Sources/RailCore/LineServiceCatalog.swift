import Foundation

/// Evidence-backed train service classes, keyed by the physical compact-package line.
/// A partial list does not imply that other classes are absent. Rolling stock is outside this catalog.
public struct LineServiceCatalog: Codable, Sendable {
    public enum Coverage: String, Codable, Sendable { case partial, unknown }

    public struct ServiceKind: Codable, Hashable, Sendable, Identifiable {
        public let id: String
        public let displayName: String
        /// Passenger-facing value compatible with Train.trainType.
        public let trainType: String
        public let sourceURL: String
        public let validFrom: String?
        /// Exclusive upper bound; null means the end was not established.
        public let validUntil: String?
        public let scope: String
        public let fromStationCode: String?
        public let toStationCode: String?
        public let observedOn: String

        public func applies(on serviceDate: String) -> Bool {
            guard LineServiceCatalog.isDate(serviceDate), let validFrom else { return false }
            return serviceDate >= validFrom && (validUntil.map { serviceDate < $0 } ?? false)
        }
    }

    public struct LineCoverage: Codable, Sendable, Identifiable {
        public var id: String { lineID }
        public let lineID: String
        public let operatorName: String
        public let lineName: String
        public let aliases: [String]
        public let coverage: Coverage
        public let kinds: [ServiceKind]
        public let note: String
    }

    /// A small, dated excerpt; omitted stations are unknown, never implied non-stops.
    public struct TimetableTrip: Codable, Sendable, Identifiable {
        public struct StopTime: Codable, Sendable {
            public let stationCode: String
            public let stationName: String
            /// Seconds since midnight in the Japanese service day. Values >=86400 cross midnight.
            public let arrivalSeconds: Int?
            public let departureSeconds: Int?
        }
        public let id: String
        public let trainNumber: String
        public let trainType: String
        public let operatorName: String
        public let lineIDs: [String]
        /// Explicit researched dates; no inferred weekday/holiday calendar.
        public let serviceDates: [String]
        public let sourceURL: String
        public let coverage: Coverage
        public let note: String
        public let stops: [StopTime]
        /// Original ODPT identities retained even when the linked trip is outside this export.
        public let previousTrainIDs: [String]?
        public let nextTrainIDs: [String]?
        public let sourceOperatorID: String?
        public let sourceRailwayID: String?
        public let sourceTrainTypeID: String?
        public let sourceCalendarID: String?
    }

    public let schemaVersion: Int
    public let inventoryVersion: String
    public let observedOn: String
    public let lines: [LineCoverage]
    public let trips: [TimetableTrip]

    public enum CatalogError: Error { case missingResource, invalidArtifact(String) }

    /// The same import path accepts future reviewed JSON artifacts without rebuilding the app.
    public init(data: Data) throws {
        let decoded = try JSONDecoder().decode(Self.self, from: data)
        guard decoded.schemaVersion == 1, Set(decoded.lines.map(\.lineID)).count == decoded.lines.count else {
            throw CatalogError.invalidArtifact("Unsupported schema or duplicate line identity")
        }
        let ids = Set(decoded.lines.map(\.lineID))
        for line in decoded.lines {
            guard line.kinds.isEmpty == (line.coverage == .unknown) else {
                throw CatalogError.invalidArtifact("Inconsistent line coverage: \(line.lineID)")
            }
            for kind in line.kinds {
                guard URL(string: kind.sourceURL)?.scheme == "https",
                      Self.isDate(kind.observedOn),
                      kind.validFrom.map(Self.isDate) ?? true,
                      kind.validUntil.map(Self.isDate) ?? true,
                      (kind.validFrom == nil || kind.validUntil == nil || kind.validFrom! < kind.validUntil!) else {
                    throw CatalogError.invalidArtifact("Invalid service provenance or validity")
                }
            }
        }
        guard Set(decoded.trips.map(\.id)).count == decoded.trips.count else {
            throw CatalogError.invalidArtifact("Duplicate trip identity")
        }
        for trip in decoded.trips {
            guard !trip.serviceDates.isEmpty, trip.serviceDates.allSatisfy(Self.isDate),
                  trip.lineIDs.allSatisfy(ids.contains),
                  URL(string: trip.sourceURL)?.scheme == "https", trip.stops.count >= 2 else {
                throw CatalogError.invalidArtifact("Invalid timetable scope")
            }
            var previous = -1
            for stop in trip.stops {
                let values = [stop.arrivalSeconds, stop.departureSeconds].compactMap { $0 }
                guard !values.isEmpty, values.allSatisfy({ $0 >= previous && $0 >= 0 }),
                      stop.arrivalSeconds == nil || stop.departureSeconds == nil || stop.arrivalSeconds! <= stop.departureSeconds! else {
                    throw CatalogError.invalidArtifact("Non-monotonic stop times")
                }
                previous = values.max()!
            }
        }
        self = decoded
    }

    public static func loadBundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "line-service-catalog", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        return try Self(data: Data(contentsOf: url))
    }

    public func coverage(lineID: String, operatorName: String? = nil, serviceDate: String? = nil) -> LineCoverage? {
        guard let line = lines.first(where: { $0.lineID == lineID }),
              operatorName == nil || operatorName == line.operatorName else { return nil }
        guard let serviceDate else { return line }
        let kinds = line.kinds.filter { $0.applies(on: serviceDate) }
        return LineCoverage(lineID: line.lineID, operatorName: line.operatorName, lineName: line.lineName,
                            aliases: line.aliases, coverage: kinds.isEmpty ? .unknown : .partial,
                            kinds: kinds, note: line.note)
    }

    public func serviceKinds(lineID: String, operatorName: String? = nil, serviceDate: String? = nil) -> [ServiceKind] {
        coverage(lineID: lineID, operatorName: operatorName, serviceDate: serviceDate)?.kinds ?? []
    }

    public func timetableTrips(lineID: String, serviceDate: String, trainType: String? = nil) -> [TimetableTrip] {
        guard Self.isDate(serviceDate) else { return [] }
        return trips.filter { $0.lineIDs.contains(lineID) && $0.serviceDates.contains(serviceDate)
            && (trainType == nil || $0.trainType == trainType) }
    }

    private static func isDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), year > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return components.year == year && components.month == month && components.day == day
    }
}
