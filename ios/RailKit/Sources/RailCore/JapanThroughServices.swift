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
        public var lineIDs: [String] {
            var seen: Set<String> = []
            return legs.flatMap { [$0.lineID] + ($0.reverseLineID.map { [$0] } ?? []) }
                .filter { seen.insert($0).inserted }
        }

        /// Display-only slices of the catalog's anchored service corridor.
        /// These preserve service identity and station occurrences, but do not
        /// prove track connectivity. Never use them as physical search edges or
        /// auto-fill candidates; LocalJourneySearch owns physical proposals.
        public func choices(package: CompactPackage, originCode: String,
                            destinationCode: String) -> [RailwayRouteChoices.Choice] {
            guard originCode != destinationCode, !legs.isEmpty else { return [] }
            struct Step {
                let line: CompactPackage.Line
                let intervalIndex: Int
                let from: CompactPackage.Station
                let to: CompactPackage.Station
                let direction: Int
                let reverseLine: CompactPackage.Line?
            }
            var steps: [Step] = []
            for leg in legs {
                guard let line = package.lines.first(where: { $0.id == leg.lineID }),
                      let start = line.stations.firstIndex(where: { $0.id == leg.fromStationCode }),
                      let end = line.stations.firstIndex(where: { $0.id == leg.toStationCode }),
                      start != end else { return [] }
                if let previous = steps.last, previous.to.id != leg.fromStationCode { return [] }
                let reverseLine: CompactPackage.Line?
                if let identity = leg.reverseLineID {
                    guard let mate = package.lines.first(where: { $0.id == identity }),
                          mate.operator == line.operator,
                          mate.alignmentOf == line.id || line.alignmentOf == mate.id,
                          mate.stations.contains(where: { $0.id == leg.fromStationCode }),
                          mate.stations.contains(where: { $0.id == leg.toStationCode }) else { return [] }
                    reverseLine = mate
                } else {
                    reverseLine = nil
                }
                let direction = start < end ? 1 : -1
                for index in stride(from: start, to: end, by: direction) {
                    steps.append(Step(line: line, intervalIndex: min(index, index + direction),
                                      from: line.stations[index], to: line.stations[index + direction],
                                      direction: direction, reverseLine: reverseLine))
                }
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
                    var sections: [RouteSection] = []
                    var visits: [RailwayRouteChoices.Visit] = []
                    var ids: [String] = []
                    var valid = true
                    for step in ordered {
                        let line = reverse ? (step.reverseLine ?? step.line) : step.line
                        var from = reverse ? step.to : step.from
                        var to = reverse ? step.from : step.to
                        var direction = reverse ? -step.direction : step.direction
                        var intervalIndex = step.intervalIndex
                        if reverse, step.reverseLine != nil {
                            guard let fromIndex = line.stations.firstIndex(where: { $0.id == from.id }),
                                  let toIndex = line.stations.firstIndex(where: { $0.id == to.id }),
                                  abs(fromIndex - toIndex) == 1 else { valid = false; break }
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
                        else { valid = false; break }
                        if visits.isEmpty { visits.append(.init(code: from.id, name: from.name)) }
                        visits.append(.init(code: to.id, name: to.name))
                        if ids.last != line.id { ids.append(line.id) }
                        sections.append(RouteSection(from: from.name, to: to.name,
                            fromN02StationCode: from.id, toN02StationCode: to.id,
                            lineNames: [line.name], operatorNames: line.operator.map { [$0] },
                            lineIDs: [line.id], sectionCodes: [intervals[intervalIndex].code]))
                    }
                    guard valid, !sections.isEmpty else { continue }
                    func unique(_ values: [String]) -> [String] {
                        var valuesSeen: Set<String> = []
                        return values.filter { valuesSeen.insert($0).inserted }
                    }
                    let choice = RailwayRouteChoices.Choice(lineIDs: ids,
                        lineNames: unique(sections.flatMap { $0.lineNames ?? [] }),
                        operatorNames: unique(sections.flatMap { $0.operatorNames ?? [] }),
                        stations: visits, sectionCodes: sections.flatMap { $0.sectionCodes ?? [] },
                        routeSections: sections)
                    if seen.insert(choice.id).inserted { results.append(choice) }
                    if results.count == 3 { return results }
                }
            }
            return results
        }
    }
    public struct Coverage: Codable, Hashable, Sendable {
        public let region: String
        public let level: CoverageLevel
        public let notes: String
    }
    public struct Catalog: Codable, Sendable {
        public let checkedAt: String
        public let scope: String
        public let patterns: [Pattern]
        public let coverage: [Coverage]
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
    public static func matches(query: String) -> [Pattern] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }
        return patterns.filter { pattern in
            ([pattern.serviceCode, pattern.name] + pattern.aliases).contains {
                normalized($0).contains(needle)
            }
        }
    }
    public static func patterns(touchingLineID lineID: String) -> [Pattern] {
        patterns.filter { $0.lineIDs.contains(lineID) }
    }
    /// Only consecutive, explicitly anchored legs can continue at a row change.
    /// Same-station interchanges elsewhere never acquire a through permission.
    public static func continuationCodes(fromLineID: String, toLineID: String,
                                         atStationCode code: String) -> Set<String> {
        guard fromLineID != toLineID else { return [] }
        return Set(patterns.compactMap { pattern in
            for (a, b) in zip(pattern.legs, pattern.legs.dropFirst()) {
                guard a.toStationCode == code, b.fromStationCode == code else { continue }
                let firstIDs = [a.lineID] + (a.reverseLineID.map { [$0] } ?? [])
                let secondIDs = [b.lineID] + (b.reverseLineID.map { [$0] } ?? [])
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
                                    fromStationCode: String, toStationCode: String) -> Set<String> {
        let intervals = RailIntervalCodes.intervals(for: line)
        return Set(patterns.compactMap { pattern in
            for leg in pattern.legs where leg.lineID == line.id || leg.reverseLineID == line.id {
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
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { !$0.isWhitespace && $0 != "-" && $0 != "・" }
    }
}
