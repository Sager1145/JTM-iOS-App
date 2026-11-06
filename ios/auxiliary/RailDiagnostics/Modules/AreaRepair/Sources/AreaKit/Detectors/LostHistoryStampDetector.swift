import Foundation
import RailCore

/// Rail-history stamps that do not reach the area's track:
/// - a retirement or identity period touching the area that matched nothing
///   (`ApplyReport.unmatched*`);
/// - a current solver feature of a retirement's line that straddles the
///   retirement's match box (matching needs every vertex inside), so it keeps
///   no validity stamp while its neighbours do. Proposes a
///   `history.retirement.add` covering that feature (generated file:
///   report-only; mirror into jp-rail-history-events.json).
public enum LostHistoryStampDetector {
    public static func detect(_ context: DetectionContext) -> [Problem] {
        let data = context.data, scope = context.scope
        let scoped = Set(scope.historyIDs)
        var problems: [Problem] = []
        let report = data.applyReport
        for retirement in data.overlay.retirements where scoped.contains(retirement.historyId)
            && report.unmatchedRetirements.contains(retirement.historyId) {
            problems.append(unmatched(retirement.historyId, match: retirement.match, kind: "retirement", context))
        }
        for period in data.overlay.identityPeriods where scoped.contains(period.historyId)
            && report.unmatchedIdentityPeriods.contains(period.historyId) {
            problems.append(unmatched(period.historyId, match: period.match, kind: "identity period", context))
        }

        let rows = (try? data.historyRows())?.retirements ?? []
        for retirement in data.overlay.retirements where scoped.contains(retirement.historyId) {
            let match = retirement.match
            guard match.bbox.count == 4, match.targets.map({ $0.isEmpty || $0.contains("sections") }) ?? true,
                  retirement.validTo != nil || retirement.validFrom != nil else { continue }
            let box = AreaBBox(minLon: match.bbox[0], minLat: match.bbox[1], maxLon: match.bbox[2], maxLat: match.bbox[3])
            for feature in data.rawSections where feature.properties.lineName == match.lineName
                && feature.properties.operator == match.operator {
                let points = feature.lines.flatMap { $0 }
                guard !points.isEmpty, feature.lines.contains(where: scope.bbox.intersects(polyline:)),
                      feature.lines.contains(where: box.intersects(polyline:)),
                      !points.allSatisfy(box.contains),
                      !stampedByAnother(points, like: retirement, in: data.overlay.retirements) else { continue }
                guard let featureBox = AreaBBox(points: points) else { continue }
                let suffix = MissingJunctionDetector.stableHash(points.map { "\($0.lon),\($0.lat)" }.joined(separator: ";"))
                let newID = "\(retirement.historyId).area-\(suffix)"
                var proposal: PatchOp?
                if var row = rows.first(where: { $0["history_id"]?.stringValue == retirement.historyId }) {
                    row["history_id"] = .string(newID)
                    var matchJSON = row["match"] ?? .object([])
                    matchJSON["bbox"] = .array([featureBox.minLon - 1e-8, featureBox.minLat - 1e-8,
                                                featureBox.maxLon + 1e-8, featureBox.maxLat + 1e-8].map(AreaJSON.number))
                    row["match"] = matchJSON
                    proposal = PatchOp(op: .historyRetirementAdd, key: newID, before: nil, after: row)
                }
                let inside = points.filter(box.contains).count
                problems.append(Problem(
                    id: "lostHistoryStamp/\(retirement.historyId)/\(suffix)", kind: .lostHistoryStamp, severity: .error,
                    lineIDs: lineIDs(match.lineName, match.operator, scope), coordinate: AreaPoint(featureBox.centre),
                    measure: Double(points.count - inside),
                    message: "\(match.operator) \(match.lineName): a track feature straddles retirement \(retirement.historyId)'s box (\(inside)/\(points.count) vertices inside), so it keeps no \(retirement.validTo != nil ? "valid_to \(retirement.validTo!)" : "valid_from \(retirement.validFrom!)") stamp.",
                    evidence: ["retirement bbox \(match.bbox)", "feature bbox [\(featureBox.minLon), \(featureBox.minLat), \(featureBox.maxLon), \(featureBox.maxLat)]",
                               "rail-history.json is generated: mirror into app/scripts/railway/jp-rail-history-events.json"],
                    proposal: proposal))
            }
        }
        return problems
    }

    static func unmatched(_ id: String, match: RailHistoryOverlay.Retirement.Match, kind: String, _ context: DetectionContext) -> Problem {
        let centre = match.bbox.count == 4
            ? Coordinate(lon: (match.bbox[0] + match.bbox[2]) / 2, lat: (match.bbox[1] + match.bbox[3]) / 2)
            : context.scope.bbox.centre
        return Problem(
            id: "lostHistoryStamp/\(id)", kind: .lostHistoryStamp, severity: .error,
            lineIDs: lineIDs(match.lineName, match.operator, context.scope), coordinate: AreaPoint(centre), measure: 0,
            message: "\(kind.capitalized) \(id) (\(match.operator) \(match.lineName)) matched no feature; its stamp is lost.",
            evidence: ["match bbox \(match.bbox)", "matching requires the same N02 line/operator and every vertex inside the box",
                       "rail-history.json is generated: mirror into app/scripts/railway/jp-rail-history-events.json"])
    }

    /// Another retirement with the same line, operator and bounds that fully covers the feature.
    static func stampedByAnother(_ points: [Coordinate], like retirement: RailHistoryOverlay.Retirement,
                                 in all: [RailHistoryOverlay.Retirement]) -> Bool {
        all.contains { other in
            other.historyId != retirement.historyId && other.match.lineName == retirement.match.lineName
                && other.match.operator == retirement.match.operator && other.validTo == retirement.validTo
                && other.validFrom == retirement.validFrom && other.match.bbox.count == 4
                && points.allSatisfy { p in
                    p.lon >= other.match.bbox[0] && p.lon <= other.match.bbox[2]
                        && p.lat >= other.match.bbox[1] && p.lat <= other.match.bbox[3]
                }
        }
    }

    static func lineIDs(_ lineName: String, _ operatorName: String, _ scope: AreaScope) -> [String] {
        scope.lines.filter { $0.name == lineName && $0.operatorName == operatorName }.map(\.lineID)
    }
}
