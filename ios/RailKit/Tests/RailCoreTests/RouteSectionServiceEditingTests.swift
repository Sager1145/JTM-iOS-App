import Foundation
import Testing
@testable import RailCore

struct RouteSectionServiceEditingTests {
    private var train: Train {
        Train(id: "through", number: "Through service", origin: "A", destination: "D",
              routeSections: [
                RouteSection(fromN02StationCode: "000001", toN02StationCode: "000002",
                             lineNames: ["First line"], operatorNames: ["First operator"], number: "101A"),
                RouteSection(from: "B", to: "C", number: "202B"),
                RouteSection(from: "C", to: "D", lineNames: ["Third line"], number: "303C"),
              ], stops: [
                Stop(name: "A", n02StationCode: "000001"),
                Stop(name: "B", n02StationCode: "000002"),
                Stop(name: "C", n02StationCode: "000003"),
                Stop(name: "D", n02StationCode: "000004"),
              ])
    }

    @Test func appliesToEachAdjacentPairWithoutChangingOtherLegsOrTrainIdentity() throws {
        let original = train
        let updated = RouteSectionServiceEditing.applying(
            RouteSectionServiceInfo(lineNames: [" Second line ", "Second line"],
                                    operatorNames: ["Second operator"], number: " 505D "),
            to: original, fromStopIndex: 1, toStopIndex: 3)
        let sections = try #require(updated.routeSections)
        #expect(sections.count == 3)
        #expect(sections[0] == StoreOperations.rideRouteSections(for: original)[0])
        #expect(sections[1].lineNames == ["Second line"])
        #expect(sections[2].operatorNames == ["Second operator"])
        #expect(sections[1].number == "505D" && sections[2].number == "505D")
        #expect(updated.stops == original.stops && updated.number == original.number)
        let exported = TrainValidation.normalizeExportTrain(updated, country: "jp", stations: .empty)
        let decoded = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(exported))
        #expect(decoded.routeSections?.map(\.number) == ["101A", "505D", "505D"])
    }

    @Test func alignsMetadataToStationPairsAfterStopInsertion() throws {
        var original = train
        original.stops.insert(Stop(name: "X", n02StationCode: "000005"), at: 1)
        let updated = RouteSectionServiceEditing.applying(
            RouteSectionServiceInfo(operatorNames: ["New operator"], number: "9"),
            to: original, fromStopIndex: 0, toStopIndex: 1)
        let sections = try #require(updated.routeSections)
        #expect(sections[0].toN02StationCode == "000005")
        #expect(sections[1].number == nil)
        #expect(sections[2].number == "202B")
        #expect(sections[3].number == "303C")
    }

    @Test func invalidRangesLeaveDraftUntouched() {
        for range in [(-1, 2), (0, 4), (2, 2), (3, 1)] {
            #expect(RouteSectionServiceEditing.applying(
                RouteSectionServiceInfo(number: "New"), to: train,
                fromStopIndex: range.0, toStopIndex: range.1) == train)
        }
    }

    @Test func clearingMetadataKeepsEndpointCodes() throws {
        let updated = RouteSectionServiceEditing.applying(
            RouteSectionServiceInfo(), to: train, fromStopIndex: 0, toStopIndex: 1)
        let section = try #require(updated.routeSections?.first)
        #expect(section.fromN02StationCode == "000001")
        #expect(section.toN02StationCode == "000002")
        #expect(RouteSectionServiceInfo(section: section).isEmpty)
    }

    @Test func routeChangesReleaseOldPhysicalConstraintsButNumberEditsRetainThem() throws {
        var original = train
        original.routeSections?[0].lineIDs = ["old-line-id"]
        original.routeSections?[0].sectionCodes = ["old-physical-section"]
        let renumbered = RouteSectionServiceEditing.applying(
            RouteSectionServiceInfo(lineNames: ["First line"], operatorNames: ["First operator"], number: "102A"),
            to: original, fromStopIndex: 0, toStopIndex: 1)
        let retained = try #require(renumbered.routeSections?.first)
        #expect(retained.lineIDs == ["old-line-id"])
        #expect(retained.sectionCodes == ["old-physical-section"])
        #expect(retained.number == "102A")
        for info in [
            RouteSectionServiceInfo(lineNames: ["New line"], operatorNames: ["First operator"]),
            RouteSectionServiceInfo(lineNames: ["First line"], operatorNames: ["New operator"])
        ] {
            let changed = RouteSectionServiceEditing.applying(
                info, to: original, fromStopIndex: 0, toStopIndex: 1)
            let section = try #require(changed.routeSections?.first)
            #expect(section.lineIDs == nil && section.sectionCodes == nil)
            #expect(section.fromN02StationCode == "000001" && section.toN02StationCode == "000002")
            #expect(changed.routeSections?[1] == original.routeSections?[1])
        }
    }
}
