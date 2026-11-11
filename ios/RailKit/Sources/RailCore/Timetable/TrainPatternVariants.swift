import Foundation

// Stop-pattern variants of a named service (Shinkansen stop-pattern database).
//
// Storage: two optional keys on a record of `train-service-patterns.json`
// (`allStations`, `variants`); see docs/maintenance/2026-11-11-shinkansen-database-design.md.
// This file is the data model and its decoder. The lookup is in
// `TrainPatternLookup.swift`, the checks in `TrainPatternVariantsValidator.swift`.
//
// Ground rule (user requirement): no rule maps a train number to a stop pattern.
// Same-named trains can have different patterns, and numbers need not follow any
// block, parity or neighbour logic. So:
// - every pattern lists its train numbers explicitly, one by one (no ranges);
// - direction is stored per group of numbers, never derived from odd or even;
// - the same number may appear in different patterns on different days or in
//   different revisions (validity windows, `runs`, `daysOfWeek` and explicit
//   `dates` store that); an extra train lists the exact dates it runs.

extension TrainServicePatterns {

    /// The `variants` block of a base record: the distinct stop patterns of one
    /// service per timetable revision. The base record's `stops` stay the
    /// always-served stations and its `optionalStops` the ones some trains skip.
    public struct Variants: Codable, Sendable, Hashable {
        /// The only block layout this reader understands. A block with another
        /// number decodes to nil, as if the record had no variants.
        public static let supportedSchema = 1

        public let schema: Int
        /// Station codes (`sourceCode`) of every always-served and optional
        /// station of the base record, in corridor order ("down" direction).
        public let order: [String]
        public let revisions: [Revision]

        public init(schema: Int = Variants.supportedSchema, order: [String], revisions: [Revision]) {
            self.schema = schema
            self.order = order
            self.revisions = revisions
        }

        /// Direction of a group of trains along `order`. Stored per group.
        public enum Direction: String, Codable, Sendable, Hashable {
            case down, up
        }

        /// On which days the trains of a group run. `extra` is for seasonal or
        /// extra trains that run on announced days only.
        public enum RunDay: String, Codable, Sendable, Hashable {
            case daily, weekdays, holidays, extra
        }

        /// What the caller knows of the day type of a ride date. Holiday means
        /// Saturday, Sunday or public holiday. The model does not own a holiday
        /// calendar; pass nil when unknown.
        public enum DayKind: String, Sendable, Hashable {
            case weekday, holiday
        }

        public enum Status: String, Codable, Sendable, Hashable {
            case verified, unverified

            public init(from decoder: Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                // Anything but an explicit "verified" is read as unverified.
                self = raw == "verified" ? .verified : .unverified
            }
        }

        /// Citation of a revision's table. `verifiedBy` is the second reader and is
        /// required for a verified status (see the validator).
        public struct Source: Codable, Sendable, Hashable {
            public let type: String
            public let publisher: String
            public let title: String
            public let locator: String
            public let accessedAt: String
            public let license: String?
            public let verifiedBy: String?

            public init(
                type: String, publisher: String, title: String, locator: String,
                accessedAt: String, license: String? = nil, verifiedBy: String? = nil
            ) {
                self.type = type
                self.publisher = publisher
                self.title = title
                self.locator = locator
                self.accessedAt = accessedAt
                self.license = license
                self.verifiedBy = verifiedBy
            }

            /// Source types an operator or printed timetable may carry a verified status.
            public static let officialTypes: Set<String> = ["operator_timetable", "printed_timetable"]
        }

        /// One timetable revision of a base record. Numbers of one revision are
        /// never read for a date outside `[validFrom, validUntil)`.
        public struct Revision: Codable, Sendable, Hashable {
            public let revision: String
            public let validFrom: String
            /// Exclusive. Nil only for the revision in force.
            public let validUntil: String?
            /// Last date the source was confirmed to be in force.
            public let checkedOn: String?
            public let status: Status
            /// Where the table was read: kept structured so a verified status can
            /// be re-checked from the bundled file alone.
            public let source: Source
            public let patterns: [Variant]

            public init(
                revision: String, validFrom: String, validUntil: String?, checkedOn: String?,
                status: Status, source: Source, patterns: [Variant]
            ) {
                self.revision = revision
                self.validFrom = validFrom
                self.validUntil = validUntil
                self.checkedOn = checkedOn
                self.status = status
                self.source = source
                self.patterns = patterns
            }

            /// Whether `day` (`YYYY-MM-DD`) lies inside `[validFrom, validUntil)`.
            /// Malformed dates never cover anything.
            public func covers(_ day: String) -> Bool {
                guard let day = Pattern.GregorianDay(day),
                      let from = Pattern.GregorianDay(validFrom), from <= day
                else { return false }
                if let validUntil {
                    guard let until = Pattern.GregorianDay(validUntil) else { return false }
                    return day < until
                }
                return true
            }
        }

        /// One distinct stop pattern of a revision, with the numbers that use it.
        public struct Variant: Codable, Sendable, Hashable {
            /// Unique inside its revision.
            public let id: String
            /// Station codes of the ends when they differ from the base record's
            /// ends (a 東京–広島 train of a 東京–博多 base record).
            public let from: String?
            public let to: String?
            /// The optional stops this pattern serves. Always-served stops
            /// between its ends are implied.
            public let calls: [String]
            public let trains: [TrainGroup]

            public init(
                id: String, from: String? = nil, to: String? = nil, calls: [String],
                trains: [TrainGroup]
            ) {
                self.id = id
                self.from = from
                self.to = to
                self.calls = calls
                self.trains = trains
            }
        }

        /// Day of the week, for `daysOfWeek`.
        public enum Weekday: String, Codable, Sendable, Hashable, CaseIterable {
            case mon, tue, wed, thu, fri, sat, sun
        }

        /// Train numbers of one pattern, each listed explicitly, with their
        /// direction and the days they run. Nothing about these numbers is
        /// implied by their value.
        public struct TrainGroup: Codable, Sendable, Hashable {
            public let direction: Direction
            /// Every number individually.
            public let numbers: [Int]
            public let runs: RunDay
            /// Optional seasonal window inside the revision; `validUntil` exclusive.
            public let validFrom: String?
            public let validUntil: String?
            /// Optional weekday filter ("fri" for a Friday-only train, all but
            /// "sun" for a train not running on Sundays). Nil means every weekday.
            public let daysOfWeek: [Weekday]?
            /// The exact dates (`YYYY-MM-DD`) of an `extra` group. Required for
            /// `extra` and not allowed otherwise: an announced extra train runs on
            /// those dates only, and on none other.
            public let dates: [String]?
            /// Coupled running of these trains. A pattern shared by coupled and
            /// uncoupled trains lists them as separate groups.
            public let coupled: Coupling?

            public init(
                direction: Direction, numbers: [Int], runs: RunDay = .daily,
                validFrom: String? = nil, validUntil: String? = nil,
                daysOfWeek: [Weekday]? = nil, dates: [String]? = nil, coupled: Coupling? = nil
            ) {
                self.direction = direction
                self.numbers = numbers
                self.runs = runs
                self.validFrom = validFrom
                self.validUntil = validUntil
                self.daysOfWeek = daysOfWeek
                self.dates = dates
                self.coupled = coupled
            }

            private enum CodingKeys: String, CodingKey {
                case direction, numbers, runs, validFrom, validUntil, daysOfWeek, dates, coupled
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                direction = try container.decode(Direction.self, forKey: .direction)
                numbers = try container.decode([Int].self, forKey: .numbers)
                runs = try container.decodeIfPresent(RunDay.self, forKey: .runs) ?? .daily
                validFrom = try container.decodeIfPresent(String.self, forKey: .validFrom)
                validUntil = try container.decodeIfPresent(String.self, forKey: .validUntil)
                daysOfWeek = try container.decodeIfPresent([Weekday].self, forKey: .daysOfWeek)
                dates = try container.decodeIfPresent([String].self, forKey: .dates)
                coupled = try container.decodeIfPresent(Coupling.self, forKey: .coupled)
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(direction, forKey: .direction)
                try container.encode(numbers, forKey: .numbers)
                if runs != .daily { try container.encode(runs, forKey: .runs) }
                try container.encodeIfPresent(validFrom, forKey: .validFrom)
                try container.encodeIfPresent(validUntil, forKey: .validUntil)
                try container.encodeIfPresent(daysOfWeek, forKey: .daysOfWeek)
                try container.encodeIfPresent(dates, forKey: .dates)
                try container.encodeIfPresent(coupled, forKey: .coupled)
            }

            /// Whether the group's own seasonal window (if any) covers `day`.
            func windowCovers(_ day: Pattern.GregorianDay) -> Bool {
                if let validFrom {
                    guard let from = Pattern.GregorianDay(validFrom), from <= day else { return false }
                }
                if let validUntil {
                    guard let until = Pattern.GregorianDay(validUntil), day < until else { return false }
                }
                return true
            }

            enum Applies: Sendable, Hashable {
                case yes, no
                /// Runs on weekdays only or holidays only and the caller gave no day type.
                case needsDayKind
            }

            /// Whether the group runs on `day` (inside its revision, which the
            /// caller has checked). Exact: `extra` groups run on their listed
            /// dates only.
            func applies(on day: Pattern.GregorianDay, dayKind: DayKind?) -> Applies {
                guard windowCovers(day) else { return .no }
                if let daysOfWeek, !daysOfWeek.contains(day.weekday) { return .no }
                switch runs {
                case .extra:
                    return dates?.contains(day.rawValue) == true ? .yes : .no
                case .daily:
                    return .yes
                case .weekdays, .holidays:
                    guard let dayKind else { return .needsDayKind }
                    return (runs == .weekdays) == (dayKind == .weekday) ? .yes : .no
                }
            }
        }

        /// Coupled running with another service over a station range.
        public struct Coupling: Codable, Sendable, Hashable {
            public let service: String
            public let from: String
            public let to: String
            /// "same" only when the source shows the partner with the same number
            /// for every train of the group.
            public let number: String?
            /// The partner's number for each train of the group that has a
            /// different one, keyed by this train's number ("23": 1023).
            public let partnerNumbers: [String: Int]?

            public init(
                service: String, from: String, to: String, number: String? = nil,
                partnerNumbers: [String: Int]? = nil
            ) {
                self.service = service
                self.from = from
                self.to = to
                self.number = number
                self.partnerNumbers = partnerNumbers
            }

            /// The partner's number for `trainNumber`, nil when the source gives none.
            public func partnerNumber(for trainNumber: Int) -> Int? {
                if number == "same" { return trainNumber }
                return partnerNumbers?[String(trainNumber)]
            }
        }

        // MARK: Decoding

        private struct SchemaProbe: Decodable {
            let schema: Int?
        }

        /// Decodes the block, or nil when the key is absent or its `schema` is
        /// not ``supportedSchema``. A supported block that is malformed throws.
        static func decodeIfSupported<Key: CodingKey>(
            from container: KeyedDecodingContainer<Key>, forKey key: Key
        ) throws -> Variants? {
            guard container.contains(key), try !container.decodeNil(forKey: key) else { return nil }
            let probe = try container.decode(SchemaProbe.self, forKey: key)
            guard probe.schema == supportedSchema else { return nil }
            return try container.decode(Variants.self, forKey: key)
        }
    }
}

// MARK: - Stop lists

extension TrainServicePatterns.Variants {

    /// The codes at the ends of the base record's own run, in `order`.
    func baseEndCodes(of base: TrainServicePatterns.Pattern) -> (first: String, last: String)? {
        func code(named name: String) -> String? {
            (base.stopRefs + base.optionalStopRefs).first { $0.name == name }?.sourceCode
        }
        guard let first = code(named: base.origin) ?? order.first,
              let last = code(named: base.destination) ?? order.last
        else { return nil }
        return (first, last)
    }

    /// Codes a pattern calls at, in down order: `order` cut to the pattern's
    /// ends, keeping the base record's always-served stops and the pattern's
    /// own `calls`. Nothing else, so a pattern cannot leave out an always-served
    /// stop or call at a station outside the base record. Empty when the ends
    /// are unknown or run against `order`.
    public func stopCodes(of variant: Variant, in base: TrainServicePatterns.Pattern) -> [String] {
        guard let ends = baseEndCodes(of: base) else { return [] }
        let from = variant.from ?? ends.first
        let to = variant.to ?? ends.last
        guard let low = order.firstIndex(of: from), let high = order.firstIndex(of: to), low <= high
        else { return [] }
        let always = Set(base.stopRefs.map(\.sourceCode))
        let calls = Set(variant.calls)
        return order[low...high].filter { always.contains($0) || calls.contains($0) }
    }
}

// MARK: - Weekday of a date

extension TrainServicePatterns.Pattern.GregorianDay {
    /// Day of the week of a valid proleptic Gregorian date.
    var weekday: TrainServicePatterns.Variants.Weekday {
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        var year = parts[0]
        let month = parts[1], day = parts[2]
        // Sakamoto's algorithm: 0 = Sunday.
        let table = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
        if month < 3 { year -= 1 }
        let index = (year + year / 4 - year / 100 + year / 400 + table[month - 1] + day) % 7
        return [.sun, .mon, .tue, .wed, .thu, .fri, .sat][index]
    }
}
