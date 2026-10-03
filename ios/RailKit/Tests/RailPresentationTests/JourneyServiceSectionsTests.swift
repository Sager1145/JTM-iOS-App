import Foundation
import RailCore
import Testing
@testable import RailPresentation

struct JourneyServiceSectionsTests {
    private func train(_ infos: [RouteSectionServiceInfo]) -> Train {
        let stops = (0...infos.count).map {
            Stop(name: "Station \($0)", n02StationCode: String(format: "%06d", $0))
        }
        return Train(id: "through", number: "Journey caption", company: "A / B",
                     origin: stops.first!.name, destination: stops.last!.name,
                     routeSections: infos.enumerated().map { index, info in
                         RouteSection(fromN02StationCode: stops[index].n02StationCode,
                                      toN02StationCode: stops[index + 1].n02StationCode,
                                      lineNames: info.lineNames, operatorNames: info.operatorNames,
                                      number: info.number, name: info.name)
                     }, stops: stops)
    }

    @Test func groupsConsecutiveEqualSectionsWithoutMixingCompaniesAndNumbers() {
        let a = RouteSectionServiceInfo(lineNames: ["A line"], operatorNames: ["A"], number: "1201")
        let b = RouteSectionServiceInfo(lineNames: ["B line"], operatorNames: ["B"], number: "302D")
        let legs = JourneyServiceSections.legs(of: train([a, a, b, b]))
        #expect(legs.count == 2)
        #expect(legs[0].fromStopIndex == 0 && legs[0].toStopIndex == 2)
        #expect(legs[1].fromStopIndex == 2 && legs[1].toStopIndex == 4)
        #expect(legs[0].info == a && legs[1].info == b)
    }

    @Test func numberChangeCreatesALegEvenOnTheSameCompanyAndLine() {
        let a = RouteSectionServiceInfo(lineNames: ["Line"], operatorNames: ["A"], number: "1")
        let b = RouteSectionServiceInfo(lineNames: ["Line"], operatorNames: ["A"], number: "2")
        #expect(JourneyServiceSections.legs(of: train([a, b])).count == 2)
    }

    @Test func unknownSectionDoesNotJoinSeparatedServicesOrGuessANumber() {
        let known = RouteSectionServiceInfo(lineNames: ["Line"], operatorNames: ["A"])
        let legs = JourneyServiceSections.legs(of: train([known, .init(), known]))
        #expect(legs.count == 2)
        #expect(legs[0].toStopIndex == 1 && legs[1].fromStopIndex == 2)
        #expect(legs.allSatisfy { $0.info.number == nil })
        #expect(legs.allSatisfy { $0.info.operatorNames == ["A"] })
    }
}
