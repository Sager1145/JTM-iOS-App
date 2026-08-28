import Foundation
import RailCore
import RailPresentation

/// Whether two arrays are the same immutable generation.
///
/// `Array` is copy-on-write, so a store mutation moves to another buffer while
/// an unchanged value handed through SwiftUI keeps this address. That makes
/// the address a complete answer to "is this the same data" — and an O(1) one,
/// which comparing 201 journeys field by field is not.
///
/// Safe against a recycled allocation because every caller here *retains* the
/// array it compares against: the previous buffer cannot be freed while the
/// cache holds it, so it cannot be handed back out to a different array.
enum ArrayGeneration {
    static func same<Element>(_ left: [Element], _ right: [Element]) -> Bool {
        guard left.count == right.count else { return false }
        guard !left.isEmpty else { return true }
        return left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                UnsafeRawPointer(leftBuffer.baseAddress!)
                    == UnsafeRawPointer(rightBuffer.baseAddress!)
            }
        }
    }
}

/// The workspace's derived answers, computed once per input rather than once
/// per read.
///
/// ## The problem this exists for
///
/// `RailWorkspaceView` is one struct, and everything it shows is a computed
/// property on it. That is legible, and it means a single body evaluation asks
/// the same expensive question several times: on the search destination
/// `filteredDays` runs three times over — once for the header's count, once
/// for the list, once for `playbackScope`, which the play button's `disabled`
/// reads — and `filteredDays` with a query is a locale-aware substring search
/// over every field of every journey. Measured over the national sample in
/// release (`ios/tools/bench`, Apple silicon): **4.9 ms per pass**, so 15 ms
/// of a frame spent answering one question three times.
///
/// A body evaluation is not a rare event. A sheet drag is one per frame; so
/// was every published playback tick until the transport moved into its own
/// view. `todayByRegion` builds five `Calendar`s per call and is called twice
/// by `launchRegion` alone.
///
/// ## Why a class, and why writing to it inside `body` is safe
///
/// Because it is *not* SwiftUI state. It is a plain reference type with no
/// `@Observable` and no `@Published`, held in `@State` so it survives the
/// struct being recreated. Nothing observes it, so filling a cache during a
/// body evaluation invalidates nothing and cannot loop — the rule this would
/// break is about mutating state SwiftUI is *watching*.
///
/// Every entry is a pure function of its key. That is the whole correctness
/// argument, and it is why the keys are generations of the inputs rather than
/// summaries of them: an answer is reused exactly when it would have been
/// recomputed identically.
@MainActor
final class WorkspaceDerived {

    // MARK: - the journey list

    private struct DaysKey {
        let days: [ItineraryStore.Loaded.Day]
        let date: String
        let query: String
        /// The search reads station names the store does not carry — see
        /// ``AppLocalization/localizedStationNames(of:)`` — so the answer
        /// depends on the reader's language and on which readings tables have
        /// landed, neither of which is in `days`.
        let naming: StationNamingGeneration
    }

    /// Two slots, because one body evaluation asks two different questions:
    /// the list's own filter and — on the search destination — the unfiltered
    /// count behind it. A single slot would thrash between them and cache
    /// nothing at all.
    private var daysCache: [(key: DaysKey, value: [ItineraryStore.Loaded.Day])] = []

    /// `RailWorkspaceView.filteredDays`, memoised.
    func days(
        of loaded: ItineraryStore.Loaded, selectedDate: String, query: String,
        naming: StationNamingGeneration,
        compute: () -> [ItineraryStore.Loaded.Day]
    ) -> [ItineraryStore.Loaded.Day] {
        for entry in daysCache
        where entry.key.date == selectedDate && entry.key.query == query
            && entry.key.naming == naming
            && ArrayGeneration.same(entry.key.days, loaded.days) {
            return entry.value
        }
        let value = compute()
        let key = DaysKey(
            days: loaded.days, date: selectedDate, query: query, naming: naming)
        daysCache.insert((key, value), at: 0)
        if daysCache.count > 2 { daysCache.removeLast(daysCache.count - 2) }
        return value
    }

    // MARK: - what day it is, on five clocks

    // `todayByRegion` used to be memoised here. It moved to ``RegionToday``,
    // which is reachable from every view that asks rather than only from this
    // workspace — and two caches would be two todays.

    // MARK: - the two ends of the calendar

    private struct DatedKey {
        let trains: [Train]
        let today: [Region: String]
    }

    private var upcomingKey: DatedKey?
    private var upcomingValue: [Train] = []
    /// The same answer as a set of ids — what the Upcoming destination's map
    /// filter wants, and the reason this returns a pair the way
    /// ``statisticsScope(trains:region:date:compute:)`` does: the list and the
    /// map ask the same question of the same pass.
    private var upcomingIDs: Set<String> = []
    private var latestPastKey: DatedKey?
    private var latestPastValue: Train?

    func upcoming(
        trains: [Train], today: [Region: String], compute: () -> [Train]
    ) -> (trains: [Train], ids: Set<String>) {
        if let upcomingKey, upcomingKey.today == today,
           ArrayGeneration.same(upcomingKey.trains, trains) {
            return (upcomingValue, upcomingIDs)
        }
        upcomingValue = compute()
        upcomingIDs = Set(upcomingValue.map(\.id))
        upcomingKey = DatedKey(trains: trains, today: today)
        return (upcomingValue, upcomingIDs)
    }

    // MARK: - the opening view

    private var launchFocusKey: [Train]?
    private var launchFocusValue: Set<String> = []

    /// The journeys the opening view is framed on, memoised against the
    /// upcoming list it is cut from.
    ///
    /// Keyed on that list's generation rather than on the store's: the answer
    /// is a function of what is still ahead, and ``upcoming(trains:today:compute:)``
    /// already hands back the same buffer while that has not changed.
    func launchFocus(upcoming: [Train], compute: () -> Set<String>) -> Set<String> {
        if let launchFocusKey, ArrayGeneration.same(launchFocusKey, upcoming) {
            return launchFocusValue
        }
        launchFocusValue = compute()
        launchFocusKey = upcoming
        return launchFocusValue
    }

    func latestPast(
        trains: [Train], today: [Region: String], compute: () -> Train?
    ) -> Train? {
        if let latestPastKey, latestPastKey.today == today,
           ArrayGeneration.same(latestPastKey.trains, trains) {
            return latestPastValue
        }
        latestPastValue = compute()
        latestPastKey = DatedKey(trains: trains, today: today)
        return latestPastValue
    }

    // MARK: - the statistics scope

    private struct ScopeKey {
        let trains: [Train]
        let region: Region?
        let date: String
    }

    private var scopeKey: ScopeKey?
    private var scopeValue: [Train] = []
    /// The same answer as a set of ids, which is what the map filter wants and
    /// what it used to rebuild on every frame of a sheet drag.
    private var scopeIDs: Set<String> = []

    /// The scope also drops journeys the record does not say were ridden, and
    /// that is not in the key because it does not need to be: it is a field of
    /// the records themselves, so `trains` moving is the only way it can
    /// change. See ``RailPresentation/RideLedger``.
    func statisticsScope(
        trains: [Train], region: Region?, date: String, compute: () -> [Train]
    ) -> (trains: [Train], ids: Set<String>) {
        if let scopeKey, scopeKey.region == region, scopeKey.date == date,
           ArrayGeneration.same(scopeKey.trains, trains) {
            return (scopeValue, scopeIDs)
        }
        scopeValue = compute()
        scopeIDs = Set(scopeValue.map(\.id))
        scopeKey = ScopeKey(trains: trains, region: region, date: date)
        return (scopeValue, scopeIDs)
    }

    // MARK: - the drawn rides

    private var rideKey: [RiddenRouteStore.DrawnRide]?
    private var rideIDsValue: Set<String> = []
    private var riddenCountriesValue: [String] = []

    /// `rideIDs` and `riddenCountries` — two passes over every drawn ride that
    /// were being made on every body evaluation for answers that change only
    /// when a route finishes solving.
    func rideSummary(
        _ rides: [RiddenRouteStore.DrawnRide]
    ) -> (ids: Set<String>, countries: [String]) {
        if let rideKey, ArrayGeneration.same(rideKey, rides) {
            return (rideIDsValue, riddenCountriesValue)
        }
        var ids = Set<String>()
        var countries = Set<String>()
        ids.reserveCapacity(rides.count)
        for ride in rides {
            ids.insert(ride.id)
            countries.insert(ride.country)
        }
        rideIDsValue = ids
        riddenCountriesValue = countries.sorted()
        rideKey = rides
        return (rideIDsValue, riddenCountriesValue)
    }

    // MARK: - the map's ride scope

    private var scopedRidesKey: (rides: [RiddenRouteStore.DrawnRide], ids: Set<String>)?
    private var scopedRidesValue: [RiddenRouteStore.DrawnRide] = []

    /// The drawn rides, narrowed to a destination's scope.
    ///
    /// Held rather than filtered per read, and that is not only about the
    /// filter's own cost: `RailMapView` takes an O(1) path when the array it
    /// is handed still shares its buffer with the one the coordinator holds,
    /// and falls back to a signature comparison over every ride when it does
    /// not. A freshly filtered array never shares, so a destination that
    /// scopes the map would pay that comparison on every frame of a sheet
    /// drag — and the Upcoming destination, which scopes it, is the one the
    /// app opens on.
    ///
    /// One slot: a body evaluation asks at most one destination's question.
    func rides(
        _ rides: [RiddenRouteStore.DrawnRide], scopedTo ids: Set<String>
    ) -> [RiddenRouteStore.DrawnRide] {
        if let scopedRidesKey, scopedRidesKey.ids == ids,
           ArrayGeneration.same(scopedRidesKey.rides, rides) {
            return scopedRidesValue
        }
        scopedRidesValue = rides.filter { ids.contains($0.id) }
        scopedRidesKey = (rides, ids)
        return scopedRidesValue
    }

    // MARK: - the map's date scope

    private var dateScopeKey: (trains: [Train], date: String)?
    private var dateScopeIDs: Set<String> = []

    /// The ids of every journey that spans `date` — `map-date-filter`'s
    /// answer, which is a pass over every journey's `forDates` and was being
    /// made once per frame while the reader dragged the sheet.
    func trainIDs(spanning date: String, in trains: [Train]) -> Set<String> {
        if let dateScopeKey, dateScopeKey.date == date,
           ArrayGeneration.same(dateScopeKey.trains, trains) {
            return dateScopeIDs
        }
        dateScopeIDs = Set(
            trains.filter { Dates.trainSpans($0.forDates, date: date) }.map(\.id))
        dateScopeKey = (trains, date)
        return dateScopeIDs
    }
}
