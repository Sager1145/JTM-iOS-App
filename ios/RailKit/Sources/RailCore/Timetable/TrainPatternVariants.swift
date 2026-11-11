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
// - every pattern lists its train numbers explicitly; a range in the JSON
//   ("101-105") is shorthand for consecutive numbers that were each checked and
//   is expanded to an explicit list when decoded (never by parity);
// - direction is stored per group of numbers, never derived from odd or even;
// - the same number may appear in different patterns on different days or in
//   different revisions (validity windows and `runs` store that explicitly).

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
            /// One citation string: publisher, title, locator, access date.
            public let citation: String
            public let patterns: [Variant]

            public init(
                revision: String, validFrom: String, validUntil: String?, checkedOn: String?,
                status: Status, citation: String, patterns: [Variant]
            ) {
                self.revision = revision
                self.validFrom = validFrom
                self.validUntil = validUntil
                self.checkedOn = checkedOn
                self.status = status
                self.citation = citation
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
            public let coupled: Coupling?

            public init(
                id: String, from: String? = nil, to: String? = nil, calls: [String],
                trains: [TrainGroup], coupled: Coupling? = nil
            ) {
                self.id = id
                self.from = from
                self.to = to
                self.calls = calls
                self.trains = trains
                self.coupled = coupled
            }
        }

        /// Train numbers of one pattern, each listed explicitly, with their
        /// direction and the days they run. Nothing about these numbers is
        /// implied by their value.
        public struct TrainGroup: Codable, Sendable, Hashable {
            public let direction: Direction
            /// Every number individually (ranges are expanded at decode time).
            public let numbers: [Int]
            public let runs: RunDay
            /// Optional seasonal window inside the revision; `validUntil` exclusive.
            public let validFrom: String?
            public let validUntil: String?

            public init(
                direction: Direction, numbers: [Int], runs: RunDay = .daily,
                validFrom: String? = nil, validUntil: String? = nil
            ) {
                self.direction = direction
                self.numbers = numbers
                self.runs = runs
                self.validFrom = validFrom
                self.validUntil = validUntil
            }

            private enum CodingKeys: String, CodingKey {
                case direction, numbers, runs, validFrom, validUntil
            }

            /// Largest range accepted as shorthand. A range is consecutive numbers
            /// that were each checked; a huge one is almost certainly a mistake.
            static let maximumRangeLength = 1000

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                direction = try container.decode(Direction.self, forKey: .direction)
                runs = try container.decodeIfPresent(RunDay.self, forKey: .runs) ?? .daily
                validFrom = try container.decodeIfPresent(String.self, forKey: .validFrom)
                validUntil = try container.decodeIfPresent(String.self, forKey: .validUntil)
                var list = try container.nestedUnkeyedContainer(forKey: .numbers)
                var expanded: [Int] = []
                while !list.isAtEnd {
                    if let single = try? list.decode(Int.self) {
                        expanded.append(single)
                        continue
                    }
                    let token = try list.decode(String.self)
                    expanded.append(contentsOf: try Self.expand(token, codingPath: list.codingPath))
                }
                numbers = expanded
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(direction, forKey: .direction)
                try container.encode(numbers, forKey: .numbers)
                if runs != .daily { try container.encode(runs, forKey: .runs) }
                try container.encodeIfPresent(validFrom, forKey: .validFrom)
                try container.encodeIfPresent(validUntil, forKey: .validUntil)
            }

            /// "23" is one number; "101-105" is 101, 102, 103, 104, 105.
            static func expand(_ token: String, codingPath: [any CodingKey]) throws -> [Int] {
                let parts = token.split(separator: "-", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                func fail(_ why: String) -> DecodingError {
                    .dataCorrupted(.init(codingPath: codingPath, debugDescription: "train number \"\(token)\": \(why)"))
                }
                func integer(_ text: String) -> Int? {
                    text.isEmpty || !text.allSatisfy({ $0.isASCII && $0.isNumber }) ? nil : Int(text)
                }
                switch parts.count {
                case 1:
                    guard let value = integer(parts[0]) else { throw fail("not a number") }
                    return [value]
                case 2:
                    guard let low = integer(parts[0]), let high = integer(parts[1]) else {
                        throw fail("not a number range")
                    }
                    guard low <= high else { throw fail("range runs backwards") }
                    guard high - low < maximumRangeLength else { throw fail("range too long") }
                    return Array(low...high)
                default:
                    throw fail("not a number or a range")
                }
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
        }

        /// Coupled running with another service over a station range.
        public struct Coupling: Codable, Sendable, Hashable {
            public let service: String
            public let from: String
            public let to: String
            /// "same" only when the source shows the partner with the same number.
            public let number: String?

            public init(service: String, from: String, to: String, number: String? = nil) {
                self.service = service
                self.from = from
                self.to = to
                self.number = number
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
