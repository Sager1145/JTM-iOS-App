import Foundation

// MARK: - RideRefs: a trip as references into the topology (model + STUBS)
//
// A ride holds no coordinates. Each section of a trip resolves to a list of
// spans on the topology (see `RailTopologyFormat`), or to a recorded gap.
// Line indices, node ordinals and metres are valid for exactly one topology
// file: they are meaningless against another revision, which is why the
// on-disk cache (U3) is keyed by the topology SHA-256 and discarded when it
// changes. Maps, statistics, line detection and the editor all read this type.

/// What a ride reference is: a 16-byte key, an outcome, an ordered list of
/// 8-byte spans and the sections that could not be resolved.
public struct RideRefs: Sendable, Equatable {
    /// Hash of the route input (stops, sections, date, policy, train type,
    /// company). Excludes notes and the app build identity, so a note edit or
    /// an app update does not invalidate it. U3 defines the hashing.
    public struct Key: Sendable, Hashable {
        public var high: UInt64
        public var low: UInt64
        public init(high: UInt64, low: UInt64) { self.high = high; self.low = low }
        /// Byte length of an encoded key.
        public static let byteCount = 16
    }

    /// Result of resolving the whole trip.
    public enum Outcome: UInt8, Sendable {
        /// Every section produced spans.
        case resolved = 0
        /// At least one section produced spans and at least one is a gap.
        case partial = 1
        /// No section produced spans. Stored as a negative cache entry.
        case unresolved = 2
        /// The trip's region is disabled; nothing was attempted.
        case disabledRegion = 3
    }

    /// One span of one section, 8 bytes in memory and on disk:
    /// `{line: UInt16, fromNode: UInt16, toNode: UInt16, tag: UInt16}`, all
    /// little-endian.
    ///
    /// `line`, `fromNode` and `toNode` are the topology's line index and node
    /// ordinals. **Direction is the order of the two nodes**: increasing
    /// ordinals when `fromNode < toNode`, decreasing when `fromNode >
    /// toNode`. On a loop line the ride may instead cross the closing edge
    /// (the edge from the last node to node 0): `wraps` set means "go the
    /// other way round", so from < to travels downward through node 0 to the
    /// last node and on to `toNode`, and from > to travels upward through the
    /// last node to node 0 and on. A span never has `fromNode == toNode`.
    ///
    /// `tag` packs: bits 0...13 the zero-based **section index** within the
    /// trip (at most 16,383 sections), bit 14 `unproven` (found only without
    /// the line filter: drawn dotted, excluded from distance), bit 15 `wraps`.
    ///
    /// A span lies on one line. A path that changes line is several spans
    /// with the same section index, in travel order; the join is a topology
    /// link and is not stored.
    public struct Span: Sendable, Hashable {
        public var span: RailTopology.Span
        public var section: UInt16
        public var unproven: Bool

        public static let byteCount = 8
        public static let maxSection: UInt16 = 0x3FFF

        public init(span: RailTopology.Span, section: UInt16, unproven: Bool = false) {
            precondition(section <= Span.maxSection, "section index exceeds 14 bits")
            self.span = span; self.section = section; self.unproven = unproven
        }

        /// The packed `tag` field.
        public var tag: UInt16 {
            section | (unproven ? 1 << 14 : 0) | (span.wraps ? 1 << 15 : 0)
        }

        /// The eight bytes, little-endian, in field order.
        public var bytes: [UInt8] {
            [span.line, span.fromNode, span.toNode, tag].flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        }

        /// Decodes eight bytes written by `bytes`. Nil when `bytes` is not 8 long.
        public init?(bytes: [UInt8]) {
            guard bytes.count == Span.byteCount else { return nil }
            func word(_ i: Int) -> UInt16 { UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 }
            let tag = word(6)
            self.init(
                span: RailTopology.Span(line: word(0), fromNode: word(2), toNode: word(4),
                                        wraps: tag & (1 << 15) != 0),
                section: tag & Span.maxSection, unproven: tag & (1 << 14) != 0)
        }
    }

    /// Why a section has no spans. Never a straight line and never track
    /// that is not in the topology.
    public struct GapReason: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        /// No path between the section's ends (including a historical date
        /// before the line existed or after it closed).
        public static let noPath = GapReason(rawValue: 1 << 0)
        /// More than one equally good path and no authored choice.
        public static let ambiguous = GapReason(rawValue: 1 << 1)
        /// A section end could not be matched to any stop.
        public static let unknownStop = GapReason(rawValue: 1 << 2)
        /// The only path uses a withheld (not proven) interval.
        public static let withheld = GapReason(rawValue: 1 << 3)
    }

    /// A section with no spans: `{section: UInt16, reason: UInt8}`.
    public struct Gap: Sendable, Hashable {
        public var section: UInt16
        public var reason: GapReason
        public init(section: UInt16, reason: GapReason) { self.section = section; self.reason = reason }
    }

    public var key: Key
    public var outcome: Outcome
    /// In section order, then travel order within a section.
    public var spans: [Span]
    /// In section order; a section is either in `spans` or in `gaps`.
    public var gaps: [Gap]

    public init(key: Key, outcome: Outcome, spans: [Span] = [], gaps: [Gap] = []) {
        self.key = key; self.outcome = outcome; self.spans = spans; self.gaps = gaps
    }
}

// MARK: - RideResolver: public signature (STUB)

/// What a trip's resolution may use besides the trip itself. Evidence is
/// computed by the app (timetable enrichment) and handed in, so the resolver
/// stays pure.
public struct RideEvidence: Sendable {
    /// Section index to the timetable's station sequence for that section
    /// (platform or station codes in travel order), when the timetable has one.
    public var stopSequences: [Int: [String]]
    public init(stopSequences: [Int: [String]] = [:]) { self.stopSequences = stopSequences }
}

/// Resolves a trip against a topology. Pure: no I/O, no shared state, safe to
/// run in parallel. Order per section: authored interval codes (never
/// rerouted), timetable stop sequence, shortest length under the section's
/// line and institution filters through dated links, the same search without
/// the line filter (`unproven`), otherwise a gap.
///
/// STUB (U0b): U6 replaces the body and moves the declaration to
/// `RideResolver.swift`; no other unit should edit it.
public enum RideResolver {
    public static func resolve(
        train: Train, evidence: RideEvidence, topology: RailTopology, key: RideRefs.Key
    ) -> RideRefs {
        RideRefs(key: key, outcome: .unresolved)
    }
}
