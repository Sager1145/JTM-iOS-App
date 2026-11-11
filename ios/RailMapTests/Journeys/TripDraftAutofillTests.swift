import Foundation
import RailCore
import Testing
@testable import RailMap

/// The add-trip editor's one-shot ticket fill: every value the ticket gives
/// lands at once, each tagged with its source, and nothing the reader set is
/// ever written over.
@MainActor
struct TripDraftAutofillTests {
    private func newDraft(region: String = "jp") -> TripDraftModel {
        var train = StoreOperations.createBlankTrain(country: region)
        train.region = region
        train.stops = []
        return TripDraftModel(train: train, isNew: true)
    }

    private func nozomi() -> TicketReadingResult {
        TicketParser.parse(lines: [
            "東京 → 新大阪", "乗車券・新幹線特急券(指定席)", "のぞみ 25号", "2026年11月6日(金)",
            "10:30発 12:55着", "5号車 12番A席", "普通車指定席", "合計 ¥14,720",
        ].map { RecognizedLine(text: $0, confidence: 0.9) }, region: .jp)
    }

    @Test func aScanFillsEveryFieldItCanAtOnce() {
        let model = newDraft()
        let written = model.fillFromTicket(nozomi(), now: Date())
        #expect(written >= 8)
        #expect(model.trainNumber == "のぞみ25号")
        #expect(model.trainType == "highSpeed")
        #expect(model.limitedExpressName == "のぞみ")
        #expect(model.draft.ticket?.seat == "12A")
        #expect(model.draft.ticket?.fare == 14720)
        #expect(model.draft.ticket?.currency == "JPY")
        #expect(model.draft.rollingStock?.riddenCar == 5)
        #expect(model.dayString(model.departure) == "2026-11-06")
        #expect(model.clock(model.departure, extraDays: 0) == "10:30")
        #expect(model.dayString(model.arrival) == "2026-11-06")
        #expect(model.clock(model.arrival, extraDays: 0) == "12:55")
        // The departure's onChange shift must not move the printed arrival.
        model.departureChanged(to: model.departure)
        #expect(model.clock(model.arrival, extraDays: 0) == "12:55")
        for field: TripDraftModel.Field in [.number, .trainType, .seat, .fare, .riddenCar, .departure, .arrival] {
            #expect(model.filledBy[field] == .ticket, "\(field)")
        }
        // A ticket's clock is a real time: the trip is filed by it, not by date alone.
        #expect(model.headerTimeIsSet)
        #expect(model.touched.isEmpty)
        #expect(model.ticketFillCount == written)
    }

    @Test func aFieldTheReaderSetIsNeverOverwritten() {
        let model = newDraft()
        model.readerBinding(.number, get: { model.trainNumber }, set: { model.trainNumber = $0 })
            .wrappedValue = "ひかり 500"
        model.ticketText(.seat, \.seat).wrappedValue = "3D"
        model.apply(TripDraftModel.Patch(trainType: "local"), source: .reader)
        let reader = model.region.clock.calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 8))!
        model.apply(TripDraftModel.Patch(departure: reader), source: .reader)
        // The editor's onChange, so the arrival below is set against this departure.
        model.departureChanged(to: reader)
        let readerArrival = reader.addingTimeInterval(3 * 3600)
        model.apply(TripDraftModel.Patch(arrival: readerArrival), source: .reader)

        model.fillFromTicket(nozomi(), now: Date())
        model.departureChanged(to: model.departure)

        #expect(model.trainNumber == "ひかり 500")
        #expect(model.draft.ticket?.seat == "3D")
        #expect(model.trainType == "local")
        #expect(model.departure == reader)
        #expect(model.arrival == readerArrival)
        for field: TripDraftModel.Field in [.number, .seat, .trainType, .departure, .arrival] {
            #expect(model.filledBy[field] == nil, "\(field)")
            #expect(model.touched.contains(field), "\(field)")
        }
        // Untouched fields still fill.
        #expect(model.draft.ticket?.fare == 14720)
        #expect(model.filledBy[.fare] == .ticket)
    }

    @Test func editingAFilledValueMakesItTheReaders() {
        let model = newDraft()
        model.fillFromTicket(nozomi(), now: Date())
        #expect(model.filledBy[.fare] == .ticket)
        model.fareText.wrappedValue = "15000"
        #expect(model.filledBy[.fare] == nil)
        #expect(model.touched.contains(.fare))
        model.fillFromTicket(nozomi(), now: Date())
        #expect(model.draft.ticket?.fare == 15000)
    }

    @Test func aTaiwanFareIsStoredInWholeDollars() {
        let model = newDraft(region: "tw")
        let reading = TicketParser.parse(lines: [
            "台灣高鐵 THSR", "2026/11/06", "台北 Taipei → 左營 Zuoying", "車次 0123",
            "10:30 → 12:15", "5車 12A", "標準車廂", "NT$1,490",
        ].map { RecognizedLine(text: $0, confidence: 0.9) }, region: .tw)
        model.fillFromTicket(reading, now: Date())
        #expect(model.draft.ticket?.fare == 1490)
        #expect(model.draft.ticket?.currency == "TWD")
        #expect(model.trainNumber == "高鐵 123次")
        #expect(model.trainType == "highSpeed")
    }

    @Test func clearingEveryStockAndTicketValueLeavesNoEmptyRecord() {
        let model = newDraft()
        model.stockText(.livery, \.livery).wrappedValue = "JR東海色"
        model.carNumber(2).wrappedValue = "783-2001"
        #expect(model.draft.rollingStock?.cars == [RollingStock.Car(sequence: 2, number: "783-2001")])
        model.stockText(.livery, \.livery).wrappedValue = ""
        model.carNumber(2).wrappedValue = " "
        #expect(model.draft.rollingStock == nil)
        model.fareText.wrappedValue = "100"
        #expect(model.draft.ticket == Ticket(fare: 100, currency: "JPY"))
        model.fareText.wrappedValue = ""
        #expect(model.draft.ticket == nil)
    }

    @Test func removingATimetableRestoresOnlyTheHeader() {
        let model = newDraft()
        model.headerBeforeTimetable = TripDraftModel.HeaderSnapshot(
            trainType: "", departure: model.departure, arrival: model.arrival,
            previousDeparture: model.departure, touched: [], filledBy: [:])
        model.timetableTrain = model.draft
        model.fareText.wrappedValue = "990"
        model.filledBy[.setNumber] = .timetable
        model.updateStock { $0.setNumber = "X1" }
        model.removeTimetable()
        #expect(model.touched.contains(.fare), "A value typed while the timetable was applied stays the reader's.")
        #expect(model.draft.rollingStock?.setNumber == nil, "The timetable's formation goes with it.")
        model.fillFromTicket(nozomi(), now: Date())
        #expect(model.draft.ticket?.fare == 990)
    }

    @Test func aTicketForAnotherDayReplacesTheAppliedTimetable() {
        let model = newDraft()
        var applied = model.draft
        applied.date = "2026-11-05"
        model.timetableTrain = applied
        model.fillFromTicket(nozomi(), now: Date())
        #expect(model.timetableTrain == nil)
        #expect(model.dayString(model.departure) == "2026-11-06")
    }

    @Test func savedDetailTextIsTrimmed() {
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.rollingStock = RollingStock(setNumber: " X1 ", livery: "  ")
        train.ticket = Ticket(seat: "12 a", seatClass: " グリーン車 ")
        TripDraftModel.trimDetails(&train)
        #expect(train.rollingStock == RollingStock(setNumber: "X1"))
        #expect(train.ticket == Ticket(seat: "12A", seatClass: "グリーン車"))
    }

    @Test func anOvernightArrivalLandsOnTheNextDay() {
        let model = newDraft()
        let reading = TicketParser.parse(lines: [
            "東京 → 出雲市", "サンライズ出雲", "11月6日", "21:50発 9:58着",
        ].map { RecognizedLine(text: $0, confidence: 0.9) }, region: .jp)
        model.fillFromTicket(reading, now: Date())
        #expect(model.clock(model.departure, extraDays: 0) == "21:50")
        #expect(model.clock(model.arrival, extraDays: 0) == "09:58")
        #expect(model.extraDays(from: model.departure, to: model.arrival) == 1)
    }

    /// The recorded strings must not move with the phone's zone. The process
    /// zone is one global, so every zone is looped inside this one test.
    @Test func recordedClocksAreIdenticalInEveryPhoneZone() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let now = try #require(tokyo.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12)))
        let overnight = TicketParser.parse(lines: [
            "東京 → 新大阪", "乗車券・新幹線特急券(指定席)", "のぞみ 25号", "2026年11月6日(金)",
            "23:55発 0:10着",
        ].map { RecognizedLine(text: $0, confidence: 0.9) }, region: .jp)

        func collect() -> [String] {
            var out: [String] = []
            let day = newDraft()
            day.fillFromTicket(nozomi(), now: now)
            day.actualTimeText(isDeparture: true).wrappedValue = "10:35"
            out += [day.dayString(day.departure), day.clock(day.departure, extraDays: 0),
                    day.clock(day.arrival, extraDays: day.extraDays(from: day.departure, to: day.arrival)),
                    day.normalizedActual("10:35", isDeparture: true) ?? "nil"]

            let night = newDraft()
            night.fillFromTicket(overnight, now: now)
            night.actualTimeText(isDeparture: false).wrappedValue = "0:10"
            out += [night.dayString(night.departure), night.clock(night.departure, extraDays: 0),
                    night.clock(night.arrival, extraDays: night.extraDays(from: night.departure, to: night.arrival)),
                    night.normalizedActual("0:10", isDeparture: false) ?? "nil"]

            var train = StoreOperations.createBlankTrain(country: "jp")
            train.stops = [
                Stop(name: "東京", departure: "23:55", stopType: "origin"),
                Stop(name: "新大阪", arrival: "24:10", stopType: "destination"),
            ]
            night.applyActualTimes(to: &train)
            out += [train.stops[1].actualArrival ?? "nil"]
            return out
        }

        let expected = ["2026-11-06", "10:30", "12:55", "10:35",
                        "2026-11-06", "23:55", "24:10", "24:10", "24:10"]
        for zone in ["Asia/Tokyo", "America/Los_Angeles", "Pacific/Kiritimati", "Europe/London"] {
            let actual = withPhoneTimeZone(zone) { collect() }
            #expect(actual == expected, "\(zone): \(actual)")
        }
    }

    // MARK: - actual times

    @Test func actualTimesAreTheReadersAndNoFillWritesThem() {
        let model = newDraft()
        model.actualTimeText(isDeparture: true).wrappedValue = "10:35"
        model.fillFromTicket(nozomi(), now: Date())
        #expect(model.actualDeparture == "10:35")
        #expect(model.actualArrival == nil, "A ticket's arrival is the scheduled one, never the actual one.")
        #expect(model.touched.contains(.actualDeparture))
        #expect(model.filledBy[.actualDeparture] == nil)
        #expect(model.scheduledClock(isDeparture: true) == "10:30")
        #expect(model.normalizedActual(model.actualDeparture, isDeparture: true) == "10:35")
    }

    @Test func anActualClockLongBeforeTheScheduleIsAfterMidnight() {
        let model = newDraft()
        let late = model.region.clock.calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 23, minute: 55))!
        model.apply(TripDraftModel.Patch(departure: late, arrival: late), source: .reader)
        #expect(model.normalizedActual("0:10", isDeparture: false) == "24:10")
        #expect(model.normalizedActual("23:50", isDeparture: false) == "23:50")
        #expect(model.normalizedActual("25:x", isDeparture: false) == nil)
    }

    @Test func savingWritesActualTimesOnTheBoardingAndAlightingStops() {
        let model = newDraft()
        model.actualTimeText(isDeparture: true).wrappedValue = " 9:07"
        model.actualTimeText(isDeparture: false).wrappedValue = "12:58"
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.stops = [
            Stop(name: "前", departure: "9:00", stopType: "passenger_stop"),
            Stop(name: "東京", departure: "9:05", stopType: "origin"),
            Stop(name: "新大阪", arrival: "12:55", stopType: "destination"),
            Stop(name: "後", arrival: "13:30", stopType: "passenger_stop"),
        ]
        model.applyActualTimes(to: &train)
        #expect(train.stops[1].actualDeparture == "9:07")
        #expect(train.stops[2].actualArrival == "12:58")
        #expect(train.stops[0].actualDeparture == nil && train.stops[3].actualArrival == nil)
        // Clearing them removes the fields; a record without them stays without them.
        model.actualTimeText(isDeparture: true).wrappedValue = ""
        model.actualTimeText(isDeparture: false).wrappedValue = ""
        for index in train.stops.indices {
            train.stops[index].actualDeparture = nil
            train.stops[index].actualArrival = nil
        }
        model.applyActualTimes(to: &train)
        #expect(train.stops.allSatisfy { $0.actualDeparture == nil && $0.actualArrival == nil })
    }

    @Test func aSavedTripOpensWithItsActualTimes() {
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.region = "jp"
        train.stops = [
            Stop(name: "東京", departure: "9:05", actualDeparture: "9:07", stopType: "origin"),
            Stop(name: "新大阪", arrival: "12:55", actualArrival: "13:01", stopType: "destination"),
        ]
        let model = TripDraftModel(train: train, isNew: false)
        #expect(model.actualDeparture == "9:07")
        #expect(model.actualArrival == "13:01")
        #expect(model.showsActualTimes)
        #expect(!model.isDirty(original: train))
        model.actualTimeText(isDeparture: false).wrappedValue = "13:05"
        #expect(model.isDirty(original: train))
    }

    private func reading(_ lines: [String]) -> TicketReadingResult {
        TicketParser.parse(lines: lines.map { RecognizedLine(text: $0, confidence: 0.9) }, region: .jp)
    }

    @Test func anArrivalOnlyTicketLandsOnTheTicketDayNotTheNext() {
        let model = newDraft()
        model.departure = model.timetableDate("2026-11-06", time: "18:10")!
        model.arrival = model.departure
        model.fillFromTicket(reading(["東京 → 新大阪", "のぞみ 25号", "2026年11月6日(金)", "12:55着"]), now: Date())
        #expect(!model.timeIsSet(.departure))
        #expect(model.dayString(model.arrival) == "2026-11-06")
        #expect(model.clock(model.arrival, extraDays: 0) == "12:55")
    }

    @Test func aLateNightServiceCountsFromItsServiceDay() {
        let model = newDraft()
        model.fillFromTicket(reading(["東京 → 新大阪", "のぞみ 25号", "2026年11月6日(金)", "24:30発 25:10着"]), now: Date())
        #expect(model.dayString(model.departure) == "2026-11-07")
        #expect(model.clock(model.departure, extraDays: 0) == "00:30")
        #expect(model.dayString(model.arrival) == "2026-11-07")
        #expect(model.clock(model.arrival, extraDays: 0) == "01:10")
    }
}
