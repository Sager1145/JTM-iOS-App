import Foundation
import Testing
@testable import RailCore

/// Permanent guard: `surveyedCornerIndices` precomputes turns and edge
/// lengths once per pass (it used to recompute `atan2`/`hypot` inside every
/// 3 px window walk, the warm-launch and zoom-prepare hot spot). Output must
/// stay identical to the old per-window implementation kept below.
struct SurveyedCornerParityTests {
    typealias Point = ContinuousStroke.Point

    /// The pre-optimisation implementation, verbatim.
    private static func referenceWindowedTurn(_ p: [Point], _ i: Int) -> Double {
        var sum = ContinuousStroke.turnAt(p, i)
        var lo = i - 1, used = hypot(p[i].x - p[i - 1].x, p[i].y - p[i - 1].y)
        while lo >= 1 && used < ContinuousStroke.curveHardWindowPx {
            sum += ContinuousStroke.turnAt(p, lo)
            used += hypot(p[lo].x - p[lo - 1].x, p[lo].y - p[lo - 1].y); lo -= 1
        }
        var hi = i + 1; used = hypot(p[i + 1].x - p[i].x, p[i + 1].y - p[i].y)
        while hi + 1 < p.count && used < ContinuousStroke.curveHardWindowPx {
            sum += ContinuousStroke.turnAt(p, hi)
            used += hypot(p[hi + 1].x - p[hi].x, p[hi + 1].y - p[hi].y); hi += 1
        }
        return sum
    }

    private static func reference(_ points: [Point]) -> Set<Int> {
        guard points.count >= 3 else { return [] }
        var result = Set<Int>()
        for i in 1..<(points.count - 1) {
            let turn = ContinuousStroke.turnAt(points, i)
            if max(abs(turn), abs(referenceWindowedTurn(points, i))) > ContinuousStroke.curveHardTurnDegrees * .pi / 180 {
                result.insert(i)
            }
            let previousTurn = i > 1 ? abs(ContinuousStroke.turnAt(points, i - 1)) : 0
            let nextTurn = i + 2 < points.count ? abs(ContinuousStroke.turnAt(points, i + 1)) : 0
            if abs(turn) >= .pi / 6, max(previousTurn, nextTurn) < 0.75 * abs(turn) {
                result.insert(i)
            }
            guard i + 2 < points.count else { continue }
            let next = ContinuousStroke.turnAt(points, i + 1)
            let short = hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
            let before = hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
            let after = hypot(points[i + 2].x - points[i + 1].x, points[i + 2].y - points[i + 1].y)
            if turn * next < 0, min(abs(turn), abs(next)) >= .pi / 6,
               short < 0.5 * min(before, after) {
                result.insert(i); result.insert(i + 1)
            }
        }
        return result
    }

    private struct SeededRandom {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    private static func walk(seed: UInt64, count: Int, step: Double) -> [Point] {
        var rng = SeededRandom(state: seed)
        var x = 0.0, y = 0.0, heading = 0.0
        var out = [Point(x: 0, y: 0)]
        for _ in 1..<count {
            heading += (rng.next() - 0.5) * 2.2
            let length = step * (0.2 + rng.next() * 1.8)
            x += cos(heading) * length
            y += sin(heading) * length
            out.append(Point(x: x, y: y))
        }
        return out
    }

    @Test func denseSubPixelPolylinesMatchTheReference() {
        for seed in 1...40 as ClosedRange<UInt64> {
            for step in [0.15, 0.6, 1.5, 6, 40] {
                let points = Self.walk(seed: seed, count: 5 + Int(seed) * 7, step: step)
                #expect(ContinuousStroke.surveyedCornerIndices(points) == Self.reference(points),
                        "seed \(seed) step \(step)")
            }
        }
    }

    @Test func tinyPolylinesMatchTheReference() {
        let three = [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)]
        let four = [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 12, y: 8), Point(x: 30, y: 9)]
        for points in [Array(three.prefix(2)), three, four] {
            #expect(ContinuousStroke.surveyedCornerIndices(points) == Self.reference(points))
        }
        #expect(!ContinuousStroke.surveyedCornerIndices(three).isEmpty)
    }

    @Test func oneAtan2PerInteriorVertexPerPass() {
        for count in [3, 4, 50, 400] {
            let points = Self.walk(seed: 7, count: count, step: 0.3)
            var evaluations = 0
            _ = ContinuousStroke.surveyedCornerIndices(points, turnEvaluations: &evaluations)
            #expect(evaluations <= count - 2, "n=\(count) used \(evaluations)")
        }
    }
}
