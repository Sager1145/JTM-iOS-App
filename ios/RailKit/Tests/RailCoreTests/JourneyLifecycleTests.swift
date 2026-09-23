import Foundation
import Testing

@testable import RailCore

/// End-to-end contracts for the pure part of adding and saving a journey.
///
/// Fixture parity proves that individual functions agree with the web app.
/// These tests exercise the functions as one workflow: a journey enters a
/// workspace, may be duplicated or edited, is saved as canonical JSON, passes
/// whole-store validation, and can be loaded again without losing identity.
@Suite("Journey add and save lifecycle")
struct JourneyLifecycleTests {
    private static func journey(
        id: String,
        date: String? = "2026-09-22",
        number: String = "Night Owl 1"
    ) -> Train {
        Train(
            id: id,
            date: date,
            number: number,
            numberEn: "Night Owl",
            trainType: "Limited Express",
            vehicleType: "EMU-9000",
            company: "Example Rail",
            origin: "Alpha",
            destination: "Omega",
            direction: "down",
            visible: true,
            style: TrainStyle(color: "#123456"),
            routePolicy: RoutePolicy(
                mode: "single_primary_route",
                jrOnly: false,
                allowAlternatives: false,
                allowBrowserStraightLineFallback: false,
                allowedInstitutionTypeCodes: ["1", "2"]),
            routeSections: [
                RouteSection(
                    from: "Alpha",
                    to: "Omega",
                    lineNames: ["Main Line"],
                    operatorNames: ["Example Rail"]),
            ],
            stops: [
                Stop(
                    name: "Alpha",
                    platformNumber: 3,
                    departure: "23:55",
                    stopType: "origin",
                    rideSegment: true),
                Stop(
                    name: "Omega",
                    platformNumber: 1,
                    arrival: "25:10",
                    stopType: "destination",
                    rideSegment: true),
            ],
            region: "jp")
    }

    private static func dateView(_ train: Train) -> Dates.Train {
        Dates.Train(
            id: train.id,
            date: train.date,
            stops: train.stops.map {
                Dates.Stop(
                    arrival: $0.arrival,
                    departure: $0.departure,
                    stopType: $0.stopType)
            })
    }

    @Test("adding a colliding id creates and focuses one distinct journey")
    func addMakesIdentityUniqueWithoutReplacingTheExistingJourney() {
        let existing = Self.journey(id: "night-owl", number: "Existing")
        var workspace = StoreOperations.Workspace(
            store: TrainStore(trains: [existing]),
            selectedTrainID: existing.id,
            focusedTrainID: existing.id,
            country: "jp")

        let result = StoreOperations.addTrain(
            Self.journey(id: "night-owl", number: "Added"),
            in: &workspace)

        #expect(result == .trainCollectionChanged)
        #expect(workspace.store.trains.map(\.id) == ["night-owl", "night-owl-2"])
        #expect(workspace.store.trains[0] == existing)
        #expect(workspace.store.trains[1].number == "Added")
        #expect(workspace.selectedTrainID == "night-owl-2")
        #expect(workspace.focusedTrainID == "night-owl-2")
    }

    @Test("duplicating twice copies the value while assigning stable identities")
    func duplicateCopiesEveryJourneyFieldExceptIdentityAndCaption() {
        let original = Self.journey(id: "night-owl")
        var workspace = StoreOperations.Workspace(
            store: TrainStore(trains: [original]),
            country: "jp")

        #expect(StoreOperations.duplicateTrain(original.id, in: &workspace) == .trainCollectionChanged)
        #expect(StoreOperations.duplicateTrain(original.id, in: &workspace) == .trainCollectionChanged)
        #expect(workspace.store.trains.map(\.id) == ["night-owl", "night-owl-copy", "night-owl-copy-2"])

        var expectedFirstCopy = original
        expectedFirstCopy.id = "night-owl-copy"
        expectedFirstCopy.number = "Night Owl 1 Copy"
        #expect(workspace.store.trains[1] == expectedFirstCopy)

        var expectedSecondCopy = expectedFirstCopy
        expectedSecondCopy.id = "night-owl-copy-2"
        #expect(workspace.store.trains[2] == expectedSecondCopy)
        #expect(workspace.store.trains[0] == original)
        #expect(workspace.selectedTrainID == "night-owl-copy-2")
        #expect(workspace.focusedTrainID == "night-owl-copy-2")
    }

    @Test("journeys sharing a date remain separate inventory entries after save")
    func duplicateDatesAreBucketsRatherThanIdentity() throws {
        var workspace = StoreOperations.Workspace(country: "jp")
        _ = StoreOperations.addTrain(Self.journey(id: "night-owl-a"), in: &workspace)
        _ = StoreOperations.addTrain(
            Self.journey(id: "night-owl-b", number: "Night Owl 2"),
            in: &workspace)

        let dateViews = workspace.store.trains.map(Self.dateView)
        let dates = Dates.availableDates(dateViews)
        #expect(dates == ["2026-09-22"])
        #expect(Dates.trains(dateViews, inBucket: "2026-09-22").compactMap(\.id)
            == ["night-owl-a", "night-owl-b"])
        #expect(workspace.store.trains.count == 2)

        let saved = StoreOperations.exportTrainStore(workspace)
        let parsed = try TrainValidation.JSON.parse(saved)
        try TrainValidation.validateTrainStore(parsed)
        let decoded = try JSONDecoder().decode(TrainStore.self, from: Data(saved.utf8))

        #expect(decoded.trains.map(\.id) == ["night-owl-a", "night-owl-b"])
        #expect(decoded.trains.map(\.date) == ["2026-09-22", "2026-09-22"])
    }

    @Test("editing a journey replaces its value without replacing its identity")
    func editThenSaveKeepsOneStableIdentity() throws {
        var workspace = StoreOperations.Workspace(country: "jp")
        _ = StoreOperations.addTrain(Self.journey(id: "night-owl"), in: &workspace)
        let stableID = try #require(workspace.selectedTrainID)
        let index = try #require(workspace.store.trains.firstIndex { $0.id == stableID })

        var edited = workspace.store.trains[index]
        edited.number = "Night Owl Revised"
        edited.vehicleType = "EMU-9100"
        edited.stops[0].departure = "23:58"
        workspace.store.trains[index] = edited

        let saved = StoreOperations.exportTrainStore(workspace)
        let parsed = try TrainValidation.JSON.parse(saved)
        try TrainValidation.validateTrainStore(parsed)
        let decoded = try JSONDecoder().decode(TrainStore.self, from: Data(saved.utf8))
        let restored = try #require(decoded.trains.first)

        #expect(decoded.trains.count == 1)
        #expect(restored.id == stableID)
        #expect(restored.number == "Night Owl Revised")
        #expect(restored.vehicleType == "EMU-9100")
        #expect(restored.stops[0].departure == "23:58")
    }

    @Test("an invalid import fails before changing journey inventory")
    func rejectedImportLeavesWorkspaceUnchanged() throws {
        let existing = Self.journey(id: "night-owl")
        var workspace = StoreOperations.Workspace(
            store: TrainStore(trains: [existing]),
            selectedTrainID: existing.id,
            focusedTrainID: existing.id,
            country: "jp")
        let before = workspace
        let invalid = try TrainValidation.JSON.parse(
            #"{"id":"broken","number":"Broken","origin":"A","destination":"B","stops":[{"name":"A"}]}"#)

        #expect(throws: TrainValidation.ValidationError.self) {
            try StoreOperations.appendImportedTrain(invalid, in: &workspace)
        }
        #expect(workspace == before)
    }

    @Test("canonical save escapes text and is stable through validation and re-import")
    func canonicalSaveRoundTripsExactInventoryAndEscapedText() throws {
        var first = Self.journey(
            id: "night-owl-a",
            date: " 2026/09/22 ",
            number: "Night \"Owl\"\n1 🚄")
        first.numberEn = "Night\tOwl"
        first.stops[0].name = "Alpha / Platform \"A\""

        var workspace = StoreOperations.Workspace(country: "jp")
        _ = StoreOperations.addTrain(first, in: &workspace)
        _ = StoreOperations.addTrain(
            Self.journey(id: "night-owl-b", date: nil, number: "Second"),
            in: &workspace)

        let saved = StoreOperations.exportTrainStore(workspace)
        #expect(saved.contains(#""number": "Night \"Owl\"\n1 🚄""#))
        #expect(saved.contains(#""number_en": "Night\tOwl""#))
        #expect(saved.contains(#""name": "Alpha / Platform \"A\"""#))

        let parsed = try TrainValidation.JSON.parse(saved)
        try TrainValidation.validateTrainStore(parsed)
        let decoded = try JSONDecoder().decode(TrainStore.self, from: Data(saved.utf8))
        let expected = TrainValidation.buildCanonicalTrainStore(
            workspace.store.trains,
            country: workspace.country)
        #expect(decoded == expected)
        #expect(decoded.trains.map(\.date) == ["2026-09-22", Dates.undated])

        guard case .array(let rows)? = parsed["trains"] else {
            Issue.record("saved store did not contain a trains array")
            return
        }
        var reimported = StoreOperations.Workspace(country: "jp")
        for row in rows {
            _ = try StoreOperations.appendImportedTrain(row, in: &reimported)
        }
        #expect(StoreOperations.exportTrainStore(reimported) == saved)
    }
}
