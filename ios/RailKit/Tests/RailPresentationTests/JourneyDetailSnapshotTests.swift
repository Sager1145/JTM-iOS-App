import RailCore
import Testing
@testable import RailPresentation

struct JourneyDetailSnapshotTests {
    @Test func namingIndexPreservesFirstNonemptyCodeAndRecordedCodePrecedence() {
        let train = Train(id: "names", number: "Test", origin: "Ａ", destination: "B", stops: [
            Stop(name: "Ａ"), Stop(name: "A", n02StationCode: ""),
            Stop(name: "A", n02StationCode: "first"), Stop(name: "Ａ", n02StationCode: "later"),
            Stop(name: "", n02StationCode: "unnamed"), Stop(name: "B"),
        ])
        let detail = JourneyDetailSnapshot(train: train)
        #expect(detail.stationCode(named: "Ａ", recorded: nil) == "first")
        #expect(detail.stationCode(named: "A", recorded: "explicit") == "explicit")
        #expect(detail.stationCode(named: "A", recorded: "") == "")
        #expect(detail.stationCode(named: "", recorded: nil) == nil)
        #expect(detail.stationCode(named: "B", recorded: nil) == nil)
    }

    @Test func preservesReorderedSectionMetadataAndStopOrder() {
        let train = Train(id: "sections", number: "Test", origin: "A", destination: "C",
                          routeSections: [
                            RouteSection(from: "B", to: "C", lineNames: ["Second"], number: "2"),
                            RouteSection(from: "A", to: "B", lineNames: ["First"], number: "1"),
                          ], stops: [Stop(name: "A"), Stop(name: "B"), Stop(name: "C")])
        let detail = JourneyDetailSnapshot(train: train)
        #expect(detail.train == train)
        #expect(detail.sections.map(\.number) == ["1", "2"])
        #expect(detail.sections.map(\.lineNames) == [["First"], ["Second"]])
    }
}
