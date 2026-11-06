import Foundation

/// The physical railways one trip ran over, in travel order, per recorded
/// route section — the single derivation every trip surface reads.
///
/// Each section's runs come from the best evidence available for it, in
/// this order: a pending confirmation claims nothing; an unproven section
/// keeps its recorded names; a selected physical route gives the run-length
/// encoding of its interval line ids; drawn geometry gives the detected
/// lines (unless an ordinary service recorded its own name); otherwise the
/// recorded names. Route-policy names appear only when no section has any.
///
/// Adjacent runs merge on the same line id, or on the same canonical name
/// and the same operator. Nothing is deduplicated globally: a loop A→B→A
/// keeps both A runs. The service caption is carried beside the runs and
/// never merged into them.
public struct RiddenLineSequence: Equatable, Sendable {
    public struct Line: Hashable, Sendable {
        public var lineID: String?
        public var name: String
        public var operatorName: String?

        public init(lineID: String?, name: String, operatorName: String?) {
            self.lineID = lineID
            self.name = name
            self.operatorName = operatorName
        }

        /// The passenger-facing name: a line-id override when one exists,
        /// otherwise the line's own name.
        public func displayName(language: String = OperatorIdentity.displayLanguage) -> String {
            lineID.flatMap { RiddenLineSequence.passengerName(forLineID: $0, language: language) } ?? name
        }
    }

    public enum BoundaryKind: Equatable, Sendable {
        /// Service codes of the through services joining the two lines there.
        case throughService([String])
        /// Same canonical line name, different operator (JR East → JR West).
        case operatorChange
        case lineChange
    }

    public struct Boundary: Equatable, Sendable {
        public var stationCode: String?
        public var stationName: String?
        public var stopIndex: Int?
        public var kind: BoundaryKind

        public init(stationCode: String?, stationName: String?, stopIndex: Int?, kind: BoundaryKind) {
            self.stationCode = stationCode
            self.stationName = stationName
            self.stopIndex = stopIndex
            self.kind = kind
        }
    }

    public enum Source: String, Sendable {
        case solved, geometry, recorded, policy, none
    }

    public enum Status: Equatable, Sendable {
        case resolved(certified: Bool)
        case unproven
        case unresolved
        case pending
    }

    public struct Section: Equatable, Sendable {
        public var sectionIndex: Int
        /// Recorded visit at the section's start or end, when the boundary is a call.
        public var fromStopIndex: Int?
        public var toStopIndex: Int?
        /// The recorded stop interval (stop k → k+1) enclosing this section.
        public var stopInterval: Int?
        public var from: String?
        public var to: String?
        public var runs: [Line]
        /// Boundaries inside the section; `count == max(0, runs.count - 1)`.
        public var boundaries: [Boundary]
        public var status: Status
        public var source: Source
        /// Line id of the last piece folded into the last run (a run named
        /// 東北線 can end on 東北線-2); a join's through-service lookup needs it.
        var tailLineID: String?
    }

    public typealias Continuations = @Sendable (
        _ fromLineID: String, _ toLineID: String, _ stationCode: String, _ date: String?
    ) -> [String]

    public let sections: [Section]
    /// Key is the index (`sectionIndex`) of the later section. Present only
    /// where the line changes across the section join.
    public let joins: [Int: Boundary]
    /// `train.number`, trimmed. Never part of `runs`.
    public let serviceCaption: String

    /// Every section's runs in order, with adjacent equal runs merged and the
    /// joins between sections as boundaries. Never deduplicated globally.
    public var summary: (runs: [Line], boundaries: [Boundary]) {
        Self.concatenate(sections, joins: joins)
    }

    /// Line ids from sections whose runs came from a solved route or geometry.
    public var resolvedLineIDs: [String] {
        var seen = Set<String>()
        return sections.lazy.filter {
            if case .resolved = $0.status { return $0.source == .solved || $0.source == .geometry }
            return false
        }.flatMap(\.runs).compactMap(\.lineID).filter { seen.insert($0).inserted }
    }

    /// Runs over the recorded stop interval `index` (stop `index` → `index + 1`).
    public func stopInterval(_ index: Int) -> (runs: [Line], boundaries: [Boundary]) {
        Self.concatenate(sections.filter { $0.stopInterval == index }, joins: joins)
    }

    /// True when any section's runs came from a solved route.
    public var hasSolvedSection: Bool { sections.contains { $0.source == .solved } }

    public init(
        train: Train,
        sections: [RouteSection]? = nil,
        selections: [Int: RideRouteResolution.PhysicalRouteSelection] = [:],
        drawnSections: Set<Int> = [],
        gaps: [RideRouteResolution.PhysicalGap] = [],
        geometryLines: [Int: [Statistics.TraversedLine]] = [:],
        solveSettled: Bool = false,
        continuations: Continuations? = RiddenLineSequence.bundledContinuations,
        stationName: ((String) -> String?)? = nil
    ) {
        let routeSections = sections ?? train.routeSections ?? []
        let date = train.date.map { String($0.prefix(10)) }
        let mapping = RecordedRouteMapping(stops: train.stops, sections: routeSections)
        let stopCount = train.stops.count
        serviceCaption = train.number.trimmingCharacters(in: .whitespacesAndNewlines)

        func kind(_ a: Line, _ b: Line, at station: String?) -> BoundaryKind {
            if Self.canonical(a.name) == Self.canonical(b.name), a.operatorName != b.operatorName {
                return .operatorChange
            }
            if let from = a.lineID, let to = b.lineID, let station, let continuations {
                let codes = Set(continuations(from, to, station, date))
                if !codes.isEmpty { return .throughService(codes.sorted()) }
            }
            return .lineChange
        }
        func boundary(_ a: Line, _ b: Line, at station: String?, name: String? = nil, stop: Int? = nil) -> Boundary {
            Boundary(stationCode: station, stationName: station.flatMap { stationName?($0) } ?? name,
                     stopIndex: stop, kind: kind(a, b, at: station))
        }
        /// Merges adjacent continuing runs; one boundary per remaining change.
        func encode(_ pieces: [(line: Line, startStation: String?)])
            -> (runs: [Line], boundaries: [Boundary], tail: String?) {
            var runs: [Line] = []
            var boundaries: [Boundary] = []
            var tail: String?
            for piece in pieces {
                if let last = runs.last {
                    if Self.continues(last, piece.line) {
                        tail = piece.line.lineID ?? tail
                        continue
                    }
                    var ending = last
                    ending.lineID = tail ?? last.lineID
                    boundaries.append(boundary(ending, piece.line, at: piece.startStation))
                }
                runs.append(piece.line)
                tail = piece.line.lineID
            }
            return (runs, boundaries, tail)
        }
        func recordedPieces(_ section: RouteSection) -> [(line: Line, startStation: String?)] {
            let names = (section.lineNames ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let ids = section.lineIDs ?? []
            let operators = section.operatorNames ?? []
            return names.enumerated().compactMap { offset, name in
                guard !name.isEmpty else { return nil }
                // The name and id arrays are not parallel (ids are stored sorted), so an
                // id is attached only when unambiguous: one name, one id.
                let lineID = names.count == 1 && ids.count == 1 ? ids[0] : nil
                let operatorName = operators.count == names.count ? operators[offset]
                    : operators.count == 1 ? operators[0] : nil
                return (line: Line(lineID: lineID?.isEmpty == false ? lineID : nil, name: name,
                                   operatorName: operatorName?.isEmpty == false ? operatorName : nil),
                        startStation: nil)
            }
        }
        func selectedPieces(_ selection: RideRouteResolution.PhysicalRouteSelection)
            -> [(line: Line, startStation: String?)] {
            func line(_ id: String) -> Line {
                if let known = selection.lines.first(where: { $0.lineID == id }) {
                    return Line(lineID: id, name: known.name, operatorName: known.operatorName)
                }
                return Line(lineID: id, name: id, operatorName: nil)
            }
            guard !selection.intervals.isEmpty else {
                return selection.lines.map { (line: line($0.lineID), startStation: nil) }
            }
            var pieces: [(line: Line, startStation: String?)] = []
            var current: String? = selection.fromStationCode
            var previousPair: (String, String)?
            for interval in selection.intervals {
                let id = interval.lineID.isEmpty
                    ? RailIntervalCodes.lineID(ofIntervalCode: interval.code) ?? interval.code : interval.lineID
                let pair = RailIntervalCodes.stationCodes(ofIntervalCode: interval.code)
                // The shared station of the previous and this interval; the
                // walked position settles a two-station loop.
                var start: String?
                if let pair, let previousPair {
                    let shared = Set([pair.0, pair.1]).intersection([previousPair.0, previousPair.1])
                    if shared.count == 1 { start = shared.first }
                    else if let current, shared.contains(current) { start = current }
                } else {
                    start = current
                }
                if pieces.last?.line.lineID != id { pieces.append((line: line(id), startStation: start)) }
                if let pair {
                    let from = start ?? current
                    current = from == pair.0 ? pair.1 : from == pair.1 ? pair.0 : nil
                } else {
                    current = nil
                }
                previousPair = pair
            }
            return pieces
        }

        let unproven = Set(gaps.lazy.filter(\.isUnproven).map(\.segmentIndex))
        let uncertified = RideRouteResolution.PhysicalGap.uncertifiedSections(gaps)
        let ordinaryService = !TrainServiceBranding.usesDetectedLines(train)
        let fallbackStatus: Status = solveSettled ? .unresolved : .pending

        var built: [Section] = routeSections.enumerated().map { index, route in
            var section = Section(
                sectionIndex: index,
                fromStopIndex: mapping.map { $0.stopIndex(atSectionBoundary: index) }
                    ?? (index < stopCount ? index : nil),
                toStopIndex: mapping.map { $0.stopIndex(atSectionBoundary: index + 1) }
                    ?? (index + 1 < stopCount ? index + 1 : nil),
                stopInterval: mapping?.stopInterval(forSectionIndex: index)
                    ?? (index + 1 < stopCount ? index : nil),
                from: route.from, to: route.to, runs: [], boundaries: [],
                status: fallbackStatus, source: .none, tailLineID: nil)
            let recorded = recordedPieces(route)
            let encoded: (runs: [Line], boundaries: [Boundary], tail: String?)
            if train.requiresRouteConfirmation {
                section.status = .pending
                return section
            } else if unproven.contains(index) {
                section.status = .unproven
                encoded = encode(recorded)
                section.source = encoded.runs.isEmpty ? .none : .recorded
            } else if let selection = selections[index] {
                section.status = .resolved(certified: !uncertified.contains(index))
                section.source = .solved
                encoded = encode(selectedPieces(selection))
            } else if drawnSections.contains(index), let lines = geometryLines[index], !lines.isEmpty {
                section.status = .resolved(certified: false)
                if ordinaryService && !recorded.isEmpty {
                    section.source = .recorded
                    encoded = encode(recorded)
                } else {
                    section.source = .geometry
                    encoded = encode(lines.map {
                        (line: Line(lineID: $0.selectedLineID, name: $0.name, operatorName: $0.operatorName),
                         startStation: nil)
                    })
                }
            } else {
                encoded = encode(recorded)
                section.source = encoded.runs.isEmpty ? .none : .recorded
            }
            section.runs = encoded.runs
            section.boundaries = encoded.boundaries
            section.tailLineID = encoded.tail
            return section
        }

        if !train.requiresRouteConfirmation, built.allSatisfy({ $0.source == .none }) {
            let policy = (train.routePolicy?.preferredLineNames ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !policy.isEmpty {
                // Policy names are corridor hints, not ridden sections: one
                // synthetic section that maps to no recorded stop interval.
                let encoded = encode(policy.map { (line: Line(lineID: nil, name: $0, operatorName: nil), startStation: nil) })
                built = [Section(
                    sectionIndex: 0, fromStopIndex: nil, toStopIndex: nil, stopInterval: nil,
                    from: nil, to: nil, runs: encoded.runs, boundaries: encoded.boundaries,
                    status: fallbackStatus, source: .policy, tailLineID: nil)]
            }
        }

        var joins: [Int: Boundary] = [:]
        var previous: Int?
        for position in built.indices where !built[position].runs.isEmpty {
            defer { previous = position }
            guard let earlier = previous,
                  let last = built[earlier].runs.last, let first = built[position].runs.first,
                  !Self.continues(last, first) else { continue }
            let adjacent = built[position].sectionIndex == built[earlier].sectionIndex + 1
            let index = built[earlier].sectionIndex
            let route = routeSections.indices.contains(index) ? routeSections[index] : nil
            let station = adjacent ? (selections[index]?.toStationCode ?? route?.toN02StationCode) : nil
            var ending = last
            ending.lineID = built[earlier].tailLineID ?? last.lineID
            joins[built[position].sectionIndex] = boundary(
                ending, first, at: station?.isEmpty == false ? station : nil,
                name: adjacent ? route?.to : nil,
                stop: adjacent ? mapping?.stopIndex(atSectionBoundary: index + 1) : nil)
        }
        self.sections = built
        self.joins = joins
    }

    /// Adjacent runs continue on the same line id, or on the same canonical
    /// name under the same operator.
    public static func continues(_ a: Line, _ b: Line) -> Bool {
        if let left = a.lineID, let right = b.lineID, left == right { return true }
        return canonical(a.name) == canonical(b.name) && a.operatorName == b.operatorName
    }

    private static func canonical(_ name: String) -> String {
        TrainServiceBranding.canonicalLineName(name)
    }

    private static func concatenate(_ sections: [Section], joins: [Int: Boundary])
        -> (runs: [Line], boundaries: [Boundary]) {
        var runs: [Line] = []
        var boundaries: [Boundary] = []
        for section in sections where !section.runs.isEmpty {
            if runs.isEmpty {
                runs = section.runs
                boundaries = section.boundaries
                continue
            }
            if let join = joins[section.sectionIndex] {
                boundaries.append(join)
                runs += section.runs
            } else if Self.continues(runs[runs.count - 1], section.runs[0]) {
                runs += section.runs.dropFirst()
                boundaries += section.boundaries
                continue
            } else {
                // Only a section outside the join chain reaches here (a stop
                // interval filtered away from its predecessor).
                boundaries.append(Boundary(stationCode: nil, stationName: nil, stopIndex: nil, kind: .lineChange))
                runs += section.runs
            }
            boundaries += section.boundaries
        }
        return (runs, boundaries)
    }

    // MARK: - Physical selections from drawn parts

    /// One selection per section from drawn parts in part order: the first
    /// part's selection, or the parts' distinct selections joined in order.
    public static func selections(
        _ parts: [(segmentIndex: Int, selection: RideRouteResolution.PhysicalRouteSelection?)]
    ) -> [Int: RideRouteResolution.PhysicalRouteSelection] {
        var distinct: [Int: [RideRouteResolution.PhysicalRouteSelection]] = [:]
        for part in parts {
            guard let selection = part.selection else { continue }
            if !(distinct[part.segmentIndex] ?? []).contains(selection) {
                distinct[part.segmentIndex, default: []].append(selection)
            }
        }
        return distinct.compactMapValues { list in
            guard let first = list.first, let last = list.last else { return nil }
            guard list.count > 1 else { return first }
            var lines: [ResolvedRailLine] = []
            for line in list.flatMap(\.lines) {
                if let index = lines.firstIndex(where: { $0.lineID == line.lineID }) {
                    let previous = lines[index]
                    lines[index] = ResolvedRailLine(lineID: previous.lineID, name: previous.name,
                                                    operatorName: previous.operatorName, km: previous.km + line.km)
                } else {
                    lines.append(line)
                }
            }
            return RideRouteResolution.PhysicalRouteSelection(
                fromStationCode: first.fromStationCode, toStationCode: last.toStationCode,
                intervals: list.flatMap(\.intervals), lines: lines, provenance: first.provenance,
                databaseProvenance: first.databaseProvenance)
        }
    }

    // MARK: - Through-service catalog

    /// The bundled Japanese through-service catalog. Ids outside Japan never
    /// appear in it, so other regions skip the lookup.
    public static let bundledContinuations: Continuations = { from, to, station, date in
        guard from.hasPrefix("jp-") || to.hasPrefix("jp-"),
              let catalog = try? JapanThroughServices.loadBundled() else { return [] }
        return Array(JapanThroughServices.continuationCodes(
            fromLineID: from, toLineID: to, atStationCode: station, on: date,
            patterns: catalog.patterns, connectors: catalog.connectors))
    }

    // MARK: - Passenger-name overrides

    /// Package lines whose identity name is not the one passengers use.
    /// `jp-東日本旅客鉄道-総武線-3` is the 品鶴線 corridor (品川–鶴見 via
    /// 武蔵小杉) that 横須賀線 and 湘南新宿ライン trains run over.
    private static let passengerNames: [String: [String: String]] = [
        "jp-東日本旅客鉄道-総武線-3": [
            "ja": "横須賀線", "zh-Hant": "橫須賀線", "zh-Hans": "横须贺线", "en": "Yokosuka Line",
        ],
    ]

    /// The passenger name for a package line id, in `language`; nil when the
    /// line's own name is already the passenger one.
    public static func passengerName(
        forLineID lineID: String, language: String = OperatorIdentity.displayLanguage
    ) -> String? {
        guard let names = passengerNames[lineID] else { return nil }
        if let exact = names[language] { return exact }
        let lowered = language.lowercased()
        if lowered.hasPrefix("zh") {
            let simplified = lowered.contains("hans") || lowered.hasSuffix("-cn") || lowered.hasSuffix("-sg")
            return names[simplified ? "zh-Hans" : "zh-Hant"]
        }
        if lowered.hasPrefix("en") { return names["en"] }
        return names["ja"]
    }
}
