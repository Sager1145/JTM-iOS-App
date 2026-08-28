import Foundation
import Testing

@testable import RailCore

// =========================================================================
//  What a Yahoo! 乗換案内 screenshot has to read as.
//
//  The fixtures below are the LAYOUT, written down: a row is a y, a column is
//  an x, and a transfer's two times are half a row above and below the name
//  they belong to. That is the whole contract between Vision and the parser,
//  so it is the thing worth pinning — a fixture of real OCR output would pin
//  one device's font metrics instead.
//
//  The two journeys are the ones this was built against: 札幌→博多 (three
//  Shinkansen and limited-express legs, a midnight crossing, bracketed
//  station names) and 上野→高崎 (a 直通 leg that changes line under way).
// =========================================================================

/// Lays out text the way the screenshot does.
private struct Screenshot {
    var lines: [TransferGuide.TextLine] = []
    var y: Double = 0
    let pitch: Double = 36
    let height: Double = 20

    /// One row. `advance` is for the half-rows a transfer's 着/発 pair sits on.
    mutating func row(_ items: (String, Double)..., advance: Double? = nil) {
        for (text, x) in items {
            lines.append(
                TransferGuide.TextLine(
                    text: text,
                    box: TransferGuide.Box(
                        x: x, y: y, width: Double(text.count) * 14, height: height)))
        }
        y += advance ?? pitch
    }
}

private func sapporoToHakata() -> [TransferGuide.TextLine] {
    var shot = Screenshot()
    shot.row(("10:45→00:09", 10), ("(13時間24分)", 130), ("8月28日(金)", 250))
    shot.row(("IC優先", 10), ("47,280円", 70), ("乗換2回", 160), ("2338.2km", 240))
    shot.row(("10:45", 10), ("発", 70), ("札幌", 110))
    shot.row(("4駅", 10), ("ＪＲ特急北斗８号", 110), ("24,640円", 290))
    shot.row(("当駅始発", 110), ("函館行", 180), ("指定席", 290))
    shot.row(("発 8番線", 110), ("3,170円", 290))
    shot.row(("着 2番線", 110))
    shot.row(("10:54", 10), ("新札幌", 110))
    shot.row(("11:16", 10), ("南千歳", 110))
    shot.row(("13:09", 10), ("大沼公園", 110))
    shot.row(("14:18着", 10), advance: 18)
    shot.row(("新函館北斗 iii", 110), advance: 18)
    shot.row(("14:39発", 10))
    shot.row(("3駅", 10), ("ＪＲ新幹線はやぶさ２８号(E5系)", 110), ("11,330円", 290))
    shot.row(("当駅始発", 110), ("東京行", 180))
    shot.row(("発 11番線", 110))
    shot.row(("着 21番線", 110))
    shot.row(("15:38", 10), ("新青森 iii", 110))
    shot.row(("18:59", 10), ("上野 iii", 110))
    shot.row(("19:04着", 10), advance: 18)
    shot.row(("東京 iii", 110), advance: 18)
    shot.row(("19:12発", 10))
    shot.row(("3駅", 10), ("ＪＲ新幹線のぞみ５７号(N700A)", 110), ("8,140円", 290))
    shot.row(("当駅始発", 110), ("博多行", 180))
    shot.row(("発 16番線", 110))
    shot.row(("着 15番線", 110))
    shot.row(("19:19", 10), ("品川 iii", 110))
    shot.row(("23:54", 10), ("小倉(福岡県) iii", 110))
    shot.row(("00:09", 10), ("着", 70), ("博多", 110))
    shot.row(("CO2排出量 40kg", 10))
    shot.row(("Yahoo!乗換案内", 100))
    return shot.lines
}

struct TransferGuideParseTests {

    @Test("the route summary reads out of the two header rows")
    func header() {
        let route = TransferGuide.parse(sapporoToHakata())
        #expect(route.header.departure == "10:45")
        #expect(route.header.arrival == "00:09")
        #expect(route.header.durationMinutes == 13 * 60 + 24)
        #expect(route.header.month == 8)
        #expect(route.header.day == 28)
        #expect(route.header.weekday == "金")
        #expect(route.header.fareYen == 47_280)
        #expect(route.header.transferCount == 2)
        #expect(route.header.distanceKm == 2338.2)
    }

    @Test("a leg header splits the document into rides")
    func legs() {
        let route = TransferGuide.parse(sapporoToHakata())
        #expect(route.legs.count == 3)
        #expect(route.legs.map(\.service) == [
            "JR特急北斗8号", "JR新幹線はやぶさ28号", "JR新幹線のぞみ57号",
        ])
        // The rolling stock is read, and kept out of the service's own name.
        #expect(route.legs.map(\.equipment) == [nil, "E5系", "N700A"])
        #expect(route.legs.map(\.destination) == ["函館", "東京", "博多"])
        #expect(route.legs.map(\.startsHere) == [true, true, true])
        #expect(route.legs.map(\.kind) == [.train, .train, .train])
    }

    @Test("platforms, fares and the station count come off the header block")
    func legDetail() {
        let route = TransferGuide.parse(sapporoToHakata())
        #expect(route.legs.map(\.departurePlatform) == [8, 11, 16])
        #expect(route.legs.map(\.arrivalPlatform) == [2, 21, 15])
        #expect(route.legs.map(\.declaredStationCount) == [4, 3, 3])
        // The through fare, not the 指定席 surcharge printed beside it.
        #expect(route.legs[0].fareYen == 24_640)
    }

    @Test("a boundary station ends one leg and starts the next")
    func transfers() {
        let route = TransferGuide.parse(sapporoToHakata())
        #expect(route.legs[0].calls.map(\.name) == ["札幌", "新札幌", "南千歳", "大沼公園", "新函館北斗"])
        #expect(route.legs[1].calls.map(\.name) == ["新函館北斗", "新青森", "上野", "東京"])
        #expect(route.legs[2].calls.map(\.name) == ["東京", "品川", "小倉", "博多"])

        // 14:18 arrives; 14:39 leaves. Neither leg carries the other's time.
        let arriving = route.legs[0].calls.last
        #expect(arriving?.arrival == "14:18")
        #expect(arriving?.departure == nil)
        let leaving = route.legs[1].calls.first
        #expect(leaving?.departure == "14:39")
        #expect(leaving?.arrival == nil)
    }

    @Test("the bracketed prefecture is kept and the 構内図 icon is not")
    func names() {
        let route = TransferGuide.parse(sapporoToHakata())
        let kokura = route.legs[2].calls[2]
        #expect(kokura.name == "小倉")
        #expect(kokura.qualifier == "福岡県")
        #expect(route.legs[1].calls[1].name == "新青森")
        #expect(route.legs[0].calls.last?.name == "新函館北斗")
    }

    @Test("past midnight is spelled 24:09, not 00:09")
    func midnight() {
        let route = TransferGuide.parse(sapporoToHakata())
        #expect(route.legs[2].calls.last?.arrival == "24:09")
        #expect(route.legs[2].calls.first?.departure == "19:12")
        #expect(route.notes.contains(
            TransferGuide.Note(kind: .crossedMidnight, subject: "JR新幹線のぞみ57号")))
    }

    @Test("a screenshot that parsed leaves nothing important unclaimed")
    func unclaimed() {
        let route = TransferGuide.parse(sapporoToHakata())
        #expect(route.unclaimed.isEmpty)
        #expect(!route.notes.contains { $0.kind == .noLegs || $0.kind == .noHeader })
        #expect(!route.notes.contains { $0.kind == .timeWentBackwards })
        #expect(!route.notes.contains { $0.kind == .stationCountDisagrees })
    }

    @Test("a 直通 block is one ride over two lines, not two rides")
    func throughService() {
        var shot = Screenshot()
        shot.row(("07:20→09:16", 10), ("(1時間56分)", 130), ("8月30日(日)", 250))
        shot.row(("07:20", 10), ("発", 70), ("上野", 110))
        shot.row(("3駅", 10), ("ＪＲ上野東京ライン", 110), ("1,980円", 290))
        shot.row(("直通", 110), ("熱海行", 170))
        shot.row(("発 8番線", 110))
        shot.row(("グリーン車を連結", 110))
        shot.row(("ＪＲ高崎線", 110), ("直通", 200), ("15両", 250))
        shot.row(("07:26", 10), ("尾久", 110))
        shot.row(("07:52", 10), ("大宮(埼玉県)", 110))
        shot.row(("09:16", 10), ("着", 70), ("高崎", 110))
        let route = TransferGuide.parse(shot.lines)

        #expect(route.legs.count == 1)
        let leg = route.legs[0]
        #expect(leg.service == "JR上野東京ライン")
        #expect(leg.throughServices == ["JR高崎線"])
        #expect(leg.carCount == 15)
        #expect(leg.departurePlatform == 8)
        #expect(leg.calls.map(\.name) == ["上野", "尾久", "大宮", "高崎"])
        #expect(leg.calls.first?.departure == "07:20")
        #expect(leg.calls.last?.arrival == "09:16")
        #expect(leg.notes.contains("グリーン車を連結"))
        #expect(TransferGuide.lineHints(for: leg) == ["上野東京ライン", "高崎線"])
    }

    @Test("a walking connection is a leg, and not one that is ridden")
    func walking() {
        var shot = Screenshot()
        shot.row(("09:00→09:30", 10), ("(30分)", 130), ("9月1日(火)", 250))
        shot.row(("09:00", 10), ("発", 70), ("東京", 110))
        shot.row(("1駅", 10), ("ＪＲ京浜東北線", 110))
        shot.row(("09:02", 10), ("着", 70), ("神田", 110))
        shot.row(("徒歩5分", 110))
        shot.row(("09:10", 10), ("発", 70), ("小川町", 110))
        shot.row(("1駅", 10), ("都営新宿線", 110))
        shot.row(("09:30", 10), ("着", 70), ("九段下", 110))
        let route = TransferGuide.parse(shot.lines)

        #expect(route.legs.map(\.kind) == [.train, .walk, .train])
        #expect(route.ridableLegs.count == 2)
        #expect(route.notes.contains { $0.kind == .legNotRidden })
        #expect(route.legs[1].calls.map(\.name) == ["神田", "小川町"])
    }

    @Test("a station count Yahoo disagrees with is reported, not corrected")
    func stationCount() {
        var shot = Screenshot()
        shot.row(("09:00", 10), ("発", 70), ("東京", 110))
        shot.row(("9駅", 10), ("ＪＲ山手線", 110))
        shot.row(("09:05", 10), ("神田", 110))
        shot.row(("09:30", 10), ("着", 70), ("池袋", 110))
        let route = TransferGuide.parse(shot.lines)
        #expect(route.legs[0].calls.count == 3)
        #expect(route.notes.contains { $0.kind == .stationCountDisagrees })
    }

    @Test("a time that steps backwards is reported and left alone")
    func backwards() {
        var shot = Screenshot()
        shot.row(("09:00", 10), ("発", 70), ("東京", 110))
        shot.row(("2駅", 10), ("ＪＲ山手線", 110))
        shot.row(("08:05", 10), ("神田", 110))
        shot.row(("09:30", 10), ("着", 70), ("池袋", 110))
        let route = TransferGuide.parse(shot.lines)
        #expect(route.legs[0].calls[1].departure == "08:05")
        #expect(route.notes.contains { $0.kind == .timeWentBackwards })
        #expect(!route.notes.contains { $0.kind == .crossedMidnight })
    }

    @Test("a misread digit in the time column does not delete the station")
    func confusedDigits() {
        var shot = Screenshot()
        // `07:20` read as `O7::20` and `07:26` as `O7:26` — the zero a
        // recogniser reads as a capital O in a column of small digits, and the
        // doubled colon it sees where the column rule runs. `l` and `I` fold
        // the other way, to the 1 they are misreadings of.
        shot.row(("O7::20→09:16", 10), ("(1時間56分)", 130), ("8月30日(日)", 250))
        shot.row(("O7:20", 10), ("発", 70), ("上野", 110))
        shot.row(("2駅", 10), ("ＪＲ高崎線", 110))
        shot.row(("O7:26", 10), ("尾久", 110))
        shot.row(("09:16", 10), ("着", 70), ("高崎", 110))
        let route = TransferGuide.parse(shot.lines)

        #expect(route.header.departure == "07:20")
        #expect(route.legs.count == 1)
        #expect(route.legs[0].calls.map(\.name) == ["上野", "尾久", "高崎"])
        #expect(route.legs[0].calls[1].departure == "07:26")
        #expect(route.unclaimed.isEmpty)
    }

    @Test("a station whose time was not read is still a station")
    func stopWithoutATime() {
        var shot = Screenshot()
        shot.row(("09:00", 10), ("発", 70), ("東京", 110))
        shot.row(("3駅", 10), ("ＪＲ山手線", 110))
        shot.row(("09:05", 10), ("神田", 110))
        shot.row(("秋葉原", 110))  // the time column came back empty here
        shot.row(("09:30", 10), ("着", 70), ("池袋", 110))
        let route = TransferGuide.parse(shot.lines)

        #expect(route.legs[0].calls.map(\.name) == ["東京", "神田", "秋葉原", "池袋"])
        #expect(route.legs[0].calls[2].departure == nil)
        #expect(route.legs[0].calls[2].arrival == nil)
        #expect(route.unclaimed.isEmpty)
    }

    // ---------------------------------------------------------------------
    //  What real screenshots turned out to look like.
    //
    //  Every case below is one the synthetic fixtures above did not produce
    //  and two real Yahoo captures did. They are written from the OCR boxes
    //  those captures actually returned.
    // ---------------------------------------------------------------------

    @Test("ＪＲ comes back split down the middle, and is put back")
    func splitPrefix() {
        var shot = Screenshot()
        shot.row(("10:45", 10), ("発", 70), ("札幌", 110))
        // One observation, with a space Vision invented between the two
        // full-width capitals.
        shot.row(("2駅", 10), ("J R特急北斗8号", 110))
        shot.row(("13:09", 10), ("大沼公園", 110))
        shot.row(("14:18", 10), ("着", 70), ("新函館北斗", 110))
        let route = TransferGuide.parse(shot.lines)
        #expect(route.legs.count == 1)
        #expect(route.legs[0].service == "JR特急北斗8号")
        #expect(TransferGuide.trainType(for: route.legs[0]) == "特急")
    }

    @Test("a service too long for one line is read off both of them")
    func wrappedService() {
        var shot = Screenshot()
        shot.row(("14:39", 10), ("発", 70), ("新函館北斗", 110))
        shot.row(("2駅", 10), ("ＪＲ新幹線はやぶ", 110), advance: 22)
        shot.row(("さ28号(E5系)", 110))
        shot.row(("当駅始発", 110), ("東京行", 200))
        shot.row(("15:38", 10), ("新青森", 110))
        shot.row(("19:04", 10), ("着", 70), ("東京", 110))
        let route = TransferGuide.parse(shot.lines)
        #expect(route.legs.count == 1)
        #expect(route.legs[0].service == "JR新幹線はやぶさ28号")
        #expect(route.legs[0].equipment == "E5系")
        #expect(route.legs[0].destination == "東京")
        // And the second line does not also become a note about itself.
        #expect(!route.legs[0].notes.contains { $0.contains("28号") })
    }

    @Test("the platform is three separate badges on one row")
    func platformBadges() {
        var shot = Screenshot()
        shot.row(("10:45", 10), ("発", 70), ("札幌", 110))
        shot.row(("2駅", 10), ("ＪＲ特急北斗８号", 110))
        // 発, 8 and 番線 are three boxes in the interface, so they arrive as
        // three observations and the row assembles them with spaces.
        shot.row(("発", 110), ("8", 150), ("番線", 175))
        shot.row(("着", 110), ("2", 150), ("番線", 175))
        shot.row(("13:09", 10), ("大沼公園", 110))
        shot.row(("14:18", 10), ("着", 70), ("新函館北斗", 110))
        let route = TransferGuide.parse(shot.lines)
        #expect(route.legs[0].departurePlatform == 8)
        #expect(route.legs[0].arrivalPlatform == 2)
        // …and the pieces of it do not survive as notes.
        #expect(route.legs[0].notes.isEmpty)
    }

    @Test("the 駅構内図 icon never becomes the station")
    func iconIsNotAStation() {
        var shot = Screenshot()
        shot.row(("09:00", 10), ("発", 70), ("東京", 110))
        shot.row(("3駅", 10), ("ＪＲ新幹線のぞみ", 110))
        // The icon sits to the RIGHT of the name and comes back as its own
        // word, or glued to the bracket that makes the name unambiguous.
        shot.row(("09:07", 10), ("品川 iff", 110))
        shot.row(("09:20", 10), ("大宮（埼玉県）ifi", 110))
        shot.row(("10:30", 10), ("着", 70), ("新横浜 ii", 110))
        let route = TransferGuide.parse(shot.lines)
        #expect(route.legs[0].calls.map(\.name) == ["東京", "品川", "大宮", "新横浜"])
        #expect(route.legs[0].calls[2].qualifier == "埼玉県")
    }

    @Test("a 着 badge glued to the station is a badge, not a longer name")
    func gluedBadge() {
        var shot = Screenshot()
        shot.row(("19:12", 10), ("発", 70), ("東京", 110))
        shot.row(("2駅", 10), ("ＪＲ新幹線のぞみ57号", 110))
        shot.row(("23:54", 10), ("小倉（福岡県）", 110))
        shot.row(("00:09", 10), ("着博多", 110))
        let route = TransferGuide.parse(shot.lines)
        #expect(route.legs[0].calls.map(\.name) == ["東京", "小倉", "博多"])
        #expect(route.legs[0].calls.last?.arrival == "24:09")
        // 発寒 begins with the other badge and is a station all the same.
        #expect(TransferGuide.gluedMarker("発寒").name == "発寒")
        #expect(TransferGuide.gluedMarker("発寒").marker == nil)
    }

    @Test("乗換不要 is one ride whose line changed, not two rides")
    func throughWithoutTransfer() {
        var shot = Screenshot()
        shot.row(("11:41", 10), ("発", 70), ("越後湯沢", 110))
        shot.row(("2駅", 10), ("北越急行ほくほく線", 110))
        shot.row(("直通", 110), ("直江津行", 200))
        shot.row(("11:57", 10), ("くびき", 110))
        // Yahoo prints the badge on the station and then repeats the service
        // block for the line the train runs onto.
        shot.row(("13:11", 10), ("乗換不要", 110), ("犀潟", 210))
        shot.row(("2駅", 10), ("ＪＲ信越本線", 110))
        shot.row(("直江津行", 110))
        shot.row(("13:18", 10), ("着", 70), ("直江津", 110))
        let route = TransferGuide.parse(shot.lines)

        #expect(route.legs.count == 1)
        let leg = route.legs[0]
        #expect(leg.service == "北越急行ほくほく線")
        #expect(leg.throughServices == ["JR信越本線"])
        #expect(leg.calls.map(\.name) == ["越後湯沢", "くびき", "犀潟", "直江津"])
        #expect(leg.calls.last?.arrival == "13:18")
        // Yahoo counts each block; the ride's own count is their sum.
        #expect(leg.declaredStationCount == 4)
        #expect(route.unclaimed.isEmpty)
    }

    @Test("a photograph of something else parses into nothing, and says so")
    func nonsense() {
        var shot = Screenshot()
        shot.row(("ホーム画面", 10))
        shot.row(("設定", 10))
        let route = TransferGuide.parse(shot.lines)
        #expect(route.legs.isEmpty)
        #expect(route.notes.contains { $0.kind == .noLegs })
    }
}

struct TransferGuideTextTests {

    @Test("full-width characters fold and the icon does not survive")
    func normalisation() {
        #expect(TransferGuide.Text.normalize("ＪＲ特急北斗８号") == "JR特急北斗8号")
        #expect(TransferGuide.Text.normalize("１０：４５") == "10:45")
        #expect(TransferGuide.Text.stripDecorations("新函館北斗iii") == "新函館北斗")
        #expect(TransferGuide.Text.stripDecorations("東京 ≡") == "東京")
        #expect(TransferGuide.Text.isAllDecoration("iii"))
        #expect(!TransferGuide.Text.isAllDecoration("東京"))
    }

    @Test("a bracketed prefecture is split off, and a paren inside a name is not")
    func stationNames() {
        let kokura = TransferGuide.Text.stationName("小倉(福岡県)")
        #expect(kokura.name == "小倉")
        #expect(kokura.qualifier == "福岡県")
        #expect(TransferGuide.Text.stationName("東京").name == "東京")
        #expect(TransferGuide.Text.stationName("東京").qualifier == nil)
    }

    @Test("the match key folds the spellings that mean one station")
    func matchKey() {
        #expect(TransferGuide.Text.matchKey("大宮(埼玉県)") == TransferGuide.Text.matchKey("大宮"))
        #expect(TransferGuide.Text.matchKey("三ヶ日") == TransferGuide.Text.matchKey("三ケ日"))
        #expect(TransferGuide.Text.matchKey("東京駅") == TransferGuide.Text.matchKey("東京"))
        #expect(TransferGuide.Text.matchKey("ＪＲ難波") == TransferGuide.Text.matchKey("JR難波"))
    }

    @Test("stations that read like other things are still stations")
    func lookalikes() {
        // 大分 ends in the character a duration ends in; 両国 begins with the
        // one a car count ends in; 三田 begins with a kanji numeral.
        for name in ["大分", "両国", "三田", "国分", "追分", "森"] {
            #expect(TransferGuide.Text.looksLikeStationName(name), "\(name)")
        }
        #expect(!TransferGuide.Text.looksLikeStationName("47,280円"))
        #expect(!TransferGuide.Text.looksLikeStationName("8番線"))
    }

    @Test("the year a screenshot never prints is the nearest reading of the day")
    func year() {
        #expect(
            TransferGuide.calendarDate(
                month: 8, day: 28, year: nil, today: (2026, 8, 27)) == "2026-08-28")
        // A December screenshot imported in January belongs to last year.
        #expect(
            TransferGuide.calendarDate(
                month: 12, day: 30, year: nil, today: (2026, 1, 3)) == "2025-12-30")
        // And a January one imported in December belongs to next year.
        #expect(
            TransferGuide.calendarDate(
                month: 1, day: 3, year: nil, today: (2026, 12, 30)) == "2027-01-03")
        #expect(
            TransferGuide.calendarDate(
                month: 8, day: 28, year: 2019, today: (2026, 8, 27)) == "2019-08-28")
    }
}

// =========================================================================
//  And what the parsed route has to become.
// =========================================================================

/// A hand-built package: enough stations to have a wrong answer available.
private func testIndex() -> StationIndex {
    typealias Line = StationIndex.LineRef
    let tokaidoShinkansen = Line(
        name: "東海道新幹線", operatorName: "東海旅客鉄道", colorHex: "#0033a0")
    let tokaidoMain = Line(name: "東海道本線", operatorName: "東日本旅客鉄道", colorHex: "#f68b1e")
    let yamanote = Line(name: "山手線", operatorName: "東日本旅客鉄道", colorHex: "#9acd32")
    let takasaki = Line(name: "高崎線", operatorName: "東日本旅客鉄道", colorHex: "#ff7f00")
    let tohokuMain = Line(name: "東北本線", operatorName: "東日本旅客鉄道", colorHex: "#f68b1e")
    let hankyu = Line(name: "阪急京都本線", operatorName: "阪急電鉄", colorHex: "#800000")

    func entries(
        _ code: String, _ name: String, _ lon: Double, _ lat: Double, _ lines: [Line]
    ) -> [StationIndex.Entry] {
        lines.map {
            StationIndex.Entry(
                code: code, name: name, coordinate: Coordinate(lon: lon, lat: lat), line: $0)
        }
    }

    return StationIndex(
        entries("100001", "東京", 139.7671, 35.6812, [tokaidoShinkansen, tokaidoMain, yamanote])
            + entries("100002", "品川", 139.7387, 35.6285, [tokaidoShinkansen, tokaidoMain, yamanote])
            + entries("100003", "新横浜", 139.6172, 35.5079, [tokaidoShinkansen])
            + entries("100004", "上野", 139.7770, 35.7141, [yamanote, tohokuMain, takasaki])
            + entries("100005", "尾久", 139.7420, 35.7561, [tohokuMain, takasaki])
            + entries("100006", "大宮", 139.6238, 35.9063, [tohokuMain, takasaki])
            + entries("900006", "大宮", 135.7477, 35.0088, [hankyu])
            + entries("100007", "高崎", 139.0125, 36.3222, [takasaki])
            // Four stops in a row on one line, plus the two 北… stations that
            // sit just outside them — the trap a corridor search has to avoid.
            + entries("100011", "北上尾", 139.5786, 35.9764, [takasaki])
            + entries("100012", "桶川", 139.5528, 35.9986, [takasaki])
            + entries("100013", "北本", 139.5308, 36.0263, [takasaki])
            + entries("100014", "鴻巣", 139.5158, 36.0663, [takasaki])
            + entries("100015", "北鴻巣", 139.4906, 36.1064, [takasaki])
            + entries("100016", "倶利伽羅", 136.8069, 36.6650, [takasaki]))
}

private func uenoToTakasaki() -> TransferGuide.Route {
    var shot = Screenshot()
    shot.row(("07:20→09:16", 10), ("(1時間56分)", 130), ("8月30日(日)", 250))
    shot.row(("07:20", 10), ("発", 70), ("上野", 110))
    shot.row(("3駅", 10), ("ＪＲ上野東京ライン", 110), ("1,980円", 290))
    shot.row(("直通", 110), ("熱海行", 170))
    shot.row(("発 8番線", 110))
    shot.row(("着 3番線", 110))
    shot.row(("ＪＲ高崎線", 110), ("15両", 250))
    shot.row(("07:26", 10), ("尾久", 110))
    shot.row(("07:52", 10), ("大宮(埼玉県)", 110))
    shot.row(("09:16", 10), ("着", 70), ("高崎", 110))
    return TransferGuide.parse(shot.lines)
}

struct TransferGuideTrainTests {

    @Test("the chain picks the station the journey could actually reach")
    func resolvesByChain() {
        let index = testIndex()
        #expect(index.places(named: "大宮").count == 2)

        let picked = StationIndex.resolve(
            names: ["上野", "尾久", "大宮", "高崎"],
            hints: [[], [], [], []],
            index: index)
        #expect(picked.map { $0?.code } == ["100004", "100005", "100006", "100007"])
    }

    @Test("a name the package does not carry leaves a hole, not a wrong answer")
    func unresolvedLeavesAHole() {
        let picked = StationIndex.resolve(
            names: ["上野", "存在しない駅", "高崎"], hints: [[], [], []], index: testIndex())
        #expect(picked.map { $0?.code } == ["100004", nil, "100007"])
    }

    @Test("a section may only be on a line both ends carry, of the right kind")
    func sectionLines() {
        let index = testIndex()
        let tokyo = index.place(code: "100001")
        let shinagawa = index.place(code: "100002")

        let bullet = StationIndex.sharedLines(
            from: tokyo, to: shinagawa, shinkansen: true, hints: [])
        #expect(bullet.map(\.name) == ["東海道新幹線"])

        let local = StationIndex.sharedLines(
            from: tokyo, to: shinagawa, shinkansen: false, hints: [])
        #expect(local.map(\.name) == ["東海道本線", "山手線"])

        // And a hint settles which of the two a local ride was on.
        let hinted = StationIndex.sharedLines(
            from: tokyo, to: shinagawa, shinkansen: false, hints: ["山手線"])
        #expect(hinted.map(\.name) == ["山手線"])
    }

    @Test("one leg becomes one canonical journey")
    func buildsOneTrainPerLeg() throws {
        let route = uenoToTakasaki()
        let result = TransferGuide.build(
            route: route,
            options: TransferGuide.BuildOptions(
                date: "2026-08-30", region: "jp", idPrefix: "yahoo", ridden: true),
            stations: testIndex())

        #expect(result.trains.count == 1)
        #expect(result.unresolved.isEmpty)
        #expect(result.resolvedCalls == result.totalCalls)

        let train = try #require(result.trains.first)
        #expect(train.id == "yahoo_20260830_01")
        #expect(train.date == "2026-08-30")
        #expect(train.origin == "上野")
        #expect(train.destination == "高崎")
        #expect(train.direction == "熱海")
        #expect(train.trainType == "普通")
        #expect(train.company == "JR東日本")
        #expect(train.region == "jp")
        // The 直通 line change survives in the one free-text field there is.
        #expect(train.number == "JR上野東京ライン（07:20 熱海行・JR高崎線直通）")
    }

    @Test("stations, times, platforms and codes all land on the stops")
    func stopsCarryEverything() throws {
        let result = TransferGuide.build(
            route: uenoToTakasaki(),
            options: TransferGuide.BuildOptions(date: "2026-08-30", ridden: true),
            stations: testIndex())
        let train = try #require(result.trains.first)

        #expect(train.stops.map(\.name) == ["上野", "尾久", "大宮", "高崎"])
        #expect(train.stops.map(\.n02StationCode) == ["100004", "100005", "100006", "100007"])
        #expect(train.stops.map(\.stopType) == [
            "origin", "passenger_stop", "passenger_stop", "destination",
        ])
        #expect(train.stops[0].departure == "07:20")
        #expect(train.stops[1].departure == "07:26")
        #expect(train.stops[3].arrival == "09:16")
        // The platform Yahoo printed, on the stop it was printed for.
        #expect(train.stops[0].platformNumber == 8)
        #expect(train.stops[3].platformNumber == 3)
        #expect(train.stops[1].platformNumber == nil)
        #expect(train.stops.map(\.rideSegment) == [true, true, true, true])
    }

    @Test("route sections carry the hard line constraint the solver needs")
    func sections() throws {
        let result = TransferGuide.build(
            route: uenoToTakasaki(),
            options: TransferGuide.BuildOptions(date: "2026-08-30"),
            stations: testIndex())
        let train = try #require(result.trains.first)
        let sections = try #require(train.routeSections)

        #expect(sections.count == 3)
        #expect(sections.map(\.from) == ["上野", "尾久", "大宮"])
        #expect(sections.map(\.fromN02StationCode) == ["100004", "100005", "100006"])
        // 上野東京ライン is not a package line; 高崎線 is, and both ends carry it.
        #expect(sections[0].lineNames == ["高崎線"])
        #expect(sections[0].operatorNames == ["東日本旅客鉄道"])

        let policy = try #require(train.routePolicy)
        #expect(policy.mode == "single_primary_route")
        #expect(policy.jrOnly == true)
        #expect(policy.allowAlternatives == false)
        #expect(policy.allowBrowserStraightLineFallback == false)
        #expect(policy.allowedInstitutionTypeCodes == ["2"])
        #expect(policy.preferredLineNames == ["高崎線"])
        #expect(policy.institutionFilterMode == "soft")
    }

    @Test("a Shinkansen leg is constrained to Shinkansen, and says so twice")
    func shinkansenPolicy() throws {
        var shot = Screenshot()
        shot.row(("09:00→10:30", 10), ("(1時間30分)", 130), ("9月2日(水)", 250))
        shot.row(("09:00", 10), ("発", 70), ("東京", 110))
        shot.row(("2駅", 10), ("ＪＲ新幹線のぞみ１号", 110))
        shot.row(("発 16番線", 110))
        shot.row(("09:07", 10), ("品川", 110))
        shot.row(("10:30", 10), ("着", 70), ("新横浜", 110))
        let result = TransferGuide.build(
            route: TransferGuide.parse(shot.lines),
            options: TransferGuide.BuildOptions(date: "2026-09-02"),
            stations: testIndex())
        let train = try #require(result.trains.first)

        #expect(train.trainType == "新幹線")
        #expect(train.company == "JR東海")
        #expect(try #require(train.routeSections)[0].lineNames == ["東海道新幹線"])
        #expect(try #require(train.routePolicy).allowedInstitutionTypeCodes == ["1"])
    }

    @Test("a planned journey is the same record with nothing claimed as ridden")
    func plannedRide() throws {
        let result = TransferGuide.build(
            route: uenoToTakasaki(),
            options: TransferGuide.BuildOptions(date: "2027-01-01", ridden: false),
            stations: testIndex())
        let train = try #require(result.trains.first)
        #expect(train.stops.allSatisfy { $0.rideSegment == false })
        #expect(train.stops.count == 4)
        #expect(train.visible == true)
    }

    @Test("importing the same screenshot twice does not overwrite the first")
    func idsDoNotCollide() {
        let route = uenoToTakasaki()
        let first = TransferGuide.build(
            route: route, options: TransferGuide.BuildOptions(date: "2026-08-30"),
            stations: testIndex())
        let second = TransferGuide.build(
            route: route,
            options: TransferGuide.BuildOptions(
                date: "2026-08-30", existingIDs: Set(first.trains.map(\.id))),
            stations: testIndex())
        #expect(first.trains.map(\.id) == ["yahoo_20260830_01"])
        #expect(second.trains.map(\.id) == ["yahoo_20260830_01-2"])
    }

    @Test("a name the recogniser damaged is recovered from where it must be")
    func fillsFromTheCorridor() {
        let index = testIndex()
        var places = StationIndex.resolve(
            names: ["桶川", "北", "鴻巣"], hints: [[], [], []], index: index)
        #expect(places[1] == nil)

        StationIndex.fill(names: ["桶川", "北", "鴻巣"], places: &places, index: index)
        // 北本 is between them. 北上尾 is behind 桶川 and 北鴻巣 is past 鴻巣,
        // and both share the same stem — projecting onto the segment is what
        // rules them out.
        #expect(places.map { $0?.name } == ["桶川", "北本", "鴻巣"])
    }

    @Test("a name that shares nothing with the truth is left unresolved")
    func doesNotInventAStation() {
        let index = testIndex()
        // 浦和, read as 申木. Nothing in the corridor is spelled anything like
        // it, and guessing would put the journey through a station it never
        // called at.
        var places = StationIndex.resolve(
            names: ["桶川", "申木", "鴻巣"], hints: [[], [], []], index: index)
        StationIndex.fill(names: ["桶川", "申木", "鴻巣"], places: &places, index: index)
        #expect(places[1] == nil)
    }

    @Test("two spellings of one kanji are one station")
    func kanjiVariants() {
        // 俱 (U+4FF1) on the screen, 倶 (U+5036) in the package. NFKC folds
        // neither into the other.
        #expect(testIndex().places(named: "俱利伽羅").map(\.code) == ["100016"])
        #expect(TransferGuide.Text.matchKey("髙島") == TransferGuide.Text.matchKey("高島"))
    }

    @Test("every record the importer writes is one the validator accepts")
    func recordsValidate() throws {
        let result = TransferGuide.build(
            route: uenoToTakasaki(),
            options: TransferGuide.BuildOptions(date: "2026-08-30"),
            stations: testIndex())
        let store = TrainStore(trains: result.trains)
        let encoded = try JSONEncoder().encode(store)
        let json = try TrainValidation.JSON.parse(String(decoding: encoded, as: UTF8.self))
        // Throws with the validator's own message if anything is out of shape.
        try TrainValidation.validateTrainStore(json)
    }
}

// =========================================================================
//  The other app.
//
//  JR東日本アプリ draws the same journey with a different grammar, and the
//  reader is given one door for both. These fixtures are its layout, written
//  down the way the Yahoo ones are: a leg header that CARRIES a time, a
//  boundary whose time and name are two rows apart, and 着/発 at every stop
//  rather than only at the transfers.
// =========================================================================

private func jrEastRoute() -> [TransferGuide.TextLine] {
    var shot = Screenshot()
    shot.row(("8月28日(金)", 100))
    shot.row(("04:16→18:24", 100))
    shot.row(("14時間8分乗換2", 100), ("10,290円", 290))
    shot.row(("移動距離 605.5km", 100))
    shot.row(("更新時刻 02:14", 240))
    shot.row(("鳥取", 80))
    shot.row(("出発時刻を変更>", 78))
    // A leg header WITH the departure time of the station above it.
    shot.row(("04:16", 20), ("ＪＲ因美線", 130))
    shot.row(("当駅始発", 18), ("智頭行", 128))
    shot.row(("9駅目で降りる", 128))
    shot.row(("05:20着", 30), advance: 20)
    shot.row(("津ノ井", 128), advance: 20)
    shot.row(("05:21発", 30))
    shot.row(("05:25着", 30), advance: 20)
    shot.row(("東郡家", 128), advance: 20)
    shot.row(("05:26発", 30))
    // A boundary: the arrival on one row, the station a long way below it.
    shot.row(("05:58", 20), advance: 60)
    shot.row(("智頭", 80), ("3分", 200))
    shot.row(("出発時刻を変更>", 78))
    shot.row(("06:03", 20), ("智頭急行", 130))
    shot.row(("当駅始発", 18), ("上郡行", 128))
    shot.row(("3番線", 24))
    shot.row(("2駅目で降りる", 128))
    shot.row(("06:09着", 30), advance: 20)
    shot.row(("恋山形", 128), advance: 20)
    shot.row(("06:10発", 30))
    shot.row(("07:21", 20), advance: 60)
    shot.row(("上郡", 80))
    shot.row(("ＪＲ東日本アプリ", 140))
    return shot.lines
}

struct JREastGuideTests {

    @Test("a JR East screenshot is recognised and read as one")
    func readsJREast() {
        let read = TransferGuide.read(jrEastRoute())
        #expect(read.source == .jrEast)

        let route = read.route
        #expect(route.header.departure == "04:16")
        #expect(route.header.arrival == "18:24")
        #expect(route.header.durationMinutes == 14 * 60 + 8)
        #expect(route.header.distanceKm == 605.5)
        #expect(route.header.fareYen == 10_290)
        // `乗換2回` with the 回 clipped off, which is how the real capture read.
        #expect(route.header.transferCount == 2)

        #expect(route.legs.count == 2)
        #expect(route.legs.map(\.service) == ["JR因美線", "智頭急行"])
        #expect(route.legs.map(\.destination) == ["智頭", "上郡"])
        #expect(route.legs[0].calls.map(\.name) == ["鳥取", "津ノ井", "東郡家", "智頭"])
        #expect(route.legs[1].calls.map(\.name) == ["智頭", "恋山形", "上郡"])
        #expect(route.legs[1].departurePlatform == 3)
        #expect(route.unclaimed.isEmpty)
    }

    @Test("the leg header's time is the departure of the station above it")
    func headerTimeBelongsAbove() {
        let route = TransferGuide.read(jrEastRoute()).route
        #expect(route.legs[0].calls.first?.departure == "04:16")
        // The boundary: in at 05:58 on the first train, out at 06:03 on the
        // second, and neither leg carries the other's time.
        #expect(route.legs[0].calls.last?.arrival == "05:58")
        #expect(route.legs[0].calls.last?.departure == nil)
        #expect(route.legs[1].calls.first?.departure == "06:03")
        #expect(route.legs[1].calls.first?.arrival == nil)
        #expect(route.legs[1].calls.last?.arrival == "07:21")
    }

    @Test("the wordmark is not what identifies it")
    func identifiesWithoutTheLogo() {
        // Every JR East row from the body, and nothing from the footer or the
        // header — what is left after somebody crops the logo off.
        let full = jrEastRoute()
        let body = full.filter {
            !$0.text.contains("アプリ") && !$0.text.contains("移動距離")
                && !$0.text.contains("更新時刻")
        }
        #expect(TransferGuide.read(body).source == .jrEast)
        #expect(TransferGuide.read(body).route.legs.count == 2)
    }

    @Test("a Yahoo screenshot is still read as one")
    func stillReadsYahoo() {
        let read = TransferGuide.read(sapporoToHakata())
        #expect(read.source == .yahoo)
        #expect(read.route.legs.count == 3)
        #expect(read.route.legs[0].calls.map(\.name).first == "札幌")
    }

    @Test("a line printed mid-leg is not a second train")
    func throughLineIsNotALeg() {
        var shot = Screenshot()
        shot.row(("下関", 80))
        shot.row(("出発時刻を変更>", 78))
        shot.row(("16:23", 20), ("ＪＲ山陽本線", 130))
        shot.row(("当駅始発", 18), ("小倉行", 128))
        shot.row(("2駅目で降りる", 128))
        shot.row(("17:30着", 30), advance: 20)
        shot.row(("門司", 128), advance: 20)
        shot.row(("17:31発", 30))
        // The train runs on to another railway. JR East labels the new line
        // exactly as it labels a leg — this row even carries the arrival time
        // of the station below it.
        shot.row(("16:37", 20), ("ＪＲ鹿児島本線", 130))
        shot.row(("小倉", 80), ("1分", 200))
        let route = TransferGuide.read(shot.lines).route

        #expect(route.legs.count == 1)
        #expect(route.legs[0].service == "JR山陽本線")
        #expect(route.legs[0].throughServices == ["JR鹿児島本線"])
        #expect(route.legs[0].calls.map(\.name) == ["下関", "門司", "小倉"])
        #expect(route.legs[0].calls.last?.arrival == "16:37")
    }

    @Test("a station whose disambiguator is a line is still a station")
    func bracketedLineName() {
        // There are two 阿品 in Hiroshima, and JR East tells them apart by
        // writing the line in the bracket. Reading that as a railway split the
        // journey in half at it.
        #expect(TransferGuide.Text.stationName("阿品（山陽本線）").name == "阿品")
        #expect(TransferGuide.Text.stationName("阿品（山陽本線）").qualifier == "山陽本線")
        #expect(TransferGuide.Text.looksLikeStationName("阿品（山陽本線）"))
    }

    @Test("the badges JR East prints beside a station are not stations")
    func badgesAreNotStations() {
        for noise in ["KERT", "(ERT", "へ", "ン", "①"] {
            #expect(!TransferGuide.Text.looksLikeStationName(noise), "\(noise)")
        }
        #expect(TransferGuide.Text.stationName("小倉（福岡県）①").name == "小倉")
        // And 智頭急行 is a railway company, not an express service.
        #expect(TransferGuide.trainType(for: TransferGuide.Leg(service: "智頭急行")) == "普通")
        #expect(TransferGuide.trainType(for: TransferGuide.Leg(service: "JR鹿児島本線快速")) == "快速")
    }

    @Test("the kanji and katakana that look identical resolve to one station")
    func homoglyphs() {
        // 二ツ井 came back as ニツ丼: kanji 二 read as katakana ニ.
        #expect(TransferGuide.Text.matchKey("ニセコ") == TransferGuide.Text.matchKey("二セコ"))
        #expect(TransferGuide.Text.matchKey("力丸") == TransferGuide.Text.matchKey("カ丸"))
    }
}
