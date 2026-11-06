import Foundation

/// The one feasibility rule for a planned trip changing rows.
///
/// A train continues from row A onto row B at station S on the ride date only when
/// (a) A and B are the same surveyed row, or a reviewed physical junction in
///     `physical-rail-junctions.json` joins exactly A and B at S and is valid on
///     that date, or
/// (b) a dated through service in `japan-through-services.json` continues from
///     A onto B at S on that date.
/// Anything else is `.none`: the reader changed trains there (a transfer), and
/// the planner never draws it as one continuous train. Shared station codes,
/// shared names, operators, crossings and nearby stations grant nothing.
public enum TripConnectivity {
    public enum Link: String, Equatable, Sendable {
        case sameLine, physicalJunction, throughService, none

        /// True when one train can continue across this row change.
        public var continues: Bool { self != .none }
    }

    /// Reviewed physical joins between two compact rows, keyed by station code.
    public struct Junctions: Sendable {
        public struct Join: Sendable, Equatable {
            public var id: String
            public var stationCode: String
            public var lineIDs: Set<String>
            public var validFrom: String?
            public var validTo: String?

            public init(id: String, stationCode: String, lineIDs: Set<String>,
                        validFrom: String? = nil, validTo: String? = nil) {
                self.id = id
                self.stationCode = stationCode
                self.lineIDs = lineIDs
                self.validFrom = validFrom
                self.validTo = validTo
            }
        }

        private let byStation: [String: [Join]]

        public static let empty = Junctions([])

        public init(_ joins: [Join]) {
            byStation = Dictionary(grouping: joins.filter { $0.lineIDs.count == 2 }, by: \.stationCode)
        }

        private struct Document: Decodable {
            struct Record: Decodable {
                struct Marker: Decodable {}
                let id: String
                let region: String
                let stationCode: String?
                let lineIDs: [String]?
                let evidence: [String]
                let validFrom: String?
                let validTo: String?
                let endJunction: Marker?
            }
            let format: String
            let junctions: [Record]
        }

        /// The registry's row-to-row joins for one region. A record joins two
        /// rows only when it names exactly two row IDs at a station code and
        /// cites evidence; a cross-identity end stub also needs same-train
        /// evidence, as the physical route graph requires.
        public init(registryData: Data, region: String) throws {
            let document = try JSONDecoder().decode(Document.self, from: registryData)
            guard document.format == "jtm-physical-rail-junctions-v1" else {
                throw PhysicalRailJunctionRegistry.RegistryError.unsupportedFormat
            }
            let region = region.lowercased()
            self.init(document.junctions.compactMap { record in
                guard record.region == region, let code = record.stationCode,
                      !record.evidence.isEmpty else { return nil }
                let ids = Set(record.lineIDs ?? [])
                guard ids.count == 2 else { return nil }
                if record.endJunction != nil,
                   !RouteGraph.PhysicalJunction.hasSameTrainEvidence(record.evidence) { return nil }
                return Join(id: record.id, stationCode: code, lineIDs: ids,
                            validFrom: record.validFrom, validTo: record.validTo)
            })
        }

        private static let bundledLock = NSLock()
        nonisolated(unsafe) private static var bundledByRegion: [String: Junctions] = [:]

        /// The app bundle's registry for `region`, decoded once. Without the
        /// resource (a test runner) there are no joins, so nothing extra
        /// connects: the rule only ever refuses more, never invents.
        public static func bundled(region: String, bundle: Bundle = .main) -> Junctions {
            let region = region.lowercased()
            bundledLock.lock()
            defer { bundledLock.unlock() }
            if let known = bundledByRegion[region] { return known }
            let value: Junctions
            if let url = bundle.url(forResource: "physical-rail-junctions", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let loaded = try? Junctions(registryData: data, region: region) {
                value = loaded
            } else {
                value = .empty
            }
            bundledByRegion[region] = value
            return value
        }

        /// The join between two rows at `stationCode` valid on `date`, if any.
        /// Half-open `[validFrom, validTo)`; an undated ride sees only joins still in use.
        public func join(_ firstLineID: String, _ secondLineID: String,
                         at stationCode: String, on date: String?) -> Join? {
            byStation[stationCode]?.first { join in
                join.lineIDs == [firstLineID, secondLineID]
                    && JapanThroughServices.active(validFrom: join.validFrom, validTo: join.validTo, on: date)
            }
        }
    }

    public static func link(from: CompactPackage.Line, to: CompactPackage.Line,
                            atStationCode stationCode: String, on date: String? = nil,
                            patterns: [JapanThroughServices.Pattern],
                            connectors: [JapanThroughServices.Connector],
                            junctions: Junctions = .empty) -> Link {
        link(fromLineID: from.id, toLineID: to.id, atStationCode: stationCode, on: date,
             patterns: patterns, connectors: connectors, junctions: junctions)
    }

    public static func link(fromLineID: String, toLineID: String,
                            atStationCode stationCode: String, on date: String? = nil,
                            patterns: [JapanThroughServices.Pattern],
                            connectors: [JapanThroughServices.Connector],
                            junctions: Junctions = .empty) -> Link {
        link(fromLineID: fromLineID, toLineID: toLineID, atStationCode: stationCode, on: date,
             through: JapanThroughServices.ContinuationIndex(patterns: patterns, connectors: connectors, on: date),
             junctions: junctions)
    }

    /// The same rule with the ride date's through services already indexed;
    /// planners checking many row changes build the index once.
    public static func link(fromLineID: String, toLineID: String,
                            atStationCode stationCode: String, on date: String?,
                            through: JapanThroughServices.ContinuationIndex,
                            junctions: Junctions = .empty) -> Link {
        if fromLineID == toLineID { return .sameLine }
        if !through.continuationCodes(fromLineID: fromLineID, toLineID: toLineID,
                                      atStationCode: stationCode).isEmpty {
            return .throughService
        }
        if junctions.join(fromLineID, toLineID, at: stationCode, on: date) != nil {
            return .physicalJunction
        }
        return .none
    }

    /// True when one train can continue from `from` onto `to` at `stationCode`.
    public static func allows(from: CompactPackage.Line, to: CompactPackage.Line,
                              atStationCode stationCode: String, on date: String? = nil,
                              patterns: [JapanThroughServices.Pattern] = [],
                              connectors: [JapanThroughServices.Connector] = [],
                              junctions: Junctions = .empty) -> Bool {
        link(from: from, to: to, atStationCode: stationCode, on: date,
             patterns: patterns, connectors: connectors, junctions: junctions).continues
    }
}
