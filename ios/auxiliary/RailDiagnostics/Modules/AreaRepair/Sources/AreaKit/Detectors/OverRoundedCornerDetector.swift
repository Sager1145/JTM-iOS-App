import Foundation
import RailCore
import RailInspection

/// Display corners (DiagnosticCandidate sharp turns) whose diagnostics smooth
/// path, rendered at the threshold zoom, strays farther than the threshold
/// from the display polyline within the corner window. Evidence only: corner
/// rounding is owned elsewhere, so no repair op is proposed.
public enum OverRoundedCornerDetector {
    public static func detect(_ context: DetectionContext) -> [Problem] {
        let data = context.data, scope = context.scope, t = context.thresholds
        let style = StrokeStyle.diagnosticsDefault(zoom: t.roundingZoom)
        var problems: [Problem] = []
        for scoped in scope.lines {
            guard let line = data.linesByID[scoped.lineID], let parts = data.displayParts[line.id], !parts.isEmpty else { continue }
            let intervals = CompactPackage.decodeDisplayIntervals(line)
            let inputs = scoped.intervalIndices.filter(intervals.indices.contains).map { index in
                InspectionInput(id: "\(line.id)#\(index)", lineID: line.id, lineName: line.name, operatorName: line.operator ?? "",
                                intervalIndex: index, fromStationID: line.stations[index % line.stations.count].id,
                                toStationID: line.stations[(index + 1) % line.stations.count].id,
                                fromName: line.stations[index % line.stations.count].name,
                                toName: line.stations[(index + 1) % line.stations.count].name,
                                source: [], display: intervals[index].map { .init(longitude: $0.lon, latitude: $0.lat) },
                                hasDisplayOverride: line.displayIntervalCoordinates[index] != nil)
            }
            let corners = DiagnosticCandidate.tasks(selected: inputs, context: inputs).compactMap { task -> (String, DiagnosticCandidate.Corner)? in
                guard task.category == "sharpTurn", let corner = task.corner, corner.turnDegrees >= t.cornerMinimumDegrees,
                      scope.bbox.contains(Coordinate(lon: corner.coordinate.longitude, lat: corner.coordinate.latitude)) else { return nil }
                return (task.itemIDs.first ?? line.id, corner)
            }
            guard !corners.isEmpty else { continue }
            let rendered = AreaStrokeGeometry.render(
                display: parts, stations: line.displayStations.map(\.coordinate),
                mapPointsPerPoint: StrokeStyle.mapPointsPerPoint(zoom: t.roundingZoom), style: style,
                literalSpans: DisplayLiteralSpans.resolve(line, parts: parts))
            let smooth = rendered.paths.map { AreaGeometry.densify($0, step: t.cornerSampleMetres) }
            for (itemID, corner) in corners {
                let c = Coordinate(lon: corner.coordinate.longitude, lat: corner.coordinate.latitude)
                var worst = 0.0
                for path in smooth {
                    for sample in path where AreaGeometry.distance(sample, c) <= t.cornerWindowMetres {
                        worst = max(worst, AreaGeometry.nearestDistance(to: parts, from: sample) ?? 0)
                    }
                }
                guard worst > t.cornerDeviationMetres else { continue }
                problems.append(Problem(
                    id: "overRoundedCorner/\(itemID)/\(corner.displayVertexIndex)", kind: .overRoundedCorner, severity: .warning,
                    lineIDs: [line.id], coordinate: AreaPoint(c), measure: worst,
                    message: "\(itemID) display vertex \(corner.displayVertexIndex) (\(String(format: "%.0f", corner.turnDegrees))°): the smooth stroke at zoom \(t.roundingZoom) leaves the line by \(AreaProblems.format(worst)).",
                    evidence: ["style \(style.contract)", "\(AreaStrokeGeometry.revision)",
                               "window \(t.cornerWindowMetres) m, samples every \(t.cornerSampleMetres) m",
                               "rounding is owned by the stroke session; evidence only"]))
            }
        }
        return problems
    }
}
