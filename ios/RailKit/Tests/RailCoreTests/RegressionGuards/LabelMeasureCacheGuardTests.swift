import Foundation
import RailTestSupport
import Testing

/// The settle restyle re-measured every visible name (`sizeThatFits`) and
/// rewrote its font even when the point size had not changed. A name's size is
/// now cached per view, keyed on text, point size, content size category and
/// bound: measured once on an unchanged key, redone when any input changes.
/// The behavioural twin is `RegressionGuardLabelMeasureCacheBehaviourTests`
/// in `RailMapTests`.
@Suite("RegressionGuardLabelMeasureCache")
struct RegressionGuardLabelMeasureCache {
    @Test("cache reuses the size on an equal key and measures on a changed one")
    func cacheDecision() throws {
        let text = try SourceFiles.text("RailMap/Map/MapLabelStyle.swift")
        let start = try #require(text.range(of: "struct LabelMeasureCache"))
        let body = String(text[start.lowerBound...])
        for field in ["let text: String?", "let pointSize: CGFloat",
                      "let contentSizeCategory: String", "let bound: CGSize"] {
            #expect(body.contains(field), "key must include \(field)")
        }
        #expect(body.contains("if self.key == key { return size }"),
                "an unchanged key must return the cached size without measuring")
    }

    @Test("both label views measure through the cache and write the font only on a size change")
    func viewsUseCache() throws {
        for path in ["RailMap/Map/StationAnnotationViews.swift",
                     "RailMap/Map/JourneyLabelAnnotationViews.swift"] {
            let text = try SourceFiles.text(path)
            #expect(text.contains("measureCache.size(for:"), "\(path) must measure via the cache")
            #expect(text.contains("appliedFontSize != "), "\(path) must skip an unchanged font write")
            #expect(text.contains("preferredContentSizeCategory"), "\(path) key must carry the category")
        }
        let station = try SourceFiles.text("RailMap/Map/StationAnnotationViews.swift")
        #expect(!station.contains("= names\n                ? nameLabel.sizeThatFits"),
                "station names must not call sizeThatFits directly")
        let ride = try SourceFiles.text("RailMap/Map/JourneyLabelAnnotationViews.swift")
        #expect(!ride.contains("let size = text.sizeThatFits"),
                "ride labels must not call sizeThatFits directly")
    }
}
