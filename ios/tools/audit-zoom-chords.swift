import Foundation

private struct LaneRowInput: Decodable { let from: Double; let to: Double; let lane: Double }
private struct FollowInput: Decodable {
    let from: Double; let to: Double; let canonFrom: Double; let canonTo: Double
    let coordinates: [[Double]]; let measures: [Double]
}
private struct StrokePartInput: Decodable {
    let lineId: String; let partIndex: Int; let coordinates: [[Double]]; let measures: [Double]
    let totalMetres: Double; let rows: [LaneRowInput]; let anchors: [Int]; let follows: [FollowInput]
}
private struct PlainPartInput: Decodable {
    let lineId: String; let partIndex: Int; let lane: Double; let coordinates: [[Double]]
}
private struct AuditInput: Decodable {
    let region: String; let version: String; let packageLineCount: Int
    let packageStationMembershipCount: Int; let continuousPartCount: Int; let plainPartCount: Int
    let parts: [StrokePartInput]; let plain: [PlainPartInput]
}
private struct Candidate: Encodable {
    let region: String; let lineId: String; let partIndex: Int; let appZoom: Double
    let projectionZoom: Double; let mode: String; let stage: String
    let fromMeasure: Double; let toMeasure: Double; let spanMetres: Double
    let previousMaxEdgeMetres: Double; let edgeRatio: Double
    let deviationPx: Double; let endpointAllowancePx: Double; let excessPx: Double
    let longitude: Double; let latitude: Double
}
private struct CrossingCandidate: Encodable {
    let region: String; let lineId: String; let partIndex: Int; let appZoom: Double
    let projectionZoom: Double; let mode: String; let stage: String
    let firstMeasure: Double; let secondMeasure: Double
    let measureSeparationMetres: Double; let sourceSeparationPx: Double
    let loopDiameterPx: Double; let intersectionAngleDegrees: Double
    let longitude: Double; let latitude: Double
}
private struct AuditOutput: Encodable {
    let region: String; let version: String; let packageLineCount: Int
    let packageStationMembershipCount: Int; let continuousPartCount: Int; let plainPartCount: Int
    let zooms: [Double]; let continuousBuilds: Int; let plainSimplifierBuilds: Int
    let plainLaneBuilds: Int; let candidates: [Candidate]
    let crossingCandidates: [CrossingCandidate]
}

private typealias Point = ContinuousStroke.Point
private struct Stage { let points: [Point]; let measures: [Double] }
private struct Crossing {
    let firstMeasure: Double; let secondMeasure: Double
    let firstSpan: Double; let secondSpan: Double; let point: Point; let angleDegrees: Double
}

private func projected(_ coordinates: [[Double]], zoom: Double) -> [Point] {
    coordinates.map { ContinuousStroke.project(lon: $0[0], lat: $0[1], zoom: zoom) }
}

private func interpolate(_ stage: Stage, at measure: Double) -> Point {
    guard stage.points.count > 1 else { return stage.points.first ?? Point(x: 0, y: 0) }
    if measure <= stage.measures[0] { return stage.points[0] }
    if measure >= stage.measures.last! { return stage.points.last! }
    var lo = 0, hi = stage.measures.count - 1
    while lo + 1 < hi {
        let mid = (lo + hi) / 2
        if stage.measures[mid] <= measure { lo = mid } else { hi = mid }
    }
    let span = stage.measures[hi] - stage.measures[lo]
    let t = span > 0 ? (measure - stage.measures[lo]) / span : 0
    let a = stage.points[lo], b = stage.points[hi]
    return Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

private func distance(_ p: Point, to a: Point, _ b: Point) -> Double {
    let dx = b.x - a.x, dy = b.y - a.y
    let square = dx * dx + dy * dy
    if square == 0 { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / square))
    return hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t))
}

private func lowerBound(_ values: [Double], _ target: Double) -> Int {
    var low = 0, high = values.count
    while low < high {
        let middle = (low + high) / 2
        if values[middle] < target { low = middle + 1 } else { high = middle }
    }
    return low
}

private func upperBound(_ values: [Double], _ target: Double) -> Int {
    var low = 0, high = values.count
    while low < high {
        let middle = (low + high) / 2
        if values[middle] <= target { low = middle + 1 } else { high = middle }
    }
    return low
}

private func stageCandidates(
    region: String, lineId: String, partIndex: Int, appZoom: Double, mode: String,
    stageName: String, previous: Stage, current: Stage
) -> [Candidate] {
    guard previous.points.count >= 2, current.points.count >= 2 else { return [] }
    var out: [Candidate] = []
    for index in 1..<current.points.count {
        let m0 = current.measures[index - 1], m1 = current.measures[index]
        guard m1 > m0 else { continue }
        let insideStart = upperBound(previous.measures, m0 + 1e-6)
        let insideEnd = lowerBound(previous.measures, m1 - 1e-6)
        guard insideEnd - insideStart >= 2 else { continue }
        var reference = [interpolate(previous, at: m0)]
        reference.append(contentsOf: (insideStart..<insideEnd).map { previous.points[$0] })
        reference.append(interpolate(previous, at: m1))
        var maxDeviation = 0.0
        for point in reference { maxDeviation = max(maxDeviation, distance(point, to: current.points[index - 1], current.points[index])) }
        let endpointAllowance = max(
            hypot(current.points[index - 1].x - reference[0].x, current.points[index - 1].y - reference[0].y),
            hypot(current.points[index].x - reference.last!.x, current.points[index].y - reference.last!.y))
        let excess = maxDeviation - endpointAllowance
        var previousMaxEdge = 0.0
        let localStart = lowerBound(previous.measures, m0)
        let localEnd = upperBound(previous.measures, m1)
        if localEnd - localStart >= 2 {
            for j in (localStart + 1)..<localEnd {
                previousMaxEdge = max(previousMaxEdge, previous.measures[j] - previous.measures[j - 1])
            }
        } else { previousMaxEdge = m1 - m0 }
        let ratio = previousMaxEdge > 0 ? (m1 - m0) / previousMaxEdge : 1
        // A review candidate must swallow several predecessor edges and bow
        // by more than one visible point beyond ordinary endpoint movement.
        // This is deliberately a review threshold, not a correctness bound;
        // the production simplification invariant remains 0.0625 px.
        guard ratio >= 2.5, excess > 1, maxDeviation > 1.5 else { continue }
        let midpoint = Point(
            x: (current.points[index - 1].x + current.points[index].x) / 2,
            y: (current.points[index - 1].y + current.points[index].y) / 2)
        let coordinate = ContinuousStroke.unproject(midpoint, zoom: appZoom - 1)
        out.append(Candidate(
            region: region, lineId: lineId, partIndex: partIndex, appZoom: appZoom,
            projectionZoom: appZoom - 1, mode: mode, stage: stageName,
            fromMeasure: m0, toMeasure: m1, spanMetres: m1 - m0,
            previousMaxEdgeMetres: previousMaxEdge, edgeRatio: ratio,
            deviationPx: maxDeviation, endpointAllowancePx: endpointAllowance, excessPx: excess,
            longitude: coordinate.lon, latitude: coordinate.lat))
    }
    return out
}

private func crossings(_ stage: Stage) -> [Crossing] {
    guard stage.points.count >= 4 else { return [] }
    struct Segment {
        let index: Int; let minX: Double; let maxX: Double; let minY: Double; let maxY: Double
    }
    let segments = (1..<stage.points.count).map { index -> Segment in
        let a = stage.points[index - 1], b = stage.points[index]
        return Segment(index: index - 1, minX: min(a.x, b.x), maxX: max(a.x, b.x),
                       minY: min(a.y, b.y), maxY: max(a.y, b.y))
    }.sorted { $0.minX < $1.minX }
    func cross(_ a: Point, _ b: Point) -> Double { a.x * b.y - a.y * b.x }
    var active: [Segment] = [], found: [Crossing] = []
    for segment in segments {
        active.removeAll { $0.maxX < segment.minX }
        for other in active {
            if other.maxY < segment.minY || segment.maxY < other.minY { continue }
            let i = segment.index, j = other.index
            if abs(i - j) <= 1 || (min(i, j) == 0 && max(i, j) == stage.points.count - 2) { continue }
            let p = stage.points[i], p2 = stage.points[i + 1]
            let q = stage.points[j], q2 = stage.points[j + 1]
            let r = Point(x: p2.x - p.x, y: p2.y - p.y)
            let s = Point(x: q2.x - q.x, y: q2.y - q.y)
            let denominator = cross(r, s)
            if abs(denominator) <= 1e-12 { continue }
            let qp = Point(x: q.x - p.x, y: q.y - p.y)
            let t = cross(qp, s) / denominator, u = cross(qp, r) / denominator
            // Shared vertices and floating-point touches are topology seams,
            // not self-crossings. Require a strict interior intersection.
            let epsilon = 1e-8
            if t <= epsilon || t >= 1 - epsilon || u <= epsilon || u >= 1 - epsilon { continue }
            let mi = stage.measures[i] + (stage.measures[i + 1] - stage.measures[i]) * t
            let mj = stage.measures[j] + (stage.measures[j + 1] - stage.measures[j]) * u
            let first = min(mi, mj), second = max(mi, mj)
            let firstSpan = mi <= mj ? stage.measures[i + 1] - stage.measures[i]
                : stage.measures[j + 1] - stage.measures[j]
            let secondSpan = mi <= mj ? stage.measures[j + 1] - stage.measures[j]
                : stage.measures[i + 1] - stage.measures[i]
            found.append(Crossing(firstMeasure: first, secondMeasure: second,
                firstSpan: firstSpan, secondSpan: secondSpan,
                point: Point(x: p.x + r.x * t, y: p.y + r.y * t),
                angleDegrees: abs(atan2(cross(r, s), r.x * s.x + r.y * s.y)) * 180 / .pi))
        }
        active.append(segment)
    }
    return found
}

private func newCrossingCandidates(
    region: String, lineId: String, partIndex: Int, appZoom: Double, mode: String,
    stageName: String, previous: Stage, current: Stage
) -> [CrossingCandidate] {
    let before = crossings(previous)
    return crossings(current).compactMap { crossing in
        let existed = before.contains { held in
            abs(held.firstMeasure - crossing.firstMeasure)
                <= max(2, held.firstSpan + crossing.firstSpan)
            && abs(held.secondMeasure - crossing.secondMeasure)
                <= max(2, held.secondSpan + crossing.secondSpan)
        }
        guard !existed else { return nil }
        let beforeA = interpolate(previous, at: crossing.firstMeasure)
        let beforeB = interpolate(previous, at: crossing.secondMeasure)
        let sourceSeparation = hypot(beforeA.x - beforeB.x, beforeA.y - beforeB.y)
        let betweenStart = lowerBound(current.measures, crossing.firstMeasure)
        let betweenEnd = upperBound(current.measures, crossing.secondMeasure)
        var loop = [interpolate(current, at: crossing.firstMeasure)]
        if betweenStart < betweenEnd {
            loop.append(contentsOf: (betweenStart..<betweenEnd).map { current.points[$0] })
        }
        loop.append(interpolate(current, at: crossing.secondMeasure))
        let diameter = hypot((loop.map(\.x).max() ?? 0) - (loop.map(\.x).min() ?? 0),
                             (loop.map(\.y).max() ?? 0) - (loop.map(\.y).min() ?? 0))
        let coordinate = ContinuousStroke.unproject(crossing.point, zoom: appZoom - 1)
        return CrossingCandidate(region: region, lineId: lineId, partIndex: partIndex,
            appZoom: appZoom, projectionZoom: appZoom - 1, mode: mode, stage: stageName,
            firstMeasure: crossing.firstMeasure, secondMeasure: crossing.secondMeasure,
            measureSeparationMetres: crossing.secondMeasure - crossing.firstMeasure,
            sourceSeparationPx: sourceSeparation, loopDiameterPx: diameter,
            intersectionAngleDegrees: crossing.angleDegrees,
            longitude: coordinate.lon, latitude: coordinate.lat)
    }
}

private func scale(atAppZoom zoom: Double) -> Double {
    min(1, max(1.0 / 3.0, pow(2, (zoom - 8) / 2)))
}
private func stroke(
    part: StrokePartInput, pixels: [Point], follows: [ContinuousStroke.Follow],
    rows: [ContinuousStroke.LaneRow], laneGap: Double, radius: Double,
    minimumRadius: Double, strict: Bool,
    joinStart: ContinuousStroke.Join? = nil, joinEnd: ContinuousStroke.Join? = nil
) -> Stage {
    let value = ContinuousStroke.buildStroke(pixels, options: .init(
        measures: part.measures, rows: rows, totalMetres: part.totalMetres,
        laneGapPx: laneGap, minRampPx: 24, cornerRadiusPx: radius,
        minCornerRadiusPx: minimumRadius, anchors: part.anchors, follows: follows,
        joinStart: joinStart, joinEnd: joinEnd,
        enforceMinimumCornerRadius: strict))
    return Stage(points: value.points, measures: value.measures)
}

/// The production pre-lane stage, assembled from ContinuousStroke's own
/// internal helpers. This gives the detector the geometry a follow/taper is
/// meant to produce, instead of treating an intentional canonical alignment
/// as deviation from the follower's survey.
private func preLaneStage(
    part: StrokePartInput, pixels: [Point], follows: [ContinuousStroke.Follow],
    jointStart: Bool = false, jointEnd: Bool = false
) -> Stage {
    let (clean, cleanMeasures, _, anchorSet) = ContinuousStroke.dedupe(
        pixels, measures: part.measures, anchors: part.anchors)
    guard clean.count >= 2 else { return Stage(points: clean, measures: cleanMeasures) }
    let cleanPx = ContinuousStroke.cumulativeLengths(clean).last ?? 0
    let cleanMetres = (cleanMeasures.last ?? 0) - (cleanMeasures.first ?? 0)
    let metresPerPx = cleanPx > 0 && cleanMetres > 0 ? cleanMetres / cleanPx : 0
    let substituted = ContinuousStroke.substituteFollows(
        clean, measures: cleanMeasures, anchors: anchorSet, follows: follows,
        jointStart: jointStart, jointEnd: jointEnd)
    var followed = substituted
    if substituted.points.count != clean.count || substituted.points != clean {
        let foldTurn = ContinuousStroke.foldTurnDegrees * Double.pi / 180
        var cleanReversal = [Bool](repeating: false, count: clean.count)
        if clean.count >= 3 {
            for index in 1..<(clean.count - 1) {
                cleanReversal[index] = abs(ContinuousStroke.turnAt(clean, index)) > foldTurn
            }
        }
        var reversal = [Bool](repeating: false, count: substituted.points.count)
        for (index, at) in substituted.map.enumerated() where at >= 0 {
            reversal[at] = cleanReversal[index] || anchorSet.contains(index)
        }
        let unfolded = ContinuousStroke.removeFolds(substituted.points, reversal: reversal)
        followed = (
            points: unfolded.points,
            measures: unfolded.map.enumerated().compactMap { index, at in
                at >= 0 ? substituted.measures[index] : nil
            },
            map: substituted.map.map { $0 < 0 ? -1 : unfolded.map[$0] })
    }
    var followedAnchors = Set<Int>()
    for index in anchorSet where followed.map[index] >= 0 { followedAnchors.insert(followed.map[index]) }
    let tapered = ContinuousStroke.taperJogs(
        followed.points, measures: followed.measures, anchors: followedAnchors,
        metresPerPx: metresPerPx)
    return Stage(points: tapered.points, measures: tapered.measures)
}

private func join(
    for part: StrokePartInput, atEnd: Bool, allParts: [StrokePartInput], projectionZoom: Double
) -> ContinuousStroke.Join? {
    let neighbourIndex = part.partIndex + (atEnd ? 1 : -1)
    guard let other = allParts.first(where: {
        $0.lineId == part.lineId && $0.partIndex == neighbourIndex
    }) else { return nil }
    let own = projected(part.coordinates, zoom: projectionZoom)
    let theirs = projected(other.coordinates, zoom: projectionZoom)
    guard own.count >= 2, theirs.count >= 2 else { return nil }
    let arriving = atEnd ? own : theirs
    let leaving = atEnd ? theirs : own
    guard arriving.last == leaving.first else { return nil }
    func unit(_ a: Point, _ b: Point) -> Point? {
        let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
        return length > 0 ? Point(x: dx / length, y: dy / length) : nil
    }
    guard let incoming = unit(arriving[arriving.count - 2], arriving.last!),
          let outgoing = unit(leaving[0], leaving[1]) else { return nil }
    let otherRows = other.rows.map { ContinuousStroke.LaneRow(from: $0.from, to: $0.to, lane: $0.lane) }
    let lanes = ContinuousStroke.terminalLanes(rows: otherRows, total: other.totalMetres)
    return ContinuousStroke.Join(
        lane: atEnd ? lanes.start : lanes.end, incoming: incoming, outgoing: outgoing)
}

private func coordinateMeasures(_ coordinates: [[Double]]) -> [Double] {
    let values = coordinates.map { Coordinate(lon: $0[0], lat: $0[1]) }
    var out = [Double](repeating: 0, count: values.count)
    for i in 1..<values.count { out[i] = out[i - 1] + Geometry.distanceMeters(values[i - 1], values[i]) }
    return out
}

@main private enum ZoomChordAudit {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else { throw NSError(domain: "audit", code: 2, userInfo: [NSLocalizedDescriptionKey: "input JSON path required"]) }
        let input = try JSONDecoder().decode(AuditInput.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let zooms = args.dropFirst(2).compactMap(Double.init)
        let requestedZooms = zooms.isEmpty ? [10, 11, 12, 13, 14, 15, 16] : zooms
        let strict = !args.contains("--legacy")
        let onlyLine = args.compactMap { $0.hasPrefix("--line=") ? String($0.dropFirst(7)) : nil }.first
        let mode = strict ? "production" : "legacy"
        var candidates: [Candidate] = []
        var crossingCandidates: [CrossingCandidate] = []
        var continuousBuilds = 0, plainSimplifierBuilds = 0, plainLaneBuilds = 0

        for appZoom in requestedZooms {
            if appZoom <= 0 { continue }
            let projectionZoom = appZoom - 1
            let styleScale = scale(atAppZoom: appZoom)
            // Cold-build bucket. Camera hysteresis is stateful and outside a
            // single-zoom geometry audit; boundary sweeps include both sides.
            let gap = 2.7 * styleScale * LaneLOD.resolve(zoom: appZoom, previousBucket: nil).scale
            for part in input.parts where onlyLine == nil || part.lineId == onlyLine {
                let pixels = projected(part.coordinates, zoom: projectionZoom)
                let follows = part.follows.map { follow in ContinuousStroke.Follow(
                    from: follow.from, to: follow.to, canonFrom: follow.canonFrom, canonTo: follow.canonTo,
                    points: projected(follow.coordinates, zoom: projectionZoom), measures: follow.measures) }
                let rows = part.rows.map { ContinuousStroke.LaneRow(from: $0.from, to: $0.to, lane: $0.lane) }
                let actualJoinStart = join(for: part, atEnd: false, allParts: input.parts, projectionZoom: projectionZoom)
                let actualJoinEnd = join(for: part, atEnd: true, allParts: input.parts, projectionZoom: projectionZoom)
                let zeroJoinStart = actualJoinStart.map { ContinuousStroke.Join(
                    lane: 0, incoming: $0.incoming, outgoing: $0.outgoing) }
                let zeroJoinEnd = actualJoinEnd.map { ContinuousStroke.Join(
                    lane: 0, incoming: $0.incoming, outgoing: $0.outgoing) }
                let sourceExpected = preLaneStage(part: part, pixels: pixels, follows: [])
                let followExpected = preLaneStage(part: part, pixels: pixels, follows: follows,
                    jointStart: actualJoinStart != nil, jointEnd: actualJoinEnd != nil)
                let source = stroke(part: part, pixels: pixels, follows: [], rows: [], laneGap: 0, radius: 0, minimumRadius: 0, strict: strict)
                let followed = stroke(part: part, pixels: pixels, follows: follows, rows: [], laneGap: 0,
                    radius: 0, minimumRadius: 0, strict: strict,
                    joinStart: zeroJoinStart, joinEnd: zeroJoinEnd)
                let laned = stroke(part: part, pixels: pixels, follows: follows, rows: rows, laneGap: gap,
                    radius: 0, minimumRadius: 0, strict: strict,
                    joinStart: actualJoinStart, joinEnd: actualJoinEnd)
                let final = stroke(part: part, pixels: pixels, follows: follows, rows: rows, laneGap: gap,
                    radius: 3.6 * styleScale, minimumRadius: max(1, 3 * styleScale), strict: strict,
                    joinStart: actualJoinStart, joinEnd: actualJoinEnd)
                candidates += stageCandidates(region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                    appZoom: appZoom, mode: mode, stageName: "source_simplify", previous: sourceExpected, current: source)
                candidates += stageCandidates(region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                    appZoom: appZoom, mode: mode, stageName: "follow_simplify", previous: followExpected, current: followed)
                candidates += stageCandidates(region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                    appZoom: appZoom, mode: mode, stageName: "lane_offset_or_fold", previous: followed, current: laned)
                candidates += stageCandidates(region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                    appZoom: appZoom, mode: mode, stageName: "fillet", previous: laned, current: final)
                crossingCandidates += newCrossingCandidates(
                    region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                    appZoom: appZoom, mode: mode, stageName: "continuous_source_simplify_new_self_intersection",
                    previous: sourceExpected, current: source)
                if !follows.isEmpty {
                    crossingCandidates += newCrossingCandidates(
                        region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                        appZoom: appZoom, mode: mode, stageName: "continuous_follow_simplify_new_self_intersection",
                        previous: followExpected, current: followed)
                }
                crossingCandidates += newCrossingCandidates(
                    region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                    appZoom: appZoom, mode: mode, stageName: "continuous_lane_new_self_intersection",
                    previous: followed, current: laned)
                crossingCandidates += newCrossingCandidates(
                    region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                    appZoom: appZoom, mode: mode, stageName: "continuous_fillet_new_self_intersection",
                    previous: laned, current: final)
                continuousBuilds += 4
            }

            for part in input.plain where onlyLine == nil || part.lineId == onlyLine {
                let measures = coordinateMeasures(part.coordinates)
                if part.lane == 0 {
                    let raw = Stage(points: projected(part.coordinates, zoom: projectionZoom), measures: measures)
                    let minX = raw.points.map(\.x).min()!, maxX = raw.points.map(\.x).max()!
                    let minY = raw.points.map(\.y).min()!, maxY = raw.points.map(\.y).max()!
                    let centerLat = ContinuousStroke.unproject(
                        Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
                        zoom: projectionZoom).lat
                    let metresPerMapPoint = cos(centerLat * .pi / 180) * (2 * .pi * 6_378_137) / 268_435_456
                    let mapPointsPerScreenPoint = pow(2, 20 - appZoom)
                    let epsilon = metresPerMapPoint * mapPointsPerScreenPoint * 0.0625
                    let coords = part.coordinates.map { Coordinate(lon: $0[0], lat: $0[1]) }
                    let kept = Geometry.douglasPeuckerIndices(coords, epsilonMeters: epsilon)
                    let simplified = Stage(points: kept.map { raw.points[$0] }, measures: kept.map { measures[$0] })
                    candidates += stageCandidates(region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                        appZoom: appZoom, mode: mode, stageName: "noncontinuous_final_simplifier", previous: raw, current: simplified)
                    crossingCandidates += newCrossingCandidates(
                        region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                        appZoom: appZoom, mode: mode, stageName: "noncontinuous_final_new_self_intersection",
                        previous: raw, current: simplified)
                    plainSimplifierBuilds += 1
                } else {
                    let synthetic = StrokePartInput(lineId: part.lineId, partIndex: part.partIndex,
                        coordinates: part.coordinates, measures: measures, totalMetres: measures.last ?? 0,
                        rows: [], anchors: [0, max(0, part.coordinates.count - 1)], follows: [])
                    let pixels = projected(part.coordinates, zoom: projectionZoom)
                    let raw = Stage(points: pixels, measures: measures)
                    let shifted = stroke(part: synthetic, pixels: pixels, follows: [],
                        rows: [ContinuousStroke.LaneRow(from: 0, to: measures.last ?? 0, lane: part.lane)],
                        laneGap: 2.7 * styleScale, radius: 3.6 * styleScale,
                        minimumRadius: max(1, 3 * styleScale), strict: strict)
                    candidates += stageCandidates(region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                        appZoom: appZoom, mode: mode, stageName: "noncontinuous_lane_final", previous: raw, current: shifted)
                    crossingCandidates += newCrossingCandidates(
                        region: input.region, lineId: part.lineId, partIndex: part.partIndex,
                        appZoom: appZoom, mode: mode, stageName: "noncontinuous_lane_new_self_intersection",
                        previous: raw, current: shifted)
                    plainLaneBuilds += 1
                }
            }
        }
        let result = AuditOutput(region: input.region, version: input.version,
            packageLineCount: input.packageLineCount,
            packageStationMembershipCount: input.packageStationMembershipCount,
            continuousPartCount: input.continuousPartCount, plainPartCount: input.plainPartCount,
            zooms: requestedZooms, continuousBuilds: continuousBuilds,
            plainSimplifierBuilds: plainSimplifierBuilds, plainLaneBuilds: plainLaneBuilds,
            candidates: candidates.sorted {
                ($0.region, $0.lineId, $0.partIndex, $0.appZoom, $0.fromMeasure) <
                ($1.region, $1.lineId, $1.partIndex, $1.appZoom, $1.fromMeasure)
            },
            crossingCandidates: crossingCandidates.sorted {
                ($0.region, $0.lineId, $0.partIndex, $0.appZoom, $0.firstMeasure) <
                ($1.region, $1.lineId, $1.partIndex, $1.appZoom, $1.firstMeasure)
            })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(result)); FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
