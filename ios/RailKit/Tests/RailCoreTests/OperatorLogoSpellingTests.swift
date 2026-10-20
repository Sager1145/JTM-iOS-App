import Testing

@testable import RailCore

/// Spelling fallback was removed. A logo is chosen from a registry operator id.
/// ``OperatorBranding/companyLabel(_:)`` remains a display shortening, and
/// ``OperatorBranding/operatorLogo(_:)`` still keys on the legal name.
struct OperatorLogoSpellingTests {

    @Test(arguments: [
        ("東日本旅客鉄道", "JR東日本"),
        ("北海道旅客鉄道", "JR北海道"),
        ("東海旅客鉄道", "JR東海"),
        ("西日本旅客鉄道", "JR西日本"),
        ("四国旅客鉄道", "JR四国"),
        ("九州旅客鉄道", "JR九州"),
    ])
    func companyLabelStillShortensJRLegalNames(legalName: String, label: String) {
        #expect(OperatorBranding.companyLabel(legalName) == label)
    }

    @Test func operatorLogoStillKeysOnTheLegalName() {
        #expect(OperatorBranding.operatorLogo("東日本旅客鉄道") != nil)
        #expect(OperatorBranding.operatorLogo("Nonexistent Railway") == nil)
    }
}
