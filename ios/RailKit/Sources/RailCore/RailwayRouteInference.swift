import Foundation

/// A physical shortest-path proposal for explicit user review. This does not
/// establish a timetable, a service pattern, or the train's actual alignment.
public enum RailwayRouteInference {
    private struct Node: Hashable {
        let line: Int
        let station: Int
        var anchorIndex: Int = 0
        var sectionIndex: Int = 0
    }

    private struct Edge {
        let from: Node
        let to: Node
        let distance: Double
        let section: RouteSection
    }

    private struct Entry {
        let node: Node
        let distance: Double
        let order: Int
    }

    private struct Heap {
        var entries: [Entry] = []
        func precedes(_ a: Entry, _ b: Entry) -> Bool {
            a.distance == b.distance ? a.order < b.order : a.distance < b.distance
        }
        mutating func push(_ entry: Entry) {
            entries.append(entry)
            var index = entries.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard precedes(entries[index], entries[parent]) else { break }
                entries.swapAt(index, parent)
                index = parent
            }
        }
        mutating func pop() -> Entry? {
            guard !entries.isEmpty else { return nil }
            if entries.count == 1 { return entries.removeLast() }
            let first = entries[0]
            entries[0] = entries.removeLast()
            var index = 0
            while index * 2 + 1 < entries.count {
                let left = index * 2 + 1
                let right = left + 1
                let child = right < entries.count && precedes(entries[right], entries[left]) ? right : left
                guard precedes(entries[child], entries[index]) else { break }
                entries.swapAt(child, index)
                index = child
            }
            return first
        }
    }

    public static func choice(in train: Train, package: CompactPackage) -> RailwayRouteChoices.Choice? {
        guard train.stops.count >= 2 else { return nil }
        let codes = train.stops.compactMap(\.n02StationCode)
        guard codes.count == train.stops.count, codes.allSatisfy({ !$0.isEmpty }) else { return nil }
        let type = (train.trainType ?? "local").lowercased()
        let highSpeed = ["highspeed", "high speed", "high-speed", "shinkansen", "新幹線", "新干线", "高速"]
            .contains { type.contains($0) }
        let lines = package.lines.filter {
            let fast = $0.name.contains("新幹線") || ["high_speed", "shinkansen"].contains($0.kind ?? "")
            return fast == highSpeed && $0.serviceStatus == nil
        }.sorted { $0.id < $1.id }
        var nodesByCode: [String: [Node]] = [:]
        var adjacency: [Node: [Edge]] = [:]
        for (row, line) in lines.enumerated() {
            guard !Task.isCancelled else { return nil }
            for (index, station) in line.stations.enumerated() {
                nodesByCode[station.id, default: []].append(Node(line: row, station: index))
            }
            for (index, interval) in RailIntervalCodes.intervals(for: line).enumerated() {
                let distance = line.segments[index].distanceKm
                guard interval.coordinates.count >= 2, distance.isFinite, distance >= 0 else { continue }
                for direction in RailwayDirection.allowedDirections(for: line, intervalIndex: index).sorted() {
                    let next = (index + 1) % line.stations.count
                    let from = Node(line: row, station: direction == 1 ? index : next)
                    let to = Node(line: row, station: direction == 1 ? next : index)
                    let start = line.stations[from.station], end = line.stations[to.station]
                    adjacency[from, default: []].append(Edge(from: from, to: to, distance: distance,
                        section: RouteSection(from: start.name, to: end.name,
                            fromN02StationCode: start.id, toN02StationCode: end.id,
                            lineNames: [line.name], operatorNames: line.operator.map { [$0] },
                            lineIDs: [line.id], sectionCodes: [interval.code])))
                }
            }
        }
        guard codes.allSatisfy({ nodesByCode[$0] != nil }) else { return nil }

        // Timetable calls and physical line boundaries are separate lists.
        // Source sections may change lines at a station that is not a call.
        func endpoint(code: String?, name: String?) -> String? {
            if let code { return nodesByCode[code] == nil ? nil : code }
            let matches = Set(train.stops.filter { $0.name == name }.compactMap(\.n02StationCode))
            return matches.count == 1 ? matches.first : nil
        }
        var boundaries: [(from: String, to: String, section: RouteSection)] = []
        for section in train.routeSections ?? [] {
            guard let from = endpoint(code: section.fromN02StationCode, name: section.from),
                  let to = endpoint(code: section.toN02StationCode, name: section.to) else { return nil }
            boundaries.append((from, to, section))
        }
        let hasRouteOnlyBoundary = boundaries.contains { !codes.contains($0.from) || !codes.contains($0.to) }
        if hasRouteOnlyBoundary {
            guard boundaries.first?.from == codes.first, boundaries.last?.to == codes.last,
                  boundaries.indices.dropFirst().allSatisfy({ boundaries[$0 - 1].to == boundaries[$0].from })
            else { return nil }
        }

        // Map authored section endpoints to the recorded visit order, including
        // repeated visits. An unresolved section must not silently be discarded.
        var spans: [(Range<Int>, RouteSection)] = []
        var cursor = 0
        for section in hasRouteOnlyBoundary ? [] : (train.routeSections ?? []) {
            func matches(_ index: Int, code: String?, name: String?) -> Bool {
                if let code { return codes[index] == code }
                if let name { return train.stops[index].name == name }
                return false
            }
            guard let start = (cursor..<codes.count).first(where: {
                matches($0, code: section.fromN02StationCode, name: section.from)
            }), let end = ((start + 1)..<codes.count).first(where: {
                matches($0, code: section.toN02StationCode, name: section.to)
            }) else { return nil }
            spans.append((start..<end, section))
            cursor = start
        }

        func permits(_ edge: Edge, constraints: [RouteSection], preferred: Bool) -> Bool {
            let line = lines[edge.to.line]
            func matchesOperator(_ names: [String]) -> Bool {
                let canonical = OperatorBranding.companyLabel(line.operator)
                return !canonical.isEmpty && names.contains {
                    OperatorBranding.companyLabel($0) == canonical
                }
            }
            for section in constraints {
                if let ids = section.lineIDs, !ids.isEmpty, !ids.contains(line.id) { return false }
                if let names = section.lineNames, !names.isEmpty,
                   !names.contains(line.name), !names.contains(line.nameNorm ?? line.name) { return false }
                if let operators = section.operatorNames, !operators.isEmpty,
                   !matchesOperator(operators) { return false }
                if let sections = section.sectionCodes, !sections.isEmpty,
                   !sections.contains(edge.section.sectionCodes![0]) { return false }
            }
            if preferred {
                if let names = train.routePolicy?.preferredLineNames, !names.isEmpty,
                   !names.contains(line.name), !names.contains(line.nameNorm ?? line.name) { return false }
                if let operators = train.routePolicy?.preferredOperatorNames, !operators.isEmpty,
                   !matchesOperator(operators) { return false }
            }
            return true
        }

        func path(from starts: [Node], to code: String, constraints: [RouteSection], preferred: Bool,
                  followBoundaries: Bool = false)
            -> ([Edge], Node)? {
            var heap = Heap(), sequence = 0
            var distances: [Node: Double] = [:]
            var previous: [Node: (Node, Edge?)] = [:]
            for node in starts {
                distances[node] = 0
                heap.push(Entry(node: node, distance: 0, order: sequence)); sequence += 1
            }
            func offer(_ node: Node, distance: Double, from: Node, edge: Edge?) {
                guard distance < (distances[node] ?? .infinity) else { return }
                distances[node] = distance
                previous[node] = (from, edge)
                heap.push(Entry(node: node, distance: distance, order: sequence)); sequence += 1
            }
            while let entry = heap.pop() {
                guard !Task.isCancelled else { return nil }
                guard entry.distance == distances[entry.node] else { continue }
                let stationCode = lines[entry.node.line].stations[entry.node.station].id
                if followBoundaries {
                    // Advance independently through every authored call and
                    // every source line boundary. Neither can be bypassed.
                    if entry.node.anchorIndex + 1 < codes.count,
                       stationCode == codes[entry.node.anchorIndex + 1] {
                        var next = entry.node
                        next.anchorIndex += 1
                        offer(next, distance: entry.distance, from: entry.node, edge: nil)
                        continue
                    }
                    if entry.node.sectionIndex < boundaries.count,
                       stationCode == boundaries[entry.node.sectionIndex].to {
                        var next = entry.node
                        next.sectionIndex += 1
                        offer(next, distance: entry.distance, from: entry.node, edge: nil)
                        continue
                    }
                }
                let complete = !followBoundaries || (entry.node.anchorIndex == codes.count - 1
                    && entry.node.sectionIndex == boundaries.count)
                if stationCode == code && complete {
                    var edges: [Edge] = [], node = entry.node
                    while let (before, edge) = previous[node] {
                        if let edge { edges.append(edge) }
                        node = before
                    }
                    return (edges.reversed(), entry.node)
                }
                if followBoundaries && entry.node.sectionIndex == boundaries.count { continue }
                // Only exact physical station identity connects line rows. A
                // transfer must depart along another physical interval: zero
                // transfer cycles cannot jump between occurrences in one row.
                let physical = Node(line: entry.node.line, station: entry.node.station)
                let departures = [physical] + (nodesByCode[stationCode] ?? []).filter {
                    $0.line != entry.node.line
                }
                let activeConstraints = followBoundaries ? [boundaries[entry.node.sectionIndex].section] : constraints
                for departure in departures {
                    for edge in adjacency[departure] ?? [] where permits(edge, constraints: activeConstraints, preferred: preferred) {
                        var next = edge.to
                        next.anchorIndex = entry.node.anchorIndex
                        next.sectionIndex = entry.node.sectionIndex
                        offer(next, distance: entry.distance + edge.distance, from: entry.node, edge: edge)
                    }
                }
            }
            return nil
        }

        var visits = [RailwayRouteChoices.Visit(code: codes[0], name: train.stops[0].name)]
        var sections: [RouteSection] = []
        var starts = nodesByCode[codes[0]]!
        if hasRouteOnlyBoundary {
            guard let (edges, _) = path(from: starts, to: codes.last!, constraints: [], preferred: true, followBoundaries: true)
                ?? path(from: starts, to: codes.last!, constraints: [], preferred: false, followBoundaries: true) else { return nil }
            for edge in edges {
                sections.append(edge.section)
                let station = lines[edge.to.line].stations[edge.to.station]
                visits.append(.init(code: station.id, name: station.name))
            }
        }
        for index in hasRouteOnlyBoundary ? [] : Array(0..<(codes.count - 1)) {
            guard !Task.isCancelled else { return nil }
            let constraints = spans.filter { $0.0.contains(index) }.map(\.1)
            guard let (edges, end) = path(from: starts, to: codes[index + 1], constraints: constraints, preferred: true)
                ?? path(from: starts, to: codes[index + 1], constraints: constraints, preferred: false) else { return nil }
            for edge in edges {
                sections.append(edge.section)
                let station = lines[edge.to.line].stations[edge.to.station]
                visits.append(.init(code: station.id, name: station.name))
            }
            if edges.isEmpty { visits.append(.init(code: codes[index + 1], name: train.stops[index + 1].name)) }
            starts = [end]
        }
        guard !sections.isEmpty else { return nil }
        let sectionCodes = sections.flatMap { $0.sectionCodes ?? [] }
        // Explicit interval identity is stronger than a shortest-path guess.
        for section in train.routeSections ?? [] {
            if let expected = section.sectionCodes, !expected.isEmpty {
                guard expected.count <= sectionCodes.count,
                      (0...(sectionCodes.count - expected.count)).contains(where: {
                          Array(sectionCodes[$0..<($0 + expected.count)]) == expected
                      }) else { return nil }
            }
        }
        func unique(_ values: [String]) -> [String] {
            var seen: Set<String> = []
            return values.filter { seen.insert($0).inserted }
        }
        return RailwayRouteChoices.Choice(
            lineIDs: unique(sections.flatMap { $0.lineIDs ?? [] }),
            lineNames: unique(sections.flatMap { $0.lineNames ?? [] }),
            operatorNames: unique(sections.flatMap { $0.operatorNames ?? [] }),
            stations: visits, sectionCodes: sectionCodes, routeSections: sections)
    }
}
