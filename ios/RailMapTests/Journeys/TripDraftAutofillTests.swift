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
        for field: TripDraftModel.Field in [.number, .trainType, .seat, .fare, .riddenCar, .departure] {
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
        let reader = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 8))!
        model.apply(TripDraftModel.Patch(departure: reader), source: .reader)

        model.fillFromTicket(nozomi(), now: Date())

        #expect(model.trainNumber == "ひかり 500")
        #expect(model.draft.ticket?.seat == "3D")
        #expect(model.trainType == "local")
        #expect(model.departure == reader)
        for field: TripDraftModel.Field in [.number, .seat, .trainType, .departure] {
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
}
