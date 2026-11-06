import Foundation
import RailCore
import Testing

struct JourneyGroupTests {
    private func train(group: JourneyGroup? = nil, region: String = "jp") -> Train {
        Train(
            id: "ride-20260930", date: "2026-09-30", number: "Local",
            origin: "A", destination: "B",
            stops: [Stop(name: "A", rideSegment: true), Stop(name: "B")],
            region: region, journeyGroup: group)
    }

    @Test func oldJSONOmitsGroupOnRoundTrip() throws {
        let legacy = """
            {"id":"legacy","number":"Local","origin":"A","destination":"B","stops":[]}
            """
        let decoded = try JSONDecoder().decode(Train.self, from: Data(legacy.utf8))
        #expect(decoded.journeyGroup == nil)
        let output = try TrainValidation.JSON.parse(
            String(decoding: JSONEncoder().encode(decoded), as: UTF8.self))
        #expect(!output.hasOwnKey("journey_group"))
        let workspace = StoreOperations.Workspace(store: TrainStore(trains: [train()]))
        let exported = try TrainValidation.JSON.parse(StoreOperations.exportTrainStore(workspace))
        #expect(Set(exported.ownKeys) == Set(["schema_version", "trains"]))
        #expect(!StoreOperations.json(train()).hasOwnKey("journey_group"))
    }

    @Test func canonicalExportKeepsAssignmentAcrossRegions() throws {
        let group = JourneyGroup(id: "summer-trip", name: "Summer trip")
        var taiwanRide = train(group: group, region: "tw")
        taiwanRide.id = "taiwan-20260930"
        let rides = [train(group: group), taiwanRide]
        let workspace = StoreOperations.Workspace(store: TrainStore(trains: rides))
        let text = StoreOperations.exportTrainStore(workspace)
        let decoded = try JSONDecoder().decode(TrainStore.self, from: Data(text.utf8))
        #expect(decoded.trains.map(\.journeyGroup) == [group, group])
        #expect(decoded.trains.map(\.region) == ["jp", "tw"])
        let raw = try TrainValidation.JSON.parse(text)
        #expect(try TrainValidation.validateTrainStore(raw))
        #expect(Set(raw.ownKeys) == Set(["schema_version", "trains"]))
        if case .array(let rows)? = raw["trains"] {
            for row in rows {
                let imported = try TrainValidation.normalizeImportedTrain(row)
                #expect(imported.journeyGroup == group)
            }
        } else {
            Issue.record("Export must contain trains")
        }
    }

    @Test func importAndCodableNormalizeNames() throws {
        let raw = try TrainValidation.JSON.parse("""
            {"id":"ride-20260930","number":"Local","origin":"A","destination":"B",
             "stops":[{"name":"A"},{"name":"B"}],
             "journey_group":{"id":"stable","name":"  North\\n\\tJapan  Tour  "}}
            """)
        let imported = try TrainValidation.normalizeImportedTrain(raw)
        #expect(imported.journeyGroup?.id == "stable")
        #expect(imported.journeyGroup?.name == "North Japan")
        let decoded = try JSONDecoder().decode(JourneyGroup.self, from: Data("""
            {"id":"stable","name":"  North\\n\\tJapan  Tour  "}
            """.utf8))
        #expect(decoded == imported.journeyGroup)
        var edited = decoded
        edited.name = "  New\nname  "
        #expect(edited.name == "New name")
    }

    @Test func duplicateRetainsAssignmentAndVisibilityEdits() {
        let group = JourneyGroup(id: "stable", name: "Trip")
        var workspace = StoreOperations.Workspace(store: TrainStore(trains: [train(group: group)]))
        #expect(StoreOperations.duplicateTrain(workspace.trains[0].id, in: &workspace) == .trainCollectionChanged)
        #expect(workspace.trains.count == 2)
        #expect(workspace.trains[0].id != workspace.trains[1].id)
        #expect(workspace.trains.map(\.journeyGroup) == [group, group])
        StoreOperations.toggleTrainVisibility(workspace.trains[1].id, in: &workspace)
        #expect(workspace.trains[1].journeyGroup == group)
    }

    @Test func lengthUsesWholeSwiftCharacters() {
        let character = "👨‍👩‍👧‍👦"
        let name = String(repeating: character, count: 13)
        let group = JourneyGroup(name: name)
        #expect(group.name.count == JourneyGroup.maxNameLength)
        #expect(group.name == String(repeating: character, count: 12))
        let combining = String(repeating: "e\u{301}", count: 13)
        #expect(JourneyGroup.normalizedName(combining).count == 12)
        #expect(JourneyGroup(name: "Trip").id != JourneyGroup(name: "Trip").id)
    }

    @Test func invalidAssignmentDoesNotSilentlyLoseGroup() throws {
        let raw = try TrainValidation.JSON.parse("""
            {"id":"ride-20260930","number":"Local","origin":"A","destination":"B",
             "stops":[{"name":"A"},{"name":"B"}],"journey_group":{"name":"Trip"}}
            """)
        #expect(throws: TrainValidation.ValidationError.self) {
            try TrainValidation.normalizeImportedTrain(raw)
        }
        let null = try TrainValidation.JSON.parse("""
            {"id":"ride-20260930","number":"Local","origin":"A","destination":"B",
             "stops":[{"name":"A"},{"name":"B"}],"journey_group":null}
            """)
        #expect(try TrainValidation.normalizeImportedTrain(null).journeyGroup == nil)
    }
}
