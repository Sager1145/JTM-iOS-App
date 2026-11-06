import Foundation

/// One detected failure inside an area, with its measurement, evidence and
/// (when one exists) a prefilled repair op. A proposal is a draft: its
/// `reason` and `source` must be completed before it can be written.
public struct Problem: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case missingJunction, lostHistoryStamp, uncertifiedPairedTrack, stationDotOffLine, overRoundedCorner, pairedDirectionSide

        /// Regression guards that cover a repair of this kind.
        public var guardClass: GuardClass {
            switch self {
            case .missingJunction: .junction
            case .lostHistoryStamp: .history
            case .uncertifiedPairedTrack, .pairedDirectionSide: .paired
            case .stationDotOffLine: .station
            case .overRoundedCorner: .rounding
            }
        }
    }
    /// `review`: evidence for a human decision, never an automatic fix.
    public enum Severity: String, Codable, Sendable { case error, warning, review, info }

    public var id: String
    public var kind: Kind
    public var severity: Severity
    public var lineIDs: [String]
    public var stationCode: String?
    public var coordinate: AreaPoint
    /// The measured quantity (metres for distances; 0/1 for boolean checks).
    public var measure: Double
    public var message: String
    public var evidence: [String]
    public var proposal: PatchOp?

    public init(id: String, kind: Kind, severity: Severity, lineIDs: [String], stationCode: String? = nil,
                coordinate: AreaPoint, measure: Double, message: String, evidence: [String] = [], proposal: PatchOp? = nil) {
        self.id = id; self.kind = kind; self.severity = severity; self.lineIDs = lineIDs
        self.stationCode = stationCode; self.coordinate = coordinate; self.measure = measure
        self.message = message; self.evidence = evidence; self.proposal = proposal
    }
}

/// The single home of every detector threshold. Codable: a JSON object may
/// override any subset; missing keys keep the defaults below.
public struct AreaThresholds: Codable, Equatable, Sendable {
    /// Default selection margin around an area (metres).
    public var marginMetres = 500.0
    /// Search radius around a shared station for each line's track vertices.
    public var junctionSearchMetres = 300.0
    /// At or below: identical-vertex (zeroLength) junction proposal.
    public var zeroLengthMetres = 1.0
    /// At or below: reviewed shortLink proposal (registry policy maximum).
    public var shortLinkMetres = 30.0
    /// A station anchor farther than this from its own line is off the line.
    public var stationOffLineMetres = 25.0
    /// Display corners at or above this deflection are checked for rounding.
    public var cornerMinimumDegrees = 20.0
    /// Smooth samples within this distance of the corner are measured.
    public var cornerWindowMetres = 150.0
    /// Sample spacing along the smooth path.
    public var cornerSampleMetres = 10.0
    /// A smooth path farther than this from the display polyline is over-rounded.
    public var cornerDeviationMetres = 15.0
    /// Map zoom (256-point tiles) the rounding check renders at.
    public var roundingZoom = 15.0
    /// Paired side check: flag when more than this fraction of samples contradict the declared direction…
    public var pairedSideContradictionFraction = 0.7
    /// …and the median lateral offset from the base line exceeds this.
    public var pairedSideMinimumOffsetMetres = 5.0

    public init() {}
    public static let `default` = AreaThresholds()

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case marginMetres, junctionSearchMetres, zeroLengthMetres, shortLinkMetres, stationOffLineMetres
        case cornerMinimumDegrees, cornerWindowMetres, cornerSampleMetres, cornerDeviationMetres, roundingZoom
        case pairedSideContradictionFraction, pairedSideMinimumOffsetMetres
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys, _ fallback: Double) throws -> Double {
            try c.decodeIfPresent(Double.self, forKey: key) ?? fallback
        }
        let d = AreaThresholds()
        marginMetres = try value(.marginMetres, d.marginMetres)
        junctionSearchMetres = try value(.junctionSearchMetres, d.junctionSearchMetres)
        zeroLengthMetres = try value(.zeroLengthMetres, d.zeroLengthMetres)
        shortLinkMetres = try value(.shortLinkMetres, d.shortLinkMetres)
        stationOffLineMetres = try value(.stationOffLineMetres, d.stationOffLineMetres)
        cornerMinimumDegrees = try value(.cornerMinimumDegrees, d.cornerMinimumDegrees)
        cornerWindowMetres = try value(.cornerWindowMetres, d.cornerWindowMetres)
        cornerSampleMetres = try value(.cornerSampleMetres, d.cornerSampleMetres)
        cornerDeviationMetres = try value(.cornerDeviationMetres, d.cornerDeviationMetres)
        roundingZoom = try value(.roundingZoom, d.roundingZoom)
        pairedSideContradictionFraction = try value(.pairedSideContradictionFraction, d.pairedSideContradictionFraction)
        pairedSideMinimumOffsetMetres = try value(.pairedSideMinimumOffsetMetres, d.pairedSideMinimumOffsetMetres)
    }
}
