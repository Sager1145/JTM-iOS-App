import Foundation
import Testing

@testable import RailCore

/// `StrokeJunctionIndex.update` must equal a full rebuild, and `affectedIDs`
/// must cover every id whose dependencies changed.
struct StrokeJunctionIncrementalTests {
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
        mutating func bool() -> Bool { next() & 1 == 0 }
    }

    private typealias Line = StrokeJunctionIndex.Line
    private static let ids = ["jp|a#0", "jp|a#1", "jp|a#2", "jp|a#3", "jp|b#0", "x", "jp|c#-1", "jp|d#z"]
    private static let phantomIDs = ["jp|a#4", "zz"]
    private static let regions = ["jp", "tw"]
    private static let operators: [String?] = [nil, "Test Rail", "Other Rail"]

    private static func point(_ x: Int, _ y: Int) -> Coordinate {
        .init(lon: 139 + Double(x) * 0.01, lat: 35 + Double(y) * 0.01)
    }

    private static func randomPoint(_ rng: inout SplitMix64) -> Coordinate {
        point(rng.int(5), rng.int(5))
    }

    private static func randomLine(_ id: String, _ rng: inout SplitMix64) -> Line {
        var points: [Coordinate]
        switch rng.int(8) {
        case 0: points = []
        case 1: points = [randomPoint(&rng)]
        case 2:
            let start = randomPoint(&rng)
            points = [start, randomPoint(&rng), randomPoint(&rng), start]
        default: points = (0..<(2 + rng.int(5))).map { _ in randomPoint(&rng) }
        }
        let follows = (0..<rng.int(3)).map { _ in (ids + phantomIDs)[rng.int(ids.count + phantomIDs.count)] }
        return Line(id: id, region: regions[rng.int(2)], operatorName: operators[rng.int(3)],
                    coordinates: points, continuous: rng.int(4) != 0, follows: Array(Set(follows)).sorted())
    }

    private static func mutate(_ lines: [Line], _ rng: inout SplitMix64) -> [Line] {
        var lines = lines
        switch rng.int(8) {
        case 0: lines.insert(randomLine(ids[rng.int(ids.count)], &rng), at: rng.int(lines.count + 1))
        case 1 where !lines.isEmpty: lines.remove(at: rng.int(lines.count))
        case 2 where !lines.isEmpty:
            let i = rng.int(lines.count)
            lines[i] = randomLine(lines[i].id, &rng)
        case 3: lines.shuffle(using: &rng)
        case 4 where !lines.isEmpty:
            let i = rng.int(lines.count)
            lines.insert(randomLine(lines[i].id, &rng), at: rng.int(lines.count + 1))
        case 5 where !lines.isEmpty:
            let victim = lines[rng.int(lines.count)].id
            lines.removeAll { $0.id == victim }
        case 6:
            lines = lines.map { Line(id: $0.id, region: $0.region, operatorName: $0.operatorName,
                                     coordinates: Array($0.coordinates.map { Coordinate(lon: $0.lon, lat: $0.lat) }),
                                     continuous: $0.continuous, follows: Array($0.follows)) }
        case 7 where !lines.isEmpty:
            let i = rng.int(lines.count)
            var coordinates = lines[i].coordinates
            coordinates.append(Coordinate(lon: -0.0, lat: 35))
            lines[i] = Line(id: lines[i].id, region: lines[i].region, operatorName: lines[i].operatorName,
                            coordinates: coordinates, continuous: lines[i].continuous, follows: lines[i].follows)
        default: break
        }
        return lines
    }

    private static func winners(_ lines: [Line]) -> [String: Line] {
        var result: [String: Line] = [:]
        for line in lines where result[line.id] == nil { result[line.id] = line }
        return result
    }

    private static func bruteChanged(_ old: [Line], _ new: [Line]) -> Set<String> {
        let a = winners(old), b = winners(new)
        return Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }
    }

    private static func expectEquivalent(
        old: StrokeJunctionIndex, next: StrokeJunctionIndex, full: StrokeJunctionIndex,
        change: StrokeJunctionIndex.Change, oldLines: [Line], lines: [Line]
    ) {
        #expect(next.isStructurallyEqual(to: full))
        for region in regions {
            for op in operators {
                for x in 0..<5 {
                    for y in 0..<5 {
                        let c = point(x, y)
                        #expect(next.candidateIDs(sharing: c, region: region, operatorName: op)
                            == full.candidateIDs(sharing: c, region: region, operatorName: op))
                    }
                }
            }
        }
        let allIDs = Set(oldLines.map(\.id)).union(lines.map(\.id)).union(phantomIDs)
        for id in allIDs {
            #expect(next.dependencyIDs(of: id) == full.dependencyIDs(of: id))
            if !change.affectedIDs.contains(id) {
                #expect(old.dependencyIDs(of: id) == next.dependencyIDs(of: id))
            }
        }
        #expect(change.changedIDs == bruteChanged(oldLines, lines))
        #expect(change.changedIDs.isSubset(of: change.affectedIDs))
    }

    @Test("random edits update exactly like a full rebuild and affectedIDs covers every dependency change")
    func randomizedMatchesFullRebuild() {
        for seed in 1...5 {
            var rng = SplitMix64(state: UInt64(seed) &* 0x1234_5678_9ABC)
            var lines: [Line] = []
            var index = StrokeJunctionIndex([])
            for _ in 0..<200 {
                let oldLines = lines
                lines = Self.mutate(lines, &rng)
                let (next, change) = index.updated(lines)
                Self.expectEquivalent(old: index, next: next, full: StrokeJunctionIndex(lines),
                                      change: change, oldLines: oldLines, lines: lines)
                var inPlace = index
                let inPlaceChange = inPlace.update(lines)
                #expect(inPlaceChange == change)
                #expect(inPlace.isStructurallyEqual(to: next))
                index = next
            }
        }
    }

    private let junction = Coordinate(lon: 139, lat: 35)

    private func line(
        _ id: String, _ coordinates: [Coordinate], continuous: Bool = true
    ) -> Line {
        .init(id: id, region: "jp", operatorName: "Test Rail", coordinates: coordinates, continuous: continuous)
    }

    @Test("identical input yields an empty change")
    func identicalInputIsEmpty() {
        let a = line("jp|a#0", [junction, .init(lon: 139.01, lat: 35)])
        var index = StrokeJunctionIndex([a])
        let change = index.update([a])
        #expect(change.isEmpty)
        #expect(change.affectedIDs.isEmpty)
    }

    @Test("an earlier duplicate disappearing swaps the winner")
    func duplicateWinnerSwap() {
        let first = line("jp|a#0", [junction, .init(lon: 139.01, lat: 35)])
        let second = line("jp|a#0", [junction, .init(lon: 139.02, lat: 35)])
        let (index, change) = StrokeJunctionIndex([first, second]).updated([second])
        #expect(change.changedIDs == ["jp|a#0"])
        #expect(index.isStructurallyEqual(to: StrokeJunctionIndex([second])))
    }

    @Test("a candidate's continuous flip reaches the branch through its neighbours")
    func continuousFlip() {
        let branch = line("jp|branch#0", [junction, .init(lon: 139.01, lat: 35.001)])
        let hostOn = line("jp|main#4", [.init(lon: 138.99, lat: 35), junction], continuous: true)
        let hostOff = line("jp|main#4", hostOn.coordinates, continuous: false)
        let before = StrokeJunctionIndex([branch, hostOn])
        let (after, change) = before.updated([branch, hostOff])
        #expect(before.dependencyIDs(of: branch.id).contains("jp|main#5"))
        #expect(!after.dependencyIDs(of: branch.id).contains("jp|main#5"))
        #expect(change.changedIDs == ["jp|main#4"])
        #expect(change.affectedIDs.contains(branch.id))
    }

    @Test("a through host arriving affects its branch only")
    func hostArrival() {
        let branch = line("jp|branch#0", [junction, .init(lon: 139.01, lat: 35.001)])
        let host = line("jp|main#4", [.init(lon: 138.99, lat: 35), junction, .init(lon: 139.02, lat: 35)])
        let unrelated = line("jp|other#0", [.init(lon: 140, lat: 35), .init(lon: 140.01, lat: 35)])
        let before = StrokeJunctionIndex([branch, unrelated])
        let (after, change) = before.updated([branch, host, unrelated])
        #expect(change.changedIDs == [host.id])
        #expect(change.affectedIDs.contains(branch.id))
        #expect(!change.affectedIDs.contains(unrelated.id))
        #expect(after.isStructurallyEqual(to: StrokeJunctionIndex([branch, host, unrelated])))
        #expect(after.dependencyIDs(of: branch.id).contains(host.id))
    }

    @Test("updating to no lines empties the index")
    func updateToEmpty() {
        let a = line("jp|a#0", [junction, .init(lon: 139.01, lat: 35)])
        let b = line("jp|a#1", [junction])
        let (index, change) = StrokeJunctionIndex([a, b]).updated([])
        #expect(change.changedIDs == [a.id, b.id])
        #expect(index.isStructurallyEqual(to: StrokeJunctionIndex([])))
    }

    @Test("a NaN vertex is never indexed, so repeated updates do not grow the index")
    func nanVertexDoesNotLeak() {
        let nan = Coordinate(lon: .nan, lat: 35)
        let a = line("jp|a#0", [junction, nan, .init(lon: 139.01, lat: 35)])
        let b = line("jp|b#0", [.init(lon: 138.99, lat: 35), junction])
        var index = StrokeJunctionIndex([a, b])
        let full = StrokeJunctionIndex([a, b])
        for _ in 0..<3 { _ = index.update([a, b]) }
        #expect(index.vertexKeyCount == full.vertexKeyCount)
        #expect(full.vertexKeyCount == 3)
        #expect(index.candidateIDs(sharing: junction, region: "jp", operatorName: a.operatorName) == [a.id, b.id])
        #expect(index.dependencyIDs(of: b.id) == full.dependencyIDs(of: b.id))
    }
}
