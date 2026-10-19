import Foundation
import Testing
@testable import RailCore

struct RouteSectionServiceEditingTests {
    @Test("Editing or clearing an exact source-only service leg leaves its sibling intact")
    func exactSourceBoundaryServiceRange() throws {
        var first = boundary("A", "B")
        first.number = "First service"
        var second = boundary("B", "C")
        second.number = "Second service"
        let original = Train(id: "exact-service", number: "", origin: "A", destination: "C",
            routeSections: [first, second], stops: [Stop(name: "A", n02StationCode: "A"),
                                                  Stop(name: "C", n02StationCode: "C")])
        let edited = RouteSectionServiceEditing.applying(.init(lineNames: ["Source"], number: "Changed"),
            to: original, fromSectionIndex: 1, toSectionIndex: 2)
        let editedSections = try #require(edited.routeSections)
        #expect(editedSections[0] == first)
        #expect(editedSections[1].number == "Changed")
        #expect(editedSections[1].sectionCodes == second.sectionCodes)
        let cleared = RouteSectionServiceEditing.applying(.init(), to: original,
            fromSectionIndex: 0, toSectionIndex: 1)
        let clearedSections = try #require(cleared.routeSections)
        #expect(RouteSectionServiceInfo(section: clearedSections[0]).isEmpty)
        #expect(clearedSections[0].fromN02StationCode == "A" && clearedSections[0].toN02StationCode == "B")
        #expect(clearedSections[1] == second)
        #expect(edited.stops == original.stops && cleared.stops == original.stops)
        for range in [(-1, 1), (0, 3), (1, 1)] {
            #expect(RouteSectionServiceEditing.applying(.init(number: "Invalid"), to: original,
                fromSectionIndex: range.0, toSectionIndex: range.1) == original)
        }
    }

    @Test("Service edits cover the selected recorded interval, including source-only boundaries")
    func sourceBoundaryServiceRange() throws {
        let original = Train(id: "boundary-service", number: "", origin: "A", destination: "E",
            routeSections: [boundary("A", "B"), boundary("B", "C"),
                            boundary("C", "D"), boundary("D", "E")],
            stops: ["A", "C", "E"].map { Stop(name: $0, n02StationCode: $0) })
        let updated = RouteSectionServiceEditing.applying(
            .init(lineNames: ["Source"], number: "New number"), to: original,
            fromStopIndex: 1, toStopIndex: 2)
        let sections = try #require(updated.routeSections)
        #expect(Array(sections.prefix(2)) == Array(original.routeSections!.prefix(2)))
        #expect(sections.map(\.number) == ["Old number", "Old number", "New number", "New number"])
        #expect(sections.flatMap { $0.sectionCodes ?? [] } == ["A>B", "B>C", "C>D", "D>E"])
    }

    private func boundary(_ from: String, _ to: String) -> RouteSection {
        .init(from: from, to: to, fromN02StationCode: from, toN02StationCode: to,
              lineNames: ["Source"], lineIDs: ["source"], sectionCodes: [from + ">" + to], number: "Old number")
    }

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
        #expect(sections[0] == original.routeSections?[0])
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
