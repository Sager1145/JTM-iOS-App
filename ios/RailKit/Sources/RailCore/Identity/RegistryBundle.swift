import Foundation

/// One region's shipped identity tables (`registry-<cc>.json`).
///
/// The file is a lookup, not a catalogue the ride is allowed to guess from.
/// ``RegistryIdentityUpgrade`` recomputes `operator_id` / `station_id` from
/// company text and station codes. A unique row is copied over any previous
/// id. An ambiguous row keeps an id only when that id is still one of the
/// bundle's answers for the current text. A missing bundle leaves the ride
/// alone (ADR 0013).
public struct RegistryBundle: Decodable, Equatable, Sendable {
    public static let currentSchema = "jtm-registry-bundle/1"

    public var schema: String
    public var region: String
    public var run: Int
    /// External station code → `st:<region>:<seq>`.
    public var stationCodes: [String: String]
    /// Group code → every company station that shares it. One entry is safe
    /// to copy; more than one is safe only when the operator narrows it to one.
    public var groupCodes: [String: [String]]
    /// `op:<region>:<seq>` → the company's names, compared exactly.
    public var operators: [String: [String]]
    /// Company station → the one operator that serves it.
    public var stationOperator: [String: String]
    /// Package line id → `lp:<region>:<seq>`. Unused by the ride upgrade.
    public var lines: [String: String]

    public init(
        schema: String = RegistryBundle.currentSchema,
        region: String,
        run: Int,
        stationCodes: [String: String] = [:],
        groupCodes: [String: [String]] = [:],
        operators: [String: [String]] = [:],
        stationOperator: [String: String] = [:],
        lines: [String: String] = [:]
    ) {
        self.schema = schema
        self.region = region
        self.run = run
        self.stationCodes = stationCodes
        self.groupCodes = groupCodes
        self.operators = operators
        self.stationOperator = stationOperator
        self.lines = lines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        guard schema == Self.currentSchema else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema, in: container,
                debugDescription: "Unsupported registry bundle schema \(schema).")
        }
        self.schema = schema
        region = try container.decode(String.self, forKey: .region)
        run = try container.decode(Int.self, forKey: .run)
        stationCodes = try container.decode([String: String].self, forKey: .stationCodes)
        groupCodes = try container.decode([String: [String]].self, forKey: .groupCodes)
        operators = try container.decode([String: [String]].self, forKey: .operators)
        stationOperator = try container.decode([String: String].self, forKey: .stationOperator)
        lines = try container.decode([String: String].self, forKey: .lines)
    }

    private enum CodingKeys: String, CodingKey {
        case schema, region, run, stationCodes, groupCodes, operators, stationOperator, lines
    }
}

/// Fills a ride's registry ids from a bundle already in memory. No I/O.
public enum RegistryIdentityUpgrade {
    public typealias BundleProvider = @Sendable (String) -> RegistryBundle?

    private static let providerLock = NSLock()
    nonisolated(unsafe) private static var bundleProvider: BundleProvider?

    /// The app target installs the bundled-file lookup. Tests and the parity
    /// suites leave this nil, so a missing hook is a no-op rather than a throw.
    public static func installBundleProvider(_ provider: BundleProvider?) {
        providerLock.lock()
        bundleProvider = provider
        providerLock.unlock()
    }

    /// `train.region` when the ride names one, otherwise the import session's
    /// country. An empty string is the same as absent.
    public static func applyLoaded(_ train: Train, regionFallback: String?) -> Train {
        let region = lookupRegion(train.region) ?? lookupRegion(regionFallback)
        guard let region else { return train }
        providerLock.lock()
        let provider = bundleProvider
        providerLock.unlock()
        guard let bundle = provider?(region) else { return train }
        return apply(train, bundle: bundle)
    }

    /// Recompute `operator_id` from `company`, then each stop's `station_id`
    /// from its code and that operator. `company`, `n02_station_code`, and
    /// route sections are not rewritten. A missing bundle never reaches here:
    /// ``applyLoaded(_:regionFallback:)`` returns the train unchanged.
    public static func apply(_ train: Train, bundle: RegistryBundle) -> Train {
        var train = train
        recomputeOperator(&train, bundle: bundle)
        let operatorID = train.operatorID
        train.stops = train.stops.map { upgradedStop($0, operatorID: operatorID, bundle: bundle) }
        return train
    }

    /// Company text is the source. The same text keeps the cached ids.
    /// A different value drops `operatorID` and every stop `stationID`.
    public static func reassignCompany(_ company: String?, on train: inout Train) {
        guard train.company != company else { return }
        train.company = company
        train.operatorID = nil
        for index in train.stops.indices {
            train.stops[index].stationID = nil
        }
    }

    private static func lookupRegion(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Trim, NFKC, and for a Taiwan bundle the passenger-facing short name.
    /// Compared as UTF-16 so Swift's canonical equivalence cannot fold two
    /// spellings the bundle keeps apart. A slash-joined pair stays a pair:
    /// it equals a name only when some name is that same pair.
    private static func normalizedCompany(_ value: String, region: String) -> String {
        let folded = JSString.trim(value).precomposedStringWithCompatibilityMapping
        guard region.lowercased() == "tw" else { return folded }
        return OperatorBranding.normalizeTaiwanCompanyName(folded)
    }

    private static func matchingOperators(_ company: String, bundle: RegistryBundle) -> [String] {
        let wanted = normalizedCompany(company, region: bundle.region)
        guard !wanted.isEmpty else { return [] }
        var matched: [String] = []
        for (identifier, names) in bundle.operators {
            let hit = names.contains {
                sameCodeUnits(normalizedCompany($0, region: bundle.region), wanted)
            }
            if hit { matched.append(identifier) }
        }
        return matched
    }

    private static func recomputeOperator(_ train: inout Train, bundle: RegistryBundle) {
        let matches = train.company.map { matchingOperators($0, bundle: bundle) } ?? []
        if matches.count == 1 {
            train.operatorID = matches[0]
            return
        }
        guard let existing = train.operatorID else { return }
        guard let names = bundle.operators[existing] else {
            train.operatorID = nil
            return
        }
        let wanted = train.company.map { normalizedCompany($0, region: bundle.region) } ?? ""
        let consistent = !wanted.isEmpty && names.contains {
            sameCodeUnits(normalizedCompany($0, region: bundle.region), wanted)
        }
        if !consistent { train.operatorID = nil }
    }

    private static func upgradedStop(
        _ stop: Stop, operatorID: String?, bundle: RegistryBundle
    ) -> Stop {
        guard let raw = stop.n02StationCode, !raw.isEmpty else {
            return keepOrClearStation(stop, code: nil, bundle: bundle)
        }
        let code = StationCodeAliases.canonical(raw)
        if let chosen = uniqueStation(code: code, operatorID: operatorID, bundle: bundle) {
            var copy = stop
            copy.stationID = chosen
            return copy
        }
        return keepOrClearStation(stop, code: code, bundle: bundle)
    }

    private static func uniqueStation(
        code: String, operatorID: String?, bundle: RegistryBundle
    ) -> String? {
        if let stationID = bundle.stationCodes[code] { return stationID }
        guard let candidates = bundle.groupCodes[code], !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }
        guard let operatorID else { return nil }
        let matched = candidates.filter { candidate in
            guard let owner = bundle.stationOperator[candidate] else { return false }
            return sameCodeUnits(owner, operatorID)
        }
        return matched.count == 1 ? matched[0] : nil
    }

    /// Not unique. Keep an id only when the bundle still lists it for this code.
    private static func keepOrClearStation(
        _ stop: Stop, code: String?, bundle: RegistryBundle
    ) -> Stop {
        guard let existing = stop.stationID else { return stop }
        let listed = bundleContainsStation(existing, bundle: bundle)
        let onCode = code.map { codeContainsStation(existing, code: $0, bundle: bundle) } ?? false
        guard listed && onCode else {
            var copy = stop
            copy.stationID = nil
            return copy
        }
        return stop
    }

    private static func bundleContainsStation(_ identifier: String, bundle: RegistryBundle) -> Bool {
        if bundle.stationCodes.values.contains(identifier) { return true }
        if bundle.stationOperator[identifier] != nil { return true }
        for stations in bundle.groupCodes.values where stations.contains(identifier) {
            return true
        }
        return false
    }

    private static func codeContainsStation(
        _ identifier: String, code: String, bundle: RegistryBundle
    ) -> Bool {
        if let direct = bundle.stationCodes[code] { return direct == identifier }
        return bundle.groupCodes[code]?.contains(identifier) ?? false
    }
}
