import RailCore
import Testing

@testable import RailPresentation

struct LaunchJourneySelectorTests {

    private func train(
        _ id: String,
        date: String?,
        region: String,
        departure: String? = nil,
        arrival: String? = nil
    ) -> Train {
        Train(
            id: id,
            date: date,
            number: id,
            origin: "A",
            destination: "B",
            stops: [
                Stop(name: "A", arrival: nil, departure: departure),
                Stop(name: "B", arrival: arrival, departure: nil),
            ],
            region: region)
    }

    private let today = [
        "jp": "2026-08-29",
        "tw": "2026-08-29",
        "hk": "2026-08-29",
        "mo": "2026-08-29",
        "kr": "2026-08-29",
    ]

    private func first(in trains: [Train]) -> Train? {
        LaunchJourneySelector.first(in: trains) { train in
            train.region.flatMap { today[$0] }
        }
    }

    @Test("an untimed Macao route cannot choose the launch country")
    func excludesUntimedMacaoRoute() {
        let macaoDemo = train("mo-demo", date: "2026-08-30", region: "mo")
        let japanTrip = train(
            "jp-trip", date: "2026-08-31", region: "jp", departure: "08:05")

        #expect(first(in: [macaoDemo, japanTrip])?.id == "jp-trip")
    }

    @Test("the earliest upcoming journey wins regardless of store order")
    func earliestUpcomingWins() {
        let later = train(
            "tw-later", date: "2026-09-03", region: "tw", departure: "09:00")
        let first = train(
            "kr-first", date: "2026-08-30", region: "kr", departure: "10:00")

        #expect(self.first(in: [later, first])?.id == "kr-first")
    }

    @Test("departure time orders journeys on the same future date")
    func departureOrdersSameDay() {
        let afternoon = train(
            "afternoon", date: "2026-08-30", region: "tw", departure: "15:00")
        let morning = train(
            "morning", date: "2026-08-30", region: "hk", departure: "07:30")

        #expect(first(in: [afternoon, morning])?.id == "morning")
    }

    @Test("future journeys take precedence over history")
    func futurePrecedesHistory() {
        let history = train(
            "history", date: "2020-01-01", region: "jp", departure: "08:00")
        let future = train(
            "future", date: "2026-09-01", region: "kr", departure: "08:00")

        #expect(first(in: [history, future])?.id == "future")
    }

    @Test("without a future journey the earliest historical journey wins")
    func fallsBackToFirstHistory() {
        let recent = train(
            "recent", date: "2025-01-01", region: "jp", departure: "08:00")
        let first = train(
            "first", date: "2019-04-12", region: "hk", departure: "08:00")

        #expect(self.first(in: [recent, first])?.id == "first")
    }

    @Test("undated, malformed, and whitespace-only routes are excluded")
    func excludesUnusableJourneys() {
        let undated = train("undated", date: nil, region: "jp", departure: "08:00")
        let malformed = train(
            "malformed", date: "tomorrow", region: "tw", departure: "09:00")
        let whitespace = train(
            "whitespace", date: "2026-08-30", region: "mo", departure: "  \n")

        #expect(first(in: [undated, malformed, whitespace]) == nil)
    }
}
