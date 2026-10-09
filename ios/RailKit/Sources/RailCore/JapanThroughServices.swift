import Foundation

/// A researched, deliberately partial catalog of operational corridors on the
/// surveyed physical network. A corridor means some trains run through; it does
/// not promise a dated departure, stopping pattern, or every endpoint pairing.
public enum JapanThroughServices {
    public enum Kind: String, Codable, Sendable { case operationalAlias, throughRunning }
    public enum CoverageLevel: String, Codable, Sendable { case checked, unknown }
    public struct Leg: Codable, Hashable, Sendable {
        public let lineID: String
        /// An explicitly reviewed paired physical row for the opposite journey
        /// direction. Package traversal permissions still apply to both rows.
        public let reverseLineID: String?
        public let fromStationCode: String
        public let toStationCode: String
        /// Inclusive ISO day (`yyyy-MM-dd`). Nil means in service since before `coverageFrom`.
        public let validFrom: String?
        /// Exclusive ISO day. Nil means still running.
        public let validTo: String?
    }
    public struct Connector: Codable, Hashable, Sendable, Identifiable {
        public let id: String
        public let fromLineID: String
        public let fromStationCode: String
        public let toLineID: String
        public let toStationCode: String
        /// Inclusive ISO day (`yyyy-MM-dd`). Nil means in service since before `coverageFrom`.
        public let validFrom: String?
        /// Exclusive ISO day. Nil means still available.
        public let validTo: String?
        public let notes: String

        func joins(_ firstLineIDs: [String], at firstCode: String,
                   to secondLineIDs: [String], at secondCode: String, on date: String?) -> Bool {
            guard JapanThroughServices.active(validFrom: validFrom, validTo: validTo, on: date) else {
                return false
            }
            return (firstLineIDs.contains(fromLineID) && firstCode == fromStationCode
                    && secondLineIDs.contains(toLineID) && secondCode == toStationCode)
                || (firstLineIDs.contains(toLineID) && firstCode == toStationCode
                    && secondLineIDs.contains(fromLineID) && secondCode == fromStationCode)
        }
    }
    public struct Pattern: Codable, Hashable, Sendable, Identifiable {
        public let id: String
        /// Catalog identity for this corridor, not a train number or a claim
        /// that all patterns with a passenger-facing alias interoperate.
        public let serviceCode: String
        public let name: String
        public let aliases: [String]
        public let kind: Kind
        public let legs: [Leg]
        public let sourceURLs: [String]
        public let notes: String
        /// Inclusive ISO day (`yyyy-MM-dd`). Nil means in service since before `coverageFrom`.
        public let validFrom: String?
        /// Exclusive ISO day. Nil means still running. A leg is active on a day only when this pattern is too.
        public let validTo: String?
        public var lineIDs: [String] {
            var seen: Set<String> = []
            return legs.flatMap { [$0.lineID] + ($0.reverseLineID.map { [$0] } ?? []) }
                .filter { seen.insert($0).inserted }
        }

        public func lineIDs(on date: String?) -> [String] {
            var seen: Set<String> = []
            return legs(on: date).flatMap { [$0.lineID] + ($0.reverseLineID.map { [$0] } ?? []) }
                .filter { seen.insert($0).inserted }
        }

        /// Active legs in catalog order. Empty when the pattern is inactive on `date`.
        /// A pattern is active iff this returns at least one leg. Consecutive pairs are that day's junctions.
        public func legs(on date: String?) -> [Leg] {
            guard JapanThroughServices.active(validFrom: validFrom, validTo: validTo, on: date) else { return [] }
            return legs.filter { JapanThroughServices.active(validFrom: $0.validFrom, validTo: $0.validTo, on: date) }
        }

        /// Display-only slices of the catalog's anchored service corridor.
        /// These preserve service identity and station occurrences, but do not
        /// prove track connectivity. Never use them as physical search edges or
        /// auto-fill candidates; LocalJourneySearch owns physical proposals.
        public func choices(package: CompactPackage, originCode: String,
                            destinationCode: String, on date: String? = nil,
                            connectors: [Connector] = JapanThroughServices.connectors) -> [RailwayRouteChoices.Choice] {
            let legs = legs(on: date)
            guard originCode != destinationCode, !legs.isEmpty else { return [] }
            var steps: [Step] = []
            for (legIndex, leg) in legs.enumerated() {
                guard appendLegSteps(leg, legIndex: legIndex, legs: legs, package: package,
                                     date: date, connectors: connectors, steps: &steps) else { return [] }
            }
            guard let first = steps.first else { return [] }
            let stationCodes = [first.from.id] + steps.map { $0.to.id }
            var results: [RailwayRouteChoices.Choice] = []
            var seen: Set<String> = []
            for start in stationCodes.indices where stationCodes[start] == originCode {
                for end in stationCodes.indices where stationCodes[end] == destinationCode && start != end {
                    let reverse = start > end
                    let slice = Array(steps[min(start, end)..<max(start, end)])
                    let ordered = reverse ? Array(slice.reversed()) : slice
                    guard let choice = makeChoice(ordered, reverse: reverse) else { continue }
                    if seen.insert(choice.id).inserted { results.append(choice) }
                    if results.count == 3 { return results }
                }
            }
            return results
        }
        private struct Step {
            let line: CompactPackage.Line?
            let intervalIndex: Int?
            let from: CompactPackage.Station
            let to: CompactPackage.Station
            let direction: Int
            let reverseLine: CompactPackage.Line?
            let connector: Connector?
        }

        private func appendLegSteps(
            _ leg: Leg, legIndex: Int, legs: [Leg], package: CompactPackage,
            date: String?, connectors: [Connector], steps: inout [Step]
        ) -> Bool {
            guard let line = package.lines.first(where: { $0.id == leg.lineID }),
                  let start = line.stations.firstIndex(where: { $0.id == leg.fromStationCode }),
                  let end = line.stations.firstIndex(where: { $0.id == leg.toStationCode }),
                  start != end else { return false }
            if let previous = steps.last, previous.to.id != leg.fromStationCode {
                guard legIndex > 0 else { return false }
                let previousLeg = legs[legIndex - 1]
                let firstIDs = [previousLeg.lineID] + (previousLeg.reverseLineID.map { [$0] } ?? [])
                let secondIDs = [leg.lineID] + (leg.reverseLineID.map { [$0] } ?? [])
                guard let connector = connectors.first(where: {
                    $0.joins(firstIDs, at: previous.to.id,
                             to: secondIDs, at: leg.fromStationCode, on: date)
                }) else { return false }
                steps.append(Step(line: nil, intervalIndex: nil, from: previous.to,
                                  to: line.stations[start], direction: 1,
                                  reverseLine: nil, connector: connector))
            }
            let reverseLine: CompactPackage.Line?
            if let identity = leg.reverseLineID {
                guard let mate = package.lines.first(where: { $0.id == identity }),
                      mate.operator == line.operator,
                      mate.alignmentOf == line.id || line.alignmentOf == mate.id,
                      mate.stations.contains(where: { $0.id == leg.fromStationCode }),
                      mate.stations.contains(where: { $0.id == leg.toStationCode }) else { return false }
                reverseLine = mate
            } else {
                reverseLine = nil
            }
            let direction = start < end ? 1 : -1
            for index in stride(from: start, to: end, by: direction) {
                steps.append(Step(line: line, intervalIndex: min(index, index + direction),
                                  from: line.stations[index], to: line.stations[index + direction],
                                  direction: direction, reverseLine: reverseLine, connector: nil))
            }
            return true
        }

        private func appendRailStep(
            _ step: Step, reverse: Bool, sections: inout [RouteSection],
            visits: inout [RailwayRouteChoices.Visit], ids: inout [String]
        ) -> Bool {
            guard let baseLine = step.line, let baseIntervalIndex = step.intervalIndex else {
                return false
            }
            let line = reverse ? (step.reverseLine ?? baseLine) : baseLine
            var from = reverse ? step.to : step.from
            var to = reverse ? step.from : step.to
            var direction = reverse ? -step.direction : step.direction
            var intervalIndex = baseIntervalIndex
            if reverse, step.reverseLine != nil {
                guard let fromIndex = line.stations.firstIndex(where: { $0.id == from.id }),
                      let toIndex = line.stations.firstIndex(where: { $0.id == to.id }),
                      abs(fromIndex - toIndex) == 1 else { return false }
                from = line.stations[fromIndex]
                to = line.stations[toIndex]
                direction = fromIndex < toIndex ? 1 : -1
                intervalIndex = min(fromIndex, toIndex)
            }
            let intervals = RailIntervalCodes.intervals(for: line)
            guard line.segments.indices.contains(intervalIndex),
                  intervals.indices.contains(intervalIndex),
                  intervals[intervalIndex].coordinates.count >= 2,
                  RailwayDirection.allowedDirections(for: line, intervalIndex: intervalIndex).contains(direction)
            else { return false }
            if visits.isEmpty { visits.append(.init(code: from.id, name: from.name)) }
            visits.append(.init(code: to.id, name: to.name))
            if ids.last != line.id { ids.append(line.id) }
            sections.append(RouteSection(from: from.name, to: to.name,
                fromN02StationCode: from.id, toN02StationCode: to.id,
                lineNames: [line.name], operatorNames: line.operator.map { [$0] },
                lineIDs: [line.id], sectionCodes: [intervals[intervalIndex].code]))
            return true
        }

        private func appendConnectorStep(
            _ step: Step, connector: Connector, reverse: Bool,
            sections: inout [RouteSection], visits: inout [RailwayRouteChoices.Visit]
        ) {
            let from = reverse ? step.to : step.from
            let to = reverse ? step.from : step.to
            if visits.isEmpty { visits.append(.init(code: from.id, name: from.name)) }
            visits.append(.init(code: to.id, name: to.name))
            sections.append(RouteSection(
                from: from.name, to: to.name,
                fromN02StationCode: from.id, toN02StationCode: to.id,
                lineNames: [], operatorNames: [], lineIDs: [],
                sectionCodes: ["connector:\(connector.id)"]))
        }

        private func unique(_ values: [String]) -> [String] {
            var valuesSeen: Set<String> = []
            return values.filter { valuesSeen.insert($0).inserted }
        }

        private func makeChoice(
            _ ordered: [Step], reverse: Bool
        ) -> RailwayRouteChoices.Choice? {
            var sections: [RouteSection] = []
            var visits: [RailwayRouteChoices.Visit] = []
            var ids: [String] = []
            var valid = true
            for step in ordered {
                if let connector = step.connector {
                    appendConnectorStep(step, connector: connector, reverse: reverse,
                                        sections: &sections, visits: &visits)
                    continue
                }
                if !appendRailStep(step, reverse: reverse, sections: &sections,
                                   visits: &visits, ids: &ids) {
                    valid = false
                    break
                }
            }
            guard valid, !sections.isEmpty else { return nil }
            let choice = RailwayRouteChoices.Choice(lineIDs: ids,
                lineNames: unique(sections.flatMap { $0.lineNames ?? [] }),
                operatorNames: unique(sections.flatMap { $0.operatorNames ?? [] }),
                stations: visits, sectionCodes: sections.flatMap { $0.sectionCodes ?? [] },
                routeSections: sections)
            return choice
        }

    }
    public struct Coverage: Codable, Hashable, Sendable {
        public let region: String
        public let level: CoverageLevel
        public let notes: String
    }
    public struct Catalog: Codable, Sendable {
        public let schemaVersion: Int?
        public let coverageFrom: String?
        public let checkedAt: String
        public let scope: String
        public let connectors: [Connector]
        public let patterns: [Pattern]
        public let coverage: [Coverage]

        public init(schemaVersion: Int? = nil, coverageFrom: String? = nil, checkedAt: String,
                    scope: String, connectors: [Connector] = [],
                    patterns: [Pattern], coverage: [Coverage]) {
            self.schemaVersion = schemaVersion
            self.coverageFrom = coverageFrom
            self.checkedAt = checkedAt
            self.scope = scope
            self.connectors = connectors
            self.patterns = patterns
            self.coverage = coverage
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, coverageFrom, checkedAt, scope, connectors, patterns, coverage
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
            coverageFrom = try values.decodeIfPresent(String.self, forKey: .coverageFrom)
            checkedAt = try values.decode(String.self, forKey: .checkedAt)
            scope = try values.decode(String.self, forKey: .scope)
            connectors = try values.decodeIfPresent([Connector].self, forKey: .connectors) ?? []
            patterns = try values.decode([Pattern].self, forKey: .patterns)
            coverage = try values.decode([Coverage].self, forKey: .coverage)
        }
    }
    public static let catalog: Catalog = {
        guard let value = try? loadBundled() else {
            return Catalog(checkedAt: "", scope: "unavailable", patterns: [], coverage: [])
        }
        return value
    }()
    public static func loadBundled() throws -> Catalog {
        guard let url = Bundle.module.url(forResource: "japan-through-services", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }
    public static var patterns: [Pattern] { catalog.patterns }
    public static var connectors: [Connector] { catalog.connectors }
    /// Patterns with at least one leg active on `date`. Nil is the current network.
    public static func patterns(on date: String? = nil) -> [Pattern] {
        patterns(on: date, patterns: Self.patterns)
    }
    static func patterns(on date: String?, patterns: [Pattern]) -> [Pattern] {
        patterns.filter { !$0.legs(on: date).isEmpty }
    }
    public static func matches(query: String, on date: String? = nil) -> [Pattern] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }
        return patterns(on: date).filter { pattern in
            ([pattern.serviceCode, pattern.name] + pattern.aliases).contains {
                normalized($0).contains(needle)
            }
        }
    }
    public static func patterns(touchingLineID lineID: String, on date: String? = nil) -> [Pattern] {
        patterns(touchingLineID: lineID, on: date, patterns: Self.patterns)
    }
    static func patterns(touchingLineID lineID: String, on date: String?,
                         patterns: [Pattern]) -> [Pattern] {
        Self.patterns(on: date, patterns: patterns).filter { $0.lineIDs(on: date).contains(lineID) }
    }
    /// Only consecutive, explicitly anchored legs can continue at a row change.
    /// Same-station interchanges elsewhere never acquire a through permission.
    /// Adjacency is consecutive pairs of the legs active on `date`.
    public static func continuationCodes(fromLineID: String, toLineID: String,
                                         atStationCode code: String, on date: String? = nil) -> Set<String> {
        continuationCodes(fromLineID: fromLineID, toLineID: toLineID, atStationCode: code,
                          on: date, patterns: patterns)
    }
    static func continuationCodes(fromLineID: String, toLineID: String, atStationCode code: String,
                                  on date: String?, patterns: [Pattern],
                                  connectors: [Connector] = Self.connectors) -> Set<String> {
        guard fromLineID != toLineID else { return [] }
        return Set(patterns.compactMap { pattern in
            let legs = pattern.legs(on: date)
            for (a, b) in zip(legs, legs.dropFirst()) {
                let firstIDs = [a.lineID] + (a.reverseLineID.map { [$0] } ?? [])
                let secondIDs = [b.lineID] + (b.reverseLineID.map { [$0] } ?? [])
                let joinsAtCode: Bool
                if a.toStationCode == b.fromStationCode {
                    joinsAtCode = code == a.toStationCode
                } else {
                    joinsAtCode = (code == a.toStationCode || code == b.fromStationCode)
                        && connectors.contains {
                            $0.joins(firstIDs, at: a.toStationCode,
                                     to: secondIDs, at: b.fromStationCode, on: date)
                        }
                }
                guard joinsAtCode else { continue }
                if (firstIDs.contains(fromLineID) && secondIDs.contains(toLineID))
                    || (firstIDs.contains(toLineID) && secondIDs.contains(fromLineID)) { return pattern.serviceCode }
            }
            return nil
        })
    }
    /// Exact directed interval membership within each anchored physical leg.
    /// Use the returned per-pattern identities across the whole candidate path;
    /// intersecting passenger aliases such as JS is insufficient at a branch.
    public static func serviceCodes(line: CompactPackage.Line,
                                    fromStationCode: String, toStationCode: String,
                                    on date: String? = nil) -> Set<String> {
        serviceCodes(line: line, fromStationCode: fromStationCode, toStationCode: toStationCode,
                     on: date, patterns: Self.patterns)
    }
    static func serviceCodes(line: CompactPackage.Line,
                             fromStationCode: String, toStationCode: String,
                             on date: String?, patterns: [Pattern]) -> Set<String> {
        let intervals = RailIntervalCodes.intervals(for: line)
        return Set(Self.patterns(on: date, patterns: patterns).compactMap { pattern in
            for leg in pattern.legs(on: date) where leg.lineID == line.id || leg.reverseLineID == line.id {
                guard let start = line.stations.firstIndex(where: { $0.id == leg.fromStationCode }),
                      let end = line.stations.firstIndex(where: { $0.id == leg.toStationCode }), start != end else { continue }
                let low = min(start, end), high = max(start, end)
                for index in low..<high where intervals.indices.contains(index) {
                    let interval = intervals[index]
                    if (interval.fromStationCode == fromStationCode && interval.toStationCode == toStationCode)
                        || (interval.fromStationCode == toStationCode && interval.toStationCode == fromStationCode) {
                        let direction = interval.fromStationCode == fromStationCode ? 1 : -1
                        guard interval.coordinates.count >= 2,
                              RailwayDirection.allowedDirections(for: line, intervalIndex: index).contains(direction) else { continue }
                        return pattern.serviceCode
                    }
                }
            }
            return nil
        })
    }
    /// Half-open window `[validFrom, validTo)`. An undated ride sees only still-running service (`validTo == nil`).
    static func active(validFrom: String?, validTo: String?, on date: String?) -> Bool {
        guard let date else { return validTo == nil }
        if let validFrom, validFrom > date { return false }
        if let validTo, date >= validTo { return false }
        return true
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { !$0.isWhitespace && $0 != "-" && $0 != "・" }
    }
}
