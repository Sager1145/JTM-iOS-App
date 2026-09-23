import Testing

@testable import RailCore

/// `OperatorBranding.operatorLogo(_:)` is keyed on legal names, but an
/// itinerary's `company` field holds the short label — sometimes several,
/// "/"-joined. ``OperatorBranding/legalNames(forLabel:)`` and
/// ``OperatorBranding/operatorLogoForAnySpelling(_:)`` are the bridge back to
/// the legal-name-keyed tables; these tests hold that bridge to the JR
/// companies, whose short labels are the ones itinerary records actually
/// carry.
struct OperatorLogoSpellingTests {

    @Test func legalNamesForJREastLabel() {
        #expect(OperatorBranding.legalNames(forLabel: "JR東日本").contains("東日本旅客鉄道"))
    }

    @Test(arguments: [
        ("JR東日本", "東日本旅客鉄道"),
        ("JR北海道", "北海道旅客鉄道"),
        ("JR東海", "東海旅客鉄道"),
        ("JR西日本", "西日本旅客鉄道"),
        ("JR四国", "四国旅客鉄道"),
        ("JR九州", "九州旅客鉄道"),
    ])
    func operatorLogoForAnySpellingMatchesLegalName(label: String, legalName: String) {
        let viaLabel = OperatorBranding.operatorLogoForAnySpelling(label)
        let viaLegalName = OperatorBranding.operatorLogo(legalName)
        #expect(viaLabel != nil)
        #expect(viaLabel == viaLegalName)
    }

    @Test func operatorLogoForAnySpellingResolvesJointOperators() {
        let joint = OperatorBranding.operatorLogoForAnySpelling("JR東日本/JR西日本")
        let jrEastOnly = OperatorBranding.operatorLogoForAnySpelling("JR東日本")
        #expect(joint != nil)
        #expect(joint == jrEastOnly)
    }

    @Test func operatorLogoForAnySpellingReturnsNilForUnknownOperator() {
        #expect(OperatorBranding.operatorLogoForAnySpelling("Nonexistent Railway") == nil)
    }
}
