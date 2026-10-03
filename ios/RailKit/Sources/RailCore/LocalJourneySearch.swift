import Foundation

/// Offline physical route proposals, ordered by distance, then row changes.
/// This searches surveyed intervals, not dated passenger services. Transfers
/// require an exact shared station ID; compact station groups are not decoded.
public enum LocalJourneySearch {
    /// Keeps at most `maximumChoices` settled labels per station occurrence and
    /// never expands more than `maximumExpansions` labels. This bounded search
    /// returns useful short alternatives rather than enumerating every path.
    /// The first result is a shortest directed route; the alternative set is
    /// deliberately bounded and is not an exhaustive list of simple paths.
    public static func choices(
        package: CompactPackage, originCode: String, destinationCode: String,
        trainType: String? = nil, excludingStationCodes: Set<String> = [],
        maximumChoices: Int = 3, maximumExpansions: Int = 50_000
    ) -> [RailwayRouteChoices.Choice] {
        guard originCode != destinationCode, maximumChoices > 0, maximumExpansions > 0,
              !excludingStationCodes.contains(originCode),
              !excludingStationCodes.contains(destinationCode) else { return [] }
        let limit = min(maximumChoices, 3)
        let budget = min(maximumExpansions, 200_000)
        let lines = package.lines.filter { permits($0, trainType: trainType) }
            .sorted { $0.id < $1.id }
        var nodes: [Node] = []
        var edges: [Edge] = []
        var outgoing: [String: [Int]] = [:]
        for (row, line) in lines.enumerated() {
            guard !Task.isCancelled else { return [] }
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
        guard outgoing[originCode] != nil else { return [] }
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
        guard reachable.contains(originCode) else { return [] }
        var records: [Record] = []
        var heap = Heap()
        var settled = Array(repeating: 0, count: nodes.count)
        var results: [RailwayRouteChoices.Choice] = []
        var seen: Set<String> = []
        var expansions = 0
        // Queue storage also has a hard bound; a large interchange cannot
        // consume unbounded memory before the expansion budget is reached.
        let queueBudget = budget * 8
        func enqueue(edgeIndex: Int, parent: Int?) {
            guard records.count < queueBudget else { return }
            let edge = edges[edgeIndex]
            let previous = parent.map { records[$0] }
            let record = Record(edge: edgeIndex, parent: parent,
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
            enqueue(edgeIndex: edge, parent: nil)
        }
        while let entry = heap.pop(), expansions < budget, results.count < limit {
            guard !Task.isCancelled else { return [] }
            let record = records[entry.id]
            let arrived = edges[record.edge]
            guard settled[arrived.to] < limit else { continue }
            settled[arrived.to] += 1
            expansions += 1
            let code = nodes[arrived.to].station.id
            if code == destinationCode {
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
                guard reachable.contains(nodes[edge.to].station.id), settled[edge.to] < limit else { continue }
                // Continuing one row must use the actual occurrence reached.
                // A–B–C–B–D therefore cannot silently become A–B–D.
                guard edge.row != arrived.row || edge.from == arrived.to else { continue }
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
        return results
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
        return highSpeed ? highSpeedLine : !highSpeedLine
    }
}
