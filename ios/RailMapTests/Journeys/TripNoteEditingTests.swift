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
struct TripNoteDayTests {
    private let clock = RegionClock.forRegionCode("jp")

    private func undated(departure: String = "23:30") -> Train {
        Train(id: "t", number: "1", origin: "A", destination: "B",
              stops: [Stop(name: "A", departure: departure, stopType: "origin")], region: "jp")
    }

    private func picked(_ time: String, current: String? = nil, byHand: Bool = false,
                        departure: Int? = 23 * 60 + 30) -> String? {
        let instant = TripNoteEditing.pickerInstant(
            serviceDate: nil, time: time, clock: clock, reference: Date())
        return TripNoteEditing.time(forPicked: instant, serviceDate: nil, clock: clock,
                                    current: current, dayChosenByHand: byHand,
                                    departureMinutes: departure)
    }

    @Test func departureClockIsTheFirstStopsDepartureModADay() {
        #expect(TripNoteEditing.departureMinutes(of: undated()) == 23 * 60 + 30)
        #expect(TripNoteEditing.departureMinutes(of: undated(departure: "25:10")) == 70)
    }

    @Test func earlierThanDepartureIsDay2AndLaterIsDay1() {
        #expect(picked("00:20") == "24:20")
        #expect(picked("23:45") == "23:45")
        #expect(picked("23:30") == "23:30")
    }

    @Test func aHandChosenDaySticks() {
        // Day 1 by hand: an early clock stays on Day 1.
        #expect(picked("00:20", current: "23:30", byHand: true) == "00:20")
        // Day 2 by hand: a late clock stays on Day 2.
        #expect(picked("23:45", current: "24:20", byHand: true) == "47:45")
    }

    @Test func withoutADepartureTheDefaultIsDay1() {
        #expect(picked("00:20", departure: nil) == "00:20")
    }

    @Test func aDatedTripIsNotTouched() {
        let instant = TripNoteEditing.pickerInstant(
            serviceDate: "2026-10-12", time: "00:20", clock: clock, reference: Date())
        #expect(TripNoteEditing.time(forPicked: instant, serviceDate: "2026-10-12", clock: clock,
                                     current: "10:00", dayChosenByHand: false,
                                     departureMinutes: 23 * 60 + 30) == "00:20")
    }

    @Test func twentyFiveTenOpensAsDay2ShowingZeroOneTen() {
        #expect(TripNoteEditing.day(of: "25:10") == 1)
        #expect(TripNoteEditing.day(of: "01:10") == 0)
        #expect(TripNoteTime.display("25:10")?.clock == "01:10")
        #expect(TripNoteEditing.withDay(1, of: "01:10") == "25:10")
        #expect(TripNoteEditing.withDay(0, of: "25:10") == "01:10")
        #expect(TripNoteEditing.withDay(1, of: "23:59") == "47:59")
    }

    @Test func aStoredDayThatDiffersFromAutoCountsAsChosenAndSurvivesANudge() {
        var train = undated(departure: "06:00")
        train.stops[0].departure = "06:00"
        let note = TripNote(id: "n", category: "x", text: "y", time: "31:00",
                            anchor: .station(TripNoteStation(name: "A"), fallback: nil))
        let flow = TripNoteFlow()
        flow.beginEdit(note, train: train)
        #expect(flow.dayChosenByHand, "31:00 on a 06:00 departure is Day 2 by choice.")
        let nudged = picked("07:05", current: "31:00", byHand: flow.dayChosenByHand, departure: 360)
        #expect(nudged == "31:05")
        // A stored day equal to the automatic one is not a choice.
        flow.beginEdit(TripNote(id: "m", category: "x", text: "y", time: "07:00",
                                anchor: note.anchor), train: train)
        #expect(!flow.dayChosenByHand)
    }

    @Test func pickerRangeAndTimeOnlyPickerHoldAcrossDaylightSavingChanges() throws {
        let newYork = RegionClock.forZone("America/New_York", regionCode: "us")
        for date in ["2026-11-01", "2026-03-08"] {
            let range = try #require(TripNoteEditing.pickerRange(serviceDate: date, clock: newYork))
            #expect(TripNoteEditing.time(forPicked: range.lowerBound, serviceDate: date,
                                         clock: newYork) == "00:00")
            #expect(TripNoteEditing.time(forPicked: range.upperBound, serviceDate: date,
                                         clock: newYork) == "47:59")
            // The wall clock the picker shows is the stored one, whatever the offset did.
            for stored in ["01:30", "02:30", "03:30", "25:10", "47:59"] {
                let shown = try #require(TripNoteTime.instant(serviceDate: date, time: stored, clock: newYork))
                #expect(range.contains(shown))
            }
            let tenThirty = try #require(TripNoteTime.instant(serviceDate: date, time: "10:30", clock: newYork))
            #expect(TripNoteEditing.time(forPicked: tenThirty, serviceDate: date, clock: newYork) == "10:30")
        }
        // Undated, on the day clocks change: the picker still shows 03:30 as 03:30.
        let reference = try #require(newYork.instant(serviceDate: "2026-03-08", clock: "12:00"))
        let shown = TripNoteEditing.pickerInstant(serviceDate: nil, time: "03:30", clock: newYork,
                                                  reference: reference)
        #expect(TripNoteEditing.time(forPicked: shown, serviceDate: nil, clock: newYork) == "03:30")
    }

    @Test func dayLabelsAreLocalizedInEveryLanguage() {
        for key in ["ios.tripNotes.day1", "ios.tripNotes.day2"] {
            let row = TripNoteStrings.table[key]
            for language in [Localization.Language.en, .ja, .zhHant, .zhHans] {
                #expect(row?[language]?.isEmpty == false)
            }
        }
    }
}

@MainActor
struct TripNoteDetailsStepAsideTests {
    private let anchor = TripNoteAnchor.station(TripNoteStation(name: "東京"), fallback: nil)

    /// Records the order of the steps and holds each callback until released.
    @MainActor private final class Harness {
        var log: [String] = []
        var closeDone: (@MainActor () -> Void)?
        var reopenDone: (@MainActor () -> Void)?
        var pickFinish: ((TripNoteAnchor?) -> Void)?
        var pickInitial: TripNoteAnchor??
        lazy var stepAside = TripNoteDetailsStepAside(
            closeDetails: { [self] done in log.append("close"); closeDone = done },
            startPick: { [self] initial, finish in
                log.append("pick"); pickInitial = .some(initial); pickFinish = finish },
            reopenDetails: { [self] done in log.append("reopen"); reopenDone = done })
    }

    private func flow(_ harness: Harness) -> TripNoteFlow {
        let flow = TripNoteFlow()
        flow.pickPlace = { initial, finish in harness.stepAside.pick(initial: initial, finish: finish) }
        return flow
    }

    private var train: Train {
        Train(id: "t", date: "2026-10-12", number: "1", origin: "東京", destination: "新大阪",
              stops: [Stop(name: "東京", departure: "9:05", stopType: "origin"),
                      Stop(name: "新大阪", arrival: "12:55", stopType: "destination")],
              region: "jp")
    }

    @Test func addClosesDetailsThenPicksThenReopensThenOpensTheForm() {
        let harness = Harness()
        let flow = flow(harness)
        flow.beginAdd(train: train)
        #expect(harness.log == ["close"])
        #expect(flow.screen == nil)
        harness.closeDone?()
        #expect(harness.log == ["close", "pick"])
        harness.pickFinish?(anchor)
        #expect(harness.log == ["close", "pick", "reopen"])
        #expect(flow.screen == nil, "The form waits for the details sheet to be back.")
        harness.reopenDone?()
        #expect(flow.screen == .form)
        #expect(flow.draft?.anchor == anchor)
        #expect(flow.draft?.isNew == true)
        #expect(!harness.stepAside.isActive)
    }

    @Test func cancelBringsDetailsBackWithNoForm() {
        let harness = Harness()
        let flow = flow(harness)
        flow.beginAdd(train: train)
        harness.closeDone?()
        harness.pickFinish?(nil)
        #expect(harness.log == ["close", "pick", "reopen"])
        harness.reopenDone?()
        #expect(flow.screen == nil)
        #expect(flow.draft == nil)
        #expect(!harness.stepAside.isActive)
    }

    @Test func changePlaceKeepsTheDraftAcrossTheStepAside() {
        let harness = Harness()
        let flow = flow(harness)
        let other = TripNoteAnchor.station(TripNoteStation(name: "新大阪"), fallback: nil)
        flow.beginEdit(TripNote(id: "n", category: "Incident", text: "stopped", time: "10:30",
                                anchor: anchor), train: train)
        flow.draft?.text = "stopped at signal"
        flow.changePlaceOnMap()
        #expect(flow.screen == nil)
        harness.closeDone?()
        #expect(harness.pickInitial == .some(.some(anchor)))
        harness.pickFinish?(other)
        harness.reopenDone?()
        #expect(flow.screen == .form)
        #expect(flow.draft?.text == "stopped at signal")
        #expect(flow.draft?.anchor == other)
        #expect(flow.isEdited)
    }

    @Test func cancelOnChangePlaceReturnsToTheFormWithTheOldPlace() {
        let harness = Harness()
        let flow = flow(harness)
        flow.beginEdit(TripNote(id: "n", category: "", text: "x", time: nil, anchor: anchor),
                       train: train)
        flow.draft?.text = "edited"
        flow.changePlaceOnMap()
        harness.closeDone?()
        harness.pickFinish?(nil)
        harness.reopenDone?()
        #expect(flow.screen == .form)
        #expect(flow.draft?.text == "edited")
        #expect(flow.draft?.anchor == anchor)
    }

    @Test func anAbandonedStepThatNeverAnsweredDoesNotBlockTheNextPick() {
        let harness = Harness()
        var oldHeard = 0
        harness.stepAside.pick(initial: nil) { _ in oldHeard += 1 }
        let staleClose = harness.closeDone   // the close step never fires
        #expect(harness.stepAside.isActive)
        harness.stepAside.abandon()
        #expect(!harness.stepAside.isActive)
        staleClose?()                         // a late answer of the dead run
        #expect(harness.log == ["close"], "A dead run starts nothing.")
        var heard = 0
        harness.stepAside.pick(initial: nil) { _ in heard += 1 }
        #expect(harness.log == ["close", "close"])
        harness.closeDone?()
        harness.pickFinish?(nil)
        harness.reopenDone?()
        #expect(heard == 1 && oldHeard == 0)
        #expect(!harness.stepAside.isActive)
    }

    @Test func abandoningDuringThePickSkipsTheReopen() {
        let harness = Harness()
        harness.stepAside.pick(initial: nil) { _ in }
        harness.closeDone?()
        harness.stepAside.abandon()
        harness.pickFinish?(nil)   // the menu's cancel answers nil afterwards
        #expect(harness.log == ["close", "pick"], "No reopen on a leaving menu.")
    }

    @Test func aSecondRequestWhileOneRunsIsAnsweredNil() {
        let harness = Harness()
        var heard: [TripNoteAnchor?] = []
        harness.stepAside.pick(initial: nil) { _ in }
        harness.stepAside.pick(initial: nil) { heard.append($0) }
        #expect(heard.count == 1 && heard[0] == nil)
        #expect(harness.log == ["close"])
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
