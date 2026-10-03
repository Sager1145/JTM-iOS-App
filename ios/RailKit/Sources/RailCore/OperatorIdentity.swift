import Foundation

/// Stable operator identities. Families are a separate namespace and expand discovery only.
public enum OperatorIdentity {
    struct Operator: Decodable, Sendable {
        let code: String
        let region: String
        let legal: String
        let label: String
        let names: [String: [String]]
        let aliases: [String]
        let families: [String]
        var searchNames: [String] { [legal, label] + names.keys.sorted().flatMap { names[$0] ?? [] } + aliases }
    }
    struct Family: Decodable, Sendable {
        let code: String
        let names: [String: [String]]
        let members: [String]
        var searchNames: [String] { names.keys.sorted().flatMap { names[$0] ?? [] } }
    }
    struct Registry: Decodable, Sendable {
        let version: Int
        let operators: [Operator]
        let families: [Family]
    }
    static let registry: Registry = {
        guard let url = Bundle.module.url(forResource: "operator-identities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(Registry.self, from: data) else {
            preconditionFailure("Missing or invalid operator identity registry")
        }
        return result
    }()
    private static let byCode = Dictionary(uniqueKeysWithValues: registry.operators.map { ($0.code, $0) })
    private static let exact: [String: Set<String>] = {
        var result: [String: Set<String>] = [:]
        for op in registry.operators {
            for name in op.searchNames {
                for indexed in [name, registryName(name)] {
                    let key = SearchFold.fold(indexed)
                    if !key.isEmpty { result[key, default: []].insert(op.code) }
                }
            }
        }
        return result
    }()

    // Legal affixes belong only to registry indexing, never query normalization.
    private static func registryName(_ name: String) -> String {
        var result = name.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(of: #"^(?:株式会社|有限会社|\(주\))\s*"#,
            with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"(?:股份有限公司|有限公司|株式会社|有限会社|주식회사|\(株\)|\(주\)|(?<![a-z])(?:incorporated|corporation|limited|company|co\.?\s*,?\s*ltd\.?|coltd|ltd|inc|co)\.?)\s*$"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        return result
    }

    /// Whole-query operator or family identity; nil permits broader discovery.
    public static func exactCodes(query: String) -> Set<String>? {
        let folded = SearchFold.fold(query)
        guard !folded.isEmpty else { return nil }
        let families = registry.families.filter {
            SearchFold.fold($0.code) == folded || $0.searchNames.contains { SearchFold.fold($0) == folded }
        }
        if !families.isEmpty { return Set(families.flatMap(\.members)) }
        return code(for: query).map { [$0] }
    }

    public static func code(for name: String) -> String? {
        if byCode[name] != nil { return name }
        for candidate in [name] {
            if let codes = exact[SearchFold.fold(candidate)], codes.count == 1 { return codes.first }
        }
        return nil
    }

    public static func codes(forJoined name: String) -> [String] {
        var seen: Set<String> = []
        return name.components(separatedBy: CharacterSet(charactersIn: "/／")).compactMap {
            guard let code = code(for: $0.trimmingCharacters(in: .whitespacesAndNewlines)), seen.insert(code).inserted else { return nil }
            return code
        }
    }

    public static func sameCompany(_ a: String, _ b: String) -> Bool {
        let left = Set(codes(forJoined: a)), right = Set(codes(forJoined: b))
        if left.isEmpty || right.isEmpty { return OperatorBranding.companyLabel(a) == OperatorBranding.companyLabel(b) }
        return !left.isDisjoint(with: right)
    }

    private final class MatchCache: @unchecked Sendable {
        let lock = NSLock()
        var values: [String: [String]] = [:]
    }
    private static let matchCache = MatchCache()

    public static func matchingCodes(query: String) -> [String] {
        matchCache.lock.lock()
        let cached = matchCache.values[query]
        matchCache.lock.unlock()
        if let cached { return cached }
        if query.isEmpty { return registry.operators.map(\.code) }
        let prepared = SearchFold.PreparedQuery(query)
        guard !prepared.whole.isEmpty else { return [] }
        if let exact = exactCodes(query: query) { return exact.sorted() }
        var result: [String] = [], seen: Set<String> = []
        func add(_ code: String) { if seen.insert(code).inserted { result.append(code) } }
        if let code = code(for: query) { add(code) }
        for op in registry.operators where prepared.matches(fields: op.searchNames) { add(op.code) }
        for family in registry.families where prepared.matches(fields: family.searchNames) {
            for member in family.members { add(member) }
        }
        matchCache.lock.lock()
        if matchCache.values.count >= 20_000 { matchCache.values.removeAll(keepingCapacity: true) }
        matchCache.values[query] = result
        matchCache.lock.unlock()
        return result
    }

    public static func matches(operatorName: String, query: String) -> Bool {
        if let exact = exactCodes(query: query) {
            return !Set(codes(forJoined: operatorName)).isDisjoint(with: exact)
        }
        return !Set(codes(forJoined: operatorName)).isDisjoint(with: matchingCodes(query: query))
            || SearchFold.matches(query: query, fields: [operatorName])
    }

    public static func searchNames(for operatorName: String) -> [String] {
        var result = [operatorName]
        for code in codes(forJoined: operatorName) {
            guard let op = byCode[code] else { continue }
            result += op.searchNames
            for family in registry.families where family.members.contains(code) { result += family.searchNames }
        }
        var seen: Set<String> = []
        return result.filter { seen.insert($0).inserted }
    }

    public static func displayName(code: String, language: String) -> String? {
        guard let op = byCode[code] else { return nil }
        let key = ["zh-Hans": "zhHans", "zh-Hant": "zhHant"][language] ?? language
        return op.names[key]?.first ?? op.label
    }
}
