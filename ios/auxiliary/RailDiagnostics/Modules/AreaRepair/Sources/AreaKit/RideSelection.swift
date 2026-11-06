import Foundation
import RailCore

/// Where rides come from.
public enum RideSource: Equatable, Sendable {
    /// A canonical journey store (`{"schema_version":..,"trains":[..]}`).
    case store(URL)
    /// A sample-data directory: `manifest.json` + `part-*.json`, each part
    /// holding one canonical `train` (its solved `route` is ignored).
    case sampleDirectory(URL)

    /// app/data/sample-data and app/data/default-trains.json, when present.
    public static func defaults(_ root: DataRoot) -> [RideSource] {
        var sources: [RideSource] = []
        let samples = root.repo.appending(path: "app/data/sample-data")
        if FileManager.default.fileExists(atPath: samples.appending(path: "manifest.json").path) { sources.append(.sampleDirectory(samples)) }
        if FileManager.default.fileExists(atPath: root.defaultTrains.path) { sources.append(.store(root.defaultTrains)) }
        return sources
    }
}

/// Rides from journey sources and the ones that cross an area.
public enum RideSelection {
    /// Imports every source through the public canonical import path
    /// (TrainValidation + ImportEngine.Session, as the route workbench does),
    /// in order; a train ID seen earlier is skipped.
    public static func loadTrains(_ sources: [RideSource]) throws -> [Train] {
        var trains: [Train] = []
        var seen = Set<String>()
        for source in sources {
            let text: String
            switch source {
            case .store(let url): text = try String(contentsOf: url, encoding: .utf8)
            case .sampleDirectory(let directory): text = try sampleStore(directory)
            }
            for train in try importStore(text) where seen.insert(train.id).inserted { trains.append(train) }
        }
        return trains
    }

    static func importStore(_ text: String) throws -> [Train] {
        let parsed = try TrainValidation.parseImportedCanonicalStore(text: text)
        guard case .array(let items)? = parsed["trains"] else { return [] }
        var session = ImportEngine.Session()
        for item in items {
            if case .string(let code)? = item["region"] { session.country = code } else { session.country = "jp" }
            try session.appendImportedTrain(item)
        }
        return session.trains
    }

    /// One canonical store text from a sample-data directory's parts.
    static func sampleStore(_ directory: URL) throws -> String {
        let manifest = try AreaJSON.parse(Data(contentsOf: directory.appending(path: "manifest.json")))
        let parts = (manifest["parts"]?.arrayValue ?? []).compactMap(\.stringValue)
        var trains: [AreaJSON] = []
        for part in parts {
            if let train = try AreaJSON.parse(Data(contentsOf: directory.appending(path: part.hasSuffix(".json") ? part : part + ".json")))["train"] { trains.append(train) }
        }
        return AreaJSON.object([("schema_version", manifest["schema_version"] ?? .string("1.3")), ("trains", .array(trains))])
            .serialized(style: .compact)
    }

    /// Rides with a recorded section that stops in the area or runs along a
    /// scoped line across a scoped interval (station-order range test).
    public static func ridesCrossing(_ scope: AreaScope, trains: [Train], data: AreaData) -> [Train] {
        trains.filter { train in (train.routeSections ?? []).contains { sectionCrosses($0, scope: scope, data: data) } }
    }

    static func sectionCrosses(_ section: RouteSection, scope: AreaScope, data: AreaData) -> Bool {
        let codes = [section.fromN02StationCode, section.toN02StationCode].compactMap { $0 }
        let areaCodes = Set(scope.stations.compactMap(\.code))
        if codes.contains(where: areaCodes.contains) { return true }
        guard codes.count == 2 else { return false }
        for scoped in scope.lines {
            guard let line = data.linesByID[scoped.lineID],
                  let a = line.stations.firstIndex(where: { $0.id == codes[0] }),
                  let b = line.stations.firstIndex(where: { $0.id == codes[1] }) else { continue }
            if scoped.intervalIndices.contains(where: { (min(a, b)..<max(a, b)).contains($0) }) { return true }
        }
        return false
    }
}

/// One ride resolved against one data snapshot.
public struct RideOutcome: Codable, Equatable, Sendable {
    public struct Section: Codable, Equatable, Sendable {
        public var index: Int
        public var from: String?
        public var to: String?
        public var fromCode: String?
        public var toCode: String?
        public var certified: Bool
        public var gaps: [String]
        public var provenance: String?
        public var lineIDs: [String]
        /// The section touches the area (see RideSelection).
        public var inArea: Bool
    }
    public var trainID: String
    public var date: String?
    public var disposition: String
    public var sections: [Section]

    /// Resolves rides serially with the snapshot's resolver (the graph cache
    /// is not thread-safe). Certified = no interior physical gap.
    public static func resolve(_ trains: [Train], data: AreaData, scope: AreaScope) -> [RideOutcome] {
        var resolver = data.resolver()
        return trains.map { train in
            let recorded = train.routeSections ?? []
            guard let result = try? resolver.resolve(.init(train: train)) else {
                return RideOutcome(trainID: train.id, date: train.date, disposition: "error", sections: [])
            }
            let uncertified = RideRouteResolution.PhysicalGap.uncertifiedSections(result.physicalGaps)
            let sections = recorded.indices.map { index -> Section in
                let section = recorded[index]
                let gaps = result.physicalGaps.filter { $0.segmentIndex == index }.map {
                    $0.isBoundary ? "boundary" : ($0.isUnproven ? "unproven" : "gap")
                }
                let route = result.segments.first { $0.segmentIndex == index }?.physicalRoute
                return Section(index: index, from: section.from, to: section.to,
                               fromCode: section.fromN02StationCode, toCode: section.toN02StationCode,
                               certified: !uncertified.contains(index), gaps: gaps,
                               provenance: route?.provenance.rawValue,
                               lineIDs: route?.lines.map(\.lineID) ?? section.lineIDs ?? [],
                               inArea: RideSelection.sectionCrosses(section, scope: scope, data: data))
            }
            return RideOutcome(trainID: train.id, date: train.date, disposition: "\(result.disposition)", sections: sections)
        }
    }
}
