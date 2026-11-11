import Foundation
import RailCore
import Testing
@testable import RailMap

/// A disabled Save always has a reason shown next to it. The editor's source
/// structure is guarded in RailKit (RegressionGuardEditorStructure).
@MainActor
struct EditorSaveStatusTests {
    private func record() -> Train {
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.region = "jp"
        train.date = "2026-11-06"
        train.stops = [
            Stop(name: "品川", stopType: "origin"),
            Stop(name: "大崎", stopType: "destination"),
        ]
        return train
    }

    private func expectConsistent(_ model: TripDraftModel, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect((model.saveBlocker == nil) == model.canSave, sourceLocation: sourceLocation)
    }

    @Test func aBlankNewTripIsBlockedUntilItHasStations() {
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.region = "jp"
        train.stops = []
        let model = TripDraftModel(train: train, isNew: true)
        #expect(!model.canSave)
        #expect(model.saveBlocker == .noRoute || model.saveBlocker == .chooseOrigin)
        expectConsistent(model)
    }

    @Test func aSavedRecordWithNoEditsCanSave() {
        let model = TripDraftModel(train: record(), isNew: false)
        #expect(model.canSave)
        #expect(model.saveBlocker == nil)
    }

    @Test func anEmptyGroupNameBlocksSave() {
        var train = record()
        train.journeyGroup = JourneyGroup(name: "")
        let model = TripDraftModel(train: train, isNew: false)
        #expect(model.saveBlocker == .groupName)
        expectConsistent(model)
    }

    @Test func arrivalBeforeDepartureBlocksSave() {
        let model = TripDraftModel(train: record(), isNew: false)
        let late = model.timetableDate("2026-11-06", time: "12:00")!
        let early = model.timetableDate("2026-11-06", time: "10:00")!
        model.apply(TripDraftModel.Patch(departure: late, arrival: early), source: .reader)
        #expect(model.saveBlocker == .times)
        expectConsistent(model)
    }
}
