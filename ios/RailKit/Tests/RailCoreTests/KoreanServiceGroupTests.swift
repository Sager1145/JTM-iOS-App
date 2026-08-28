import Testing

@testable import RailCore

// =========================================================================
//  Korea's own service vocabulary, which the fixtures do not cover.
//
//  `port-fixtures/stats.json` has one Korean case — 특급 → other — and its
//  own `why` says "Only jp and tw have their own vocabulary; every other
//  country falls through to Japan's rules." That was true of the JavaScript
//  once. It stopped being true when `app-stats.js` grew a `kr` branch, and
//  because the fixture was never regenerated the parity suite went on
//  asserting the older belief — 350 green tests said nothing about whether a
//  KTX ride was counted as high speed. It was not: every Korean journey's
//  kilometres landed in 其他列車 while 高速鐵道（KTX・SRT） read 0.0 km.
//
//  These cases are written against `app/public/app-stats.js:517-526`
//  directly, because that is the reference the fixture should have carried.
//  They are the answer the JavaScript gives.
// =========================================================================

@Suite("Korean services are classified the way the reference classifies them")
struct KoreanServiceGroupTests {

    private func group(_ trainType: String) -> String {
        Statistics.serviceGroupOfTrain(trainType: trainType, country: "kr")
    }

    @Test("KTX, SRT and 고속 are high speed")
    func highSpeed() {
        for name in ["KTX", "KTX-산천", "SRT", "고속열차", "KTX-이음"] {
            #expect(group(name) == "hsr", "\(name) was \(group(name)), not hsr")
        }
    }

    /// `/KTX|SRT|고속/i` carries the `i` flag, so the ASCII half folds.
    @Test("the high-speed test is case-insensitive, as its regex is")
    func highSpeedFolds() {
        for name in ["ktx", "Ktx-산천", "srt"] {
            #expect(group(name) == "hsr", "\(name) was \(group(name)), not hsr")
        }
    }

    @Test("ITX, 새마을 and 무궁화 are the reserved-seat tier")
    func reservedSeat() {
        for name in ["ITX-새마을", "ITX-마음", "무궁화호", "새마을호", "セマウル", "ムグンファ", "無窮花"] {
            #expect(group(name) == "ltd", "\(name) was \(group(name)), not ltd")
        }
    }

    /// The second regex carries no `i` flag, so its ASCII half does NOT fold.
    /// Faithfulness here matters more than tidiness: the two ends have to
    /// disagree in the same places or they do not agree at all.
    @Test("the reserved-seat test is case-sensitive, as its regex is")
    func reservedSeatDoesNotFold() {
        #expect(group("itx-새마을") == "ltd", "the Hangul half should still match")
        #expect(group("itx") == "other", "lower-case itx alone must not match")
    }

    @Test("anything else is other, including the case the fixture does carry")
    func everythingElse() {
        for name in ["특급", "일반", "", "누리로"] {
            #expect(group(name) == "other", "\(name) was \(group(name)), not other")
        }
    }

    /// Korea must not pick up Japan's words now that it has its own branch.
    @Test("Korea no longer falls through to Japan's vocabulary")
    func koreaDoesNotUseJapaneseWords() {
        #expect(Statistics.serviceGroupOfTrain(trainType: "特急", country: "kr") == "other")
        #expect(Statistics.serviceGroupOfTrain(trainType: "特急", country: "jp") == "ltd")
    }
}
