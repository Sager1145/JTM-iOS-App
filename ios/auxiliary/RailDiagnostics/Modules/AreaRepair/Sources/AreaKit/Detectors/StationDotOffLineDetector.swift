import Foundation
import RailCore

/// A package station anchor farther than the threshold from its own line.
/// The display polyline is pinned to the anchor (CompactPackage overwrites
/// interval ends with it), so "own line" is measured both against the
/// DisplayParts strokes and against the line's own surveyed solver track
/// (same N02 name/operator); the larger distance decides. Proposes a
/// `package.stationAnchor.set` to the nearest surveyed point (package file:
/// report-only); the N02 station coordinate is listed as an alternative.
public enum StationDotOffLineDetector {
    public static func detect(_ context: DetectionContext) -> [Problem] {
        let data = context.data, scope = context.scope
        var problems: [Problem] = []
        for scoped in scope.lines {
            guard let line = data.linesByID[scoped.lineID] else { continue }
            let survey = data.featureIndices(lineName: line.name, operatorName: line.operator, in: scope.sectionFeatureIndices)
                .flatMap { data.sections[$0].lines }
            let display = data.displayParts[line.id] ?? []
            for station in line.stations {
                let anchor = line.displayCoordinate(for: station)
                guard scope.bbox.contains(anchor) else { continue }
                let displayMetres = AreaGeometry.nearestDistance(to: display, from: anchor)
                let nearestSurvey = survey.compactMap { AreaGeometry.nearest(on: $0, to: anchor) }.min { $0.metres < $1.metres }
                let measure = max(displayMetres ?? 0, nearestSurvey?.metres ?? 0)
                guard measure > context.thresholds.stationOffLineMetres else { continue }
                let n02 = data.stations.features.first { Stations.stationCode($0) == station.id }
                    .flatMap { AreaScope.points($0.geometry?.coordinates).first }
                var proposal: PatchOp?
                if let target = nearestSurvey?.point {
                    let after = AreaGeometry.rounded(target)
                    proposal = PatchOp(op: .packageStationAnchorSet, key: "\(line.id)/\(station.id)",
                                       before: .array([.number(anchor.lon), .number(anchor.lat)]),
                                       after: .array([.number(after.lon), .number(after.lat)]))
                }
                problems.append(Problem(
                    id: "stationDotOffLine/\(line.id)/\(station.id)", kind: .stationDotOffLine,
                    severity: .error, lineIDs: [line.id], stationCode: station.id, coordinate: AreaPoint(anchor),
                    measure: measure,
                    message: "\(station.name) (\(station.id)) on \(line.id): the station dot is \(AreaProblems.format(measure)) from its own line.",
                    evidence: [
                        "display distance \(displayMetres.map(AreaProblems.format) ?? "n/a")",
                        "surveyed track distance \(nearestSurvey.map { AreaProblems.format($0.metres) } ?? "n/a (no own-identity track in area)")",
                        n02.map { "N02 station coordinate [\($0.lon), \($0.lat)] (\(AreaProblems.format(AreaGeometry.distance(anchor, $0))) away)" } ?? "no N02 station feature",
                        "jp-2025.json is generated: mirror into the package builder's station anchors",
                    ],
                    proposal: proposal))
            }
        }
        return problems
    }
}
