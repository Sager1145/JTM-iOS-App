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
        /// Inclusive ISO day (`yyyy-MM-dd`). Nil leaves the start unspecified.
        public let validFrom: String?
        /// Exclusive ISO day. Nil means still running.
        public let validTo: String?
        /// Reviewed direction around a loop in this physical row's station order:
        /// `forward` advances indices, `reverse` decreases them, wrapping at the seam.
        /// Nil retains the legacy anchored linear slice.
        public let loopTraversal: String?
        /// Sources for selecting this arc, separate from the pattern's general evidence.
        public let loopTraversalSourceURLs: [String]?

        public init(lineID: String, reverseLineID: String? = nil,
                    fromStationCode: String, toStationCode: String,
                    validFrom: String? = nil, validTo: String? = nil,
                    loopTraversal: String? = nil, loopTraversalSourceURLs: [String]? = nil) {
            self.lineID = lineID
            self.reverseLineID = reverseLineID
            self.fromStationCode = fromStationCode
            self.toStationCode = toStationCode
            self.validFrom = validFrom
            self.validTo = validTo
            self.loopTraversal = loopTraversal
            self.loopTraversalSourceURLs = loopTraversalSourceURLs
        }
    }
    /// An explicitly researched path through the base legs for one service period.
    public struct LegVariant: Codable, Hashable, Sendable {
        /// Inclusive ISO day. Nil means the path predates catalog coverage.
        public let validFrom: String?
        /// Exclusive ISO day. Nil means the current path.
        public let validTo: String?
        /// Ordered indices into `Pattern.legs`; gaps must be explicitly reviewed here.
        public let legIndices: [Int]
        public let sourceURLs: [String]
        public let notes: String
        /// A sourced, bounded period with no operational path. Its indices must be empty.
        public let suspended: Bool?

        public init(validFrom: String?, validTo: String?, legIndices: [Int],
                    sourceURLs: [String], notes: String, suspended: Bool? = nil) {
            self.validFrom = validFrom
            self.validTo = validTo
            self.legIndices = legIndices
            self.sourceURLs = sourceURLs
            self.notes = notes
            self.suspended = suspended
        }
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
        /// Inclusive ISO day (`yyyy-MM-dd`). Nil leaves the start unspecified;
        /// dated lookups then begin at the owning catalog's evidence coverage.
        public let validFrom: String?
        /// Exclusive ISO day. Nil means still running. A leg is active on a day only when this pattern is too.
        public let validTo: String?
        /// When present, exactly one dated path must match; the base path is never a fallback.
        public let legVariants: [LegVariant]?
        /// Evidence coverage supplied by the owning catalog, never serialized as a pattern field.
        fileprivate var catalogCoverageFrom: String? = nil

        private enum CodingKeys: String, CodingKey {
            case id, serviceCode, name, aliases, kind, legs, sourceURLs, notes, validFrom, validTo, legVariants
        }

        public init(id: String, serviceCode: String, name: String, aliases: [String],
                    kind: Kind, legs: [Leg], sourceURLs: [String], notes: String,
                    validFrom: String?, validTo: String?, legVariants: [LegVariant]? = nil) {
            self.id = id
            self.serviceCode = serviceCode
            self.name = name
            self.aliases = aliases
            self.kind = kind
            self.legs = legs
            self.sourceURLs = sourceURLs
            self.notes = notes
            self.validFrom = validFrom
            self.validTo = validTo
            self.legVariants = legVariants
        }

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

        /// Active legs in the explicitly selected path, or in base catalog order.
        /// Filtering may trim its ends but cannot create a new interior junction.
        /// Invalid or ambiguous variants and inactive patterns return no path.
        public func legs(on date: String?) -> [Leg] {
            guard JapanThroughServices.active(validFrom: validFrom, validTo: validTo, on: date) else { return [] }
            if validFrom == nil, let date, let catalogCoverageFrom, date < catalogCoverageFrom {
                return []
            }
            let indices: [Int]
            if let legVariants {
                guard variantsAreValid(legVariants) else { return [] }
                let matching = legVariants.filter {
                    JapanThroughServices.active(validFrom: $0.validFrom, validTo: $0.validTo, on: date)
                }
                guard matching.count == 1 else { return [] }
                if matching[0].suspended == true { return [] }
                indices = matching[0].legIndices
            } else {
                indices = Array(legs.indices)
            }
            let activePositions = indices.indices.filter {
                let leg = legs[indices[$0]]
                return JapanThroughServices.active(validFrom: leg.validFrom, validTo: leg.validTo, on: date)
            }
            guard zip(activePositions, activePositions.dropFirst()).allSatisfy({ $0.1 == $0.0 + 1 }) else {
                return []
            }
            return activePositions.map { legs[indices[$0]] }
        }

        private func variantsAreValid(_ variants: [LegVariant]) -> Bool {
            for variant in variants {
                if variant.suspended == true {
                    guard variant.legIndices.isEmpty,
                          variant.validFrom != nil, variant.validTo != nil else { return false }
                } else if variant.legIndices.isEmpty { return false }
                guard Set(variant.legIndices).count == variant.legIndices.count,
                      variant.legIndices.allSatisfy({ legs.indices.contains($0) }),
                      Self.validVariantDay(variant.validFrom), Self.validVariantDay(variant.validTo),
                      !variant.sourceURLs.isEmpty,
                      variant.sourceURLs.allSatisfy({
                          guard !$0.contains(where: { $0.isWhitespace }), let url = URL(string: $0) else { return false }
                          return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                              && !(url.host ?? "").isEmpty
                      }) else { return false }
                if let from = variant.validFrom, let to = variant.validTo, from >= to { return false }
            }
            let ordered = variants.sorted { ($0.validFrom ?? "") < ($1.validFrom ?? "") }
            for (previous, next) in zip(ordered, ordered.dropFirst()) {
                guard let end = previous.validTo, let start = next.validFrom, end <= start else {
                    return false
                }
            }
            return true
        }

        private static func validVariantDay(_ value: String?) -> Bool {
            guard let value else { return true }
            guard Dates.isValidDateString(value) else { return false }
            let components = value.split(separator: "-").compactMap { Int($0) }
            guard components.count == 3, components[0] > 0 else { return false }
            let year = components[0], month = components[1], day = components[2]
            let leap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
            let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            return day <= days[month - 1]
        }

        /// Display-only slices of the catalog's anchored service corridor.
        /// These preserve service identity and station occurrences, but do not
        /// prove track connectivity. Never use them as physical search edges or
        /// auto-fill candidates; LocalJourneySearch owns physical proposals.
        public func choices(package: CompactPackage, originCode: String,
                            destinationCode: String, on date: String? = nil,
                            connectors: [Connector]) -> [RailwayRouteChoices.Choice] {
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
            guard let traversal = JapanThroughServices.traversal(for: leg, line: line) else { return false }
            for edge in traversal {
                steps.append(Step(line: line, intervalIndex: edge.intervalIndex,
                                  from: line.stations[edge.fromIndex], to: line.stations[edge.toIndex],
                                  direction: edge.direction, reverseLine: reverseLine, connector: nil))
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
                      let toIndex = line.stations.firstIndex(where: { $0.id == to.id }) else { return false }
                if abs(fromIndex - toIndex) == 1 {
                    direction = fromIndex < toIndex ? 1 : -1
                    intervalIndex = min(fromIndex, toIndex)
                } else if line.isLoop, Set([fromIndex, toIndex]) == Set([0, line.stations.count - 1]) {
                    direction = toIndex == 0 ? 1 : -1
                    intervalIndex = line.stations.count - 1
                } else { return false }
                from = line.stations[fromIndex]
                to = line.stations[toIndex]
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
            self.patterns = patterns.map {
                var contextual = $0
                contextual.catalogCoverageFrom = coverageFrom
                return contextual
            }
            self.coverage = coverage
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, coverageFrom, checkedAt, scope, connectors, patterns, coverage
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
            let floor = try values.decodeIfPresent(String.self, forKey: .coverageFrom)
            coverageFrom = floor
            checkedAt = try values.decode(String.self, forKey: .checkedAt)
            scope = try values.decode(String.self, forKey: .scope)
            connectors = try values.decodeIfPresent([Connector].self, forKey: .connectors) ?? []
            patterns = try values.decode([Pattern].self, forKey: .patterns).map {
                var contextual = $0
                contextual.catalogCoverageFrom = floor
                return contextual
            }
            coverage = try values.decode([Coverage].self, forKey: .coverage)
        }
    }
    private static let bundledLock = NSLock()
    nonisolated(unsafe) private static var bundledCatalogs: [URL: Catalog] = [:]

    /// A successful immutable package catalog is shared. A missing or damaged
    /// resource remains a failure, never a successfully loaded empty catalog.
    public static func loadBundled(bundle: Bundle? = nil) throws -> Catalog {
        let bundle = bundle ?? .module
        guard let url = bundle.url(forResource: "japan-through-services", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        bundledLock.lock()
        defer { bundledLock.unlock() }
        let key = url.standardizedFileURL
        if let catalog = bundledCatalogs[key] { return catalog }
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        bundledCatalogs[key] = catalog
        return catalog
    }

    /// Patterns with at least one leg active on `date`. Nil is the current network.
    public static func patterns(on date: String? = nil, patterns: [Pattern]) -> [Pattern] {
        patterns.filter { !$0.legs(on: date).isEmpty }
    }
    public static func matches(query: String, on date: String? = nil, patterns: [Pattern]) -> [Pattern] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }
        return Self.patterns(on: date, patterns: patterns).filter { pattern in
            ([pattern.serviceCode, pattern.name] + pattern.aliases).contains {
                normalized($0).contains(needle)
            }
        }
    }
    public static func patterns(touchingLineID lineID: String, on date: String? = nil,
                                patterns: [Pattern]) -> [Pattern] {
        Self.patterns(on: date, patterns: patterns).filter { $0.lineIDs(on: date).contains(lineID) }
    }
    /// Only consecutive, explicitly anchored legs can continue at a row change.
    /// Same-station interchanges elsewhere never acquire a through permission.
    /// Adjacency is consecutive pairs of the legs active on `date`.
    public static func continuationCodes(fromLineID: String, toLineID: String, atStationCode code: String,
                                         on date: String? = nil, patterns: [Pattern],
                                         connectors: [Connector]) -> Set<String> {
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
                                    on date: String? = nil, patterns: [Pattern]) -> Set<String> {
        let intervals = RailIntervalCodes.intervals(for: line)
        return Set(Self.patterns(on: date, patterns: patterns).compactMap { pattern in
            for leg in pattern.legs(on: date) where leg.lineID == line.id || leg.reverseLineID == line.id {
                guard let traversal = traversal(for: leg, line: line) else { continue }
                for edge in traversal where intervals.indices.contains(edge.intervalIndex) {
                    let index = edge.intervalIndex
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

    private struct TraversalStep {
        let fromIndex: Int
        let toIndex: Int
        let intervalIndex: Int
        let direction: Int
    }

    /// The closing interval has index `count - 1`, matching CompactPackage and
    /// RailIntervalCodes. Hints choose an arc; physical traversal permissions
    /// are still checked by each caller for the actual journey direction.
    private static func traversal(for leg: Leg, line: CompactPackage.Line) -> [TraversalStep]? {
        guard let start = line.stations.firstIndex(where: { $0.id == leg.fromStationCode }),
              let end = line.stations.firstIndex(where: { $0.id == leg.toStationCode }),
              start != end else { return nil }
        let direction: Int
        if let hint = leg.loopTraversal {
            guard line.isLoop, ["forward", "reverse"].contains(hint),
                  let sources = leg.loopTraversalSourceURLs, !sources.isEmpty,
                  sources.allSatisfy({ source in
                      guard !source.contains(where: { $0.isWhitespace }), let url = URL(string: source) else { return false }
                      return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                          && !(url.host ?? "").isEmpty
                  }) else { return nil }
            direction = hint == "forward" ? 1 : -1
        } else {
            direction = start < end ? 1 : -1
        }
        let count = line.stations.count
        var current = start
        var result: [TraversalStep] = []
        for _ in 0..<(count - 1) {
            let next = (current + direction + count) % count
            let index = direction == 1 ? current : next
            if leg.loopTraversal != nil, !line.segments.indices.contains(index) { return nil }
            result.append(TraversalStep(fromIndex: current, toIndex: next,
                                        intervalIndex: index, direction: direction))
            if next == end { return result }
            current = next
        }
        return nil
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
