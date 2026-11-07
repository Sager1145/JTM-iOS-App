import Foundation
import Testing
@testable import RailCore

@Suite("Ticket reading to editor values")
struct TicketReadingDraftTests {
    private func day(_ text: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }

    @Test func aYearlessDateIsTheLatestNotFarAhead() {
        #expect(TicketDate(year: nil, month: 12, day: 30).dayString(near: day("2027-01-03")) == "2026-12-30")
        #expect(TicketDate(year: nil, month: 1, day: 2).dayString(near: day("2026-12-30")) == "2027-01-02")
        #expect(TicketDate(year: nil, month: 6, day: 1).dayString(near: day("2026-11-06")) == "2026-06-01")
        // A used ticket from six months back is not read as next year's.
        #expect(TicketDate(year: nil, month: 5, day: 6).dayString(near: day("2026-11-06")) == "2026-05-06")
        #expect(TicketDate(year: nil, month: 11, day: 20).dayString(near: day("2026-11-06")) == "2026-11-20")
        // No leap day within a year either side: nothing, rather than a guess.
        #expect(TicketDate(year: nil, month: 2, day: 29).dayString(near: day("2026-11-06")) == nil)
        #expect(TicketDate(year: 2024, month: 2, day: 29).dayString(near: day("2026-11-06")) == "2024-02-29")
        #expect(TicketDate(year: 2025, month: 2, day: 30).dayString(near: day("2026-11-06")) == nil)
    }

    @Test func faresAreStoredInWholePrintedUnits() throws {
        var tw = TicketReadingResult(region: .tw)
        tw.fare = TicketField(149000, confidence: 0.9)
        tw.currency = TicketField("TWD", confidence: 0.9)
        tw.seat = TicketField("５ Ａ", confidence: 0.9)
        let twTicket = try #require(Ticket(reading: tw))
        #expect(twTicket.fare == 1490)
        #expect(twTicket.currency == "TWD")
        #expect(twTicket.seat == "5A")

        var jp = TicketReadingResult(region: .jp)
        jp.fare = TicketField(14720, confidence: 0.9)
        jp.currency = TicketField("JPY", confidence: 0.9)
        jp.kind = TicketField(.expressSupplement, confidence: 0.9)
        let jpTicket = try #require(Ticket(reading: jp))
        #expect(jpTicket.fare == 14720)
        #expect(jpTicket.kind == "expressSupplement")

        var empty = TicketReadingResult(region: .kr)
        empty.origin = TicketField("서울", confidence: 0.9)
        #expect(Ticket(reading: empty) == nil)
    }

    @Test func serviceNamesImplyOnlyFixedClasses() {
        #expect(TicketServiceType.trainType(serviceName: "のぞみ", region: .jp) == "highSpeed")
        #expect(TicketServiceType.trainType(serviceName: "あずさ", region: .jp) == nil)
        #expect(TicketServiceType.trainType(serviceName: "あずさ", region: .jp, kind: .expressSupplement) == "limitedExpress")
        #expect(TicketServiceType.trainType(serviceName: "自強", region: .tw) == "limitedExpress")
        #expect(TicketServiceType.trainType(serviceName: "區間快", region: .tw) == "rapid")
        #expect(TicketServiceType.trainType(serviceName: "KTX-산천", region: .kr) == "highSpeed")
        #expect(TicketServiceType.trainType(serviceName: "무궁화호", region: .kr) == "express")
        #expect(TicketServiceType.trainType(serviceName: nil, region: .kr) == nil)
    }

    @Test func numbersAreWrittenTheRegionsWay() {
        #expect(TicketServiceType.displayNumber(serviceName: "のぞみ", serviceNumber: "023", region: .jp) == "のぞみ23号")
        #expect(TicketServiceType.displayNumber(serviceName: "自強", serviceNumber: "123", region: .tw) == "自強 123次")
        #expect(TicketServiceType.displayNumber(serviceName: "KTX", serviceNumber: "101", region: .kr) == "KTX 101")
        #expect(TicketServiceType.displayNumber(serviceName: "あずさ", serviceNumber: nil, region: .jp) == "あずさ")
        #expect(TicketServiceType.displayNumber(serviceName: nil, serviceNumber: nil, region: .jp) == nil)
    }
}
