import Foundation
import RailCore

/// A station code served by two scoped package lines whose own surveyed
/// tracks neither share a physical graph node (same identity, same 5-decimal
/// vertex) nor have a reviewed registry row. Proposes a zeroLength row when
/// the nearest vertices are identical, a shortLink row when they are distinct
/// and ≤ 30 m apart (the JunctionRowRules split), or reports "needs survey".
public enum MissingJunctionDetector {
    struct TrackEnd { var identity: RouteGraph.TrackIdentity; var vertices: [Coordinate] }

    public static func detect(_ context: DetectionContext) -> [Problem] {
        let data = context.data, scope = context.scope, t = context.thresholds
        // Station code → (line, anchor) for anchors inside the area.
        var linesByCode: [String: [(LineScope, CompactPackage.Station)]] = [:]
        for lineScope in scope.lines {
            guard let line = data.linesByID[lineScope.lineID] else { continue }
            for station in line.stations where scope.bbox.contains(station.coordinate) {
                linesByCode[station.id, default: []].append((lineScope, station))
            }
        }
        var problems: [Problem] = []
        for code in linesByCode.keys.sorted() {
            let entries = linesByCode[code]!.sorted { $0.0.lineID < $1.0.lineID }
            guard entries.count >= 2 else { continue }
            for i in 0..<entries.count {
                for j in (i + 1)..<entries.count {
                    let (a, stationA) = entries[i], (b, stationB) = entries[j]
                    guard let endsA = trackEnds(a, near: stationA.coordinate, context),
                          let endsB = trackEnds(b, near: stationB.coordinate, context) else { continue }
                    if sharesNode(endsA, endsB) { continue }
                    if hasRegistryRow(code: code, a: a.lineID, b: b.lineID, endsA: endsA, endsB: endsB,
                                      near: stationA.coordinate, context) { continue }
                    guard let nearest = nearestPair(endsA, endsB) else { continue }
                    let distance = nearest.metres
                    let evidence = [
                        "\(a.lineID) identities: \(endsA.map { describe($0.identity) }.joined(separator: ", "))",
                        "\(b.lineID) identities: \(endsB.map { describe($0.identity) }.joined(separator: ", "))",
                        "nearest surveyed vertices \(AreaProblems.format(distance)) apart: [\(nearest.a.lon), \(nearest.a.lat)] / [\(nearest.b.lon), \(nearest.b.lat)]",
                        "no shared physical node and no physical-rail-junctions.json row for \(code) with both line IDs",
                    ]
                    var proposal: PatchOp?
                    let message: String
                    if distance <= t.shortLinkMetres {
                        let row = proposedRow(code: code, station: stationA.name, a: a.lineID, b: b.lineID,
                                              from: (nearest.identityA, nearest.a), to: (nearest.identityB, nearest.b),
                                              metres: distance, zeroLength: nearest.a == nearest.b)
                        proposal = PatchOp(op: .junctionAdd, key: row["id"]!.stringValue!, before: nil, after: row)
                        message = "\(stationA.name) (\(code)): \(a.lineID) and \(b.lineID) are not physically joined; their tracks are \(AreaProblems.format(distance)) apart."
                    } else {
                        message = "\(stationA.name) (\(code)): \(a.lineID) and \(b.lineID) are not physically joined; nearest tracks are \(AreaProblems.format(distance)) apart, beyond a short link — needs survey."
                    }
                    problems.append(Problem(
                        id: "missingJunction/\(code)/\(a.lineID)/\(b.lineID)", kind: .missingJunction,
                        severity: distance <= t.shortLinkMetres ? .error : .info,
                        lineIDs: [a.lineID, b.lineID], stationCode: code, coordinate: AreaPoint(stationA.coordinate),
                        measure: distance, message: message, evidence: evidence, proposal: proposal))
                }
            }
        }
        return problems
    }

    /// The line's own solver tracks (same N02 name/operator) within the search radius of its anchor.
    static func trackEnds(_ line: LineScope, near anchor: Coordinate, _ context: DetectionContext) -> [TrackEnd]? {
        let data = context.data
        var byIdentity: [RouteGraph.TrackIdentity: [Coordinate]] = [:]
        var order: [RouteGraph.TrackIdentity] = []
        for index in data.featureIndices(lineName: line.name, operatorName: line.operatorName, in: context.scope.sectionFeatureIndices) {
            let feature = data.sections[index]
            let identity = feature.physicalTrackIdentity
            for vertex in feature.quantisedLines.flatMap({ $0 })
            where AreaGeometry.distance(anchor, vertex) <= context.thresholds.junctionSearchMetres {
                if byIdentity[identity] == nil { order.append(identity) }
                byIdentity[identity, default: []].append(vertex)
            }
        }
        let ends = order.map { TrackEnd(identity: $0, vertices: byIdentity[$0]!) }
        return ends.isEmpty ? nil : ends
    }

    static func sharesNode(_ a: [TrackEnd], _ b: [TrackEnd]) -> Bool {
        let keysA = Set(a.flatMap { end in end.vertices.map { RouteGraph.physicalNodeKey($0, identity: end.identity) } })
        return b.contains { end in end.vertices.contains { keysA.contains(RouteGraph.physicalNodeKey($0, identity: end.identity)) } }
    }

    static func sameTrack(_ x: RouteGraph.TrackIdentity, _ y: RouteGraph.TrackIdentity) -> Bool {
        x.operatorName == y.operatorName && x.lineName == y.lineName && x.railwayClassCode == y.railwayClassCode
    }

    static func hasRegistryRow(code: String, a: String, b: String, endsA: [TrackEnd], endsB: [TrackEnd],
                               near anchor: Coordinate, _ context: DetectionContext) -> Bool {
        let radius = context.thresholds.junctionSearchMetres
        return context.data.junctions.contains { row in
            let near = AreaGeometry.distance(anchor, row.from.coordinate) <= radius
                || AreaGeometry.distance(anchor, row.to.coordinate) <= radius
            if Set(row.lineIDs).isSuperset(of: [a, b]), row.stationCode == code || near { return true }
            guard near else { return false }
            func joins(_ p: [TrackEnd], _ q: [TrackEnd]) -> Bool {
                p.contains { sameTrack($0.identity, row.from.identity) } && q.contains { sameTrack($0.identity, row.to.identity) }
            }
            return joins(endsA, endsB) || joins(endsB, endsA)
        }
    }

    static func nearestPair(_ a: [TrackEnd], _ b: [TrackEnd])
        -> (a: Coordinate, b: Coordinate, identityA: RouteGraph.TrackIdentity, identityB: RouteGraph.TrackIdentity, metres: Double)? {
        var best: (Coordinate, Coordinate, RouteGraph.TrackIdentity, RouteGraph.TrackIdentity, Double)?
        for endA in a {
            for endB in b {
                for va in endA.vertices {
                    for vb in endB.vertices {
                        let d = AreaGeometry.distance(va, vb)
                        if best == nil || d < best!.4 { best = (va, vb, endA.identity, endB.identity, d) }
                    }
                }
            }
        }
        return best.map { (a: $0.0, b: $0.1, identityA: $0.2, identityB: $0.3, metres: $0.4) }
    }

    static func describe(_ identity: RouteGraph.TrackIdentity) -> String {
        "\(identity.operatorName)/\(identity.lineName)/\(identity.railwayClassCode)" + (identity.trackID.map { "#\($0)" } ?? "")
    }

    static func identityJSON(_ identity: RouteGraph.TrackIdentity) -> AreaJSON {
        var pairs: [(String, AreaJSON)] = [
            ("operatorName", .string(identity.operatorName)), ("lineName", .string(identity.lineName)),
            ("railwayClassCode", .string(identity.railwayClassCode)),
        ]
        if let level = identity.level { pairs.append(("level", .string(level))) }
        if let trackID = identity.trackID { pairs.append(("trackID", .string(trackID))) }
        return .object(pairs)
    }

    /// A draft registry row in the file's key order; evidence is left for the reviewer.
    static func proposedRow(code: String, station: String, a: String, b: String,
                            from: (RouteGraph.TrackIdentity, Coordinate), to: (RouteGraph.TrackIdentity, Coordinate),
                            metres: Double, zeroLength: Bool) -> AreaJSON {
        func endpoint(_ end: (RouteGraph.TrackIdentity, Coordinate)) -> AreaJSON {
            .object([("identity", identityJSON(end.0)),
                     ("coordinate", .array([.number(end.1.lon), .number(end.1.lat)]))])
        }
        var pairs: [(String, AreaJSON)] = [("id", .string("area-\(code)-\(stableHash(a + "|" + b))"))]
        if !zeroLength { pairs.append(("kind", .string("shortLink"))) }
        pairs += [
            ("region", .string("jp")), ("station", .string(station)), ("stationCode", .string(code)),
            ("lineIDs", .array([.string(a), .string(b)])),
            ("from", endpoint(from)), ("to", endpoint(to)),
            ("evidence", .array([])),
            ("geometryEvidence", .string(zeroLength
                ? "app/data/rail-sections.json: identical existing surveyed vertex on both named railway identities"
                : "app/data/rail-sections.json: existing surveyed vertices \(String(format: "%.1f", metres)) m apart on the two named railway identities")),
            ("reviewedAt", .string(AreaProblems.today())),
            ("validFrom", .null), ("validTo", .null),
            ("temporalEvidence", .string("")),
        ]
        return .object(pairs)
    }

    /// 32-bit FNV-1a in hex: stable across runs (never Swift's Hasher).
    static func stableHash(_ text: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return String(format: "%08x", hash)
    }
}
