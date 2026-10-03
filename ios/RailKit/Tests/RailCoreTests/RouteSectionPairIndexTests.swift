import Testing
@testable import RailCore

struct RouteSectionPairIndexTests {
    private func sections(_ stops: [Stop], _ sections: [RouteSection]) -> [RouteSection] {
        StoreOperations.rideRouteSections(for: Train(
            id: "matching", number: "Test", origin: stops.first?.name ?? "",
            destination: stops.last?.name ?? "", routeSections: sections, stops: stops))
    }

    @Test func sameIndexMatchWinsOverEarlierDuplicate() {
        let result = sections([Stop(name: "X"), Stop(name: "A"), Stop(name: "B")], [
            RouteSection(from: "A", to: "B", number: "earlier"),
            RouteSection(from: "A", to: "B", number: "aligned"),
        ])
        #expect(result.map(\.number) == [nil, "aligned"])
    }

    @Test(arguments: [true, false]) func fallbackUsesEarliestCodeOrNameMatch(nameFirst: Bool) {
        let name = RouteSection(from: "A", to: "B", number: "name")
        let code = RouteSection(from: "Other A", to: "Other B",
                                fromN02StationCode: "000001", toN02StationCode: "000002",
                                number: "code")
        let filler = RouteSection(from: "Unrelated", to: "Pair", number: "filler")
        let candidates = [filler] + (nameFirst ? [name, code] : [code, name])
        let result = sections([
            Stop(name: "A", n02StationCode: "000001"),
            Stop(name: "B", n02StationCode: "000002"),
        ], candidates)
        #expect(result.first?.number == (nameFirst ? "name" : "code"))
    }

    @Test func fallbackCanonicalizesAliasesAndKeepsFirstDuplicate() {
        let result = sections([
            Stop(name: "Origin", n02StationCode: "EAL-LOW-MTR-ADM"),
            Stop(name: "Destination", n02StationCode: "LR-505-LR-100"),
        ], [
            RouteSection(from: "Unrelated", to: "Pair"),
            RouteSection(fromN02StationCode: "MTR-ADM", toN02StationCode: "LR-100",
                         number: "first"),
            RouteSection(fromN02StationCode: "SIL-MTR-ADM", toN02StationCode: "LR-100",
                         number: "second"),
        ])
        #expect(result.first?.number == "first")
        #expect(result.first?.fromN02StationCode == "MTR-ADM")
        #expect(result.first?.toN02StationCode == "LR-100")
    }

    @Test func fallbackDistinguishesCanonicalUnicodeEquivalents() {
        let decomposed = "e\u{301}"
        let composed = "\u{e9}"
        #expect(decomposed == composed)
        let result = sections([Stop(name: composed), Stop(name: "B")], [
            RouteSection(from: "Unrelated", to: "Pair"),
            RouteSection(from: decomposed, to: "B", number: "different UTF-16"),
            RouteSection(from: composed, to: "B", number: "exact UTF-16"),
        ])
        #expect(result.first?.number == "exact UTF-16")
    }

    @Test func incompleteCodesAndEmptyNamesDoNotReuseMetadata() {
        let result = sections([
            Stop(name: "", n02StationCode: "000001"), Stop(name: "B"),
        ], [
            RouteSection(from: "Unrelated", to: "Pair"),
            RouteSection(from: "", to: "B", fromN02StationCode: "000001",
                         toN02StationCode: "", number: "invalid match"),
        ])
        #expect(result.count == 1)
        #expect(result.first?.number == nil)
        #expect(result.first?.fromN02StationCode == "000001")
    }

    @Test func reversedLongRecordReusesMetadataAndSynthesizesInsertedPairs() {
        let count = 1_000
        var stops = (0...count).map { Stop(name: "Station \($0)") }
        let recorded = (0..<count).map {
            RouteSection(from: "Station \($0)", to: "Station \($0 + 1)", number: "Leg \($0)")
        }
        stops.insert(Stop(name: "Inserted"), at: 501)
        let result = sections(stops, Array(recorded.reversed()))
        #expect(result.count == count + 1)
        #expect(result[499].number == "Leg 499")
        #expect(result[500].number == nil && result[501].number == nil)
        #expect(result[500].to == "Inserted" && result[501].from == "Inserted")
        #expect(result[502].number == "Leg 501")
        #expect(result.last?.number == "Leg 999")
    }
}
