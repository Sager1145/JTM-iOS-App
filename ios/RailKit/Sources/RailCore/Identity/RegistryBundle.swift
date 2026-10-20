import Foundation

/// One region's shipped identity tables (`registry-<cc>.json`).
///
/// The file is a lookup, not a catalogue the ride is allowed to guess from.
/// ``RegistryIdentityUpgrade`` recomputes `operator_id` / `station_id` from
/// company text and station codes. A unique row is copied over any previous
/// id. An ambiguous row keeps an id only when that id is still one of the
/// bundle's answers for the current text. A missing bundle leaves the ride
/// alone (ADR 0013).
public struct RegistryOperatorRecord: Equatable, Sendable, Decodable {
    public var names: [String]
    public var label: String
    public var logo: String?
    public var identity: String?

    public init(names: [String], label: String = "", logo: String? = nil, identity: String? = nil) {
        self.names = names
        self.label = label
        self.logo = logo
        self.identity = identity
    }
}

public struct RegistryStationRecord: Equatable, Sendable, Decodable {
    public var cx: String
    public var group: String
    public var codes: [String]
    public var op: String
    public var name: String
    public var parts: StationNameRecord?
    public var lines: [String]
    public var ln: [String]?
    /// Editor romanizations and other spellings of `name`. Absent in shipped bundles.
    public var aka: [String]?

    public init(
        cx: String, group: String, codes: [String], op: String, name: String,
        parts: StationNameRecord? = nil, lines: [String], ln: [String]? = nil,
        aka: [String]? = nil
    ) {
        self.cx = cx
        self.group = group
        self.codes = codes
        self.op = op
        self.name = name
        self.parts = parts
        self.lines = lines
        self.ln = ln
        self.aka = aka
    }
}

public struct RegistryComplexRecord: Equatable, Sendable, Decodable {
    public var group: String
    public var name: String
    public var stations: [String]
    public var lon: Double
    public var lat: Double

    public init(group: String, name: String, stations: [String], lon: Double, lat: Double) {
        self.group = group
        self.name = name
        self.stations = stations
        self.lon = lon
        self.lat = lat
    }
}

public struct RegistryLinePartRecord: Equatable, Sendable, Decodable {
    public var packageLine: String
    public var name: String
    public var op: String
    public var ln: String?
    public var rank: Int

    public init(packageLine: String, name: String, op: String, ln: String? = nil, rank: Int) {
        self.packageLine = packageLine
        self.name = name
        self.op = op
        self.ln = ln
        self.rank = rank
    }
}

public struct RegistryBundle: Decodable, Equatable, Sendable {
    public static let currentSchema = "jtm-registry-bundle/2"
    public static let legacySchema = "jtm-registry-bundle/1"

    public var schema: String
    public var region: String
    public var run: Int
    /// External station code → `st:<region>:<seq>`.
    public var stationCodes: [String: String]
    /// Group code → every company station that shares it. One entry is safe
    /// to copy; more than one is safe only when the operator narrows it to one.
    public var groupCodes: [String: [String]]
    /// `op:<region>:<seq>` → the company's names, compared exactly.
    /// Schema 2 stores these inside ``operatorRecords``; this stays the name list.
    public var operators: [String: [String]]
    /// Schema 2 operator row. A schema 1 bundle fills names and leaves the rest empty.
    public var operatorRecords: [String: RegistryOperatorRecord]
    /// Company station → the one operator that serves it.
    public var stationOperator: [String: String]
    /// Package line id → `lp:<region>:<seq>`. Unused by the ride upgrade.
    public var lines: [String: String]
    /// Company station → complex, codes, name, and the lines that serve it.
    /// Empty when the file is schema 1.
    public var stations: [String: RegistryStationRecord]
    /// Complex → group, name, member stations, and the rounded anchor.
    /// Empty when the file is schema 1.
    public var complexes: [String: RegistryComplexRecord]
    /// Line part → package line, name, operator, optional network, and rank.
    /// Empty when the file is schema 1.
    public var lineParts: [String: RegistryLinePartRecord]
    /// Official station or line-station name → the stored bracket split.
    /// Absent in a bundle written before the field existed.
    public var bracketedNames: [String: StationNameRecord]
    /// Distinct complexes whose official name or base equals the key.
    /// Only bases that appear in ``bracketedNames``.
    public var baseNameCounts: [String: Int]
    /// Retired id (`st`, `op`, `cx`, `lp`, `ls`) → the live id it merged into.
    /// Chains are already followed. Absent in a bundle written before the field existed.
    public var aliases: [String: String]

    /// The live id for `identifier`, or `identifier` itself when it is not retired.
    public func canonicalID(_ identifier: String) -> String {
        aliases[identifier] ?? identifier
    }

    public init(
        schema: String = RegistryBundle.currentSchema,
        region: String,
        run: Int,
        stationCodes: [String: String] = [:],
        groupCodes: [String: [String]] = [:],
        operators: [String: [String]] = [:],
        operatorRecords: [String: RegistryOperatorRecord] = [:],
        stationOperator: [String: String] = [:],
        lines: [String: String] = [:],
        stations: [String: RegistryStationRecord] = [:],
        complexes: [String: RegistryComplexRecord] = [:],
        lineParts: [String: RegistryLinePartRecord] = [:],
        bracketedNames: [String: StationNameRecord] = [:],
        baseNameCounts: [String: Int] = [:],
        aliases: [String: String] = [:]
    ) {
        self.schema = schema
        self.region = region
        self.run = run
        self.stationCodes = stationCodes
        self.groupCodes = groupCodes
        self.operatorRecords = operatorRecords.isEmpty
            ? operators.mapValues { RegistryOperatorRecord(names: $0) }
            : operatorRecords
        self.operators = operators.isEmpty && !self.operatorRecords.isEmpty
            ? self.operatorRecords.mapValues(\.names)
            : operators
        self.stationOperator = stationOperator
        self.lines = lines
        self.stations = stations
        self.complexes = complexes
        self.lineParts = lineParts
        self.bracketedNames = bracketedNames
        self.baseNameCounts = baseNameCounts
        self.aliases = aliases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        guard schema == Self.currentSchema || schema == Self.legacySchema else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema, in: container,
                debugDescription: "Unsupported registry bundle schema \(schema).")
        }
        self.schema = schema
        region = try container.decode(String.self, forKey: .region)
        run = try container.decode(Int.self, forKey: .run)
        stationCodes = try container.decode([String: String].self, forKey: .stationCodes)
        groupCodes = try container.decode([String: [String]].self, forKey: .groupCodes)
        let decodedOperators = try container.decode([String: OperatorField].self, forKey: .operators)
        var names: [String: [String]] = [:]
        var records: [String: RegistryOperatorRecord] = [:]
        for (identifier, field) in decodedOperators {
            let record = field.record
            names[identifier] = record.names
            records[identifier] = record
        }
        operators = names
        operatorRecords = records
        stationOperator = try container.decode([String: String].self, forKey: .stationOperator)
        lines = try container.decode([String: String].self, forKey: .lines)
        if schema == Self.legacySchema {
            stations = [:]
            complexes = [:]
            lineParts = [:]
        } else {
            stations = try container.decodeIfPresent([String: RegistryStationRecord].self, forKey: .stations) ?? [:]
            complexes = try container.decodeIfPresent([String: RegistryComplexRecord].self, forKey: .complexes) ?? [:]
            lineParts = try container.decodeIfPresent([String: RegistryLinePartRecord].self, forKey: .lineParts) ?? [:]
        }
        bracketedNames = try container.decodeIfPresent([String: StationNameRecord].self, forKey: .bracketedNames) ?? [:]
        baseNameCounts = try container.decodeIfPresent([String: Int].self, forKey: .baseNameCounts) ?? [:]
        aliases = try container.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case schema, region, run, stationCodes, groupCodes, operators, stationOperator, lines
        case stations, complexes, lineParts, bracketedNames, baseNameCounts, aliases
    }

    private enum OperatorField: Decodable {
        case legacy([String])
        case record(RegistryOperatorRecord)

        var record: RegistryOperatorRecord {
            switch self {
            case .legacy(let names):
                return RegistryOperatorRecord(names: names)
            case .record(let record):
                return record
            }
        }

        init(from decoder: Decoder) throws {
            // An array is schema 1. A failed unkeyed decode leaves the keyed
            // object unread, so the schema 2 record can still be decoded.
            if var names = try? decoder.unkeyedContainer() {
                var list: [String] = []
                while !names.isAtEnd {
                    list.append(try names.decode(String.self))
                }
                self = .legacy(list)
                return
            }
            self = .record(try RegistryOperatorRecord(from: decoder))
        }
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

    /// Recompute `operator_id` from `company`, then each stop and route-section
    /// endpoint `station_id` from its code and that operator. `company` and
    /// source codes are not rewritten. A missing bundle never reaches here:
    /// ``applyLoaded(_:regionFallback:)`` returns the train unchanged.
    public static func apply(_ train: Train, bundle: RegistryBundle) -> Train {
        var train = train
        canonicalizeOperators(&train, bundle: bundle)
        recomputeOperator(&train, bundle: bundle)
        let operatorID = train.operatorID
        train.stops = train.stops.map { upgradedStop($0, operatorID: operatorID, bundle: bundle) }
        train.routeSections = train.routeSections?.map {
            upgradedSection($0, operatorID: operatorID, bundle: bundle)
        }
        return train
    }

    /// Company text is the source. The same text keeps the cached ids.
    /// A different value drops both operator fields and every stop and section station id.
    public static func reassignCompany(_ company: String?, on train: inout Train) {
        guard train.company != company else { return }
        train.company = company
        train.operatorID = nil
        train.operatorIDs = nil
        for index in train.stops.indices {
            train.stops[index].stationID = nil
        }
        if var sections = train.routeSections {
            for index in sections.indices {
                sections[index].fromStationID = nil
                sections[index].toStationID = nil
            }
            train.routeSections = sections
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

    private static func companyParts(_ company: String) -> [String] {
        company.components(separatedBy: CharacterSet(charactersIn: "/／"))
            .map { JSString.trim($0) }
            .filter { !$0.isEmpty }
    }

    /// A stored operator id that was retired into another reads as the live id.
    private static func canonicalizeOperators(_ train: inout Train, bundle: RegistryBundle) {
        guard !bundle.aliases.isEmpty else { return }
        train.operatorID = train.operatorID.map(bundle.canonicalID)
        train.operatorIDs = train.operatorIDs?.map(bundle.canonicalID)
    }

    private static func recomputeOperator(_ train: inout Train, bundle: RegistryBundle) {
        let company = train.company ?? ""
        let parts = companyParts(company)
        if parts.count >= 2 {
            let converted = parts.map { matchingOperators($0, bundle: bundle) }
            if converted.allSatisfy({ $0.count == 1 }) {
                train.operatorIDs = converted.map { $0[0] }
                train.operatorID = nil
                return
            }
        }
        train.operatorIDs = nil
        let matches = matchingOperators(company, bundle: bundle)
        if matches.count == 1 {
            train.operatorID = matches[0]
            return
        }
        guard let existing = train.operatorID.map(bundle.canonicalID) else { return }
        train.operatorID = existing
        guard let names = bundle.operators[existing] else {
            train.operatorID = nil
            return
        }
        let wanted = normalizedCompany(company, region: bundle.region)
        let consistent = !wanted.isEmpty && names.contains {
            sameCodeUnits(normalizedCompany($0, region: bundle.region), wanted)
        }
        if !consistent { train.operatorID = nil }
    }

    private static func upgradedStop(
        _ stop: Stop, operatorID: String?, bundle: RegistryBundle
    ) -> Stop {
        var copy = stop
        copy.stationID = upgradedStationID(
            existing: stop.stationID, code: stop.n02StationCode,
            operatorID: operatorID, bundle: bundle)
        return copy
    }

    private static func upgradedSection(
        _ section: RouteSection, operatorID: String?, bundle: RegistryBundle
    ) -> RouteSection {
        var copy = section
        copy.fromStationID = upgradedStationID(
            existing: section.fromStationID, code: section.fromN02StationCode,
            operatorID: operatorID, bundle: bundle)
        copy.toStationID = upgradedStationID(
            existing: section.toStationID, code: section.toN02StationCode,
            operatorID: operatorID, bundle: bundle)
        return copy
    }

    /// Same fail-closed rule as a stop: a unique code wins, otherwise keep an
    /// id only while the bundle still lists it for that code.
    private static func upgradedStationID(
        existing: String?, code raw: String?, operatorID: String?, bundle: RegistryBundle
    ) -> String? {
        guard let raw, !raw.isEmpty else {
            return keepOrClearStationID(existing, code: nil, bundle: bundle)
        }
        let code = StationCodeAliases.canonical(raw)
        if let chosen = uniqueStation(code: code, operatorID: operatorID, bundle: bundle) {
            return chosen
        }
        return keepOrClearStationID(existing, code: code, bundle: bundle)
    }

    private static func uniqueStation(
        code: String, operatorID: String?, bundle: RegistryBundle
    ) -> String? {
        RegistryIdentity(bundle: bundle).stationID(forCode: code, operator: operatorID)
    }

    /// Not unique. Keep an id only when the bundle still lists it for this code.
    private static func keepOrClearStationID(
        _ existing: String?, code: String?, bundle: RegistryBundle
    ) -> String? {
        guard let existing = existing.map(bundle.canonicalID) else { return nil }
        let listed = bundleContainsStation(existing, bundle: bundle)
        let onCode = code.map { codeContainsStation(existing, code: $0, bundle: bundle) } ?? false
        return listed && onCode ? existing : nil
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
