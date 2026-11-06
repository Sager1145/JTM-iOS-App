import Foundation
import RailCore

import Testing

struct ServiceCaptionTests {
    @Test(arguments: [
        ("根室本線 普通 (Nemuro Main Line Local) (5625D)", "根室本線 普通 (5625D)", "Nemuro Main Line Local"),
        ("はるか38号 (Haruka 38) (1038M)", "はるか38号 (1038M)", "Haruka 38"),
        ("こだま号 (Kodama) (846A)", "こだま号 (846A)", "Kodama"),
        ("おおぞら３号 (Ōzora 3) (4003D)", "おおぞら３号 (4003D)", "Ōzora 3"),
        ("  KTX 산천 (KTX-Sancheon) (101)  ", "KTX 산천 (101)", "KTX-Sancheon"),
    ])
    func liftsTheLatinNameOutOfTheJapaneseShape(
        caption: String, primary: String, latin: String
    ) {
        let split = ServiceCaption.split(caption)
        #expect(split.primary == primary)
        #expect(split.latinName == latin)
    }

    @Test(arguments: [
        // No Latin group: the trailing group is the only one.
        "のぞみ1号 (1A)",
        // Full-width parentheses are a destination, not a name.
        "自強(3000) 125次（嘉義→高雄）",
        "台灣高鐵 161次（南港→台北）",
        // No parentheses at all.
        "東鐵綫 官方路線示例",
        "경북선 공식 노선 예시",
        // The first group is not Latin.
        "はやぶさ (こまち) (5B)",
        // The head is not a native-script name.
        "Amtrak Cascades (Seattle) (503)",
        // Empty groups are not a shape.
        "ひかり () (500A)",
        "ひかり (Hikari) ()",
        "",
    ])
    func leavesEveryOtherCaptionWhole(caption: String) {
        let split = ServiceCaption.split(caption)
        #expect(split.primary == caption)
        #expect(split.latinName == nil)
    }

    private static func makeTrain(id: String, number: String, numberEn: String? = nil) -> Train {
        Train(
            id: id,
            number: number,
            numberEn: numberEn,
            origin: "A",
            destination: "B",
            stops: [
                Stop(name: "A"),
                Stop(name: "B"),
            ])
    }

    @Test func migrateLegacyCaptionsReturnsNilWhenNothingChanges() {
        let trains = [
            Self.makeTrain(id: "1", number: "のぞみ1号 (1A)"),
            Self.makeTrain(id: "2", number: "根室本線 普通 (5625D)", numberEn: "Nemuro Main Line Local"),
        ]
        #expect(ServiceCaption.migrateLegacyCaptions(trains) == nil)
    }

    @Test func migrateLegacyCaptionsSplitsOnlyTrainsMissingNumberEn() {
        let trains = [
            Self.makeTrain(id: "1", number: "はるか38号 (Haruka 38) (1038M)"),
            Self.makeTrain(id: "2", number: "のぞみ1号 (1A)"),
        ]
        guard let migrated = ServiceCaption.migrateLegacyCaptions(trains) else {
            Issue.record("expected a migration")
            return
        }
        #expect(migrated[0].number == "はるか38号 (1038M)")
        #expect(migrated[0].numberEn == "Haruka 38")
        #expect(migrated[1].number == "のぞみ1号 (1A)")
        #expect(migrated[1].numberEn == nil)
    }

    @Test func migrateLegacyCaptionsLeavesAnExplicitNumberEnUntouched() {
        let trains = [
            Self.makeTrain(
                id: "1", number: "はるか38号 (Haruka 38) (1038M)", numberEn: "Already Set")
        ]
        #expect(ServiceCaption.migrateLegacyCaptions(trains) == nil)
    }
}
