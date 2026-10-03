import Foundation
import Testing
@testable import RailCore

struct LocalJourneyAutofillTests {
    @Test("Only endpoints are required, and generated visits have no fabricated times")
    func endpointsOnly() throws {
        var train = ride(["A", "D"])
        train.date = "2026-10-02"
        train.stops[0].departure = "09:00"
        train.stops[1].arrival = "10:00"
        train.notes = "Preserve me"
        train.routeConfirmation = .pending
        let proposal = try #require(LocalJourneyAutofill.proposal(train: train, choice: choice(["A", "B", "C", "D"])))
        #expect(!proposal.requiresConfirmation)
        #expect(proposal.train.stops.map(\.n02StationCode) == ["A", "B", "C", "D"])
        #expect(proposal.train.stops.first?.departure == "09:00")
        #expect(proposal.train.stops.last?.arrival == "10:00")
        #expect(proposal.train.stops[1].stopType == "pass_through")
        #expect(proposal.train.stops[1].arrival == nil)
        #expect(proposal.train.stops[1].departure == nil)
        #expect(proposal.train.routeSections?.count == 3)
        #expect(proposal.train.date == train.date)
        #expect(proposal.train.notes == train.notes)
        #expect(proposal.train.routeConfirmation == .confirmed)
        #expect(!proposal.train.requiresRouteConfirmation)
    }

    @Test("A new blank draft can select both endpoints without authoring visits first")
    func blankDraft() throws {
        let train = Train(id: "new", number: "", origin: "", destination: "", stops: [Stop(name: ""), Stop(name: "")])
        let proposal = try #require(LocalJourneyAutofill.proposal(train: train, choice: choice(["A", "B", "D"])))
        #expect(!proposal.requiresConfirmation)
        #expect(proposal.train.origin == "A")
        #expect(proposal.train.destination == "D")
        #expect(proposal.train.stops.first?.stopType == "origin")
        #expect(proposal.train.stops.last?.stopType == "destination")
        #expect(proposal.train.stops.allSatisfy { !$0.rideSegment })
    }

    @Test("Changing endpoints preserves matching timed visits and protects removed authored data")
    func replaceEndpoints() throws {
        var train = ride(["A", "B", "C"])
        train.stops[1].departure = "09:12"
        train.stops[2].arrival = "09:20"
        let proposal = try #require(LocalJourneyAutofill.proposal(train: train, choice: choice(["B", "C", "D"])))
        #expect(proposal.requiresConfirmation)
        #expect(proposal.conflictingStops.map(\.name) == ["A"])
        #expect(proposal.train.stops.first?.departure == "09:12")
        #expect(proposal.train.stops[1].arrival == "09:20")
        #expect(proposal.train.stops[1].stopType == "passenger_stop")
        #expect(proposal.train.stops.first?.stopType == "origin")
        #expect(proposal.train.stops.last?.stopType == "destination")
    }

    @Test("Removing authored intermediate calls requires confirmation while repeated visits survive")
    func authoredAndRepeated() throws {
        let train = ride(["A", "B", "C", "B", "D"])
        let unchanged = try #require(LocalJourneyAutofill.proposal(train: train, choice: choice(["A", "B", "C", "B", "D"])))
        #expect(!unchanged.requiresConfirmation)
        #expect(Set(unchanged.train.stops.compactMap { $0.routeEditing?.visitID }).count == 5)
        let replaced = try #require(LocalJourneyAutofill.proposal(train: train, choice: choice(["A", "X", "D"])))
        #expect(replaced.requiresConfirmation)
        #expect(replaced.conflictingStops.map(\.name) == ["B", "C", "B"])
    }

    @Test("Each operator and physical interval survives a cross-company autofill")
    func throughRunning() throws {
        var route = choice(["A", "B", "C"])
        route.lineIDs = ["Keisei", "Toei"]
        route.operatorNames = ["京成電鉄", "東京都"]
        route.routeSections[0].lineIDs = ["Keisei"]
        route.routeSections[0].operatorNames = ["京成電鉄"]
        route.routeSections[1].lineIDs = ["Toei"]
        route.routeSections[1].operatorNames = ["東京都"]
        let proposal = try #require(LocalJourneyAutofill.proposal(train: ride(["A", "C"]), choice: route))
        #expect(proposal.train.routeSections?.map(\.lineIDs) == [["Keisei"], ["Toei"]])
        #expect(proposal.train.routeSections?.map(\.operatorNames) == [["京成電鉄"], ["東京都"]])
        #expect(proposal.train.routeSections?.flatMap { $0.sectionCodes ?? [] } == route.sectionCodes)
    }

    private func ride(_ codes: [String]) -> Train {
        Train(id: "ride", number: "", origin: codes[0], destination: codes.last!, stops: codes.enumerated().map {
            Stop(name: $0.element, n02StationCode: $0.element,
                stopType: $0.offset == 0 ? "origin" : ($0.offset == codes.count - 1 ? "destination" : "passenger_stop"),
                rideSegment: true)
        })
    }
    private func choice(_ codes: [String]) -> RailwayRouteChoices.Choice {
        let sections = (0..<(codes.count - 1)).map { index in
            RouteSection(from: codes[index], to: codes[index + 1],
                fromN02StationCode: codes[index], toN02StationCode: codes[index + 1],
                lineNames: ["Line"], operatorNames: ["Operator"], lineIDs: ["line"],
                sectionCodes: ["line@\(codes[index]):\(codes[index + 1])#\(index)"])
        }
        return .init(lineIDs: ["line"], lineNames: ["Line"], operatorNames: ["Operator"],
            stations: codes.map { .init(code: $0, name: $0) }, sectionCodes: sections.flatMap { $0.sectionCodes ?? [] },
            routeSections: sections)
    }
}
