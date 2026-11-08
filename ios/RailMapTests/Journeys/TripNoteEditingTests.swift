import Foundation
import RailCore
import Testing

@testable import RailMap

struct TripNoteEditingTests {
    @Test func categoryReusesExistingSpellingIgnoringCaseAndWidth() {
        let existing = ["Incident", "事故"]
        #expect(TripNoteEditing.canonicalCategory("incident", existing: existing) == "Incident")
        #expect(TripNoteEditing.canonicalCategory("ＩＮＣＩＤＥＮＴ", existing: existing) == "Incident")
        #expect(TripNoteEditing.canonicalCategory("  Incident ", existing: existing) == "Incident")
        #expect(TripNoteEditing.canonicalCategory("Delay", existing: existing) == "Delay")
        #expect(TripNoteEditing.canonicalCategory("   ", existing: existing) == "")
    }

    @Test func chipsFilterByTypedText() {
        let all = ["Incident", "Observation", "事故"]
        #expect(TripNoteEditing.filteredSuggestions(all, typed: "") == all)
        #expect(TripNoteEditing.filteredSuggestions(all, typed: "OBS") == ["Observation"])
        #expect(TripNoteEditing.filteredSuggestions(all, typed: "事") == ["事故"])
        #expect(TripNoteEditing.filteredSuggestions(all, typed: "zzz").isEmpty)
    }

    @Test func pickerConvertsInTheRegionZoneNotTheDeviceZone() throws {
        let clock = RegionClock.forRegionCode("jp")
        let instant = TripNoteEditing.pickerInstant(
            serviceDate: "2026-10-12", time: "25:10", clock: clock, reference: Date())
        // 2026-10-13 01:10 JST is 2026-10-12 16:10 UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        #expect(parts.day == 12 && parts.hour == 16 && parts.minute == 10)
        #expect(TripNoteEditing.time(forPicked: instant, serviceDate: "2026-10-12", clock: clock) == "25:10")
    }

    @Test func pickerRangeSpansTwoServiceDays() throws {
        let clock = RegionClock.forRegionCode("jp")
        let range = try #require(TripNoteEditing.pickerRange(serviceDate: "2026-10-12", clock: clock))
        #expect(TripNoteEditing.time(forPicked: range.lowerBound, serviceDate: "2026-10-12", clock: clock) == "00:00")
        #expect(TripNoteEditing.time(forPicked: range.upperBound, serviceDate: "2026-10-12", clock: clock) == "47:59")
        #expect(TripNoteEditing.pickerRange(serviceDate: nil, clock: clock) == nil)
    }

    @Test func undatedPickerKeepsTheStoredDayOffset() {
        let clock = RegionClock.forRegionCode("jp")
        let shown = TripNoteEditing.pickerInstant(
            serviceDate: nil, time: "25:10", clock: clock, reference: Date())
        // The time-only picker shows 01:10; untouched it must read back 25:10.
        #expect(TripNoteEditing.time(forPicked: shown, serviceDate: nil, clock: clock,
                                     carryingDayOf: "25:10") == "25:10")
        let seven = TripNoteEditing.pickerInstant(
            serviceDate: nil, time: "07:05", clock: clock, reference: Date())
        #expect(TripNoteEditing.time(forPicked: seven, serviceDate: nil, clock: clock,
                                     carryingDayOf: "25:10") == "31:05")
        #expect(TripNoteEditing.time(forPicked: seven, serviceDate: nil, clock: clock) == "07:05")
    }

    @Test func timeOnlyPickerRoundTripsWithoutServiceDate() {
        let clock = RegionClock.forRegionCode("jp")
        let instant = TripNoteEditing.pickerInstant(
            serviceDate: nil, time: "07:05", clock: clock, reference: Date())
        #expect(TripNoteEditing.time(forPicked: instant, serviceDate: nil, clock: clock) == "07:05")
    }
}

@MainActor
struct TripNoteClockTests {
    @Test func aTripWithoutARegionUsesTheResolvedRegionClock() {
        let train = Train(id: "t", date: "2026-10-12", number: "1", origin: "A",
                          destination: "B", stops: [])
        #expect(train.region == nil)
        let describer = TripNoteDescriber(train: train, localization: AppLocalization())
        #expect(describer.clock == Region.resolved(train).clock)
        let taiwan = Train(id: "t2", date: "2026-10-12", number: "1", origin: "A",
                           destination: "B", stops: [], region: "tw")
        #expect(TripNoteDescriber(train: taiwan, localization: AppLocalization()).clock
                == RegionClock.taiwan)
    }
}

@MainActor
struct TripNoteShareTextTests {
    @Test func shareTextMatchesTheCardAndKeepsTheBodyExactly() {
        let train = Train(id: "t", date: "2026-10-12", number: "Notes 1", origin: "A",
                          destination: "B", stops: [], region: "jp")
        let note = TripNote(
            id: "n", category: "Crew change", text: "- [ ] swap\n\n  indented line", time: "25:10",
            anchor: .coordinate(Coordinate(lon: 139.7, lat: 35.6)))
        let describer = TripNoteDescriber(train: train, localization: AppLocalization())
        let text = describer.shareText(note)
        let lines = text.components(separatedBy: "\n")
        #expect(lines[0] == "Crew change · 01:10 (+1) UTC+9")
        #expect(lines.contains("Notes 1 · 2026-10-12"))
        #expect(text.hasSuffix("\n\n- [ ] swap\n\n  indented line"))
    }
}
