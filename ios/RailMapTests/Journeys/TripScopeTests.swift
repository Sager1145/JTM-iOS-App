import Foundation
import RailCore
import Testing
@testable import RailMap

/// The map's 500-trip cap and the hide-by-region/year/month filter.
@MainActor
struct TripScopeTests {
    private func train(_ id: String, date: String?, country: String = "jp") -> Train {
        var train = StoreOperations.createBlankTrain(country: country)
        train.id = id
        train.date = date
        // A declared region is what the scope rule reads first; the blank
        // starter's own station codes do not name every region.
        train.region = country
        return train
    }

    private func loaded(_ trains: [Train]) -> ItineraryStore.Loaded {
        let byDate = Dictionary(grouping: trains) { $0.date ?? "" }
        let days = byDate.keys.sorted().map { ItineraryStore.Loaded.Day(date: $0, trains: byDate[$0]!) }
        return ItineraryStore.Loaded(regions: [], trains: trains, days: days, elapsed: .zero)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "trip-scope-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: cap

    @Test func capKeepsLimitSelectedFirstThenMostRecent() {
        let limit = MapTripCap.limit
        let ids = (0..<(limit + 100)).map { "t\($0)" }
        var dates: [String: String] = [:]
        for (index, id) in ids.enumerated() {
            dates[id] = String(format: "2025-%02d-%02d", index % 12 + 1, index % 28 + 1)
        }
        let selected = "t0"
        let capped = MapTripCap.capped(ids, id: { $0 }, selectedID: selected, dates: dates)
        #expect(limit == ResourceProfile.current.mapTripLimit)
        #expect(capped.count == limit)
        #expect(capped.contains(selected))
        // Every kept trip is at least as recent as every dropped one
        // (the selected trip aside).
        let dropped = Set(ids).subtracting(capped)
        let oldestKept = capped.filter { $0 != selected }.compactMap { dates[$0] }.min()!
        let newestDropped = dropped.compactMap { dates[$0] }.max()!
        #expect(oldestKept >= newestDropped)
        // Drawing order among survivors is preserved.
        #expect(capped == ids.filter { capped.contains($0) })
    }

    @Test func capLeavesSmallSetsUntouched() {
        let ids = (0..<MapTripCap.limit).map { "t\($0)" }
        #expect(MapTripCap.capped(ids, id: { $0 }, selectedID: nil, dates: [:]) == ids)
    }

    // MARK: hide filter

    @Test func hidingARegionYearOrMonthRemovesThoseTripsEverywhere() {
        let trains = [
            train("jp-2024", date: "2024-05-01"),
            train("jp-2025-03", date: "2025-03-10"),
            train("jp-2025-04", date: "2025-04-10"),
            train("tw-2025", date: "2025-03-11", country: "tw"),
            train("undated", date: nil),
        ]
        let store = loaded(trains)
        let filter = TripHideFilter(defaults: freshDefaults())
        #expect(filter.scoped(store).trains.count == 5)

        filter.setRegion(.tw, hidden: true)
        #expect(Set(filter.scoped(store).trains.map(\.id)) == ["jp-2024", "jp-2025-03", "jp-2025-04", "undated"])

        filter.setYear(2024, hidden: true)
        filter.setMonth("2025-03", hidden: true)
        let scoped = filter.scoped(store)
        #expect(Set(scoped.trains.map(\.id)) == ["jp-2025-04", "undated"])
        #expect(scoped.hiddenIDs == ["tw-2025", "jp-2024", "jp-2025-03"])
        // Days follow the trips, and empty days disappear.
        #expect(Set(scoped.days.flatMap(\.trains).map(\.id)) == Set(scoped.trains.map(\.id)))
        #expect(filter.activeCount == 3)

        filter.showAll()
        #expect(filter.scoped(store).trains.count == 5)
        #expect(!filter.isActive)
    }

    @Test func showingOneMonthOfAHiddenYearHidesTheOtherMonthsInstead() {
        let filter = TripHideFilter(defaults: freshDefaults())
        filter.setYear(2025, hidden: true)
        #expect(filter.isMonthHidden("2025-07"))
        filter.setMonth("2025-07", hidden: false)
        #expect(!filter.isYearHidden(2025))
        #expect(!filter.isMonthHidden("2025-07"))
        #expect(filter.isMonthHidden("2025-06"))
    }

    @Test func choicesPersistAcrossLaunches() {
        let defaults = freshDefaults()
        let first = TripHideFilter(defaults: defaults, storageID: "a")
        first.setRegion(.hk, hidden: true)
        first.setMonth("2024-12", hidden: true)
        let relaunched = TripHideFilter(defaults: defaults, storageID: "a")
        #expect(relaunched.isRegionHidden(.hk))
        #expect(relaunched.isMonthHidden("2024-12"))
        // A different storage id (another UI test) sees none of it.
        #expect(!TripHideFilter(defaults: defaults, storageID: "b").isActive)
    }

    @Test func scopedAnswerIsStableUntilSomethingChanges() {
        let store = loaded([train("a", date: "2025-01-01"), train("b", date: "2024-01-01")])
        let filter = TripHideFilter(defaults: freshDefaults())
        filter.setYear(2024, hidden: true)
        let first = filter.scoped(store)
        let second = filter.scoped(store)
        #expect(ArrayGeneration.same(first.trains, second.trains))
        filter.setYear(2024, hidden: false)
        #expect(filter.scoped(store).trains.count == 2)
    }
}

/// Region support lives in `RailCore.RegionConnectivity`; a disabled region
/// keeps its stored trips but offers no UI and draws nothing.
@MainActor
struct DisabledRegionScopeTests {
    @Test("mainland China is absent from the enabled regions and its trips are hidden from the scoped list")
    func chinaDisabled() {
        #expect(!Region.enabledOrdered.contains(.cn))
        #expect(Region.cn.isEnabled == false)
        #expect(Region.enabledOrdered.contains(.hk))

        var cn = StoreOperations.createBlankTrain(country: "cn")
        cn.id = "cn-1"; cn.region = "cn"; cn.date = "2026-07-01"
        var jp = StoreOperations.createBlankTrain(country: "jp")
        jp.id = "jp-1"; jp.region = "jp"; jp.date = "2026-07-01"
        let trains = [cn, jp]
        let days = [ItineraryStore.Loaded.Day(date: "2026-07-01", trains: trains)]
        let loaded = ItineraryStore.Loaded(regions: [], trains: trains, days: days, elapsed: .zero)
        let defaults = UserDefaults(suiteName: "disabled-region-\(UUID().uuidString)")!
        let filter = TripHideFilter(defaults: defaults, storageID: nil)
        #expect(filter.scoped(loaded).trains.map(\.id) == ["jp-1"])
        #expect(filter.scoped(loaded).hiddenIDs == ["cn-1"])
        #expect(StatisticsScope.everything.regions.contains(.cn) == false)
    }

    @Test("a Hong Kong trip naming a CN-OSM source code never gets a merged route scope")
    func unconnectedSourceCodesDoNotMerge() {
        var hk = StoreOperations.createBlankTrain(country: "hk")
        hk.region = "hk"
        hk.routeSections = [RouteSection(
            from: "A", to: "B", fromN02StationCode: "CN-OSM-N1", toN02StationCode: "CN-OSM-N2")]
        let scope = RouteScope(hk)
        #expect(!scope.crossesBorder)
        #expect(scope.graphRegions.count == 1)
        #expect(scope.home == .hk)
    }
}
