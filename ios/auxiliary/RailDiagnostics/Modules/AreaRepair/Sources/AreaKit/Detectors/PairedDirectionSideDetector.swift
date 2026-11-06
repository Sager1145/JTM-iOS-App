import Foundation
import RailCore

/// Checks a paired alignment's declared `alignmentDirection` against
/// left-hand running: walking the base line in its "down" direction, a
/// separated track lying to the LEFT is the down track. Samples the paired
/// row's segment midpoints, takes each one's signed side against the base
/// polyline, and flags when more than the threshold fraction of samples
/// contradict the declaration and the median lateral offset exceeds the
/// threshold. Severity `review`; the proposal flips the direction
/// (package file: report-only).
public enum PairedDirectionSideDetector {
    public struct Measurement: Codable, Equatable, Sendable {
        public var samples: Int
        /// Fraction of samples left of down-direction travel on the base line.
        public var leftFraction: Double
        public var medianOffsetMetres: Double
        /// Direction the side implies by majority: "down" (left) or "up" (right).
        public var impliedDirection: String
    }

    /// The side measurement of paired row `lineID` against its base, or nil
    /// when the row is not a paired alignment with a usable base span.
    public static func measure(_ data: AreaData, lineID: String) -> Measurement? {
        guard let paired = data.linesByID[lineID], let baseID = paired.alignmentOf,
              let base = data.linesByID[baseID], let first = paired.stations.first, let last = paired.stations.last,
              let a = base.stations.firstIndex(where: { $0.id == first.id }),
              let b = base.stations.firstIndex(where: { $0.id == last.id }), a != b else { return nil }
        let intervals = CompactPackage.decodeIntervals(base)
        var polyline: [Coordinate] = []
        for index in min(a, b)..<max(a, b) where intervals.indices.contains(index) {
            polyline += polyline.isEmpty ? intervals[index] : Array(intervals[index].dropFirst())
        }
        // Station order is "down" unless the base declares it "up".
        if base.stationOrderDirection == "up" { polyline.reverse() }
        guard polyline.count >= 2 else { return nil }
        let own = CompactPackage.decodeIntervals(paired).flatMap { $0 }
        let midpoints = zip(own, own.dropFirst()).map { Coordinate(lon: ($0.lon + $1.lon) / 2, lat: ($0.lat + $1.lat) / 2) }
        var left = 0, counted = 0
        var offsets: [Double] = []
        for p in midpoints {
            guard let (side, offset) = signedSide(p, polyline) else { continue }
            offsets.append(offset)
            guard offset > 0.5 else { continue }
            counted += 1
            if side > 0 { left += 1 }
        }
        guard counted > 0 else { return nil }
        offsets.sort()
        let fraction = Double(left) / Double(counted)
        return Measurement(samples: counted, leftFraction: fraction, medianOffsetMetres: offsets[offsets.count / 2],
                           impliedDirection: fraction >= 0.5 ? "down" : "up")
    }

    /// Cross-product sign (> 0 = left of travel) against the nearest base segment, with the distance.
    static func signedSide(_ p: Coordinate, _ polyline: [Coordinate]) -> (Double, Double)? {
        var best: (Double, Double)?
        for (a, b) in zip(polyline, polyline.dropFirst()) {
            let (ax, ay) = AreaGeometry.project(a, origin: p), (bx, by) = AreaGeometry.project(b, origin: p)
            let dx = bx - ax, dy = by - ay, length2 = dx * dx + dy * dy
            guard length2 > 0 else { continue }
            let t = max(0, min(1, -(ax * dx + ay * dy) / length2))
            let distance = hypot(ax + t * dx, ay + t * dy)
            if best == nil || distance < best!.1 { best = (dx * (0 - ay) - dy * (0 - ax), distance) }
        }
        return best
    }

    public static func detect(_ context: DetectionContext) -> [Problem] {
        let t = context.thresholds
        var problems: [Problem] = []
        for scoped in context.scope.lines where scoped.alignmentOf != nil {
            guard let declared = scoped.alignmentDirection, ["up", "down"].contains(declared),
                  let m = measure(context.data, lineID: scoped.lineID) else { continue }
            let contradiction = declared == "down" ? 1 - m.leftFraction : m.leftFraction
            guard contradiction > t.pairedSideContradictionFraction, m.medianOffsetMetres > t.pairedSideMinimumOffsetMetres else { continue }
            let flipped = declared == "up" ? "down" : "up"
            let anchor = context.data.linesByID[scoped.lineID]?.stations.first?.coordinate ?? context.scope.bbox.centre
            problems.append(Problem(
                id: "pairedDirectionSide/\(scoped.lineID)", kind: .pairedDirectionSide, severity: .review,
                lineIDs: [scoped.lineID, scoped.alignmentOf!], coordinate: AreaPoint(anchor), measure: contradiction,
                message: "\(scoped.lineID) is declared \(declared), but \(Int((contradiction * 100).rounded()))% of its samples lie on the \(declared == "up" ? "left" : "right") of down-direction travel on \(scoped.alignmentOf!) (left-hand running implies \(flipped)).",
                evidence: [
                    "samples \(m.samples), left fraction \(String(format: "%.2f", m.leftFraction)), median offset \(AreaProblems.format(m.medianOffsetMetres))",
                    "base station order \(context.data.linesByID[scoped.alignmentOf!]?.stationOrderDirection ?? "down (default)")",
                    "Japan runs on the left: the track left of down-direction travel is the down track",
                    "jp-2025.json is generated: mirror into app/scripts/railway/jp-directional-alignment-overrides.json",
                ],
                proposal: PatchOp(op: .packageAlignmentPairSet, key: scoped.lineID,
                                  before: .object([("alignmentDirection", .string(declared))]),
                                  after: .object([("alignmentDirection", .string(flipped))]))))
        }
        return problems
    }
}
