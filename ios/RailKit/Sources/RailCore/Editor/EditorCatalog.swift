import Foundation

public struct StationKey: Hashable, Codable, Sendable {
    public var regionCode: String
    public var sourceCode: String

    public init(regionCode: String, sourceCode: String) {
        self.regionCode = regionCode
        self.sourceCode = sourceCode
    }
}

public struct OperatorRedirect: Hashable, Sendable {
    public var regionCode: String
    public var fromOfficialName: String
    public var operatorID: String

    public init(regionCode: String, fromOfficialName: String, operatorID: String) {
        self.regionCode = regionCode
        self.fromOfficialName = fromOfficialName
        self.operatorID = operatorID
    }
}

public struct CatalogOperator: Hashable, Codable, Sendable {
    public var id: String
    public var regionCode: String
    public var name: String
    public var shortName: String?
    public var aliases: [String]

    public init(
        id: String, regionCode: String, name: String, shortName: String? = nil, aliases: [String] = []
    ) {
        self.id = id
        self.regionCode = regionCode
        self.name = name
        self.shortName = shortName
        self.aliases = aliases
    }
}

public struct CatalogLine: Hashable, Codable, Sendable {
    public var id: String
    public var regionCode: String
    public var operatorIDs: [String]
    public var name: String
    public var aliases: [String]
    /// Passenger route symbol (`MO`, `JY`). Absent when the package has none.
    public var lineCode: String?
    /// Package rank. Lower is the more important line and sorts first in a label.
    public var rank: Int

    public init(
        id: String, regionCode: String, operatorIDs: [String], name: String, aliases: [String] = [],
        lineCode: String? = nil, rank: Int = 0
    ) {
        self.id = id
        self.regionCode = regionCode
        self.operatorIDs = operatorIDs
        self.name = name
        self.aliases = aliases
        self.lineCode = lineCode
        self.rank = rank
    }
}

public struct CatalogStation: Hashable, Codable, Sendable {
    public var key: StationKey
    public var name: String
    public var aliases: [String]
    public var longitude: Double
    public var latitude: Double

    public init(
        key: StationKey, name: String, aliases: [String] = [], longitude: Double, latitude: Double
    ) {
        self.key = key
        self.name = name
        self.aliases = aliases
        self.longitude = longitude
        self.latitude = latitude
    }
}

public struct StationLineMembership: Hashable, Codable, Sendable {
    public var stationKey: StationKey
    public var lineID: String
    public var regionCode: String
    public var membershipID: String
    public var sequence: Int
    public var longitude: Double
    public var latitude: Double

    public init(
        stationKey: StationKey, lineID: String, regionCode: String, membershipID: String,
        sequence: Int, longitude: Double, latitude: Double
    ) {
        self.stationKey = stationKey
        self.lineID = lineID
        self.regionCode = regionCode
        self.membershipID = membershipID
        self.sequence = sequence
        self.longitude = longitude
        self.latitude = latitude
    }
}

public enum EditorCatalogIssue: Hashable, Sendable {
    case duplicateLineID(regionCode: String, lineID: String)
    case duplicateMembershipID(String)
    case redirectCycle(regionCode: String, fromOfficialName: String)
    case dangling
}

public struct EditorCatalogLineSource: Sendable {
    public var regionCode: String
    public var lineID: String
    public var name: String
    public var nameNorm: String?
    public var nameRoma: String?
    public var operatorName: String?
    public var operatorShort: String?
    public var stations: [EditorCatalogStationSource]
    public var lineCode: String?
    public var rank: Int

    public init(
        regionCode: String, lineID: String, name: String, nameNorm: String? = nil,
        nameRoma: String? = nil, operatorName: String? = nil, operatorShort: String? = nil,
        stations: [EditorCatalogStationSource] = [],
        lineCode: String? = nil, rank: Int = 0
    ) {
        self.regionCode = regionCode
        self.lineID = lineID
        self.name = name
        self.nameNorm = nameNorm
        self.nameRoma = nameRoma
        self.operatorName = operatorName
        self.operatorShort = operatorShort
        self.stations = stations
        self.lineCode = lineCode
        self.rank = rank
    }
}

public struct EditorCatalogStationSource: Sendable {
    public var sourceCode: String
    public var name: String
    public var nameRoma: String?
    public var longitude: Double
    public var latitude: Double

    public init(
        sourceCode: String, name: String, nameRoma: String? = nil, longitude: Double, latitude: Double
    ) {
        self.sourceCode = sourceCode
        self.name = name
        self.nameRoma = nameRoma
        self.longitude = longitude
        self.latitude = latitude
    }
}

public struct EditorCatalog: Sendable {
    public let issues: [EditorCatalogIssue]

    private let operatorsByRegion: [String: [CatalogOperator]]
    private let linesByOperator: [String: [CatalogLine]]
    private let lineIndex: [EditorCatalogLineKey: CatalogLine]
    private let stationIndex: [StationKey: CatalogStation]
    private let membershipsByLine: [EditorCatalogLineKey: [StationLineMembership]]
    private let membershipsByStation: [StationKey: [StationLineMembership]]
    /// `StationLabel` line labels, keyed by region then line id. Built once.
    private let lineLabelsByRegion: [String: [String: String]]

    fileprivate init(
        issues: [EditorCatalogIssue],
        operatorsByRegion: [String: [CatalogOperator]],
        linesByOperator: [String: [CatalogLine]],
        lineIndex: [EditorCatalogLineKey: CatalogLine],
        stationIndex: [StationKey: CatalogStation],
        membershipsByLine: [EditorCatalogLineKey: [StationLineMembership]],
        membershipsByStation: [StationKey: [StationLineMembership]]
    ) {
        self.issues = issues
        self.operatorsByRegion = operatorsByRegion
        self.linesByOperator = linesByOperator
        self.lineIndex = lineIndex
        self.stationIndex = stationIndex
        self.membershipsByLine = membershipsByLine
        self.membershipsByStation = membershipsByStation
        var linesByRegion: [String: [CatalogLine]] = [:]
        for line in lineIndex.values {
            linesByRegion[line.regionCode, default: []].append(line)
        }
        var labels: [String: [String: String]] = [:]
        for region in Set(linesByRegion.keys).union(operatorsByRegion.keys) {
            labels[region] = StationLabel.lineLabels(
                lines: linesByRegion[region] ?? [],
                operators: operatorsByRegion[region] ?? [])
        }
        self.lineLabelsByRegion = labels
    }

    /// Line labels for one country. Computed when the catalog is built.
    public func storedLineLabels(regionCode: String) -> [String: String] {
        lineLabelsByRegion[regionCode] ?? [:]
    }

    public func operators(in regionCode: String) -> [CatalogOperator] {
        operatorsByRegion[regionCode] ?? []
    }

    public func stations(in regionCode: String) -> [CatalogStation] {
        stationIndex.values
            .filter { $0.key.regionCode == regionCode }
            .sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.key.sourceCode < rhs.key.sourceCode
            }
    }

    public func lines(in regionCode: String) -> [CatalogLine] {
        lineIndex.values
            .filter { $0.regionCode == regionCode }
            .sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id < rhs.id
            }
    }

    public func lines(operatorID: String) -> [CatalogLine] {
        linesByOperator[operatorID] ?? []
    }

    public func line(id: String, regionCode: String) -> CatalogLine? {
        lineIndex[EditorCatalogLineKey(regionCode: regionCode, lineID: id)]
    }

    public func station(_ key: StationKey) -> CatalogStation? {
        stationIndex[key]
    }

    public func memberships(lineID: String, regionCode: String) -> [StationLineMembership] {
        membershipsByLine[EditorCatalogLineKey(regionCode: regionCode, lineID: lineID)] ?? []
    }

    public func memberships(stationKey: StationKey) -> [StationLineMembership] {
        membershipsByStation[stationKey] ?? []
    }

    public func candidates(named query: String, regionCode: String?) -> [CatalogStation] {
        let needle = EditorCatalogMatch.fold(query)
        return stationIndex.values.filter { station in
            if let regionCode, station.key.regionCode != regionCode { return false }
            if EditorCatalogMatch.fold(station.name) == needle { return true }
            return station.aliases.contains { EditorCatalogMatch.fold($0) == needle }
        }
        .sorted { lhs, rhs in
            if lhs.key.regionCode != rhs.key.regionCode {
                return lhs.key.regionCode < rhs.key.regionCode
            }
            return lhs.key.sourceCode < rhs.key.sourceCode
        }
    }
}

public enum EditorCatalogBuilder {
    public static func build(
        _ lines: [EditorCatalogLineSource],
        operatorRedirects: [OperatorRedirect] = []
    ) -> EditorCatalog {
        let redirects = EditorCatalogRedirects.resolve(operatorRedirects)
        var issues = redirects.issues

        var operatorAcc: [String: EditorCatalogOperatorAcc] = [:]
        var catalogLines: [CatalogLine] = []
        var seenLines: Set<EditorCatalogLineKey> = []
        var memberships: [StationLineMembership] = []
        var seenMemberships: Set<String> = []
        var stationAcc: [StationKey: EditorCatalogStationAcc] = [:]

        appendLines(
            lines, redirects: redirects, issues: &issues, operatorAcc: &operatorAcc,
            catalogLines: &catalogLines, seenLines: &seenLines, memberships: &memberships,
            seenMemberships: &seenMemberships, stationAcc: &stationAcc)

        var operatorsByRegion: [String: [CatalogOperator]] = [:]
        indexOperators(operatorAcc, operatorsByRegion: &operatorsByRegion)

        var linesByOperator: [String: [CatalogLine]] = [:]
        var lineIndex: [EditorCatalogLineKey: CatalogLine] = [:]
        indexLines(catalogLines, linesByOperator: &linesByOperator, lineIndex: &lineIndex)

        var membershipsByLine: [EditorCatalogLineKey: [StationLineMembership]] = [:]
        var membershipsByStation: [StationKey: [StationLineMembership]] = [:]
        indexMemberships(memberships, membershipsByLine: &membershipsByLine,
            membershipsByStation: &membershipsByStation)

        var stationIndex: [StationKey: CatalogStation] = [:]
        for (key, acc) in stationAcc {
            stationIndex[key] = acc.station(key)
        }

        return EditorCatalog(
            issues: issues,
            operatorsByRegion: operatorsByRegion,
            linesByOperator: linesByOperator,
            lineIndex: lineIndex,
            stationIndex: stationIndex,
            membershipsByLine: membershipsByLine,
            membershipsByStation: membershipsByStation
        )
    }

    private static func appendLines(
        _ lines: [EditorCatalogLineSource], redirects: EditorCatalogRedirects,
        issues: inout [EditorCatalogIssue], operatorAcc: inout [String: EditorCatalogOperatorAcc],
        catalogLines: inout [CatalogLine], seenLines: inout Set<EditorCatalogLineKey>,
        memberships: inout [StationLineMembership], seenMemberships: inout Set<String>,
        stationAcc: inout [StationKey: EditorCatalogStationAcc]
    ) {
        for line in lines {
            let lineKey = EditorCatalogLineKey(regionCode: line.regionCode, lineID: line.lineID)
            if seenLines.contains(lineKey) {
                issues.append(.duplicateLineID(regionCode: line.regionCode, lineID: line.lineID))
                continue
            }
            seenLines.insert(lineKey)

            let operatorID = redirects.operatorID(for: line)
            let officialName = EditorCatalogIdentity.collapseWhitespace(line.operatorName ?? "")
            operatorAcc[operatorID, default: EditorCatalogOperatorAcc(
                id: operatorID, regionCode: line.regionCode, name: officialName
            )].absorb(officialName: officialName, operatorShort: line.operatorShort)

            catalogLines.append(CatalogLine(
                id: line.lineID,
                regionCode: line.regionCode,
                operatorIDs: [operatorID],
                name: line.name,
                aliases: EditorCatalogIdentity.lineAliases(line),
                lineCode: line.lineCode,
                rank: line.rank
            ))

            appendMemberships(
                line, issues: &issues, memberships: &memberships,
                seenMemberships: &seenMemberships, stationAcc: &stationAcc)
        }
    }

    private static func appendMemberships(
        _ line: EditorCatalogLineSource, issues: inout [EditorCatalogIssue],
        memberships: inout [StationLineMembership], seenMemberships: inout Set<String>,
        stationAcc: inout [StationKey: EditorCatalogStationAcc]
    ) {
        for (sequence, station) in line.stations.enumerated() {
            let membershipID = [
                line.regionCode, line.lineID, station.sourceCode, String(sequence),
            ].joined(separator: "|")
            if seenMemberships.contains(membershipID) {
                issues.append(.duplicateMembershipID(membershipID))
                continue
            }
            seenMemberships.insert(membershipID)

            let key = StationKey(regionCode: line.regionCode, sourceCode: station.sourceCode)
            let membership = StationLineMembership(
                stationKey: key,
                lineID: line.lineID,
                regionCode: line.regionCode,
                membershipID: membershipID,
                sequence: sequence,
                longitude: station.longitude,
                latitude: station.latitude
            )
            memberships.append(membership)
            stationAcc[key, default: EditorCatalogStationAcc(
                name: station.name,
                longitude: station.longitude,
                latitude: station.latitude,
                lineID: line.lineID,
                sequence: sequence
            )].absorb(station, lineID: line.lineID, sequence: sequence)
        }
    }

    private static func indexOperators(
        _ operatorAcc: [String: EditorCatalogOperatorAcc],
        operatorsByRegion: inout [String: [CatalogOperator]]
    ) {
        for acc in operatorAcc.values {
            operatorsByRegion[acc.regionCode, default: []].append(acc.operator)
        }
        operatorsByRegion = operatorsByRegion.mapValues { rows in
            rows.sorted { $0.id < $1.id }
        }
    }

    private static func indexLines(
        _ catalogLines: [CatalogLine], linesByOperator: inout [String: [CatalogLine]],
        lineIndex: inout [EditorCatalogLineKey: CatalogLine]
    ) {
        for line in catalogLines {
            lineIndex[EditorCatalogLineKey(regionCode: line.regionCode, lineID: line.id)] = line
            for operatorID in line.operatorIDs {
                linesByOperator[operatorID, default: []].append(line)
            }
        }
        linesByOperator = linesByOperator.mapValues { rows in
            rows.sorted { lhs, rhs in
                if lhs.regionCode != rhs.regionCode { return lhs.regionCode < rhs.regionCode }
                return lhs.id < rhs.id
            }
        }
    }

    private static func indexMemberships(
        _ memberships: [StationLineMembership],
        membershipsByLine: inout [EditorCatalogLineKey: [StationLineMembership]],
        membershipsByStation: inout [StationKey: [StationLineMembership]]
    ) {
        for membership in memberships {
            let key = EditorCatalogLineKey(regionCode: membership.regionCode, lineID: membership.lineID)
            membershipsByLine[key, default: []].append(membership)
            membershipsByStation[membership.stationKey, default: []].append(membership)
        }
        membershipsByLine = membershipsByLine.mapValues { rows in
            rows.sorted { $0.sequence < $1.sequence }
        }
        membershipsByStation = membershipsByStation.mapValues { rows in
            rows.sorted { lhs, rhs in
                if lhs.lineID != rhs.lineID { return lhs.lineID < rhs.lineID }
                return lhs.sequence < rhs.sequence
            }
        }
    }
}

extension EditorCatalogBuilder {
    public static func sources(regionCode: String, package: CompactPackage) -> [EditorCatalogLineSource] {
        package.lines.map { line in
            EditorCatalogLineSource(
                regionCode: regionCode,
                lineID: line.id,
                name: line.name,
                nameNorm: line.nameNorm,
                nameRoma: line.nameRoma,
                operatorName: line.operator,
                operatorShort: line.operatorShort,
                stations: line.stations.map { station in
                    EditorCatalogStationSource(
                        sourceCode: station.id,
                        name: station.name,
                        nameRoma: station.nameRoma,
                        longitude: station.coordinate.lon,
                        latitude: station.coordinate.lat
                    )
                },
                lineCode: line.lineCode,
                rank: line.rank
            )
        }
    }
}

private struct EditorCatalogLineKey: Hashable {
    var regionCode: String
    var lineID: String
}

private enum EditorCatalogMatch {
    static func fold(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
}

private enum EditorCatalogIdentity {
    // OperatorID is `regionCode + "|" + officialOperatorName` after trimming ends
    // and collapsing internal whitespace to one space. The same region and official
    // name are one operator. A nil or blank operator does not join other lines:
    // its id is `regionCode + "|__line__|" + lineID`.
    static func collapseWhitespace(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func synthesizedOperatorID(regionCode: String, officialName: String) -> String {
        regionCode + "|" + officialName
    }

    static func unnamedOperatorID(regionCode: String, lineID: String) -> String {
        regionCode + "|__line__|" + lineID
    }

    static func lineAliases(_ line: EditorCatalogLineSource) -> [String] {
        var aliases: Set<String> = []
        for candidate in [line.nameNorm, line.nameRoma] {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || candidate == line.name { continue }
            aliases.insert(candidate)
        }
        return aliases.sorted()
    }

    static func present(_ value: String?) -> String? {
        guard let value else { return nil }
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return value
    }
}

private struct EditorCatalogRedirects {
    fileprivate struct NameKey: Hashable {
        var regionCode: String
        var normalizedName: String
    }

    var issues: [EditorCatalogIssue]
    var applied: [NameKey: String]
    var cyclic: Set<NameKey>

    static func resolve(_ redirects: [OperatorRedirect]) -> EditorCatalogRedirects {
        var first: [NameKey: OperatorRedirect] = [:]
        var order: [NameKey] = []
        for redirect in redirects {
            let key = NameKey(
                regionCode: redirect.regionCode,
                normalizedName: EditorCatalogIdentity.collapseWhitespace(redirect.fromOfficialName)
            )
            if first[key] == nil {
                first[key] = redirect
                order.append(key)
            }
        }

        var ownerOfSynthesizedID: [String: NameKey] = [:]
        for key in order {
            let synthesized = EditorCatalogIdentity.synthesizedOperatorID(
                regionCode: key.regionCode, officialName: key.normalizedName)
            if ownerOfSynthesizedID[synthesized] == nil {
                ownerOfSynthesizedID[synthesized] = key
            }
        }

        var issues: [EditorCatalogIssue] = []
        var cyclic: Set<NameKey> = []
        var applied: [NameKey: String] = [:]
        for key in order {
            guard let redirect = first[key] else { continue }
            var stack: Set<NameKey> = []
            if chainTerminates(key, redirects: first, ownerOfSynthesizedID: ownerOfSynthesizedID, stack: &stack) {
                applied[key] = redirect.operatorID
            } else {
                cyclic.insert(key)
                issues.append(.redirectCycle(
                    regionCode: redirect.regionCode, fromOfficialName: redirect.fromOfficialName))
            }
        }
        return EditorCatalogRedirects(issues: issues, applied: applied, cyclic: cyclic)
    }

    func operatorID(for line: EditorCatalogLineSource) -> String {
        let official = EditorCatalogIdentity.collapseWhitespace(line.operatorName ?? "")
        if official.isEmpty {
            return EditorCatalogIdentity.unnamedOperatorID(regionCode: line.regionCode, lineID: line.lineID)
        }
        let key = NameKey(regionCode: line.regionCode, normalizedName: official)
        if let redirected = applied[key], !cyclic.contains(key) {
            return redirected
        }
        return EditorCatalogIdentity.synthesizedOperatorID(regionCode: line.regionCode, officialName: official)
    }

    private static func chainTerminates(
        _ key: NameKey,
        redirects: [NameKey: OperatorRedirect],
        ownerOfSynthesizedID: [String: NameKey],
        stack: inout Set<NameKey>
    ) -> Bool {
        guard let redirect = redirects[key] else { return true }
        if stack.contains(key) { return false }
        guard let next = ownerOfSynthesizedID[redirect.operatorID] else { return true }
        stack.insert(key)
        let terminated = chainTerminates(
            next, redirects: redirects, ownerOfSynthesizedID: ownerOfSynthesizedID, stack: &stack)
        stack.remove(key)
        return terminated
    }
}

private struct EditorCatalogOperatorAcc {
    var id: String
    var regionCode: String
    var name: String
    var shortName: String?
    var aliases: Set<String> = []

    mutating func absorb(officialName: String, operatorShort: String?) {
        if name.isEmpty, !officialName.isEmpty {
            name = officialName
        } else if !officialName.isEmpty, officialName != name {
            aliases.insert(officialName)
        }
        guard let short = EditorCatalogIdentity.present(operatorShort) else { return }
        let collapsed = EditorCatalogIdentity.collapseWhitespace(short)
        if collapsed.isEmpty || collapsed == name || collapsed == officialName { return }
        aliases.insert(collapsed)
        if shortName == nil { shortName = collapsed }
    }

    var `operator`: CatalogOperator {
        CatalogOperator(
            id: id, regionCode: regionCode, name: name, shortName: shortName, aliases: aliases.sorted())
    }
}

private struct EditorCatalogStationAcc {
    var name: String
    var aliases: Set<String> = []
    var longitude: Double
    var latitude: Double
    var lineID: String
    var sequence: Int

    mutating func absorb(_ station: EditorCatalogStationSource, lineID: String, sequence: Int) {
        if (lineID, sequence) < (self.lineID, self.sequence) {
            name = station.name
            longitude = station.longitude
            latitude = station.latitude
            self.lineID = lineID
            self.sequence = sequence
        }
        if let roma = EditorCatalogIdentity.present(station.nameRoma) {
            aliases.insert(roma)
        }
    }

    func station(_ key: StationKey) -> CatalogStation {
        CatalogStation(
            key: key,
            name: name,
            aliases: aliases.filter { $0 != name }.sorted(),
            longitude: longitude,
            latitude: latitude
        )
    }
}

// MARK: - Station search

/// Which station populations a query may return. Retired hits also require a ride date.
public struct StationSearchEligibility: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let current = StationSearchEligibility(rawValue: 1 << 0)
    public static let retired = StationSearchEligibility(rawValue: 1 << 1)
}

/// One station query. Hits are station identities, never rows merged by display name.
public struct StationSearchQuery: Hashable, Sendable {
    public var regionCode: String
    public var needle: String
    public var rideDate: String?
    public var eligibility: StationSearchEligibility
    public var lineIDs: Set<String>
    public var companyName: String?
    /// Applied only when `needle` is non-empty. An empty needle is the line browser.
    public var sectionLimit: Int
    public var rowLimit: Int
    public var suggestionLimit: Int

    public init(
        regionCode: String,
        needle: String = "",
        rideDate: String? = nil,
        eligibility: StationSearchEligibility = .current,
        lineIDs: Set<String> = [],
        companyName: String? = nil,
        sectionLimit: Int = 60,
        rowLimit: Int = 400,
        suggestionLimit: Int = 6
    ) {
        self.regionCode = regionCode
        self.needle = needle
        self.rideDate = rideDate
        self.eligibility = eligibility
        self.lineIDs = lineIDs
        self.companyName = companyName
        self.sectionLimit = sectionLimit
        self.rowLimit = rowLimit
        self.suggestionLimit = suggestionLimit
    }
}

public struct StationSearchHit: Hashable, Sendable, Identifiable {
    public enum Subject: Hashable, Sendable {
        /// `lineID` is the line section this row belongs to. Suggestions leave it nil.
        case current(StationKey, lineID: String?)
        case retired(String)
    }

    public var subject: Subject
    /// 0 exact folded field, 1 prefix, 2 other match, 3 included because the line matched.
    public var rank: Int

    public var id: String {
        switch subject {
        case .current(let key, let lineID):
            return "\(key.regionCode)|\(key.sourceCode)|\(lineID ?? "")"
        case .retired(let id):
            return "retired|\(id)"
        }
    }

    public init(subject: Subject, rank: Int) {
        self.subject = subject
        self.rank = rank
    }
}

public struct StationSearchLine: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var header: String
    public var operatorID: String
    public var operatorName: String
    public var hits: [StationSearchHit]

    public init(
        id: String, name: String, header: String, operatorID: String, operatorName: String,
        hits: [StationSearchHit]
    ) {
        self.id = id
        self.name = name
        self.header = header
        self.operatorID = operatorID
        self.operatorName = operatorName
        self.hits = hits
    }
}

public struct StationSearchResult: Hashable, Sendable {
    public var lines: [StationSearchLine]
    public var retired: [StationSearchHit]
    /// Best rank per current `StationKey`. Two stations that share a display name stay two hits.
    public var suggestions: [StationSearchHit]

    public init(lines: [StationSearchLine] = [], retired: [StationSearchHit] = [], suggestions: [StationSearchHit] = []) {
        self.lines = lines
        self.retired = retired
        self.suggestions = suggestions
    }
}

/// Line and station index for one catalog region. Ranking lives here; pickers only present hits.
public struct StationSearchIndex: Sendable {
    public let regionCode: String
    private let lines: [IndexedLine]

    fileprivate init(regionCode: String, lines: [IndexedLine]) {
        self.regionCode = regionCode
        self.lines = lines
    }

    public func search(_ query: StationSearchQuery, retired retiredStations: [RetiredStation] = []) -> StationSearchResult {
        let needle = query.needle.trimmingCharacters(in: .whitespacesAndNewlines)
        let prepared = SearchFold.PreparedQuery(needle)
        let browsing = needle.isEmpty
        var sections: [StationSearchLine] = []
        var suggestionPool: [(hit: StationSearchHit, name: String, code: String)] = []
        var seenSuggestion: Set<StationKey> = []
        var rowCount = 0

        if query.eligibility.contains(.current) {
            for line in lines {
                if Task.isCancelled { break }
                if !query.lineIDs.isEmpty && !query.lineIDs.contains(line.id) { continue }
                if let company = query.companyName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !company.isEmpty, !line.operatorNames.contains(company) {
                    continue
                }
                let lineMatched = !browsing && Self.matches(prepared, fields: line.matchFields)
                var hits: [StationSearchHit] = []
                for station in line.stations {
                    let stationRank = browsing ? 0 : Self.rank(prepared, fields: station.matchFields)
                    guard browsing || lineMatched || stationRank != nil else { continue }
                    let rank = stationRank ?? 3
                    hits.append(StationSearchHit(
                        subject: .current(station.key, lineID: line.id), rank: rank))
                    if !browsing, let stationRank, seenSuggestion.insert(station.key).inserted {
                        suggestionPool.append((
                            StationSearchHit(subject: .current(station.key, lineID: nil), rank: stationRank),
                            station.name,
                            station.key.sourceCode))
                    }
                }
                guard !hits.isEmpty else { continue }
                if !browsing {
                    if sections.count == query.sectionLimit || rowCount == query.rowLimit { break }
                    let room = query.rowLimit - rowCount
                    if hits.count > room { hits = Array(hits.prefix(room)) }
                }
                sections.append(StationSearchLine(
                    id: line.id, name: line.name, header: line.header, operatorID: line.operatorID,
                    operatorName: line.operatorName, hits: hits))
                rowCount += hits.count
            }
        }

        suggestionPool.sort { lhs, rhs in
            if lhs.hit.rank != rhs.hit.rank { return lhs.hit.rank < rhs.hit.rank }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.code < rhs.code
        }
        let suggestions = browsing
            ? []
            : suggestionPool.prefix(max(0, query.suggestionLimit)).map(\.hit)

        let retiredHits = query.eligibility.contains(.retired)
            ? Self.retiredHits(
                eligibleRetired(retiredStations, rideDate: query.rideDate, lineIDs: query.lineIDs),
                prepared: prepared, browsing: browsing)
            : []
        return StationSearchResult(lines: sections, retired: retiredHits, suggestions: Array(suggestions))
    }

    /// Retired stations open on `rideDate`. An empty or non-ISO date yields nothing.
    /// Selected lines restrict by catalog line name; an empty name match keeps the open set,
    /// because overlay spellings do not always equal the catalog.
    public func eligibleRetired(
        _ stations: [RetiredStation], rideDate: String?, lineIDs: Set<String>
    ) -> [RetiredStation] {
        let open = RailHistoryStations.open(stations, on: rideDate)
        guard !open.isEmpty, !lineIDs.isEmpty else { return open }
        let allowed = Set(lines.filter { lineIDs.contains($0.id) }.flatMap { [$0.name] + $0.aliases })
        let filtered = open.filter { allowed.contains($0.lineName) }
        return filtered.isEmpty ? open : filtered
    }

    private static func retiredHits(
        _ stations: [RetiredStation], prepared: SearchFold.PreparedQuery, browsing: Bool
    ) -> [StationSearchHit] {
        stations.compactMap { station in
            let rank = browsing ? 0 : rank(prepared, fields: [station.name])
            guard let rank else { return nil }
            return StationSearchHit(subject: .retired(station.id), rank: rank)
        }
    }

    private static func matches(_ prepared: SearchFold.PreparedQuery, fields: [String]) -> Bool {
        rank(prepared, fields: fields) != nil
    }

    private static func rank(_ prepared: SearchFold.PreparedQuery, fields: [String]) -> Int? {
        let meaningful = fields.filter { !$0.isEmpty }
        guard !prepared.isEmpty, prepared.matches(fields: meaningful) else { return nil }
        let names = meaningful.map(SearchFold.fold)
        if names.contains(prepared.whole) { return 0 }
        if names.contains(where: { $0.hasPrefix(prepared.whole) }) { return 1 }
        return 2
    }

    fileprivate struct IndexedStation: Sendable {
        var key: StationKey
        var name: String
        var aliases: [String]
        var matchFields: [String] { [name, key.sourceCode] + aliases }
    }

    fileprivate struct IndexedLine: Sendable {
        var id: String
        var name: String
        var aliases: [String]
        var operatorID: String
        var operatorName: String
        var operatorNames: [String]
        var header: String
        var matchFields: [String]
        var stations: [IndexedStation]
    }
}

extension EditorCatalog {
    /// Build the region index once, then query it. The index does not merge stations by name.
    public func stationSearchIndex(regionCode: String) -> StationSearchIndex {
        let operatorsByID = Dictionary(
            operators(in: regionCode).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        var indexed: [StationSearchIndex.IndexedLine] = []
        for line in lines(in: regionCode) {
            let lineOperators = line.operatorIDs.compactMap { operatorsByID[$0] }
            let operatorNames = lineOperators.map(\.name).filter { !$0.isEmpty }
            let header = operatorNames.isEmpty
                ? line.name
                : operatorNames.joined(separator: " / ") + " · " + line.name
            var seen: Set<String> = []
            var stations: [StationSearchIndex.IndexedStation] = []
            for member in memberships(lineID: line.id, regionCode: regionCode) {
                guard seen.insert(member.stationKey.sourceCode).inserted,
                      let station = station(member.stationKey) else { continue }
                stations.append(StationSearchIndex.IndexedStation(
                    key: station.key, name: station.name, aliases: station.aliases))
            }
            guard !stations.isEmpty else { continue }
            let operatorID = line.operatorIDs.first ?? ""
            indexed.append(StationSearchIndex.IndexedLine(
                id: line.id,
                name: line.name,
                aliases: line.aliases.filter { !$0.isEmpty },
                operatorID: operatorID,
                operatorName: operatorNames.first ?? "",
                operatorNames: operatorNames,
                header: header,
                matchFields: [line.name] + line.aliases.filter { !$0.isEmpty }
                    + operatorNames
                    + lineOperators.compactMap(\.shortName).filter { !$0.isEmpty }
                    + lineOperators.flatMap(\.aliases).filter { !$0.isEmpty },
                stations: stations))
        }
        return StationSearchIndex(regionCode: regionCode, lines: indexed)
    }

    public func searchStations(
        _ query: StationSearchQuery, retired: [RetiredStation] = []
    ) -> StationSearchResult {
        stationSearchIndex(regionCode: query.regionCode).search(query, retired: retired)
    }
}
