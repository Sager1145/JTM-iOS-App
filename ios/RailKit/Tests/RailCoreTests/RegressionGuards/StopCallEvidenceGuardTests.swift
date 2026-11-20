import Foundation
import RailTestSupport
import Testing
@testable import RailCore

/// Regression guard for the trip card's stop timeline: a station is shown as
/// passing only when the trip's record says the train passed it.
///
/// The route planner writes every station between two calls as `pass_through`
/// with a `generated_by` marker. That is a statement about the track, not about
/// the train, so the timeline shows those rows as "on route" and keeps
/// "Passing" and the レ marker for passes the record itself carries
/// (entered, imported, or a bundled sample).
@Suite("RegressionGuardStopCallEvidence")
struct RegressionGuardStopCallEvidenceTests {
    private struct Part: Decodable { let train: Train }

    /// The trip in the user's screenshot: sample はやぶさ27号, 2026-07-13.
    @Test("the sample はやぶさ27号 keeps its recorded stops and recorded passes")
    func sampleHayabusaKeepsRecordedStopsAndPasses() throws {
        let url = try PortFixtures.repositoryRoot().appending(path: "app/data/sample-data/part-067.json")
        let train = try JSONDecoder().decode(Part.self, from: Data(contentsOf: url)).train
        #expect(train.number.hasPrefix("はやぶさ27号"))
        #expect(train.date == "2026-07-13")

        let stops = train.stops.filter { $0.callEvidence == .stop }
        #expect(stops.map(\.name) == ["東京", "上野", "大宮", "仙台", "盛岡", "八戸", "新青森", "新函館北斗"])
        #expect(stops.prefix(3).map(\.departure) == ["14:20", "14:26", "14:45"])

        // The record itself says these were passed; none is planner-made.
        let passes = train.stops.filter { $0.callEvidence == .recordedPass }
        #expect(Array(passes.prefix(7).map(\.name))
            == ["小山", "宇都宮", "那須塩原", "新白河", "郡山", "福島", "白石蔵王"])
        #expect(passes.count == 18)
        #expect(passes.allSatisfy { $0.arrival == nil && $0.departure == nil })
        #expect(!train.stops.contains { $0.callEvidence == .onRouteUnknown })
    }

    @Test("a timetable-filled trip has only stops")
    func matchedTimetableTripHasOnlyStops() throws {
        let database = try TrainTimetableDatabase.bundled(bundle: .module)
        let draft = Train(id: "matched", date: nil, number: "", origin: "", destination: "",
                          stops: [], region: "jp")
        let filled = try database.trips(on: "2026-05-16").lazy
            .compactMap { $0.publishedStopsDraft(to: draft) }.first
        let train = try #require(filled)
        #expect(train.stops.count >= 2)
        #expect(train.stops.allSatisfy { $0.callEvidence == .stop })
    }

    @Test("stations the route planner inserts are on route, not passing, until edited")
    func plannerInsertedStationsAreNotCalledPassing() throws {
        // Only the boarding and alighting stations are known; no timetable, no pattern.
        let ends = ["A", "E"]
        let route = choice(["A", "B", "C", "D", "E"])
        let recorded = RailwayRouteEditing.preparing(Train(
            id: "old-trip", date: "1998-08-10", number: "Express", origin: "A", destination: "E",
            stops: ends.map { Stop(name: $0, n02StationCode: $0, rideSegment: true) }))
        let plan = try #require(RailwayRouteEditing.plan(train: recorded, choice: route))
        let planned = plan.updatedTrain
        #expect(planned.stops.map(\.name) == ["A", "B", "C", "D", "E"])
        #expect(planned.stops.map(\.callEvidence)
            == [.stop, .onRouteUnknown, .onRouteUnknown, .onRouteUnknown, .stop])

        // The state survives save and reload.
        let saved = TrainValidation.normalizeExportTrain(planned)
        var reloaded = try TrainValidation.normalizeImportedTrain(StoreOperations.json(saved))
        #expect(reloaded.stops.map(\.callEvidence) == planned.stops.map(\.callEvidence))

        // The editor clears the marker when the user changes a row. A row the
        // user confirms as a pass is then a recorded pass; one they make a stop is a stop.
        reloaded.stops[1].routeEditing?.generatedBy = nil
        reloaded.stops[2].routeEditing?.generatedBy = nil
        reloaded.stops[2].stopType = "passenger_stop"
        #expect(reloaded.stops.map(\.callEvidence)
            == [.stop, .recordedPass, .stop, .onRouteUnknown, .stop])
    }

    @Test("an authored pass with no editing metadata is a recorded pass")
    func authoredPassIsRecorded() {
        #expect(Stop(name: "小山", stopType: "pass_through", rideSegment: true).callEvidence == .recordedPass)
        for type in ["origin", "passenger_stop", "operational_stop", "destination"] {
            #expect(Stop(name: "仙台", stopType: type, rideSegment: true).callEvidence == .stop)
        }
    }

    @Test("the timeline asks callEvidence and never calls a planner row passing")
    func timelineUsesCallEvidence() throws {
        let view = try SourceFiles.text("RailMap/Journeys/RideDetailView.swift")
        #expect(view.contains("stop.callEvidence"))
        #expect(view.contains("\"ios.routeGuide.onRouteUnknown\""))
        #expect(!view.contains("inferredPass"))
        // The only remaining stop-type test is the chip that hides the two plain types.
        #expect(view.components(separatedBy: "\"pass_through\"").count - 1 == 1)
        #expect(view.contains("if stop.callEvidence == .recordedPass,\n"
            + "               stop.arrival?.isEmpty != false, stop.departure?.isEmpty != false {\n"
            + "                Text(\"レ\")"))
    }

    @Test("the on-route text exists in four languages and does not say passing")
    func onRouteTextInFourLanguages() throws {
        let strings = try SourceFiles.text("RailMap/Localization/RouteGuideStrings.swift")
        #expect(!strings.contains("ios.routeGuide.inferredPass"))
        let start = try #require(strings.range(of: "\"ios.routeGuide.onRouteUnknown\": ["))
        let rest = strings[start.upperBound...]
        let block = String(rest[..<(try #require(rest.range(of: "],"))).lowerBound])
        for language in [".en:", ".zhHans:", ".zhHant:", ".ja:"] {
            #expect(block.contains(language), "\(language)")
        }
        #expect(block.contains("On route"))
        #expect(!block.contains("Passing") && !block.contains("Inferred"))
        #expect(strings.contains("\"ios.routeGuide.passUnknown\": ["))
    }

    private func choice(_ codes: [String]) -> RailwayRouteChoices.Choice {
        let edges = zip(codes, codes.dropFirst()).map { "\($0)>\($1)" }
        let sections = edges.indices.map { index in
            RouteSection(from: codes[index], to: codes[index + 1],
                         fromN02StationCode: codes[index], toN02StationCode: codes[index + 1],
                         lineNames: ["Physical line"], lineIDs: ["line"], sectionCodes: [edges[index]])
        }
        return .init(lineIDs: ["line"], lineNames: ["Physical line"], operatorNames: [],
                     stations: codes.map { .init(code: $0, name: $0) },
                     sectionCodes: edges, routeSections: sections)
    }
}
