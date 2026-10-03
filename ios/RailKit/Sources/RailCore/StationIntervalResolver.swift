import Foundation

/// Bounded inference over sourced physical intervals. Build once per network.
/// Passenger service names, preferences and train identifiers are not evidence.
public struct StationIntervalResolver: Sendable {
    public struct DirectedInterval: Codable, Equatable, Hashable, Sendable {
        public let lineID: String
        public let code: String
        /// `1` follows the package interval; `-1` traverses it in reverse.
        public let direction: Int

        public init(lineID: String, code: String, direction: Int) {
            self.lineID = lineID
            self.code = code
            self.direction = direction
        }
    }

    public struct Selection: Codable, Equatable, Sendable {
        public let stationCodes: [String]
        /// One ordered interval list for each adjacent pair of requested visits.
        public let legIntervals: [[DirectedInterval]]
        public var fromStationCode: String { stationCodes[0] }
        public var toStationCode: String { stationCodes[stationCodes.count - 1] }
        public var intervals: [DirectedInterval] { legIntervals.flatMap { $0 } }
        public var sectionCodes: [String] { intervals.map(\.code) }
        public var lineIDs: [String] {
            var seen: Set<String> = []
            return intervals.map(\.lineID).filter { seen.insert($0).inserted }
        }
    }

    public enum Result: Equatable, Sendable {
        case resolved(Selection)
        case ambiguous
        case unsupported
    }

    private struct Family: Hashable, Sendable {
        let name: String
        let operatorName: String
    }
    private struct Row: Sendable {
        let id: String
        let names: Set<String>
        let family: Family
        let pairedAlignment: Bool
    }
    private struct Occurrence: Hashable, Sendable {
        let row: Int
        let station: Int
    }
    private struct Edge: Sendable {
        let identity: DirectedInterval
        let family: Family
        let from: Occurrence
        let to: Occurrence
        let fromCode: String
        let toCode: String
        let start: Coordinate
        let end: Coordinate
    }
    private let rows: [Row]
    private let rowsByID: [String: [Int]]
    private let adjacency: [String: [Edge]]
    private let incompleteFamilies: Set<Family>

    public init(network: RouteNetwork) {
        let rows = network.lines.map { line in
            let names = Set([line.name, line.compactLine?.name, line.compactLine?.nameNorm]
                .compactMap { $0 }.filter { !$0.isEmpty })
            let compact = line.compactLine
            let pairedAlignment = compact?.alignmentOf != nil
                || ["up", "down"].contains(compact?.alignmentDirection ?? line.alignmentDirection ?? "")
                || compact?.alignmentPairs.contains(where: { ["up", "down"].contains($0.direction) }) == true
            return Row(id: line.lineId, names: names, family: Family(
                name: line.compactLine?.nameNorm ?? line.name ?? "",
                operatorName: line.operator ?? ""), pairedAlignment: pairedAlignment)
        }
        self.rows = rows
        let rowsByID = Dictionary(grouping: rows.indices, by: { rows[$0].id })
        self.rowsByID = rowsByID
        var adjacency: [String: [Edge]] = [:]
        var incomplete: Set<Family> = []
        var codes: Set<String> = []
        for (rowIndex, line) in network.lines.enumerated() {
            let family = rows[rowIndex].family
            if line.intervals.isEmpty { incomplete.insert(family) }
            for (offset, interval) in line.intervals.enumerated() {
                guard interval.lineID == line.lineId, codes.insert(interval.code).inserted,
                      interval.coordinates.count >= 2,
                      let start = interval.coordinates.first, let end = interval.coordinates.last,
                      interval.coordinates.allSatisfy({ $0.lon.isFinite && $0.lat.isFinite })
                else { incomplete.insert(family); continue }
                let next: Int
                let directions: [Int]
                if let compact = line.compactLine {
                    guard compact.stations.indices.contains(offset), !compact.stations.isEmpty,
                          offset + 1 < compact.stations.count || compact.isLoop,
                          compact.stations[offset].id == interval.fromStationCode,
                          compact.stations[(offset + 1) % compact.stations.count].id == interval.toStationCode
                    else { incomplete.insert(family); continue }
                    next = (offset + 1) % compact.stations.count
                    directions = RailwayDirection.allowedDirections(for: compact, intervalIndex: offset)
                } else {
                    next = line.isLoop && offset == line.intervals.count - 1 ? 0 : offset + 1
                    directions = [-1, 1]
                }
                let from = Occurrence(row: rowIndex, station: offset)
                let to = Occurrence(row: rowIndex, station: next)
                for direction in directions {
                    let forward = direction == 1
                    let edge = Edge(
                        identity: DirectedInterval(lineID: line.lineId, code: interval.code, direction: direction),
                        family: family, from: forward ? from : to, to: forward ? to : from,
                        fromCode: forward ? interval.fromStationCode : interval.toStationCode,
                        toCode: forward ? interval.toStationCode : interval.fromStationCode,
                        start: forward ? start : end, end: forward ? end : start)
                    adjacency[edge.fromCode, default: []].append(edge)
                }
            }
        }
        for indices in rowsByID.values where indices.count > 1 {
            for index in indices { incomplete.insert(rows[index].family) }
        }
        self.adjacency = adjacency
        incompleteFamilies = incomplete
    }

    /// Complete sibling rows matching the explicit family constraint, including
    /// same-name operator collisions. `nil` means the constraint is unsupported.
    /// Callers may certify these rows before inference; excluding rows could turn
    /// ambiguity into a false unique result.
    public func candidateLineIDs(
        requiredLineIDs: [String] = [], requiredLineNames: [String] = [],
        requiredOperatorNames: [String] = []
    ) -> Set<String>? {
        guard let families = matchingFamilies(
            requiredLineIDs: requiredLineIDs, requiredLineNames: requiredLineNames,
            requiredOperatorNames: requiredOperatorNames) else { return nil }
        return Set(rows.filter { families.contains($0.family) }.map(\.id))
    }

    private func matchingFamilies(
        requiredLineIDs: [String], requiredLineNames: [String], requiredOperatorNames: [String]
    ) -> Set<Family>? {
        guard !requiredLineIDs.isEmpty || !requiredLineNames.isEmpty,
              requiredLineIDs.allSatisfy({ rowsByID[$0] != nil }) else { return nil }
        let ids = Set(requiredLineIDs)
        let names = Set(requiredLineNames)
        let operators = Set(requiredOperatorNames)
        let families = Set(rows.filter { row in
            (ids.isEmpty || ids.contains(row.id))
                && (names.isEmpty || !row.names.isDisjoint(with: names))
                && (operators.isEmpty || operators.contains(row.family.operatorName))
        }.map(\.family))
        return families.isEmpty ? nil : families
    }

    /// Visits must already carry source-backed station aliases. Every visit is
    /// consumed in order, including authored repeats. No nearest-track matching,
    /// arbitrary laps, shortest-path choice, or proximity transfer is performed.
    public func resolve(
        stationCodes: [String], requiredLineIDs: [String] = [],
        requiredLineNames: [String] = [], requiredOperatorNames: [String] = [],
        maximumExaminedStates: Int = 10_000,
        isCancelled: @Sendable () -> Bool = { Task.isCancelled }
    ) -> Result {
        guard stationCodes.count >= 2, stationCodes.allSatisfy({ !$0.isEmpty }),
              maximumExaminedStates > 0, !isCancelled(),
              let families = matchingFamilies(
                requiredLineIDs: requiredLineIDs, requiredLineNames: requiredLineNames,
                requiredOperatorNames: requiredOperatorNames),
              families.isDisjoint(with: incompleteFamilies) else { return .unsupported }
        struct State {
            let previous: Edge
            let stage: Int
            let visited: Set<Occurrence>
            let visitedCodes: Set<String>
            let legs: [[DirectedInterval]]
            let incomplete: Bool
            let mayReverse: Bool
        }
        var pending: [State] = []
        var examined = 0
        var found: [[DirectedInterval]] = []
        var selection: Selection?
        var incompleteCandidate = false
        let permittedIDs = Set(requiredLineIDs)

        func append(_ edge: Edge, after state: State?) {
            let stage = state?.stage ?? 1
            let reachesVisit = edge.toCode == stationCodes[stage]
            var legs = state?.legs ?? Array(repeating: [], count: stationCodes.count - 1)
            legs[stage - 1].append(edge.identity)
            let incomplete: Bool
            if let previous = state?.previous {
                // Same row must also retain its exact station occurrence.
                let changesRow = previous.to.row != edge.from.row
                let pairedJoin = changesRow && (rows[previous.to.row].pairedAlignment || rows[edge.from.row].pairedAlignment)
                incomplete = state!.incomplete || previous.end != edge.start || pairedJoin
            } else { incomplete = false }
            if reachesVisit && stage == stationCodes.count - 1 {
                if incomplete { incompleteCandidate = true; return }
                let identity = legs.flatMap { $0 }
                if !found.contains(identity) {
                    found.append(identity)
                    selection = Selection(stationCodes: stationCodes, legIntervals: legs)
                }
                return
            }
            let nextStage = reachesVisit ? stage + 1 : stage
            // A later via cannot license a lap through already visited trunk
            // stations. Only an explicitly repeated requested visit opens a
            // return leg, which may need those same intermediate occurrences.
            let returnLeg = reachesVisit && stationCodes[..<stage].contains(stationCodes[nextStage])
            var visited = returnLeg ? [] : state?.visited ?? [edge.from]
            var visitedCodes = returnLeg ? [] : state?.visitedCodes ?? [edge.fromCode]
            visited.insert(edge.to)
            visitedCodes.insert(edge.toCode)
            pending.append(State(
                previous: edge, stage: nextStage, visited: visited, visitedCodes: visitedCodes,
                legs: legs, incomplete: incomplete,
                mayReverse: returnLeg))
        }

        // Count every examined edge, including completed and rejected paths.
        func admitsAnotherState() -> Bool {
            guard !isCancelled(), examined < maximumExaminedStates else { return false }
            examined += 1
            return true
        }
        for edge in adjacency[stationCodes[0]] ?? [] where families.contains(edge.family)
            && (permittedIDs.isEmpty || permittedIDs.contains(edge.identity.lineID)) {
            guard admitsAnotherState() else { return .unsupported }
            append(edge, after: nil)
            if found.count >= 2 { return .ambiguous }
        }
        while let state = pending.popLast() {
            guard !isCancelled() else { return .unsupported }
            for edge in adjacency[state.previous.toCode] ?? [] where edge.family == state.previous.family
                && (permittedIDs.isEmpty || permittedIDs.contains(edge.identity.lineID)) {
                guard admitsAnotherState() else { return .unsupported }
                // Changing rows can only use the same station code. A non-exact
                // endpoint remains an incomplete candidate, never a real join.
                guard edge.from.row != state.previous.to.row || edge.from == state.previous.to else { continue }
                let reachesVisit = edge.toCode == stationCodes[state.stage]
                guard reachesVisit || (!state.visited.contains(edge.to)
                    && !state.visitedCodes.contains(edge.toCode)) else { continue }
                if edge.toCode == state.previous.fromCode && !state.mayReverse { continue }
                append(edge, after: state)
                if found.count >= 2 { return .ambiguous }
            }
        }
        guard !isCancelled(), !incompleteCandidate, let selection else { return .unsupported }
        return .resolved(selection)
    }
}
