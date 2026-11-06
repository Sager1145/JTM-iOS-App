import Foundation
import RailCore

/// Paired one-direction alignments whose scoped intervals have no source
/// certification in either station order (RouteNetwork.sourceCertification,
/// as OnEdgeCertificationTests certifies a span), and crossing rides whose
/// in-area sections resolve uncertified. Proposes a `package.alignmentPair.set`
/// draft with the line's direction fields (package file: report-only; mirror
/// into jp-directional-alignment-overrides.json).
public enum UncertifiedPairedTrackDetector {
    /// Forward / reverse certification of one interval.
    public static func certification(_ data: AreaData, lineID: String, intervalIndex: Int) -> (forward: Bool, reverse: Bool)? {
        guard let line = data.networkLine(lineID), line.intervals.indices.contains(intervalIndex) else { return nil }
        let interval = line.intervals[intervalIndex]
        func certified(_ from: String, _ to: String) -> Bool {
            data.network.sourceCertification(for: RouteHints(
                requiredLineIDs: [lineID], sectionCodes: [interval.code],
                fromStationCode: from, toStationCode: to)) != nil
        }
        return (certified(interval.fromStationCode, interval.toStationCode),
                certified(interval.toStationCode, interval.fromStationCode))
    }

    public static func detect(_ context: DetectionContext) -> [Problem] {
        let data = context.data
        var problems: [Problem] = []
        for scoped in context.scope.lines where scoped.isPaired {
            guard let line = data.linesByID[scoped.lineID], let networkLine = data.networkLine(scoped.lineID) else { continue }
            for index in scoped.intervalIndices {
                guard let result = certification(data, lineID: scoped.lineID, intervalIndex: index),
                      !result.forward, !result.reverse else { continue }
                let interval = networkLine.intervals[index]
                let fields: [(String, String?)] = [
                    ("alignmentDirection", line.alignmentDirection),
                    ("stationOrderDirection", line.stationOrderDirection),
                    ("permittedTraversal", line.permittedTraversal),
                ]
                let current = AreaJSON.object(fields.map { ($0.0, $0.1.map(AreaJSON.string) ?? .null) })
                problems.append(Problem(
                    id: "uncertifiedPairedTrack/\(scoped.lineID)/\(index)", kind: .uncertifiedPairedTrack, severity: .error,
                    lineIDs: [scoped.lineID] + [scoped.alignmentOf].compactMap { $0 } + scoped.alignmentPairs.map(\.with),
                    stationCode: interval.fromStationCode,
                    coordinate: AreaPoint(lon: (interval.from.lon + interval.to.lon) / 2, lat: (interval.from.lat + interval.to.lat) / 2),
                    measure: 0,
                    message: "\(scoped.lineID) interval \(index) (\(interval.fromStationCode)→\(interval.toStationCode)) is a paired alignment with no source certification in either direction.",
                    evidence: ["code \(interval.code)",
                               "alignmentOf=\(scoped.alignmentOf ?? "nil") alignmentDirection=\(scoped.alignmentDirection ?? "nil") stationOrderDirection=\(scoped.stationOrderDirection ?? "nil") permittedTraversal=\(scoped.permittedTraversal ?? "nil")",
                               "pairs: " + scoped.alignmentPairs.map { "\($0.with) \($0.from)→\($0.to) \($0.direction)" }.joined(separator: "; "),
                               "jp-2025.json is generated: mirror into app/scripts/railway/jp-directional-alignment-overrides.json"],
                    proposal: PatchOp(op: .packageAlignmentPairSet, key: scoped.lineID, before: current, after: current)))
            }
        }
        problems += rideProblems(context)
        return problems
    }

    /// Crossing rides whose in-area sections resolve uncertified.
    static func rideProblems(_ context: DetectionContext) -> [Problem] {
        guard !context.trains.isEmpty else { return [] }
        var problems: [Problem] = []
        for outcome in RideOutcome.resolve(context.trains, data: context.data, scope: context.scope) {
            for section in outcome.sections where section.inArea && !section.certified {
                problems.append(Problem(
                    id: "uncertifiedRide/\(outcome.trainID)/\(section.index)", kind: .uncertifiedPairedTrack, severity: .warning,
                    lineIDs: section.lineIDs, stationCode: section.fromCode,
                    coordinate: AreaPoint(context.scope.bbox.centre), measure: 0,
                    message: "Ride \(outcome.trainID) section \(section.index) (\(section.from ?? "?")→\(section.to ?? "?")) crosses the area uncertified.",
                    evidence: ["disposition \(outcome.disposition)", "provenance \(section.provenance ?? "none")"]))
            }
        }
        return problems
    }
}
