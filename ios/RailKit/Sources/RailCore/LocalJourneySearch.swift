import Foundation

/// Offline physical route proposals, ordered by distance, then row changes.
/// This searches surveyed intervals, not dated passenger services. Transfers
/// at a shared station group are reviewable candidates, not certification
/// of physical junction connectivity.
public enum LocalJourneySearch {
    public struct Result: Sendable {
        public let choices: [RailwayRouteChoices.Choice]
        public let isTruncated: Bool
        /// compact-v1 provides interval order but no audited network junctions
        /// or declaration that every possible physical route is represented.
        public let topologyIsComplete: Bool
        public var hasAmbiguity: Bool { choices.count > 1 }
        public var uniqueChoice: RailwayRouteChoices.Choice? {
            guard topologyIsComplete, !isTruncated, choices.count == 1 else { return nil }
            return choices.first
        }
    }

    public static func choices(
        package: CompactPackage, originCode: String, destinationCode: String,
        trainType: String? = nil, excludingStationCodes: Set<String> = [],
        requiredStationCodes: [String] = [], stationAliases: [String: String] = [:],
        maximumChoices: Int = 3, maximumExpansions: Int = 50_000,
        continuation: ((_ from: CompactPackage.Line, _ to: CompactPackage.Line, _ stationCode: String) -> Bool)? = nil,
        originLineIDs: Set<String>? = nil, destinationLineIDs: Set<String>? = nil
    ) -> [RailwayRouteChoices.Choice] {
        search(package: package, originCode: originCode, destinationCode: destinationCode,
               trainType: trainType, excludingStationCodes: excludingStationCodes,
               requiredStationCodes: requiredStationCodes, stationAliases: stationAliases,
               maximumChoices: maximumChoices, maximumExpansions: maximumExpansions,
               continuation: continuation, originLineIDs: originLineIDs,
               destinationLineIDs: destinationLineIDs).choices
    }

    /// Keeps at most `maximumChoices` settled labels per station occurrence and anchor progress, and
    /// never expands more than `maximumExpansions` labels. This bounded search
    /// returns useful short alternatives rather than enumerating every path.
    /// The first result is a shortest directed route; the alternative set is
    /// deliberately bounded and is not an exhaustive list of simple paths.
    public static func search(
        package: CompactPackage, originCode: String, destinationCode: String,
        trainType: String? = nil, excludingStationCodes: Set<String> = [],
        requiredStationCodes: [String] = [], stationAliases: [String: String] = [:],
        maximumChoices: Int = 3, maximumExpansions: Int = 50_000,
        continuation: ((_ from: CompactPackage.Line, _ to: CompactPackage.Line, _ stationCode: String) -> Bool)? = nil,
        originLineIDs: Set<String>? = nil, destinationLineIDs: Set<String>? = nil
    ) -> Result {
        let packageCodes = Set(package.lines.flatMap { $0.stations.map(\.id) })
        func canonical(_ code: String) -> String {
            packageCodes.contains(code) ? code : stationAliases[code] ?? code
        }
        let originalAnchors = requiredStationCodes.isEmpty ? [originCode, destinationCode] : requiredStationCodes
        let originCode = canonical(originCode), destinationCode = canonical(destinationCode)
        let requiredStationCodes = requiredStationCodes.map(canonical)
        let protectedCodes = Set(requiredStationCodes + [originCode, destinationCode])
        let excludingStationCodes = Set(excludingStationCodes.map(canonical)).subtracting(protectedCodes)
        func restoreAnchors(_ input: RailwayRouteChoices.Choice) -> RailwayRouteChoices.Choice {
            var choice = input
            var anchor = 0
            for index in choice.stations.indices {
                guard anchor < originalAnchors.count,
                      choice.stations[index].code == canonical(originalAnchors[anchor]) else { continue }
                choice.stations[index].code = originalAnchors[anchor]
                anchor += 1
            }
            for index in choice.routeSections.indices {
                choice.routeSections[index].fromN02StationCode = choice.stations[index].code
                choice.routeSections[index].toN02StationCode = choice.stations[index + 1].code
            }
            // Choice identity remains the ordered physical section-code chain.
            return choice
        }
        func result(_ choices: [RailwayRouteChoices.Choice] = [], truncated: Bool = false) -> Result {
            Result(choices: choices.map(restoreAnchors), isTruncated: truncated, topologyIsComplete: false)
        }
        guard maximumChoices > 0, maximumExpansions > 0 else { return result(truncated: true) }
        guard originCode != destinationCode,
              !excludingStationCodes.contains(originCode),
              !excludingStationCodes.contains(destinationCode) else { return result() }
        let anchors = requiredStationCodes.isEmpty ? [originCode, destinationCode] : requiredStationCodes
        guard anchors.first == originCode, anchors.last == destinationCode,
              anchors.allSatisfy({ !excludingStationCodes.contains($0) }) else { return result() }
        let limit = min(maximumChoices, 3)
        let budget = min(maximumExpansions, 200_000)
        let lines = package.lines.filter { permits($0, trainType: trainType) }
            .sorted { $0.id < $1.id }
        var nodes: [Node] = []
        var edges: [Edge] = []
        var outgoing: [String: [Int]] = [:]
        for (row, line) in lines.enumerated() {
            guard !Task.isCancelled else { return result(truncated: true) }
            let base = nodes.count
            nodes += line.stations.map { Node(row: row, station: $0) }
            let intervals = RailIntervalCodes.intervals(for: line)
            for (index, interval) in intervals.enumerated() {
                guard line.segments.indices.contains(index), interval.coordinates.count >= 2,
                      !excludingStationCodes.contains(interval.fromStationCode),
                      !excludingStationCodes.contains(interval.toStationCode) else { continue }
                let distance = line.segments[index].distanceKm
                guard distance.isFinite, distance >= 0 else { continue }
                let next = (index + 1) % line.stations.count
                for direction in RailwayDirection.allowedDirections(for: line, intervalIndex: index) {
                    let from = base + (direction == 1 ? index : next)
                    let to = base + (direction == 1 ? next : index)
                    outgoing[nodes[from].station.id, default: []].append(edges.count)
                    edges.append(Edge(from: from, to: to, row: row,
                                      code: interval.code, distance: distance))
                }
            }
        }
        guard outgoing[originCode] != nil else { return result() }
        // A cheap directed reachability pass avoids searching disconnected
        // national components. Occurrence constraints are applied below.
        var predecessors: [String: [String]] = [:]
        for edge in edges {
            predecessors[nodes[edge.to].station.id, default: []].append(nodes[edge.from].station.id)
        }
        var reachable: Set<String> = [destinationCode]
        var pending = [destinationCode]
        while let code = pending.popLast() {
            for previous in predecessors[code] ?? [] where reachable.insert(previous).inserted {
                pending.append(previous)
            }
        }
        guard reachable.contains(originCode) else { return result() }
        var records: [Record] = []
        var heap = Heap()
        var settled = Array(repeating: 0, count: nodes.count * anchors.count)
        var results: [RailwayRouteChoices.Choice] = []
        var seen: Set<String> = []
        var expansions = 0
        var truncated = false
        // Queue storage also has a hard bound; a large interchange cannot
        // consume unbounded memory before the expansion budget is reached.
        let queueBudget = budget * 8
        func enqueue(edgeIndex: Int, parent: Int?) {
            guard records.count < queueBudget else { truncated = true; return }
            let edge = edges[edgeIndex]
            let previous = parent.map { records[$0] }
            var anchorIndex = previous?.anchorIndex ?? 0
            if anchorIndex + 1 < anchors.count, nodes[edge.to].station.id == anchors[anchorIndex + 1] {
                anchorIndex += 1
            }
            let record = Record(edge: edgeIndex, parent: parent, anchorIndex: anchorIndex,
                                distance: (previous?.distance ?? 0) + edge.distance,
                                transfers: (previous?.transfers ?? 0)
                                    + (previous.map { edges[$0.edge].row != edge.row ? 1 : 0 } ?? 0),
                                hops: (previous?.hops ?? 0) + 1)
            let id = records.count
            records.append(record)
            heap.push(Entry(id: id, distance: record.distance,
                            transfers: record.transfers, hops: record.hops))
        }
        for edge in outgoing[originCode] ?? [] where reachable.contains(nodes[edges[edge].to].station.id) {
            guard originLineIDs?.contains(lines[edges[edge].row].id) ?? true else { continue }
            enqueue(edgeIndex: edge, parent: nil)
        }
        let operatorCodes = lines.map { line in
            line.operator.map { Set(OperatorIdentity.codes(forJoined: $0)) } ?? []
        }
        while !heap.items.isEmpty {
            guard expansions < budget, results.count < limit else { truncated = true; break }
            guard let entry = heap.pop() else { break }
            guard !Task.isCancelled else { return result(results, truncated: true) }
            let record = records[entry.id]
            let arrived = edges[record.edge]
            let settledIndex = arrived.to * anchors.count + record.anchorIndex
            guard settled[settledIndex] < limit else { truncated = true; continue }
            settled[settledIndex] += 1
            expansions += 1
            let code = nodes[arrived.to].station.id
            if code == destinationCode && record.anchorIndex == anchors.count - 1,
               destinationLineIDs?.contains(lines[arrived.row].id) ?? true {
                var path: [Edge] = []
                var cursor: Int? = entry.id
                while let id = cursor {
                    path.append(edges[records[id].edge])
                    cursor = records[id].parent
                }
                let choice = makeChoice(path: Array(path.reversed()), nodes: nodes, lines: lines)
                if seen.insert(choice.id).inserted { results.append(choice) }
                continue
            }
            for edgeIndex in outgoing[code] ?? [] {
                let edge = edges[edgeIndex]
                guard reachable.contains(nodes[edge.to].station.id) else { continue }
                // Continuing one row must use the actual occurrence reached.
                // A–B–C–B–D therefore cannot silently become A–B–D.
                if edge.row == arrived.row {
                    guard edge.from == arrived.to else { continue }
                } else {
                    guard continuation?(lines[arrived.row], lines[edge.row], code)
                        ?? transferAllowed(lines[arrived.row], lines[edge.row],
                                           fromCodes: operatorCodes[arrived.row],
                                           toCodes: operatorCodes[edge.row]) else { continue }
                }
                // Forbid revisiting an occurrence, including a transfer's
                // departure occurrence; repeated IDs at other positions remain.
                var cursor: Int? = entry.id
                var cycle = false
                while let id = cursor {
                    let prior = edges[records[id].edge]
                    if prior.from == edge.to || prior.to == edge.to
                        || (edge.row != arrived.row && (prior.from == edge.from || prior.to == edge.from)) {
                        cycle = true
                        break
                    }
                    cursor = records[id].parent
                }
                if !cycle { enqueue(edgeIndex: edgeIndex, parent: entry.id) }
            }
        }
        return result(results, truncated: truncated)
    }

    /// Resolve line-instance codes through official station-group identity only.
    public static func stationAliases(
        for codes: [String], package: CompactPackage, groupCode: (String) -> String?
    ) -> [String: String] {
        let packageCodes = Set(package.lines.flatMap { $0.stations.map(\.id) })
        var members: [String: Set<String>] = [:]
        for code in packageCodes {
            if let group = groupCode(code) { members[group, default: []].insert(code) }
        }
        var aliases: [String: String] = [:]
        for code in codes where !packageCodes.contains(code) {
            guard let group = groupCode(code) else { continue }
            if packageCodes.contains(group) {
                aliases[code] = group
            } else if let candidates = members[group], candidates.count == 1 {
                aliases[code] = candidates.first
            }
        }
        return aliases
    }

    private static func transferAllowed(
        _ from: CompactPackage.Line, _ to: CompactPackage.Line,
        fromCodes: Set<String>, toCodes: Set<String>
    ) -> Bool {
        if let a = from.operator, let b = to.operator, !fromCodes.isEmpty {
            let sameOperator = toCodes.isEmpty
                ? OperatorBranding.companyLabel(a) == OperatorBranding.companyLabel(b)
                : !fromCodes.isDisjoint(with: toCodes)
            if sameOperator { return true }
        }
        if let kind = from.kind, kind == to.kind { return true }
        let throughKinds: Set<String> = ["jr_conventional", "private", "third_sector", "subway"]
        return throughKinds.contains(from.kind ?? "") && throughKinds.contains(to.kind ?? "")
    }

    private struct Node {
        let row: Int
        let station: CompactPackage.Station
    }
    private struct Edge {
        let from: Int
        let to: Int
        let row: Int
        let code: String
        let distance: Double
    }
    private struct Record {
        let edge: Int
        let parent: Int?
        let anchorIndex: Int
        let distance: Double
        let transfers: Int
        let hops: Int
    }
    private struct Entry {
        let id: Int
        let distance: Double
        let transfers: Int
        let hops: Int
        func precedes(_ other: Entry) -> Bool {
            if distance != other.distance { return distance < other.distance }
            if transfers != other.transfers { return transfers < other.transfers }
            if hops != other.hops { return hops < other.hops }
            return id < other.id
        }
    }
    private struct Heap {
        var items: [Entry] = []
        mutating func push(_ entry: Entry) {
            items.append(entry)
            var index = items.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard items[index].precedes(items[parent]) else { break }
                items.swapAt(index, parent)
                index = parent
            }
        }
        mutating func pop() -> Entry? {
            guard !items.isEmpty else { return nil }
            let first = items[0]
            let last = items.removeLast()
            if items.isEmpty { return first }
            items[0] = last
            var index = 0
            while index * 2 + 1 < items.count {
                let left = index * 2 + 1, right = left + 1
                let child = right < items.count && items[right].precedes(items[left]) ? right : left
                guard items[child].precedes(items[index]) else { break }
                items.swapAt(index, child)
                index = child
            }
            return first
        }
    }

    private static func makeChoice(
        path: [Edge], nodes: [Node], lines: [CompactPackage.Line]
    ) -> RailwayRouteChoices.Choice {
        let first = nodes[path[0].from].station
        var visits = [RailwayRouteChoices.Visit(code: first.id, name: first.name)]
        var sections: [RouteSection] = []
        var lineIDs: [String] = []
        for edge in path {
            let from = nodes[edge.from].station, to = nodes[edge.to].station
            let line = lines[edge.row]
            visits.append(.init(code: to.id, name: to.name))
            if lineIDs.last != line.id { lineIDs.append(line.id) }
            sections.append(RouteSection(
                from: from.name, to: to.name,
                fromN02StationCode: from.id, toN02StationCode: to.id,
                lineNames: [line.name], operatorNames: line.operator.map { [$0] },
                lineIDs: [line.id], sectionCodes: [edge.code]))
        }
        func unique(_ values: [String]) -> [String] {
            var seen: Set<String> = []
            return values.filter { seen.insert($0).inserted }
        }
        return .init(lineIDs: lineIDs, lineNames: unique(sections.flatMap { $0.lineNames ?? [] }),
                     operatorNames: unique(sections.flatMap { $0.operatorNames ?? [] }),
                     stations: visits, sectionCodes: path.map(\.code), routeSections: sections)
    }

    private static func permits(_ line: CompactPackage.Line, trainType: String?) -> Bool {
        let type = (trainType ?? "local").lowercased()
        let highSpeed = ["highspeed", "high speed", "high-speed", "shinkansen", "新幹線", "新干线", "高速"]
            .contains { type.contains($0) }
        let highSpeedLine = line.name.contains("新幹線") || ["high_speed", "shinkansen"].contains(line.kind ?? "")
        return line.isTraversableForSearch && (highSpeed ? highSpeedLine : !highSpeedLine)
    }
}


extension CompactPackage.Line {
    /// Statuses describe service, not track; search candidates still require confirmation.
    /// Only a whole line replaced by buses is excluded from physical route search.
    var isTraversableForSearch: Bool { serviceStatus != "substitute_bus" }
}
