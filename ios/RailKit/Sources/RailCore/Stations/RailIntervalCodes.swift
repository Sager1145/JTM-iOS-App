import Foundation

/// Physical railway identity. Travel order is carried by the ordered code
/// list, while the code itself survives a reversal and package reordering.
public enum RailIntervalCodes {
    public struct Interval: Sendable {
        public let code: String
        public let lineID: String
        public let fromStationCode: String
        public let toStationCode: String
        public let from: Coordinate
        public let to: Coordinate
        /// Canonical WGS84 survey vertices, before display approach grooming.
        public let coordinates: [Coordinate]
    }

    public static func intervals(for line: CompactPackage.Line) -> [Interval] {
        guard line.stations.count >= 2 else { return [] }
        let pairs = line.segments.indices.compactMap { index -> (CompactPackage.Station, CompactPackage.Station)? in
            guard index < line.stations.count, index + 1 < line.stations.count || line.isLoop else { return nil }
            return (line.stations[index], line.stations[(index + 1) % line.stations.count])
        }
        let bases = pairs.map { pair in
            line.id + "@" + [pair.0.id, pair.1.id].sorted().joined(separator: ":")
        }
        let counts = Dictionary(bases.map { ($0, 1) }, uniquingKeysWith: +)
        let coordinates = CompactPackage.decodeIntervals(line)
        var occurrences: [String: Int] = [:]
        return pairs.enumerated().map { index, pair in
            let base = bases[index]
            occurrences[base, default: 0] += 1
            let code = counts[base] == 1 ? base : base + "~\(occurrences[base]!)"
            return Interval(code: code, lineID: line.id,
                            fromStationCode: pair.0.id, toStationCode: pair.1.id,
                            from: pair.0.coordinate, to: pair.1.coordinate,
                            coordinates: coordinates[index])
        }
    }
}
