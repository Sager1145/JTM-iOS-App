import Foundation

/// Passenger-facing metadata for the physical line identities selected by a route.
public struct ResolvedRailLine: Codable, Equatable, Sendable {
    public let lineID: String
    public let name: String
    public let operatorName: String?
    public let km: Double

    public init(lineID: String, name: String, operatorName: String?, km: Double) {
        self.lineID = lineID
        self.name = name
        self.operatorName = operatorName
        self.km = km
    }
}

extension RouteNetwork {
    /// Freeze travel direction separately from the interval's symmetric code.
    public func directedIntervals(
        sectionCodes: [String], fromStationCode: String, toStationCode: String
    ) -> [StationIntervalResolver.DirectedInterval]? {
        guard !sectionCodes.isEmpty else { return nil }
        var current = fromStationCode
        var result: [StationIntervalResolver.DirectedInterval] = []
        for code in sectionCodes {
            guard let record = intervalByCode[code] else { return nil }
            let interval = record.interval
            let direction: Int
            if current == interval.fromStationCode { direction = 1; current = interval.toStationCode }
            else if current == interval.toStationCode { direction = -1; current = interval.fromStationCode }
            else { return nil }
            guard allowedDirections(for: code).contains(direction) else { return nil }
            result.append(.init(lineID: interval.lineID, code: code, direction: direction))
        }
        return current == toStationCode ? result : nil
    }

    /// Summarizes the selected surveyed intervals in first-occurrence line order.
    /// Repeated interval occurrences contribute their distance each time.
    public func resolvedLines(sectionCodes: [String]) -> [ResolvedRailLine]? {
        guard !sectionCodes.isEmpty else { return nil }
        var results: [ResolvedRailLine] = []
        var positions: [String: Int] = [:]
        for code in sectionCodes {
            guard let record = intervalByCode[code] else { return nil }
            let line = lines[record.lineIndex]
            let interval = record.interval
            guard !line.lineId.isEmpty, interval.lineID == line.lineId,
                  let name = line.compactLine?.nameNorm ?? line.name, !name.isEmpty,
                  interval.coordinates.count >= 2 else { return nil }
            let km = Metric.pathLength(interval.coordinates) / 1000
            if let index = positions[line.lineId] {
                let previous = results[index]
                results[index] = ResolvedRailLine(
                    lineID: previous.lineID, name: previous.name,
                    operatorName: previous.operatorName, km: previous.km + km)
            } else {
                positions[line.lineId] = results.count
                results.append(ResolvedRailLine(
                    lineID: line.lineId, name: name, operatorName: line.operator, km: km))
            }
        }
        return results
    }
}
