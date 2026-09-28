import Foundation
import SQLite3

/// A lazy, read-only view of the generated historical timetable artifact.
///
/// The database keeps trip templates, calendars, and exceptions normalized.
/// Queries materialize only the requested service day; the whole historical
/// catalog is never decoded or retained in memory.
public final class TrainTimetableDatabase: @unchecked Sendable {
    public enum DatabaseError: Error, LocalizedError, Sendable {
        case cannotOpen(String)
        case incompatibleSchema(missingTables: [String])
        case invalidArtifact(String)
        case queryFailed(String)
        case invalidServiceDate(String)

        public var errorDescription: String? {
            switch self {
            case .cannotOpen(let message): "Could not open timetable database: \(message)"
            case .incompatibleSchema(let tables):
                "Timetable database is missing required tables: \(tables.joined(separator: ", "))"
            case .invalidArtifact(let message): "Invalid timetable database artifact: \(message)"
            case .queryFailed(let message): "Timetable query failed: \(message)"
            case .invalidServiceDate(let date): "Invalid Gregorian service date: \(date)"
            }
        }
    }

    public enum Coverage: String, Sendable, Hashable, Codable {
        case verified
        case partial
        case unknown
        case conflict
        case notApplicable = "not_applicable"

        init(databaseValue: String?) {
            self = databaseValue.flatMap(Self.init(rawValue:)) ?? .unknown
        }
    }

    public struct QueryCoverage: Sendable, Hashable {
        /// Scope-wide research coverage, not merely the completeness label of
        /// whichever timetable versions happened to match the date.
        public let status: Coverage
        public let timetableVersionIDs: [String]

        public init(status: Coverage, timetableVersionIDs: [String]) {
            self.status = status
            self.timetableVersionIDs = timetableVersionIDs
        }
    }

    public struct SourceDocument: Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        public let publisher: String
        public let urlOrLocator: String
        public let licenseStatus: String
    }

    public struct Service: Sendable, Hashable, Identifiable {
        public let id: String
        public let canonicalName: String
        public let serviceClass: String
        public let historicalGeneration: Int
        public let firstVerifiedDate: String?
        public let lastVerifiedDate: String?
        public let jrScope: String
        public let matchingName: String?

        public var isJRService: Bool { jrScope != "private" }
    }

    public struct StationIdentity: Sendable, Hashable, Identifiable {
        public enum ReferenceKind: String, Sendable, Hashable, Codable {
            case currentN02 = "current_n02"
            case historicalOverlay = "historical_overlay"
        }

        public let id: String
        public let name: String
        public let referenceKind: ReferenceKind
        public let currentSourceCode: String?
        public let railHistoryID: String?
        public let validFrom: String?
        public let validUntil: String?

        public var stationKey: StationKey? {
            guard referenceKind == .currentN02, let currentSourceCode else { return nil }
            return StationKey(regionCode: "jp", sourceCode: currentSourceCode)
        }

        public func isValid(on serviceDate: String) -> Bool {
            TimetableServiceDayContext(serviceDate: serviceDate)
                .contains(validFrom: validFrom, validUntil: validUntil)
        }
    }

    public struct StopTime: Sendable, Hashable, Identifiable {
        public var id: Int { sequence }
        public let sequence: Int
        public let station: StationIdentity
        public let arrivalTime: String?
        public let departureTime: String?
        /// Total seconds from the start of the trip's Japanese service day.
        public let arrivalSeconds: Int?
        public let departureSeconds: Int?
        /// Legacy shared fallback. A dwell across midnight uses separate offsets.
        public let dayOffset: Int
        public let arrivalDayOffset: Int
        public let departureDayOffset: Int
        public let callType: String
        public let pickupAllowed: Bool
        public let dropoffAllowed: Bool
        public let platform: String?
        public let timeAccuracy: String?

        public var isPassengerCall: Bool {
            callType == "origin" || callType == "passenger_stop" || callType == "destination"
        }
    }

    public struct LineSegment: Sendable, Hashable, Identifiable {
        public enum ReferenceKind: String, Sendable, Hashable, Codable {
            case currentN02 = "current_n02"
            case historicalOverlay = "historical_overlay"
        }

        public var id: Int { sequence }
        public let sequence: Int
        public let fromStationID: String
        public let toStationID: String
        public let lineName: String
        public let operatorID: String?
        public let confidence: String?
        public let referenceKind: ReferenceKind?
        public let currentN02LineID: String?
        public let railHistoryID: String?

        /// Historical overlay identities cannot yet be represented by the
        /// editor's RouteSection model. An explicit current-network identity
        /// is therefore required; all-null and unknown references are research
        /// records and stay read-only.
        fileprivate var canApplyToCurrentEditor: Bool {
            return referenceKind == .currentN02
                && currentN02LineID?.isEmpty == false
                && railHistoryID == nil
        }
    }

    public struct OperatorSegment: Sendable, Hashable, Identifiable {
        public var id: String { "\(fromSequence):\(toSequence):\(operatorID)" }
        public let fromSequence: Int
        public let toSequence: Int
        public let operatorID: String
        public let displayName: String
    }

    public struct Trip: Sendable, Hashable, Identifiable {
        private static let currentJRPassengerOperatorIDs: Set<String> = [
            "jr-hokkaido", "jr-east", "jr-central", "jr-west", "jr-shikoku", "jr-kyushu",
        ]

        public let id: String
        public let serviceDate: String
        public let timetableVersionID: String
        public let service: Service
        public let calendarID: String
        public let trainNumber: String
        public let publicNumber: String?
        public let direction: String?
        public let serviceClass: String
        public let operationGroupID: String?
        public let notes: String?
        public let timetableCompleteness: Coverage
        /// Per-trip verification state from `fact_completeness`, keyed by
        /// canonical dimension (`stops`, `route_lines`, `station_refs`, …).
        public let factCompleteness: [String: Coverage]
        public let stops: [StopTime]
        public let lineSegments: [LineSegment]
        public let operatorSegments: [OperatorSegment]

        public var origin: StopTime? { stops.first(where: \.isPassengerCall) }
        public var destination: StopTime? { stops.last(where: \.isPassengerCall) }
        public var passengerStops: [StopTime] { stops.filter(\.isPassengerCall) }
        public var displayName: String { service.canonicalName }

        /// Exact trips can enter the legacy editor only when every passenger
        /// stop maps to the current station directory. Historical-only station
        /// identities remain queryable, but are not silently replaced by a
        /// same-name modern station.
        public var canApplyToCurrentStationDirectory: Bool {
            passengerStops.count >= 2 && passengerStops.allSatisfy { $0.station.stationKey != nil }
        }

        /// Applying an exact trip is allowed only when the facts needed by
        /// the route editor are independently verified. A partially researched
        /// trip remains visible to database clients but cannot create a route.
        public var canApplyToRouteEditor: Bool {
            let required = [
                "identity", "train_number", "operator", "validity_calendar",
                "origin_destination", "stops", "times", "route_lines", "station_refs", "provenance",
            ]
            return canApplyToCurrentStationDirectory
                && passengerStops.allSatisfy { $0.station.isValid(on: serviceDate) }
                && hasValidChronology
                && hasCompleteLineCoverage
                && hasCompleteOperatorCoverage
                && exactRouteSections != nil
                && required.allSatisfy { factCompleteness[$0] == .verified }
        }

        private var hasValidChronology: Bool {
            var previous = -1
            for stop in stops {
                let values = [stop.arrivalSeconds, stop.departureSeconds].compactMap { $0 }
                guard values.allSatisfy({ (0..<(72 * 60 * 60)).contains($0) }) else { return false }
                for value in values {
                    guard value >= previous else { return false }
                    previous = value
                }
            }
            return true
        }

        private var hasCompleteOperatorCoverage: Bool {
            guard let first = stops.first?.sequence, let last = stops.last?.sequence,
                  let initial = operatorSegments.first,
                  initial.fromSequence <= first, initial.toSequence >= first
            else { return false }
            var coveredThrough = initial.toSequence
            guard coveredThrough >= initial.fromSequence else { return false }
            for segment in operatorSegments.dropFirst() {
                guard segment.fromSequence <= coveredThrough + 1,
                      segment.toSequence >= segment.fromSequence
                else { return false }
                coveredThrough = max(coveredThrough, segment.toSequence)
            }
            return coveredThrough >= last
        }

        private var hasCompleteLineCoverage: Bool {
            guard let originID = origin?.station.id, let destinationID = destination?.station.id,
                  let first = lineSegments.first, let last = lineSegments.last,
                  first.fromStationID == originID, last.toStationID == destinationID
            else { return false }
            guard zip(lineSegments, lineSegments.dropFirst()).allSatisfy({ pair in
                pair.0.toStationID == pair.1.fromStationID
                    && pair.0.sequence < pair.1.sequence
            }) else { return false }
            let operators = Set(operatorSegments.map(\.operatorID))
            return lineSegments.allSatisfy { segment in
                segment.confidence == "high"
                    && segment.operatorID.map(operators.contains) == true
            }
        }

        /// Hard route constraints for every adjacent passenger-stop pair.
        /// A globally complete origin-to-destination chain is insufficient:
        /// each passenger boundary must occur in order in that chain, or the
        /// verified facts cannot be attached to the editor's route sections.
        private var exactRouteSections: [RouteSection]? {
            let calls = passengerStops
            guard calls.count >= 2, !lineSegments.isEmpty else { return nil }
            let chainStationIDs = [lineSegments[0].fromStationID]
                + lineSegments.map(\.toStationID)
            guard calls.allSatisfy({ call in
                chainStationIDs.lazy.filter { $0 == call.station.id }.count == 1
            }) else { return nil }
            let operatorNames = Dictionary(
                operatorSegments.map { ($0.operatorID, $0.displayName) },
                uniquingKeysWith: { first, _ in first })
            var cursor = lineSegments.startIndex
            var sections: [RouteSection] = []
            sections.reserveCapacity(calls.count - 1)

            for index in 0..<(calls.count - 1) {
                let from = calls[index]
                let to = calls[index + 1]
                guard lineSegments.indices.contains(cursor),
                      lineSegments[cursor].fromStationID == from.station.id
                else { return nil }

                var covered: [LineSegment] = []
                var reachedBoundary = false
                while lineSegments.indices.contains(cursor) {
                    let segment = lineSegments[cursor]
                    if let previous = covered.last,
                       previous.toStationID != segment.fromStationID
                    { return nil }
                    covered.append(segment)
                    cursor += 1
                    if segment.toStationID == to.station.id {
                        reachedBoundary = true
                        break
                    }
                }
                guard reachedBoundary,
                      // RouteSection expresses allowed line/operator sets, not
                      // an ordered chain of intermediate waypoints. More than
                      // one source segment would lose verified traversal facts.
                      covered.count == 1,
                      covered.allSatisfy({ $0.confidence == "high" }),
                      let fromCode = from.station.currentSourceCode,
                      let toCode = to.station.currentSourceCode
                else { return nil }

                let segment = covered[0]
                guard !segment.lineName.isEmpty,
                      segment.canApplyToCurrentEditor,
                      let operatorID = segment.operatorID,
                      let operatorName = operatorNames[operatorID],
                      !operatorName.isEmpty,
                      operatorSegments.contains(where: {
                          $0.operatorID == operatorID
                              && $0.fromSequence <= from.sequence
                              && $0.toSequence >= to.sequence
                      })
                else { return nil }
                sections.append(RouteSection(
                    from: from.station.name, to: to.station.name,
                    fromN02StationCode: fromCode, toN02StationCode: toCode,
                    lineNames: [segment.lineName], operatorNames: [operatorName]))
            }
            guard cursor == lineSegments.endIndex else { return nil }
            return sections
        }

        /// A one-day compatibility projection for the existing route editor.
        /// It contains this trip's exact passenger calls and explicit line
        /// segments; it never invents optional stops or a fallback route.
        public func compatibilityPattern() -> TrainServicePatterns.Pattern? {
            guard canApplyToRouteEditor,
                  let validUntil = Self.nextGregorianDay(after: serviceDate)
            else { return nil }

            let refs = passengerStops.compactMap { stop -> TrainServicePatterns.Pattern.StationRef? in
                guard let code = stop.station.currentSourceCode else { return nil }
                return .init(name: stop.station.name, sourceCode: code)
            }
            let operators = operatorSegments.map(\.displayName).uniqued()
            let company = operators.isEmpty ? "" : operators.joined(separator: "/")
            let level: TrainServicePatterns.Pattern.Level = .complete
            let exactNumber = publicNumber ?? trainNumber
            let exactName = [service.canonicalName, exactNumber]
                .filter { !$0.isEmpty }.joined(separator: " ")
            return .init(
                id: "timetable:\(id):\(serviceDate)",
                serviceId: service.id,
                name: exactName,
                company: company,
                label: exactName,
                origin: refs.first?.name ?? "",
                destination: refs.last?.name ?? "",
                stopRefs: refs,
                optionalStopRefs: [],
                via: [],
                confidence: nil,
                source: nil,
                lines: lineSegments.map(\.lineName),
                validFrom: serviceDate,
                validUntil: validUntil,
                completeness: .init(
                    stops: level,
                    lines: level,
                    validity: level),
                notes: notes)
        }

        /// Applies this exact occurrence to an editor draft, preserving its
        /// published times and route facts. Callers must respect
        /// ``canApplyToRouteEditor``; incomplete research records fail closed.
        public func applying(to train: Train, ridden: Bool = true) -> Train? {
            guard canApplyToRouteEditor, let origin, let destination,
                  let routeSections = exactRouteSections
            else { return nil }
            var result = train
            result.date = TimetableServiceDayContext(serviceDate: serviceDate).networkRideDate
            result.number = [service.canonicalName, publicNumber ?? trainNumber]
                .filter { !$0.isEmpty }.joined(separator: " ")
            result.trainType = serviceClass == "sleeper_limited_express" ? "寝台特急" : "特急"
            let operatorNames = operatorSegments.map(\.displayName).uniqued()
            result.company = operatorNames.joined(separator: "/")
            result.origin = origin.station.name
            result.destination = destination.station.name
            result.direction = direction
            result.routeSections = routeSections
            result.routePolicy = RoutePolicy(
                mode: "single_primary_route",
                jrOnly: !operatorSegments.isEmpty && operatorSegments.allSatisfy {
                    Self.currentJRPassengerOperatorIDs.contains($0.operatorID)
                },
                allowAlternatives: false,
                allowBrowserStraightLineFallback: false,
                allowedInstitutionTypeCodes: nil,
                preferredLineNames: lineSegments.map(\.lineName),
                preferredOperatorNames: operatorNames,
                institutionFilterMode: "soft")
            result.stops = passengerStops.enumerated().map { index, stop in
                let type: String
                if index == 0 { type = "origin" }
                else if index == passengerStops.count - 1 { type = "destination" }
                else { type = "passenger_stop" }
                return Stop(
                    name: stop.station.name,
                    n02StationCode: stop.station.currentSourceCode,
                    platformNumber: stop.platform.flatMap(Int.init),
                    arrival: Self.editorTime(seconds: stop.arrivalSeconds, source: stop.arrivalTime),
                    departure: Self.editorTime(seconds: stop.departureSeconds, source: stop.departureTime),
                    stopType: type,
                    rideSegment: ridden)
            }
            if result.region == nil { result.region = "jp" }
            return result
        }

        private static func editorTime(seconds: Int?, source: String?) -> String? {
            guard let seconds else { return source }
            let hour = seconds / 3600
            let minute = seconds % 3600 / 60
            let second = seconds % 60
            if second != 0 || source?.split(separator: ":").count == 3 {
                return String(format: "%02d:%02d:%02d", hour, minute, second)
            }
            return String(format: "%02d:%02d", hour, minute)
        }

        private static func nextGregorianDay(after day: String) -> String? {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            guard let date = formatter.date(from: day),
                  let next = calendar.date(byAdding: .day, value: 1, to: date)
            else { return nil }
            return formatter.string(from: next)
        }
    }

    public struct ServiceCalendar: Sendable, Hashable, Identifiable {
        public let id: String
        public let weekdays: [Bool]
        public let validFrom: String
        public let validUntil: String?
        public let holidayPolicy: String
    }

    public struct Query: Sendable, Hashable {
        public let serviceDate: String
        public var serviceID: String?
        public var serviceName: String?
        public var tripID: String?

        public init(
            serviceDate: String, serviceID: String? = nil,
            serviceName: String? = nil, tripID: String? = nil
        ) {
            self.serviceDate = serviceDate
            self.serviceID = serviceID
            self.serviceName = serviceName
            self.tripID = tripID
        }
    }

    private let connection: OpaquePointer
    private let lock = NSLock()

    public init(url: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw DatabaseError.cannotOpen(message)
        }
        do {
            try Self.validateArtifactIdentity(in: database)
        } catch {
            sqlite3_close(database)
            throw error
        }
        let required = [
            "source_documents", "operators", "services", "service_name_periods",
            "timetable_versions", "timetable_version_sources", "trips",
            "calendars", "calendar_exceptions", "station_identities", "stop_times",
            "trip_stop_time_overrides", "trip_operator_segments", "trip_line_segments",
            "fact_sources", "fact_completeness", "holiday_dates", "holiday_calendar_years",
            "coverage_declarations", "metadata", "verified_zero_service_intervals",
        ]
        let present: Set<String>
        do {
            present = try Self.tableNames(in: database)
        } catch {
            sqlite3_close(database)
            throw error
        }
        let missing = required.filter { !present.contains($0) }
        guard missing.isEmpty else {
            sqlite3_close(database)
            throw DatabaseError.incompatibleSchema(missingTables: missing)
        }
        do {
            try Self.validateEssentialColumns(in: database)
        } catch {
            sqlite3_close(database)
            throw error
        }
        connection = database
    }

    deinit { sqlite3_close(connection) }

    /// Opens the generated package resource when present. A missing or
    /// incompatible artifact returns `nil`, allowing the app to retain the
    /// legacy pattern catalog while the historical database is being built.
    public static func bundled() -> TrainTimetableDatabase? {
        guard let url = Bundle.module.url(
            forResource: "train-service-timetable", withExtension: "sqlite")
        else { return nil }
        return try? TrainTimetableDatabase(url: url)
    }

    public func trips(on serviceDate: String) throws -> [Trip] {
        try trips(matching: Query(serviceDate: serviceDate))
    }

    public func trips(for serviceID: String, on serviceDate: String) throws -> [Trip] {
        try trips(matching: Query(serviceDate: serviceDate, serviceID: serviceID))
    }

    public func trip(id: String, on serviceDate: String) throws -> Trip? {
        try trips(matching: Query(serviceDate: serviceDate, tripID: id)).first
    }

    /// Source registry records supporting this trip's timetable edition or
    /// its trip-level facts. The registry metadata is returned verbatim; the
    /// runtime does not infer a publisher, locator, or license.
    public func sources(for trip: Trip) throws -> [SourceDocument] {
        try withLock {
            try rows("""
                SELECT sd.source_id, sd.title, sd.publisher,
                       sd.url_or_locator, sd.license_status
                FROM source_documents sd
                JOIN (
                    SELECT source_id
                    FROM timetable_version_sources
                    WHERE timetable_version_id = ?1
                    UNION
                    SELECT source_id
                    FROM fact_sources
                    WHERE entity_type = 'trip' AND entity_id = ?2
                ) refs ON refs.source_id = sd.source_id
                ORDER BY sd.source_id
                """, bindings: [trip.timetableVersionID, trip.id]).map { row in
                    SourceDocument(
                        id: row.string(0), title: row.string(1), publisher: row.string(2),
                        urlOrLocator: row.string(3), licenseStatus: row.string(4))
                }
        }
    }

    public func trips(named name: String, on serviceDate: String) throws -> [Trip] {
        try trips(matching: Query(serviceDate: serviceDate, serviceName: name))
    }

    public func service(named name: String, on serviceDate: String? = nil) throws -> [Service] {
        try withLock {
            if let serviceDate { try Self.validate(serviceDate: serviceDate) }
            let datedJoin = serviceDate == nil ? "" : """
                 AND snp.valid_from <= ?2
                 AND (snp.valid_until IS NULL OR ?2 < snp.valid_until)
                """
            let sql = """
                SELECT s.service_id, s.canonical_name, s.service_class,
                       s.historical_generation, s.first_verified_date,
                       s.last_verified_date, s.jr_scope, MAX(snp.name)
                FROM services s
                LEFT JOIN service_name_periods snp ON snp.service_id = s.service_id \(datedJoin)
                WHERE (s.canonical_name LIKE ?1 ESCAPE '\\' COLLATE NOCASE
                       OR snp.name LIKE ?1 ESCAPE '\\' COLLATE NOCASE)
                GROUP BY s.service_id, s.canonical_name, s.service_class,
                         s.historical_generation, s.first_verified_date,
                         s.last_verified_date, s.jr_scope
                ORDER BY s.canonical_name, s.service_id
                """
            var bindings = ["%\(Self.escapedLike(name))%"]
            if let serviceDate {
                bindings.append(serviceDate)
            }
            return try rows(sql, bindings: bindings).map(Self.decodeService)
        }
    }

    public func calendar(id: String) throws -> ServiceCalendar? {
        try withLock {
            try rows("""
                SELECT calendar_id, monday, tuesday, wednesday, thursday,
                       friday, saturday, sunday, valid_from, valid_until, holiday_policy
                FROM calendars WHERE calendar_id = ?1
                """, bindings: [id]).first.map { row in
                    ServiceCalendar(
                        id: row.string(0),
                        weekdays: (1...7).map { row.int($0) != 0 },
                        validFrom: row.string(8),
                        validUntil: row.optionalString(9),
                        holidayPolicy: row.string(10))
                }
        }
    }

    public func coverage(on serviceDate: String) throws -> QueryCoverage {
        try Self.validate(serviceDate: serviceDate)
        return try withLock {
            let result = try rows("""
                SELECT timetable_version_id, completeness
                FROM timetable_versions
                WHERE effective_from <= ?1
                  AND (effective_until IS NULL OR ?1 < effective_until)
                ORDER BY timetable_version_id
                """, bindings: [serviceDate])
            let versions = result.map { $0.string(0) }
            let versionStatuses = result.map { Coverage(databaseValue: $0.optionalString(1)) }
            let status: Coverage
            if versionStatuses.contains(.conflict) {
                status = .conflict
            } else if try hasScopeWideVerifiedCoverage(on: serviceDate)
                        || (versions.isEmpty && (try hasNationalVerifiedZero(on: serviceDate))) {
                status = .verified
            } else if versions.isEmpty {
                status = .unknown
            } else {
                // A verified timetable version proves those records, not that
                // every expected JR operator and train has been inventoried.
                status = .partial
            }
            return QueryCoverage(status: status, timetableVersionIDs: versions)
        }
    }

    public func patterns(for serviceID: String, on serviceDate: String) throws
        -> [TrainServicePatterns.Pattern]
    {
        try trips(for: serviceID, on: serviceDate).compactMap { $0.compatibilityPattern() }
    }

    public func patterns(on serviceDate: String) throws -> [TrainServicePatterns.Pattern] {
        try trips(on: serviceDate).compactMap { $0.compatibilityPattern() }
    }

    public func trips(matching query: Query) throws -> [Trip] {
        try Self.validate(serviceDate: query.serviceDate)
        return try withLock {
            let weekday = try Self.weekdayColumn(for: query.serviceDate)
            var bindings = [query.serviceDate]
            var predicates: [String] = []
            if let serviceID = query.serviceID {
                bindings.append(serviceID)
                predicates.append("t.service_id = ?\(bindings.count)")
            }
            if let tripID = query.tripID {
                bindings.append(tripID)
                predicates.append("t.trip_id = ?\(bindings.count)")
            }
            if let name = query.serviceName {
                bindings.append("%\(Self.escapedLike(name))%")
                let slot = bindings.count
                predicates.append("""
                    (s.canonical_name LIKE ?\(slot) ESCAPE '\\' COLLATE NOCASE OR EXISTS (
                        SELECT 1 FROM service_name_periods snp
                        WHERE snp.service_id = s.service_id
                          AND snp.name LIKE ?\(slot) ESCAPE '\\' COLLATE NOCASE
                          AND snp.valid_from <= ?1
                          AND (snp.valid_until IS NULL OR ?1 < snp.valid_until)))
                    """)
            }
            let extra = predicates.isEmpty ? "" : " AND " + predicates.joined(separator: " AND ")
            try validateHolidayCalendarIfNeeded(
                on: query.serviceDate, extraPredicate: extra, bindings: bindings)
            let baseRows = try rows("""
                SELECT t.trip_id, t.timetable_version_id, t.calendar_id,
                       t.train_number, t.public_number, t.direction, t.service_class,
                       t.operation_group_id, t.notes, tv.completeness,
                       s.service_id, s.canonical_name, s.service_class,
                       s.historical_generation, s.first_verified_date,
                       s.last_verified_date, s.jr_scope
                FROM trips t
                JOIN timetable_versions tv
                  ON tv.timetable_version_id = t.timetable_version_id
                JOIN services s ON s.service_id = t.service_id
                JOIN calendars c ON c.calendar_id = t.calendar_id
                WHERE tv.effective_from <= ?1
                  AND (tv.effective_until IS NULL OR ?1 < tv.effective_until)
                  AND (
                    EXISTS (SELECT 1 FROM calendar_exceptions ce
                            WHERE ce.calendar_id = c.calendar_id
                              AND ce.service_date = ?1 AND ce.exception_type = 'add')
                    OR (c.valid_from <= ?1
                        AND (c.valid_until IS NULL OR ?1 < c.valid_until)
                        AND (CASE
                          WHEN c.holiday_policy = 'treat_as_sunday'
                           AND EXISTS (SELECT 1 FROM holiday_dates hd WHERE hd.service_date = ?1)
                          THEN c.sunday ELSE c.\(weekday) END) = 1 AND NOT EXISTS (
                        SELECT 1 FROM calendar_exceptions ce
                        WHERE ce.calendar_id = c.calendar_id
                          AND ce.service_date = ?1 AND ce.exception_type = 'remove'))
                  )
                  \(extra)
                ORDER BY s.canonical_name, t.train_number, t.trip_id
                """, bindings: bindings)

            guard !baseRows.isEmpty else { return [] }
            let tripIDs = baseRows.map { $0.string(0) }
            let stopsByTrip = try loadStops(tripIDs: tripIDs, serviceDate: query.serviceDate)
            let linesByTrip = try loadLineSegments(
                tripIDs: tripIDs, serviceDate: query.serviceDate)
            let operatorsByTrip = try loadOperatorSegments(
                tripIDs: tripIDs, serviceDate: query.serviceDate)
            let factsByTrip = try loadFactCompleteness(tripIDs: tripIDs)

            return baseRows.map { row in
                let id = row.string(0)
                let service = Service(
                    id: row.string(10), canonicalName: row.string(11),
                    serviceClass: row.string(12), historicalGeneration: row.int(13),
                    firstVerifiedDate: row.optionalString(14), lastVerifiedDate: row.optionalString(15),
                    jrScope: row.string(16), matchingName: nil)
                return Trip(
                    id: id, serviceDate: query.serviceDate,
                    timetableVersionID: row.string(1), service: service,
                    calendarID: row.string(2), trainNumber: row.string(3),
                    publicNumber: row.optionalString(4), direction: row.optionalString(5),
                    serviceClass: row.string(6), operationGroupID: row.optionalString(7),
                    notes: row.optionalString(8),
                    timetableCompleteness: Coverage(databaseValue: row.optionalString(9)),
                    factCompleteness: factsByTrip[id] ?? [:],
                    stops: stopsByTrip[id] ?? [], lineSegments: linesByTrip[id] ?? [],
                    operatorSegments: operatorsByTrip[id] ?? [])
            }
        }
    }

    private func validateHolidayCalendarIfNeeded(
        on serviceDate: String, extraPredicate: String, bindings: [String]
    ) throws {
        let usesHistoricalHolidays = try !rows("""
            SELECT c.calendar_id
            FROM trips t
            JOIN timetable_versions tv ON tv.timetable_version_id = t.timetable_version_id
            JOIN services s ON s.service_id = t.service_id
            JOIN calendars c ON c.calendar_id = t.calendar_id
            WHERE tv.effective_from <= ?1
              AND (tv.effective_until IS NULL OR ?1 < tv.effective_until)
              AND c.holiday_policy = 'treat_as_sunday'
              \(extraPredicate)
            LIMIT 1
            """, bindings: bindings).isEmpty
        guard usesHistoricalHolidays else { return }
        let year = String(serviceDate.prefix(4))
        let verified = try !rows("""
            SELECT year FROM holiday_calendar_years
            WHERE year = ?1 AND status = 'verified' LIMIT 1
            """, bindings: [year]).isEmpty
        guard verified else {
            throw DatabaseError.queryFailed(
                "Holiday-sensitive timetable query requires a verified holiday calendar for \(year)")
        }
    }

    private func hasNationalVerifiedZero(on serviceDate: String) throws -> Bool {
        try !rows("""
            SELECT interval_id FROM verified_zero_service_intervals
            WHERE operator_scope = 'jr-ancestral-national-railways'
              AND valid_from <= ?1 AND ?1 < valid_until
            LIMIT 1
            """, bindings: [serviceDate]).isEmpty
    }

    private func hasScopeWideVerifiedCoverage(on serviceDate: String) throws -> Bool {
        let metadataRows = try rows("""
            SELECT value FROM metadata WHERE key = 'coverage_required_operator_scopes'
            """)
        guard let scopesValue = metadataRows.first?.optionalString(0) else { return false }
        let scopes = scopesValue.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !scopes.isEmpty, let year = Int(serviceDate.prefix(4)) else { return false }
        let requiredDimensions = [
            "inventory", "calendar", "stops", "times", "route_lines", "station_refs", "provenance",
        ]
        for scope in scopes {
            let records = try rows("""
                SELECT dimension, status FROM coverage_declarations
                WHERE operator_scope = ?1 AND year = ?2
                """, bindings: [scope, String(year)])
            let statuses = Dictionary(uniqueKeysWithValues: records.map { ($0.string(0), $0.string(1)) })
            guard requiredDimensions.allSatisfy({
                statuses[$0] == "verified" || statuses[$0] == "verified_no_service"
            }) else { return false }
        }
        return true
    }

    private func loadStops(tripIDs: [String], serviceDate: String) throws -> [String: [StopTime]] {
        var result: [String: [StopTime]] = [:]
        for batch in tripIDs.chunked(maximumCount: 400) {
            let placeholders = batch.indices.map { "?\($0 + 2)" }.joined(separator: ",")
            let records = try rows("""
                SELECT st.trip_id, st.stop_sequence, si.station_id, si.name_snapshot,
                       si.reference_kind, si.current_source_code, si.rail_history_id,
                       si.valid_from, si.valid_until,
                       COALESCE(o.arrival_override, st.arrival_time),
                       COALESCE(o.departure_override, st.departure_time),
                       COALESCE(o.arrival_seconds_override, st.arrival_seconds),
                       COALESCE(o.departure_seconds_override, st.departure_seconds),
                       st.day_offset, st.call_type, st.pickup_allowed,
                       st.dropoff_allowed, st.platform, st.time_accuracy,
                       COALESCE(o.arrival_day_offset_override, st.arrival_day_offset, st.day_offset),
                       COALESCE(o.departure_day_offset_override, st.departure_day_offset, st.day_offset)
                FROM stop_times st
                JOIN station_identities si ON si.station_id = st.station_id
                LEFT JOIN trip_stop_time_overrides o
                  ON o.trip_id = st.trip_id AND o.stop_sequence = st.stop_sequence
                 AND o.service_date = ?1
                WHERE st.trip_id IN (\(placeholders))
                ORDER BY st.trip_id, st.stop_sequence
                """, bindings: [serviceDate] + batch)
            for row in records {
                let tripID = row.string(0)
                let station = StationIdentity(
                    id: row.string(2), name: row.string(3),
                    referenceKind: StationIdentity.ReferenceKind(rawValue: row.string(4))
                        ?? .historicalOverlay,
                    currentSourceCode: row.optionalString(5), railHistoryID: row.optionalString(6),
                    validFrom: row.optionalString(7), validUntil: row.optionalString(8))
                result[tripID, default: []].append(StopTime(
                    sequence: row.int(1), station: station,
                    arrivalTime: row.optionalString(9), departureTime: row.optionalString(10),
                    arrivalSeconds: row.optionalInt(11), departureSeconds: row.optionalInt(12),
                    dayOffset: row.int(13), arrivalDayOffset: row.int(19),
                    departureDayOffset: row.int(20), callType: row.string(14),
                    pickupAllowed: row.int(15) != 0, dropoffAllowed: row.int(16) != 0,
                    platform: row.optionalString(17), timeAccuracy: row.optionalString(18)))
            }
        }
        return result
    }

    private func loadLineSegments(
        tripIDs: [String], serviceDate: String
    ) throws -> [String: [LineSegment]] {
        var result: [String: [LineSegment]] = [:]
        for batch in tripIDs.chunked(maximumCount: 400) {
            let placeholders = batch.indices.map { "?\($0 + 2)" }.joined(separator: ",")
            for row in try rows("""
                SELECT tls.trip_id, tls.sequence, tls.from_station_id, tls.to_station_id,
                       tls.line_name, tls.operator_id, tls.confidence,
                       tls.reference_kind, tls.current_n02_line_id, tls.rail_history_id
                FROM trip_line_segments tls
                JOIN operators o ON o.operator_id = tls.operator_id
                JOIN station_identities sf ON sf.station_id = tls.from_station_id
                JOIN station_identities st ON st.station_id = tls.to_station_id
                WHERE tls.trip_id IN (\(placeholders))
                  AND o.valid_from <= ?1
                  AND (o.valid_until IS NULL OR ?1 < o.valid_until)
                  AND (sf.valid_from IS NULL OR sf.valid_from <= ?1)
                  AND (sf.valid_until IS NULL OR ?1 < sf.valid_until)
                  AND (st.valid_from IS NULL OR st.valid_from <= ?1)
                  AND (st.valid_until IS NULL OR ?1 < st.valid_until)
                ORDER BY tls.trip_id, tls.sequence
                """, bindings: [serviceDate] + batch) {
                result[row.string(0), default: []].append(LineSegment(
                    sequence: row.int(1), fromStationID: row.string(2),
                    toStationID: row.string(3), lineName: row.string(4),
                    operatorID: row.optionalString(5), confidence: row.optionalString(6),
                    referenceKind: row.optionalString(7).flatMap(LineSegment.ReferenceKind.init),
                    currentN02LineID: row.optionalString(8), railHistoryID: row.optionalString(9)))
            }
        }
        return result
    }

    private func loadOperatorSegments(
        tripIDs: [String], serviceDate: String
    ) throws -> [String: [OperatorSegment]] {
        var result: [String: [OperatorSegment]] = [:]
        for batch in tripIDs.chunked(maximumCount: 400) {
            let placeholders = batch.indices.map { "?\($0 + 2)" }.joined(separator: ",")
            for row in try rows("""
                SELECT tos.trip_id, tos.from_sequence, tos.to_sequence,
                       tos.operator_id, o.display_name
                FROM trip_operator_segments tos
                JOIN operators o ON o.operator_id = tos.operator_id
                WHERE tos.trip_id IN (\(placeholders))
                  AND o.valid_from <= ?1
                  AND (o.valid_until IS NULL OR ?1 < o.valid_until)
                ORDER BY tos.trip_id, tos.from_sequence
                """, bindings: [serviceDate] + batch) {
                result[row.string(0), default: []].append(OperatorSegment(
                    fromSequence: row.int(1), toSequence: row.int(2),
                    operatorID: row.string(3), displayName: row.string(4)))
            }
        }
        return result
    }

    private func loadFactCompleteness(tripIDs: [String]) throws -> [String: [String: Coverage]] {
        var result: [String: [String: Coverage]] = [:]
        for batch in tripIDs.chunked(maximumCount: 400) {
            let placeholders = batch.indices.map { "?\($0 + 1)" }.joined(separator: ",")
            for row in try rows("""
                SELECT entity_id, dimension, status
                FROM fact_completeness
                WHERE entity_type = 'trip' AND entity_id IN (\(placeholders))
                """, bindings: batch) {
                result[row.string(0), default: [:]][row.string(1)] =
                    Coverage(databaseValue: row.optionalString(2))
            }
        }
        return result
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private struct Row {
        let values: [Value]
        func string(_ index: Int) -> String { optionalString(index) ?? "" }
        func optionalString(_ index: Int) -> String? {
            if case .text(let value) = values[index] { return value }
            return nil
        }
        func int(_ index: Int) -> Int { optionalInt(index) ?? 0 }
        func optionalInt(_ index: Int) -> Int? {
            if case .integer(let value) = values[index] { return Int(value) }
            return nil
        }
    }

    private enum Value { case text(String), integer(Int64), null }

    private func rows(_ sql: String, bindings: [String] = []) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(connection))) }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in bindings.enumerated() {
            guard sqlite3_bind_text(statement, Int32(offset + 1), value, -1, transient) == SQLITE_OK
            else { throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(connection))) }
        }

        var result: [Row] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let count = sqlite3_column_count(statement)
                let values = (0..<count).map { column -> Value in
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER: .integer(sqlite3_column_int64(statement, column))
                    case SQLITE_TEXT:
                        sqlite3_column_text(statement, column).map {
                            .text(String(cString: $0))
                        } ?? .null
                    default: .null
                    }
                }
                result.append(Row(values: values))
            case SQLITE_DONE: return result
            default: throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(connection)))
            }
        }
    }

    private static func tableNames(in connection: OpaquePointer) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            connection, "SELECT name FROM sqlite_master WHERE type = 'table'", -1, &statement, nil
        ) == SQLITE_OK, let statement else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 0) {
                names.insert(String(cString: name))
            }
        }
        return names
    }

    private static func validateArtifactIdentity(in connection: OpaquePointer) throws {
        let applicationID = try integerPragma("application_id", in: connection)
        guard applicationID == 0x4A54_4D54 else {
            throw DatabaseError.invalidArtifact(
                "application_id is \(applicationID), expected 0x4A544D54")
        }
        let userVersion = try integerPragma("user_version", in: connection)
        guard userVersion == 1 else {
            throw DatabaseError.invalidArtifact("user_version is \(userVersion), expected 1")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            connection, "SELECT value FROM metadata WHERE key = 'schema_version'", -1,
            &statement, nil) == SQLITE_OK, let statement
        else {
            throw DatabaseError.invalidArtifact("metadata.schema_version is unavailable")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0),
              String(cString: value) == "1.0.0"
        else { throw DatabaseError.invalidArtifact("metadata.schema_version must be 1.0.0") }
    }

    private static func integerPragma(
        _ name: String, in connection: OpaquePointer
    ) throws -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA \(name)", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw DatabaseError.invalidArtifact("PRAGMA \(name) is unavailable") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.invalidArtifact("PRAGMA \(name) has no value")
        }
        return sqlite3_column_int(statement, 0)
    }

    private static func validateEssentialColumns(in connection: OpaquePointer) throws {
        let required: [String: Set<String>] = [
            "source_documents": ["source_id", "title", "publisher", "url_or_locator",
                                 "license_status"],
            "operators": ["operator_id", "display_name", "valid_from", "valid_until"],
            "services": ["service_id", "canonical_name", "service_class", "historical_generation",
                         "first_verified_date", "last_verified_date", "jr_scope"],
            "service_name_periods": ["service_id", "name", "valid_from", "valid_until"],
            "timetable_versions": ["timetable_version_id", "effective_from", "effective_until", "completeness"],
            "timetable_version_sources": ["timetable_version_id", "source_id"],
            "calendars": ["calendar_id", "monday", "tuesday", "wednesday", "thursday", "friday",
                          "saturday", "sunday", "valid_from", "valid_until", "holiday_policy"],
            "calendar_exceptions": ["calendar_id", "service_date", "exception_type"],
            "station_identities": ["station_id", "name_snapshot", "reference_kind",
                                   "current_source_code", "rail_history_id", "valid_from", "valid_until"],
            "trips": ["trip_id", "timetable_version_id", "service_id", "calendar_id", "train_number",
                      "public_number", "origin_station_id", "destination_station_id", "direction",
                      "service_class", "operation_group_id", "notes"],
            "stop_times": ["trip_id", "stop_sequence", "station_id", "arrival_time", "departure_time",
                           "arrival_seconds", "departure_seconds", "day_offset", "arrival_day_offset",
                           "departure_day_offset", "call_type",
                           "pickup_allowed", "dropoff_allowed", "platform", "time_accuracy"],
            "trip_stop_time_overrides": ["trip_id", "service_date", "stop_sequence", "arrival_override",
                                         "departure_override", "arrival_seconds_override",
                                         "departure_seconds_override", "arrival_day_offset_override",
                                         "departure_day_offset_override"],
            "trip_operator_segments": ["trip_id", "from_sequence", "to_sequence", "operator_id"],
            "trip_line_segments": ["trip_id", "sequence", "from_station_id", "to_station_id",
                                   "line_name", "operator_id", "confidence", "reference_kind",
                                   "current_n02_line_id", "rail_history_id"],
            "fact_sources": ["entity_type", "entity_id", "source_id"],
            "fact_completeness": ["entity_type", "entity_id", "dimension", "status"],
        ]
        for (table, expected) in required {
            let columns = try columnNames(of: table, in: connection)
            let missing = expected.subtracting(columns).sorted()
            guard missing.isEmpty else {
                throw DatabaseError.invalidArtifact(
                    "table \(table) is missing columns: \(missing.joined(separator: ", "))")
            }
        }
    }

    private static func columnNames(
        of table: String, in connection: OpaquePointer
    ) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA table_info(\(table))", -1, &statement, nil)
                == SQLITE_OK, let statement
        else { throw DatabaseError.invalidArtifact("cannot inspect table \(table)") }
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: name))
            }
        }
        return columns
    }

    private static func validate(serviceDate: String) throws {
        guard serviceDate.count == 10 else { throw DatabaseError.invalidServiceDate(serviceDate) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: serviceDate), formatter.string(from: date) == serviceDate
        else { throw DatabaseError.invalidServiceDate(serviceDate) }
    }

    private static func weekdayColumn(for serviceDate: String) throws -> String {
        try validate(serviceDate: serviceDate)
        let parts = serviceDate.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: parts[0], month: parts[1], day: parts[2]))!
        let columns = [
            "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
        ]
        return columns[calendar.component(.weekday, from: date) - 1]
    }

    private static func escapedLike(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func decodeService(_ row: Row) -> Service {
        Service(
            id: row.string(0), canonicalName: row.string(1), serviceClass: row.string(2),
            historicalGeneration: row.int(3), firstVerifiedDate: row.optionalString(4),
            lastVerifiedDate: row.optionalString(5), jrScope: row.string(6),
            matchingName: row.optionalString(7))
    }
}

private extension Array {
    func chunked(maximumCount: Int) -> [[Element]] {
        guard !isEmpty else { return [] }
        return stride(from: 0, to: count, by: maximumCount).map {
            Array(self[$0..<Swift.min($0 + maximumCount, count)])
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
