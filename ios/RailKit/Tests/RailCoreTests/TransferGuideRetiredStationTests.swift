import Testing

@testable import RailCore

// =========================================================================
//  ADR 0011: a dated screenshot may resolve a call onto a retired station,
//  via an index widened with entries whose `code` is a `history:` id (the
//  caller's job — see `TransferGuideImport.stationIndex(forISODate:)`). A
//  history id is the index's own bookkeeping key for that complex, never a
//  real `n02_station_code`: `build(route:options:stations:)` must still
//  resolve the NAME onto the stop, but leave its station code (and any
//  section boundary built from it) nil rather than hand the solver a string
//  it cannot look up.
// =========================================================================

private func widenedIndex() -> StationIndex {
    typealias Line = StationIndex.LineRef
    let current = Line(name: "宗谷本線", operatorName: "北海道旅客鉄道", colorHex: nil)
    let retired = Line(name: "留萌本線", operatorName: "北海道旅客鉄道", colorHex: nil)
    return StationIndex([
        StationIndex.Entry(
            code: "100001", name: "旭川", coordinate: Coordinate(lon: 142.3650, lat: 43.7707),
            line: current),
        StationIndex.Entry(
            code: "history:mashike-1", name: "増毛",
            coordinate: Coordinate(lon: 141.5139, lat: 43.9014), line: retired),
    ])
}

private func retiredLeg() -> TransferGuide.Leg {
    TransferGuide.Leg(
        kind: .train, service: "普通", startsHere: true,
        calls: [
            TransferGuide.Call(name: "旭川", departure: "10:00"),
            TransferGuide.Call(name: "増毛", arrival: "12:30"),
        ])
}

@Suite("a retired station resolves without a stop-worthy code")
struct TransferGuideRetiredStationTests {

    @Test("the retired call keeps its name and loses its code; the current one keeps both")
    func retiredStopHasNoCode() throws {
        let route = TransferGuide.Route(legs: [retiredLeg()])
        let result = TransferGuide.build(
            route: route,
            options: TransferGuide.BuildOptions(date: "2016-03-01", ridden: true),
            stations: widenedIndex())

        #expect(result.unresolved.isEmpty)
        let train = try #require(result.trains.first)
        #expect(train.stops.map(\.name) == ["旭川", "増毛"])
        #expect(train.stops[0].n02StationCode == "100001")
        #expect(train.stops[1].n02StationCode == nil)

        // The section boundary built from the same resolved place must agree.
        let section = try #require(train.routeSections?.first)
        #expect(section.fromN02StationCode == "100001")
        #expect(section.toN02StationCode == nil)
    }
}
