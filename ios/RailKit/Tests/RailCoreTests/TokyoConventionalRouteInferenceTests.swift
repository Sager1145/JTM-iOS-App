import Foundation
import Testing
@testable import RailCore

struct TokyoConventionalRouteInferenceTests {
    private func sparse(reverse: Bool = false) -> Train {
        var visits = [Stop(name: "東京", n02StationCode: "003766", departure: "10:00"),
                      Stop(name: "品川", n02StationCode: "004095", arrival: "10:15")]
        if reverse { visits.reverse() }
        return Train(id: "tokyo-default", date: "2026-10-01", number: "Local",
                     trainType: "local", origin: visits[0].name, destination: visits[1].name,
                     routeSections: [RouteSection(from: visits[0].name, to: visits[1].name,
                        fromN02StationCode: visits[0].n02StationCode,
                        toN02StationCode: visits[1].n02StationCode, number: "1234M")],
                     stops: visits, region: "jp")
    }

    @Test("Sparse Tokyo corridor uses the requested tunnel default in both directions", arguments: [false, true])
    func sparseDefault(reverse: Bool) throws {
        let train = sparse(reverse: reverse)
        let result = TokyoConventionalRouteInference.applying(to: train)
        let section = try #require(result.routeSections?.first)
        let codes = ["jp-東日本旅客鉄道-総武線-3@003766:003872",
                     "jp-東日本旅客鉄道-総武線-3@003872:004095"]
        #expect(section.sectionCodes == (reverse ? Array(codes.reversed()) : codes))
        #expect(section.lineIDs == [TokyoConventionalRouteInference.tunnelLineID])
        #expect(section.number == "1234M")
        #expect(result.stops == train.stops)
        #expect(TokyoConventionalRouteInference.applying(to: result) == result)
    }

    @Test("An authored Yurakucho or other surface-only visit prevents tunnel inference")
    func surfaceEvidence() {
        for (code, name) in [("003795", "有楽町"), ("003949", "浜松町"), ("004000", "田町")] {
            var train = sparse()
            train.stops.insert(Stop(name: name, n02StationCode: code), at: 1)
            #expect(TokyoConventionalRouteInference.applying(to: train) == train)
        }
    }

    @Test("Manual physical selections and explicit surface hints remain unchanged")
    func selectedRoute() {
        var train = sparse()
        train.routeSections?[0].sectionCodes = ["manual@a:b"]
        #expect(TokyoConventionalRouteInference.applying(to: train) == train)
        train = sparse()
        train.routeSections?[0].lineIDs = [TokyoConventionalRouteInference.surfaceLineID]
        #expect(TokyoConventionalRouteInference.applying(to: train) == train)
        train = sparse()
        train.routeSections?[0].lineNames = ["東海道線"]
        #expect(TokyoConventionalRouteInference.applying(to: train) == train)
    }

    @Test("The default does not affect Shinkansen, other countries or non-JR services")
    func otherServices() {
        var train = sparse()
        train.trainType = "highSpeed"
        #expect(TokyoConventionalRouteInference.applying(to: train) == train)
        train = sparse()
        train.region = "tw"
        #expect(TokyoConventionalRouteInference.applying(to: train) == train)
        train = sparse()
        train.company = "東京メトロ"
        #expect(TokyoConventionalRouteInference.applying(to: train) == train)
    }

    @Test("Editor fills Shimbashi and its physical codes without changing endpoint times")
    func editorDefault() throws {
        let train = RailwayRouteEditing.preparing(sparse())
        let choice = try #require(TokyoConventionalRouteInference.choice(
            in: train, package: try PortFixtures.package(country: "jp")))
        #expect(choice.stations.map(\.name) == ["東京", "新橋", "品川"])
        let plan = try #require(RailwayRouteEditing.plan(train: train, choice: choice,
            fromVisitID: train.stops.first?.routeEditing?.visitID,
            toVisitID: train.stops.last?.routeEditing?.visitID))
        #expect(!plan.requiresConfirmation)
        #expect(plan.updatedTrain.stops.first?.departure == "10:00")
        #expect(plan.updatedTrain.stops.last?.arrival == "10:15")
        #expect(plan.updatedTrain.stops[1].routeEditing?.generatedBy != nil)
        let saved = TrainValidation.normalizeExportTrain(plan.updatedTrain)
        let reopened = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(saved))
        #expect(reopened.routeSections?.flatMap { $0.sectionCodes ?? [] } == choice.sectionCodes)
        #expect(TokyoConventionalRouteInference.choice(in: reopened,
            package: try PortFixtures.package(country: "jp")) == nil)
    }

    @Test("Repeated authored visits cannot disappear into a simple default path")
    func repeatedVisits() throws {
        var train = sparse()
        train.stops = [train.stops[0], Stop(name: "新橋", n02StationCode: "003872"),
            Stop(name: "東京", n02StationCode: "003766"), train.stops[1]]
        #expect(TokyoConventionalRouteInference.choice(in: train,
            package: try PortFixtures.package(country: "jp")) == nil)
    }
}
