import Foundation

/// Display track geometry for a planned route choice, for previewing
/// candidates before anything is saved. Pure and synchronous.
///
/// Each route section names its physical interval code. The interval's display
/// polyline is taken in traversal direction, so the drawn path follows the
/// surveyed track rather than straight chords between stations. A connector
/// section (a through service between two different stations) has no track of
/// its own and becomes a separate two-point `connector` piece.
public enum TripRouteGeometry {
    public struct Piece: Sendable, Equatable {
        public var lineID: String?
        public var coordinates: [Coordinate]
        public var isConnector: Bool
    }

    /// Decoded per-line display intervals, shared across several choices.
    public final class Cache: @unchecked Sendable {
        private struct Entry {
            var byCode: [String: Int]
            var intervals: [RailIntervalCodes.Interval]
            var display: [[Coordinate]]
        }

        private let linesByID: [String: CompactPackage.Line]
        private var entries: [String: Entry] = [:]
        private let lock = NSLock()

        public init(package: CompactPackage) {
            linesByID = Dictionary(package.lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }

        func stationCoordinate(code: String, lineID: String?) -> Coordinate? {
            if let lineID, let line = linesByID[lineID],
               let station = line.stations.first(where: { $0.id == code }) {
                return line.displayCoordinate(for: station)
            }
            for line in linesByID.values {
                if let station = line.stations.first(where: { $0.id == code }) {
                    return line.displayCoordinate(for: station)
                }
            }
            return nil
        }

        func interval(code: String, lineID: String) -> (RailIntervalCodes.Interval, [Coordinate])? {
            lock.lock()
            defer { lock.unlock() }
            if entries[lineID] == nil {
                guard let line = linesByID[lineID] else { return nil }
                let intervals = RailIntervalCodes.intervals(for: line)
                entries[lineID] = Entry(
                    byCode: Dictionary(intervals.enumerated().map { ($1.code, $0) },
                                       uniquingKeysWith: { first, _ in first }),
                    intervals: intervals,
                    display: CompactPackage.decodeDisplayIntervals(line))
            }
            guard let entry = entries[lineID], let index = entry.byCode[code],
                  entry.display.indices.contains(index) else { return nil }
            return (entry.intervals[index], entry.display[index])
        }
    }

    /// Pieces in traversal order. Consecutive sections on the same line are
    /// merged into one piece. Sections whose interval cannot be found fall back
    /// to the straight station-to-station span, marked as a connector.
    public static func pieces(for choice: RailwayRouteChoices.Choice, cache: Cache) -> [Piece] {
        pieces(for: choice.routeSections, cache: cache)
    }

    /// Pieces for saved route sections, such as a stored `Train.routeSections`.
    public static func pieces(for sections: [RouteSection], cache: Cache) -> [Piece] {
        var result: [Piece] = []
        func append(_ coordinates: [Coordinate], lineID: String?, connector: Bool) {
            guard coordinates.count >= 2 else { return }
            if !connector, var last = result.last, !last.isConnector, last.lineID == lineID,
               last.coordinates.last == coordinates.first {
                last.coordinates += coordinates.dropFirst()
                result[result.count - 1] = last
            } else {
                result.append(Piece(lineID: lineID, coordinates: coordinates, isConnector: connector))
            }
        }
        for section in sections {
            let lineID = section.lineIDs?.first
            let fromCode = section.fromN02StationCode
            let toCode = section.toN02StationCode
            if let lineID, let code = section.sectionCodes?.first, !code.hasPrefix("connector:"),
               let (interval, display) = cache.interval(code: code, lineID: lineID), display.count >= 2 {
                let forward = fromCode.map { $0 == interval.fromStationCode }
                    ?? (toCode.map { $0 == interval.toStationCode } ?? true)
                append(forward ? display : display.reversed(), lineID: lineID, connector: false)
                continue
            }
            guard let fromCode, let toCode,
                  let from = cache.stationCoordinate(code: fromCode, lineID: lineID),
                  let to = cache.stationCoordinate(code: toCode, lineID: lineID) else { continue }
            append([from, to], lineID: lineID, connector: true)
        }
        return result
    }

    /// Display coordinates of every visit, in order. Nil for an unknown station.
    public static func stationCoordinates(
        for choice: RailwayRouteChoices.Choice, cache: Cache
    ) -> [Coordinate?] {
        choice.stations.enumerated().map { index, visit in
            let section = index < choice.routeSections.count
                ? choice.routeSections[index] : choice.routeSections.last
            return cache.stationCoordinate(code: visit.code, lineID: section?.lineIDs?.first)
        }
    }
}
