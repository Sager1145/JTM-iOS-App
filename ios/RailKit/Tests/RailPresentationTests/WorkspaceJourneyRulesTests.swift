import RailCore
import Testing

@testable import RailPresentation

struct WorkspaceJourneyRulesTests {
    private let rule = RegionScopeRule(
        regionCodes: ["jp", "tw", "hk"],
        numericCodeRegion: "jp",
        fallback: "jp")

    private let today = [
        "jp": "2026-09-07",
        "tw": "2026-09-06",
        "hk": "2026-09-07",
    ]

    private func train(
        _ id: String,
        date: String?,
        region: String? = "jp",
        departure: String? = "08:00",
        arrival: String? = "09:00",
        ridden: Bool = true
    ) -> Train {
        Train(
            id: id,
            date: date,
            number: id,
            origin: "A",
            destination: "B",
            stops: [
                Stop(name: "A", departure: departure, rideSegment: ridden),
                Stop(name: "B", arrival: arrival, rideSegment: ridden),
            ],
            region: region)
    }

    @Test("journey days use buckets while scopes use spans")
    func bucketAndSpanStayDistinct() {
        let overnight = train(
            "overnight", date: "2026-09-07", departure: "23:30", arrival: "25:00")
        let days = [JourneyDay(date: "2026-09-07", trains: [overnight])]

        #expect(WorkspaceJourneyRules.filteredDays(
            days, selectedDate: "2026-09-08", regionCode: nil, rule: rule).isEmpty)
        #expect(WorkspaceJourneyRules.upcomingScope(
            trains: [overnight], regionCode: nil, selectedDate: "2026-09-08",
            todayByRegion: today, rule: rule).map(\.id) == ["overnight"])
        #expect(WorkspaceJourneyRules.statisticsScope(
            trains: [overnight], regionCode: nil, selectedDate: "2026-09-08",
            rule: rule).map(\.id) == ["overnight"])
    }

    @Test("day filtering removes empty region buckets and resolves fallbacks")
    func filtersDayBucketsByRegion() {
        let japan = train("jp", date: "2026-09-07")
        let taiwan = train("tw", date: "2026-09-07", region: "tw")
        let fallback = train("fallback", date: "2026-09-08", region: nil)
        let days = [
            JourneyDay(date: "2026-09-07", trains: [japan, taiwan]),
            JourneyDay(date: "2026-09-08", trains: [fallback]),
        ]

        let taiwanDays = WorkspaceJourneyRules.filteredDays(
            days, selectedDate: Dates.allDates, regionCode: "tw", rule: rule)
        #expect(taiwanDays.map(\.date) == ["2026-09-07"])
        #expect(taiwanDays.flatMap(\.trains).map(\.id) == ["tw"])

        let japanDays = WorkspaceJourneyRules.filteredDays(
            days, selectedDate: Dates.allDates, regionCode: "jp", rule: rule)
        #expect(japanDays.map(\.date) == ["2026-09-07", "2026-09-08"])
        #expect(japanDays.flatMap(\.trains).map(\.id) == ["jp", "fallback"])
    }

    @Test("normal date menus retain manual buckets under a region scope")
    func normalDatesIncludeManualBuckets() {
        let trains = [
            train("jp", date: "2026-09-07"),
            train("tw", date: "2026-09-08", region: "tw"),
        ]

        let dates = WorkspaceJourneyRules.journeyDates(
            trains: trains, regionCode: "tw", upcoming: false,
            todayByRegion: [:], manualDates: ["2026/09/09", "bad"], rule: rule)

        #expect(dates == ["2026-09-08", "2026-09-09"])
    }

    @Test("upcoming date menus ignore manual dates and the selected date")
    func upcomingDatesUseCalendarAlone() {
        let overnight = train(
            "overnight", date: "2026-09-07", departure: "23:30", arrival: "25:00")
        let past = train("past", date: "2026-09-06")

        let dates = WorkspaceJourneyRules.journeyDates(
            trains: [past, overnight], regionCode: "jp", upcoming: true,
            todayByRegion: today, manualDates: ["2026-09-20"], rule: rule)

        #expect(dates == ["2026-09-07"])
    }

    @Test("upcoming compares raw stored dates against each region's today")
    func upcomingUsesRawRegionalDate() {
        let trains = [
            train("jp-yesterday", date: "2026-09-06"),
            train("tw-today", date: "2026-09-06", region: "tw"),
            train("jp-today-z", date: "2026-09-07"),
            train("jp-today-a", date: "2026-09-07"),
            train("malformed", date: "tomorrow"),
            train("undated", date: nil),
        ]

        let scope = WorkspaceJourneyRules.upcomingScope(
            trains: trains, regionCode: nil, selectedDate: Dates.allDates,
            todayByRegion: today, rule: rule)

        #expect(scope.map(\.id) == [
            "tw-today", "jp-today-a", "jp-today-z", "malformed",
        ])
    }

    @Test("statistics include only ridden journeys in the selected span")
    func statisticsRequireRiddenSegments() {
        let ridden = train("ridden", date: "2026-09-07")
        let planned = train("planned", date: "2026-09-07", ridden: false)
        let otherRegion = train("tw", date: "2026-09-07", region: "tw")

        let scope = WorkspaceJourneyRules.statisticsScope(
            trains: [ridden, planned, otherRegion], regionCode: "jp",
            selectedDate: "2026-09-07", rule: rule)

        #expect(scope.map(\.id) == ["ridden"])
    }

    @Test("the selected journey decides the default region")
    func selectedJourneyWinsDefaultRegion() {
        let selected = train("selected", date: nil, region: "hk")
        let plurality = (0..<3).map { train("tw-\($0)", date: nil, region: "tw") }

        #expect(WorkspaceJourneyRules.defaultRegion(
            selectedTrain: selected, trains: plurality,
            orderedRegionCodes: ["hk", "tw", "jp"], rule: rule) == "hk")
    }

    @Test("plurality ties follow explicit order, then an empty store falls back")
    func pluralityOrderAndFallback() {
        let tied = [
            train("jp", date: nil),
            train("tw", date: nil, region: "tw"),
        ]

        #expect(WorkspaceJourneyRules.defaultRegion(
            selectedTrain: nil, trains: tied,
            orderedRegionCodes: ["tw", "jp", "hk"], rule: rule) == "tw")
        #expect(WorkspaceJourneyRules.defaultRegion(
            selectedTrain: nil, trains: [],
            orderedRegionCodes: ["tw", "jp", "hk"], rule: rule) == "jp")

        let taiwanFallback = RegionScopeRule(
            regionCodes: ["jp", "tw"], numericCodeRegion: "jp", fallback: "tw")
        #expect(WorkspaceJourneyRules.defaultRegion(
            selectedTrain: nil, trains: [],
            orderedRegionCodes: ["jp", "tw"], rule: taiwanFallback) == "tw")
        #expect(WorkspaceJourneyRules.defaultRegion(
            selectedTrain: train("unknown", date: nil, region: nil), trains: tied,
            orderedRegionCodes: ["jp", "tw"], rule: taiwanFallback) == "tw")
    }
}
