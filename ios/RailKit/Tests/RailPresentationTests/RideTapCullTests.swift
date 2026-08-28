import Foundation
import Testing

@testable import RailPresentation

/// The tap cull, checked against the thing it is allowed to be: faster, and
/// otherwise indistinguishable.
///
/// `RideTapIndex` in the app is what projects and culls, but the two decisions
/// it rests on are here — how a stroke is cut into chunks, and whether a box
/// can hold a hit — and they are the two that can be wrong silently. A cull
/// that drops one chunk too many is a line the reader can see under their
/// finger that does not answer, which no screenshot and no build failure
/// reports.
@Suite("RideTapResolver culling")
struct RideTapCullTests {

    // MARK: - chunkRanges

    @Test("every segment of a stroke belongs to exactly one chunk")
    func chunksCoverEverySegment() {
        for count in 0...300 {
            for size in [1, 2, 7, 64] {
                let ranges = RideTapResolver.chunkRanges(
                    count: count, segmentsPerChunk: size)
                guard count >= 2 else {
                    #expect(ranges.isEmpty, "\(count) points cannot draw a segment")
                    continue
                }
                // A range `a..<b` covers segments a … b-2.
                var covered: [Int] = []
                for range in ranges {
                    #expect(range.count >= 2, "a chunk of one vertex draws nothing")
                    covered.append(contentsOf: range.lowerBound..<(range.upperBound - 1))
                }
                #expect(
                    covered == Array(0..<(count - 1)),
                    "count \(count) size \(size): covered \(covered) not 0..<\(count - 1)")
            }
        }
    }

    @Test("a short stroke is one chunk")
    func shortStrokeIsOneChunk() {
        #expect(RideTapResolver.chunkRanges(count: 2) == [0..<2])
        #expect(RideTapResolver.chunkRanges(count: 65) == [0..<65])
        #expect(RideTapResolver.chunkRanges(count: 1).isEmpty)
        #expect(RideTapResolver.chunkRanges(count: 0).isEmpty)
    }

    @Test("consecutive chunks share the vertex between them")
    func chunksOverlapByOne() {
        let ranges = RideTapResolver.chunkRanges(count: 200, segmentsPerChunk: 64)
        #expect(ranges == [0..<65, 64..<129, 128..<193, 192..<200])
    }

    // MARK: - Bounds

    @Test("a box's distance is zero inside and the gap outside")
    func boundsDistance() {
        let box = RideTapResolver.Bounds(minX: 0, minY: 0, maxX: 10, maxY: 10)
        #expect(box.distance(to: .init(x: 5, y: 5)) == 0)
        #expect(box.distance(to: .init(x: 0, y: 0)) == 0)
        #expect(box.distance(to: .init(x: 13, y: 5)) == 3)
        #expect(box.distance(to: .init(x: 5, y: -4)) == 4)
        // A corner is the hypotenuse, not the larger of the two gaps — the
        // 3/4/5 here is what a `max(dx, dy)` version would answer 4 to, and a
        // tolerance between 4 and 5 is where that version culls a real hit.
        #expect(box.distance(to: .init(x: 13, y: 14)) == 5)
    }

    @Test("a box built from points contains them all")
    func boundsFromPoints() {
        let points = [
            RideTapResolver.Point(x: -3, y: 7),
            RideTapResolver.Point(x: 11, y: -2),
            RideTapResolver.Point(x: 4, y: 4),
        ]
        let box = RideTapResolver.Bounds(points)
        #expect(box == RideTapResolver.Bounds(minX: -3, minY: -2, maxX: 11, maxY: 7))
        for point in points { #expect(box?.distance(to: point) == 0) }
        #expect(RideTapResolver.Bounds([]) == nil)
    }

    // MARK: - the property the app relies on

    /// The cull may not change one answer, over geometry with the shape the
    /// real thing has: many short strokes, a few very long ones, and taps that
    /// mostly land on nothing.
    ///
    /// A deterministic generator rather than `random()`: a property test that
    /// fails once and then passes is a property test that has told you nothing.
    @Test("culling by chunk never changes what a tap answers")
    func cullMatchesFullScan() {
        var random = Deterministic(seed: 0x5EED)
        for trial in 0..<40 {
            let rides = (0..<12).map { rideIndex in
                RideTapResolver.Candidate(
                    id: "train-\(rideIndex)",
                    strokes: (0..<random.int(1...5)).map { _ in
                        // One stroke in five is long enough to be cut up.
                        let count = random.int(0...9) == 0
                            ? random.int(200...900) : random.int(0...40)
                        var points: [RideTapResolver.Point] = []
                        var x = random.double(-50...450)
                        var y = random.double(-50...900)
                        for _ in 0..<count {
                            x += random.double(-8...8)
                            y += random.double(-8...8)
                            points.append(.init(x: x, y: y))
                        }
                        return points
                    })
            }
            let tolerance = RideTapResolver.defaultTolerance
            for _ in 0..<25 {
                let tap = RideTapResolver.Point(
                    x: random.double(0...393), y: random.double(0...852))
                let full = RideTapResolver.hits(
                    at: tap, among: rides, tolerance: tolerance)
                let culled = RideTapResolver.hits(
                    at: tap, among: cull(rides, at: tap, tolerance: tolerance),
                    tolerance: tolerance)
                #expect(
                    full == culled,
                    "trial \(trial): the cull changed a tap at \(tap): \(full) vs \(culled)")
            }
        }
    }

    /// What `RideTapIndex` does, spelled in one place a test can run.
    ///
    /// The app builds the boxes in `MKMapPoint` space and the tap in the same
    /// space; here both are already the screen's, which is the same argument
    /// with the similarity transform set to the identity.
    private func cull(
        _ candidates: [RideTapResolver.Candidate],
        at tap: RideTapResolver.Point, tolerance: Double
    ) -> [RideTapResolver.Candidate] {
        candidates.compactMap { candidate in
            var kept: [[RideTapResolver.Point]] = []
            for stroke in candidate.strokes {
                for range in RideTapResolver.chunkRanges(count: stroke.count) {
                    guard let box = RideTapResolver.Bounds(stroke[range]),
                          box.mayContain(tap, within: tolerance)
                    else { continue }
                    kept.append(Array(stroke[range]))
                }
            }
            guard !kept.isEmpty else { return nil }
            return RideTapResolver.Candidate(id: candidate.id, strokes: kept)
        }
    }
}

/// A tiny reproducible generator. `SystemRandomNumberGenerator` would make the
/// property above pass or fail differently on every run, which is the one
/// thing a regression test may not do.
private struct Deterministic {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 2_862_933_555_777_941_757 &+ 1 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }
}
