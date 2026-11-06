//
//  WorkspaceJourneyRules.swift — pure journey scopes for the app workspace.
//

import RailCore

/// One date bucket in the journey list.
///
/// A bucket is deliberately different from the days its journeys span. An
/// overnight journey belongs to the bucket of its own date, while date scopes
/// for the map and statistics may include it on a later day.
public struct JourneyDay: Identifiable, Sendable {
    public var date: String
    public var trains: [Train]
    public var id: String { date }

    public init(date: String, trains: [Train]) {
        self.date = date
        self.trains = trains
    }
}

/// Pure rules shared by the workspace's journey destinations.
///
/// Region values stay as stored strings at this layer. The app supplies its
/// catalog's ``RegionScopeRule`` and display order, which keeps this policy
/// independent of MapKit, the app's `Region` enum, and observable stores.
public enum WorkspaceJourneyRules {

    /// Date-bucket and region filtering for the journey log.
    ///
    /// The selected date chooses a bucket, not every journey that physically
    /// spans that day. Empty region sections are removed.
    public static func filteredDays(
        _ days: [JourneyDay],
        selectedDate: String,
        regionCode: String?,
        rule: RegionScopeRule
    ) -> [JourneyDay] {
        var source = selectedDate == Dates.allDates
            ? days
            : days.filter { $0.date == selectedDate }
        guard let regionCode else { return source }
        source = source.compactMap { day in
            let trains = day.trains.filter { resolvedRegion(of: $0, rule: rule) == regionCode }
            return trains.isEmpty ? nil : JourneyDay(date: day.date, trains: trains)
        }
        return source
    }

    /// Dates offered by the Upcoming or All Journeys menus.
    ///
    /// The normal menu includes manually created empty buckets. Upcoming is
    /// built only from journeys in the Upcoming list (see
    /// ``TripListRules/isUpcoming(_:today:)``); manual buckets are intentionally absent. The
    /// menu remains bucket-based, so an overnight journey offers its own date
    /// here even though the list and map scopes can include its later days.
    ///
    /// `history` narrows the normal menu to the History list — every journey
    /// NOT in Upcoming — and keeps the manual buckets.
    public static func journeyDates(
        trains: [Train],
        regionCode: String?,
        upcoming: Bool,
        history: Bool = false,
        todayByRegion: [String: String],
        manualDates: [String],
        rule: RegionScopeRule
    ) -> [String] {
        let regional = trains.filter { train in
            guard let regionCode else { return true }
            return resolvedRegion(of: train, rule: rule) == regionCode
        }
        func isUpcoming(_ train: Train) -> Bool {
            TripListRules.isUpcoming(
                train, today: todayByRegion[resolvedRegion(of: train, rule: rule)])
        }
        guard upcoming else {
            let listed = history ? regional.filter { !isUpcoming($0) } : regional
            return Dates.availableDates(listed, manualDates: manualDates)
        }
        return Dates.availableDates(regional.filter(isUpcoming))
    }

    /// The journeys in the Upcoming list.
    ///
    /// The reader's date filter is a span filter here: an overnight journey
    /// remains present on its second day. Whether it is upcoming is the
    /// record's stored list membership, or for a legacy record its date — see
    /// ``TripListRules/isUpcoming(_:today:)``.
    public static func upcomingScope(
        trains: [Train],
        regionCode: String?,
        selectedDate: String,
        todayByRegion: [String: String],
        rule: RegionScopeRule
    ) -> [Train] {
        trains
            .filter { train in
                let region = resolvedRegion(of: train, rule: rule)
                if let regionCode, region != regionCode { return false }
                if selectedDate != Dates.allDates,
                    !Dates.trainSpans(train, date: selectedDate)
                {
                    return false
                }
                return TripListRules.isUpcoming(train, today: todayByRegion[region])
            }
            .sorted { lhs, rhs in
                let leftDate = lhs.date ?? ""
                let rightDate = rhs.date ?? ""
                return leftDate == rightDate ? lhs.id < rhs.id : leftDate < rightDate
            }
    }

    /// The ridden journeys counted by statistics and drawn on its coverage map.
    ///
    /// Like Upcoming, a concrete date is a span filter. The ride record itself,
    /// through ``RideLedger``, decides whether a journey contributes.
    public static func statisticsScope(
        trains: [Train],
        regionCode: String?,
        selectedDate: String,
        rule: RegionScopeRule
    ) -> [Train] {
        trains.filter { train in
            if let regionCode, resolvedRegion(of: train, rule: rule) != regionCode {
                return false
            }
            guard RideLedger.hasBeenRidden(train) else { return false }
            guard selectedDate != Dates.allDates else { return true }
            return Dates.trainSpans(train, date: selectedDate)
        }
    }

    /// The region used to scaffold a new journey.
    ///
    /// A selected journey wins. Otherwise the region with the most journeys
    /// wins, with ties resolved by the caller's explicit interface order.
    /// An empty store falls back to the rule's fallback region.
    public static func defaultRegion(
        selectedTrain: Train?,
        trains: [Train],
        orderedRegionCodes: [String],
        rule: RegionScopeRule
    ) -> String {
        if let selectedTrain { return resolvedRegion(of: selectedTrain, rule: rule) }
        guard !trains.isEmpty else { return rule.fallback }

        let counts = Dictionary(grouping: trains) {
            resolvedRegion(of: $0, rule: rule)
        }.mapValues(\.count)
        guard let greatest = counts.values.max() else { return rule.fallback }
        if let ordered = orderedRegionCodes.first(where: { counts[$0] == greatest }) {
            return ordered
        }
        if counts[rule.fallback] == greatest { return rule.fallback }
        return counts.filter { $0.value == greatest }.map(\.key).sorted().first ?? rule.fallback
    }

    private static func resolvedRegion(of train: Train, rule: RegionScopeRule) -> String {
        rule.matched(train) ?? rule.fallback
    }
}
