public enum TripRoutePlanner {
    public struct Request: Sendable, Equatable {
        public var originCode: String
        public var destinationCode: String
        public var trainType: String?
        public var operatorName: String?
        public var stationAliases: [String: String]
        public var originLineID: String?
        public var destinationLineID: String?

        public init(originCode: String, destinationCode: String, trainType: String? = nil,
                    operatorName: String? = nil, stationAliases: [String: String] = [:],
                    originLineID: String? = nil, destinationLineID: String? = nil) {
            self.originCode = originCode
            self.destinationCode = destinationCode
            self.trainType = trainType
            self.operatorName = operatorName
            self.stationAliases = stationAliases
            self.originLineID = originLineID
            self.destinationLineID = destinationLineID
        }
    }

    public struct Junction: Sendable, Equatable, Hashable {
        public var stationCode: String
        public var stationName: String
        public var fromLineID: String
        public var fromLineName: String
        public var toLineID: String
        public var toLineName: String
        public var link: TripConnectivity.Link
    }

    public struct Corridor: Identifiable, Sendable, Equatable {
        public var id: String
        public var choice: RailwayRouteChoices.Choice
        public var lineNames: [String]
        public var operatorNames: [String]
        public var junctions: [Junction]
        public var distanceKm: Double
        public var passStationCount: Int
    }

    public enum Outcome: Sendable, Equatable {
        case corridors([Corridor])
        case disconnected([Junction])
        case noRoute
        case noCompanyRoute(String)
        case sameStation
        case truncated
    }

    public static func plan(package: CompactPackage, request: Request) -> Outcome {
        guard request.originCode != request.destinationCode else { return .sameStation }
        let packageCodes = Set(package.lines.flatMap { $0.stations.map(\.id) })
        // Match LocalJourneySearch: package IDs take precedence over aliases.
        func stationKey(_ code: String) -> String {
            packageCodes.contains(code) ? code : request.stationAliases[code] ?? code
        }
        var linesByStation: [String: [CompactPackage.Line]] = [:]
        for line in package.lines {
            for key in Set(line.stations.map { stationKey($0.id) }) {
                linesByStation[key, default: []].append(line)
            }
        }
        // Share the connectivity memo between component discovery and route search.
        var memo: [String: TripConnectivity.Link] = [:]
        func link(_ from: CompactPackage.Line, _ to: CompactPackage.Line,
                  _ code: String) -> TripConnectivity.Link {
            let key = from.id + "\u{1F}" + to.id + "\u{1F}" + code
            if let known = memo[key] { return known }
            let value = TripConnectivity.link(from: from, to: to, atStationCode: code)
            memo[key] = value
            return value
        }
        let originKey = stationKey(request.originCode)
        let destinationKey = stationKey(request.destinationCode)
        let seeds: [CompactPackage.Line]
        if let id = request.originLineID, let line = package.lines.first(where: { $0.id == id }) {
            seeds = [line]
        } else {
            seeds = linesByStation[originKey] ?? []
        }
        var reachable = Set(seeds.map(\.id))
        var pending = seeds
        var cursor = 0
        while cursor < pending.count {
            let from = pending[cursor]
            cursor += 1
            for key in Set(from.stations.map { stationKey($0.id) }) {
                for to in linesByStation[key] ?? [] where !reachable.contains(to.id) {
                    if link(from, to, key) != .none {
                        reachable.insert(to.id)
                        pending.append(to)
                    }
                }
            }
        }
        let destinationIDs = request.destinationLineID.map { Set([$0]) }
            ?? Set((linesByStation[destinationKey] ?? []).map(\.id))
        func narrowed(to lines: [CompactPackage.Line]) -> CompactPackage {
            CompactPackage(format: package.format, version: package.version,
                           country: package.country, lines: lines)
        }
        func matchesHints(_ choice: RailwayRouteChoices.Choice) -> Bool {
            (request.originLineID == nil || choice.routeSections.first?.lineIDs?.first == request.originLineID)
                && (request.destinationLineID == nil
                    || choice.routeSections.last?.lineIDs?.first == request.destinationLineID)
        }
        let originLineIDs = request.originLineID.map { Set([$0]) }
        let destinationLineIDs = request.destinationLineID.map { Set([$0]) }
        var constrainedTruncated = false
        if !reachable.isDisjoint(with: destinationIDs) {
            let lines = package.lines.filter { reachable.contains($0.id) }
            let constrained = LocalJourneySearch.search(
                package: narrowed(to: lines), originCode: request.originCode,
                destinationCode: request.destinationCode, trainType: request.trainType,
                stationAliases: request.stationAliases, maximumChoices: 3,
                continuation: { from, to, code in link(from, to, code) != .none },
                originLineIDs: originLineIDs, destinationLineIDs: destinationLineIDs)
            constrainedTruncated = constrained.isTruncated
            var choices = constrained.choices
            let names: Set<String>
            if request.originLineID != nil || request.destinationLineID != nil {
                let hintedIDs = Set([request.originLineID, request.destinationLineID].compactMap { $0 })
                names = Set(package.lines.filter { hintedIDs.contains($0.id) }.map(\.name))
            } else {
                names = Set(lines.filter { line in
                    let keys = Set(line.stations.map { stationKey($0.id) })
                    return keys.contains(originKey) && keys.contains(destinationKey)
                }.map(\.name))
            }
            let namedLines = lines.filter { names.contains($0.name) }
            var directIDs: Set<String> = []
            if !namedLines.isEmpty {
                let direct = LocalJourneySearch.search(
                    package: narrowed(to: namedLines), originCode: request.originCode,
                    destinationCode: request.destinationCode, trainType: request.trainType,
                    stationAliases: request.stationAliases, maximumChoices: 1,
                    continuation: { from, to, code in link(from, to, code) != .none },
                    originLineIDs: originLineIDs, destinationLineIDs: destinationLineIDs)
                choices += direct.choices
                directIDs.formUnion(direct.choices.map(\.id))
            }
            choices = choices.filter(matchesHints)
            if let operatorName = request.operatorName, !choices.isEmpty {
                choices = choices.filter { $0.operatorNames.contains(operatorName) }
                if choices.isEmpty { return .noCompanyRoute(operatorName) }
            }
            var byKey: [String: Corridor] = [:]
            for choice in choices {
                let corridor = Corridor(
                    id: choice.id, choice: choice, lineNames: choice.lineNames,
                    operatorNames: choice.operatorNames,
                    junctions: junctions(for: choice, package: package).filter { $0.link != .none },
                    distanceKm: distance(for: choice, package: package),
                    passStationCount: max(0, choice.stations.count - 2))
                let key = choice.lineIDs.joined(separator: "→") + "|"
                    + (choice.stations.dropFirst().first?.code ?? "")
                if let previous = byKey[key], previous.distanceKm <= corridor.distanceKm { continue }
                byKey[key] = corridor
            }
            func isDirect(_ corridor: Corridor) -> Bool {
                directIDs.contains(corridor.id)
            }
            let ordered = byKey.values.sorted {
                if isDirect($0) != isDirect($1) { return isDirect($0) }
                if $0.distanceKm != $1.distanceKm { return $0.distanceKm < $1.distanceKm }
                if $0.junctions.count != $1.junctions.count { return $0.junctions.count < $1.junctions.count }
                return $0.id < $1.id
            }
            var corridors: [Corridor] = []
            var keptKeys: [Set<String>] = []
            for corridor in ordered {
                let keys = Set(corridor.choice.stations.map { stationKey($0.code) })
                guard !keptKeys.contains(where: { keys.intersection($0).count * 5 >= keys.count * 4 }) else {
                    continue
                }
                corridors.append(corridor)
                keptKeys.append(keys)
            }
            if !corridors.isEmpty { return .corridors(corridors) }
        }
        // When both endpoint lines are known and meet somewhere, the useful
        // explanation is the single change between them, not whichever
        // multi-change path happens to be shortest in kilometres.
        if let originLine = package.lines.first(where: { $0.id == request.originLineID }),
           let destinationLine = package.lines.first(where: { $0.id == request.destinationLineID }),
           originLine.id != destinationLine.id {
            let originIndex = originLine.stations.firstIndex { stationKey($0.id) == originKey }
            let destinationIndex = destinationLine.stations.firstIndex { stationKey($0.id) == destinationKey }
            var best: (cost: Int, station: CompactPackage.Station)?
            for (index, station) in originLine.stations.enumerated() {
                let key = stationKey(station.id)
                guard let other = destinationLine.stations.firstIndex(where: { stationKey($0.id) == key })
                else { continue }
                let cost = abs(index - (originIndex ?? index)) + abs(other - (destinationIndex ?? other))
                if best == nil || cost < best!.cost { best = (cost, station) }
            }
            if let best {
                return .disconnected([Junction(
                    stationCode: best.station.id, stationName: best.station.name,
                    fromLineID: originLine.id, fromLineName: originLine.name,
                    toLineID: destinationLine.id, toLineName: destinationLine.name,
                    link: link(originLine, destinationLine, best.station.id))])
            }
        }
        let unconstrained = LocalJourneySearch.search(
            package: package, originCode: request.originCode, destinationCode: request.destinationCode,
            trainType: request.trainType, stationAliases: request.stationAliases, maximumChoices: 3,
            // Any shared station counts here: this pass only explains where a
            // passenger would have to change trains.
            continuation: { _, _, _ in true },
            originLineIDs: originLineIDs, destinationLineIDs: destinationLineIDs)
        if let choice = unconstrained.choices.first(where: matchesHints) ?? unconstrained.choices.first {
            let all = junctions(for: choice, package: package)
            let disconnected = all.filter { $0.link == .none }
            return .disconnected(disconnected.isEmpty ? all : disconnected)
        }
        return constrainedTruncated ? .truncated : .noRoute
    }

    private static func junctions(for choice: RailwayRouteChoices.Choice,
                                  package: CompactPackage) -> [Junction] {
        var result: [Junction] = []
        for (index, pair) in zip(choice.routeSections, choice.routeSections.dropFirst()).enumerated() {
            let (section, next) = pair
            guard let fromID = section.lineIDs?.first, let toID = next.lineIDs?.first,
                  fromID != toID,
                  let from = package.lines.first(where: { $0.id == fromID }),
                  let to = package.lines.first(where: { $0.id == toID }) else { continue }
            let station = choice.stations[index + 1]
            let code = section.toN02StationCode ?? station.code
            result.append(Junction(stationCode: code, stationName: station.name,
                                   fromLineID: from.id, fromLineName: from.name,
                                   toLineID: to.id, toLineName: to.name,
                                   link: TripConnectivity.link(from: from, to: to, atStationCode: code)))
        }
        return result
    }

    private static func distance(for choice: RailwayRouteChoices.Choice, package: CompactPackage) -> Double {
        var total = 0.0
        for lineID in Set(choice.lineIDs) {
            guard let line = package.lines.first(where: { $0.id == lineID }) else { continue }
            let intervals = RailIntervalCodes.intervals(for: line)
            let codes = choice.routeSections.filter { $0.lineIDs?.first == lineID }
                .flatMap { $0.sectionCodes ?? [] }
            for code in codes {
                guard let index = intervals.firstIndex(where: { $0.code == code }),
                      line.segments.indices.contains(index) else { continue }
                total += line.segments[index].distanceKm
            }
        }
        return total
    }
}
