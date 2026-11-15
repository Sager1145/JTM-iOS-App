import Testing
@testable import RailPresentation

@Suite("AnnotationDiff")
struct AnnotationDiffTests {
    typealias Item = AnnotationDiff.Item<String>
    func station(_ key: String, _ lat: Double, _ lon: Double, style: String = "a") -> Item {
        Item(key: key, latitude: lat, longitude: lon, canMove: true, canRestyle: true, style: style)
    }

    @Test func aMovedStationIsKeptNotReAdded() {
        let diff = AnnotationDiff.make(old: [station("s1", 35, 139)], new: [station("s1", 35.001, 139.002)])
        #expect(diff.added.isEmpty && diff.removed.isEmpty)
        #expect(diff.kept == [.init(oldIndex: 0, newIndex: 0, moved: true, restyled: false)])
    }

    @Test func aNewStationIsAddedAndAVanishedOneRemoved() {
        let diff = AnnotationDiff.make(old: [station("s1", 35, 139), station("gone", 36, 140)],
                                       new: [station("s1", 35, 139), station("new", 37, 141)])
        #expect(diff.added == [1])
        #expect(diff.removed == [1])
        #expect(diff.kept == [.init(oldIndex: 0, newIndex: 0, moved: false, restyled: false)])
    }

    @Test func aStyleOnlyChangeUpdatesInPlace() {
        let diff = AnnotationDiff.make(old: [station("s1", 35, 139, style: "a")],
                                       new: [station("s1", 35, 139, style: "b")])
        #expect(diff.added.isEmpty && diff.removed.isEmpty)
        #expect(diff.kept == [.init(oldIndex: 0, newIndex: 0, moved: false, restyled: true)])
    }

    @Test func aKindThatCannotMoveOrRestyleIsReplacedInstead() {
        func frozen(_ lat: Double, style: String = "a") -> Item {
            Item(key: "n", latitude: lat, longitude: 0, canMove: false, canRestyle: false, style: style)
        }
        let moved = AnnotationDiff.make(old: [frozen(1)], new: [frozen(2)])
        #expect(moved.added == [0] && moved.removed == [0] && moved.kept.isEmpty)
        let restyled = AnnotationDiff.make(old: [frozen(1)], new: [frozen(1, style: "b")])
        #expect(restyled.added == [0] && restyled.removed == [0])
        let same = AnnotationDiff.make(old: [frozen(1)], new: [frozen(1)])
        #expect(same.kept.count == 1 && same.added.isEmpty && same.removed.isEmpty)
    }

    @Test func coincidentKeysPairExactFirstThenNearest() {
        let old = [station("k", 10, 10), station("k", 20, 20)]
        let new = [station("k", 20, 20), station("k", 11, 10)]
        let diff = AnnotationDiff.make(old: old, new: new)
        #expect(diff.added.isEmpty && diff.removed.isEmpty)
        #expect(diff.kept.map(\.oldIndex) == [1, 0])
        #expect(diff.kept.map(\.moved) == [false, true])
    }

    @Test func duplicatesBeyondTheOldCountAreAdded() {
        let diff = AnnotationDiff.make(old: [station("k", 1, 1)], new: [station("k", 1, 1), station("k", 1, 1)])
        #expect(diff.kept.count == 1 && diff.added == [1] && diff.removed.isEmpty)
    }

    @Test func dotHitPicksTheNearestReachingTarget() {
        let dots = [DotHitTest.Dot(x: 0, y: 0, reach: 22), .init(x: 30, y: 0, reach: 22)]
        #expect(DotHitTest.hit(x: 20, y: 0, among: dots) == 1)
        #expect(DotHitTest.hit(x: 10, y: 0, among: dots) == 0)
        #expect(DotHitTest.hit(x: 100, y: 100, among: dots) == nil)
    }
}
