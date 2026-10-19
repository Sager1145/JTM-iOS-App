import Foundation
import RailCore
import Testing

struct StationNameFieldsTests {
    private func emptyCatalog() throws -> Localization.Catalog {
        try .init(data: Data(#"{"sourceLanguage":"en","version":"1.0","strings":{}}"#.utf8))
    }

    @Test("Details retain every stored name with all map reading switches off",
          arguments: Localization.Language.allCases)
    func allNames(_ language: Localization.Language) throws {
        let row = Localization.StationReadingRow(
            kana: "とうきょう", romaji: "Tōkyō", zhHant: "東京", zhHans: "东京",
            ja: "東京", en: "Tokyo", katakana: "トウキョウ")
        let localization = Localization(
            catalog: try emptyCatalog(), language: language,
            readingPrefs: .init(kana: false, romaji: false, zh: false),
            stationReadings: .init(byCode: ["001000": row]))
        #expect(localization.nameReadingsList("東京", code: "001000").isEmpty)
        #expect(localization.stationNameFields("東京", code: "001000") == [
            .init(kind: .ja, text: "東京"), .init(kind: .en, text: "Tokyo"),
            .init(kind: .zhHant, text: "東京"), .init(kind: .zhHans, text: "东京"),
            .init(kind: .kana, text: "とうきょう"), .init(kind: .katakana, text: "トウキョウ"),
            .init(kind: .romaji, text: "Tōkyō"),
        ])
    }

    @Test("Station identity wins over a same-name fallback")
    func codeBeforeName() throws {
        let localization = Localization(
            catalog: try emptyCatalog(),
            stationReadings: .init(
                country: "TW",
                byCode: ["TRA-4080": .init(zhHant: "嘉義", en: "Chiayi")],
                byName: ["嘉義": .init(zhHant: "嘉義", en: "Alishan Chiayi")]))
        #expect(localization.stationNameFields("嘉義", code: "TRA-4080") == [
            .init(kind: .en, text: "Chiayi"), .init(kind: .zhHant, text: "嘉義"),
        ])
    }

    @Test("Missing names are omitted without inventing translations")
    func unavailableNames() throws {
        let localization = Localization(
            catalog: try emptyCatalog(),
            stationReadings: .init(
                country: "HK", byCode: ["MTR-ADM": .init(zhHant: "金鐘", ja: "", en: "Admiralty")]))
        #expect(localization.stationNameFields("金鐘", code: "MTR-ADM").map(\.kind) == [.en, .zhHant])
        #expect(localization.stationNameFields("Unknown").isEmpty)
        #expect(localization.stationNameFields(nil, code: "MTR-ADM").isEmpty)
    }

    @Test("Platform and group identities are tried before a same-name match")
    func platformAndGroupCodes() throws {
        let localization = Localization(
            catalog: try emptyCatalog(),
            stationReadings: .init(
                byCode: [
                    "line:group": .init(en: "Platform name"),
                    "group": .init(en: "Group name"),
                ],
                byName: ["Same name": .init(en: "Other station")]))
        #expect(localization.stationNameFields("Same name", code: "line:group", alternateCode: "group") == [
            .init(kind: .en, text: "Platform name"),
        ])
        #expect(localization.stationNameFields("Same name", code: "other-line:group", alternateCode: "group") == [
            .init(kind: .en, text: "Group name"),
        ])
    }

    @Test("A sparse platform row gains only its missing kinds from the exact official code")
    func sparsePlatformFillsFromOfficialCode() throws {
        // The bundled Marunouchi platform row for Tokyo has empty readings;
        // the official station row 003766 has them.
        let localization = Localization(
            catalog: try emptyCatalog(),
            stationReadings: .init(
                byCode: [
                    "jp-東京地下鉄-4号線丸ノ内線:003766": .init(
                        kana: "", romaji: "Tōkyō", zhHant: "東京", zhHans: "东京",
                        ja: "東京", en: "Tokyo", katakana: ""),
                    "003766": .init(
                        kana: "とうきょう", romaji: "Tokyo official", zhHant: "東京", zhHans: "东京",
                        ja: "東京駅", en: "Tokyo Station", katakana: "トウキョウ"),
                ],
                byName: ["東京": .init(kana: "ひがしきょう", katakana: "ヒガシキョウ")]))
        #expect(localization.stationNameFields(
            "東京", code: "jp-東京地下鉄-4号線丸ノ内線:003766", alternateCode: "003766") == [
            .init(kind: .ja, text: "東京"), .init(kind: .en, text: "Tokyo"),
            .init(kind: .zhHant, text: "東京"), .init(kind: .zhHans, text: "东京"),
            .init(kind: .kana, text: "とうきょう"), .init(kind: .katakana, text: "トウキョウ"),
            .init(kind: .romaji, text: "Tōkyō"),
        ])
        // Without an exact official row, a same-name row never fills the gaps.
        for alternate in [nil, "", "999999"] as [String?] {
            #expect(localization.stationNameFields(
                "東京", code: "jp-東京地下鉄-4号線丸ノ内線:003766", alternateCode: alternate
            ).map(\.kind) == [.ja, .en, .zhHant, .zhHans, .romaji])
        }
    }
}
