import Foundation

/// Passenger direction inferred from package station order and surveyed distance.
///
/// Increasing `line.stations` index means 下り or 上り in this order:
/// timetable calibration (`line-direction-calibration.json`), then an explicit
/// `stationOrderDirection` of `up` or `down`, then — for a JR line, 新幹線
/// included — 上り toward 東京駅. Anything else casts no vote. Reverse travel
/// uses the opposite word. A loop, a tie, or a winner under 60% of the
/// weighted distance returns nil. Interval distance counts only when
/// `RailwayDirection.allowedDirections` permits the traveled sign.
public enum TravelDirection {
    public enum Direction: String, Sendable, Equatable {
        case up
        case down

        var opposite: Direction { self == .up ? .down : .up }
    }

    public struct Result: Sendable, Equatable {
        public var direction: Direction
        /// Line that contributed the most distance to `direction`.
        public var lineID: String
        /// Total kilometres that voted for `direction`, across every line.
        public var kilometers: Double
    }

    public static func infer(train: Train, package: CompactPackage) -> Result? {
        guard train.stops.count >= 2 else { return nil }
        let index = PackageIndex(package)
        let pairs = endpointPairs(in: train)
        var totals: [Direction: Double] = [.up: 0, .down: 0]
        var byLine: [Direction: [String: Double]] = [.up: [:], .down: [:]]
        for pair in pairs {
            guard let vote = vote(pair, train: train, index: index) else { continue }
            totals[vote.direction, default: 0] += vote.kilometers
            byLine[vote.direction, default: [:]][vote.lineID, default: 0] += vote.kilometers
        }
        let up = totals[.up] ?? 0
        let down = totals[.down] ?? 0
        let total = up + down
        guard total > 0, up != down else { return nil }
        let direction: Direction = up > down ? .up : .down
        let winner = direction == .up ? up : down
        guard winner / total >= 0.6 else { return nil }
        guard let lineID = supportingLine(byLine[direction] ?? [:]) else { return nil }
        return Result(direction: direction, lineID: lineID, kilometers: winner)
    }

    private struct EndpointPair {
        var from: Stop
        var to: Stop
        var lineIDs: [String]?
    }

    private struct Vote {
        var direction: Direction
        var lineID: String
        var kilometers: Double
    }

    private struct PackageIndex {
        var lines: [CompactPackage.Line]
        var byCode: [String: [(line: Int, station: Int)]] = [:]
        var byName: [String: [(line: Int, station: Int)]] = [:]

        init(_ package: CompactPackage) {
            lines = package.lines
            for (lineIndex, line) in package.lines.enumerated() {
                for (stationIndex, station) in line.stations.enumerated() {
                    byCode[station.id, default: []].append((lineIndex, stationIndex))
                    byName[station.name, default: []].append((lineIndex, stationIndex))
                }
            }
        }

        /// A code that already identifies a package station is never matched by
        /// name onto a different station. Name fallback is only for a code the
        /// package does not contain, and for a stop with no code.
        func stationIndex(of stop: Stop, on line: Int) -> Int? {
            if let code = stop.n02StationCode, !code.isEmpty, let hits = byCode[code] {
                return unique(hits.filter { $0.line == line }.map(\.station))
            }
            let hits = (byName[stop.name] ?? []).filter { $0.line == line }.map(\.station)
            return unique(hits)
        }

        func covers(_ stop: Stop, on line: Int) -> Bool {
            stationIndex(of: stop, on: line) != nil
        }

        private func unique(_ indices: [Int]) -> Int? {
            let values = Set(indices)
            return values.count == 1 ? values.first : nil
        }
    }

    private static func endpointPairs(in train: Train) -> [EndpointPair] {
        let stops = train.stops
        guard stops.count >= 2 else { return [] }
        if let sections = train.routeSections, sections.count == stops.count - 1 {
            return sections.indices.map { index in
                EndpointPair(from: stops[index], to: stops[index + 1], lineIDs: sections[index].lineIDs)
            }
        }
        return (0..<(stops.count - 1)).map { index in
            EndpointPair(from: stops[index], to: stops[index + 1], lineIDs: nil)
        }
    }

    private static func vote(_ pair: EndpointPair, train: Train, index: PackageIndex) -> Vote? {
        let common = index.lines.indices.filter { line in
            !isLoop(index.lines[line])
                && index.stationIndex(of: pair.from, on: line) != nil
                && index.stationIndex(of: pair.to, on: line) != nil
        }
        var restricted = common
        if let ids = pair.lineIDs, !ids.isEmpty {
            let named = common.filter { ids.contains(index.lines[$0].id) }
            if !named.isEmpty { restricted = named }
        }
        let directed = restricted.filter { increasingIndexDirection(index.lines[$0]) != nil }
        guard let line = preferredLine(directed, train: train, index: index),
              let from = index.stationIndex(of: pair.from, on: line),
              let to = index.stationIndex(of: pair.to, on: line),
              from != to,
              let order = increasingIndexDirection(index.lines[line]) else { return nil }
        let sign = from < to ? 1 : -1
        let row = index.lines[line]
        let lower = min(from, to)
        let upper = max(from, to)
        var kilometers = 0.0
        for interval in lower..<upper {
            guard row.segments.indices.contains(interval),
                  RailwayDirection.allowedDirections(for: row, intervalIndex: interval).contains(sign)
            else { continue }
            kilometers += row.segments[interval].distanceKm
        }
        guard kilometers > 0 else { return nil }
        let direction = sign == 1 ? order : order.opposite
        return Vote(direction: direction, lineID: row.id, kilometers: kilometers)
    }

    /// The common line that contains the most of this ride's stops.
    /// An equal count keeps the lowest line id.
    private static func preferredLine(_ lines: [Int], train: Train, index: PackageIndex) -> Int? {
        var best: Int?
        var bestCoverage = -1
        var bestID = ""
        for line in lines {
            let coverage = train.stops.reduce(0) { count, stop in
                count + (index.covers(stop, on: line) ? 1 : 0)
            }
            let id = index.lines[line].id
            if coverage > bestCoverage || (coverage == bestCoverage && (best == nil || id < bestID)) {
                best = line
                bestCoverage = coverage
                bestID = id
            }
        }
        return best
    }

    /// What an increasing station index means, or nil when this line abstains.
    ///
    /// Calibration wins. `downSign` 1 means increasing index is 下り.
    /// An explicit `up` or `down` is next. A JR line with neither compares the
    /// two terminal stations with 東京駅: the nearer terminal is the 上り end,
    /// and the line abstains when those distances differ by under 5%.
    private static func increasingIndexDirection(_ line: CompactPackage.Line) -> Direction? {
        if let entry = calibrationByLine[line.id] {
            if entry.downSign == 1 { return .down }
            if entry.downSign == -1 { return .up }
        }
        if line.stationOrderDirection == "up" { return .up }
        if line.stationOrderDirection == "down" { return .down }
        guard isJR(line) else { return nil }
        return jrIncreasingDirection(line)
    }

    private static func isJR(_ line: CompactPackage.Line) -> Bool {
        guard let name = line.`operator` else { return false }
        return jrOperators.contains { name.contains($0) }
    }

    /// Direction word of increasing index. 上り runs toward the terminal closer to Tokyo.
    private static func jrIncreasingDirection(_ line: CompactPackage.Line) -> Direction? {
        guard line.stations.count >= 2,
              let first = line.stations.first?.coordinate,
              let last = line.stations.last?.coordinate else { return nil }
        let toFirst = Geometry.distanceMeters(first, tokyoStation)
        let toLast = Geometry.distanceMeters(last, tokyoStation)
        let scale = max(toFirst, toLast)
        guard scale > 0, abs(toFirst - toLast) / scale >= 0.05 else { return nil }
        return toLast < toFirst ? .up : .down
    }

    private struct CalibrationEntry: Decodable {
        var downSign: Int
    }

    /// First access reads the generated resource. `Package.swift` processes the
    /// whole `Resources` directory, so this JSON is in `Bundle.module`.
    private static let calibrationByLine: [String: CalibrationEntry] = {
        guard let url = Bundle.module.url(
            forResource: "line-direction-calibration", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: CalibrationEntry].self, from: data)
        else { return [:] }
        return decoded
    }()

    private static let jrOperators = [
        "北海道旅客鉄道", "東日本旅客鉄道", "東海旅客鉄道",
        "西日本旅客鉄道", "四国旅客鉄道", "九州旅客鉄道",
    ]

    /// 東京駅, the JR 上り reference. Longitude, then latitude.
    private static let tokyoStation = Coordinate(lon: 139.7671, lat: 35.6812)

    private static func isLoop(_ line: CompactPackage.Line) -> Bool {
        if line.isLoop { return true }
        if line.name.contains("環状") || (line.nameNorm ?? "").contains("環状") { return true }
        return false
    }

    private static func supportingLine(_ kilometers: [String: Double]) -> String? {
        var bestID: String?
        var best = -1.0
        for (id, km) in kilometers where km > best || (km == best && (bestID == nil || id < bestID!)) {
            best = km
            bestID = id
        }
        return bestID
    }
}
