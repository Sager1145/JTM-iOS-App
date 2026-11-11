import Foundation
import RailPresentation
import Testing
@testable import RailMap

/// A screenshot import opens "ridden" exactly when the editor would file the
/// trip under History, from the journey's first departure on Japan's clock,
/// and every leg of one screenshot is filed together.
struct TransferGuideImportMembershipTests {
    /// 2026-11-11 12:00 in Japan.
    private let now = Date(timeIntervalSince1970: 1_794_368_400)
    private var today: Date { RecordDate.date(from: "2026-11-11", in: TransferGuideImport.clock)! }

    @Test func laterTodayIsUpcoming() {
        #expect(TransferGuideImport.membership(date: today, firstDeparture: "18:30", now: now) == .upcoming)
    }

    @Test func alreadyDepartedTodayIsPast() {
        #expect(TransferGuideImport.membership(date: today, firstDeparture: "09:00", now: now) == .past)
    }

    /// A mid-journey screenshot: the first leg left this morning, the later
    /// legs are still ahead. The journey is judged once, by its first leg, so
    /// no leg is filed apart from the others.
    @Test func midJourneyIsJudgedByItsFirstLeg() {
        let legDepartures = ["09:00", "13:10", "18:30"]
        let first = legDepartures.first
        let filed = Set(legDepartures.map { _ in
            TransferGuideImport.membership(date: today, firstDeparture: first, now: now)
        })
        #expect(filed == [.past])
    }

    @Test func tomorrowIsUpcomingAndYesterdayIsPast() throws {
        let tomorrow = try #require(RecordDate.date(from: "2026-11-12", in: TransferGuideImport.clock))
        let yesterday = try #require(RecordDate.date(from: "2026-11-10", in: TransferGuideImport.clock))
        #expect(TransferGuideImport.membership(date: tomorrow, firstDeparture: "00:05", now: now) == .upcoming)
        #expect(TransferGuideImport.membership(date: yesterday, firstDeparture: "23:50", now: now) == .past)
    }
}
