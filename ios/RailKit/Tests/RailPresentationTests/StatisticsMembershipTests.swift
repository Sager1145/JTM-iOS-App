import RailCore
import Testing
@testable import RailPresentation

struct StatisticsMembershipTests {
    private let rule = RegionScopeRule(regionCodes: ["jp", "tw"], numericCodeRegion: "jp", fallback: "jp")

    private func ride(_ id: String, date: String, ridden: Bool = true) -> Train {
        Train(id: id, date: date, number: id, origin: "A", destination: "B",
              stops: [Stop(name: "A", departure: "23:00", rideSegment: ridden),
                      Stop(name: "B", arrival: "25:00", rideSegment: ridden)], region: "jp")
    }

    @Test("Map span dates and passport bucket dates retain their different meanings")
    func spanAndBucket() {
        let overnight = ride("night", date: "2026-10-11")
        let unconfirmed = ride("plan", date: "2026-10-11", ridden: false)
        let excluded = ride("other-area", date: "2026-10-11")
        let trains = [overnight, unconfirmed, excluded]
        let days = [JourneyDay(date: "2026-10-11", trains: trains)]
        let passport = StatisticsMembership.slice(
            trains: trains, days: days, regionCode: "jp", rule: rule,
            selection: .init(year: 2026), memberIDs: ["night", "plan"])
        #expect(passport.trains.map(\.id) == ["night"])
        #expect(passport.days.first?.trains.map(\.id) == ["night"])
        #expect(passport.unconfirmed == 1)
        let map = StatisticsMembership.slice(
            trains: trains, regionCode: "jp", rule: rule, selection: .init(),
            memberIDs: ["night", "plan"], selectedDate: "2026-10-12")
        #expect(map.trains.map(\.id) == ["night"])
        var dates = StatisticsDateSelection()
        dates.tap("2026-10-12", availableDates: ["2026-10-12"])
        #expect(StatisticsMembership.slice(
            trains: trains, regionCode: "jp", rule: rule,
            selection: .init(dates: dates)).trains.isEmpty)
        #expect(StatisticsMembership.availableDates(
            trains: trains, regionCode: "jp", rule: rule, year: 2026,
            memberIDs: ["night", "plan"]) == ["2026-10-11"])
    }

    @Test("Year options retain selected and current years but omit unconfirmed and other-area rides")
    func years() {
        let trains = [ride("old", date: "2023-05-01"), ride("plan", date: "2022-05-01", ridden: false),
                      ride("other-area", date: "2021-05-01")]
        #expect(StatisticsMembership.availableYears(
            trains: trains, regionCode: "jp", rule: rule, groupID: nil,
            memberIDs: ["old", "plan"], currentYear: 2026, selectedYear: 2024) == [2026, 2024, 2023])
    }

    @Test("Year, group and date holes combine while region membership remains required")
    func selectionIntersection() {
        var selected = ride("selected", date: "2026-10-11")
        selected.journeyGroup = JourneyGroup(id: "trip", name: "Trip")
        var hole = selected
        hole.id = "hole"
        hole.date = "2026-10-12"
        var otherRegion = selected
        otherRegion.id = "taiwan"
        otherRegion.region = "tw"
        let noGroup = ride("ungrouped", date: "2026-10-11")
        var dates = StatisticsDateSelection()
        let occupied: Set<String> = ["2026-10-11", "2026-10-12", "2026-10-13"]
        dates.tap("2026-10-11", availableDates: occupied)
        dates.tap("2026-10-13", availableDates: occupied)
        dates.tap("2026-10-12", availableDates: occupied)
        #expect(StatisticsMembership.slice(
            trains: [selected, hole, otherRegion, noGroup], regionCode: "jp", rule: rule,
            selection: .init(year: 2026, groupID: "trip", dates: dates),
            memberIDs: ["selected", "hole", "taiwan", "ungrouped"]).trains.map(\.id) == ["selected"])
    }
}
