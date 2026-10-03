import Foundation

/// Endpoint choices use the package's physical station order. Passenger
/// service names and timetables cannot add a station to a different alignment.
public enum RailwayRouteChoices {
    public struct Visit: Hashable, Sendable {
        public var code: String
        public var name: String
    }

    public struct Choice: Identifiable, Equatable, Sendable {
        public var id: String { sectionCodes.joined(separator: ">") }
        public var lineIDs: [String]
        public var lineNames: [String]
        public var operatorNames: [String]
        public var stations: [Visit]
        public var sectionCodes: [String]
        public var routeSections: [RouteSection]
    }

    public static func choices(
        package: CompactPackage, originCode: String, destinationCode: String,
        trainType: String? = nil, excludingStationCodes: Set<String> = []
    ) -> [Choice] {
        guard originCode != destinationCode,
              !excludingStationCodes.contains(originCode),
              !excludingStationCodes.contains(destinationCode) else { return [] }
        let lines = package.lines.filter { permits($0, trainType: trainType) }
        var found: [Choice] = []
        for line in lines {
            found += slices(line: line, from: originCode, to: destinationCode,
                            excluding: excludingStationCodes)
        }
        // compact-v1 does not carry verified junctions between line rows.
        // A shared station/name/operator cannot establish a train connection.
        var seen: Set<String> = []
        return found.filter { seen.insert($0.id).inserted }.sorted {
            if $0.lineIDs.count != $1.lineIDs.count { return $0.lineIDs.count < $1.lineIDs.count }
            let lhs = $0.lineNames.joined(separator: " · ")
            let rhs = $1.lineNames.joined(separator: " · ")
            if lhs != rhs { return lhs < rhs }
            return $0.id < $1.id
        }
    }

    private static func permits(_ line: CompactPackage.Line, trainType: String?) -> Bool {
        let type = (trainType ?? "local").lowercased()
        let highSpeed = ["highspeed", "high speed", "high-speed", "shinkansen", "新幹線", "新干线", "高速"]
            .contains { type.contains($0) }
        let highSpeedLine = line.name.contains("新幹線") || ["high_speed", "shinkansen"].contains(line.kind ?? "")
        return line.isTraversableForSearch && (highSpeed ? highSpeedLine : !highSpeedLine)
    }

    private static func slices(
        line: CompactPackage.Line, from: String, to: String, excluding: Set<String>
    ) -> [Choice] {
        let intervals = RailIntervalCodes.intervals(for: line)
        let count = line.stations.count
        guard count >= 2 else { return [] }
        var result: [Choice] = []
        for start in line.stations.indices where line.stations[start].id == from {
            for direction in [-1, 1] {
                var index = start
                var visits = [Visit(code: from, name: line.stations[start].name)]
                var codes: [String] = []
                for _ in 0..<(count - 1) {
                    let rawNext = index + direction
                    guard line.isLoop || (0..<count).contains(rawNext) else { break }
                    let next = (rawNext + count) % count
                    let edge = direction == 1 ? index : next
                    guard intervals.indices.contains(edge), line.segments.indices.contains(edge),
                          RailwayDirection.allowedDirections(for: line, intervalIndex: edge).contains(direction),
                          intervals[edge].coordinates.count >= 2 else { break }
                    let station = line.stations[next]
                    guard !excluding.contains(station.id) else { break }
                    visits.append(Visit(code: station.id, name: station.name))
                    codes.append(intervals[edge].code)
                    if station.id == to {
                        let operators = line.operator.map { [$0] } ?? []
                        result.append(Choice(
                            lineIDs: [line.id], lineNames: [line.name], operatorNames: operators,
                            stations: visits, sectionCodes: codes,
                            // The canonical export recomputes one section per
                            // adjacent visit. Persist each selected physical
                            // interval at precisely that granularity.
                            routeSections: codes.indices.map { index in
                                RouteSection(
                                    from: visits[index].name, to: visits[index + 1].name,
                                    fromN02StationCode: visits[index].code,
                                    toN02StationCode: visits[index + 1].code,
                                    lineNames: [line.name], operatorNames: operators.isEmpty ? nil : operators,
                                    lineIDs: [line.id], sectionCodes: [codes[index]])
                            }))
                        break
                    }
                    index = next
                }
            }
        }
        return result
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
