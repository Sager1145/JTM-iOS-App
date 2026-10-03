import Foundation
import Testing
@testable import RailCore

struct RailwayRouteEditingTests {
    private func choice(_ codes: [String], intervals: [String]? = nil) -> RailwayRouteChoices.Choice {
        let edges = intervals ?? zip(codes, codes.dropFirst()).map { "\($0)>\($1)" }
        let sections = edges.indices.map { index in
            RouteSection(from: codes[index], to: codes[index + 1],
                         fromN02StationCode: codes[index], toN02StationCode: codes[index + 1],
                         lineNames: ["Physical line"], lineIDs: ["line"], sectionCodes: [edges[index]])
        }
        return .init(lineIDs: ["line"], lineNames: ["Physical line"], operatorNames: [],
                     stations: codes.map { .init(code: $0, name: $0) },
                     sectionCodes: edges, routeSections: sections)
    }

    private func train(_ codes: [String]) -> Train {
        let route = choice(codes)
        return RailwayRouteEditing.preparing(Train(
            id: "ride", number: "Local", origin: codes[0], destination: codes.last!,
            routeSections: route.routeSections,
            stops: codes.map { Stop(name: $0, n02StationCode: $0, rideSegment: true) }))
    }

    @Test("Independent divergences use exact physical intervals even with identical station lists")
    func independentDivergences() throws {
        let first = choice(["A", "B", "C", "D", "E"], intervals: ["ab", "bc", "cd", "de"])
        let second = choice(["A", "B", "C", "D", "E"], intervals: ["AB", "bc", "CD", "de"])
        let decisions = RailwayRouteEditing.decisions(choices: [first, second])
        #expect(decisions.map(\.originCode) == ["A", "C"])
        #expect(decisions.map(\.destinationCode) == ["B", "D"])
        #expect(decisions.map { $0.options.map(\.sectionCodes) } == [[["ab"], ["AB"]], [["cd"], ["CD"]]])
        #expect(decisions.allSatisfy { $0.options.allSatisfy { $0.routeSections.count == 1 } })
    }

    @Test("A whole span remains selectable without intermediate common anchors")
    func wholeSpan() {
        let choices = [choice(["A", "B", "D"]), choice(["A", "C", "D"])]
        let decisions = RailwayRouteEditing.decisions(choices: choices)
        #expect(decisions.count == 1)
        #expect(decisions.first?.options == choices)
    }

    @Test("Generated rows fill and remove without creating authored conflicts, with stable identity")
    func generatedRows() throws {
        let original = train(["A", "D"])
        let expanded = try #require(RailwayRouteEditing.plan(train: original, choice: choice(["A", "B", "C", "D"])))
        let repeated = try #require(RailwayRouteEditing.plan(train: original, choice: choice(["A", "B", "C", "D"])))
        #expect(expanded.insertedStops == repeated.insertedStops)
        #expect(expanded.requiresConfirmation == false)
        #expect(expanded.insertedStops.allSatisfy {
            $0.stopType == "pass_through" && $0.platformNumber == nil && $0.arrival == nil
                && $0.departure == nil && $0.actualArrival == nil && $0.actualDeparture == nil
        })
        let collapsed = try #require(RailwayRouteEditing.plan(train: expanded.updatedTrain, choice: choice(["A", "D"])))
        #expect(collapsed.removedStops.map(\.name) == ["B", "C"])
        #expect(collapsed.conflictingStops.isEmpty)
        #expect(collapsed.updatedTrain.stops == original.stops)
    }

    @Test("Authored and edited generated visits require explicit removal confirmation")
    func protectedConflicts() throws {
        let original = train(["A", "B", "D"])
        let conflict = try #require(RailwayRouteEditing.plan(train: original, choice: choice(["A", "D"])))
        #expect(conflict.requiresConfirmation)
        #expect(conflict.conflictingStops == [original.stops[1]])
        #expect(conflict.removedStops.isEmpty)
        let expanded = try #require(RailwayRouteEditing.plan(train: train(["A", "D"]), choice: choice(["A", "B", "D"])))
        for edit in 0..<4 {
            var edited = expanded.updatedTrain
            switch edit {
            case 0: edited.stops[1].actualArrival = "09:10"
            case 1: edited.stops[1].name = "Edited name"
            case 2: edited.stops[1].routeEditing?.generatedBy = nil
            default: edited.stops[1].rideSegment = false
            }
            let proposal = try #require(RailwayRouteEditing.plan(train: edited, choice: choice(["A", "D"])))
            #expect(proposal.conflictingStops == [edited.stops[1]])
        }
    }

    @Test("Boundary and common visits retain every field, and outside sections remain exact")
    func preservePayloadAndSections() throws {
        var original = train(["X", "A", "B", "D", "Z"])
        original.stops[2].name = "Authored B name"
        original.stops[2].platformNumber = 3
        original.stops[2].arrival = "09:10"
        original.stops[2].departure = "09:11"
        original.stops[2].actualArrival = "09:12"
        original.stops[2].actualDeparture = "09:13"
        original.stops[2].stopType = "passenger_stop"
        original.routeSections?[1].number = "123"
        original.routeSections?[1].name = "Service"
        original.routeSections?[2].number = "123"
        original.routeSections?[2].name = "Service"
        original.routeSections?[0].from = nil
        original.routeSections?[3].operatorNames = ["Outside"]
        let plan = try #require(RailwayRouteEditing.plan(
            train: original, choice: choice(["A", "B", "C", "D"]),
            fromVisitID: original.stops[1].routeEditing?.visitID,
            toVisitID: original.stops[3].routeEditing?.visitID))
        #expect(plan.updatedTrain.stops[0...2] == original.stops[0...2])
        #expect(Array(plan.updatedTrain.stops.suffix(2)) == Array(original.stops.suffix(2)))
        #expect(plan.updatedTrain.routeSections?.first == original.routeSections?.first)
        #expect(plan.updatedTrain.routeSections?.last == original.routeSections?.last)
        #expect(plan.updatedTrain.routeSections?[1...3].map(\.number) == ["123", "123", "123"])
        #expect(plan.updatedTrain.routeSections?[1...3].map(\.name) == ["Service", "Service", "Service"])
        #expect(plan.updatedTrain.routeSections?[1...3].flatMap { $0.sectionCodes ?? [] } == ["A>B", "B>C", "C>D"])
    }

    @Test("Legacy stops stay authored and optional editing metadata survives every persistence path")
    func metadataRoundTrip() throws {
        let legacy = Data("""
        {"name":"A","n02_station_code":"A","arrival":null,"departure":null,"stop_type":"origin","ride_segment":true}
        """.utf8)
        let stop = try JSONDecoder().decode(Stop.self, from: legacy)
        #expect(stop.routeEditing == nil)
        let legacyObject = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(stop)) as? [String: Any])
        #expect(legacyObject["route_editing"] == nil)
        let expanded = try #require(RailwayRouteEditing.plan(train: train(["A", "D"]), choice: choice(["A", "B", "D"]))).updatedTrain
        let direct = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(expanded))
        let normalized = TrainValidation.normalizeExportTrain(expanded)
        let imported = try TrainValidation.normalizeImportedTrain(StoreOperations.json(normalized))
        #expect(direct.stops == expanded.stops)
        #expect(normalized.stops == expanded.stops)
        #expect(imported.stops == expanded.stops)
        #expect(imported.routeSections?.flatMap { $0.sectionCodes ?? [] } == ["A>B", "B>D"])
    }

    @Test("Manual deletion or insertion before correction retains shifted outside interval metadata")
    func shiftedOutsideSections() throws {
        var original = train(["X", "A", "B", "D", "Z"])
        original.routeSections?[3].number = "Outside number"
        original.routeSections?[3].name = "Outside service"
        original.routeSections?[3].operatorNames = ["Outside operator"]
        original.routeSections?[3].from = nil
        let outside = original.routeSections?.last
        for deleting in [true, false] {
            var changed = original
            if deleting { changed.stops.remove(at: 1) }
            else { changed.stops.insert(Stop(name: "Added", n02StationCode: "Y"), at: 1) }
            let plan = try #require(RailwayRouteEditing.plan(
                train: changed, choice: choice(["B", "C", "D"])))
            #expect(plan.updatedTrain.routeSections?.last == outside)
            var later = plan.updatedTrain
            later.stops.insert(Stop(name: "Later", n02StationCode: "W"), at: 0)
            let restored = try #require(plan.undo.restore(in: later))
            #expect(restored.stops.first?.n02StationCode == "W")
            #expect(restored.routeSections?.last == outside)
        }
    }

    @Test("Shifted duplicate endpoint pairs do not guess occurrence-specific service labels")
    func ambiguousShiftedSections() throws {
        var original = train(["X", "A", "B", "A", "B", "D", "Z"])
        original.routeSections?[1].number = "First occurrence"
        original.routeSections?[3].number = "Second occurrence"
        original.stops.remove(at: 0)
        let plan = try #require(RailwayRouteEditing.plan(
            train: original, choice: choice(["D", "C", "Z"])))
        #expect(plan.updatedTrain.routeSections?[0].number == nil)
        #expect(plan.updatedTrain.routeSections?[2].number == nil)
        #expect(plan.updatedTrain.routeSections?[0].sectionCodes == nil)
        #expect(plan.updatedTrain.routeSections?[2].sectionCodes == nil)
    }

    @Test("Expanding one service portion keeps its own number across the inserted visit")
    func preserveThroughServiceLabels() throws {
        var original = train(["A", "B", "D"])
        original.routeSections?[0].number = "123"
        original.routeSections?[0].name = "First service"
        original.routeSections?[1].number = "456"
        original.routeSections?[1].name = "Through service"
        let plan = try #require(RailwayRouteEditing.plan(
            train: original, choice: choice(["A", "B", "C", "D"])))
        #expect(plan.updatedTrain.routeSections?.map(\.number) == ["123", "456", "456"])
        #expect(plan.updatedTrain.routeSections?.map(\.name) == [
            "First service", "Through service", "Through service"])
    }

    @Test("Repeated physical station visits retain payload in traversal order")
    func repeatedVisitOrder() throws {
        var original = train(["A", "B", "C", "B", "D"])
        original.stops[1].arrival = "09:10"
        original.stops[3].arrival = "10:10"
        let plan = try #require(RailwayRouteEditing.plan(train: original, choice: choice(["A", "B", "X", "C", "B", "D"])))
        #expect(plan.updatedTrain.stops[1] == original.stops[1])
        #expect(plan.updatedTrain.stops[4] == original.stops[3])
        #expect(plan.conflictingStops.isEmpty)
        #expect(RailwayRouteEditing.plan(train: original, choice: choice(["B", "D"])) == nil)
        #expect(RailwayRouteEditing.plan(train: original, choice: choice(["B", "D"]),
                                      fromVisitID: original.stops[3].routeEditing?.visitID) != nil)
        #expect(RailwayRouteEditing.plan(train: original, choice: choice(["A", "B", "A"])) == nil)
    }

    @Test("Inserted repeated visits cannot reuse a retained occurrence identity")
    func repeatedGeneratedIdentity() throws {
        let first = try #require(RailwayRouteEditing.plan(
            train: train(["A", "D"]), choice: choice(["A", "B", "C", "B", "D"])))
        let nextChoice = choice(["A", "C", "B", "X", "B", "D"])
        let next = try #require(RailwayRouteEditing.plan(train: first.updatedTrain, choice: nextChoice))
        let repeated = try #require(RailwayRouteEditing.plan(train: first.updatedTrain, choice: nextChoice))
        let ids = next.updatedTrain.stops.compactMap { $0.routeEditing?.visitID }
        #expect(Set(ids).count == next.updatedTrain.stops.count)
        #expect(next.updatedTrain.stops[2] == first.updatedTrain.stops[3])
        #expect(next.updatedTrain.stops[2].routeEditing?.visitID != next.updatedTrain.stops[4].routeEditing?.visitID)
        #expect(next.insertedStops == repeated.insertedStops)
    }

    @Test("Generated identity collisions with outside visits resolve without changing outside payload")
    func outsideGeneratedIdentity() throws {
        var original = train(["X", "A", "D", "Z"])
        let selected = choice(["A", "B", "D"])
        let initial = try #require(RailwayRouteEditing.plan(train: original, choice: selected))
        original.stops[0].routeEditing?.visitID = try #require(initial.insertedStops.first?.routeEditing?.visitID)
        let next = try #require(RailwayRouteEditing.plan(train: original, choice: selected))
        let repeated = try #require(RailwayRouteEditing.plan(train: original, choice: selected))
        #expect(next.updatedTrain.stops[0] == original.stops[0])
        #expect(next.insertedStops.first?.routeEditing?.visitID != original.stops[0].routeEditing?.visitID)
        #expect(next.insertedStops == repeated.insertedStops)
    }

    @Test("Undo preserves unrelated notes, dates and outside stop changes")
    func undoPreservesUnrelatedEdits() throws {
        let original = train(["X", "A", "D", "Z"])
        let plan = try #require(RailwayRouteEditing.plan(train: original, choice: choice(["A", "B", "D"])))
        var edited = plan.updatedTrain
        edited.notes = "Added after correction"
        edited.date = "2026-10-01"
        edited.stops[0].platformNumber = 4
        let restored = try #require(plan.undo.restore(in: edited))
        #expect(restored.notes == edited.notes)
        #expect(restored.date == edited.date)
        #expect(restored.stops[0] == edited.stops[0])
        #expect(Array(restored.stops.dropFirst()) == Array(original.stops.dropFirst()))
        #expect(restored.routeSections == original.routeSections)
        edited.stops[2].arrival = "12:00"
        #expect(plan.undo.restore(in: edited) == nil)
    }
}
