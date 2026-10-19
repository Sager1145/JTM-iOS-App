import Foundation
import Testing
@testable import RailInspection

struct DiagnosticRequestTests {
    private func request(_ fields: String = "") throws -> DiagnosticRequest {
        try JSONDecoder().decode(DiagnosticRequest.self, from: Data("""
        {"schemaVersion":1,"requestID":"scope","workspace":"alignment","action":"prepare","sessionDirectory":"/tmp/session","lineID":"a"\(fields)}
        """.utf8))
    }
    private func input(_ index: Int, line: String = "a", start: Double, end: Double) -> InspectionInput {
        .init(id: "\(line)#\(index)", lineID: line, lineName: line, operatorName: "op", intervalIndex: index,
              fromStationID: "s\(index)", toStationID: "s\(index + 1)", fromName: "from", toName: "to",
              source: [], display: [.init(longitude: start, latitude: 35), .init(longitude: end, latitude: 35)], hasDisplayOverride: false)
    }
    @Test func scopeNeverFallsBackToAnotherLineOrUnknownInterval() throws {
        let inputs = [input(0, start: 139, end: 139.01), input(0, line: "b", start: 139, end: 139.01)]
        #expect(try request().alignmentInputs(inputs).map(\.id) == ["a#0"])
        #expect(throws: DiagnosticError.self) { try request(",\"intervalIndices\":[9]").alignmentInputs(inputs) }
        #expect(throws: DiagnosticError.self) { try request(",\"stationIDs\":[\"missing\"]").alignmentInputs(inputs) }
    }
    @Test func inputPathContractDependsOnWorkspace() throws {
        var alignment = try request()
        try alignment.validate()
        alignment.inputPath = "/tmp/candidate-compact.json"
        try alignment.validate()
        #expect(try JSONDecoder().decode(DiagnosticRequest.self, from: JSONEncoder().encode(alignment)) == alignment)
        alignment.inputPath = "relative-candidate.json"
        #expect(throws: DiagnosticError.self) { try alignment.validate() }

        var route = DiagnosticRequest(requestID: "route", workspace: .route, action: .solve, sessionDirectory: "/tmp/route")
        #expect(throws: DiagnosticError.self) { try route.validate() }
        route.inputPath = "/tmp/journeys.json"
        try route.validate()

        var through = DiagnosticRequest(requestID: "through", workspace: .through, action: .inspect,
                                        sessionDirectory: "/tmp/through", patternID: "pattern", reviewDay: "2026-10-18")
        try through.validate()
        through.inputPath = "/tmp/candidate-compact.json"
        #expect(throws: DiagnosticError.self) { try through.validate() }
    }
    @Test func intervalAndStationScopesIntersect() throws {
        let inputs = (0...2).map { input($0, start: 139, end: 139.01) }
        #expect(try request(",\"intervalIndices\":[0,1],\"stationIDs\":[\"s2\"]").alignmentInputs(inputs).map(\.id) == ["a#1"])
        #expect(throws: DiagnosticError.self) { try request(",\"intervalIndices\":[0],\"stationIDs\":[\"s3\"]").alignmentInputs(inputs) }
    }
    @Test func seamRetainsNeighborIdentityWithoutAcceptingConnectivity() throws {
        let inputs = [input(0, start: 139, end: 139.01), input(1, start: 139.011, end: 139.02)]
        let tasks = DiagnosticCandidate.tasks(selected: [inputs[0]], context: inputs)
        let seam = try #require(tasks.first { $0.category == "intervalSeam" })
        #expect(seam.itemIDs == ["a#0", "a#1"])
        #expect(DiagnosticCandidate.tasks(selected: [inputs[1]], context: inputs).contains { $0.id == seam.id })
        #expect((seam.measuredMetres ?? 0) > 80)
        #expect(tasks.allSatisfy { $0.state == "pendingReview" })
        #expect(tasks.contains { $0.category == "stationOffset" && $0.note.contains("purple") })
    }
    @Test func invalidActionAndCaptureLimitRejectBeforeWork() throws {
        #expect(throws: DiagnosticError.self) { try request(",\"captureLimit\":0").validate() }
        var invalid = try request()
        invalid.action = .solve
        #expect(throws: DiagnosticError.self) { try invalid.validate() }
    }
    @Test func viewpointSelectionRoundTripsAndRejectsInvalidLists() throws {
        let value = try request(",\"viewpointIDs\":[\"a#0#point-2\",\"a#0#point-0\"]")
        try value.validate()
        let encoded = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["viewpointIDs"] as? [String] == ["a#0#point-2", "a#0#point-0"])
        #expect(try JSONDecoder().decode(DiagnosticRequest.self, from: encoded) == value)
        let legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request())) as? [String: Any])
        #expect(legacy["viewpointIDs"] == nil)
        for list in ["[]", "[\"\"]", "[\"  \"]", "[\"a#0#point-0\",\"a#0#point-0\"]"] {
            #expect(throws: DiagnosticError.self) { try request(",\"viewpointIDs\":\(list)").validate() }
        }
        #expect(throws: DecodingError.self) { try request(",\"viewpointIDs\":null") }
        var route = value
        route.workspace = .route; route.action = .solve; route.inputPath = "/tmp/journeys.json"
        #expect(throws: DiagnosticError.self) { try route.validate() }
    }
    @Test func viewpointSelectionAdmitsOnlyExactScopedPlanIDs() throws {
        let inputs = [input(0, start: 139, end: 139.01), input(1, start: 139.01, end: 139.02),
                      input(0, line: "b", start: 139, end: 139.01)]
        let plan = BatchInspectionPlan.build(inputs: inputs, packageVersion: "test")
        let id = try #require(plan.viewpoints.first { $0.itemID == "a#0" }?.id)
        var value = try request(",\"intervalIndices\":[0]")
        #expect(try value.alignmentViewpointIDs(in: plan, inputs: inputs) == nil)
        value.viewpointIDs = [id]
        #expect(try value.alignmentViewpointIDs(in: plan, inputs: inputs) == Set([id]))
        for rejected in ["a#0#point-999", "a#1#point-0", "b#0#point-0"] {
            value.viewpointIDs = [id, rejected]
            #expect(throws: DiagnosticError.self) { try value.alignmentViewpointIDs(in: plan, inputs: inputs) }
        }
        value.viewpointIDs = [id]
        let noAvailableTargets = BatchInspectionPlan.build(inputs: [], packageVersion: "test")
        #expect(throws: DiagnosticError.self) { try value.alignmentViewpointIDs(in: noAvailableTargets, inputs: inputs) }
    }
    @Test func captureSettingsRejectUnsupportedRequestsAndSurviveRoundTrip() throws {
        let settings = DiagnosticCaptureSettings(zoom: 19, width: 640, height: 480,
                                                  appearance: .dark, outputModes: [.smooth])
        var value = try request()
        value.captureSettings = settings
        try value.validate()
        #expect(try JSONDecoder().decode(DiagnosticRequest.self, from: JSONEncoder().encode(value)) == value)
        #expect(value != (try request()))
        #expect(try request().normalizedCaptureSettings == DiagnosticCaptureSettings())
        for invalid in [DiagnosticCaptureSettings(zoom: .infinity), .init(zoom: 21),
                        .init(width: 0), .init(height: 8192), .init(outputModes: []),
                        .init(outputModes: [.display, .display])] {
            value.captureSettings = invalid
            #expect(throws: DiagnosticError.self) { try value.validate() }
        }
        #expect(throws: DecodingError.self) { try request(",\"captureSettings\":{\"zoom\":17,\"width\":640,\"height\":480,\"appearance\":\"sepia\",\"outputModes\":[\"smooth\"]}") }
        #expect(throws: DecodingError.self) { try request(",\"captureSettings\":{\"zom\":19}") }
        #expect(throws: DecodingError.self) { try request(",\"captureSettings\":{\"zoom\":null}") }
        #expect(try request(",\"captureSettings\":{\"zoom\":19}").normalizedCaptureSettings.zoom == 19)
    }
    @Test func misspelledRootCaptureSettingsNeverFallsBackToDefaultZoom() throws {
        let json = Data("""
        {"schemaVersion":1,"requestID":"typo","workspace":"alignment","action":"capture",
         "sessionDirectory":"/tmp/typo-session","lineID":"a","captureSetting":{"zoom":20}}
        """.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DiagnosticRequest.self, from: json) }
        let omittedVersion = Data("""
        {"requestID":"default-version","workspace":"alignment","action":"prepare","sessionDirectory":"/tmp/default-version","lineID":"a"}
        """.utf8)
        #expect(try JSONDecoder().decode(DiagnosticRequest.self, from: omittedVersion).schemaVersion == 1)
    }
    @Test func basemapStyleDefaultsToStandardAndImagerySurvivesRoundTrip() throws {
        #expect(try request().normalizedCaptureSettings.basemapStyle == .standard)
        #expect(try request(",\"captureSettings\":{}").normalizedCaptureSettings.basemapStyle == .standard)
        for style in [DiagnosticCaptureSettings.BasemapStyle.standard, .imagery] {
            let value = try request(",\"captureSettings\":{\"basemapStyle\":\"\(style.rawValue)\"}")
            try value.validate()
            #expect(value.normalizedCaptureSettings.basemapStyle == style)
            let encoded = try JSONEncoder().encode(value)
            #expect(try JSONDecoder().decode(DiagnosticRequest.self, from: encoded) == value)
        }
        for unsupported in ["\"hybrid\"", "null"] {
            #expect(throws: DecodingError.self) {
                try request(",\"captureSettings\":{\"basemapStyle\":\(unsupported)}")
            }
        }
        #expect(throws: DecodingError.self) { try request(",\"captureSettings\":{\"basemapStyl\":\"imagery\"}") }
    }
    @Test func sharpTurnRetainsExactOwnDisplayCornerAndFiniteLegs() throws {
        var selected = input(0, start: 139, end: 139.002)
        selected.display = [.init(longitude: 139, latitude: 35),
                            .init(longitude: 139.001, latitude: 35),
                            .init(longitude: 139.001, latitude: 35.001)]
        var foreign = selected
        foreign.id = "foreign#0"; foreign.lineID = "foreign"
        let candidates = DiagnosticCandidate.tasks(selected: [selected], context: [selected, foreign])
            .filter { $0.category == "sharpTurn" }
        #expect(candidates.count == 1)
        let candidate = try #require(candidates.first)
        #expect(candidate.id == "a#0/displayVertex/1/sharpTurn")
        #expect(candidate.itemIDs == [selected.id])
        #expect(candidate.state == "pendingReview")
        #expect(candidate.note.contains("vertex 1"))
        #expect(candidate.note.contains("139.001"))
        #expect(candidate.note.contains("35.0"))
        #expect(candidate.note.contains("candidate"))
        #expect(candidate.note.contains("physical proof"))
        let encoded = try JSONEncoder().encode(candidate)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let corner = try #require(object["corner"] as? [String: Any])
        #expect(corner["displayVertexIndex"] as? Int == 1)
        let coordinate = try #require(corner["coordinate"] as? [String: Double])
        #expect(coordinate == ["longitude": 139.001, "latitude": 35])
        let angle = try #require(corner["turnDegrees"] as? Double)
        let incoming = try #require(corner["incomingMetres"] as? Double)
        let outgoing = try #require(corner["outgoingMetres"] as? Double)
        #expect(angle.isFinite && abs(angle - 90) < 1e-9)
        #expect(incoming.isFinite && (90...92).contains(incoming))
        #expect(outgoing.isFinite && (110...112).contains(outgoing))
        #expect(try JSONDecoder().decode(DiagnosticCandidate.self, from: encoded) == candidate)
    }
    @Test func sharpTurnExcludesStraightDuplicateInvalidAndUnselectedContextGeometry() {
        let a = InspectionPoint(longitude: 139, latitude: 35)
        let b = InspectionPoint(longitude: 139.001, latitude: 35)
        let c = InspectionPoint(longitude: 139.002, latitude: 35)
        var selected = input(0, start: 139, end: 139.002)
        var foreign = input(0, line: "foreign", start: 139, end: 139.002)
        foreign.display = [a, b, .init(longitude: 139.001, latitude: 35.001)]
        for points in [[a, b, c], [a, a, b], [a, b, b], [a, a, a],
                       [a, .init(longitude: .infinity, latitude: 35), c],
                       [a, .init(longitude: 181, latitude: 35), c],
                       [a, .init(longitude: 139, latitude: 91), c]] {
            selected.display = points
            #expect(!DiagnosticCandidate.tasks(selected: [selected], context: [selected, foreign])
                .contains { $0.category == "sharpTurn" })
        }
    }
    @Test func sharpTurnMetadataRemainsAbsentWhenDecodingAnOldCandidate() throws {
        let legacy = Data("""
        {"id":"a#0/lineOffset","category":"lineOffset","itemIDs":["a#0"],
         "state":"pendingReview","note":"Compare retained basemap."}
        """.utf8)
        let candidate = try JSONDecoder().decode(DiagnosticCandidate.self, from: legacy)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate)) as? [String: Any])
        #expect(object["corner"] == nil)
        #expect(candidate.itemIDs == ["a#0"])
    }
}
