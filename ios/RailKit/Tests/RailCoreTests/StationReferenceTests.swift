import Foundation
import Testing

@testable import RailCore

struct StationReferenceTests {
    @Test("bare, country, line, and country-plus-line forms")
    func grammar() {
        let cases: [(String, String, String?, String?, Bool)] = [
            ("府中", "府中", nil, nil, false),
            ("  府中  ", "府中", nil, nil, false),
            ("府中\u{3000}(JP)", "府中", "JP", nil, false),
            ("府中 (JP)", "府中", "JP", nil, false),
            ("府中 (jp)", "府中", "JP", nil, false),
            ("府中（ｊｐ）", "府中", "JP", nil, false),
            ("府中 (tw)", "府中", "TW", nil, false),
            ("府中 (HK)", "府中", "HK", nil, false),
            ("府中 (mo)", "府中", "MO", nil, false),
            ("府中 (Kr)", "府中", "KR", nil, false),
            ("府中 (CN)", "府中", "CN", nil, false),
            ("府中 (京王線)", "府中", nil, "京王線", false),
            ("府中 (US)", "府中", nil, "US", false),
            ("府中 (CA)", "府中", nil, "CA", false),
            ("府中(JP,京王線)", "府中", "JP", "京王線", false),
            ("府中 (JP, 京王線)", "府中", "JP", "京王線", false),
            ("府中 （JP，京王線）", "府中", "JP", "京王線", false),
            ("府中 (JP、京王線)", "府中", "JP", "京王線", false),
            ("府中 (JP·京王線)", "府中", nil, "JP·京王線", false),
            ("府中 (JP・京王線)", "府中", nil, "JP・京王線", false),
            ("府中 (JP, 日暮里・舎人ライナー)", "府中", "JP", "日暮里・舎人ライナー", false),
            ("府中 ( JP , 京王線 )", "府中", "JP", "京王線", false),
            ("浜松町 (JP, MO)", "浜松町", "JP", "MO", false),
            ("浜松町 (MO)", "浜松町", "MO", nil, false),
            ("浜松町 (mo)", "浜松町", "MO", nil, false),
            ("府中 (JP, 京王線) 09:03", "府中", "JP", "京王線", false),
            ("府中 (JP, 1号線(御堂筋線))", "府中", "JP", "1号線(御堂筋線)", false),
            ("府中（JP，1号線（御堂筋線））", "府中", "JP", "1号線（御堂筋線）", false),
            ("府中 (JP, 京王線, 南武線)", "府中", "JP", "京王線, 南武線", false),
            ("府中 (US, Acela)", "府中", nil, "Acela", true),
            ("府中 (CA, VIA)", "府中", nil, "VIA", true),
            ("府中 ()", "府中", nil, nil, false),
            ("府中 (JP,)", "府中", "JP", nil, false),
        ]
        for item in cases {
            let parsed = StationReference.parse(item.0)
            #expect(parsed?.name == item.1, Comment(rawValue: item.0))
            #expect(parsed?.country == item.2, Comment(rawValue: item.0))
            #expect(parsed?.line == item.3, Comment(rawValue: item.0))
            #expect(parsed?.unsupportedCountry == item.4, Comment(rawValue: item.0))
        }
    }

    @Test("empty input and a bracket with no station name do not parse")
    func rejectsEmpty() {
        #expect(StationReference.parse("") == nil)
        #expect(StationReference.parse("   ") == nil)
        #expect(StationReference.parse("(JP)") == nil)
        #expect(StationReference.parse("（京王線）") == nil)
    }

    @Test("an unclosed bracket stays part of the name")
    func unclosedBracket() {
        let parsed = StationReference.parse("府中 (JP")
        #expect(parsed?.name == "府中 (JP")
        #expect(parsed?.country == nil)
        #expect(parsed?.line == nil)
    }

    @Test("the catalog search ignores everything inside the brackets")
    func nameScopeStopsAtTheBracket() {
        #expect(StationReference.nameScope(in: "府中 (JP, 京王線) 09:03") == "府中")
        #expect(StationReference.nameScope(in: "東京 09:03 発") == "東京 09:03 発")
        #expect(StationReference.nameScope(in: "  浜松町 (MO) ") == "浜松町")
    }

    @Test("a qualifier bracket may sit against a stored official name")
    func qualifierTouchesOfficialName() {
        let directory = StationNameDirectory(
            bracketedNames: [
                "西鉄福岡（天神）": StationNameRecord(
                    base: "西鉄福岡", bracket: "天神", kind: .subname, position: .suffix),
            ],
            baseNameCounts: ["西鉄福岡": 1])
        let parsed = StationReference.parse("西鉄福岡（天神）(JP, 天神大牟田線)", names: directory)
        #expect(parsed?.name == "西鉄福岡（天神）")
        #expect(parsed?.country == "JP")
        #expect(parsed?.line == "天神大牟田線")
    }
}
