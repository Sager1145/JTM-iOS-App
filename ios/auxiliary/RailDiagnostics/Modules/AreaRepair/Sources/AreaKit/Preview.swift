import Foundation
import RailCore

/// Area geometry for drawing one snapshot.
public struct AreaGeometrySnapshot: Codable, Equatable, Sendable {
    public struct Line: Codable, Equatable, Sendable {
        public var lineID: String
        public var display: [[AreaPoint]]
        public var smooth: [[AreaPoint]]
    }
    public struct Station: Codable, Equatable, Sendable {
        public var lineID: String
        public var stationID: String
        public var name: String
        public var anchor: AreaPoint
    }
    public struct Junction: Codable, Equatable, Sendable {
        public var id: String
        public var from: AreaPoint
        public var to: AreaPoint
    }
    public var lines: [Line]
    public var stations: [Station]
    public var junctions: [Junction]

    /// Display strokes, smooth strokes (diagnostics style at `zoom`), anchors
    /// and junction endpoints of every scoped line.
    public static func capture(_ data: AreaData, scope: AreaScope, zoom: Double) -> AreaGeometrySnapshot {
        let style = StrokeStyle.diagnosticsDefault(zoom: zoom)
        var lines: [Line] = [], stations: [Station] = []
        for scoped in scope.lines {
            guard let line = data.linesByID[scoped.lineID] else { continue }
            let parts = data.displayParts[line.id] ?? []
            let smooth = AreaStrokeGeometry.render(
                display: parts, stations: line.displayStations.map(\.coordinate),
                mapPointsPerPoint: StrokeStyle.mapPointsPerPoint(zoom: zoom), style: style,
                literalSpans: DisplayLiteralSpans.resolve(line, parts: parts)).paths
            func clipped(_ paths: [[Coordinate]]) -> [[AreaPoint]] {
                paths.filter { scope.bbox.intersects(polyline: $0) }.map { $0.map(AreaPoint.init) }
            }
            lines.append(.init(lineID: line.id, display: clipped(parts), smooth: clipped(smooth)))
            for station in line.stations {
                let anchor = line.displayCoordinate(for: station)
                if scope.bbox.contains(anchor) {
                    stations.append(.init(lineID: line.id, stationID: station.id, name: station.name, anchor: AreaPoint(anchor)))
                }
            }
        }
        let ids = Set(scope.junctionIDs)
        let junctions = data.junctions.filter { ids.contains($0.id) }
            .map { Junction(id: $0.id, from: AreaPoint($0.from.coordinate), to: AreaPoint($0.to.coordinate)) }
        return .init(lines: lines, stations: stations, junctions: junctions)
    }
}

/// Baseline vs patched comparison of one area.
public struct PreviewResult: Codable, Equatable, Sendable {
    public var scopeBefore: AreaScope
    public var scopeAfter: AreaScope
    public var ridesBefore: [RideOutcome]
    public var ridesAfter: [RideOutcome]
    public var problemsBefore: [Problem]
    public var problemsAfter: [Problem]
    public var geometryBefore: AreaGeometrySnapshot
    public var geometryAfter: AreaGeometrySnapshot

    /// Problem IDs present before and gone after.
    public var cleared: [String] {
        let after = Set(problemsAfter.map(\.id))
        return problemsBefore.map(\.id).filter { !after.contains($0) }
    }
    /// Problem IDs that appear only after.
    public var introduced: [String] {
        let before = Set(problemsBefore.map(\.id))
        return problemsAfter.map(\.id).filter { !before.contains($0) }
    }
}

public enum Preview {
    /// Resolves the scope's selection in both snapshots, re-detects problems,
    /// resolves the given rides and captures geometry. Serial: each AreaData's
    /// graph cache is used by one caller at a time.
    public static func run(baseline: AreaData, patched: AreaData, scope: AreaScope, trains: [Train] = [],
                           thresholds: AreaThresholds = .default, zoom: Double = 15) throws -> PreviewResult {
        let after = try AreaScope.resolve(scope.selection, data: patched)
        let ridesBefore = RideOutcome.resolve(trains, data: baseline, scope: scope)
        let ridesAfter = RideOutcome.resolve(trains, data: patched, scope: after)
        return PreviewResult(
            scopeBefore: scope, scopeAfter: after, ridesBefore: ridesBefore, ridesAfter: ridesAfter,
            problemsBefore: AreaProblems.detect(scope: scope, data: baseline, trains: trains, thresholds: thresholds),
            problemsAfter: AreaProblems.detect(scope: after, data: patched, trains: trains, thresholds: thresholds),
            geometryBefore: .capture(baseline, scope: scope, zoom: zoom),
            geometryAfter: .capture(patched, scope: after, zoom: zoom))
    }
}
