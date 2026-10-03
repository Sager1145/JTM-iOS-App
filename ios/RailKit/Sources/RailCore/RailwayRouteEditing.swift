import Foundation

/// Guided corrections preserve visits by physical code and traversal order.
/// A plan with conflicts is a proposal that requires explicit confirmation.
public enum RailwayRouteEditing {
    public struct Decision: Identifiable, Equatable, Sendable {
        public var id: String
        public var originCode: String
        public var originName: String
        public var destinationCode: String
        public var destinationName: String
        public var options: [RailwayRouteChoices.Choice]
    }

    public struct Plan: Equatable, Sendable {
        public var updatedTrain: Train
        public var insertedStops: [Stop]
        public var removedStops: [Stop]
        public var conflictingStops: [Stop]
        public var requiresConfirmation: Bool { !conflictingStops.isEmpty }
        public var undo: Undo
    }

    /// Restores the affected visits and sections without replacing the Train.
    /// Returns nil if that route span has subsequently changed.
    public struct Undo: Equatable, Sendable {
        fileprivate var before: [Stop]
        fileprivate var after: [Stop]
        fileprivate var beforeSections: [RouteSection]
        fileprivate var afterSections: [RouteSection]
        /// Exact source constraints may include boundaries absent from calls.
        fileprivate var originalRouteSections: [RouteSection]?

        public func restore(in train: Train) -> Train? {
            guard let range = RailwayRouteEditing.range(
                in: train.stops, origin: after[0].n02StationCode!,
                destination: after[after.count - 1].n02StationCode!,
                fromVisitID: after[0].routeEditing?.visitID,
                toVisitID: after[after.count - 1].routeEditing?.visitID),
                Array(train.stops[range]) == after else { return nil }
            var sections = RailwayRouteEditing.sections(for: train)
            guard Array(sections[range.lowerBound..<range.upperBound]) == afterSections else { return nil }
            sections.replaceSubrange(range.lowerBound..<range.upperBound, with: beforeSections)
            var result = train
            result.stops.replaceSubrange(range, with: before)
            result.routeSections = range.lowerBound == 0 && range.upperBound == train.stops.count - 1
                ? originalRouteSections : sections
            return result
        }
    }

    /// Give legacy authored visits persistent identities before presenting an
    /// editor. Repeated station visits each receive their own identity.
    public static func preparing(_ train: Train) -> Train {
        var result = train
        for index in result.stops.indices where result.stops[index].routeEditing == nil {
            result.stops[index].routeEditing = Stop.RouteEditingMetadata()
        }
        return result
    }

    /// Split at common anchors that occur in the same order on every path.
    /// Equal station lists can still diverge on different physical intervals.
    public static func decisions(choices: [RailwayRouteChoices.Choice]) -> [Decision] {
        let candidates = choices.filter(valid)
        guard let first = candidates.first, candidates.count > 1,
              candidates.allSatisfy({ $0.stations.first?.code == first.stations.first?.code
                  && $0.stations.last?.code == first.stations.last?.code }) else { return [] }
        var anchors = first.stations.map(\.code)
        for candidate in candidates.dropFirst() {
            anchors = commonPairs(anchors, candidate.stations.map(\.code)).map { anchors[$0.0] }
        }
        guard anchors.count >= 2 else { return [] }
        var result: [Decision] = []
        var positions = Array(repeating: 0, count: candidates.count)
        for anchorIndex in 0..<(anchors.count - 1) {
            let origin = anchors[anchorIndex]
            let destination = anchors[anchorIndex + 1]
            var options: [RailwayRouteChoices.Choice] = []
            for index in candidates.indices {
                let candidate = candidates[index]
                guard let start = candidate.stations.indices.dropFirst(positions[index])
                    .first(where: { candidate.stations[$0].code == origin }),
                    let end = candidate.stations.indices.dropFirst(start + 1)
                    .first(where: { candidate.stations[$0].code == destination }) else { continue }
                positions[index] = end
                let option = slice(candidate, from: start, to: end)
                if !options.contains(where: { $0.sectionCodes == option.sectionCodes }) {
                    options.append(option)
                }
            }
            guard options.count > 1, let option = options.first else { continue }
            result.append(Decision(
                id: "\(anchorIndex):\(origin)>\(destination)",
                originCode: origin, originName: option.stations[0].name,
                destinationCode: destination, destinationName: option.stations.last!.name,
                options: options))
        }
        return result
    }

    /// Use visit IDs for an explicitly selected boundary span. Without IDs,
    /// both endpoints must occur uniquely; names never select a visit.
    public static func plan(
        train: Train, choice: RailwayRouteChoices.Choice,
        fromVisitID: UUID? = nil, toVisitID: UUID? = nil
    ) -> Plan? {
        guard valid(choice), let origin = choice.stations.first?.code,
              let destination = choice.stations.last?.code, origin != destination,
              let range = range(in: train.stops, origin: origin, destination: destination,
                                fromVisitID: fromVisitID, toVisitID: toVisitID) else { return nil }
        let oldStops = Array(train.stops[range])
        let oldInterior = Array(oldStops.dropFirst().dropLast())
        let newInterior = Array(choice.stations.dropFirst().dropLast())
        let matches = commonPairs(oldInterior.map { $0.n02StationCode ?? "" }, newInterior.map(\.code))
        let retained = Dictionary(uniqueKeysWithValues: matches.map { ($0.1, oldInterior[$0.0]) })
        let retainedIndices = Set(matches.map(\.0))
        let removed = oldInterior.indices.filter { !retainedIndices.contains($0) }.map { oldInterior[$0] }
        let conflicts = removed.filter { !isUntouchedGenerated($0) }
        var inserted: [Stop] = []
        var replacement = [oldStops[0]]
        var occupiedVisitIDs = Set(train.stops.indices.compactMap { index -> UUID? in
            guard index <= range.lowerBound || index >= range.upperBound
                || retainedIndices.contains(index - range.lowerBound - 1) else { return nil }
            return train.stops[index].routeEditing?.visitID
        })
        var occurrences: [String: Int] = [:]
        for (index, station) in newInterior.enumerated() {
            let occurrence = occurrences[station.code, default: 0]
            occurrences[station.code] = occurrence + 1
            if let stop = retained[index] { replacement.append(stop); continue }
            let identity = [train.id,
                            oldStops[0].routeEditing?.visitID.uuidString ?? "\(range.lowerBound):\(origin)",
                            oldStops.last!.routeEditing?.visitID.uuidString ?? "\(range.upperBound):\(destination)",
                            station.code, String(occurrence)].joined(separator: "|")
            // An order-preserved visit can move from the second occurrence to
            // the first. Reserve its old ID before minting the new second one.
            var visitID = stableUUID(identity)
            var collision = 0
            while !occupiedVisitIDs.insert(visitID).inserted {
                collision += 1
                visitID = stableUUID(identity + "|collision:\(collision)")
            }
            let stop = Stop(
                name: station.name, n02StationCode: station.code,
                stopType: "pass_through", rideSegment: oldStops[0].rideSegment,
                routeEditing: .init(visitID: visitID,
                                    generatedBy: generatedMarker(code: station.code, name: station.name, rideSegment: oldStops[0].rideSegment)))
            inserted.append(stop)
            replacement.append(stop)
        }
        replacement.append(oldStops.last!)
        let existingSections = sections(for: train)
        let oldSections = Array(existingSections[range.lowerBound..<range.upperBound])
        var selectedSections = choice.routeSections
        // Carry service labels between consecutive retained anchors. Expanding
        // B–D into B–C–D keeps that portion's number even if A–B uses another.
        var anchorPairs = [(0, 0)]
        anchorPairs += matches.map { ($0.1 + 1, $0.0 + 1) }
        anchorPairs.append((replacement.count - 1, oldStops.count - 1))
        for anchorIndex in 0..<(anchorPairs.count - 1) {
            let start = anchorPairs[anchorIndex]
            let end = anchorPairs[anchorIndex + 1]
            let labels = Array(oldSections[start.1..<end.1])
            let number = uniform(labels.map(\.number))
            let name = uniform(labels.map(\.name))
            for index in start.0..<end.0 {
                selectedSections[index].number = selectedSections[index].number ?? number
                selectedSections[index].name = selectedSections[index].name ?? name
            }
        }
        var updatedSections = existingSections
        updatedSections.replaceSubrange(range.lowerBound..<range.upperBound, with: selectedSections)
        var updated = train
        updated.stops.replaceSubrange(range, with: replacement)
        updated.routeSections = updatedSections
        return Plan(
            updatedTrain: updated, insertedStops: inserted,
            removedStops: removed.filter(isUntouchedGenerated), conflictingStops: conflicts,
            undo: Undo(before: oldStops, after: replacement, beforeSections: oldSections,
                       afterSections: selectedSections, originalRouteSections: train.routeSections))
    }

    public static func isUntouchedGenerated(_ stop: Stop) -> Bool {
        guard let code = stop.n02StationCode,
              stop.routeEditing?.generatedBy == generatedMarker(code: code, name: stop.name, rideSegment: stop.rideSegment) else { return false }
        return stop.stopType == "pass_through" && stop.platformNumber == nil
            && stop.arrival == nil && stop.departure == nil
            && stop.actualArrival == nil && stop.actualDeparture == nil
    }

    private static func generatedMarker(code: String, name: String, rideSegment: Bool) -> String {
        "railway-route:\(rideSegment):\(code.utf8.count):\(code):\(name)"
    }

    private static func range(
        in stops: [Stop], origin: String, destination: String,
        fromVisitID: UUID?, toVisitID: UUID?
    ) -> ClosedRange<Int>? {
        func endpoint(_ code: String, _ id: UUID?) -> Int? {
            let matches = stops.indices.filter {
                stops[$0].n02StationCode == code && (id == nil || stops[$0].routeEditing?.visitID == id)
            }
            return matches.count == 1 ? matches[0] : nil
        }
        guard let start = endpoint(origin, fromVisitID), let end = endpoint(destination, toVisitID),
              start < end else { return nil }
        return start...end
    }

    private static func valid(_ choice: RailwayRouteChoices.Choice) -> Bool {
        guard choice.stations.count > 1, choice.routeSections.count == choice.stations.count - 1,
              !choice.sectionCodes.isEmpty,
              choice.routeSections.flatMap({ $0.sectionCodes ?? [] }) == choice.sectionCodes,
              choice.stations.first?.code != choice.stations.last?.code else { return false }
        return choice.routeSections.indices.allSatisfy { index in
            let section = choice.routeSections[index]
            return section.fromN02StationCode == choice.stations[index].code
                && section.toN02StationCode == choice.stations[index + 1].code
                && section.sectionCodes?.isEmpty == false
        }
    }

    private static func slice(_ choice: RailwayRouteChoices.Choice, from start: Int, to end: Int)
        -> RailwayRouteChoices.Choice {
        let sections = Array(choice.routeSections[start..<end])
        var lineIDs: [String] = []
        for id in sections.flatMap({ $0.lineIDs ?? [] }) where lineIDs.last != id { lineIDs.append(id) }
        func unique(_ values: [String]) -> [String] {
            var seen: Set<String> = []
            return values.filter { seen.insert($0).inserted }
        }
        return RailwayRouteChoices.Choice(
            lineIDs: lineIDs, lineNames: unique(sections.flatMap { $0.lineNames ?? [] }),
            operatorNames: unique(sections.flatMap { $0.operatorNames ?? [] }),
            stations: Array(choice.stations[start...end]),
            sectionCodes: sections.flatMap { $0.sectionCodes ?? [] }, routeSections: sections)
    }

    /// Preserve aligned sections and uniquely identified shifted pairs without
    /// export normalization or station-name matching. Repeated endpoint pairs
    /// need a fully aligned list to retain their occurrence-specific labels.
    private static func sections(for train: Train) -> [RouteSection] {
        let source = train.routeSections ?? []
        let indices = 0..<max(0, train.stops.count - 1)
        func matches(_ section: RouteSection, _ index: Int) -> Bool {
            section.fromN02StationCode == train.stops[index].n02StationCode
                && section.toN02StationCode == train.stops[index + 1].n02StationCode
        }
        let aligned = source.count == indices.count
            && indices.allSatisfy { matches(source[$0], $0) }
        return indices.map { index in
            let from = train.stops[index], to = train.stops[index + 1]
            if aligned { return source[index] }
            if let fromCode = from.n02StationCode, let toCode = to.n02StationCode {
                let existing = source.filter { matches($0, index) }
                let occurrences = indices.filter {
                    train.stops[$0].n02StationCode == fromCode
                        && train.stops[$0 + 1].n02StationCode == toCode
                }
                if existing.count == 1 && occurrences.count == 1 { return existing[0] }
            }
            return RouteSection(from: from.name, to: to.name,
                                fromN02StationCode: from.n02StationCode,
                                toN02StationCode: to.n02StationCode)
        }
    }

    private static func uniform(_ values: [String?]) -> String? {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// LCS maps repeated physical codes by occurrence and traversal order.
    private static func commonPairs(_ lhs: [String], _ rhs: [String]) -> [(Int, Int)] {
        var lengths = Array(repeating: Array(repeating: 0, count: rhs.count + 1), count: lhs.count + 1)
        for i in lhs.indices.reversed() {
            for j in rhs.indices.reversed() {
                lengths[i][j] = lhs[i] == rhs[j] ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = [], i = 0, j = 0
        while i < lhs.count && j < rhs.count {
            if lhs[i] == rhs[j] { pairs.append((i, j)); i += 1; j += 1 }
            else if lengths[i + 1][j] >= lengths[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        return pairs
    }

    private static func stableUUID(_ text: String) -> UUID {
        func hash(_ seed: UInt64) -> UInt64 {
            text.utf8.reduce(seed) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }
        let bytes = [hash(14_695_981_039_346_656_037), hash(7_809_847_782_465_536_322)]
            .flatMap { value in (0..<8).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           (bytes[6] & 0x0f) | 0x50, bytes[7], (bytes[8] & 0x3f) | 0x80,
                           bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
