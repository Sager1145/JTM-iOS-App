import Foundation
import RailCore
import RailPresentation
import Testing
@testable import RailMap

/// Only the date is required. Each scheduled and actual clock is optional on
/// its own, and a clock nobody set is never written as a placeholder.
@MainActor
struct TripDraftOptionalTimesTests {
    private func newDraft() -> TripDraftModel {
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.region = "jp"
        train.stops = []
        return TripDraftModel(train: train, isNew: true)
    }

    private func at(_ time: String, day: String = "2026-11-06", _ model: TripDraftModel) -> Date {
        model.timetableDate(day, time: time)!
    }

    private func twoStops(date: String = "2026-11-06") -> Train {
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.region = "jp"
        train.date = date
        train.stops = [
            Stop(name: "品川", stopType: "origin"),
            Stop(name: "大崎", stopType: "destination"),
        ]
        return train
    }

    private func tokyoNoon() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!
    }

    @Test func aDateOnlyTripWritesNoClockAndIsFiledByDate() {
        let model = newDraft()
        var train = twoStops()
        model.writeHeaderClocks(into: &train, departureIndex: 0, arrivalIndex: 1)
        #expect(train.stops[0].departure == nil)
        #expect(train.stops[1].arrival == nil)
        model.fileByDateIfUntimed(&train)
        #expect(train.listByDate == true)
        #expect(model.timesAllowSave)
    }

    @Test func scheduledTimesAreWrittenWhenBothAreSet() {
        let model = newDraft()
        model.apply(TripDraftModel.Patch(departure: at("10:30", model), arrival: at("12:55", model)), source: .reader)
        var train = twoStops()
        model.writeHeaderClocks(into: &train, departureIndex: 0, arrivalIndex: 1)
        #expect(train.stops[0].departure == "10:30")
        #expect(train.stops[1].arrival == "12:55")
        model.fileByDateIfUntimed(&train)
        #expect(train.listByDate == nil)
    }

    @Test func anActualOnlyTripWritesNoScheduledClockAndIsFiledByTheActualOne() {
        let model = newDraft()
        model.actualTimeText(isDeparture: true).wrappedValue = "10:07"
        var train = twoStops()
        model.writeHeaderClocks(into: &train, departureIndex: 0, arrivalIndex: 1)
        model.applyActualTimes(to: &train)
        #expect(train.stops[0].departure == nil)
        #expect(train.stops[1].arrival == nil)
        #expect(train.stops[0].actualDeparture == "10:07")
        #expect(train.stops[1].actualArrival == nil)
        let clock = Region.jp.clock
        #expect(TripListRules.initialMembership(for: train, clock: clock, now: tokyoNoon()) == .past)
        #expect(TripListRules.initialMembership(for: twoStops(), clock: clock, now: tokyoNoon()) == .upcoming)
    }

    @Test func aScheduledDepartureWithAnActualArrivalWritesOnlyTheDeparture() {
        let model = newDraft()
        model.apply(TripDraftModel.Patch(departure: at("10:30", model)), source: .reader)
        model.actualTimeText(isDeparture: false).wrappedValue = "12:58"
        var train = twoStops()
        model.writeHeaderClocks(into: &train, departureIndex: 0, arrivalIndex: 1)
        model.applyActualTimes(to: &train)
        #expect(train.stops[0].departure == "10:30")
        #expect(train.stops[1].arrival == nil)
        #expect(train.stops[0].actualDeparture == nil)
        #expect(train.stops[1].actualArrival == "12:58")
    }

    @Test func anUntouchedArrivalNeverBlocksSaveButTwoSetTimesInTheWrongOrderDo() {
        let model = newDraft()
        model.apply(TripDraftModel.Patch(departure: at("23:00", day: "2099-01-01", model)), source: .reader)
        #expect(model.arrival < model.departure, "The arrival is still the placeholder, before the set departure.")
        #expect(!model.scheduledTimesConflict)
        #expect(model.timesAllowSave)
        model.apply(TripDraftModel.Patch(arrival: at("22:00", day: "2099-01-01", model)), source: .reader)
        #expect(model.scheduledTimesConflict)
        #expect(!model.timesAllowSave)
        model.apply(TripDraftModel.Patch(arrival: at("23:30", day: "2099-01-01", model)), source: .reader)
        #expect(!model.scheduledTimesConflict)
        #expect(model.timesAllowSave)
    }

    @Test func anActualArrivalBeforeTheActualDepartureBlocksSaveButAnOvernightOneDoesNot() {
        let model = newDraft()
        model.actualTimeText(isDeparture: true).wrappedValue = "10:30"
        model.actualTimeText(isDeparture: false).wrappedValue = "10:10"
        #expect(model.actualTimesConflict)
        #expect(!model.timesAllowSave)

        let overnight = newDraft()
        overnight.actualTimeText(isDeparture: true).wrappedValue = "23:55"
        overnight.actualTimeText(isDeparture: false).wrappedValue = "0:10"
        #expect(overnight.normalizedActual(overnight.actualArrival, isDeparture: false) == "24:10")
        #expect(!overnight.actualTimesConflict)
        #expect(overnight.timesAllowSave)
    }

    @Test func aNewTripsPlaceholderIsNowOnTheRegionsWallClock() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(newYork.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 18, minute: 10)))
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.region = "jp"
        train.stops = []
        let model = newDraft()
        withPhoneTimeZone("America/New_York") {
            let seed = EditorSeed(train: train, isNew: true, clock: Region.jp.clock, now: now)
            #expect(model.dayString(seed.departure) == "2026-11-08")
            #expect(model.clock(seed.departure, extraDays: 0) == "08:10")
            #expect(!seed.departureKnown && !seed.arrivalKnown)
        }
    }

    @Test func theTimetableQueryCarriesAKnownSavedTripsClocks() {
        var train = twoStops()
        train.stops[0].departure = "10:30"
        train.stops[1].arrival = "12:55"
        let model = TripDraftModel(train: train, isNew: false)
        // The query's stops come from the catalog stations; its clocks from this rule.
        var query = twoStops()
        model.writeHeaderClocks(into: &query, departureIndex: 0, arrivalIndex: 1, includingKnown: true)
        #expect(query.stops[0].departure == "10:30")
        #expect(query.stops[1].arrival == "12:55")
        // Saving still writes only what the reader set.
        var saved = twoStops()
        model.writeHeaderClocks(into: &saved, departureIndex: 0, arrivalIndex: 1)
        #expect(saved.stops[0].departure == nil)
    }

    /// What `applyTimetableTrip` leaves behind: the header as it was, the
    /// timetable's own clocks, nothing marked touched.
    private func applyTimetable(
        _ model: TripDraftModel, departure: String, arrival: String, date: String = "2026-11-06"
    ) {
        model.headerBeforeTimetable = TripDraftModel.HeaderSnapshot(
            trainType: model.trainType, departure: model.departure, arrival: model.arrival,
            previousDeparture: model.previousDeparture, touched: model.touched, filledBy: model.filledBy)
        var train = twoStops(date: date)
        train.stops[0].departure = departure
        train.stops[1].arrival = arrival
        model.timetableTrain = train
        model.apply(
            TripDraftModel.Patch(
                departure: at(departure, day: date, model), arrival: at(arrival, day: date, model)),
            source: .timetable)
        model.filledBy[.departure] = .timetable
        model.filledBy[.arrival] = .timetable
    }

    @Test func droppingATimetableRestoresTheReadersHeaderTimes() {
        let model = newDraft()
        model.apply(
            TripDraftModel.Patch(departure: at("10:00", model), arrival: at("11:00", model)), source: .reader)
        applyTimetable(model, departure: "12:30", arrival: "13:40")
        #expect(model.scheduledClock(isDeparture: true) == "12:30")
        model.clearTimetable()
        #expect(model.scheduledClock(isDeparture: true) == "10:00")
        #expect(model.scheduledClock(isDeparture: false) == "11:00")
        #expect(model.timeIsSet(.departure) && model.timeIsSet(.arrival))
        var train = twoStops()
        model.writeHeaderClocks(into: &train, departureIndex: 0, arrivalIndex: 1)
        #expect(train.stops[0].departure == "10:00")
        #expect(train.stops[1].arrival == "11:00")
    }

    @Test func droppingATimetableOnANewTripWithUntouchedTimesWritesDateOnly() {
        let model = newDraft()
        applyTimetable(model, departure: "12:30", arrival: "13:40")
        model.clearTimetable()
        #expect(!model.timeIsSet(.departure) && !model.timeIsSet(.arrival))
        var train = twoStops()
        model.writeHeaderClocks(into: &train, departureIndex: 0, arrivalIndex: 1)
        #expect(train.stops[0].departure == nil)
        #expect(train.stops[1].arrival == nil)
    }

    @Test func aClockTheReaderSetWhileATimetableWasAppliedSurvivesDroppingIt() {
        let model = newDraft()
        applyTimetable(model, departure: "12:30", arrival: "13:40")
        model.apply(TripDraftModel.Patch(arrival: at("14:00", model)), source: .reader)
        model.clearTimetable()
        #expect(model.scheduledClock(isDeparture: false) == "14:00")
        #expect(model.timeIsSet(.arrival))
        #expect(!model.timeIsSet(.departure))
    }

    @Test func aSavedTripWithALateNightTimetableKeepsItsServiceDay() {
        let model = TripDraftModel(train: twoStops(date: "2026-11-01"), isNew: false)
        applyTimetable(model, departure: "24:10", arrival: "25:00", date: "2026-11-01")
        #expect(model.headerServiceDate() == "2026-11-01")
        #expect(model.scheduledClock(isDeparture: true) == "24:10")
    }

    @Test func aRegionChangeReseedsAnUnsetPlaceholderToTheNewRegionsClock() {
        let model = newDraft()
        let old = model.region
        model.region = .tw
        model.regionChanged(from: old)
        // The placeholder is now itself, a real instant shown in the new zone.
        #expect(abs(model.departure.timeIntervalSinceNow) < 120)
        #expect(model.arrival == model.departure)
        #expect(model.previousDeparture == model.departure)

        // A time the reader set keeps its wall clock in the new region.
        let set = newDraft()
        set.apply(TripDraftModel.Patch(departure: at("10:30", set)), source: .reader)
        let before = set.region
        set.region = .tw
        set.regionChanged(from: before)
        #expect(set.dayString(set.departure) == "2026-11-06")
        #expect(set.clock(set.departure, extraDays: 0) == "10:30")
        #expect(set.previousDeparture == set.departure)
    }

    @Test func aRegionChangeReseedsEachSideIndependently() {
        let arrivalOnly = newDraft()
        arrivalOnly.apply(TripDraftModel.Patch(arrival: at("10:30", arrivalOnly)), source: .reader)
        let old = arrivalOnly.region
        arrivalOnly.region = .tw
        arrivalOnly.regionChanged(from: old)
        #expect(arrivalOnly.clock(arrivalOnly.arrival, extraDays: 0) == "10:30")
        #expect(abs(arrivalOnly.departure.timeIntervalSinceNow) < 120)
        #expect(arrivalOnly.previousDeparture == arrivalOnly.departure)

        let departureOnly = newDraft()
        departureOnly.apply(TripDraftModel.Patch(departure: at("10:30", departureOnly)), source: .reader)
        let before = departureOnly.region
        departureOnly.region = .tw
        departureOnly.regionChanged(from: before)
        #expect(departureOnly.clock(departureOnly.departure, extraDays: 0) == "10:30")
        #expect(departureOnly.previousDeparture == departureOnly.departure)
        #expect(abs(departureOnly.arrival.timeIntervalSinceNow) < 120)
    }

    // MARK: - date only, each clock optional

    private func savedTrip(departure: String? = nil, arrival: String? = nil, date: String = "2026-11-06") -> Train {
        var train = twoStops(date: date)
        train.stops[0].departure = departure
        train.stops[1].arrival = arrival
        return train
    }

    private func saved(_ model: TripDraftModel, _ train: Train) -> Train {
        var result = train
        model.applyHeader(to: &result)
        return result
    }

    private func nozomiTicket() -> TicketReadingResult {
        TicketParser.parse(lines: [
            "東京 → 新大阪", "乗車券・新幹線特急券(指定席)", "のぞみ 25号", "2026年11月6日(金)",
            "10:30発 12:55着",
        ].map { RecognizedLine(text: $0, confidence: 0.9) }, region: .jp)
    }

    @Test func aDateOnlyChangeRecordsTheDayNotTheClock() {
        let model = newDraft()
        model.setDay(at("00:00", day: "2027-03-04", model), isDeparture: true)
        model.departureChanged(to: model.departure)
        #expect(model.dayString(model.departure) == "2027-03-04")
        #expect(model.touched.contains(.date))
        #expect(!model.touched.contains(.departure) && !model.touched.contains(.arrival))
        #expect(model.dayIsSet && !model.headerTimeIsSet)
        #expect(model.scheduledClock(isDeparture: true) == nil)
        var train = twoStops()
        model.writeHeaderClocks(into: &train, departureIndex: 0, arrivalIndex: 1)
        #expect(train.stops[0].departure == nil && train.stops[1].arrival == nil)
        model.fileByDateIfUntimed(&train)
        #expect(train.listByDate == true)
    }

    @Test func anArrivalDateOnlyRecordsArrivalDate() {
        let model = newDraft()
        model.setDay(at("00:00", day: "2027-03-05", model), isDeparture: false)
        #expect(model.dayString(model.arrival) == "2027-03-05")
        #expect(model.touched.contains(.arrivalDate))
        #expect(!model.touched.contains(.arrival) && !model.touched.contains(.date))
        #expect(!model.timeIsSet(.arrival) && !model.dayIsSet)
        var train = twoStops()
        model.writeHeaderClocks(into: &train, departureIndex: 0, arrivalIndex: 1)
        #expect(train.stops[1].arrival == nil)
    }

    @Test func aKnownSavedClockKeepsItsTimeWhenOnlyTheDateMoves() {
        let train = savedTrip(departure: "10:30", arrival: "12:55")
        let model = TripDraftModel(train: train, isNew: false)
        model.setDay(at("00:00", day: "2026-11-08", model), isDeparture: true)
        model.departureChanged(to: model.departure)
        let result = saved(model, train)
        #expect(result.date == "2026-11-08")
        #expect(result.stops[0].departure == "10:30")
        #expect(result.stops[1].arrival == "12:55")
        #expect(!model.touched.contains(.departure))

        // "24:30" is the next civil day's 0:30: the field shows that civil day,
        // and moving it keeps the clock past midnight.
        let late = savedTrip(departure: "24:30", arrival: "25:10")
        let lateModel = TripDraftModel(train: late, isNew: false)
        lateModel.setDay(at("00:00", day: "2026-11-09", lateModel), isDeparture: true)
        lateModel.departureChanged(to: lateModel.departure)
        let lateResult = saved(lateModel, late)
        #expect(lateResult.date == "2026-11-08")
        #expect(lateResult.stops[0].departure == "24:30")
        #expect(lateResult.stops[1].arrival == "25:10")
    }

    @Test func anUntouchedSavedClockIsWrittenBackVerbatimWhenOnlyTheDateMoves() {
        for (stored, arrivalStored) in [("10:30:15", "12:55:30"), ("10:00+1", "11:00+1"), ("24:30", "25:10")] {
            let train = savedTrip(departure: stored, arrival: arrivalStored)
            let model = TripDraftModel(train: train, isNew: false)
            model.setDay(at("00:00", day: "2026-11-08", model), isDeparture: true)
            model.departureChanged(to: model.departure)
            let result = saved(model, train)
            #expect(result.stops[0].departure == stored)
            #expect(result.stops[1].arrival == arrivalStored)
            #expect(result.date != train.date)
        }
    }

    /// The arrival branch: the reader also touched the arrival's date, moving
    /// it by the same days as the departure, so its stored text stays as is.
    @Test func anUntouchedArrivalWhoseDateWasTouchedIsWrittenBackVerbatim() {
        for (stored, arrivalStored) in [("10:30:15", "12:55:30"), ("10:00+1", "11:00+1"), ("24:30", "25:10")] {
            let train = savedTrip(departure: stored, arrival: arrivalStored)
            let model = TripDraftModel(train: train, isNew: false)
            model.setDay(at("00:00", day: "2026-11-08", model), isDeparture: true)
            model.departureChanged(to: model.departure)
            model.setDay(model.arrival, isDeparture: false)
            #expect(model.touched.contains(.arrivalDate))
            let result = saved(model, train)
            #expect(result.stops[0].departure == stored)
            #expect(result.stops[1].arrival == arrivalStored, "\(result.stops[1].arrival ?? "nil")")
        }
    }

    @Test func typingANewClockStillWritesTheCanonicalClock() {
        let train = savedTrip(departure: "10:30:15", arrival: "11:00")
        let model = TripDraftModel(train: train, isNew: false)
        model.apply(TripDraftModel.Patch(departure: at("10:35", model)), source: .reader)
        model.departureChanged(to: model.departure)
        #expect(saved(model, train).stops[0].departure == "10:35")
    }

    @Test func secondsInASavedClockDoNotSkewTheArrivalShift() {
        let train = savedTrip(departure: "10:30:15", arrival: "11:00")
        let model = TripDraftModel(train: train, isNew: false)
        model.apply(TripDraftModel.Patch(departure: at("10:35", model)), source: .reader)
        model.departureChanged(to: model.departure)
        #expect(model.scheduledClock(isDeparture: false) == "11:05")
    }

    @Test func aClocklessSavedTripsDateMoveWritesNoClock() {
        let train = savedTrip()
        let model = TripDraftModel(train: train, isNew: false)
        model.setDay(at("00:00", day: "2026-11-09", model), isDeparture: true)
        model.departureChanged(to: model.departure)
        let result = saved(model, train)
        #expect(result.date == "2026-11-09")
        #expect(result.stops[0].departure == nil && result.stops[1].arrival == nil)
    }

    @Test func midnightOnAnUnreadableRecordApplies() {
        let train = savedTrip()
        let model = TripDraftModel(train: train, isNew: false)
        model.setClock(at("00:00", model), isDeparture: true)
        #expect(model.timeIsSet(.departure))
        #expect(saved(model, train).stops[0].departure == "00:00")
        let fresh = newDraft()
        fresh.setClock(at("00:00", fresh), isDeparture: true)
        var written = twoStops()
        fresh.writeHeaderClocks(into: &written, departureIndex: 0, arrivalIndex: 1)
        #expect(written.stops[0].departure == "00:00")
    }

    @Test func clearingAReaderOrTicketClockMakesItUnset() {
        let reader = newDraft()
        reader.setClock(at("10:30", reader), isDeparture: true)
        reader.setClock(at("12:55", reader), isDeparture: false)
        reader.clearTime(isDeparture: true)
        #expect(reader.scheduledClock(isDeparture: true) == nil)
        #expect(reader.scheduledClock(isDeparture: false) == "12:55")
        reader.applyActualChip(minutes: 5, isDeparture: true)
        #expect(reader.actualDeparture == nil)
        #expect(reader.dayIsSet && reader.touched.contains(.date), "The cleared clock's day still counts.")
        var train = twoStops()
        reader.writeHeaderClocks(into: &train, departureIndex: 0, arrivalIndex: 1)
        #expect(train.stops[0].departure == nil)
        #expect(train.stops[1].arrival == "12:55")

        let ticket = newDraft()
        ticket.fillFromTicket(nozomiTicket(), now: Date())
        #expect(ticket.filledBy[.departure] == .ticket)
        ticket.clearTime(isDeparture: true)
        #expect(ticket.scheduledClock(isDeparture: true) == nil)
        #expect(ticket.filledBy[.date] == .ticket && ticket.dayIsSet)
        ticket.applyActualChip(minutes: 0, isDeparture: true)
        #expect(ticket.actualDeparture == nil)

        let known = savedTrip(departure: "10:30", arrival: "12:55")
        let model = TripDraftModel(train: known, isNew: false)
        model.clearTime(isDeparture: true)
        model.clearTime(isDeparture: false)
        #expect(model.isDirty(original: known))
        let result = saved(model, known)
        #expect(result.stops[0].departure == nil && result.stops[1].arrival == nil)
        #expect(result.date == "2026-11-06")

        let typed = TripDraftModel(train: known, isNew: false)
        typed.setClock(at("11:00", typed), isDeparture: true)
        typed.clearTime(isDeparture: true)
        #expect(saved(typed, known).stops[0].departure == nil)
        #expect(typed.dayIsSet)
    }

    @Test func aClearSurvivesDroppingATimetable() {
        let model = newDraft()
        model.setClock(at("10:00", model), isDeparture: true)
        applyTimetable(model, departure: "12:30", arrival: "13:40")
        model.clearTime(isDeparture: true)
        #expect(model.scheduledClock(isDeparture: true) == nil)
        var result = model.timetableResult(model.timetableTrain!, original: twoStops())
        #expect(result.stops[0].departure == nil, "The timetable stays; the cleared side writes no clock.")
        #expect(result.stops[1].arrival == "13:40")
        model.clearTimetable()
        #expect(model.clearedClocks.contains(.departure))
        #expect(model.scheduledClock(isDeparture: true) == nil)
        result = twoStops()
        model.writeHeaderClocks(into: &result, departureIndex: 0, arrivalIndex: 1)
        #expect(result.stops[0].departure == nil)
    }

    @Test func aManualTimetableClearsTheClearMark() {
        let model = newDraft()
        model.setClock(at("10:00", model), isDeparture: true)
        model.clearTime(isDeparture: true)
        #expect(model.clearedClocks.contains(.departure))
        var timetable = twoStops()
        timetable.stops[0].departure = "12:30"
        timetable.stops[1].arrival = "13:40"
        #expect(model.acceptTimetable(timetable))
        #expect(!model.clearedClocks.contains(.departure))
        #expect(model.scheduledClock(isDeparture: true) == "12:30")
        model.clearTimetable()
        #expect(model.clearedClocks.contains(.departure), "Dropping the timetable puts the reader's clear back.")
        #expect(model.scheduledClock(isDeparture: true) == nil)
    }

    @Test func riddenNeverReadsThePlaceholder() {
        let past = newDraft()
        past.setDay(at("00:00", day: "2020-01-01", past), isDeparture: true)
        #expect(!past.headerTimeIsSet)
        #expect(past.isRidden)
        let future = newDraft()
        future.setDay(at("00:00", day: "2099-01-01", future), isDeparture: true)
        #expect(!future.isRidden)
    }

    @Test func aTimetableWithoutAnEndpointClockIsNotScheduled() {
        let model = newDraft()
        model.timetableTrain = twoStops()
        model.timetableRideSpan = 0...1
        #expect(!model.scheduledIsSet(isDeparture: true) && !model.scheduledIsSet(isDeparture: false))
        #expect(!model.headerTimeIsSet)
        var arrivalOnly = twoStops()
        arrivalOnly.stops[1].arrival = "12:00"
        model.timetableTrain = arrivalOnly
        #expect(!model.scheduledIsSet(isDeparture: true) && model.scheduledIsSet(isDeparture: false))
        #expect(model.scheduledClock(isDeparture: true) == nil)
    }

    @Test func aTicketKeepsTheReadersDay() {
        let model = newDraft()
        model.setDay(at("00:00", day: "2026-11-08", model), isDeparture: true)
        model.fillFromTicket(nozomiTicket(), now: Date())
        #expect(model.dayString(model.departure) == "2026-11-08")
        #expect(model.clock(model.departure, extraDays: 0) == "10:30")
        #expect(model.dayString(model.arrival) == "2026-11-08")

        let cleared = newDraft()
        cleared.setClock(at("08:00", cleared), isDeparture: true)
        cleared.clearTime(isDeparture: true)
        cleared.fillFromTicket(nozomiTicket(), now: Date())
        #expect(cleared.scheduledClock(isDeparture: true) == nil, "A ticket does not refill a clock the reader emptied.")
        #expect(cleared.filledBy[.departure] == nil)
    }

    @Test func aRegionChangeKeepsAReaderSetDay() {
        let model = newDraft()
        model.setDay(at("00:00", day: "2027-03-04", model), isDeparture: true)
        model.setDay(at("00:00", day: "2027-03-05", model), isDeparture: false)
        let old = model.region
        model.region = .tw
        model.regionChanged(from: old)
        #expect(model.dayString(model.departure) == "2027-03-04")
        #expect(model.dayString(model.arrival) == "2027-03-05")
        #expect(!model.headerTimeIsSet)

        let untouched = newDraft()
        untouched.setDay(at("00:00", day: "2027-03-04", untouched), isDeparture: true)
        untouched.region = .tw
        untouched.regionChanged(from: .jp)
        #expect(abs(untouched.arrival.timeIntervalSinceNow) < 120, "An arrival day nobody set starts over.")
    }

    @Test func aTouchedBigOffsetClockIsStoredInAFormEveryReaderParses() {
        // Four days after the service day at 05:30 is past hour 99: stored as `H:MM+N`.
        let train = savedTrip(departure: "05:00", arrival: "05:30")
        let model = TripDraftModel(train: train, isNew: false)
        model.setClock(at("05:30", day: "2026-11-10", model), isDeparture: false)
        let stored = saved(model, train).stops[1].arrival
        #expect(stored == "5:30+4")
        if case .valid(_, let time) = EditorTime.parseTime(stored) {
            #expect(time.dayOffset == 4 && time.hour == 5 && time.minute == 30)
        } else {
            Issue.record("EditorTime cannot read \(stored ?? "nil")")
        }
        #expect(Dates.parseTimeToMinutes(stored) == Double(4 * 1440 + 330))
    }
}

// MARK: - day moves and day-only edits

extension TripDraftOptionalTimesTests {
    /// A typed arrival follows a day move by whole days and keeps its clock,
    /// forward or back; it is never clamped onto the placeholder departure,
    /// and the saved arrival stays on the departure's day.
    @Test func aDayMoveWithABlankDepartureMovesATypedArrivalByWholeDays() {
        for day in ["2026-11-07", "2026-11-08", "2027-03-04", "2026-11-03", "2026-10-06"] {
            let model = newDraft()
            // A new draft opens on today: put both ends on 2026-11-06 first.
            model.setDay(at("00:00", model), isDeparture: true)
            model.departureChanged(to: model.departure)
            model.apply(TripDraftModel.Patch(arrival: at("10:00", model)), source: .reader)
            #expect(model.dayString(model.departure) == "2026-11-06")
            model.setDay(at("00:00", day: day, model), isDeparture: true)
            model.departureChanged(to: model.departure)
            #expect(model.dayString(model.arrival) == day, "\(day)")
            #expect(model.scheduledClock(isDeparture: false) == "10:00", "\(day)")
            #expect(model.timeIsSet(.arrival) && !model.timeIsSet(.departure))
            let train = saved(model, savedTrip(date: "2026-11-06"))
            #expect(train.date == day)
            #expect(train.stops[0].departure == nil)
            #expect(train.stops[1].arrival == "10:00", "\(day): \(train.stops[1].arrival ?? "nil")")
        }
    }

    @Test func aDayMoveWithASetDepartureStillFollowsAndClamps() {
        let model = newDraft()
        model.apply(
            TripDraftModel.Patch(departure: at("10:00", model), arrival: at("11:00", model)), source: .reader)
        model.previousDeparture = model.departure
        model.setDay(at("00:00", day: "2026-11-08", model), isDeparture: true)
        model.departureChanged(to: model.departure)
        #expect(model.scheduledClock(isDeparture: true) == "10:00")
        #expect(model.scheduledClock(isDeparture: false) == "11:00")
        #expect(model.dayString(model.arrival) == "2026-11-08")
    }

    @Test func aDayOnlyEditMadeWhileATimetableWasAppliedSurvivesRemove() {
        let model = newDraft()
        applyTimetable(model, departure: "12:30", arrival: "13:40")
        model.touched.insert(.date)
        model.departure = at("12:30", day: "2027-01-02", model)
        model.clearTimetable()
        #expect(model.dayString(model.departure) == "2027-01-02")
        #expect(model.touched.contains(.date))
    }

    @Test func anArrivalDayOnlyEditSurvivesRemoveToo() {
        let model = newDraft()
        applyTimetable(model, departure: "12:30", arrival: "13:40")
        model.touched.insert(.arrivalDate)
        model.arrival = at("13:40", day: "2027-01-03", model)
        model.clearTimetable()
        #expect(model.dayString(model.arrival) == "2027-01-03")
    }
}
