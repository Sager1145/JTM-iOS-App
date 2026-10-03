import Testing
@testable import RailCore

struct SearchFoldTests {
    @Test func normalization() {
        #expect(SearchFold.fold("ＪＲ・West") == SearchFold.fold("jr-west"))
        #expect(SearchFold.fold("Café") == "cafe")
        #expect(SearchFold.fold("ひろでん") == SearchFold.fold("ヒロデン"))
        #expect(SearchFold.fold("が") != SearchFold.fold("か"))
        #expect(SearchFold.fold("鉄鐵営広浜沢関県気発図線東電車臺") == "铁铁营广滨泽关县气发图线东电车台")
        #expect(SearchFold.fold("駅") != SearchFold.fold("站"))
        #expect(SearchFold.fold("株式会社 JR West Co., Ltd.") == "株式会社jrwestcoltd")
        #expect(SearchFold.fold("Lincoln") == "lincoln")
        #expect(SearchFold.fold("Incheon") == "incheon")
        #expect(SearchFold.fold("Coast Co.") == "coastco")
    }
    @Test func scriptTokens() {
        #expect(SearchFold.tokens("JR西日本 West") == ["jr", "西日本", "west"])
        #expect(SearchFold.tokens("首尔 지하철") == ["首尔", "지하철"])
    }
    @Test func multilingualSynonyms() {
        for query in ["地下鉄", "地鐵", "捷運", "subway", "지하철"] {
            #expect(SearchFold.matches(query: query, fields: ["Metro"]))
        }
        #expect(SearchFold.matches(query: "Tokyo 地铁", fields: ["Tokyo Metro"]))
        #expect(SearchFold.matches(query: "limited express", fields: ["特急"]))
        #expect(SearchFold.matches(query: "electric railway", fields: ["電鐵"]))
        #expect(SearchFold.matches(query: "東京站", fields: ["東京駅"]))
        #expect(SearchFold.matches(query: "JR西日本 West", fields: ["JR西日本", "JR West"]))
        #expect(!SearchFold.matches(query: "Tokyo railway", fields: ["Osaka Metro"]))
    }
    @Test func precisionRegressions() {
        for query in ["株式会社", "有限公司", "co", "limited", "!!!"] {
            #expect(!SearchFold.matches(query: query, fields: ["Tokyo Metro"]))
        }
        #expect(OperatorIdentity.matchingCodes(query: "!!!").isEmpty)
        #expect(!SearchFold.matches(query: "501", fields: ["2024-05-01"]))
        #expect(!SearchFold.matches(query: "405", fields: ["10:05", "2024-05-01"]))
        #expect(SearchFold.matches(query: "501", fields: ["のぞみ501号"]))
        #expect(SearchFold.fold("limited express") == "limitedexpress")
        #expect(!SearchFold.matches(query: "역", fields: ["station"]))
        for (query, name) in [("神户", "神戸"), ("后乐园", "後楽園"), ("涩谷", "渋谷"), ("樱木町", "桜木町"), ("霞ケ関", "霞ヶ関"), ("霞ケ関", "霞ヵ関")] {
            #expect(SearchFold.matches(query: query, fields: [name]))
        }
    }
}
