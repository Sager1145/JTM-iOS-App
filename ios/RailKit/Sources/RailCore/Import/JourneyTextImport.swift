import Foundation

/// A conservative, local first pass over pasted railway text.
///
/// This parser does not invent station identities. It recognizes clock values, finds station
/// names and aliases in the regional catalog, and returns every catalog candidate for review.
/// A caller must choose a candidate for every stop before ``RawDraft/train(selections:)`` can
/// produce a structured journey.
public extension JourneyCompletion {
    struct RawStop: Hashable, Sendable, Identifiable {
        public var id: Int
        public var sourceText: String
        public var matchedName: String
        public var arrival: String?
        public var departure: String?
        public var platformNumber: Int?
        public var candidates: [CatalogStation]
        /// Full label for each candidate, same order: `府中 (JP, 京王線)`.
        public var candidateLabels: [String]
        /// A base matched more than one station, or the bundle says the base is not unique.
        /// A single visible candidate is still not an automatic choice.
        public var ambiguous: Bool

        public init(
            id: Int, sourceText: String, matchedName: String,
            arrival: String? = nil, departure: String? = nil,
            platformNumber: Int? = nil, candidates: [CatalogStation],
            candidateLabels: [String] = [],
            ambiguous: Bool = false
        ) {
            self.id = id
            self.sourceText = sourceText
            self.matchedName = matchedName
            self.arrival = arrival
            self.departure = departure
            self.platformNumber = platformNumber
            self.candidates = candidates
            self.candidateLabels = candidateLabels
            self.ambiguous = ambiguous
        }

        public var automaticSelection: StationKey? {
            guard !ambiguous, candidates.count == 1 else { return nil }
            return candidates[0].key
        }

        /// One unambiguous candidate is already chosen. An ambiguous stop stays in the
        /// selectable list even when only one candidate is visible, so the rider can
        /// write a selection.
        public var confirmsSingleCandidate: Bool {
            !ambiguous && candidates.count == 1
        }

        /// Candidates the chooser must list. Empty when the single row is already chosen.
        public var selectableCandidates: [CatalogStation] {
            confirmsSingleCandidate ? [] : candidates
        }
    }

    struct RawDraft: Hashable, Sendable {
        public var sourceText: String
        public var date: String?
        public var service: String?
        public var stops: [RawStop]
        public var unmatchedLines: [String]

        public init(
            sourceText: String, date: String? = nil, service: String? = nil,
            stops: [RawStop] = [], unmatchedLines: [String] = []
        ) {
            self.sourceText = sourceText
            self.date = date
            self.service = service
            self.stops = stops
            self.unmatchedLines = unmatchedLines
        }

        /// Builds a canonical draft only after every extracted stop has a catalog selection.
        public func train(
            seed: Train, selections: [Int: StationKey], catalog: EditorCatalog
        ) -> Train? {
            guard stops.count >= 2 else { return nil }
            var builtStops: [Stop] = []
            builtStops.reserveCapacity(stops.count)
            let ridden = seed.stops.first?.rideSegment ?? false

            for (position, raw) in stops.enumerated() {
                guard let key = selections[raw.id],
                      raw.candidates.contains(where: { $0.key == key }),
                      let station = catalog.station(key)
                else { return nil }
                var stop = Stop(
                    name: station.name,
                    n02StationCode: station.key.sourceCode,
                    platformNumber: raw.platformNumber,
                    arrival: raw.arrival,
                    departure: raw.departure,
                    stopType: position == 0
                        ? "origin" : (position == stops.count - 1 ? "destination" : "passenger_stop"),
                    rideSegment: ridden)
                if !RegistryStationSelection.apply(
                    sourceCode: station.key.sourceCode, regionCode: key.regionCode, to: &stop)
                {
                    stop.stationID = nil
                    stop.name = station.name
                    stop.n02StationCode = station.key.sourceCode
                }
                builtStops.append(stop)
            }

            var train = seed
            train.date = date ?? seed.date
            if train.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let service, !service.isEmpty
            {
                train.number = service
            }
            train.origin = builtStops[0].name
            train.destination = builtStops[builtStops.count - 1].name
            train.stops = builtStops
            train.region = builtStops[0].n02StationCode.flatMap { _ in
                selections[stops[0].id]?.regionCode
            } ?? seed.region
            // The old route belongs to the old endpoints. The ordinary editor or route solver
            // can rebuild it from the confirmed station codes.
            train.routePolicy = nil
            train.routeSections = nil
            return train
        }
    }

    static func rawDraft(
        text: String, catalog: EditorCatalog, regionCode: String, seed: Train,
        directory: StationNameDirectory? = nil
    ) -> RawDraft {
        let rawLines = text.components(separatedBy: .newlines)
            .map(TransferGuide.Text.normalize)
            .filter { !$0.isEmpty }
        let segments = rawLines.flatMap(splitRouteLine)
        let names = searchableNames(catalog: catalog, regionCode: regionCode)

        var infos = segments.map { segment in
            RawLine(
                text: segment,
                match: stationMatch(
                    in: segment, searchable: names, catalog: catalog, regionCode: regionCode,
                    directory: directory),
                times: times(in: segment),
                platformNumber: platform(in: segment))
        }

        attachAdjacentTimes(to: &infos)
        let stops = rawStops(from: infos)

        let rideDate = rawLines.lazy.compactMap(date(in:)).first
        let service = firstService(
            in: rawLines, names: names, catalog: catalog, regionCode: regionCode,
            directory: directory)
        let claimed = Set(infos.filter { $0.match != nil || !$0.times.isEmpty }.map(\.text))
        let unmatched = rawLines.filter { !claimed.contains($0) && date(in: $0) == nil && $0 != service }
        return RawDraft(
            sourceText: text, date: rideDate, service: service,
            stops: stops, unmatchedLines: unmatched)
    }
}

private extension JourneyCompletion {
    struct SearchableName {
        var text: String
        var folded: String
        var stations: [CatalogStation]
    }

    struct StationMatch {
        var name: String
        var candidates: [CatalogStation]
        var labels: [String]
        var ambiguous: Bool = false
    }

    struct RawLine {
        var text: String
        var match: StationMatch?
        var times: [String]
        var platformNumber: Int?
        var timeText: String?

        init(
            text: String, match: StationMatch?, times: [String],
            platformNumber: Int?, timeText: String? = nil
        ) {
            self.text = text
            self.match = match
            self.times = times
            self.platformNumber = platformNumber
            self.timeText = timeText
        }
    }

    static func attachAdjacentTimes(to infos: inout [RawLine]) {
        // Timetable copies often place a station and its time on adjacent rows. Attach a
        // time-only row to the nearest station row, preferring the row after the station.
        var ownedRows: Set<Int> = []
        for index in infos.indices where infos[index].match != nil && infos[index].times.isEmpty {
            if infos.indices.contains(index + 1), infos[index + 1].match == nil,
               !infos[index + 1].times.isEmpty, !ownedRows.contains(index + 1)
            {
                infos[index].times = infos[index + 1].times
                infos[index].timeText = infos[index + 1].text
                ownedRows.insert(index + 1)
            } else if index > 0, infos[index - 1].match == nil, !infos[index - 1].times.isEmpty,
                      !ownedRows.contains(index - 1) {
                infos[index].times = infos[index - 1].times
                infos[index].timeText = infos[index - 1].text
                ownedRows.insert(index - 1)
            }
        }
    }

    static func rawStops(from infos: [RawLine]) -> [RawStop] {
        let matched = infos.filter { $0.match != nil }
        var stops: [RawStop] = []
        for (position, info) in matched.enumerated() {
            guard let match = info.match else { continue }
            let assigned = assign(
                info.times,
                markerText: info.text + " " + (info.timeText ?? ""),
                position: position,
                count: matched.count)
            let stop = RawStop(
                id: stops.count,
                sourceText: info.text,
                matchedName: match.name,
                arrival: assigned.arrival,
                departure: assigned.departure,
                platformNumber: info.platformNumber,
                candidates: match.candidates,
                candidateLabels: match.labels,
                ambiguous: match.ambiguous)
            // Repeated headers and copied transfer rows can say the same station twice. Preserve
            // a genuine revisit, but collapse adjacent duplicate rows with identical times.
            if let last = stops.last,
               Set(last.candidates.map(\.key)) == Set(stop.candidates.map(\.key)),
               last.arrival == stop.arrival, last.departure == stop.departure
            {
                continue
            }
            stops.append(stop)
        }
        for index in stops.indices { stops[index].id = index }

        return stops
    }

    static func firstService(
        in rawLines: [String], names: [SearchableName], catalog: EditorCatalog, regionCode: String,
        directory: StationNameDirectory? = nil
    ) -> String? {
        let service = rawLines.lazy.compactMap { line -> String? in
            guard stationMatch(
                in: line, searchable: names, catalog: catalog, regionCode: regionCode,
                directory: directory) == nil,
                  times(in: line).isEmpty,
                  looksLikeService(line)
            else { return nil }
            return cleanedService(line)
        }.first
        return service
    }

    static func splitRouteLine(_ line: String) -> [String] {
        let parts = line.components(separatedBy: "→")
            .flatMap { $0.components(separatedBy: "=>") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [line] : parts
    }

    static func searchableNames(
        catalog: EditorCatalog, regionCode: String
    ) -> [SearchableName] {
        var grouped: [String: (text: String, stations: [CatalogStation])] = [:]
        for station in catalog.stations(in: regionCode) {
            for name in [station.name] + station.aliases {
                let folded = name.precomposedStringWithCompatibilityMapping.lowercased()
                guard !folded.isEmpty else { continue }
                var value = grouped[folded] ?? (name, [])
                if !value.stations.contains(where: { $0.key == station.key }) {
                    value.stations.append(station)
                }
                grouped[folded] = value
            }
        }
        return grouped.map { SearchableName(text: $0.value.text, folded: $0.key, stations: $0.value.stations) }
            .sorted {
                if $0.folded.count != $1.folded.count { return $0.folded.count > $1.folded.count }
                return $0.folded < $1.folded
            }
    }

    static func stationMatch(
        in line: String, searchable: [SearchableName], catalog: EditorCatalog, regionCode: String,
        directory: StationNameDirectory? = nil
    ) -> StationMatch? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let foldedLine = fold(trimmed)
        guard !foldedLine.isEmpty else { return nil }
        switch RegistryIdentityLookup.phase(forRegion: regionCode) {
        case .pending:
            return StationMatch(name: trimmed, candidates: [], labels: [], ambiguous: true)
        case .unavailable:
            return nil
        case .ready(let identity):
            guard !identity.bundle.stations.isEmpty else { return nil }
            let stored = directory ?? StationNameLookup.directory(forRegion: regionCode)
            return registryStationMatch(
                in: trimmed, identity: identity, catalog: catalog, regionCode: regionCode,
                directory: stored)
        }
    }

    /// Registry records answer the segment. Catalog rows are attached when a
    /// code is still in the editor catalog, so a confirmed draft can be built.
    private static func registryStationMatch(
        in trimmed: String, identity: RegistryIdentity, catalog: EditorCatalog,
        regionCode: String, directory: StationNameDirectory?
    ) -> StationMatch? {
        let names = directory ?? StationNameDirectory(bundle: identity.bundle)
        guard let parsed = StationReference.parse(trimmed, names: names) else { return nil }
        let whole = StationReferenceResolution.resolve(parsed, identity: identity)
        let countryBound = parsed.country != nil || parsed.unsupportedCountry
        if countryBound || parsed.line != nil {
            if !whole.isEmpty {
                return registryMatch(whole, catalog: catalog, regionCode: regionCode)
            }
            // `東京 (3番線)` and `09:00 (発) 東京` are not country qualifiers.
            // A line token that serves no station falls through to a name span.
            // A country, including a wrong line, stays unresolved.
            if countryBound { return nil }
        }
        let exactText = fold(parsed.name) == fold(trimmed)
        if parsed.line == nil, exactText, !whole.isEmpty {
            return registryMatch(whole, catalog: catalog, regionCode: regionCode)
        }
        let spans = identity.containedNameSpans(in: trimmed)
        var groups: [[RegistryIdentity.StationInputMatch]] = []
        for span in spans {
            let reference = StationReference.parse(span, names: names) ?? StationReference(name: span)
            let hits = StationReferenceResolution.resolve(reference, identity: identity)
            if !hits.isEmpty { groups.append(hits) }
        }
        return combinedSpanMatches(groups, catalog: catalog, regionCode: regionCode)
    }

    private static func registryMatch(
        _ hits: [RegistryIdentity.StationInputMatch], catalog: EditorCatalog, regionCode: String
    ) -> StationMatch {
        combinedSpanMatches([hits], catalog: catalog, regionCode: regionCode)
            ?? StationMatch(name: hits.first?.name ?? "", candidates: [], labels: hits.map(\.label), ambiguous: true)
    }

    private static func combinedSpanMatches(
        _ groups: [[RegistryIdentity.StationInputMatch]], catalog: EditorCatalog, regionCode: String
    ) -> StationMatch? {
        guard !groups.isEmpty else { return nil }
        var stations: [CatalogStation] = []
        var labels: [String] = []
        var seen: Set<String> = []
        for hits in groups {
            for hit in hits {
                labels.append(hit.label)
                guard seen.insert(hit.stationID).inserted else { continue }
                if let station = catalogStation(for: hit, catalog: catalog, regionCode: regionCode) {
                    stations.append(station)
                }
            }
        }
        let distinct = Set(groups.flatMap { $0.map(\.stationID) })
        return StationMatch(
            name: groups.first?.first?.name ?? "",
            candidates: stations,
            labels: labels,
            ambiguous: distinct.count != 1 || stations.count != 1)
    }

    private static func catalogStation(
        for hit: RegistryIdentity.StationInputMatch, catalog: EditorCatalog, regionCode: String
    ) -> CatalogStation? {
        for code in hit.codes {
            if let station = catalog.station(StationKey(regionCode: regionCode, sourceCode: code)) {
                return station
            }
        }
        return catalog.stations(in: regionCode).first { station in
            station.name == hit.name && hit.codes.contains(station.key.sourceCode)
        }
    }

    private static func fold(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .lowercased()
    }

    static func times(in line: String) -> [String] {
        let expression = try? NSRegularExpression(
            pattern: #"(?<![0-9])([0-9]{1,2}:[0-9]{2}(?:[ \t]*\+[ \t]*[0-9]{1,3})?)(?![0-9])"#)
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return expression?.matches(in: line, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: line) else { return nil }
            let raw = String(line[swiftRange])
            guard case .valid(_, let time) = EditorTime.parseTime(raw) else { return nil }
            return EditorTime.canonical(time)
        } ?? []
    }

    static func assign(
        _ times: [String], markerText: String, position: Int, count: Int
    ) -> (arrival: String?, departure: String?) {
        guard let first = times.first else { return (nil, nil) }
        if times.count >= 2 { return (first, times[1]) }
        if markerText.contains("着"), !markerText.contains("発") { return (first, nil) }
        if markerText.lowercased().contains("arriv"), !markerText.lowercased().contains("depart") {
            return (first, nil)
        }
        if markerText.contains("発"), !markerText.contains("着") { return (nil, first) }
        if markerText.lowercased().contains("depart"), !markerText.lowercased().contains("arriv") {
            return (nil, first)
        }
        if position == count - 1 { return (first, nil) }
        return (nil, first)
    }

    static func platform(in line: String) -> Int? {
        let expression = try? NSRegularExpression(
            pattern: #"(?:[着発]\s*)?([0-9]{1,3})\s*(?:番線|のりば|ホーム|platform|track)"#,
            options: [.caseInsensitive])
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = expression?.firstMatch(in: line, range: range),
              let swiftRange = Range(match.range(at: 1), in: line)
        else { return nil }
        return Int(line[swiftRange])
    }

    static func date(in line: String) -> String? {
        let expression = try? NSRegularExpression(pattern: #"(?<![0-9])([0-9]{4}[-/][0-9]{2}[-/][0-9]{2})(?![0-9])"#)
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = expression?.firstMatch(in: line, range: range),
              let swiftRange = Range(match.range(at: 1), in: line)
        else { return nil }
        if case .valid(_, _, _, let canonical) = EditorTime.parseDate(String(line[swiftRange])) {
            return canonical
        }
        return nil
    }

    static func looksLikeService(_ line: String) -> Bool {
        let lower = line.lowercased()
        return line.contains("号") || line.contains("列車") || line.contains("新幹線")
            || line.contains("特急") || line.contains("快速") || line.contains("急行")
            || lower.contains("train") || lower.contains("express") || lower.contains("rapid")
            || lower.contains("service")
    }

    static func cleanedService(_ line: String) -> String {
        for separator in [":", "："] {
            if let index = line.firstIndex(of: Character(separator)) {
                let suffix = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
                if !suffix.isEmpty { return suffix }
            }
        }
        return line
    }
}
