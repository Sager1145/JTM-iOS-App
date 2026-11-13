import Foundation

/// One drawn chain, as the stroke engine needs it: geometry in the display datum plus the
/// reviewed lane, follow, withheld and family data. No presentation state (names, colour
/// objects, history stamps); the app's `DrawnLine` carries one of these beside those.
public struct StrokeLineInput: Sendable, Identifiable {

    /// Corridor follow: over `from…to` this chain is drawn from the named chain's alignment.
    public struct Follow: Sendable, Hashable {
        public let from: Double
        public let to: Double
        /// `StrokeLineInput.id` of the canonical chain (`lineKey#chain`).
        public let canonicalID: String
        public let canonicalFrom: Double
        public let canonicalTo: Double

        public init(from: Double, to: Double, canonicalID: String, canonicalFrom: Double, canonicalTo: Double) {
            self.from = from
            self.to = to
            self.canonicalID = canonicalID
            self.canonicalFrom = canonicalFrom
            self.canonicalTo = canonicalTo
        }
    }

    /// A span a continuous chain draws THROUGH rather than around. Metres in the chain's own
    /// measure space.
    public struct Withheld: Sendable, Hashable {
        public let from: Double
        public let to: Double

        public init(from: Double, to: Double) {
            self.from = from
            self.to = to
        }
    }

    /// A stretch this chain shares its stroke with a sibling railway of the same operator
    /// collapse. A landlord window draws the shared family stroke in `colorHex`; a tenant
    /// window withholds this chain's own stroke there.
    public struct FamilyWindow: Sendable, Hashable {
        public let from: Double
        public let to: Double
        public let isLandlord: Bool
        public let groupID: String
        public let colorHex: String
        public let colorDarkHex: String

        public init(
            from: Double, to: Double, isLandlord: Bool, groupID: String,
            colorHex: String, colorDarkHex: String
        ) {
            self.from = from
            self.to = to
            self.isLandlord = isLandlord
            self.groupID = groupID
            self.colorHex = colorHex
            self.colorDarkHex = colorDarkHex
        }
    }

    /// Drawing identity: `lineKey#chain` for a continuous chain, `lineKey@lane` otherwise.
    public let id: String
    /// Identity of this immutable decoded content. Copies retain it; a re-decoded line gets a
    /// new one even if its public id is unchanged.
    public let contentID: UUID
    /// The canonical package line id the chain belongs to.
    public let lineID: String
    /// Region code (`jp`, `hk`, …).
    public let region: String
    public let operatorName: String?
    /// Lower-case `#rrggbb`, the batching key beside the tier.
    public let colorHex: String
    public let colorDarkHex: String
    /// Signed screen-space corridor lane. Zero keeps canonical geometry.
    public let lane: Double
    public let continuous: Bool
    public let joinPrevious: Bool
    public let laneRows: [ContinuousStroke.LaneRow]
    public let totalMetres: Double
    public let follows: [Follow]
    public let withheld: [Withheld]
    public let familyWindows: [FamilyWindow]
    public let literalDisplaySpansV1: [DisplayLiteralSpans.Span]
    /// One polyline per station-to-station interval, in the display datum.
    public let intervals: [[Coordinate]]
    /// For each interval, the index of the fragment part it came from (a part with fewer than
    /// two usable points is dropped, so the two can differ).
    public let sourcePartIndices: [Int]
    /// Bounding box in map points, computed once so the junction test is a rectangle test.
    public let bounds: StrokeBounds

    public init(
        id: String, contentID: UUID = UUID(), lineID: String, region: String, operatorName: String?,
        colorHex: String, colorDarkHex: String, lane: Double, continuous: Bool,
        joinPrevious: Bool = true, laneRows: [ContinuousStroke.LaneRow] = [],
        totalMetres: Double = 0, follows: [Follow] = [], withheld: [Withheld] = [],
        familyWindows: [FamilyWindow] = [],
        literalDisplaySpansV1: [DisplayLiteralSpans.Span] = [],
        intervals: [[Coordinate]], sourcePartIndices: [Int]? = nil
    ) {
        self.id = id
        self.contentID = contentID
        self.lineID = lineID
        self.region = region
        self.operatorName = operatorName
        self.colorHex = colorHex
        self.colorDarkHex = colorDarkHex
        self.lane = lane
        self.continuous = continuous
        self.joinPrevious = joinPrevious
        self.laneRows = laneRows
        self.totalMetres = totalMetres
        self.follows = follows
        self.withheld = withheld
        self.familyWindows = familyWindows
        self.literalDisplaySpansV1 = literalDisplaySpansV1
        self.intervals = intervals
        self.sourcePartIndices = sourcePartIndices ?? Array(intervals.indices)
        var box = StrokeBounds.null
        for interval in intervals {
            for coordinate in interval { box = box.union(StrokeProjection.point(coordinate)) }
        }
        self.bounds = box
    }

    public var vertexCount: Int { intervals.reduce(0) { $0 + $1.count } }
}

/// What the manifest says about a railway, reduced to what the stroke input needs.
public struct DisplayLineMetadata: Sendable {
    /// The package line id (`jp-東日本旅客鉄道-山手線`).
    public var id: String
    public var region: String
    public var operatorName: String?
    public var color: String
    public var colorDark: String

    public init(id: String, region: String, operatorName: String?, color: String, colorDark: String) {
        self.id = id
        self.region = region
        self.operatorName = operatorName
        self.color = color
        self.colorDark = colorDark
    }
}

extension StrokeLineInput {
    /// The one place a display-chunk fragment becomes drawn geometry: the id rule, the datum
    /// shift, the reviewed lane / follow / family rows and the literal-span eligibility.
    /// The app's `prepareDisplayLine` and the host-side `RailBakeKit` both call it.
    ///
    /// - Parameters:
    ///   - shiftToGCJ02: apply the GCJ-02 displacement to every vertex before anything else
    ///     reads it, as the app does for a region drawn on the China map service.
    ///   - fullDetail: the chunk is a full one, not an overview; literal spans only ride on
    ///     full chunks.
    ///   - stampedPartIndices: fragment part indices that carry a history stamp. Literal spans
    ///     are not used on a stamped line.
    /// - Returns: nil when the fragment has no part with two usable points.
    public static func make(
        fragment: DisplayChunk.LineFragment, metadata: DisplayLineMetadata,
        families: [String: DisplayChunk.FamilyColor], shiftToGCJ02: Bool,
        fullDetail: Bool = true, stampedPartIndices: Set<Int> = []
    ) -> StrokeLineInput? {
        let drawID = fragment.continuous == true
            ? "\(fragment.lineKey)#\(fragment.chain ?? 0)"
            : "\(fragment.lineKey)@\(fragment.lane ?? 0)"
        var intervals: [[Coordinate]] = []
        var sourceIndices: [Int] = []
        var stamped = false
        for (index, part) in fragment.parts.enumerated() {
            let source = part.compactMap(Coordinate.init(pair:))
            guard source.count >= 2 else { continue }
            intervals.append(shiftToGCJ02 ? source.map(GCJ02.fromWGS84) : source)
            sourceIndices.append(index)
            if stampedPartIndices.contains(index) { stamped = true }
        }
        guard !intervals.isEmpty else { return nil }
        let laneRows = (fragment.laneRows ?? []).map {
            ContinuousStroke.LaneRow(from: $0[0], to: $0[1], lane: $0[2])
        }
        let literalEligible = fullDetail && metadata.region == "jp"
            && fragment.continuous == true && !stamped
            && (fragment.lane ?? 0) == 0
            && (fragment.laneRows ?? []).allSatisfy({ $0[2] == 0 })
            && (fragment.follows ?? []).isEmpty
            && (fragment.familyWindows ?? []).isEmpty
            && (fragment.withheld ?? []).isEmpty
        return StrokeLineInput(
            id: drawID, lineID: metadata.id, region: metadata.region,
            operatorName: metadata.operatorName,
            colorHex: metadata.color.lowercased(), colorDarkHex: metadata.colorDark.lowercased(),
            lane: fragment.lane ?? 0, continuous: fragment.continuous == true,
            joinPrevious: fragment.joinPrevious ?? true, laneRows: laneRows,
            totalMetres: fragment.totalMetres ?? 0,
            follows: (fragment.follows ?? []).map {
                Follow(
                    from: $0.from, to: $0.to,
                    canonicalID: "\($0.canonicalLineKey)#\($0.canonicalChain)",
                    canonicalFrom: $0.canonicalFrom, canonicalTo: $0.canonicalTo)
            },
            withheld: (fragment.withheld ?? []).compactMap {
                $0.count >= 2 ? Withheld(from: $0[0], to: $0[1]) : nil
            },
            familyWindows: (fragment.familyWindows ?? []).compactMap { window in
                guard let group = families[window.groupID] else { return nil }
                return FamilyWindow(
                    from: window.from, to: window.to, isLandlord: window.isLandlord,
                    groupID: window.groupID, colorHex: group.color.lowercased(),
                    colorDarkHex: group.colorDark.lowercased())
            },
            literalDisplaySpansV1: literalEligible ? fragment.literalDisplaySpansV1 ?? [] : [],
            intervals: intervals, sourcePartIndices: sourceIndices)
    }

    /// Station anchors per chain: for each `region|lineID#chain` key, the chain vertex indices
    /// its stations sit on, in station order. Keys equal `StrokeLineInput.id` of the chain.
    public static func anchors(
        stations: [DisplayChunk.StationSlot], lineMetadata: (String) -> DisplayLineMetadata?
    ) -> [String: [Int]] {
        var anchors: [String: [Int]] = [:]
        for station in stations {
            guard let slot = station.slot, slot.count >= 2,
                  let metadata = lineMetadata(station.lineKey) else { continue }
            anchors["\(metadata.region)|\(metadata.id)#\(slot[0])", default: []].append(slot[1])
        }
        return anchors
    }
}
