import Foundation
import RailCore
import Testing

@testable import RailPresentation

/// Which packages a journey is solved against.
///
/// Everything here is checked against the codes the shipped stores actually
/// carry. The two cross-border samples are real records —
/// `app/data/train-store-us.json`'s *Adirondack 69* and
/// `app/data/train-store-ca.json`'s *Maple Leaf 64* — and their border hop is
/// the pair `US-AMTRAK-RSP` → `CA-AMTRAK-RSP`, Rouses Point on each side of
/// the line, which is what makes the crossing visible to a rule that reads
/// nothing but the strings.
struct RegionScopeRuleTests {

    /// The catalog this app ships, spelled the way `Region.scopeRule` spells
    /// it: `allCases` order, Japan's six-digit N02 codes, Japan as the
    /// fallback for a ride that names nothing.
    private let rule = RegionScopeRule(
        regionCodes: ["jp", "tw", "hk", "mo", "kr", "us", "ca"],
        numericCodeRegion: "jp",
        fallback: "jp")

    private func stop(_ code: String?) -> Stop {
        Stop(name: code ?? "", n02StationCode: code, rideSegment: true)
    }

    private func train(
        region: String? = nil, stops: [String?], sections: [(String?, String?)] = []
    ) -> Train {
        Train(
            id: "t1", number: "1", origin: "", destination: "",
            routeSections: sections.isEmpty
                ? nil
                : sections.map {
                    RouteSection(fromN02StationCode: $0.0, toN02StationCode: $0.1)
                },
            stops: stops.map(stop),
            region: region)
    }

    // MARK: - one station code

    /// Japan's are bare digits; everything else names its region before the
    /// first dash, in either case.
    @Test("a station code names its region, or nothing")
    func stationCodes() {
        #expect(rule.regionCode(forStationCode: "005853") == "jp")
        #expect(rule.regionCode(forStationCode: "us-official-chicago-union") == "us")
        #expect(rule.regionCode(forStationCode: "US-AMTRAK-RSP") == "us")
        #expect(rule.regionCode(forStationCode: "CA-AMTRAK-RSP") == "ca")
        #expect(rule.regionCode(forStationCode: "CA-GO-TRANSIT-AD") == "ca")
        #expect(rule.regionCode(forStationCode: "kr-official-busan") == "kr")
        // An operator code that merely begins with its own region's letters.
        #expect(rule.regionCode(forStationCode: "KR-GYEONGBUSEON-BUSAN") == "kr")
    }

    /// The codes a train store carries outside Japan are the operator's own
    /// and name no region at all. Answering `nil` is what sends them to the
    /// app's `RegionCodeIndex`, which reads the shipped station tables; a
    /// guess here would be permanent.
    @Test("an operator's own code names nothing rather than guessing")
    func operatorCodesNameNothing() {
        #expect(rule.regionCode(forStationCode: "TYMC-A13") == nil)
        #expect(rule.regionCode(forStationCode: "AEL-MTR-HOK") == nil)
        #expect(rule.regionCode(forStationCode: "MLM-TAIPA-MLM-BARRA") == nil)
        // Digits, but not SIX of them. The length is written down rather than
        // "all digits" so that a numeric code from another country's operator
        // cannot be read as a Japanese one.
        #expect(rule.regionCode(forStationCode: "00385") == nil)
        #expect(rule.regionCode(forStationCode: "0058530") == nil)
        #expect(rule.regionCode(forStationCode: "003859") == "jp")
        #expect(rule.regionCode(forStationCode: "N02_005c") == nil)
        #expect(rule.regionCode(forStationCode: "") == nil)
        #expect(rule.regionCode(forStationCode: nil) == nil)
        // A prefix that looks like a region but is not one in this catalog.
        #expect(rule.regionCode(forStationCode: "MX-FERROMEX-1") == nil)
    }

    // MARK: - one journey

    @Test("a journey inside one country names one region")
    func singleRegion() {
        let acela = train(region: "us", stops: ["US-AMTRAK-NYP", "US-AMTRAK-BOS"])
        #expect(rule.regionCodesTouched(acela) == ["us"])
        #expect(rule.matched(acela) == "us")
        #expect(rule.scopeKey(rule.regionCodesTouched(acela)) == "us")
    }

    /// *Adirondack 69*, New York to Montréal. The record is filed under `us`
    /// and its last three stops are Canadian, which is the whole case this
    /// type exists for: asking the United States' graph to find Montréal is
    /// how a journey comes back 無法繪製路線.
    @Test("the Adirondack reaches two packages, starting in its own")
    func adirondackCrossesSouthToNorth() {
        let adirondack = train(
            region: "us",
            stops: [
                "US-AMTRAK-NYP", "US-AMTRAK-ALB", "US-AMTRAK-PLB", "US-AMTRAK-RSP",
                "CA-AMTRAK-RSP", "CA-AMTRAK-SLQ", "CA-AMTRAK-MTR",
            ],
            sections: [("US-AMTRAK-RSP", "CA-AMTRAK-RSP")])
        #expect(rule.regionCodesTouched(adirondack) == ["us", "ca"])
        #expect(rule.matched(adirondack) == "us")
    }

    /// *Maple Leaf 64*, Toronto to New York — the same border the other way.
    @Test("the Maple Leaf reaches the same two, starting in the other one")
    func mapleLeafCrossesNorthToSouth() {
        let mapleLeaf = train(
            region: "ca",
            stops: ["CA-VIA-TRTO", "CA-AMTRAK-NIAG", "US-AMTRAK-NFL", "US-AMTRAK-NYP"])
        #expect(rule.regionCodesTouched(mapleLeaf) == ["ca", "us"])
        #expect(rule.matched(mapleLeaf) == "ca")
    }

    /// The two directions of one crossing share a graph. This is the property
    /// `DisplayNetworkCache` files its merged network under, and the reason
    /// the key is sorted by the catalog rather than by the ride.
    @Test("both directions of a crossing key the same working set")
    func crossingsShareOneKey() {
        #expect(rule.scopeKey(["us", "ca"]) == "us+ca")
        #expect(rule.scopeKey(["ca", "us"]) == "us+ca")
        // …and the CONTENT of that working set is laid down in one order too,
        // whichever direction asked for it first. A `RouteNetwork`'s name
        // index is insertion-ordered, and the four cross-border services are
        // one name over two lines.
        #expect(rule.canonicalOrder(["us", "ca"]) == ["us", "ca"])
        #expect(rule.canonicalOrder(["ca", "us"]) == ["us", "ca"])
    }

    /// The catalog's order, not the alphabet's and not the ride's.
    @Test("the canonical order is the catalog's")
    func canonicalOrderIsTheCatalogs() {
        #expect(rule.canonicalOrder(["ca", "jp", "kr"]) == ["jp", "kr", "ca"])
        #expect(rule.canonicalOrder(["mx", "us"]) == ["us"])
        #expect(rule.canonicalOrder([]).isEmpty)
        #expect(rule.scopeKey(["kr", "hk", "tw"]) == "tw+hk+kr")
    }

    /// A single region is its own key, and a journey that names none still
    /// has to be given a package to be drawn against.
    @Test("a journey that names nothing falls back rather than answering none")
    func fallback() {
        let untagged = train(stops: ["TYMC-A13", "TYMC-A14"])
        #expect(rule.matched(untagged) == nil)
        #expect(rule.regionCodesTouched(untagged) == ["jp"])
        #expect(rule.scopeKey([]) == "jp")
        #expect(rule.scopeKey(["mo"]) == "mo")
    }

    /// A `region` this build does not recognise is a stale or foreign tag, and
    /// it may not stand in front of codes that actually say something.
    @Test("an unknown declared region is ignored, not trusted")
    func unknownDeclaredRegion() {
        let mislabelled = train(region: "xx", stops: ["US-AMTRAK-NYP"])
        #expect(rule.matched(mislabelled) == "us")
        #expect(rule.regionCodesTouched(mislabelled) == ["us"])
    }

    /// The sections are consulted after the stops, and they are what answers
    /// for a record whose stops carry no codes at all.
    @Test("the route sections answer when the stops do not")
    func sectionsAnswerWhenStopsDoNot() {
        let sectionsOnly = train(
            stops: [nil, nil],
            sections: [("US-AMTRAK-RSP", "CA-AMTRAK-RSP")])
        #expect(rule.matched(sectionsOnly) == "us")
        #expect(rule.regionCodesTouched(sectionsOnly) == ["us", "ca"])
    }

    /// A rule handed no catalog claims nothing. It exists so a caller can be
    /// built before it has one, not so that one can be skipped.
    @Test("an empty catalog recognises no code")
    func emptyCatalog() {
        #expect(RegionScopeRule.empty.regionCode(forStationCode: "US-AMTRAK-NYP") == nil)
        #expect(RegionScopeRule.empty.regionCode(forStationCode: "005853") == nil)
        #expect(RegionScopeRule.empty.scopeKey(["us", "ca"]) == "")
    }
}
