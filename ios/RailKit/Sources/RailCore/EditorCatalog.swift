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

    public init(
        id: String, regionCode: String, operatorIDs: [String], name: String, aliases: [String] = []
    ) {
        self.id = id
        self.regionCode = regionCode
        self.operatorIDs = operatorIDs
        self.name = name
        self.aliases = aliases
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

    public init(
        regionCode: String, lineID: String, name: String, nameNorm: String? = nil,
        nameRoma: String? = nil, operatorName: String? = nil, operatorShort: String? = nil,
        stations: [EditorCatalogStationSource] = []
    ) {
        self.regionCode = regionCode
        self.lineID = lineID
        self.name = name
        self.nameNorm = nameNorm
        self.nameRoma = nameRoma
        self.operatorName = operatorName
        self.operatorShort = operatorShort
        self.stations = stations
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
                aliases: EditorCatalogIdentity.lineAliases(line)
            ))

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

        var operatorsByRegion: [String: [CatalogOperator]] = [:]
        for acc in operatorAcc.values {
            operatorsByRegion[acc.regionCode, default: []].append(acc.operator)
        }
        operatorsByRegion = operatorsByRegion.mapValues { rows in
            rows.sorted { $0.id < $1.id }
        }

        var linesByOperator: [String: [CatalogLine]] = [:]
        var lineIndex: [EditorCatalogLineKey: CatalogLine] = [:]
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

        var membershipsByLine: [EditorCatalogLineKey: [StationLineMembership]] = [:]
        var membershipsByStation: [StationKey: [StationLineMembership]] = [:]
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
                }
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
