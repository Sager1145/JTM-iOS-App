import Foundation
import Testing
@testable import RailCore

struct RecentSearchStoreTests {
    private func defaults() -> UserDefaults {
        let name = "RecentSearchStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func clearEmptiesOneRegionAndBoxOnly() {
        let d = defaults()
        RecentSearchStore.record("新宿", box: .stationPicker, regionCode: "jp", defaults: d)
        RecentSearchStore.record("台北", box: .stationPicker, regionCode: "tw", defaults: d)
        RecentSearchStore.record("新宿", box: .journeys, regionCode: "jp", defaults: d)
        RecentSearchStore.clear(.stationPicker, regionCode: "jp", defaults: d)
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "jp", defaults: d).isEmpty)
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "tw", defaults: d) == ["台北"])
        #expect(RecentSearchStore.load(.journeys, regionCode: "jp", defaults: d) == ["新宿"])
    }

    @Test func removeDeletesOnlyThatQuery() {
        let d = defaults()
        RecentSearchStore.record("新宿", box: .stationPicker, regionCode: "jp", defaults: d)
        RecentSearchStore.record("渋谷", box: .stationPicker, regionCode: "jp", defaults: d)
        RecentSearchStore.record("渋谷", box: .stationPicker, regionCode: "tw", defaults: d)
        let rest = RecentSearchStore.remove("新宿", box: .stationPicker, regionCode: "jp", defaults: d)
        #expect(rest == ["渋谷"])
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "jp", defaults: d) == ["渋谷"])
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "tw", defaults: d) == ["渋谷"])
    }
}
