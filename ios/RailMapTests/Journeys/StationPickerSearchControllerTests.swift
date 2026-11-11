import Foundation
import RailCore
import Testing
@testable import RailMap

/// The picker's empty-box refresh when the map settles somewhere new.
@MainActor
struct StationPickerSearchControllerTests {
    /// A debounce that waits until opened, so a test decides when it elapses.
    private final class Hold: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        func open() { lock.withLock { isOpen = true } }
        func wait() async throws {
            while !lock.withLock({ isOpen }) {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    private static let boxAroundB = SearchMapRect(
        minLatitude: 35.4, maxLatitude: 35.6, minLongitude: 139.4, maxLongitude: 139.6)

    private func installed(_ hold: Hold) -> StationPickerSearchController {
        func station(_ code: String, _ name: String, lon: Double, lat: Double) -> EditorCatalogStationSource {
            EditorCatalogStationSource(sourceCode: code, name: name, nameRoma: nil, longitude: lon, latitude: lat)
        }
        let catalog = EditorCatalogBuilder.build([
            EditorCatalogLineSource(
                regionCode: "jp", lineID: "line-1", name: "本線", nameNorm: nil, nameRoma: nil,
                operatorName: "テスト鉄道", operatorShort: nil,
                stations: [station("A", "アルファ", lon: 135.0, lat: 35.0),
                           station("B", "ブラボー", lon: 139.5, lat: 35.5),
                           station("C", "チャーリー", lon: 130.0, lat: 34.0)]),
        ])
        let controller = StationPickerSearchController(debounce: { try await hold.wait() })
        let id = controller.beginLoad()
        controller.install(
            index: catalog.stationSearchIndex(regionCode: "jp", extraNames: [:]), retired: [],
            request: .init(regionCode: "jp", rideDate: nil, lineIDs: [], includesRetired: false),
            output: StationSearchResult(), loadID: id)
        return controller
    }

    private func codes(_ controller: StationPickerSearchController) -> [String] {
        controller.output.suggestions.compactMap {
            if case .current(let key, _) = $0.subject { return key.sourceCode }
            return nil
        }
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(250)) }

    @Test func aNewVisibleRegionReappliesWhileTheBoxIsEmpty() async {
        let hold = Hold(); hold.open()
        let controller = installed(hold)
        #expect(codes(controller).isEmpty)
        controller.setSignals(visibleRegion: Self.boxAroundB)
        await settle()
        #expect(codes(controller) == ["B"])
    }

    @Test func aTypedQueryIsNotReplacedByARegionChange() async {
        let hold = Hold(); hold.open()
        let controller = installed(hold)
        controller.apply(query: "アルファ")
        await settle()
        #expect(controller.output.response?.query == "アルファ")
        controller.setSignals(visibleRegion: Self.boxAroundB)
        await settle()
        #expect(controller.output.response?.query == "アルファ")
    }

    @Test func typingCancelsAPendingRefresh() async {
        let hold = Hold()
        let controller = installed(hold)
        controller.setSignals(visibleRegion: Self.boxAroundB) // waits on the debounce
        controller.apply(query: "ブラボー")
        hold.open()
        await settle()
        #expect(controller.output.response?.query == "ブラボー")
        #expect(controller.output.response != nil)
    }

    @Test func beginLoadDropsAPendingRefresh() async {
        let hold = Hold()
        let controller = installed(hold)
        controller.setSignals(visibleRegion: Self.boxAroundB)
        _ = controller.beginLoad()
        hold.open()
        await settle()
        #expect(codes(controller).isEmpty)
        #expect(controller.output.response == nil)
    }

    @Test func aStaleRefreshNeverOverwritesNewerOutput() async {
        let hold = Hold(); hold.open()
        let controller = installed(hold)
        controller.setSignals(visibleRegion: Self.boxAroundB)
        try? await Task.sleep(for: .milliseconds(30)) // the refresh search may be in flight
        controller.apply(query: "チャーリー")
        await settle()
        #expect(controller.output.response?.query == "チャーリー")
    }
}

@MainActor
struct StationPickerRecentsClearTests {
    private func defaults() -> UserDefaults {
        let name = "StationPickerRecentsClearTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func seed(_ d: UserDefaults, region: String) {
        RecentSearchStore.record("アルファ", box: .stationPicker, regionCode: region, defaults: d)
        StationPickerRecents.record(stationCode: "A", regionCode: region, defaults: d)
    }

    @Test func clearEmptiesBothStoresForThatRegionOnly() {
        let d = defaults()
        seed(d, region: "jp"); seed(d, region: "tw")
        StationPickerSearchController().clearRecents(regionCode: "jp", defaults: d)
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "jp", defaults: d).isEmpty)
        #expect(StationPickerRecents.load(regionCode: "jp", defaults: d).isEmpty)
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "tw", defaults: d) == ["アルファ"])
        #expect(StationPickerRecents.load(regionCode: "tw", defaults: d).count == 1)
    }

    @Test func removeDeletesOneQuery() {
        let d = defaults()
        RecentSearchStore.record("アルファ", box: .stationPicker, regionCode: "jp", defaults: d)
        RecentSearchStore.record("ブラボー", box: .stationPicker, regionCode: "jp", defaults: d)
        let rest = StationPickerSearchController().removeRecentQuery("アルファ", regionCode: "jp", defaults: d)
        #expect(rest == ["ブラボー"])
    }

    @Test func clearRefreshesTheEmptyBoxList() async {
        let d = defaults()
        seed(d, region: "jp")
        let catalog = EditorCatalogBuilder.build([
            EditorCatalogLineSource(
                regionCode: "jp", lineID: "line-1", name: "本線", nameNorm: nil, nameRoma: nil,
                operatorName: "テスト鉄道", operatorShort: nil,
                stations: [EditorCatalogStationSource(
                    sourceCode: "A", name: "アルファ", nameRoma: nil, longitude: 135.0, latitude: 35.0)]),
        ])
        let controller = StationPickerSearchController(debounce: {})
        let id = controller.beginLoad()
        controller.install(
            index: catalog.stationSearchIndex(regionCode: "jp", extraNames: [:]), retired: [],
            request: .init(regionCode: "jp", rideDate: nil, lineIDs: [], includesRetired: false),
            output: StationSearchResult(), loadID: id)
        func codes() -> [String] {
            controller.output.suggestions.compactMap {
                if case .current(let key, _) = $0.subject { return key.sourceCode }
                return nil
            }
        }
        controller.setSignals(recentPicks: StationPickerRecents.load(regionCode: "jp", defaults: d))
        func settle(until done: () -> Bool) async {
            for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(25)) }
        }
        controller.apply(query: "")
        await settle { codes() == ["A"] }
        #expect(codes() == ["A"])
        controller.clearRecents(regionCode: "jp", defaults: d)
        await settle { codes().isEmpty }
        #expect(codes().isEmpty)
    }

    @Test func resetToDefaultsLeavesSearchHistoryAlone() {
        let d = defaults()
        seed(d, region: "jp")
        RecentSearchStore.record("新宿", box: .journeys, regionCode: "jp", defaults: d)
        DisplaySettings(userDefaults: d).reset()
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "jp", defaults: d) == ["アルファ"])
        #expect(RecentSearchStore.load(.journeys, regionCode: "jp", defaults: d) == ["新宿"])
        #expect(StationPickerRecents.load(regionCode: "jp", defaults: d).count == 1)
    }
}
