import Foundation

extension RouteNetwork {
    /// A nearby parallel branch is not a platform of a station it never serves.
    /// Only reject a snap backed by that sibling's surveyed source; legacy
    /// identities and unrelated transfer platforms keep the existing behavior.
    public func permitsStationConnectorNode(stationCode: String?, point: Coordinate) -> Bool {
        guard let stationCode, let serving = stationLineIndices[stationCode] else { return true }
        func distance(_ index: Int) -> Double {
            // Only distances within 30 m can affect the 25 m + 5 m rule.
            // Reuse measured intervals and discard remote bounding boxes.
            let latMargin = 30.0 / 111_320
            let lonMargin = latMargin / max(0.01, cos(point.lat * .pi / 180))
            var best = Double.infinity
            for metric in sourceMetrics[index] where
                point.lon >= metric.minLon - lonMargin && point.lon <= metric.maxLon + lonMargin &&
                point.lat >= metric.minLat - latMargin && point.lat <= metric.maxLat + latMargin {
                if let projection = Self.project(point, onto: metric.coordinates, measures: metric.cumulative) {
                    best = min(best, projection.distance)
                }
            }
            return best
        }
        let servingDistance = serving.map(distance).min() ?? .infinity
        if servingDistance <= 5 { return true }
        for index in serving {
            for sibling in familyLineIndices[Self.familyKey(lines[index])] ?? [] where !serving.contains(sibling) {
                let siblingDistance = distance(sibling)
                if siblingDistance <= 25, siblingDistance + 5 < servingDistance { return false }
            }
        }
        return true
    }

    public struct IntervalMatch: Sendable {
        public let sectionCodes: [String]
        public let lineIDs: [String]
        public let score: Double
        public var corrected: Bool = false
    }

    struct MatchedEdge {
        let source: String
        let destination: String
        let interval: RailIntervalCodes.Interval
        let coordinates: [Coordinate]
        let weight: Double
    }

    struct PathProjection {
        let measure: Double
        let distance: Double
    }

    static func cumulativeMeasures(_ path: [Coordinate]) -> [Double] {
        var values = [0.0]
        for index in 1..<max(path.count, 1) {
            values.append(values[index - 1] + Metric.distanceMeters(path[index - 1], path[index]))
        }
        return values
    }

    /// Project within the station interval's passage through the raw path.
    /// A shared station approach may occur twice; a global nearest point can
    /// accidentally select the preceding passage through that same rail.
    static func project(
        _ point: Coordinate, onto path: [Coordinate], measures: [Double],
        low: Double? = nil, high: Double? = nil,
        zeroLengthSegments preparedZeros: [Int]? = nil
    ) -> PathProjection? {
        guard path.count >= 2 else { return nil }
        // Measures are monotonic: only the segments touching this passage
        // can contribute. Keep zero-length segments outside it as well,
        // matching the original projection's degenerate-segment behavior.
        func bound(_ value: Double, upper: Bool) -> Int {
            var left = 0, right = measures.count
            while left < right {
                let middle = (left + right) / 2
                if measures[middle] < value || (upper && measures[middle] == value) {
                    left = middle + 1
                } else {
                    right = middle
                }
            }
            return left
        }
        let start = low.map { max(0, min(path.count - 1, bound($0, upper: false) - 1)) } ?? 0
        let end = high.map { max(0, min(path.count - 1, bound($0, upper: true))) } ?? (path.count - 1)
        let zeros = low == nil && high == nil ? [] : preparedZeros
            ?? (0..<(path.count - 1)).filter { measures[$0] == measures[$0 + 1] }
        var next = start, zero = 0
        var best: PathProjection?
        let p = Metric.local(point, latitude: point.lat)
        // Merge in source order so equal-distance projections still choose
        // the first segment, including repeated station approaches.
        while next < end || zero < zeros.count {
            let rangeIndex = next < end ? next : Int.max
            let zeroIndex = zero < zeros.count ? zeros[zero] : Int.max
            let index = min(rangeIndex, zeroIndex)
            if index == rangeIndex { next += 1 }
            if index == zeroIndex { zero += 1 }
            let length = measures[index + 1] - measures[index]
            let minimum = low == nil || length == 0 ? 0 : max(0, (low! - measures[index]) / length)
            let maximum = high == nil || length == 0 ? 1 : min(1, (high! - measures[index]) / length)
            if minimum > maximum { continue }
            let a = Metric.local(path[index], latitude: point.lat)
            let b = Metric.local(path[index + 1], latitude: point.lat)
            let dx = b.x - a.x, dy = b.y - a.y
            let squared = dx * dx + dy * dy
            let ratio = squared == 0 ? 0 : max(minimum, min(maximum, ((p.x - a.x) * dx + (p.y - a.y) * dy) / squared))
            let coordinate = Coordinate(
                lon: path[index].lon + (path[index + 1].lon - path[index].lon) * ratio,
                lat: path[index].lat + (path[index + 1].lat - path[index].lat) * ratio)
            let distance = Metric.distanceMeters(point, coordinate)
            if best == nil || distance < best!.distance {
                best = PathProjection(measure: measures[index] + length * ratio, distance: distance)
            }
        }
        return best
    }

    static func shortestChain(
        adjacency: [String: [MatchedEdge]], from: String, to: String
    ) -> (edges: [MatchedEdge], score: Double)? {
        var costs = [from: 0.0]
        var previous: [String: MatchedEdge] = [:]
        var pending = [from]
        while !pending.isEmpty {
            var next = 0
            for index in pending.indices where costs[pending[index]]! < costs[pending[next]]! { next = index }
            let current = pending.remove(at: next)
            if current == to { break }
            for edge in adjacency[current] ?? [] {
                let cost = costs[current]! + edge.weight
                if cost >= (costs[edge.destination] ?? .infinity) { continue }
                costs[edge.destination] = cost
                previous[edge.destination] = edge
                if !pending.contains(edge.destination) { pending.append(edge.destination) }
            }
        }
        guard previous[to] != nil, let score = costs[to] else { return nil }
        var edges: [MatchedEdge] = []
        var current = to
        while current != from {
            guard let edge = previous[current] else { return nil }
            edges.insert(edge, at: 0)
            current = edge.source
        }
        return (edges, score)
    }

    /// Identify a complete physical interval chain from the solved path's
    /// shape and travel order. Exact shared station codes create the joins;
    /// proximity only validates existing intervals and never creates an edge.
    public func matchRouteAcrossLineRows(_ feature: RouteFeature) -> IntervalMatch? {
        guard !Task.isCancelled, feature.hints.sectionCodes.isEmpty,
              case .lineString(let raw) = feature.geometry,
              Set(raw).count >= 3,
              let from = feature.hints.fromStationCode, let to = feature.hints.toStationCode,
              from != to else { return nil }
        let maxLateral = 520.0, maxBacktrack = 600.0
        let measures = Self.cumulativeMeasures(raw)
        let zeroLengthSegments = (0..<(raw.count - 1)).filter { measures[$0] == measures[$0 + 1] }
        let hints = feature.hints
        let names = Set((hints.requiredLineNames + hints.preferredLineNames).compactMap { $0 }
            .filter { !$0.isEmpty } + hints.usedLineNames)
        let operators = Set((hints.requiredOperatorNames + hints.preferredOperatorNames).compactMap { $0 }
            .filter { !$0.isEmpty } + hints.usedOperatorNames)
        let required = Set(hints.requiredLineIDs)
        let normalizedNames = Set(lines.filter {
            names.contains($0.name ?? "") || names.contains($0.compactLine?.nameNorm ?? "")
        }.map { $0.compactLine?.nameNorm ?? $0.name ?? "" })
        let families = matchingFamilies(names: names, operators: operators, required: required, normalizedNames: normalizedNames)
        var best: IntervalMatch?
        var projections: [Coordinate: PathProjection] = [:]
        for family in families where family.count >= 2 {
            guard matchFamily(family, raw: raw, measures: measures, zeroLengthSegments: zeroLengthSegments,
                from: from, to: to, maxLateral: maxLateral, maxBacktrack: maxBacktrack,
                projections: &projections, best: &best) else { return nil }
        }
        guard let best,
              let corrected = correctRouteIntervalDirections(best.sectionCodes, from: from, to: to) else { return nil }
        let IDs = uniqueLineIDs(corrected.codes)
        if !required.isEmpty && !IDs.allSatisfy(required.contains) { return nil }
        return IntervalMatch(sectionCodes: corrected.codes, lineIDs: IDs, score: best.score, corrected: corrected.changed)
    }

    private func matchingFamilies(
        names: Set<String>, operators: Set<String>, required: Set<String>, normalizedNames: Set<String>
    ) -> [[Line]] {
        var families: [[Line]] = []
        var familyIndices: [String: Int] = [:]
        for line in lines where (names.isEmpty || normalizedNames.contains(line.compactLine?.nameNorm ?? line.name ?? ""))
            && (operators.isEmpty || operators.contains(line.operator ?? ""))
            && (required.isEmpty || required.contains(line.lineId)) {
            let key = (line.operator ?? "") + "\0" + (line.compactLine?.nameNorm ?? line.name ?? "")
            if familyIndices[key] == nil {
                familyIndices[key] = families.count
                families.append([])
            }
            families[familyIndices[key]!].append(line)
        }
        return families
    }

    private static func projectAnchor(
        _ point: Coordinate, raw: [Coordinate], measures: [Double], projections: inout [Coordinate: PathProjection]
    ) -> PathProjection? {
        if let cached = projections[point] { return cached }
        let result = Self.project(point, onto: raw, measures: measures)
        projections[point] = result
        return result
    }

    private static func appendMatchedIntervals(
        _ intervals: [RailIntervalCodes.Interval], raw: [Coordinate], measures: [Double],
        zeroLengthSegments: [Int], maxLateral: Double, maxBacktrack: Double,
        projections: inout [Coordinate: PathProjection], adjacency: inout [String: [MatchedEdge]]
    ) -> Bool {
        for interval in intervals {
            guard !Task.isCancelled else { return false }
            guard let start = Self.projectAnchor(interval.from, raw: raw, measures: measures, projections: &projections), let end = Self.projectAnchor(interval.to, raw: raw, measures: measures, projections: &projections),
                  start.distance <= maxLateral, end.distance <= maxLateral,
                  abs(end.measure - start.measure) >= 0.01 else { continue }
            let forward = start.measure < end.measure
            let coordinates = forward ? interval.coordinates : Array(interval.coordinates.reversed())
            guard coordinates.count >= 2 else { continue }
            let low = min(start.measure, end.measure) - maxBacktrack
            let high = max(start.measure, end.measure) + maxBacktrack
            guard let lateralSum = matchedLateralSum(coordinates, raw: raw, measures: measures,
                low: low, high: high, zeroLengthSegments: zeroLengthSegments,
                maxLateral: maxLateral, maxBacktrack: maxBacktrack) else { continue }
            let source = forward ? interval.fromStationCode : interval.toStationCode
            let edge = MatchedEdge(
                source: source, destination: forward ? interval.toStationCode : interval.fromStationCode,
                interval: interval, coordinates: coordinates,
                weight: max(1, abs(Metric.pathLength(coordinates) - abs(end.measure - start.measure))
                    + 2 * lateralSum / Double(coordinates.count)))
            adjacency[source, default: []].append(edge)
        }
        return true
    }

    private static func matchedLateralSum(
        _ coordinates: [Coordinate], raw: [Coordinate], measures: [Double], low: Double, high: Double,
        zeroLengthSegments: [Int], maxLateral: Double, maxBacktrack: Double
    ) -> Double? {
        var maximum = -Double.infinity, lateralSum = 0.0, accepted = true
        for point in coordinates {
            guard !Task.isCancelled,
                  let match = Self.project(point, onto: raw, measures: measures, low: low, high: high,
                                           zeroLengthSegments: zeroLengthSegments),
                  match.distance <= maxLateral, match.measure >= maximum - maxBacktrack else {
                accepted = false
                break
            }
            maximum = max(maximum, match.measure)
            lateralSum += match.distance
        }
        return accepted ? lateralSum : nil
    }

    private static func matchedSourceParts(_ edges: [MatchedEdge]) -> [[Coordinate]] {
        var sourceParts: [[Coordinate]] = []
        for edge in edges {
            if sourceParts.last?.last == edge.coordinates.first {
                sourceParts[sourceParts.count - 1] += edge.coordinates.dropFirst()
            } else {
                sourceParts.append(edge.coordinates)
            }
        }
        return sourceParts
    }

    private func matchFamily(
        _ family: [Line], raw: [Coordinate], measures: [Double], zeroLengthSegments: [Int],
        from: String, to: String, maxLateral: Double, maxBacktrack: Double,
        projections: inout [Coordinate: PathProjection], best: inout IntervalMatch?
    ) -> Bool {
        let intervals = family.flatMap(\.intervals)
        var anchors: [String: [Coordinate]] = [:]
        for interval in intervals {
            anchors[interval.fromStationCode, default: []].append(interval.from)
            anchors[interval.toStationCode, default: []].append(interval.to)
        }
        guard let origin = anchors[from], let destination = anchors[to],
              origin.contains(where: { Metric.distanceMeters(raw[0], $0) <= maxLateral }),
              destination.contains(where: { Metric.distanceMeters(raw[raw.count - 1], $0) <= maxLateral }) else { return true }
        var adjacency: [String: [MatchedEdge]] = [:]
        guard Self.appendMatchedIntervals(intervals, raw: raw, measures: measures,
            zeroLengthSegments: zeroLengthSegments, maxLateral: maxLateral, maxBacktrack: maxBacktrack,
            projections: &projections, adjacency: &adjacency) else { return false }
        guard let chain = Self.shortestChain(adjacency: adjacency, from: from, to: to) else { return true }
        var lineIDs: [String] = []
        for edge in chain.edges where !lineIDs.contains(edge.interval.lineID) { lineIDs.append(edge.interval.lineID) }
        let directional = family.contains { $0.compactLine.map {
            $0.alignmentDirection == "up" || $0.alignmentDirection == "down" || $0.permittedTraversal != nil
        } ?? false }
        guard lineIDs.count >= 2 || directional else { return true }
        let sourceParts = Self.matchedSourceParts(chain.edges)
        // Exact station identity may join different platform anchors. Keep
        // separate surveyed strokes, never manufacture a physical chord.
        let sourceMeasures = sourceParts.map(Self.cumulativeMeasures)
        guard raw.allSatisfy({ point in !Task.isCancelled && sourceParts.indices.contains { index in
            (Self.project(point, onto: sourceParts[index], measures: sourceMeasures[index])?.distance ?? .infinity) <= maxLateral
        } })
        else { return true }
        if best == nil || chain.score < best!.score {
            best = IntervalMatch(sectionCodes: chain.edges.map { $0.interval.code }, lineIDs: lineIDs, score: chain.score)
        }
        return true
    }

    func allowedDirections(for code: String) -> [Int] {
        guard let record = intervalByCode[code], let line = lines[record.lineIndex].compactLine else { return [-1, 1] }
        return RailwayDirection.allowedDirections(for: line, intervalIndex: record.intervalIndex)
    }

    func uniqueLineIDs(_ codes: [String]) -> [String] {
        var IDs: [String] = []
        for code in codes {
            if let ID = intervalByCode[code]?.interval.lineID, !IDs.contains(ID) { IDs.append(ID) }
        }
        return IDs
    }

    /// An inferred legacy path may use the opposite bore. Replace only the
    /// forbidden run between its known junctions, preserving the branch chosen
    /// by the solved geometry and the station visits on either side.
    func correctRouteIntervalDirections(
        _ codes: [String], from: String, to: String
    ) -> (codes: [String], changed: Bool)? {
        guard let chain = directionVisitChain(codes, from: from),
              chain.last?.destination == to, !chain.isEmpty else { return nil }
        if chain.allSatisfy(\.permitted) { return (codes, false) }
        var result: [String] = []
        guard appendCorrectedDirectionRuns(chain, result: &result) else { return nil }
        return verifyCorrectedDirectionChain(result, from: from, to: to)
    }

    private struct VisitEdge {
        let code: String
        let interval: RailIntervalCodes.Interval
        let source: String
        let destination: String
        let permitted: Bool
    }

    private func directionVisitChain(_ codes: [String], from: String) -> [VisitEdge]? {
        var chain: [VisitEdge] = []
        var current = from
        for code in codes {
            guard let interval = intervalByCode[code]?.interval,
                  current == interval.fromStationCode || current == interval.toStationCode else { return nil }
            let forward = current == interval.fromStationCode
            let destination = forward ? interval.toStationCode : interval.fromStationCode
            chain.append(VisitEdge(code: code, interval: interval, source: current, destination: destination,
                                   permitted: allowedDirections(for: code).contains(forward ? 1 : -1)))
            current = destination
        }
        return chain
    }

    private func appendCorrectedDirectionRuns(_ chain: [VisitEdge], result: inout [String]) -> Bool {
        var index = 0
        while index < chain.count {
            if chain[index].permitted { result.append(chain[index].code); index += 1; continue }
            let start = index
            guard let record = intervalByCode[chain[start].code] else { return false }
            let firstLine = lines[record.lineIndex]
            while index < chain.count && !chain[index].permitted { index += 1 }
            let source = chain[start].source, destination = chain[index - 1].destination
            let blocked = Self.blockedDirectionStations(chain, preserving: start..<index, source: source, destination: destination)
            let adjacency = directionReplacementAdjacency(firstLine: firstLine, blocked: blocked)
            guard let replacement = Self.shortestChain(adjacency: adjacency, from: source, to: destination) else { return false }
            result += replacement.edges.map { $0.interval.code }
        }
        return true
    }

    private static func blockedDirectionStations(
        _ chain: [VisitEdge], preserving replaced: Range<Int>, source: String, destination: String
    ) -> Set<String> {
        var blocked: Set<String> = []
        for preserved in chain.indices where !replaced.contains(preserved) {
            blocked.insert(chain[preserved].source)
            blocked.insert(chain[preserved].destination)
        }
        blocked.remove(source)
        blocked.remove(destination)
        return blocked
    }

    private func directionReplacementAdjacency(firstLine: Line, blocked: Set<String>) -> [String: [MatchedEdge]] {
        var adjacency: [String: [MatchedEdge]] = [:]
        for line in lines where line.name == firstLine.name && line.operator == firstLine.operator {
            for interval in line.intervals {
                for direction in allowedDirections(for: interval.code) {
                    let from = direction == 1 ? interval.fromStationCode : interval.toStationCode
                    let to = direction == 1 ? interval.toStationCode : interval.fromStationCode
                    if blocked.contains(from) || blocked.contains(to) { continue }
                    adjacency[from, default: []].append(MatchedEdge(
                        source: from, destination: to, interval: interval,
                        coordinates: direction == 1 ? interval.coordinates : Array(interval.coordinates.reversed()),
                        weight: Metric.pathLength(interval.coordinates)))
                }
            }
        }
        return adjacency
    }

    private func verifyCorrectedDirectionChain(
        _ result: [String], from: String, to: String
    ) -> (codes: [String], changed: Bool)? {
        var seen: Set<String> = [from]
        var current = from
        for code in result {
            guard let interval = intervalByCode[code]?.interval,
                  current == interval.fromStationCode || current == interval.toStationCode else { return nil }
            current = current == interval.fromStationCode ? interval.toStationCode : interval.fromStationCode
            guard seen.insert(current).inserted else { return nil }
        }
        return current == to ? (result, true) : nil
    }

    /// Endpoint station order is sufficient for a sourced directional window
    /// on one base row. It is insufficient to invent an arbitrary branch.
    func directedEndpointIntervals(_ feature: RouteFeature) -> IntervalMatch? {
        guard case .lineString(let raw) = feature.geometry, raw.count <= 2,
              let from = feature.hints.fromStationCode, let to = feature.hints.toStationCode,
              from != to else { return nil }
        let hints = feature.hints
        let names = Set((hints.requiredLineNames + hints.preferredLineNames).compactMap { $0 } + hints.usedLineNames)
        let operators = Set((hints.requiredOperatorNames + hints.preferredOperatorNames).compactMap { $0 } + hints.usedOperatorNames)
        for line in lines {
            guard let compact = line.compactLine, compact.alignmentOf == nil,
                  compact.alignmentPairs.contains(where: { $0.direction == "up" || $0.direction == "down" }),
                  names.isEmpty || names.contains(line.name ?? ""),
                  operators.isEmpty || operators.contains(line.operator ?? ""),
                  let start = compact.stations.firstIndex(where: { $0.id == from }),
                  let end = compact.stations.firstIndex(where: { $0.id == to }), start != end else { continue }
            let low = min(start, end), high = max(start, end)
            guard high <= line.intervals.count else { continue }
            var codes = line.intervals[low..<high].map(\.code)
            guard codes.contains(where: { allowedDirections(for: $0).count != 2 }) else { continue }
            if start > end { codes.reverse() }
            guard let corrected = correctRouteIntervalDirections(codes, from: from, to: to) else { continue }
            let IDs = uniqueLineIDs(corrected.codes)
            guard hints.requiredLineIDs.isEmpty || IDs.allSatisfy(hints.requiredLineIDs.contains) else { continue }
            return IntervalMatch(sectionCodes: corrected.codes, lineIDs: IDs, score: 0, corrected: corrected.changed)
        }
        return nil
    }
}
