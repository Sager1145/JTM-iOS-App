import Testing
@testable import RailCore

@Suite("Timetable service-day alignment")
struct TimetableServiceDayContextTests {
    @Test func overnightClockKeepsOneRailValidityDate() {
        let context = TimetableServiceDayContext(serviceDate: "2026-09-27")
        #expect(context.networkRideDate == "2026-09-27")
        #expect(context.railValidityDate(totalSeconds: 23 * 3600 + 50 * 60) == "2026-09-27")
        #expect(context.railValidityDate(totalSeconds: 25 * 3600 + 3 * 60) == "2026-09-27")
    }

    @Test func validityUsesHalfOpenServiceDayBounds() {
        let context = TimetableServiceDayContext(serviceDate: "1987-04-01")
        #expect(context.contains(validFrom: "1987-04-01", validUntil: nil))
        #expect(!context.contains(validFrom: nil, validUntil: "1987-04-01"))
        #expect(context.contains(validFrom: "1900-01-01", validUntil: "1987-04-02"))
    }
}
