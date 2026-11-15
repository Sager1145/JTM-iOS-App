import Foundation
import Testing

@testable import RailCore

/// `StrokeJunctionState.advanced` must equal a fresh build plus
/// `dependencyIDs(of:)`, and must never change the value it advances from.
struct StrokeJunctionStateTests {
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
    }

    private typealias Line = StrokeJunctionIndex.Line
    private static let ids = ["jp|a#0", "jp|a#1", "jp|a#2", "jp|b#0", "jp|b#1", "x"]

    private static func point(_ x: Int, _ y: Int) -> Coordinate {
        .init(lon: 139 + Double(x) * 0.01, lat: 35 + Double(y) * 0.01)
    }

    private static func randomLine(_ id: String, _ rng: inout SplitMix64) -> Line {
        let points = (0..<(2 + rng.int(4))).map { _ in point(rng.int(4), rng.int(4)) }
        let follows = rng.int(3) == 0 ? [ids[rng.int(ids.count)]] : []
        return Line(id: id, region: "jp", operatorName: rng.int(2) == 0 ? nil : "Rail",
                    coordinates: points, continuous: rng.int(4) != 0, follows: follows)
    }

    private static func randomSet(_ rng: inout SplitMix64) -> [Line] {
        ids.filter { _ in rng.int(3) != 0 }.map { randomLine($0, &rng) }
    }

    private static func mutate(_ lines: [Line], _ rng: inout SplitMix64) -> [Line] {
        var lines = lines
        switch rng.int(3) {
        case 0 where !lines.isEmpty: lines.remove(at: rng.int(lines.count))
        case 1 where !lines.isEmpty:
            let i = rng.int(lines.count)
            lines[i] = randomLine(lines[i].id, &rng)
        default:
            let id = ids[rng.int(ids.count)]
            if !lines.contains(where: { $0.id == id }) { lines.append(randomLine(id, &rng)) }
        }
        return lines
    }

    private static func expectedDependencies(_ lines: [Line]) -> [String: Set<String>] {
        let fresh = StrokeJunctionIndex(lines)
        return Dictionary(lines.map { ($0.id, fresh.dependencyIDs(of: $0.id)) },
                          uniquingKeysWith: { first, _ in first })
    }

    @Test func advancingEqualsAFreshBuildAndDependencyIDs() {
        var rng = SplitMix64(state: 7)
        for _ in 0..<60 {
            var lines = Self.randomSet(&rng)
            var state = StrokeJunctionState().advanced(to: lines).state
            for _ in 0..<8 {
                lines = Self.mutate(lines, &rng)
                state = state.advanced(to: lines).state
                #expect(state.index.isStructurallyEqual(to: StrokeJunctionIndex(lines)))
                #expect(state.dependencyIDs == Self.expectedDependencies(lines))
            }
        }
    }

    @Test func advancingNeverChangesTheBaseValue() {
        var rng = SplitMix64(state: 11)
        for _ in 0..<40 {
            let first = Self.randomSet(&rng)
            let base = StrokeJunctionState().advanced(to: first).state
            let baseDependencies = base.dependencyIDs
            _ = base.advanced(to: Self.mutate(first, &rng))
            _ = base.advanced(to: Self.randomSet(&rng))
            #expect(base.index.isStructurallyEqual(to: StrokeJunctionIndex(first)))
            #expect(base.dependencyIDs == baseDependencies)
        }
    }

    @Test func twoChainedAdvancesEqualOne() {
        var rng = SplitMix64(state: 23)
        for _ in 0..<40 {
            let a = Self.randomSet(&rng)
            let b = Self.mutate(a, &rng)
            let c = Self.mutate(b, &rng)
            let chained = StrokeJunctionState().advanced(to: a).state.advanced(to: b).state.advanced(to: c).state
            let direct = StrokeJunctionState().advanced(to: c).state
            #expect(chained.index.isStructurallyEqual(to: direct.index))
            #expect(chained.dependencyIDs == direct.dependencyIDs)
        }
    }
}
