import Foundation
import Testing
@testable import RailCore

struct JourneyThroughCompletionTests {
    private func train() -> Train {
        Train(id: "through", date: "2026-07-29", number: "Through express",
              origin: "Alpha", destination: "Omega", stops: [
                Stop(name: "Alpha", n02StationCode: "A", departure: "09:00", stopType: "origin", rideSegment: true),
                Stop(name: "Boundary", n02StationCode: "B", arrival: "09:30", departure: "09:32", rideSegment: true),
                Stop(name: "Omega", n02StationCode: "C", arrival: "10:00", stopType: "destination")
              ], region: "jp")
    }

    private func response(_ body: String) -> String {
        """
        {"trains":[{"id":"through","sources":[{"url":"https://operator.example/timetable","explanation":"Dated timetable supports each operator and train number"}],\(body)}]}
        """
    }

    private let sections = """
    "route_sections":[
      {"from_index":0,"to_index":1,"from":"Alpha","to":"Boundary","line_names":["First Line"],"operator_names":["First Rail"],"number":"101M"},
      {"from_index":1,"to_index":2,"from":"Boundary","to":"Omega","line_names":["Second Line"],"operator_names":["Second Rail"],"number":"201M"}
    ]
    """

    @Test("through completion binds different operator numbers to their exact intervals")
    func intervalCompletion() throws {
        let original = train()
        let completed = try #require(JourneyCompletion.merge(response: response(sections), into: [original]).first)
        let legs = StoreOperations.rideRouteSections(for: completed)
        #expect(legs.map(\.number) == ["101M", "201M"])
        #expect(legs.map(\.operatorNames) == [["First Rail"], ["Second Rail"]])
        #expect(legs.map(\.lineNames) == [["First Line"], ["Second Line"]])
        #expect(completed.stops == original.stops)
        #expect(completed.company == nil)
        let exported = TrainValidation.normalizeExportTrain(completed)
        #expect(exported.routeSections?.map(\.number) == ["101M", "201M"])
    }

    @Test("prompt includes per-interval facts and notes without station codes")
    func promptContext() throws {
        var original = train()
        original.notes = "Ticket says 101M"
        original.routeSections = [RouteSection(fromN02StationCode: "A", toN02StationCode: "B", lineNames: ["First Line"], operatorNames: ["First Rail"], number: "101M")]
        let prompt = try JourneyCompletion.prompt(trains: [original], context: "Check the boundary number")
        #expect(prompt.contains("First Rail"))
        #expect(prompt.contains("101M"))
        #expect(prompt.contains("Ticket says 101M"))
        #expect(prompt.contains("Check the boundary number"))
        #expect(!prompt.contains("n02_station_code"))
    }

    @Test("conflicting interval facts reject the entire response")
    func conflictsAreAtomic() throws {
        var original = train()
        original.routeSections = [RouteSection(fromN02StationCode: "A", toN02StationCode: "B", number: "99M")]
        #expect(throws: JourneyCompletion.Error.self) {
            try JourneyCompletion.merge(response: response("\"notes\":\"A sourced note\", " + sections), into: [original])
        }
        #expect(original.notes == nil)
        #expect(original.routeSections?.first?.number == "99M")
    }

    @Test("interval references reject wrong names, skipped stops, duplicate and empty metadata")
    func invalidIntervals() {
        for row in [
            #"{"from_index":0,"to_index":1,"from":"Wrong","to":"Boundary","number":"101M"}"#,
            #"{"from_index":0,"to_index":2,"from":"Alpha","to":"Omega","number":"101M"}"#,
            #"{"from_index":0,"to_index":1,"from":"Alpha","to":"Boundary","line_names":[]}"#,
            #"{"from_index":0,"to_index":1,"from":"Alpha","to":"Boundary","operator_names":["Rail","Rail"]}"#,
            #"{"from_index":0,"to_index":1,"from":"Alpha","to":"Boundary","number":" "}"#,
            #"{"from_index":0,"to_index":1,"from":"Alpha","to":"Boundary","number":"101M","station_code":"A"}"#
        ] {
            #expect(throws: JourneyCompletion.Error.self) {
                try JourneyCompletion.merge(response: response("\"route_sections\":[" + row + "]"), into: [train()])
            }
        }
        let row = #"{"from_index":0,"to_index":1,"from":"Alpha","to":"Boundary","number":"101M"}"#
        #expect(throws: JourneyCompletion.Error.self) {
            try JourneyCompletion.merge(response: response("\"route_sections\":[" + row + "," + row + "]"), into: [train()])
        }
    }

    @Test("new intermediate calls retain the correct company's metadata across split legs")
    func insertedCallsSplitIdentity() throws {
        let json = response(sections + #", "intermediate_stops":[{"after_index":0,"name":"Beta","arrival":"09:15","departure":"09:16"}]"#)
        let completed = try #require(JourneyCompletion.merge(response: json, into: [train()]).first)
        #expect(completed.stops.map(\.name) == ["Alpha", "Beta", "Boundary", "Omega"])
        let legs = StoreOperations.rideRouteSections(for: completed)
        #expect(legs.map(\.number) == ["101M", "101M", "201M"])
        #expect(legs.map(\.operatorNames) == [["First Rail"], ["First Rail"], ["Second Rail"]])
        #expect(completed.stops[1].rideSegment)
    }

    @Test("notes persist through canonical import and export; personal remarks append separately")
    func notesRoundTrip() throws {
        var original = train()
        original.notes = "Published operating restriction"
        let withRemarks = JourneyCompletion.addingRemarks("  Ticket photo attached  ", to: original)
        #expect(withRemarks.notes == "Published operating restriction\n\nTicket photo attached")
        #expect(JourneyCompletion.addingRemarks(" ", to: original) == original)
        let exported = TrainValidation.buildCanonicalTrainStore([withRemarks])
        let data = try JSONEncoder().encode(exported)
        let decoded = try JSONDecoder().decode(TrainStore.self, from: data)
        #expect(decoded.trains.first?.notes == withRemarks.notes)
        let imported = try TrainValidation.normalizeImportedTrain(StoreOperations.json(withRemarks))
        #expect(imported.notes == withRemarks.notes)
    }

    @Test("a new operator boundary in an endpoint-only draft gets separate service numbers")
    func newBoundaryGetsSeparateNumbers() throws {
        var original = train()
        original.stops.remove(at: 1)
        let json = response("""
        "intermediate_stops":[{"after_index":0,"name":"Boundary","arrival":"09:30","departure":"09:32"}],
        "expanded_route_sections":[
          {"from_index":0,"to_index":1,"from":"Alpha","to":"Boundary","line_names":["First Line"],"operator_names":["First Rail"],"number":"101M"},
          {"from_index":1,"to_index":2,"from":"Boundary","to":"Omega","line_names":["Second Line"],"operator_names":["Second Rail"],"number":"201M"}
        ]
        """)
        let completed = try #require(JourneyCompletion.merge(response: json, into: [original]).first)
        #expect(completed.stops.map(\.name) == ["Alpha", "Boundary", "Omega"])
        #expect(StoreOperations.rideRouteSections(for: completed).map(\.number) == ["101M", "201M"])
    }

    @Test("splitting an interval preserves recorded company-specific outer station codes")
    func splitPreservesBoundaryCodes() throws {
        var original = train()
        original.routeSections = [RouteSection(
            from: "Alpha", to: "Boundary", fromN02StationCode: "ALT-A",
            toN02StationCode: "ALT-B", lineNames: ["First Line"], number: "101M")]
        let completed = try #require(JourneyCompletion.merge(
            response: response(#""intermediate_stops":[{"after_index":0,"name":"Beta","arrival":"09:15","departure":"09:16"}]"#),
            into: [original]).first)
        let legs = try #require(completed.routeSections)
        #expect(legs.count == 2)
        #expect(legs[0].fromN02StationCode == "ALT-A")
        #expect(legs[1].toN02StationCode == "ALT-B")
        #expect(legs.map(\.number) == ["101M", "101M"])
        #expect(StoreOperations.rideRouteSections(for: completed)[0].fromN02StationCode == "ALT-A")
    }

    @Test("sourced AI notes fill blanks but preserve recorded notes")
    func sourcedNotes() throws {
        let completed = try #require(JourneyCompletion.merge(response: response(#""notes":"Number changes at Boundary""#), into: [train()]).first)
        #expect(completed.notes == "Number changes at Boundary")
        #expect(throws: JourneyCompletion.Error.self) {
            try JourneyCompletion.merge(response: response(#""notes":"Different restriction""#), into: [completed])
        }
        #expect(throws: JourneyCompletion.Error.missingEvidence(trainID: "through")) {
            try JourneyCompletion.merge(response: #"{"trains":[{"id":"through","sources":[],"notes":"Unsourced"}]}"#, into: [train()])
        }
    }

    @Test("new calls cannot duplicate a verified physical corridor onto each split interval")
    func physicalCorridorRequiresReviewedSplit() {
        var original = train()
        original.routeSections = [RouteSection(
            from: "Alpha", to: "Boundary", lineNames: ["First Line"],
            lineIDs: ["reviewed-line"], sectionCodes: ["physical-1", "physical-2"], number: "101M")]
        #expect(throws: JourneyCompletion.Error.self) {
            try JourneyCompletion.merge(
                response: response(#""intermediate_stops":[{"after_index":0,"name":"Beta","arrival":"09:15","departure":"09:16"}]"#),
                into: [original])
        }
        #expect(original.stops.count == 3)
        #expect(original.routeSections?.first?.sectionCodes == ["physical-1", "physical-2"])
    }

    @Test("research requests return readable sourced answers while completion remains JSON")
    func requestPurposes() throws {
        let research = try ChatGPTSubscriptionProtocol.requestBody(prompt: "Find the train", model: "available", purpose: .research)
        let completion = try ChatGPTSubscriptionProtocol.requestBody(prompt: "Complete the train", model: "available")
        let researchBody = try #require(JSONSerialization.jsonObject(with: research) as? [String: Any])
        let completionBody = try #require(JSONSerialization.jsonObject(with: completion) as? [String: Any])
        #expect((researchBody["instructions"] as? String)?.contains("readable text and source URLs") == true)
        #expect((completionBody["instructions"] as? String)?.contains("JSON only") == true)
        #expect(researchBody["store"] as? Bool == false)
    }
}
