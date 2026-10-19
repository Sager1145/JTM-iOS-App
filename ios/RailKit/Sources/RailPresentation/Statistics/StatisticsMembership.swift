import RailCore

/// Membership shared by the coverage map, passport cards and available-year picker.
/// Area geometry supplies candidate IDs; it never changes the record's ridden status.
public enum StatisticsMembership {
    public struct Selection: Equatable, Sendable {
        public var year: Int?
        public var groupID: String?
        public var dates: StatisticsDateSelection

        public init(year: Int? = nil, groupID: String? = nil,
                    dates: StatisticsDateSelection = StatisticsDateSelection()) {
            self.year = year
            self.groupID = groupID
            self.dates = dates
        }

        public func includes(_ train: Train) -> Bool {
            (year == nil || StatisticsMembership.year(of: train) == year)
                && (groupID == nil || train.journeyGroup?.id == groupID)
                && (dates.isEmpty || dates.contains(StatisticsMembership.date(of: train)))
        }
    }

    public struct Slice: Sendable {
        public let trains: [Train]
        public let days: [JourneyDay]
        public let unconfirmed: Int
    }

    public static func slice(
        trains: [Train], days: [JourneyDay] = [], regionCode: String?,
        rule: RegionScopeRule, selection: Selection, memberIDs: Set<String>? = nil,
        selectedDate: String = Dates.allDates
    ) -> Slice {
        var kept: [Train] = []
        var unconfirmed = 0
        for train in trains {
            if let regionCode, (rule.matched(train) ?? rule.fallback) != regionCode { continue }
            if let memberIDs {
                guard memberIDs.contains(train.id) else { continue }
            }
            guard selection.includes(train) else { continue }
            guard RideLedger.hasBeenRidden(train) else { unconfirmed += 1; continue }
            if selectedDate != Dates.allDates {
                guard Dates.trainSpans(train, date: selectedDate) else { continue }
            }
            kept.append(train)
        }
        let ids = Set(kept.map(\.id))
        return Slice(trains: kept, days: days.compactMap { day in
            let trains = day.trains.filter { ids.contains($0.id) }
            return trains.isEmpty ? nil : JourneyDay(date: day.date, trains: trains)
        }, unconfirmed: unconfirmed)
    }

    /// The year picker ignores its own year/date selection, retaining region, area and group.
    public static func availableYears(
        trains: [Train], regionCode: String?, rule: RegionScopeRule,
        groupID: String?, memberIDs: Set<String>? = nil, currentYear: Int, selectedYear: Int?
    ) -> [Int] {
        let slice = slice(trains: trains, regionCode: regionCode, rule: rule,
                          selection: Selection(groupID: groupID), memberIDs: memberIDs)
        var years = Set(slice.trains.compactMap { year(of: $0) })
        years.insert(currentYear)
        if let selectedYear { years.insert(selectedYear) }
        return years.sorted(by: >)
    }

    public static func year(of train: Train) -> Int? {
        let date = date(of: train)
        return date == Dates.undated ? nil : Int(date.prefix(4))
    }

    /// Calendar choices ignore active date/group filters so another classification remains reachable.
    public static func availableDates(
        trains: [Train], regionCode: String?, rule: RegionScopeRule,
        year: Int?, memberIDs: Set<String>? = nil
    ) -> [String] {
        let slice = slice(trains: trains, regionCode: regionCode, rule: rule,
                          selection: Selection(year: year), memberIDs: memberIDs)
        return Set(slice.trains.map { date(of: $0) }).filter { $0 != Dates.undated }.sorted()
    }

    private static func date(of train: Train) -> String {
        Dates.trainDate(train)
    }
}
