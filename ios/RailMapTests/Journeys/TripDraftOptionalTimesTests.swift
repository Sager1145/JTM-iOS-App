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
}
