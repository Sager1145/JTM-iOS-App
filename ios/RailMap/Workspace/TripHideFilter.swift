import Foundation
import Observation
import RailCore
import RailPresentation

/// The most trips the map draws at once.
///
/// The one hard-coded cap, applied where the scoped trips feed the map
/// (`RailWorkspaceView.mapRides`), and reused by the two other places that
/// can draw many routes: playback's queue and the share card's map. Lists
/// still scroll through every trip; only drawing is capped.
enum MapTripCap {
    static let limit = 500

    /// Trip id → normalised `YYYY-MM-DD` ("" when undated), the sort key.
    static func dates(_ trains: [Train]) -> [String: String] {
        var dates: [String: String] = [:]
        dates.reserveCapacity(trains.count)
        for train in trains where dates[train.id] == nil {
            dates[train.id] = Dates.normalizeDateString(train.date) ?? ""
        }
        return dates
    }

    /// The `limit` most relevant trips: the selected one first, then the most
    /// recent. `dates` is trip id → `YYYY-MM-DD`; undated trips sort last.
    static func capped<Item>(
        _ items: [Item], id: (Item) -> String, selectedID: String?, dates: [String: String]
    ) -> [Item] {
        guard items.count > limit else { return items }
        let ranked = items.enumerated().sorted { a, b in
            let aSelected = id(a.element) == selectedID, bSelected = id(b.element) == selectedID
            if aSelected != bSelected { return aSelected }
            let aDate = dates[id(a.element)] ?? "", bDate = dates[id(b.element)] ?? ""
            if aDate != bDate { return aDate > bDate }
            return a.offset < b.offset
        }
        // Keep the original drawing order among the survivors.
        return ranked.prefix(limit).sorted { $0.offset < $1.offset }.map(\.element)
    }
}

/// Hide whole countries/regions, years or single months from the map, the
/// lists and Stats — the second half of the shared scope filter.
///
/// Not the per-trip "hide" (`Train.visible`): that takes one trip off the
/// map and keeps it in every list. This takes trips out of the scope
/// everywhere. The two compose: a trip shows on the map only when it is
/// neither switched off itself nor in a hidden region or month.
///
/// Phone budget: a trip → (region, year-month) index is built once per store
/// generation, and the hidden set and the filtered trips/days once per index
/// or choice change. Every screen reads the same memoised answer.
@MainActor
@Observable
final class TripHideFilter {
    private(set) var hiddenRegions: Set<String> = []
    private(set) var hiddenYears: Set<Int> = []
    /// `YYYY-MM`.
    private(set) var hiddenMonths: Set<String> = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults = .standard, storageID: String? = nil) {
        self.defaults = defaults
        // Scoped by the UI-test storage id, so one test's choice cannot hide
        // another test's trips.
        key = "trip-hide-filter-v1" + (storageID.map { "-" + $0 } ?? "")
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            hiddenRegions = Set(saved.regions)
            hiddenYears = Set(saved.years)
            hiddenMonths = Set(saved.months)
        }
    }

    private struct Saved: Codable {
        var regions: [String]
        var years: [Int]
        var months: [String]
    }

    /// How many choices are hidden — the filter button's badge.
    var activeCount: Int { hiddenRegions.count + hiddenYears.count + hiddenMonths.count }
    var isActive: Bool { activeCount > 0 }

    func isRegionHidden(_ region: Region) -> Bool { hiddenRegions.contains(region.code) }
    func isYearHidden(_ year: Int) -> Bool { hiddenYears.contains(year) }
    func isMonthHidden(_ month: String) -> Bool {
        hiddenMonths.contains(month) || Int(month.prefix(4)).map(hiddenYears.contains) == true
    }

    func setRegion(_ region: Region, hidden: Bool) {
        if hidden { hiddenRegions.insert(region.code) } else { hiddenRegions.remove(region.code) }
        persist()
    }

    func setYear(_ year: Int, hidden: Bool) {
        if hidden {
            hiddenYears.insert(year)
            hiddenMonths = hiddenMonths.filter { !$0.hasPrefix("\(year)-") }
        } else {
            hiddenYears.remove(year)
        }
        persist()
    }

    func setMonth(_ month: String, hidden: Bool) {
        if let year = Int(month.prefix(4)), hiddenYears.contains(year), !hidden {
            // Showing one month of a hidden year: hide the year's other months
            // individually instead.
            hiddenYears.remove(year)
            for other in 1...12 {
                let candidate = String(format: "%04d-%02d", year, other)
                if candidate != month { hiddenMonths.insert(candidate) }
            }
        } else if hidden {
            hiddenMonths.insert(month)
        } else {
            hiddenMonths.remove(month)
        }
        persist()
    }

    func showAll() {
        hiddenRegions = []
        hiddenYears = []
        hiddenMonths = []
        persist()
    }

    private func persist() {
        let saved = Saved(regions: hiddenRegions.sorted(), years: hiddenYears.sorted(),
                          months: hiddenMonths.sorted())
        if saved.regions.isEmpty, saved.years.isEmpty, saved.months.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: - the index

    struct Entry {
        let region: Region
        /// `YYYY-MM`, or nil for an undated trip (never hidden by date).
        let month: String?
    }

    @ObservationIgnored private var indexKey: [Train]?
    @ObservationIgnored private var indexValue: [String: Entry] = [:]

    /// trip id → (region, month), once per store generation.
    func index(_ trains: [Train]) -> [String: Entry] {
        if let indexKey, ArrayGeneration.same(indexKey, trains) { return indexValue }
        var index: [String: Entry] = [:]
        index.reserveCapacity(trains.count)
        for train in trains {
            let date = Dates.normalizeDateString(train.date)
            index[train.id] = Entry(region: Region.resolved(train), month: date.map { String($0.prefix(7)) })
        }
        indexValue = index
        indexKey = trains
        return index
    }

    /// Years and their months that have trips, newest first — what the
    /// picker offers. Only months that exist; never an empty choice.
    func calendar(_ trains: [Train]) -> [(year: Int, months: [String])] {
        var byYear: [Int: Set<String>] = [:]
        for entry in index(trains).values {
            guard let month = entry.month, let year = Int(month.prefix(4)) else { continue }
            byYear[year, default: []].insert(month)
        }
        return byYear.keys.sorted(by: >).map { ($0, byYear[$0]!.sorted()) }
    }

    /// Whether `scoped(_:)` has anything to remove: an active filter, or trips
    /// in a disabled region. Memoised through the trip index.
    func needsScoping(_ loaded: ItineraryStore.Loaded) -> Bool {
        isActive || hasDisabledRegionTrips(loaded.trains)
    }

    /// Whether the store holds trips in a disabled region (hidden everywhere).
    func hasDisabledRegionTrips(_ trains: [Train]) -> Bool {
        index(trains).values.contains { !$0.region.isEnabled }
    }

    /// The regions that have trips, in the interface's order.
    func regions(_ trains: [Train]) -> [Region] {
        let present = Set(index(trains).values.map(\.region))
        return Region.enabledOrdered.filter { present.contains($0) }
    }

    // MARK: - the scoped answer

    struct Scoped {
        let trains: [Train]
        let days: [ItineraryStore.Loaded.Day]
        let hiddenIDs: Set<String>
    }

    @ObservationIgnored private var scopedKey: (trains: [Train], days: [ItineraryStore.Loaded.Day],
                                                regions: Set<String>, years: Set<Int>, months: Set<String>)?
    @ObservationIgnored private var scopedValue = Scoped(trains: [], days: [], hiddenIDs: [])

    /// The store's trips and days minus hidden regions, years and months.
    /// Returns the SAME arrays until the store or a choice changes, so the
    /// memoised derivations downstream keep their keys.
    func scoped(_ loaded: ItineraryStore.Loaded) -> Scoped {
        // Trips in a disabled region (RegionConnectivity) are always hidden
        // here — display only; the store still holds, saves and exports them.
        if let scopedKey, ArrayGeneration.same(scopedKey.trains, loaded.trains),
           ArrayGeneration.same(scopedKey.days, loaded.days),
           scopedKey.regions == hiddenRegions, scopedKey.years == hiddenYears,
           scopedKey.months == hiddenMonths {
            return scopedValue
        }
        let index = index(loaded.trains)
        var hidden = Set<String>()
        for (id, entry) in index {
            if !entry.region.isEnabled { hidden.insert(id); continue }
            if hiddenRegions.contains(entry.region.code) { hidden.insert(id); continue }
            if let month = entry.month, isMonthHidden(month) { hidden.insert(id) }
        }
        let trains = loaded.trains.filter { !hidden.contains($0.id) }
        let days = loaded.days.compactMap { day -> ItineraryStore.Loaded.Day? in
            var day = day
            day.trains = day.trains.filter { !hidden.contains($0.id) }
            return day.trains.isEmpty ? nil : day
        }
        scopedValue = Scoped(trains: trains, days: days, hiddenIDs: hidden)
        scopedKey = (loaded.trains, loaded.days, hiddenRegions, hiddenYears, hiddenMonths)
        return scopedValue
    }
}
