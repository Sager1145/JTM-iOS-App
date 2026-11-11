import Foundation
import RailCore
import Testing

@testable import RailMap

@MainActor
struct TripNoteGapsTests {
    private func note(_ id: String = "n1", text: String = "stopped", time: String? = "10:30",
                      anchor: TripNoteAnchor? = nil) -> TripNote {
        TripNote(id: id, category: "Incident", text: text, time: time,
                 anchor: anchor ?? .station(TripNoteStation(name: "東京"), fallback: nil))
    }

    private func trip(notes: [TripNote]? = nil) -> Train {
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.region = "jp"
        train.date = "2026-10-12"
        train.number = "のぞみ 25号"
        train.stops = [
            Stop(name: "東京", departure: "9:05", stopType: "origin"),
            Stop(name: "新大阪", arrival: "12:55", stopType: "destination"),
        ]
        train.tripNotes = notes
        return train
    }

    // MARK: notes survive an editor save

    @Test func notesSurviveAnEditorSave() throws {
        let notes = [note("a"), note("b", text: "second")]
        let train = trip(notes: notes)
        let model = TripDraftModel(train: train, isNew: false)
        model.trainNumber = "のぞみ 27号"
        var saved: Train?
        model.commit(confirmedRemoval: false, original: train, existingIDs: [], onSave: { saved = $0 })
        let result = try #require(saved)
        #expect(result.tripNotes == notes)
    }

    // MARK: persist before close

    @Test func aRefusedWriteKeepsTheDraftAndFormOpen() async {
        let flow = TripNoteFlow()
        flow.draft = TripNoteDraft(id: "n1", isNew: true, category: "", text: "x", time: nil,
                                   anchor: .station(TripNoteStation(name: "東京"), fallback: nil))
        flow.screen = .form
        await flow.persist([note()], replacing: nil, onSet: { _ in false })
        #expect(flow.saveRefused)
        #expect(flow.screen == .form)
        #expect(flow.draft != nil)
        #expect(!flow.isSaving)
    }

    @Test func aPersistedWriteClosesTheForm() async {
        let flow = TripNoteFlow()
        flow.screen = .form
        await flow.persist([note()], replacing: nil, onSet: { _ in true })
        #expect(!flow.saveRefused)
        #expect(flow.screen == nil)
    }

    // MARK: unchanged save

    @Test func anUnchangedSaveSucceedsWithoutWriting() async {
        let flow = TripNoteFlow()
        flow.screen = .form
        var wrote = false
        await flow.persist([note()], replacing: [note()], onSet: { _ in wrote = true; return false })
        #expect(!wrote)
        #expect(!flow.saveRefused)
        #expect(flow.screen == nil)
    }

    // MARK: one alert per failed save

    @Test func aFailedNoteSaveRaisesOnlyTheFormsAlert() {
        #expect(NoteSaveAlert.journeyFailureDetail(afterNoteSave: false, current: "disk full") == nil)
        #expect(NoteSaveAlert.journeyFailureDetail(afterNoteSave: true, current: nil) == nil)
        // A persisted note save leaves an unrelated journey failure alone.
        #expect(NoteSaveAlert.journeyFailureDetail(afterNoteSave: true, current: "disk full") == "disk full")
    }

    // MARK: offset label

    @Test func offsetLabelUsesTheNotesOwnInstant() {
        let describer = TripNoteDescriber(train: trip(notes: [note()]), localization: AppLocalization())
        let label = describer.time("10:30")
        #expect(label?.hasSuffix("UTC+9") == true)
        let expected = describer.clock.instant(serviceDate: "2026-10-12", clock: "10:30")
        #expect(describer.offsetInstant("10:30") == expected)
    }

    /// New York changes its offset on 2026-11-01, so the trip date's midnight
    /// (UTC-4) and a 10:30 note (UTC-5) disagree: only the note's own instant is right.
    @Test func offsetLabelFollowsTheNotesInstantAcrossADaylightSavingChange() {
        var train = trip(notes: [note()])
        train.date = "2026-11-01"
        let describer = TripNoteDescriber(
            train: train, localization: AppLocalization(),
            clock: RegionClock.forZone("America/New_York", regionCode: "us"))
        #expect(describer.time("10:30")?.hasSuffix("UTC-5") == true)
        #expect(describer.time("00:30")?.hasSuffix("UTC-4") == true)
        #expect(describer.time("25:10")?.hasSuffix("UTC-5") == true)
    }

    @Test func anUndatedTripFallsBackToNow() {
        var train = trip()
        train.date = nil
        let describer = TripNoteDescriber(train: train, localization: AppLocalization())
        #expect(abs(describer.offsetInstant("10:30").timeIntervalSinceNow) < 5)
    }

    // MARK: place naming

    @Test func cardAndMapNamePlacesThroughOneHelper() {
        let train = trip()
        let localization = AppLocalization()
        let describer = TripNoteDescriber(train: train, localization: localization)
        let anchors: [TripNoteAnchor] = [
            .station(TripNoteStation(name: "新大阪"), fallback: nil),
            .interval(from: TripNoteStation(name: "東京"), to: TripNoteStation(name: "新大阪"),
                      fraction: 0.5, fallback: nil),
            .coordinate(Coordinate(lon: 139, lat: 35)),
        ]
        for anchor in anchors {
            let shared = TripNotePlaceNaming.place(
                anchor, stops: train.stops, region: Region.resolved(train), localization: localization)
            #expect(describer.place(anchor) == shared)
        }
    }
}
