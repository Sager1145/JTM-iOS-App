import Foundation
import RailCore
import Testing
@testable import RailMap

/// The actual-time chips: scheduled clock plus N minutes, on clock text only,
/// and never over a clock the reader typed.
@MainActor
struct TripDraftActualTimesTests {
    private func draft(departure: String = "10:30", arrival: String = "12:55") -> TripDraftModel {
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.region = "jp"
        train.stops = []
        let model = TripDraftModel(train: train, isNew: true)
        let start = model.timetableDate("2026-11-06", time: departure)
        let end = model.timetableDate("2026-11-06", time: arrival)
        model.apply(TripDraftModel.Patch(departure: start, arrival: end), source: .reader)
        return model
    }

    private func type(_ text: String, isDeparture: Bool, into model: TripDraftModel) {
        model.actualTimeText(isDeparture: isDeparture).wrappedValue = text
    }

    @Test func plusFiveStoresTheClockAndReadsLate() {
        let model = draft()
        #expect(model.headerTimeIsSet)
        model.applyActualChip(minutes: 5, isDeparture: true)
        #expect(model.actualDeparture == "10:35")
        #expect(model.normalizedActual(model.actualDeparture, isDeparture: true) == "10:35")
        #expect(model.touched.contains(.actualDeparture))
        let label = StopTimingStatus.localizedLabel(
            scheduled: model.scheduledClock(isDeparture: true), actual: "10:35", localization: AppLocalization())
        #expect(label?.contains("5") == true)
        #expect(label != StopTimingStatus.localizedLabel(
            scheduled: "10:30", actual: "10:30", localization: AppLocalization()))
    }

    @Test func rollsPastMidnightAndOnTimeIsTheScheduledClock() {
        let model = draft(departure: "23:55", arrival: "23:58")
        model.applyActualChip(minutes: 10, isDeparture: true)
        #expect(model.actualDeparture == "24:05")
        model.applyActualChip(minutes: 0, isDeparture: true)
        #expect(model.actualDeparture == "23:55")
    }

    @Test func aChipNeverReplacesATypedClockButReplacesAChipOne() {
        let model = draft()
        type("10:41", isDeparture: true, into: model)
        model.applyActualChip(minutes: 5, isDeparture: true)
        #expect(model.actualDeparture == "10:41")

        model.applyActualChip(minutes: 10, isDeparture: false)
        #expect(model.actualArrival == "13:05")
        model.applyActualChip(minutes: 15, isDeparture: false)
        #expect(model.actualArrival == "13:10")
    }

    @Test func typingAfterAChipMakesItTyped() {
        let model = draft()
        model.applyActualChip(minutes: 5, isDeparture: true)
        type("10:36", isDeparture: true, into: model)
        #expect(model.actualIsTyped(isDeparture: true))
        model.applyActualChip(minutes: 15, isDeparture: true)
        #expect(model.actualDeparture == "10:36")
    }

    @Test func anEarlyArrivalStaysAsTyped() {
        let model = draft()
        type("12:50", isDeparture: false, into: model)
        #expect(model.actualArrival == "12:50")
        #expect(model.normalizedActual("12:50", isDeparture: false) == "12:50")
    }

    @Test func chipValuesDoNotDependOnTheTimeZone() {
        // The chip is the clock text plus minutes: no Calendar or zone is
        // applied on top, so the strings are fixed in every phone zone.
        for id in ["Asia/Tokyo", "America/Los_Angeles", "Pacific/Kiritimati"] {
            withPhoneTimeZone(id) {
                let model = draft(departure: "23:55", arrival: "23:58")
                model.applyActualChip(minutes: 10, isDeparture: true)
                #expect(model.actualDeparture == "24:05", "\(id)")
                model.applyActualChip(minutes: 0, isDeparture: true)
                #expect(model.actualDeparture == "23:55", "\(id)")
            }
        }
    }

    private func savedTrip(departure: String, arrival: String, actual: String? = nil) -> Train {
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.region = "jp"
        train.date = "2026-11-06"
        train.stops = [
            Stop(name: "品川", departure: departure, actualDeparture: actual, stopType: "origin"),
            Stop(name: "大崎", arrival: arrival, stopType: "destination"),
        ]
        return train
    }

    @Test func aStopEditorEditSurvivesSaveAndUntouchedValuesStayByteIdentical() {
        let saved = savedTrip(departure: "09:00", arrival: "09:30", actual: "09:07")
        let model = TripDraftModel(train: saved, isNew: false)

        var untouched = saved
        model.applyActualTimes(to: &untouched)
        #expect(untouched.stops[0].actualDeparture == "09:07")

        var edited = saved
        edited.stops[0].actualDeparture = "9:10"
        model.applyActualTimes(to: &edited)
        #expect(edited.stops[0].actualDeparture == "9:10")

        var raw = saved
        raw.stops[0].actualDeparture = "9:07"
        model.applyActualTimes(to: &raw)
        #expect(raw.stops[0].actualDeparture == "9:07")
    }

    @Test func aChangedHeaderActualIsWritten() {
        let saved = savedTrip(departure: "09:00", arrival: "09:30", actual: "09:07")
        let model = TripDraftModel(train: saved, isNew: false)
        model.actualTimeText(isDeparture: true).wrappedValue = "9:12"
        var result = saved
        model.applyActualTimes(to: &result)
        #expect(result.stops[0].actualDeparture == "9:12")
        model.actualTimeText(isDeparture: true).wrappedValue = ""
        var cleared = saved
        model.applyActualTimes(to: &cleared)
        #expect(cleared.stops[0].actualDeparture == nil)
    }

    @Test func aSavedLateNightRecordKeepsItsServiceClocks() {
        let model = TripDraftModel(train: savedTrip(departure: "24:30", arrival: "25:10"), isNew: false)
        #expect(model.scheduledClock(isDeparture: true) == "24:30")
        #expect(model.scheduledClock(isDeparture: false) == "25:10")
        model.applyActualChip(minutes: 5, isDeparture: true)
        #expect(model.actualDeparture == "24:35")
    }

    @Test func aReplacedRouteGetsTheSavedActualsBack() {
        let saved = savedTrip(departure: "09:00", arrival: "09:30", actual: "10:05")
        let model = TripDraftModel(train: saved, isNew: false)
        var fresh = StoreOperations.createBlankTrain(country: "jp")
        fresh.region = "jp"
        fresh.stops = [
            Stop(name: "品川", departure: "09:00", stopType: "origin"),
            Stop(name: "大崎", arrival: "09:30", stopType: "destination"),
        ]
        model.applyActualTimes(to: &fresh)
        #expect(fresh.stops[0].actualDeparture == "10:05")
        #expect(fresh.stops[1].actualArrival == nil)
    }
}
