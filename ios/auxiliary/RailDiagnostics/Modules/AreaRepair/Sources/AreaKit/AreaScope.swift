import Foundation
import RailCore
import RailInspection

/// One package line inside an area, with the display intervals that touch it
/// and its paired-alignment declaration.
public struct LineScope: Codable, Equatable, Sendable {
    public struct Pair: Codable, Equatable, Sendable {
        public var with: String
        public var from: String
        public var to: String
        public var direction: String
    }
    public var lineID: String
    public var name: String
    public var operatorName: String?
    /// Display interval indices whose geometry intersects the area box.
    public var intervalIndices: [Int]
    public var alignmentOf: String?
    public var alignmentDirection: String?
    public var stationOrderDirection: String?
    public var permittedTraversal: String?
    public var alignmentPairs: [Pair]

    /// True when the line is one half of a paired one-direction alignment.
    public var isPaired: Bool { alignmentOf != nil || !alignmentPairs.isEmpty }
}

/// The display intervals between two stations of one package line. Interval
/// `i` joins station `i` to station `i + 1`; on a loop (`isLoop`) the last
/// interval joins the last station back to the first, so a pair may be
/// joined either way round: the one with fewer intervals is taken (a tie
/// keeps station order).
public enum StationSpan {
    public static func intervals(_ line: CompactPackage.Line, _ a: Int, _ b: Int) -> [Int] {
        intervals(a, b, stationCount: line.stations.count, isLoop: line.isLoop)
    }

    /// Interval indices in travel order from the lower end (station order), or
    /// from the higher index through the wrap when that way is shorter.
    public static func intervals(_ a: Int, _ b: Int, stationCount n: Int, isLoop: Bool) -> [Int] {
        let low = min(a, b), high = max(a, b)
        guard isLoop, n - (high - low) < high - low else { return Array(low..<high) }
        return Array(high..<n) + Array(0..<low)
    }

    /// Station indices the intervals touch (both ends of each).
    public static func stations(_ intervals: [Int], stationCount n: Int) -> [Int] {
        var out: [Int] = []
        for i in intervals { for s in [i % n, (i + 1) % n] where !out.contains(s) { out.append(s) } }
        return out
    }
}

/// A stations.json feature inside the area.
public struct ScopedStation: Codable, Equatable, Sendable {
    public var featureIndex: Int
    public var code: String?
    public var name: String?
    public var lineName: String
    public var operatorName: String
    public var coordinate: AreaPoint
}

/// Everything an area touches: its padded box, the package lines and their
/// intervals, N02 stations, solver features, junction rows and history rows.
public struct AreaScope: Codable, Equatable, Sendable {
    public var selection: AreaSelection
    public var bbox: AreaBBox
    public var lines: [LineScope]
    public var stations: [ScopedStation]
    /// Indices into `AreaData.sections` (history applied).
    public var sectionFeatureIndices: [Int]
    /// Junction row IDs with at least one endpoint in the box.
    public var junctionIDs: [String]
    /// Retirement / identity-period / overlay-section history IDs touching the box.
    public var historyIDs: [String]

    public func line(_ id: String) -> LineScope? { lines.first { $0.lineID == id } }

    /// Resolves a selection against loaded data. Station pairs accept either
    /// order; unknown lines, stations or intervals fail without widening.
    public static func resolve(_ selection: AreaSelection, data: AreaData) throws -> AreaScope {
        do { try selection.validate() } catch { throw AreaRepairError.invalidScope(error.localizedDescription) }
        let core: AreaBBox
        switch selection.mode {
        case let .rect(minLon, minLat, maxLon, maxLat):
            core = .init(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
        case let .centre(lon, lat, radius):
            core = AreaBBox(minLon: lon, minLat: lat, maxLon: lon, maxLat: lat).padded(metres: radius)
        case let .stationPair(lineID, fromID, toID):
            guard let line = data.linesByID[lineID] else { throw AreaRepairError.invalidScope("unknown line \(lineID).") }
            guard let a = line.stations.firstIndex(where: { $0.id == fromID }) else {
                throw AreaRepairError.invalidScope("station \(fromID) is not on \(lineID).")
            }
            guard let b = line.stations.firstIndex(where: { $0.id == toID }) else {
                throw AreaRepairError.invalidScope("station \(toID) is not on \(lineID).")
            }
            core = try intervalBox(line, StationSpan.intervals(line, a, b))
        case let .lineSection(lineID, first, last):
            guard let line = data.linesByID[lineID] else { throw AreaRepairError.invalidScope("unknown line \(lineID).") }
            guard last < line.segments.count else {
                throw AreaRepairError.invalidScope("\(lineID) has intervals 0...\(line.segments.count - 1); \(last) is out of range.")
            }
            core = try intervalBox(line, Array(first...last))
        }
        let bbox = core.padded(metres: selection.marginMetres)

        var lines: [LineScope] = []
        for line in data.package.lines {
            let intervals = CompactPackage.decodeDisplayIntervals(line)
            let hit = intervals.indices.filter { bbox.intersects(polyline: intervals[$0]) }
            guard !hit.isEmpty else { continue }
            lines.append(LineScope(
                lineID: line.id, name: line.name, operatorName: line.operator, intervalIndices: hit,
                alignmentOf: line.alignmentOf, alignmentDirection: line.alignmentDirection,
                stationOrderDirection: line.stationOrderDirection, permittedTraversal: line.permittedTraversal,
                alignmentPairs: line.alignmentPairs.map { .init(with: $0.with, from: $0.from, to: $0.to, direction: $0.direction) }))
        }

        var stations: [ScopedStation] = []
        for (index, feature) in data.stations.features.enumerated() {
            guard let point = Self.points(feature.geometry?.coordinates).first(where: bbox.contains) else { continue }
            stations.append(.init(featureIndex: index, code: Stations.stationCode(feature), name: Stations.stationName(feature),
                                  lineName: Stations.stationLineName(feature), operatorName: Stations.stationOperator(feature),
                                  coordinate: AreaPoint(point)))
        }

        let sectionIndices = data.graphStore.featureIndicesInBBox(bbox.routeGraphBBox).sorted()
        let junctionIDs = data.junctions.filter { bbox.contains($0.from.coordinate) || bbox.contains($0.to.coordinate) }.map(\.id)

        var historyIDs: [String] = []
        func matchBox(_ values: [Double]) -> AreaBBox? {
            values.count == 4 ? AreaBBox(minLon: values[0], minLat: values[1], maxLon: values[2], maxLat: values[3]) : nil
        }
        for retirement in data.overlay.retirements where matchBox(retirement.match.bbox).map(bbox.intersects) == true {
            historyIDs.append(retirement.historyId)
        }
        for period in data.overlay.identityPeriods where matchBox(period.match.bbox).map(bbox.intersects) == true {
            historyIDs.append(period.historyId)
        }
        for section in data.overlay.sections {
            guard let id = section.properties.historyId, section.lines.contains(where: bbox.intersects(polyline:)) else { continue }
            historyIDs.append(id)
        }
        var seen = Set<String>()
        historyIDs = historyIDs.filter { seen.insert($0).inserted }

        return AreaScope(selection: selection, bbox: bbox, lines: lines, stations: stations,
                         sectionFeatureIndices: sectionIndices, junctionIDs: junctionIDs, historyIDs: historyIDs)
    }

    /// Union of the selected display intervals and their station anchors.
    private static func intervalBox(_ line: CompactPackage.Line, _ indices: [Int]) throws -> AreaBBox {
        let intervals = CompactPackage.decodeDisplayIntervals(line)
        var points: [Coordinate] = []
        for index in indices where intervals.indices.contains(index) {
            points += intervals[index]
            points.append(line.stations[index % line.stations.count].coordinate)
            points.append(line.stations[(index + 1) % line.stations.count].coordinate)
        }
        guard let box = AreaBBox(points: points) else {
            throw AreaRepairError.invalidScope("\(line.id) has no geometry for intervals \(indices).")
        }
        return box
    }

    static func points(_ value: Stations.Value?) -> [Coordinate] {
        guard case .array(let items)? = value else { return [] }
        if items.count == 2, case .number(let lon) = items[0], case .number(let lat) = items[1] {
            return [Coordinate(lon: lon, lat: lat)]
        }
        return items.flatMap { points($0) }
    }
}
