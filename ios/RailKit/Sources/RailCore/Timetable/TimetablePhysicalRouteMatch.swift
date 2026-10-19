import Foundation

/// A separate operation from `TimetableTripMatch`: it proves a rider's original
/// boundary chain inside one published occurrence without applying the whole trip.
/// The caller supplies date-indexed candidates and subsequently validates the
/// returned physical identities against its dated network and source geometry.
public enum TimetablePhysicalRouteMatch {
    /// A service-date snapshot indexed by exact recorded station identities.
    /// This excludes only occurrences that cannot contain the recorded calls.
    /// Order, repeated visits, uncertain clocks and physical proof stay with
    /// the matcher; this index never establishes a route or its uniqueness.
    public struct CandidateIndex: Sendable {
        private let trips: [TrainTimetableDatabase.Trip]
        private let stationTrips: [String: Set<Int>]
        public var tripCount: Int { trips.count }

        public init(trips: [TrainTimetableDatabase.Trip]) {
            var seen = Set<TrainTimetableDatabase.Trip>()
            self.trips = trips.filter { seen.insert($0).inserted }
            var postings: [String: Set<Int>] = [:]
            for (index, trip) in self.trips.enumerated() {
                for code in Set(trip.passengerStops.compactMap(\.station.currentSourceCode)) {
                    postings[code, default: []].insert(index)
                }
            }
            stationTrips = postings
        }

        fileprivate func candidates(for train: Train) -> [TrainTimetableDatabase.Trip] {
            let codes = Set(train.stops.compactMap(\.n02StationCode))
            guard !codes.isEmpty else { return trips }
            var postings: [Set<Int>] = []
            for code in codes {
                guard let matches = stationTrips[code] else { return [] }
                postings.append(matches)
            }
            guard let smallest = postings.min(by: { $0.count < $1.count }) else { return [] }
            return smallest.sorted().filter { index in
                postings.allSatisfy { $0.contains(index) }
            }.map { trips[$0] }
        }
    }

    public enum Outcome: Sendable, Equatable {
        case matched(Match)
        case ambiguous
        case unavailable
        /// An identity, supplied constraint, or required evidence could not be verified.
        case unsupported
    }

    public struct Provenance: Codable, Sendable, Hashable {
        public let tripID: String
        public let serviceDate: String
        public let timetableVersionID: String
        public let calendarID: String
    }

    public struct Section: Sendable, Hashable {
        public let originalIndex: Int
        public let originalSection: RouteSection
        public let fromPassengerCallIndex: Int
        public let toPassengerCallIndex: Int
        /// Traversal order and repeated passages are retained.
        public let sectionCodes: [String]
        public let lineIDs: [String]

        public var enrichedRouteSection: RouteSection {
            var section = originalSection
            // Explicit choices were checked for exact agreement before this result.
            if section.sectionCodes?.isEmpty != false { section.sectionCodes = sectionCodes }
            if section.lineIDs?.isEmpty != false { section.lineIDs = lineIDs }
            return section
        }
    }

    public struct Match: Sendable, Equatable {
        public let provenance: Provenance
        /// Original recorded visits mapped together, including repeated stations.
        public let passengerCallIndices: [Int]
        public let sections: [Section]
        public var serviceDate: String { provenance.serviceDate }
        public var enrichedRouteSections: [RouteSection] { sections.map(\.enrichedRouteSection) }
    }

    public static func resolve(
        for train: Train, routeSections: [RouteSection],
        among trips: [TrainTimetableDatabase.Trip]
    ) -> Outcome {
        if Task.isCancelled { return .unsupported }
        return resolve(for: train, routeSections: routeSections,
                       indexedBy: [CandidateIndex(trips: trips)])
    }

    /// Reuse the service-date indexes for an entire batch instead of hashing
    /// every trip and inspecting every published call for each journey.
    public static func resolve(
        for train: Train, routeSections: [RouteSection],
        indexedBy indexes: [CandidateIndex]
    ) -> Outcome {
        if Task.isCancelled { return .unsupported }
        guard TrainTimetableDatabase.accepts(train), !train.requiresRouteConfirmation,
              train.stops.count >= 2, !routeSections.isEmpty,
              let rideDate = train.date, gregorianDate(rideDate) != nil,
              train.vehicleType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              let times = recordedTimes(train.stops),
              train.stops.allSatisfy({ nonempty($0.n02StationCode) != nil
                  && ["origin", "passenger_stop", "destination"].contains($0.stopType) }),
              routeSections.allSatisfy({ nonempty($0.fromN02StationCode) != nil && nonempty($0.toN02StationCode) != nil }),
              routeSections.first?.fromN02StationCode == train.stops.first?.n02StationCode,
              routeSections.last?.toN02StationCode == train.stops.last?.n02StationCode,
              zip(routeSections, routeSections.dropFirst()).allSatisfy({
                  $0.0.toN02StationCode == $0.1.fromN02StationCode
              })
        else { return .unsupported }

        let trips = indexes.flatMap { $0.candidates(for: train) }
        var matches: [Match] = []
        var missingProof = false
        var budget = 20_000
        // Identical materializations do not manufacture ambiguity. Distinct
        // occurrences and distinct ordered station embeddings do.
        for trip in Set(trips) {
            if Task.isCancelled { return .unsupported }
            guard let dateOffset = dayDifference(from: trip.serviceDate, to: rideDate),
                  (0...2).contains(dateOffset) else { continue }
            let serviceAgreement = serviceConstraints(train, trip: trip)
            switch serviceAgreement {
            case .no: continue
            case .unknown, .yes: break
            }
            let calls = trip.passengerStops
            guard calls.count >= train.stops.count else { continue }
            var stopMappings: [(indices: [Int], unknown: Bool)] = []
            func mapStops(_ index: Int, after: Int, path: [Int], hasUnknown: Bool) {
                guard budget > 0 else { return }
                if index == train.stops.count { stopMappings.append((path, hasUnknown)); return }
                guard after + 1 < calls.count else { return }
                for callIndex in (after + 1)..<calls.count {
                    budget -= 1
                    guard budget > 0 else { return }
                    let call = calls[callIndex], stop = train.stops[index]
                    guard call.station.currentSourceCode == stop.n02StationCode else { continue }
                    var unknown = hasUnknown
                    var conflictingTime = false
                    let exactClock = call.timeAccuracy == "exact" || call.timeAccuracy == "minute"
                    for (recorded, published) in [(times[index].arrival, call.arrivalSeconds),
                                                   (times[index].departure, call.departureSeconds)] {
                        guard let recorded else { continue }
                        if exactClock, let published {
                            if published != recorded + dateOffset * 86_400 { conflictingTime = true }
                        } else { unknown = true }
                    }
                    if conflictingTime { continue }
                    if index == 0, !call.pickupAllowed { continue }
                    if index == train.stops.count - 1, !call.dropoffAllowed { continue }
                    if let platform = stop.platformNumber {
                        if let published = call.platform.flatMap(platformNumber) {
                            if platform != published { continue }
                        } else { unknown = true }
                    }
                    // An untimed first visit still belongs to the rider's civil
                    // boarding day; do not freely shift it to a different day.
                    if index == 0, times[0].arrival == nil, times[0].departure == nil {
                        if exactClock, let seconds = call.departureSeconds ?? call.arrivalSeconds {
                            if seconds / 86_400 != dateOffset { continue }
                        } else { unknown = true }
                    }
                    mapStops(index + 1, after: callIndex, path: path + [callIndex], hasUnknown: unknown)
                }
            }
            mapStops(0, after: -1, path: [], hasUnknown: false)
            if budget <= 0 { return .unsupported }
            guard !stopMappings.isEmpty else { continue }
            for mapping in stopMappings {
                let stopMapping = mapping.indices
                let start = stopMapping[0], end = stopMapping[stopMapping.count - 1]
                if let company = nonempty(train.company) {
                    let names = company.components(separatedBy: CharacterSet(charactersIn: "/／"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    switch operatorConstraint(names, trip: trip, from: calls[start].sequence, to: calls[end].sequence) {
                    case .no: continue
                    case .unknown: missingProof = true; continue
                    case .yes: break
                    }
                }
                guard !mapping.unknown, serviceAgreement != .unknown,
                      trip.timetableCompleteness != .conflict, trip.canApplyToRouteEditor,
                      completePhysicalChain(trip), !trip.id.isEmpty,
                      !trip.timetableVersionID.isEmpty, !trip.calendarID.isEmpty else {
                    missingProof = true; continue
                }
                let boundaries = [routeSections[0].fromN02StationCode!] + routeSections.map { $0.toN02StationCode! }
                func mapBoundaries(_ index: Int, path: [Int]) {
                    guard budget > 0, matches.count < 2 else { return }
                    if index == boundaries.count {
                        guard path.last == end, stopMapping.allSatisfy(path.contains) else { return }
                        var output: [Section] = []
                        for sectionIndex in routeSections.indices {
                            let a = path[sectionIndex], b = path[sectionIndex + 1]
                            let physical = Array(trip.physicalRouteSections[a..<b])
                            switch sectionConstraints(routeSections[sectionIndex], physical: physical,
                                                      trip: trip, from: calls[a], to: calls[b]) {
                            case .no: return
                            case .unknown: missingProof = true; return
                            case .yes: break
                            }
                            output.append(Section(originalIndex: sectionIndex, originalSection: routeSections[sectionIndex],
                                fromPassengerCallIndex: a, toPassengerCallIndex: b,
                                sectionCodes: physical.flatMap { $0.sectionCodes ?? [] },
                                lineIDs: orderedUnique(physical.flatMap { $0.lineIDs ?? [] })))
                        }
                        matches.append(Match(provenance: Provenance(tripID: trip.id, serviceDate: trip.serviceDate,
                            timetableVersionID: trip.timetableVersionID, calendarID: trip.calendarID),
                            passengerCallIndices: stopMapping, sections: output))
                        return
                    }
                    let after = path.last ?? (start - 1)
                    guard after + 1 <= end else { return }
                    for callIndex in (after + 1)...end {
                        budget -= 1
                        guard budget > 0 else { return }
                        if index == 0, callIndex != start { continue }
                        if index == boundaries.count - 1, callIndex != end { continue }
                        guard calls[callIndex].station.currentSourceCode == boundaries[index] else { continue }
                        mapBoundaries(index + 1, path: path + [callIndex])
                    }
                }
                let previousCount = matches.count
                mapBoundaries(0, path: [])
                // A canonical boundary cannot be sliced through an interval by
                // name, nearest geometry, or an unrecorded station identity.
                if matches.count == previousCount,
                   boundaries.contains(where: { code in !calls[start...end].contains { $0.station.currentSourceCode == code } }) {
                    missingProof = true
                }
                if budget <= 0 { return .unsupported }
                if matches.count > 1 { return .ambiguous }
            }
        }
        if missingProof { return .unsupported }
        return matches.first.map(Outcome.matched) ?? .unavailable
    }

    private enum Agreement: Equatable { case yes, no, unknown }

    private static func completePhysicalChain(_ trip: TrainTimetableDatabase.Trip) -> Bool {
        let calls = trip.passengerStops
        guard calls.count >= 2, trip.physicalRouteSections.count == calls.count - 1,
              zip(trip.stops, trip.stops.dropFirst()).allSatisfy({ $0.0.sequence < $0.1.sequence }),
              trip.stops.allSatisfy({ stop in
                  (stop.arrivalSeconds.map { $0 / 86_400 == stop.arrivalDayOffset } ?? true)
                      && (stop.departureSeconds.map { $0 / 86_400 == stop.departureDayOffset } ?? true)
              }) else { return false }
        return trip.physicalRouteSections.enumerated().allSatisfy { index, section in
            section.fromN02StationCode == calls[index].station.currentSourceCode
                && section.toN02StationCode == calls[index + 1].station.currentSourceCode
                && section.sectionCodes?.isEmpty == false && section.lineIDs?.isEmpty == false
                && section.sectionCodes!.allSatisfy { nonempty($0) != nil }
                && section.lineIDs!.allSatisfy { nonempty($0) != nil }
        }
    }

    private static func serviceConstraints(_ train: Train, trip: TrainTimetableDatabase.Trip) -> Agreement {
        var unknown = false
        for input in [train.number, train.numberEn].compactMap({ $0 }).filter({ nonempty($0) != nil }) {
            if !matchesService(input, trip: trip) { return .no }
        }
        if let direction = nonempty(train.direction), direction != "unknown" {
            if let published = nonempty(trip.direction) {
                if folded(direction) != folded(published) { return .no }
            } else { unknown = true }
        }
        if let type = nonempty(train.trainType) {
            let aliases = trip.serviceClass == "limited_express" ? ["limited_express", "特急"]
                : trip.serviceClass == "sleeper_limited_express" ? ["sleeper_limited_express", "寝台特急"]
                : [trip.serviceClass]
            if !aliases.map(folded).contains(folded(type)) { return .no }
        }
        // Institution classification belongs to the physical network, not the
        // timetable. The caller must verify such a policy there before drawing.
        return unknown ? .unknown : .yes
    }

    private static func sectionConstraints(_ section: RouteSection, physical: [RouteSection],
        trip: TrainTimetableDatabase.Trip, from: TrainTimetableDatabase.StopTime,
        to: TrainTimetableDatabase.StopTime) -> Agreement {
        for input in [section.name, section.number].compactMap({ nonempty($0) }) {
            if !matchesService(input, trip: trip) { return .no }
        }
        if let explicit = section.sectionCodes, !explicit.isEmpty,
           explicit != physical.flatMap({ $0.sectionCodes ?? [] }) { return .no }
        if let ids = section.lineIDs, !ids.isEmpty {
            let facts = physical.flatMap { $0.lineIDs ?? [] }
            guard !facts.isEmpty else { return .unknown }
            if !Set(facts).isSubset(of: Set(ids)) { return .no }
        }
        if let names = section.lineNames, !names.isEmpty {
            let facts = physical.flatMap { $0.lineNames ?? [] }
            guard !facts.isEmpty else { return .unknown }
            if !Set(facts.map(folded)).isSubset(of: Set(names.map(folded))) { return .no }
        }
        if let operators = section.operatorNames, !operators.isEmpty {
            return operatorConstraint(operators, trip: trip, from: from.sequence, to: to.sequence)
        }
        return .yes
    }

    private static func operatorConstraint(_ inputs: [String], trip: TrainTimetableDatabase.Trip,
                                           from: Int, to: Int) -> Agreement {
        let allowed = inputs.compactMap(OperatorIdentity.code(for:))
        guard allowed.count == inputs.count else { return .unknown }
        let segments = trip.operatorSegments.filter { $0.fromSequence < to && $0.toSequence > from }
        guard !segments.isEmpty else { return .unknown }
        let actual = segments.map { OperatorIdentity.code(for: $0.displayName) ?? "jp." + $0.operatorID }
        return Set(actual).isSubset(of: Set(allowed)) ? .yes : .no
    }

    private static func matchesService(_ input: String, trip: TrainTimetableDatabase.Trip) -> Bool {
        let names = [trip.service.canonicalName, trip.service.englishName, trip.service.matchingName]
            .compactMap { nonempty($0) }
        let numbers = [trip.trainNumber, trip.publicNumber].compactMap { nonempty($0) }
        var labels: [String] = names + numbers
        for name in names {
            for number in numbers {
                labels.append(name + " " + number)
                labels.append(name + number + "号")
                labels.append(name + " " + number + "号")
            }
        }
        return labels.map(folded).contains(folded(input))
    }

    private struct RecordedTime { let arrival: Int?; let departure: Int? }

    /// Strict parsing here is intentional: the archive's permissive JavaScript
    /// parser accepts trailing text, which cannot establish an exact clock fact.
    private static func recordedTimes(_ stops: [Stop]) -> [RecordedTime]? {
        var previous: Int?
        func seconds(_ raw: String?) -> Int?? {
            guard let raw else { return .some(nil) }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let offsetParts = text.components(separatedBy: "+")
            guard offsetParts.count <= 2 else { return nil }
            let clock = offsetParts[0].trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
            guard clock.count == 2, (1...2).contains(clock[0].count), clock[1].count == 2,
                  clock.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
                  let hour = Int(clock[0]), let minute = Int(clock[1]), minute < 60, hour < 72 else { return nil }
            var offset = 0
            if offsetParts.count == 2 {
                let value = offsetParts[1].trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
                      let parsed = Int(value), (0...2).contains(parsed) else { return nil }
                offset = parsed
            }
            var value = (hour * 60 + minute + offset * 1_440) * 60
            if hour < 24, offsetParts.count == 1, let previous {
                while value < previous { value += 86_400 }
            }
            guard value < 72 * 3_600, previous.map({ value >= $0 }) ?? true else { return nil }
            previous = value
            return .some(value)
        }
        var result: [RecordedTime] = []
        for stop in stops {
            guard let arrival = seconds(stop.arrival), let departure = seconds(stop.departure) else { return nil }
            result.append(RecordedTime(arrival: arrival, departure: departure))
        }
        return result
    }

    private static func gregorianDate(_ text: String) -> Date? {
        let parts = text.components(separatedBy: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        return check.year == year && check.month == month && check.day == day ? date : nil
    }

    private static func dayDifference(from source: String, to target: String) -> Int? {
        guard let sourceDate = gregorianDate(source), let targetDate = gregorianDate(target) else { return nil }
        return Int(targetDate.timeIntervalSince(sourceDate) / 86_400)
    }

    private static func platformNumber(_ text: String) -> Int? {
        Int(text.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "()")))
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func folded(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    /// Exactly the train and section fields `resolve` reads. Record identity,
    /// stop names, observed clocks (`actualArrival` / `actualDeparture`), and
    /// `rideSegment` are unread, so changing them does not change the match.
    /// `routeConfirmation` is stored because `.pending` refuses the match.
    /// The flag is not itself a result.
    public struct MatchRequestIdentity: Hashable, Sendable {
        private struct StopFact: Hashable, Sendable {
            let code: String?
            let stopType: String
            let arrival: String?
            let departure: String?
            let platformNumber: Int?
        }

        private struct SectionFact: Hashable, Sendable {
            let fromCode: String?
            let toCode: String?
            let name: String?
            let number: String?
            let sectionCodes: [String]?
            let lineIDs: [String]?
            let lineNames: [String]?
            let operatorNames: [String]?
        }

        private let region: String?
        private let rideDate: String?
        private let number: String
        private let numberEn: String?
        private let direction: String?
        private let trainType: String?
        private let company: String?
        private let vehicleType: String?
        /// Pending confirmation changes the matcher's refusal. The raw value is
        /// not proof; `.confirmed` never satisfies `reusableAppliedMatch`.
        private let routeConfirmation: String?
        private let stops: [StopFact]
        private let sections: [SectionFact]

        public init(train: Train, sections: [RouteSection]) {
            region = train.region
            rideDate = train.date
            number = train.number
            numberEn = train.numberEn
            direction = train.direction
            trainType = train.trainType
            company = train.company
            vehicleType = train.vehicleType
            routeConfirmation = train.routeConfirmation?.rawValue
            stops = train.stops.map {
                StopFact(code: $0.n02StationCode, stopType: $0.stopType,
                         arrival: $0.arrival, departure: $0.departure,
                         platformNumber: $0.platformNumber)
            }
            self.sections = sections.map {
                SectionFact(fromCode: $0.fromN02StationCode, toCode: $0.toN02StationCode,
                            name: $0.name, number: $0.number,
                            sectionCodes: $0.sectionCodes, lineIDs: $0.lineIDs,
                            lineNames: $0.lineNames, operatorNames: $0.operatorNames)
            }
        }
    }

    /// Editor-applied occurrence evidence. Not `Codable`: an imported JSON
    /// confirmation flag cannot be decoded into this value.
    public struct AppliedOccurrenceBinding: Equatable, Sendable {
        public let identity: MatchRequestIdentity
        public let serviceDate: String
        public let timetableVersionID: String
        public let calendarID: String
        public let railRevision: String
        public let timetableRevision: String
    }

    public struct AppliedOccurrenceEvidence: Equatable, Sendable {
        public let match: Match
        public let binding: AppliedOccurrenceBinding
    }

    /// Binds one applied occurrence to the train that was kept and to the rail
    /// and timetable revisions used to read it. Returns nil unless provenance
    /// is verified and the kept stops and sections are that occurrence's
    /// passenger calls. `routeConfirmation` is not consulted.
    public static func appliedEvidence(
        trip: TrainTimetableDatabase.Trip,
        train: Train,
        sections: [RouteSection],
        railRevision: String?,
        timetableRevision: String?
    ) -> AppliedOccurrenceEvidence? {
        guard let railRevision, !railRevision.isEmpty,
              let timetableRevision, !timetableRevision.isEmpty,
              !trip.id.isEmpty, !trip.serviceDate.isEmpty,
              !trip.timetableVersionID.isEmpty, !trip.calendarID.isEmpty,
              trip.timetableCompleteness != .conflict,
              trip.factCompleteness["provenance"] == .verified
        else { return nil }
        if let date = train.date, date != trip.serviceDate { return nil }
        let calls = trip.passengerStops
        guard calls.count >= 2, train.stops.count == calls.count,
              zip(train.stops, calls).allSatisfy({
                  $0.n02StationCode == $1.station.currentSourceCode
              }),
              sections.count == trip.physicalRouteSections.count,
              zip(sections, trip.physicalRouteSections).allSatisfy({
                  $0.fromN02StationCode == $1.fromN02StationCode
                      && $0.toN02StationCode == $1.toN02StationCode
              }),
              trip.physicalRouteSections.allSatisfy({ $0.sectionCodes?.isEmpty == false })
        else { return nil }
        var matchedSections: [Section] = []
        matchedSections.reserveCapacity(trip.physicalRouteSections.count)
        for (index, physical) in trip.physicalRouteSections.enumerated() {
            guard let codes = physical.sectionCodes, !codes.isEmpty else { return nil }
            matchedSections.append(Section(
                originalIndex: index, originalSection: sections[index],
                fromPassengerCallIndex: index, toPassengerCallIndex: index + 1,
                sectionCodes: codes, lineIDs: physical.lineIDs ?? []))
        }
        let match = Match(
            provenance: Provenance(
                tripID: trip.id, serviceDate: trip.serviceDate,
                timetableVersionID: trip.timetableVersionID, calendarID: trip.calendarID),
            passengerCallIndices: Array(calls.indices), sections: matchedSections)
        let binding = AppliedOccurrenceBinding(
            identity: MatchRequestIdentity(train: train, sections: sections),
            serviceDate: trip.serviceDate, timetableVersionID: trip.timetableVersionID,
            calendarID: trip.calendarID, railRevision: railRevision,
            timetableRevision: timetableRevision)
        return AppliedOccurrenceEvidence(match: match, binding: binding)
    }

    /// Returns the bound match only when the train, sections, provenance, and
    /// both revisions are still the ones that produced it. A nil binding is
    /// never treated as proof, including when `routeConfirmation` is `.confirmed`.
    public static func reusableAppliedMatch(
        _ evidence: AppliedOccurrenceEvidence?,
        train: Train,
        sections: [RouteSection],
        railRevision: String?,
        timetableRevision: String?
    ) -> Match? {
        guard let evidence,
              let railRevision, !railRevision.isEmpty,
              let timetableRevision, !timetableRevision.isEmpty,
              evidence.binding.railRevision == railRevision,
              evidence.binding.timetableRevision == timetableRevision,
              !evidence.match.provenance.tripID.isEmpty,
              evidence.match.provenance.serviceDate == evidence.binding.serviceDate,
              evidence.match.provenance.timetableVersionID == evidence.binding.timetableVersionID,
              evidence.match.provenance.calendarID == evidence.binding.calendarID,
              MatchRequestIdentity(train: train, sections: sections) == evidence.binding.identity
        else { return nil }
        return evidence.match
    }
}
