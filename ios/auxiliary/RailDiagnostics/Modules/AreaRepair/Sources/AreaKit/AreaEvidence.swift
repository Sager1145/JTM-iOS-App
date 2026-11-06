import Foundation
import RailCore
import RailInspection

/// `jtm-area-evidence-v1`: everything known about one area in one file
/// (`area-evidence.json`), written by the CLI and the app.
public struct AreaEvidence: Codable, Sendable {
    public static let format = "jtm-area-evidence-v1"

    public struct DataRootRecord: Codable, Sendable {
        public var repo: String
        public var overlay: String?
        /// Repository-relative path → sha256 of the file actually read.
        public var sha256: [String: String]
    }
    public struct StationRecord: Codable, Sendable {
        public var id: String
        public var name: String
        public var lineID: String
        public var anchor: AreaPoint
        public var n02: AreaPoint?
        public var offLineMetres: Double?
    }
    public struct PairedTrack: Codable, Sendable {
        public struct Interval: Codable, Sendable {
            public var index: Int
            public var code: String
            public var certifiedForward: Bool
            public var certifiedReverse: Bool
        }
        public var lineID: String
        public var alignmentOf: String?
        public var alignmentDirection: String?
        public var stationOrderDirection: String?
        public var permittedTraversal: String?
        public var pairs: [LineScope.Pair]
        public var intervals: [Interval]
    }
    public struct Stamp: Codable, Sendable {
        public var featureIndex: Int
        public var lineName: String
        public var operatorName: String
        public var validFrom: String?
        public var validTo: String?
        public var historyId: String?
    }
    public struct History: Codable, Sendable {
        public var retirements: [AreaJSON]
        public var identityPeriods: [AreaJSON]
        public var stamps: [Stamp]
    }
    public struct View: Codable, Sendable {
        public var viewpointID: String
        public var directory: String
        public init(viewpointID: String, directory: String) { self.viewpointID = viewpointID; self.directory = directory }
    }

    public var format = AreaEvidence.format
    public var selection: AreaSelection
    public var bbox: AreaBBox
    public var dataRoot: DataRootRecord
    public var lines: [LineScope]
    public var stations: [StationRecord]
    public var junctions: [AreaJSON]
    public var pairedTracks: [PairedTrack]
    public var history: History
    public var rides: [RideOutcome]
    public var problems: [Problem]
    public var styleContract: String
    /// App captures only.
    public var views: [View]?

    /// Builds the evidence for a resolved scope.
    public static func make(data: AreaData, scope: AreaScope, rides: [RideOutcome], problems: [Problem],
                            zoom: Double = 15, views: [View]? = nil) throws -> AreaEvidence {
        var hashes: [String: String] = [:]
        for file in DataFile.allCases {
            hashes[file.relativePath] = WriteTransaction.sha256(try Data(contentsOf: data.root.url(file)))
        }
        var stations: [StationRecord] = []
        let offLine = Dictionary(problems.filter { $0.kind == .stationDotOffLine }.map { ("\($0.lineIDs.first ?? "")/\($0.stationCode ?? "")", $0.measure) },
                                 uniquingKeysWith: { a, _ in a })
        for scoped in scope.lines {
            guard let line = data.linesByID[scoped.lineID] else { continue }
            for station in line.stations {
                let anchor = line.displayCoordinate(for: station)
                guard scope.bbox.contains(anchor) else { continue }
                let n02 = scope.stations.first { $0.code == station.id }?.coordinate
                    ?? data.stations.features.first { Stations.stationCode($0) == station.id }
                        .flatMap { AreaScope.points($0.geometry?.coordinates).first }.map(AreaPoint.init)
                let display = AreaGeometry.nearestDistance(to: data.displayParts[line.id] ?? [], from: anchor)
                stations.append(.init(id: station.id, name: station.name, lineID: line.id, anchor: AreaPoint(anchor),
                                      n02: n02, offLineMetres: offLine["\(line.id)/\(station.id)"] ?? display))
            }
        }
        let junctionIDs = Set(scope.junctionIDs)
        let junctions = data.junctionRows.filter { $0["id"]?.stringValue.map(junctionIDs.contains) == true }
        let paired = scope.lines.filter(\.isPaired).map { scoped in
            PairedTrack(lineID: scoped.lineID, alignmentOf: scoped.alignmentOf, alignmentDirection: scoped.alignmentDirection,
                        stationOrderDirection: scoped.stationOrderDirection, permittedTraversal: scoped.permittedTraversal,
                        pairs: scoped.alignmentPairs, intervals: scoped.intervalIndices.compactMap { index in
                guard let line = data.networkLine(scoped.lineID), line.intervals.indices.contains(index),
                      let c = UncertifiedPairedTrackDetector.certification(data, lineID: scoped.lineID, intervalIndex: index) else { return nil }
                return .init(index: index, code: line.intervals[index].code, certifiedForward: c.forward, certifiedReverse: c.reverse)
            })
        }
        let historyIDs = Set(scope.historyIDs)
        let rows = try data.historyRows()
        func scoped(_ list: [AreaJSON]) -> [AreaJSON] {
            list.filter { $0["history_id"]?.stringValue.map(historyIDs.contains) == true }
        }
        let stamps = scope.sectionFeatureIndices.compactMap { index -> Stamp? in
            let p = data.sections[index].properties
            guard p.validFrom != nil || p.validTo != nil || p.historyId != nil else { return nil }
            return Stamp(featureIndex: index, lineName: p.lineName, operatorName: p.operator,
                         validFrom: p.validFrom, validTo: p.validTo, historyId: p.historyId)
        }
        let style = StrokeStyle.diagnosticsDefault(zoom: zoom)
        return AreaEvidence(
            selection: scope.selection, bbox: scope.bbox,
            dataRoot: .init(repo: data.root.repo.path, overlay: data.root.overlay?.path, sha256: hashes),
            lines: scope.lines, stations: stations, junctions: junctions, pairedTracks: paired,
            history: .init(retirements: scoped(rows.retirements), identityPeriods: scoped(rows.identityPeriods), stamps: stamps),
            rides: rides, problems: problems,
            styleContract: "\(AreaStrokeGeometry.revision);\(AreaStrokeGeometry.joinContract);\(style.contract);zoom=\(zoom)",
            views: views)
    }

    /// Writes `area-evidence.json` into `directory` (created if needed) and returns its URL.
    @discardableResult
    public func write(to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = directory.appending(path: "area-evidence.json")
        try encoder.encode(self).write(to: url, options: .atomic)
        return url
    }

    /// Convenience: make + write.
    @discardableResult
    public static func write(to directory: URL, data: AreaData, scope: AreaScope, rides: [RideOutcome],
                             problems: [Problem], zoom: Double = 15, views: [View]? = nil) throws -> URL {
        try make(data: data, scope: scope, rides: rides, problems: problems, zoom: zoom, views: views).write(to: directory)
    }
}
