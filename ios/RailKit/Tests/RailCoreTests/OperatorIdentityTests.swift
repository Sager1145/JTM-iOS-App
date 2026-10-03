import Foundation
import Testing
@testable import RailCore

struct OperatorIdentityTests {
    @Test func multilingualIdentities() {
        let cases: [String: [String]] = [
            "jp.jr-west": ["JR西日本", "西日本旅客鉄道", "JR West", "JR-West", "西日本旅客铁道", "西日本旅客鐵道", "JR 서일본"],
            "jp.nishitetsu": ["西日本鉄道", "西鉄", "Nishitetsu"],
            "tw.tra": ["台鐵", "臺鐵", "台铁", "TRA", "Taiwan Railway"],
            "tw.taipei-metro": ["台北捷運", "台北捷运", "Taipei Metro", "타이베이 지하철"],
            "hk.mtr": ["港鐵", "港铁", "MTR"],
            "kr.korail": ["코레일", "KORAIL", "韩国铁道", "韓國鐵道"],
            "jp.toei": ["都営地下鉄", "Toei", "都营地铁"]
        ]
        for (code, names) in cases {
            for name in names { #expect(OperatorIdentity.code(for: name) == code, "\(name)") }
        }
        #expect(!OperatorIdentity.sameCompany("西日本鉄道", "JR西日本"))
        #expect(!OperatorIdentity.sameCompany("東京急行電鉄", "東京地下鉄"))
        #expect(OperatorIdentity.sameCompany("JR West / JR東日本", "西日本旅客鉄道"))
        #expect(OperatorIdentity.sameCompany("Unknown", "Unknown"))
    }

    @Test func inclusiveFamiliesAndRanking() {
        for query in ["东京地铁", "東京地下鉄", "東京の地下鉄", "도쿄 지하철", "Tokyo subway", "Tokyo 地铁"] {
            let codes = Set(OperatorIdentity.matchingCodes(query: query))
            #expect(Set(["jp.tokyo-metro", "jp.toei"]).isSubset(of: codes), "\(query)")
        }
        #expect(OperatorIdentity.matchingCodes(query: "Tokyo Metro").first == "jp.tokyo-metro")
        #expect(OperatorIdentity.matches(operatorName: "JR西日本", query: "JR西日本 West"))
        #expect(OperatorIdentity.matches(operatorName: "東京メトロ", query: "东京メトロ"))
        #expect(OperatorIdentity.matches(operatorName: "서울교통공사", query: "首尔 지하철"))
        #expect(OperatorIdentity.displayName(code: "jp.jr-west", language: "missing") == "JR西日本")
    }

    @Test func catalogAndTimetableUseOperatorAliases() throws {
        let patterns = TrainServicePatterns.search("JR West")
        #expect(!patterns.isEmpty)
        let pattern = try #require(patterns.first { OperatorIdentity.sameCompany($0.company, "JR West") })
        #expect(TimetableSearch("西日本旅客鐵道").matches(pattern))
        #expect(TrainServicePatterns.search("", filter: .init(company: "jp.jr-west"))
            .contains { $0.id == pattern.id })
    }

    @Test func registryCoverageAndUniqueness() throws {
        let registry = OperatorIdentity.registry
        let codes = Set(registry.operators.map(\.code))
        #expect(codes.count == registry.operators.count)
        let familyCodes = Set(registry.families.map(\.code))
        #expect(familyCodes.count == registry.families.count)
        var index: [String: Set<String>] = [:]
        for op in registry.operators {
            #expect(!op.code.isEmpty && op.code.hasPrefix(op.region + "."))
            #expect(op.label == OperatorBranding.companyLabel(op.legal), "\(op.code)")
            #expect(Set(op.families).isSubset(of: familyCodes))
            for name in op.searchNames {
                let key = SearchFold.fold(name)
                #expect(!key.isEmpty, "\(op.code): \(name)")
                index[key, default: []].insert(op.code)
            }
        }
        for (key, matches) in index { #expect(matches.count == 1, "Ambiguous \(key): \(matches)") }
        for family in registry.families {
            #expect(!family.code.isEmpty)
            #expect(Set(family.members).isSubset(of: codes))
        }
        let root = try PortFixtures.repositoryRoot()
        func json(_ path: String) throws -> Any {
            try JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: path)))
        }
        var sources: [String: Set<String>] = [:]
        func add(_ value: Any?, source: String, split: Bool = false) {
            guard let value = value as? String else { return }
            let parts = split ? value.components(separatedBy: CharacterSet(charactersIn: "/／")) : [value]
            for part in parts {
                let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { sources[name, default: []].insert(source) }
            }
        }
        for region in ["jp", "tw", "hk", "mo", "kr"] {
            let data = try #require(json("app/public/rail/\(region)-2025.json") as? [String: Any])
            let lines = try #require(data["lines"] as? [[String: Any]])
            for line in lines {
                add(line["operator"], source: "compact:\(region)")
                add(line["operatorShort"], source: "compactShort:\(region)")
            }
        }
        let stationFiles = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "app/data").path)
            .filter { $0.hasPrefix("stations") && $0.hasSuffix(".json") }
        #expect(!stationFiles.isEmpty)
        for file in stationFiles {
            let data = try #require(json("app/data/\(file)") as? [String: Any])
            for feature in try #require(data["features"] as? [[String: Any]]) {
                add((feature["properties"] as? [String: Any])?["operator"], source: file)
            }
        }
        func walk(_ node: Any) {
            if let object = node as? [String: Any] {
                add(object["company"], source: "patterns", split: true)
                for value in object.values { walk(value) }
            } else if let array = node as? [Any] { for value in array { walk(value) } }
        }
        walk(try json("ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json"))
        let store = try #require(json("app/data/train-store.json") as? [String: Any])
        for train in try #require(store["trains"] as? [[String: Any]]) {
            add(train["company"], source: "train-store", split: true)
        }
        // Read the actual label tables, including keys and values, so new labels require registry coverage.
        let swift = try String(contentsOf: root.appending(path: "ios/RailKit/Sources/RailCore/OperatorBranding.swift"), encoding: .utf8)
        let pair = try NSRegularExpression(pattern: #"\("((?:\\.|[^"\\])*)",\s*"((?:\\.|[^"\\])*)"\)"#)
        func decodeSwift(_ raw: String) throws -> String {
            var value = raw
            let unicode = try NSRegularExpression(pattern: #"\\u\{([0-9a-fA-F]+)\}"#)
            for match in unicode.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).reversed() {
                let digits = String(raw[Range(match.range(at: 1), in: raw)!])
                if let number = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(number), let range = Range(match.range, in: value) {
                    value.replaceSubrange(range, with: String(scalar))
                }
            }
            return value.replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\\"#, with: "\\")
        }
        for marker in ["companyLabelPairs: [(String, String)] = [", "taiwanCompanyLabels = CodeUnitTable([", "hongKongCompanyLabels = CodeUnitTable([", "macaoCompanyLabels = CodeUnitTable(["] {
            let start = try #require(swift.range(of: marker)).upperBound
            let end = try #require(swift[start...].range(of: "]")).lowerBound
            let block = String(swift[start..<end])
            let matches = pair.matches(in: block, range: NSRange(block.startIndex..., in: block))
            #expect(!matches.isEmpty)
            for match in matches {
                for group in [1, 2] { add(try decodeSwift(String(block[Range(match.range(at: group), in: block)!])), source: marker) }
            }
        }
        for (name, tags) in sources {
            #expect(index[SearchFold.fold(name)]?.count == 1, "Unresolved/ambiguous \(name): \(tags)")
            #expect(OperatorIdentity.code(for: name) != nil, "Lookup failed: \(name)")
        }
        print("Operator registry coverage: \(registry.operators.count) operators, \(registry.families.count) families, \(sources.count) source strings")
    }
}
