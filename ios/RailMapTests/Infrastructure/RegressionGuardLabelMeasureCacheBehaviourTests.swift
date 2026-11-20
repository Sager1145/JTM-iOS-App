import CoreGraphics
import Testing
@testable import RailMap

@Suite("RegressionGuardLabelMeasureCacheBehaviour")
struct RegressionGuardLabelMeasureCacheBehaviourTests {
    private func key(text: String? = "Tokyo", size: CGFloat = 11,
                     category: String = "large") -> LabelMeasureCache.Key {
        .init(text: text, pointSize: size, contentSizeCategory: category,
              bound: CGSize(width: 180, height: 24))
    }

    @Test func unchangedKeySkipsMeasure() {
        var cache = LabelMeasureCache()
        var calls = 0
        let first = cache.size(for: key()) { calls += 1; return CGSize(width: 40, height: 14) }
        let second = cache.size(for: key()) { calls += 1; return CGSize(width: 99, height: 99) }
        #expect(calls == 1)
        #expect(first == second)
        #expect(cache.measureCount == 1)
    }

    @Test func anyChangedInputRemeasures() {
        var cache = LabelMeasureCache()
        var calls = 0
        let measure: () -> CGSize = { calls += 1; return CGSize(width: CGFloat(calls), height: 14) }
        _ = cache.size(for: key(), measure: measure)
        _ = cache.size(for: key(size: 12), measure: measure)
        _ = cache.size(for: key(text: "Osaka", size: 12), measure: measure)
        _ = cache.size(for: key(text: "Osaka", size: 12, category: "extraLarge"), measure: measure)
        #expect(calls == 4)
    }
}
