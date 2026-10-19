import Foundation

/// Passenger-facing label derived from one company station and one line part.
public struct RegistryStationLabel: Equatable, Sendable {
    /// Large name and status secondary, from ``StationLabel/presented``.
    public var presentation: StationLabel.Presentation
    /// Country caption built from ``presentation.label`` and the chosen line.
    public var text: StationLabel.Text
    /// Line part used for the caption. Nil when the station lists none.
    public var lineID: String?

    public init(presentation: StationLabel.Presentation, text: StationLabel.Text, lineID: String?) {
        self.presentation = presentation
        self.text = text
        self.lineID = lineID
    }
}

/// Read-only identity queries over one ``RegistryBundle``.
///
/// Schema 1 files decode with empty reverse maps, so station, complex, and
/// label queries miss. ``stationID(forCode:operator:)`` still answers from the
/// forward code tables. The value is pure: it does not read the clock or disk.
public struct RegistryIdentity: Equatable, Sendable {
    public var bundle: RegistryBundle
    /// NFKC exact key → the one operator that owns it. A key two operators share is omitted.
    private var exactOperatorByName: [String: String]
    /// Identity code → the one operator that stores it. A code two records share is omitted.
    private var operatorByIdentityCode: [String: String]
    /// Line-part name → how many parts in this bundle use that exact name.
    private var lineNameCounts: [String: Int]
    /// Folded name, label, alias, or identity display name, paired with its operator.
    /// The raw identity code is not a query key.
    private var queryHaystacks: [(haystack: String, identifier: String)]

    public init(bundle: RegistryBundle) {
        self.bundle = bundle
        let maps = Self.conversionMaps(bundle)
        self.exactOperatorByName = maps.exact
        self.operatorByIdentityCode = maps.byCode
        self.lineNameCounts = maps.lineNames
        self.queryHaystacks = maps.haystacks
    }

    public static func == (lhs: RegistryIdentity, rhs: RegistryIdentity) -> Bool {
        lhs.bundle == rhs.bundle
    }

    /// Unique exact name or identity-code string. Ambiguous and unknown names are nil.
    public func operatorID(forExactName name: String) -> String? {
        let key = Self.exactKey(name, region: bundle.region)
        guard !key.isEmpty else { return nil }
        return exactOperatorByName[key]
    }

    /// Folded query as a substring of a name, label, alias, or identity display name.
    /// An empty query and a query that names no operator both return an empty set.
    /// The raw identity code is not a match key: a query is UI text.
    public func operatorIDs(matchingQuery query: String) -> Set<String> {
        let folded = SearchFold.fold(JSString.trim(query))
        guard !folded.isEmpty else { return [] }
        var matched: Set<String> = []
        for entry in queryHaystacks where entry.haystack.contains(folded) {
            matched.insert(entry.identifier)
        }
        return matched
    }

    /// Catalog company text → operator ids. A slash-joined string that is itself a
    /// bundle name stays one operator. Otherwise each `/` part converts on its own,
    /// and a part that does not convert is dropped.
    public func operatorIDs(forCatalogName name: String) -> [String] {
        let trimmed = JSString.trim(name)
        guard !trimmed.isEmpty else { return [] }
        if let whole = operatorID(forExactName: trimmed) { return [whole] }
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: "/／"))
        guard parts.count > 1 else { return [] }
        var seen: Set<String> = []
        var result: [String] = []
        for part in parts {
            guard let identifier = operatorID(forExactName: part), seen.insert(identifier).inserted else { continue }
            result.append(identifier)
        }
        return result
    }

    /// Exact catalog name, then a stored identity code, then `jp.` plus a timetable token.
    public func operatorID(forCatalogOrTimetableToken token: String) -> String? {
        let trimmed = JSString.trim(token)
        guard !trimmed.isEmpty else { return nil }
        if let exact = operatorID(forExactName: trimmed) { return exact }
        if let coded = operatorID(forIdentityCode: trimmed) { return coded }
        let prefixed = trimmed.hasPrefix("jp.") ? trimmed : "jp." + trimmed
        if prefixed != trimmed {
            if let coded = operatorID(forIdentityCode: prefixed) { return coded }
            if let exact = operatorID(forExactName: prefixed) { return exact }
        }
        return nil
    }

    /// Passenger label. The stored short label wins; a schema-1 record falls back to its first name.
    public func operatorLabel(_ identifier: String) -> String? {
        guard let record = bundle.operatorRecords[identifier] else { return nil }
        if !record.label.isEmpty { return record.label }
        return record.names.first
    }

    /// Logo path stored on the operator. Empty and missing logos are nil.
    public func operatorLogo(_ identifier: String) -> String? {
        guard let logo = bundle.operatorRecords[identifier]?.logo, !logo.isEmpty else { return nil }
        return logo
    }

    private static func exactKey(_ value: String, region: String) -> String {
        let folded = JSString.trim(value).precomposedStringWithCompatibilityMapping
        guard region.lowercased() == "tw" else { return folded }
        return OperatorBranding.normalizeTaiwanCompanyName(folded)
    }

    private static func conversionMaps(
        _ bundle: RegistryBundle
    ) -> (exact: [String: String], byCode: [String: String], lineNames: [String: Int], haystacks: [(String, String)]) {
        var owners: [String: Set<String>] = [:]
        var haystacks: [(String, String)] = []
        var seenHaystack: Set<String> = []
        var codeOwners: [String: Set<String>] = [:]
        for (identifier, record) in bundle.operatorRecords {
            var exactSources = record.names
            if let identity = record.identity, !identity.isEmpty {
                exactSources.append(identity)
                codeOwners[identity, default: []].insert(identifier)
            }
            for raw in exactSources {
                let key = exactKey(raw, region: bundle.region)
                guard !key.isEmpty else { continue }
                owners[key, default: []].insert(identifier)
            }
            var foldSources = record.names
            if !record.label.isEmpty { foldSources.append(record.label) }
            if let identity = record.identity, !identity.isEmpty {
                for name in OperatorIdentity.searchNames(for: identity) where name != identity {
                    foldSources.append(name)
                }
            }
            for raw in foldSources {
                let key = SearchFold.fold(raw)
                guard !key.isEmpty else { continue }
                let token = key + "\u{0}" + identifier
                guard seenHaystack.insert(token).inserted else { continue }
                haystacks.append((key, identifier))
            }
        }
        var exact: [String: String] = [:]
        for (key, identifiers) in owners where identifiers.count == 1 {
            exact[key] = identifiers.first
        }
        var byCode: [String: String] = [:]
        for (code, identifiers) in codeOwners where identifiers.count == 1 {
            byCode[code] = identifiers.first
        }
        var lineNames: [String: Int] = [:]
        for part in bundle.lineParts.values {
            lineNames[part.name, default: 0] += 1
        }
        return (exact, byCode, lineNames, haystacks)
    }

    public func station(_ identifier: String) -> RegistryStationRecord? {
        bundle.stations[identifier]
    }

    public func codes(of stationID: String) -> [String] {
        bundle.stations[stationID]?.codes ?? []
    }

    public func complex(of stationID: String) -> RegistryComplexRecord? {
        guard let complexID = bundle.stations[stationID]?.cx else { return nil }
        return bundle.complexes[complexID]
    }

    public func stations(in complexID: String) -> [String] {
        bundle.complexes[complexID]?.stations ?? []
    }

    public func `operator`(for identifier: String) -> RegistryOperatorRecord? {
        bundle.operatorRecords[identifier]
    }

    /// The operator whose stored identity code equals `code`. Nil unless exactly one does.
    public func operatorID(forIdentityCode code: String) -> String? {
        operatorByIdentityCode[code]
    }

    /// Same fail-closed rule ``RegistryIdentityUpgrade`` used before this facade.
    ///
    /// Canonicalize the code, then a direct `stationCodes` hit wins. A group
    /// code with one station is that station. Several stations narrow to one
    /// only when `operator` owns exactly one of them. Anything else is nil.
    public func stationID(forCode rawCode: String, operator operatorID: String?) -> String? {
        let code = StationCodeAliases.canonical(rawCode)
        if let direct = bundle.stationCodes[code] {
            return direct
        }
        guard let candidates = bundle.groupCodes[code] else { return nil }
        if candidates.count == 1 { return candidates[0] }
        guard let operatorID else { return nil }
        let narrowed = candidates.filter { candidate in
            guard let owner = bundle.stationOperator[candidate] else { return false }
            return sameCodeUnits(owner, operatorID)
        }
        return narrowed.count == 1 ? narrowed[0] : nil
    }

    /// Nil when the bundle has no station record (including every schema 1 file).
    ///
    /// `line` is used only when it serves the station. Otherwise the best line
    /// by rank, then name, then id. A line name that appears once in the country
    /// is shown bare; a repeated name is qualified with the operator's short label.
    public func label(for stationID: String, line requested: String? = nil, country: String) -> RegistryStationLabel? {
        guard let station = bundle.stations[stationID] else { return nil }
        let countryCode = country.uppercased()
        let lineID = chosenLineID(station: station, requested: requested)
        let detail = lineID.flatMap { lineLabel(for: $0) }
        let qualifier = StationLabel.caption(countryCode: countryCode, detail: detail)
        let presentation = StationLabel.presented(
            officialName: station.name,
            qualifier: qualifier,
            parts: station.parts,
            statusWord: nil)
        let text = detail.map {
            StationLabel.make(name: presentation.label, countryCode: countryCode, detail: $0)
        } ?? StationLabel.countryOnly(name: presentation.label, countryCode: countryCode)
        return RegistryStationLabel(presentation: presentation, text: text, lineID: lineID)
    }

    private func chosenLineID(station: RegistryStationRecord, requested: String?) -> String? {
        if let requested, station.lines.contains(requested), bundle.lineParts[requested] != nil {
            return requested
        }
        let choices = station.lines.compactMap { identifier -> StationLabel.LineChoice? in
            guard let part = bundle.lineParts[identifier] else { return nil }
            return StationLabel.LineChoice(id: identifier, label: part.name, rank: part.rank, name: part.name)
        }
        return StationLabel.orderedLines(choices, contextLineIDs: []).first?.id
    }

    private func lineLabel(for lineID: String) -> String? {
        guard let part = bundle.lineParts[lineID] else { return nil }
        let copies = lineNameCounts[part.name] ?? 1
        return StationLabel.lineLabel(
            name: part.name,
            operatorName: brandingSource(for: part.op),
            uniqueInCountry: copies <= 1)
    }

    /// A package name whose ``OperatorBranding/companyLabel(_:)`` equals the stored
    /// short label. Prefer one that the short label actually changes, so a
    /// UTF-16-first spelling such as "JR East" is not the only string offered.
    private func brandingSource(for operatorID: String) -> String? {
        guard let record = bundle.operatorRecords[operatorID] else { return nil }
        let stored = record.label
        guard !stored.isEmpty else { return record.names.first }
        if let changing = record.names.first(where: { name in
            let short = OperatorBranding.companyLabel(name)
            return sameCodeUnits(short, stored) && !sameCodeUnits(short, name)
        }) {
            return changing
        }
        if let exact = record.names.first(where: { sameCodeUnits(OperatorBranding.companyLabel($0), stored) }) {
            return exact
        }
        return stored
    }
}

/// Whether a region's registry can be read yet.
public enum RegistryPhase: Sendable {
    /// Decoded and ready for identity queries.
    case ready(RegistryIdentity)
    /// A bundle exists and a background decode is still running.
    case pending
    /// This region has no bundle, or the file failed to decode.
    case absent
}

/// The app installs a per-region lookup. Tests leave it nil.
public enum RegistryIdentityLookup {
    public typealias Provider = @Sendable (String) -> RegistryIdentity?
    public typealias PhaseProvider = @Sendable (String) -> RegistryPhase

    /// A provider installed for the current task. Parallel tests each keep their own.
    public enum TestOverride: Sendable {
        case sync(Provider?)
        case phase(PhaseProvider?)
    }

    @TaskLocal static var testOverride: TestOverride?

    private static let lock = NSLock()
    nonisolated(unsafe) private static var provider: Provider?
    nonisolated(unsafe) private static var phaseProvider: PhaseProvider?
    nonisolated(unsafe) private static var generation: UInt64 = 0
    nonisolated(unsafe) private static var settled: [String: UInt64] = [:]
    nonisolated(unsafe) private static var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    /// Bumps every time the provider changes or a preload settles. The cache keys on this.
    public static var providerGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    /// A synchronous provider. A nil result is absent, never pending.
    /// Installing one clears a phase provider.
    public static func install(_ provider: Provider?) {
        lock.lock()
        self.provider = provider
        self.phaseProvider = nil
        generation &+= 1
        let pending = waiters
        waiters.removeAll(keepingCapacity: true)
        lock.unlock()
        for list in pending.values {
            for waiter in list { waiter.resume() }
        }
    }

    /// Runs `operation` with a task-local synchronous provider. The app-wide install is unchanged.
    public static func withTestProvider<T>(
        _ provider: Provider?, operation: () throws -> T
    ) rethrows -> T {
        try $testOverride.withValue(.sync(provider), operation: operation)
    }

    /// Runs `operation` with a task-local phase provider. The app-wide install is unchanged.
    public static func withTestPhase<T>(
        _ provider: PhaseProvider?, operation: () throws -> T
    ) rethrows -> T {
        try $testOverride.withValue(.phase(provider), operation: operation)
    }

    /// Async overload. Child tasks inherit the override; `Task.detached` does not.
    public static func withTestPhase<T: Sendable>(
        _ provider: PhaseProvider?,
        operation: nonisolated(nonsending) @Sendable () async throws -> T
    ) async rethrows -> T {
        try await $testOverride.withValue(.phase(provider), operation: operation)
    }

    /// The app's background-preload provider. A nil provider is absent for every region.
    public static func installPhase(_ provider: PhaseProvider?) {
        lock.lock()
        self.provider = nil
        self.phaseProvider = provider
        generation &+= 1
        let pending = waiters
        waiters.removeAll(keepingCapacity: true)
        lock.unlock()
        for list in pending.values {
            for waiter in list { waiter.resume() }
        }
    }

    public static func phase(forRegion region: String) -> RegistryPhase {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return .absent }
        if let testOverride {
            switch testOverride {
            case .sync(let provider):
                if let identity = provider?(cc) { return .ready(identity) }
                return .absent
            case .phase(let provider):
                return provider?(cc) ?? .absent
            }
        }
        lock.lock()
        let sync = provider
        let phased = phaseProvider
        lock.unlock()
        if let phased { return phased(cc) }
        if let sync {
            if let identity = sync(cc) { return .ready(identity) }
            return .absent
        }
        return .absent
    }

    public static func identity(forRegion region: String) -> RegistryIdentity? {
        if case .ready(let identity) = phase(forRegion: region) { return identity }
        return nil
    }

    /// Resume waiters for one region and drop cached misses. Called when a preload finishes.
    public static func notifySettled(region: String) {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return }
        lock.lock()
        generation &+= 1
        settled[cc] = generation
        let resumed = waiters.removeValue(forKey: cc) ?? []
        lock.unlock()
        for waiter in resumed { waiter.resume() }
    }

    /// Waits until the region is ready or absent. A region that is already settled returns immediately.
    /// A notify for a provider this task does not see is ignored and the wait continues.
    public static func waitUntilSettled(region: String) async {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return }
        while true {
            let stamp = settledStamp(cc)
            if case .pending = phase(forRegion: cc) {} else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if !enqueueWaiter(region: cc, stamp: stamp, continuation) {
                    continuation.resume()
                }
            }
        }
    }

    /// Synchronous so the lock stays out of an async context.
    private static func settledStamp(_ region: String) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return settled[region] ?? 0
    }

    /// Returns false when the region settled before the waiter was recorded.
    private static func enqueueWaiter(
        region: String, stamp: UInt64, _ continuation: CheckedContinuation<Void, Never>
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if (settled[region] ?? 0) != stamp { return false }
        waiters[region, default: []].append(continuation)
        return true
    }
}

/// One ``RegistryIdentity`` per region for the currently installed provider.
///
/// Maps are built in ``RegistryIdentity/init(bundle:)``. This cache keeps that
/// build off the per-row path. The lookup lock is never taken while this lock is held.
public enum RegistryIdentityCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var generation: UInt64 = .max
    nonisolated(unsafe) private static var identities: [String: RegistryIdentity] = [:]
    nonisolated(unsafe) private static var misses: Set<String> = []

    public static func identity(forRegion region: String) -> RegistryIdentity? {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return nil }
        // A task-local provider must not read or fill the process-wide cache.
        if RegistryIdentityLookup.testOverride != nil {
            if case .ready(let built) = RegistryIdentityLookup.phase(forRegion: cc) { return built }
            return nil
        }
        let current = RegistryIdentityLookup.providerGeneration
        lock.lock()
        if generation != current {
            identities.removeAll(keepingCapacity: true)
            misses.removeAll(keepingCapacity: true)
            generation = current
        } else if let cached = identities[cc] {
            lock.unlock()
            return cached
        } else if misses.contains(cc) {
            lock.unlock()
            return nil
        }
        lock.unlock()
        switch RegistryIdentityLookup.phase(forRegion: cc) {
        case .pending:
            return nil
        case .absent:
            lock.lock()
            if generation == current { misses.insert(cc) }
            lock.unlock()
            return nil
        case .ready(let built):
            lock.lock()
            defer { lock.unlock() }
            guard generation == current else { return built }
            identities[cc] = built
            return built
        }
    }
}

/// Station text for a ride stop. A missing id, region, or station record is unresolved:
/// the stored name is shown and readings are not looked up by that name.
public struct RegistryStationDisplay: Equatable, Sendable {
    public var primary: String
    public var caption: String?
    public var unresolved: Bool
    public var readingCodes: [String]
    public static let unresolvedKey = "ios.identity.unresolved"

    public init(primary: String, caption: String?, unresolved: Bool, readingCodes: [String]) {
        self.primary = primary
        self.caption = caption
        self.unresolved = unresolved
        self.readingCodes = readingCodes
    }

    /// The first code whose readings row exists. Later codes are tried in order.
    public static func firstCodeWithReading(_ codes: [String], hasRow: (String) -> Bool) -> String? {
        codes.first(where: hasRow)
    }

    public static func resolve(
        storedName: String, stationID: String?, region: String?, lineID: String? = nil
    ) -> RegistryStationDisplay {
        func unresolved() -> RegistryStationDisplay {
            RegistryStationDisplay(primary: storedName, caption: nil, unresolved: true, readingCodes: [])
        }
        func pending() -> RegistryStationDisplay {
            RegistryStationDisplay(primary: storedName, caption: nil, unresolved: false, readingCodes: [])
        }
        guard let stationID, !stationID.isEmpty else { return unresolved() }
        let resolvedRegion = (region?.isEmpty == false ? region : nil) ?? SolverRegistryInput.regionCode(stationID)
        guard let resolvedRegion, !resolvedRegion.isEmpty else { return unresolved() }
        switch RegistryIdentityLookup.phase(forRegion: resolvedRegion) {
        case .pending:
            return pending()
        case .absent:
            return unresolved()
        case .ready(let identity):
            guard let label = identity.label(for: stationID, line: lineID, country: resolvedRegion) else {
                return unresolved()
            }
            let secondary = label.presentation.secondary
            let qualifier = label.text.qualifier
            let caption = !secondary.isEmpty ? secondary : (qualifier.isEmpty ? nil : qualifier)
            return RegistryStationDisplay(
                primary: label.presentation.label,
                caption: caption,
                unresolved: false,
                readingCodes: identity.codes(of: stationID))
        }
    }
}
