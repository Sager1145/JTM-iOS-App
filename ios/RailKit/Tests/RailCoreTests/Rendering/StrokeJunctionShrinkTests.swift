import Foundation
import Testing

@testable import RailCore

/// A much smaller line set must hand back the vertex storage the larger one grew.
struct StrokeJunctionShrinkTests {
    private typealias Line = StrokeJunctionIndex.Line

    private static func lines(count: Int) -> [Line] {
        (0..<count).map { n in
            Line(
                id: "jp|l\(n)#0", region: "jp", operatorName: nil,
                coordinates: (0..<8).map { k in
                    Coordinate(lon: 130 + Double(n) * 0.001, lat: 30 + Double(k) * 0.001)
                },
                continuous: true)
        }
    }

    @Test func shrinkingIsStructurallyEqualToAFreshIndexAndBoundsItsCapacity() {
        let large = Self.lines(count: 4_000)
        var index = StrokeJunctionIndex(large)
        #expect(index.vertexCapacity > 4 * 1024)
        let small = Array(large.prefix(10))
        _ = index.update(small)
        let fresh = StrokeJunctionIndex(small)
        #expect(index.isStructurallyEqual(to: fresh))
        #expect(index.vertexCapacity <= 4 * max(index.vertexKeyCount, 1024))
    }

    @Test func aSmallIndexIsLeftAlone() {
        var index = StrokeJunctionIndex(Self.lines(count: 50))
        let before = index.vertexCapacity
        _ = index.update(Self.lines(count: 49))
        #expect(index.vertexCapacity <= max(before, 4 * 1024))
        #expect(index.isStructurallyEqual(to: StrokeJunctionIndex(Self.lines(count: 49))))
    }
}
