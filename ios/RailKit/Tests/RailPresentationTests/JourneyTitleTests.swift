import Foundation
import RailCore
import RailPresentation
import Testing

/// What the compact panel header may say — see ``JourneyTitle``.
///
/// Every `number` below is a value out of a committed store rather than an
/// invented one. That is the point of the suite: the rule is a reading of what
/// the archive actually contains, and a case written to suit the rule would
/// only prove the rule agrees with itself.
struct JourneyTitleTests {

    func train(number: String, trainType: String?) -> Train {
        Train(
            id: "t-1", date: "2026-07-26", number: number, trainType: trainType,
            company: nil, origin: "東京", destination: "熱海", direction: nil,
            stops: [
                Stop(name: "東京", departure: "09:00", rideSegment: true),
                Stop(name: "熱海", arrival: "10:19", rideSegment: false),
            ])
    }

    func title(_ number: String, _ trainType: String?) -> String {
        JourneyTitle.compact(train(number: number, trainType: trainType))
    }

    // MARK: - what the reader asked to stop seeing

    @Test
    func dropsTheDepartureTimeDestinationAndThroughServiceNote() {
        // The case that prompted the rule, from the JR East records: one line
        // of header, and four facts in it that the subtitle and the map are
        // already carrying.
        #expect(title("普通（08:05 我孫子行・東京メトロ千代田線から直通）", "普通") == "普通")
    }

    @Test
    func dropsTheRomajiGlossAndKeepsTheLocalName() {
        #expect(title("東海道本線 普通（Tōkaidō Main Line Local）", "普通") == "東海道本線 普通")
        #expect(title("京急・浅草線（Keikyū / Asakusa Line）", "普通") == "普通 京急・浅草線")
        #expect(title("普通列車（Local）", "普通") == "普通列車")
    }

    @Test
    func dropsAnEndpointAside() {
        #expect(title("台灣高鐵 165次（台北→台中）", "高鐵") == "台灣高鐵 165次")
        #expect(
            title("桃園機場捷運 直達車（機場第二航廈站→台北車站）", "直達車")
                == "桃園機場捷運 直達車")
    }

    // MARK: - what is kept

    @Test
    func keepsTheTrainNumberWhenTheRecordKnowsOne() {
        #expect(title("埼京線（Saikyō Line）（1201F）", "快速") == "快速 埼京線（1201F）")
        #expect(
            title("湘南新宿ライン（Shōnan-Shinjuku Line）（4835Y）", "特別快速")
                == "特別快速 湘南新宿ライン（4835Y）")
    }

    @Test
    func aLimitedExpressKeepsItsOwnNameAndNumber() {
        #expect(title("はるか38号（Haruka 38）（1038M）", "特急") == "特急 はるか38号（1038M）")
        #expect(title("こだま号（Kodama）（846A）", "新幹線") == "新幹線 こだま号（846A）")
    }

    @Test
    func keepsABracketThatIsPartOfTheNameItself() {
        // 自強(3000) is a class of train, not an aside — and the ASCII
        // brackets it is written with are the ones a naive "cut at the first
        // bracket" would have cut at, losing the 車次 that follows.
        #expect(title("自強(3000) 137次（臺中→彰化）", "自強(3000)") == "自強(3000) 137次")
        #expect(title("區間 3262次（新烏日→臺中）", "區間") == "區間 3262次")
    }

    // MARK: - the 種別

    @Test
    func leadsWithTheTypeOnlyWhenTheNameDoesNotAlreadyCarryIt() {
        #expect(title("埼京線", "快速") == "快速 埼京線")
        #expect(title("東海道本線 普通", "普通") == "東海道本線 普通")
        #expect(title("경북선 공식 노선 예시", nil) == "경북선 공식 노선 예시")
        #expect(title("東鐵綫 官方路線示例", "") == "東鐵綫 官方路線示例")
    }

    // MARK: - a header is never blank

    @Test
    func aNameThatIsNothingButAsidesFallsBackToTheRecordsOwnText() {
        #expect(title("（Local）", nil) == "（Local）")
    }

    @Test
    func anUnclosedBracketIsKeptWholeRatherThanEatingTheName() {
        // Malformed either way; the reader keeps the caption they had rather
        // than losing the journey's identity to a missing character.
        #expect(title("普通（08:05 我孫子行", "普通") == "普通（08:05 我孫子行")
    }
}
