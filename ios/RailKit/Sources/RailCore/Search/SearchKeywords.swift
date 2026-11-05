import Foundation

/// Type keywords in every UI language, company-name suffixes and known brands,
/// all held as canonical keys.
enum SearchKeywords {
    private static func keys(_ words: [String]) -> [[UInt16]] {
        Array(Set(words.map { SearchNormalizer.canonical($0) }.filter { !$0.isEmpty }))
            .sorted { $0.count > $1.count }
    }

    /// Line type: 線/线/선/Line/号线/號線/호선/新幹線/Shinkansen.
    static let lineSuffixes = keys([
        "新幹線", "新干线", "shinkansen", "신칸센", "号线", "號線", "호선", "線", "线", "綫", "선", "line",
    ])
    /// Station type: 駅/站/역/Station.
    static let stationSuffixes = keys(["駅", "站", "車站", "车站", "역", "station", "sta", "stn", "eki"])
    /// Company type: 鉄道/铁路/鐵路/電鉄/Metro/Railway/公司/交通局/공사 …
    static let companySuffixes = keys([
        "電気鉄道", "旅客鉄道", "高速鉄道", "鉄道", "鐵道", "铁路", "鐵路", "電鉄", "电铁", "電鐵", "電気軌道",
        "地下鉄", "交通局", "交通", "電車", "公司", "有限公司", "株式会社", "공사", "철도", "교통공사",
        "railway", "railways", "railroad", "metro", "electricrailway", "corporation",
    ])
    /// Pure keywords that only say which kind of thing is wanted.
    static let lineWords = Set(keys(["線", "line", "lines", "路線", "线路", "線路", "노선", "新幹線", "shinkansen"]))
    static let stationWords = Set(keys(["駅", "站", "車站", "车站", "역", "station", "stations", "sta", "stn", "eki"]))
    static let companyWords = Set(keys(["鉄道", "铁路", "railway", "公司", "会社", "operator", "company", "회사", "운영사"]))

    static func stripLineSuffix(_ key: [UInt16]) -> [UInt16]? {
        strip(key, lineSuffixes)
    }

    static func stripStationSuffix(_ key: [UInt16]) -> [UInt16]? {
        strip(key, stationSuffixes)
    }

    static func stripCompanySuffix(_ key: [UInt16]) -> [UInt16]? {
        strip(key, companySuffixes)
    }

    static func hasLineSuffix(_ key: [UInt16]) -> Bool { stripLineSuffix(key) != nil }

    private static func strip(_ key: [UInt16], _ suffixes: [[UInt16]]) -> [UInt16]? {
        for suffix in suffixes where key.count > suffix.count && key.suffix(suffix.count).elementsEqual(suffix) {
            return Array(key.dropLast(suffix.count))
        }
        return nil
    }

    /// Brand spellings that name the same operator. A company document that
    /// matches any spelling of a group (exactly) gets the whole group as aliases.
    static let brandGroups: [[String]] = [
        ["JR東日本", "JR East", "JR东日本", "東日本旅客鉄道", "JR-East", "제이알 동일본"],
        ["JR東海", "JR Central", "JR东海", "東海旅客鉄道"],
        ["JR西日本", "JR West", "JR西日本", "西日本旅客鉄道"],
        ["JR北海道", "JR Hokkaido", "北海道旅客鉄道"],
        ["JR九州", "JR Kyushu", "九州旅客鉄道"],
        ["JR四国", "JR Shikoku", "四国旅客鉄道"],
        ["東急", "東急電鉄", "Tokyu", "東京急行電鉄", "东急", "도큐"],
        ["東京メトロ", "Tokyo Metro", "東京地下鉄", "东京地铁", "메트로", "東京Metro"],
        ["都営", "都営地下鉄", "東京都交通局", "東京都", "Toei", "Toei Subway"],
        ["小田急", "小田急電鉄", "Odakyu"],
        ["京王", "京王電鉄", "Keio"],
        ["西武", "西武鉄道", "Seibu"],
        ["東武", "東武鉄道", "Tobu"],
        ["京急", "京浜急行", "京浜急行電鉄", "Keikyu"],
        ["京成", "京成電鉄", "Keisei"],
        ["相鉄", "相模鉄道", "Sotetsu"],
        ["阪急", "阪急電鉄", "Hankyu"],
        ["阪神", "阪神電気鉄道", "Hanshin"],
        ["京阪", "京阪電気鉄道", "Keihan"],
        ["近鉄", "近畿日本鉄道", "Kintetsu"],
        ["南海", "南海電気鉄道", "Nankai"],
        ["名鉄", "名古屋鉄道", "Meitetsu"],
        ["西鉄", "西日本鉄道", "Nishitetsu"],
        ["大阪メトロ", "Osaka Metro", "大阪市高速電気軌道", "大阪地铁"],
        ["りんかい線", "東京臨海高速鉄道", "TWR", "Rinkai"],
        ["つくばエクスプレス", "首都圏新都市鉄道", "Tsukuba Express", "TX"],
        ["江ノ電", "江ノ島電鉄", "Enoden", "Enoshima Electric Railway"],
        ["Korail", "코레일", "한국철도공사", "韓国鉄道公社", "韩国铁道公社", "韓國鐵道公社", "KORAIL"],
        ["서울교통공사", "Seoul Metro", "首尔交通公社", "ソウル交通公社"],
        ["MTR", "港鐵", "港铁", "香港鐵路", "香港铁路", "MTR Corporation"],
        ["台鐵", "臺鐵", "台铁", "TRA", "臺灣鐵路", "台灣鐵路", "台湾铁路", "Taiwan Railway", "台湾鉄道"],
        ["台灣高鐵", "高鐵", "THSR", "Taiwan High Speed Rail", "台湾高铁", "台湾新幹線"],
        ["台北捷運", "北捷", "Taipei Metro", "台北地铁", "TRTC"],
        ["澳門輕軌", "輕軌", "Macao LRT", "Macau LRT", "澳门轻轨"],
    ]

    /// Brand-group canonical keys, by any member key.
    static let brandAliases: [[UInt16]: [String]] = {
        var table: [[UInt16]: [String]] = [:]
        for group in brandGroups {
            for name in group {
                let key = SearchNormalizer.canonical(name)
                guard !key.isEmpty else { continue }
                table[key, default: []].append(contentsOf: group)
            }
        }
        return table
    }()

    /// Synonym groups for free-text matching (journey fields).
    static let synonyms: [[[UInt16]]] = [
        ["地铁", "地下鉄", "地下铁", "捷运", "subway", "metro", "지하철"],
        ["铁路", "铁道", "railway", "railroad", "철도"],
        ["电车", "電鐵", "electric railway"],
        ["新干线", "新幹線", "shinkansen", "신칸센"],
        ["特急", "特快", "limited express", "특급"],
        ["站", "駅", "station", "기차역"],
    ].map { group in Array(Set(group.map { SearchNormalizer.canonical($0) })) }
}
