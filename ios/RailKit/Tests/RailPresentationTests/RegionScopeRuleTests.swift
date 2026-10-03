import Foundation
import RailCore
import Testing

@testable import RailPresentation

/// Which packages a journey is solved against.
///
/// Supported station-code prefixes and generic scope ordering stay independent
/// of the order in which a caller requests packages.
struct RegionScopeRuleTests {

    /// The catalog this app ships, spelled the way `Region.scopeRule` spells
    /// it: `allCases` order, Japan's six-digit N02 codes, Japan as the
    /// fallback for a ride that names nothing.
    private let rule = RegionScopeRule(
        regionCodes: ["jp", "tw", "hk", "mo", "kr"],
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
        #expect(rule.regionCode(forStationCode: "tw-official-taipei") == "tw")
        #expect(rule.regionCode(forStationCode: "TW-OFFICIAL-TAIPEI") == "tw")
        #expect(rule.regionCode(forStationCode: "HK-OFFICIAL-CENTRAL") == "hk")
        #expect(rule.regionCode(forStationCode: "MO-OFFICIAL-BARRA") == "mo")
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
        #expect(rule.regionCode(forStationCode: "MTR-HOK") == nil)
        #expect(rule.regionCode(forStationCode: "MLM-BARRA") == nil)
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
        let regional = train(region: "kr", stops: ["KR-OFFICIAL-SEOUL", "KR-OFFICIAL-BUSAN"])
        #expect(rule.regionCodesTouched(regional) == ["kr"])
        #expect(rule.matched(regional) == "kr")
        #expect(rule.scopeKey(rule.regionCodesTouched(regional)) == "kr")
    }

    @Test("requested region order does not change the scope key or content order")
    func requestedOrdersShareOneKey() {
        #expect(rule.scopeKey(["hk", "mo"]) == "hk+mo")
        #expect(rule.scopeKey(["mo", "hk"]) == "hk+mo")
        #expect(rule.canonicalOrder(["hk", "mo"]) == ["hk", "mo"])
        #expect(rule.canonicalOrder(["mo", "hk"]) == ["hk", "mo"])
    }

    /// The catalog's order, not the alphabet's and not the ride's.
    @Test("the canonical order is the catalog's")
    func canonicalOrderIsTheCatalogs() {
        #expect(rule.canonicalOrder(["mo", "jp", "kr"]) == ["jp", "mo", "kr"])
        #expect(rule.canonicalOrder(["mx", "tw"]) == ["tw"])
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
        let mislabelled = train(region: "xx", stops: ["TW-OFFICIAL-TAIPEI"])
        #expect(rule.matched(mislabelled) == "tw")
        #expect(rule.regionCodesTouched(mislabelled) == ["tw"])
    }

    /// The sections are consulted after the stops, and they are what answers
    /// for a record whose stops carry no codes at all.
    @Test("the route sections answer when the stops do not")
    func sectionsAnswerWhenStopsDoNot() {
        let sectionsOnly = train(
            stops: [nil, nil],
            sections: [("TW-OFFICIAL-TAIPEI", "HK-OFFICIAL-CENTRAL")])
        #expect(rule.matched(sectionsOnly) == "tw")
        #expect(rule.regionCodesTouched(sectionsOnly) == ["tw", "hk"])
    }

    /// A rule handed no catalog claims nothing. It exists so a caller can be
    /// built before it has one, not so that one can be skipped.
    @Test("an empty catalog recognises no code")
    func emptyCatalog() {
        #expect(RegionScopeRule.empty.regionCode(forStationCode: "TW-OFFICIAL-TAIPEI") == nil)
        #expect(RegionScopeRule.empty.regionCode(forStationCode: "005853") == nil)
        #expect(RegionScopeRule.empty.scopeKey(["tw", "hk"]) == "")
    }
}
