import Testing

@testable import RailCore

// A dated screenshot may resolve a call onto a retired station only through
// the registry. A `history:` code is bookkeeping, never an `n02_station_code`.
// With no registry both calls stay unresolved.

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

private func retiredIdentity() -> RegistryIdentity {
    RegistryIdentity(bundle: RegistryBundle(
        region: "jp", run: 1,
        stationCodes: ["100001": "st:jp:1", "history:mashike-1": "st:jp:2"],
        stations: [
            "st:jp:1": RegistryStationRecord(
                cx: "cx:1", group: "asahikawa", codes: ["100001"], op: "op:jp:1",
                name: "旭川", lines: ["lp:1"]),
            "st:jp:2": RegistryStationRecord(
                cx: "cx:2", group: "mashike", codes: ["history:mashike-1"], op: "op:jp:1",
                name: "増毛", lines: ["lp:2"]),
        ],
        lineParts: [
            "lp:1": RegistryLinePartRecord(packageLine: "souya", name: "宗谷本線", op: "op:jp:1", rank: 1),
            "lp:2": RegistryLinePartRecord(packageLine: "rumoi", name: "留萌本線", op: "op:jp:1", rank: 1),
        ]))
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
        let result = try RegistryIdentityTestGate.withProvider({ region in
            region == "jp" ? retiredIdentity() : nil
        }) {
            TransferGuide.build(
                route: route,
                options: TransferGuide.BuildOptions(date: "2016-03-01", ridden: true),
                stations: widenedIndex())
        }

        #expect(result.unresolved.isEmpty)
        let train = try #require(result.trains.first)
        #expect(train.stops.map(\.name) == ["旭川", "増毛"])
        #expect(train.stops[0].n02StationCode == "100001")
        #expect(train.stops[0].stationID == "st:jp:1")
        #expect(train.stops[1].n02StationCode == nil)
        #expect(train.stops[1].stationID == "st:jp:2")

        let section = try #require(train.routeSections?.first)
        #expect(section.fromN02StationCode == "100001")
        #expect(section.toN02StationCode == nil)
    }

    @Test("no registry leaves both calls unresolved")
    func absentRegistryWritesNoCodes() throws {
        let result = TransferGuide.build(
            route: TransferGuide.Route(legs: [retiredLeg()]),
            options: TransferGuide.BuildOptions(date: "2016-03-01", ridden: true),
            stations: widenedIndex())
        let train = try #require(result.trains.first)
        #expect(result.unresolved == ["旭川", "増毛"])
        #expect(result.resolvedCalls == 0)
        #expect(train.stops.map(\.n02StationCode) == [nil, nil])
        #expect(train.stops.map(\.stationID) == [nil, nil])
        #expect(train.company == "")
        let section = try #require(train.routeSections?.first)
        #expect(section.fromN02StationCode == nil)
        #expect(section.toN02StationCode == nil)
    }
}
