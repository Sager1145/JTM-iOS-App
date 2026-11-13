import Foundation

/// The JSON a display-network chunk holds for the stroke engine: one railway's line
/// fragments and the slots of its stations.
///
/// These Decodable types moved out of the app's `RailDisplayNetworkFile` (which now aliases
/// them) so the host-side bake reads exactly the document the app reads. Validation of a
/// chunk against its manifest stays in the app; the bake trusts the builder it just ran.
public struct DisplayChunk: Decodable, Sendable {
    public struct LineFragment: Decodable, Sendable {
        public var lineKey: String
        public var lane: Double?
        /// One part per station-to-station interval, or per lane piece where a reviewed lane
        /// cuts one.
        public var parts: [[[Double]]]
        /// A reviewed continuous-stroke fragment: the parts are one uncut chain of intervals
        /// sharing their endpoints, and the device bakes the screen-space offset in.
        public var continuous: Bool?
        /// Which chain of the line this is; a withheld interval breaks one.
        public var chain: Int?
        /// False when this chain shares a station anchor with the preceding chain but
        /// represents a different branch, not its continuation.
        public var joinPrevious: Bool?
        /// `[fromMetres, toMetres, lane]` rows along the chain.
        public var laneRows: [[Double]]?
        public var totalMetres: Double?
        /// Over `from…to` this chain is drawn from the named chain's alignment.
        public var follows: [FollowRow]?
        /// `[fromMetres, toMetres]` rows this chain bridges rather than cuts.
        public var withheld: [[Double]]?
        /// Family-collapse windows along this chain.
        public var familyWindows: [FamilyWindowRow]?
        /// Exact P,A,B,Q witnesses compiled from the full written joined chain.
        /// Optional drawing metadata must never invalidate required geometry.
        public var literalDisplaySpansV1: [DisplayLiteralSpans.Span]?

        private enum CodingKeys: String, CodingKey {
            case lineKey, lane, parts, continuous, chain, joinPrevious, laneRows
            case totalMetres, follows, withheld, familyWindows, literalDisplaySpansV1
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            lineKey = try container.decode(String.self, forKey: .lineKey)
            lane = try container.decodeIfPresent(Double.self, forKey: .lane)
            parts = try container.decode([[[Double]]].self, forKey: .parts)
            continuous = try container.decodeIfPresent(Bool.self, forKey: .continuous)
            chain = try container.decodeIfPresent(Int.self, forKey: .chain)
            joinPrevious = try container.decodeIfPresent(Bool.self, forKey: .joinPrevious)
            laneRows = try container.decodeIfPresent([[Double]].self, forKey: .laneRows)
            totalMetres = try container.decodeIfPresent(Double.self, forKey: .totalMetres)
            follows = try container.decodeIfPresent([FollowRow].self, forKey: .follows)
            withheld = try container.decodeIfPresent([[Double]].self, forKey: .withheld)
            familyWindows = try container.decodeIfPresent([FamilyWindowRow].self, forKey: .familyWindows)
            literalDisplaySpansV1 = (try? container.decodeIfPresent(
                LiteralSpanRows.self, forKey: .literalDisplaySpansV1))?.spans
        }

        private struct LiteralSpanRows: Decodable {
            var spans: [DisplayLiteralSpans.Span] = []

            init(from decoder: any Decoder) throws {
                var rows = try decoder.unkeyedContainer()
                while !rows.isAtEnd {
                    let child = try rows.superDecoder()
                    if let span = try? DisplayLiteralSpans.Span(from: child) {
                        spans.append(span)
                    }
                }
            }
        }
    }

    /// A family window row decodes from a mixed JSON array.
    public struct FamilyWindowRow: Decodable, Sendable {
        public var from: Double
        public var to: Double
        /// 0 (landlord: this chain draws the shared family stroke over the window) or 1
        /// (tenant: this chain's own stroke is withheld over it). Kept as the raw value so a
        /// role outside 0/1 is a validation failure rather than something an enum coerces.
        public var role: Int
        public var groupID: String
        public var isLandlord: Bool { role == 0 }

        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            from = try container.decode(Double.self)
            to = try container.decode(Double.self)
            role = try container.decode(Int.self)
            groupID = try container.decode(String.self)
        }
    }

    /// One family's resolved colours.
    public struct FamilyColor: Decodable, Sendable {
        public var color: String
        public var colorDark: String

        public init(color: String, colorDark: String) {
            self.color = color
            self.colorDark = colorDark
        }
    }

    /// A follow row decodes from a mixed JSON array.
    public struct FollowRow: Decodable, Sendable {
        public var from: Double
        public var to: Double
        public var canonicalLineKey: String
        public var canonicalChain: Int
        public var canonicalFrom: Double
        public var canonicalTo: Double

        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            from = try container.decode(Double.self)
            to = try container.decode(Double.self)
            canonicalLineKey = try container.decode(String.self)
            canonicalChain = try container.decode(Int.self)
            canonicalFrom = try container.decode(Double.self)
            canonicalTo = try container.decode(Double.self)
        }
    }

    /// The part of a station row the stroke engine reads: which vertex of which chain it sits on.
    public struct StationSlot: Decodable, Sendable {
        public var id: String
        public var lineKey: String
        /// `[chain, vertexIndex]`.
        public var slot: [Int]?
    }

    public var lines: [LineFragment]
    public var stations: [StationSlot]
    public var families: [String: FamilyColor]

    private enum CodingKeys: String, CodingKey { case families, lines, stations }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        families = try container.decodeIfPresent([String: FamilyColor].self, forKey: .families) ?? [:]
        lines = try container.decode([LineFragment].self, forKey: .lines)
        stations = try container.decodeIfPresent([StationSlot].self, forKey: .stations) ?? []
    }
}
