import Foundation
import RailPresentation
import Testing

/// The station card's 「マップで開く」 rule, checked against the answers a live
/// `MKLocalSearch` actually gave.
///
/// Every candidate list below is a transcription of one recorded search —
/// names, categories and distances as the service returned them — rather than
/// an invented one. That is deliberate: the failure this rule exists to prevent
/// is not a mis-typed string, it is picking a plausible WRONG place, and the
/// wrong places are ones no test author would have thought to write down. The
/// bus stop outside a bank ranked first for 臺北; the road stop 5 m from 金鐘
/// outranked the station 137 m away.
///
/// `ios/tools/audit-station-places.swift` is the other half. It runs this same
/// rule over a live sweep and reports the hit rate; these lock in what it found
/// so that a change to the rule has to answer for the cases it already solved.
struct StationPlaceLinkTests {

    func station(_ names: String..., country: String = "tw") -> StationPlaceLink.Station {
        StationPlaceLink.Station(names: names, country: country)
    }

    func transit(_ name: String, _ metres: Double) -> StationPlaceLink.Candidate {
        StationPlaceLink.Candidate(name: name, isPublicTransport: true, metres: metres)
    }

    func untyped(_ name: String, _ metres: Double) -> StationPlaceLink.Candidate {
        StationPlaceLink.Candidate(name: name, isPublicTransport: false, metres: metres)
    }

    // MARK: - Folding

    /// The two sides never spell a station the same way, and the fold is what
    /// makes that stop mattering.
    @Test(arguments: [
        // Traditional against the Simplified the service answers in.
        ("臺北", "台北车站"),
        ("金鐘", "金钟站"),
        ("媽閣", "妈阁"),
        ("土瓜灣", "土瓜湾"),
        // The word for "station" on either side, or both.
        ("鍾屋村", "钟屋村站"),
        ("十字路", "十字路车站"),
        ("嘉義", "嘉义火车站"),
        ("서울", "서울역"),
        // An operator's mark, glued to the front by one side and to the back
        // by the other.
        ("金鐘港鐵站", "金钟"),
        ("台中", "高铁台中站"),
        ("南科", "台湾铁路管理局南科火车站"),
        // A bracket the service adds and the package does not.
        ("五塊厝", "五块厝(地铁站)"),
    ])
    func foldsToTheSameString(_ package: String, _ apple: String) {
        #expect(StationPlaceLink.normalize(package) == StationPlaceLink.normalize(apple))
    }

    /// A live en-US sweep returns Taiwan's high-speed line and light-rail
    /// stops wearing an operator name English packages do not carry, and
    /// "Main Station" where the package and the reading both just say
    /// "Station".
    @Test(arguments: [
        ("HSR Taoyuan Station", "Taoyuan"),
        ("Taoyuan HSR Station", "Taoyuan"),
        ("High Speed Rail Taichung Station", "Taichung"),
        ("Taiwan High Speed Rail Tainan Station", "Tainan"),
        ("Light Rail Shoushan Park Station", "Shoushan Park"),
    ])
    func foldsAnOperatorOrFormNameOffAnEnglishStationName(_ apple: String, _ plain: String) {
        #expect(StationPlaceLink.normalize(apple) == StationPlaceLink.normalize(plain))
    }

    @Test
    func foldsMainStationTheSameAsStation() {
        #expect(
            StationPlaceLink.normalize("Kaohsiung Main Station")
                == StationPlaceLink.normalize("Kaohsiung Station"))
    }

    /// Apple spells Japanese romaji with macrons the packages do not carry,
    /// or the other way round, and the fold has to reach across either
    /// direction.
    @Test(arguments: [
        ("Nishijō", "nishijo station"),
        ("Hongō", "Hongo Station"),
        ("Minami-Ōtsuka", "Minami-Otsuka Station"),
    ])
    func foldsMacronedRomajiToThePlainSpelling(_ one: String, _ other: String) {
        #expect(StationPlaceLink.normalize(one) == StationPlaceLink.normalize(other))
    }

    /// ガ and カ differ only by a dakuten, and that mark is the difference
    /// between two distinct stations rather than two spellings of one — the
    /// diacritic fold must not reach into kana the way it reaches into Latin.
    @Test
    func keepsDakutenStationsApart() {
        #expect(StationPlaceLink.normalize("ガーラ湯沢") != StationPlaceLink.normalize("カーラ湯沢"))
    }

    /// Two different stations must not fold together. 新埔 is both a Taipei
    /// metro station and a TRA station 60 km away, and 左營/新左營 are two
    /// stations 400 m apart — the fold is allowed to ignore script and
    /// punctuation, never a syllable.
    @Test(arguments: [
        ("左營", "新左營"), ("大安", "大安森林公園"), ("中山", "中山國中"),
        ("東京", "東京テレポート"), ("金鐘", "九龍塘"),
    ])
    func keepsDifferentStationsApart(_ one: String, _ other: String) {
        #expect(StationPlaceLink.normalize(one) != StationPlaceLink.normalize(other))
    }

    /// An English name is a separate spelling rather than something a fold
    /// could reach — no transform turns 東京 into Tokyo. It matches because the
    /// card hands the rule every spelling it knows, which is why
    /// `StationCard.searchNames` carries the romaji and the readings and not
    /// just the header.
    @Test
    func reachesAnEnglishNamedPlaceThroughTheStationsOtherSpellings() {
        let candidates = [transit("Tokyo Station", 40)]
        #expect(StationPlaceLink.best(candidates, for: station("東京", "Tokyo", country: "jp")) == 0)
        #expect(StationPlaceLink.best(candidates, for: station("東京", country: "jp")) == nil)
    }

    /// A name made of nothing but a station word keeps it, or every such name
    /// would fold to the empty string and match all the others.
    @Test
    func neverFoldsANameAway() {
        #expect(!StationPlaceLink.normalize("駅").isEmpty)
        #expect(!StationPlaceLink.normalize("站").isEmpty)
        #expect(!StationPlaceLink.normalize("(公交站)").isEmpty)
    }

    // MARK: - Picking the place

    /// The recorded answer to 臺北, in the order the service gave it. The bus
    /// stop outside 台北银行 came first and stood 1.6 km away.
    @Test
    func picksTheStationRatherThanTheFirstResult() {
        let candidates = [
            transit("台北银行(公交站)", 1_643),
            transit("台北车站", 51),
            transit("台北车站(地铁站)", 134),
            transit("台北车站(公交站)", 114),
            transit("台北车站(东三门)(公交站)", 113),
        ]
        let index = StationPlaceLink.best(candidates, for: station("臺北", "Taipei"))
        #expect(index == 1)
    }

    /// 金鐘, recorded. Distance alone picks 金钟道(金钟港铁站)(东行方向) at 5 m;
    /// the station itself is 137 m away and is the answer.
    @Test
    func prefersItsOwnNameOverBeingMentionedInABracket() {
        let candidates = [
            transit("金钟道(金钟港铁站)(东行方向)", 5),
            transit("金钟道(金钟港铁站)(西行方向)", 28),
            transit("金钟道，太古广场(港铁金钟站)", 85),
            transit("金钟", 137),
        ]
        let index = StationPlaceLink.best(candidates, for: station("金鐘港鐵站", country: "hk"))
        #expect(index == 3)
    }

    /// Hong Kong's street-running trams have no place of their own: 汕頭街 is
    /// held as a stop on 莊士敦道. With nothing better in the list, the bracket
    /// is the station.
    @Test
    func fallsBackToTheBracketWhenNothingCarriesTheNameItself() {
        let candidates = [transit("庄士敦道(汕头街)(西行方向)", 4)]
        let index = StationPlaceLink.best(candidates, for: station("汕頭街", country: "hk"))
        #expect(index == 0)
    }

    /// …but only within 150 m. Four other tram stops on 渣華道 carry the road's
    /// name between 300 m and 1.2 km, and the service lists them in no
    /// particular order.
    @Test
    func doesNotTakeADistantStopOnTheSameRoad() {
        let candidates = [
            transit("北角道，渣华道(东行方向)", 1_223),
            transit("琴行街(渣华道)(西行方向)", 864),
        ]
        #expect(StationPlaceLink.best(candidates, for: station("渣華道", country: "hk")) == nil)
    }

    /// The bus stop at a station carries the station's name, sits metres from
    /// the platform, and is not the station. Taiwan's small TRA stops are held
    /// this way and nothing else: the card sends the captioned pin instead.
    @Test(arguments: [
        "龙泉车站(公交站)", "麟洛车站(公交站)", "石龟车站(公交站)",
        "泰安火车站(公交站)", "玉里火车站(公交站)",
    ])
    func neverPicksARoadStop(_ name: String) {
        let package = String(name.prefix(while: { $0 != "车" && $0 != "火" }))
        let candidates = [transit(name, 3)]
        #expect(StationPlaceLink.best(candidates, for: station(package)) == nil)
    }

    /// Nothing at all is a real answer, and the caller depends on it: on the
    /// China map service every Japanese and Korean query comes back empty.
    @Test
    func answersNothingRatherThanGuessing() {
        #expect(StationPlaceLink.best([], for: station("東京", country: "jp")) == nil)
        let unrelated = [transit("東京都庁", 120), untyped("東京タワー", 300)]
        #expect(StationPlaceLink.best(unrelated, for: station("東京", country: "jp")) == nil)
    }

    /// A station further away than the budget is a different station of the
    /// same name, not this one.
    @Test
    func holdsTheDistanceBudget() {
        #expect(StationPlaceLink.best([transit("泰安车站", 599)], for: station("泰安")) != nil)
        #expect(StationPlaceLink.best([transit("泰安车站", 601)], for: station("泰安")) == nil)
    }

    /// A categorised station beats an uncategorised one of the same name, and
    /// an unbracketed spelling beats a bracketed one, before distance is
    /// consulted at all.
    @Test
    func ordersTheTiersBeforeDistance() {
        let candidates = [
            untyped("大安", 5),
            transit("大安(地铁站)", 60),
            transit("大安", 400),
        ]
        #expect(StationPlaceLink.best(candidates, for: station("大安")) == 2)
    }

    /// The slash split runs on the CANDIDATE's side only. Apple's own "Caoya
    /// / KRTC Station" carries 草衙 in only the first half of a slash-joined
    /// name, and picks it; a candidate whose first half is unrelated, "Xyz /
    /// KRTC Station", must not match just because it shares the second half.
    @Test
    func picksAStationByOneHalfOfASlashSeparatedCandidateName() {
        let matching = [transit("Caoya / KRTC Station", 40)]
        #expect(StationPlaceLink.best(matching, for: station("草衙", "Caoya", country: "tw")) == 0)
        let nonMatching = [transit("Xyz / KRTC Station", 40)]
        #expect(StationPlaceLink.best(nonMatching, for: station("草衙", "Caoya", country: "tw")) == nil)
    }

    /// Hong Kong's tram network holds street furniture as "Whitty Street
    /// Stop" rather than under 屈地街 itself — the lowest tier, but still a
    /// match within the 150 m the bracket tiers use.
    @Test
    func picksANamedStopWhenNothingElseCarriesTheStationsName() {
        let candidates = [transit("Whitty Street Stop", 17)]
        let index = StationPlaceLink.best(
            candidates, for: station("屈地街", "Whitty Street", country: "hk"))
        #expect(index == 0)
    }

    @Test
    func doesNotTakeADistantNamedStop() {
        let candidates = [transit("Whitty Street Stop", 300)]
        #expect(
            StationPlaceLink.best(candidates, for: station("屈地街", "Whitty Street", country: "hk"))
                == nil)
    }

    /// "Taian Station Stop" is the English rendering of a bus stop's Chinese
    /// name, 泰安(公交站), and the named-stop tier must not re-admit it. The
    /// station is given "Taian" as a second name so the guard under test —
    /// "the remainder still ends in a station word" — is the thing doing the
    /// rejecting, rather than there being no Latin alias to match at all.
    @Test
    func rejectsAStopThatIsTheEnglishFormOfARoadStop() {
        let candidates = [transit("Taian Station Stop", 3)]
        #expect(StationPlaceLink.best(candidates, for: station("泰安", "Taian")) == nil)
    }

    @Test
    func doesNotMatchANamedStopByAPartialName() {
        let candidates = [transit("Shalun Rd Sec 1 Stop", 40)]
        #expect(
            StationPlaceLink.best(candidates, for: station("沙崙", "Shalun", country: "tw")) == nil)
    }

    /// `bestMatch` marks a `.namedStop` winner weak, so a caller running a
    /// multi-query plan knows to keep looking rather than settle for it —
    /// but a station winner from any other tier is never weak.
    @Test
    func reportsANamedStopWinnerAsWeak() {
        let stopOnly = [transit("Whitty Street Stop", 17)]
        let stopMatch = StationPlaceLink.bestMatch(
            stopOnly, for: station("屈地街", "Whitty Street", country: "hk"))
        #expect(stopMatch?.index == 0)
        #expect(stopMatch?.isWeak == true)

        let properStation = [transit("屈地街", 137)]
        let stationMatch = StationPlaceLink.bestMatch(
            properStation, for: station("屈地街", "Whitty Street", country: "hk"))
        #expect(stationMatch?.index == 0)
        #expect(stationMatch?.isWeak == false)
        #expect(stationMatch?.isTransport == true)
    }

    @Test("an untyped landmark from the filter-off pass is reported as such")
    func reportsAnUntypedWinnerAsNotTransport() {
        let hall = [untyped("Kaohsiung Exhibition Center", 249)]
        let match = StationPlaceLink.bestMatch(
            hall, for: station("高雄展覽館", "Kaohsiung Exhibition Center"))
        #expect(match?.index == 0)
        #expect(match?.isWeak == false)
        #expect(match?.isTransport == false)
    }

    @Test("a package name joined by a slash matches on either half")
    func picksAStationByOneHalfOfASlashSeparatedPackageName() {
        let aozihdi = station("凹子底/愛河之心")
        #expect(StationPlaceLink.best([transit("Aozihdi Station", 42)], for: station("凹子底/愛河之心", "Aozihdi/Heart of Love River")) == 0)
        #expect(StationPlaceLink.best([transit("愛河之心", 40)], for: aozihdi) == 0)
        #expect(StationPlaceLink.best([transit("凹子底", 40)], for: aozihdi) == 0)
        #expect(StationPlaceLink.best([transit("凹子", 40)], for: aozihdi) == nil)
    }

    @Test
    func prefersAProperStationOverANamedStop() {
        let candidates = [
            transit("Whitty Street Stop", 5),
            transit("屈地街", 137),
        ]
        let index = StationPlaceLink.best(
            candidates, for: station("屈地街", "Whitty Street", country: "hk"))
        #expect(index == 1)
    }

    // MARK: - Queries

    @Test
    func asksForTheBareNameFirstAndTheSuffixedOneSecond() {
        #expect(StationPlaceLink.queries(for: station("臺北", country: "tw")) == ["臺北", "臺北站"])
        #expect(StationPlaceLink.queries(for: station("金鐘", country: "hk")) == ["金鐘", "金鐘站"])
    }

    /// A name that already ends in the word gets one query, not 서울역역.
    @Test
    func neverDoublesAStationWordThatIsAlreadyThere() {
        #expect(StationPlaceLink.queries(for: station("서울역", country: "kr")) == ["서울역"])
        #expect(StationPlaceLink.queries(for: station("山鼻站", country: "tw")) == ["山鼻站"])
    }

    /// A live audit found 8 Japanese stations an English-language map service
    /// answers nothing for by kanji alone — 新豊田, 本町, 近鉄名古屋 — while
    /// "<romaji> Station" found each of them. So a jp station with a romaji
    /// spelling gets a third query built off it; a jp station without one
    /// keeps the same two-query plan as every other country.
    @Test
    func addsAThirdQueryForJapanWhenARomajiNameExists() {
        #expect(
            StationPlaceLink.queries(for: station("新豊田", "Shin-Toyota", country: "jp"))
                == ["新豊田", "新豊田駅", "Shin-Toyota Station"])
        #expect(StationPlaceLink.queries(for: station("東京", country: "jp")) == ["東京", "東京駅"])
    }

    /// The same English-service gap the romaji fallback closes for Japan
    /// shows up in Hong Kong too: 灣仔 alone answers only Admiralty, while
    /// "Wan Chai Station" finds the station itself.
    @Test
    func addsAThirdQueryForHongKongWhenAnEnglishNameExists() {
        #expect(
            StationPlaceLink.queries(for: station("灣仔", "Wan Chai", country: "hk"))
                == ["灣仔", "灣仔站", "Wan Chai Station"])
    }

    /// The suffix guard reads the Latin name's own ending rather than the
    /// CJK/Hangul `word`, so a Latin name that already says "Station" is
    /// never doubled into "Kaohsiung Main Station Station".
    @Test
    func doesNotDoubleAStationWordAlreadyOnTheLatinName() {
        #expect(
            StationPlaceLink.queries(for: station("高雄", "Kaohsiung Main Station", country: "tw"))
                == ["高雄", "高雄站", "Kaohsiung Main Station"])
    }

    /// "Terminus", "Depot" and "Sta" (no period) are also read as already
    /// naming a station, so a Latin name ending in one of them is never
    /// doubled into "Kennedy Town Terminus Station" or "Light Rail Depot
    /// Station".
    @Test(arguments: [
        ("九龍", "Kowloon Terminus", "Kowloon Terminus"),
        ("石排灣", "Wong Chuk Hang Depot", "Wong Chuk Hang Depot"),
        ("高雄", "Kaohsiung Sta", "Kaohsiung Sta"),
    ])
    func doesNotDoubleATerminusDepotOrStaSuffix(
        _ package: String, _ latin: String, _ expected: String
    ) {
        #expect(
            StationPlaceLink.queries(for: station(package, latin, country: "tw"))
                == [package, package + "站", expected])
    }

    /// Korea's own packages already spell the word into the station's name,
    /// so a Latin name buys it nothing and it stays at two queries.
    @Test
    func keepsKoreaAtTwoQueriesEvenWithALatinName() {
        #expect(
            StationPlaceLink.queries(for: station("서울", "Seoul Station", country: "kr"))
                == ["서울", "서울역"])
    }

    // MARK: - Links

    /// The place link carries the identifier and NOTHING else. A `place-id`
    /// Apple cannot resolve answers 「找不到你搜尋的頁面」 rather than falling
    /// back to a coordinate sitting beside it, so a second parameter would be a
    /// fallback that never fires.
    @Test
    func placeLinkNamesThePlaceAndOnlyThePlace() {
        let url = StationPlaceLink.placeURL(placeID: "H2710I3F9267AE5EC56")
        #expect(url?.absoluteString == "https://maps.apple.com/place?place-id=H2710I3F9267AE5EC56")
    }

    /// An identifier that is not one cannot be allowed to build a URL: the
    /// result would be a link that resolves to an error page, which is worse
    /// than the pin it replaced.
    @Test(arguments: ["", "   ", "abc def", "I123&q=x", "../place"])
    func refusesToBuildAPlaceLinkFromRubbish(_ rubbish: String) {
        #expect(StationPlaceLink.placeURL(placeID: rubbish) == nil)
    }

    /// The fallback is unchanged from what the card sent before places were
    /// resolved at all — a positioned, captioned pin.
    @Test
    func pinLinkKeepsThePositionAndTheCaption() {
        let url = StationPlaceLink.pinURL(name: "東京", latitude: 35.681391, longitude: 139.766103)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host == "maps.apple.com")
        #expect(items.first { $0.name == "ll" }?.value == "35.681391,139.766103")
        #expect(items.first { $0.name == "q" }?.value == "東京")
    }
}
