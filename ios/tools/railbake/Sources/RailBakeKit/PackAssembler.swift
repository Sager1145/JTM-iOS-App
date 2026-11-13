import Foundation
import RailCore

/// Bakes a region at every level of a ladder and assembles the `RailPackSource` the writer turns
/// into a `.railpack` (spec sections 2 and 6).
///
/// Per level: `NetworkStrokeBake` runs the stroke engine over the whole network, `PieceCutter` cuts
/// every chain, station nodes get their vertices, and the pieces get their group (colours, tier
/// window, style class) and date span. Levels are baked one at a time and only their compact piece
/// lists are kept, so memory holds one baked level plus the pieces of all of them.
///
/// Choices where the specification is open:
///  - A level's stroke frame is found from its `mapPointsPerPoint` (the app's frame at the camera
///    with the same scale, `appZoom = 20 - log2(mapPointsPerPoint)`), not from the ladder's zoom
///    number: the ladder counts zoom in the 512-point convention, one below the app's.
///  - A non-continuous line has one chain per part (the topology's flat part number). A part has
///    its own ruler (`NetworkStrokeBake.Run.measures`: 0 at its first vertex, the topology ruler's
///    step over the finished run), and a node is placed on its part's pieces by metres on that
///    ruler. The run is the part as drawn (simplified, lane-offset), so its ruler can differ from
///    the topology's, which was measured on the source part, by the length the simplification and
///    the offset change; the node still lands on the part's line, within that difference of the
///    station's metre.
///  - Every level is thinned (`NetworkStrokeBake.thinned`, `RailStrokeTokens.packThinTolerance`)
///    between the engine's bake and the cutter, with the station metres as forced vertices.
///  - A dated chain (history span) keeps every one of its solid pieces whole: the era picks solid or
///    dashed at run time and a dashed run is never cut.
public enum PackAssembler {

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case lineNotInTopology(String)
        case tooManyChains(String)
        case regionMismatch(topology: String, requested: String)
        case levelFrameMismatch(level: Int)

        public var description: String {
            switch self {
            case .lineNotInTopology(let id): "display line \(id) is not in the topology file"
            case .tooManyChains(let id): "line \(id) has more chains than the pack format holds"
            case .regionMismatch(let topology, let requested): "topology is for \(topology), not \(requested)"
            case .levelFrameMismatch(let level): "level \(level) does not map to a stroke frame"
            }
        }
    }

    /// The stroke frame the app draws at the same scale as ladder level `level`.
    public static func frame(
        for ladder: RailPackLadder, level: Int, datumToken: String
    ) throws -> NetworkStrokeBake.Level {
        let mpp = ladder.mapPointsPerPoint(level: level)
        let appZoom = log2(StrokeProjection.worldSize / (256 * mpp))
        let frame = NetworkStrokeBake.Level(appZoom: appZoom, datumToken: datumToken)
        guard abs(frame.mapPointsPerPoint - mpp) <= mpp * 1e-9 else { throw Failure.levelFrameMismatch(level: level) }
        return frame
    }

    /// One chain of the pack and where it came from.
    struct ChainSlot {
        var inputIndex: Int
        /// Interval index of a non-continuous line; nil for a continuous chain.
        var part: Int?
        var tier: Int16
        var span: DisplayInput.DaySpan?
        var closed: Bool
        /// Global node indices on this chain, with their metres.
        var nodes: [(id: Int, metres: Double)]
    }

    static func rgba(_ hex: String) -> UInt32 {
        var digits = Substring(hex)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return 0x0000_00FF }
        return value << 8 | 0xFF
    }

    private struct GroupKey: Hashable {
        var light: UInt32, dark: UInt32
        var tierMin: Int16, tierMax: Int16
        var style: UInt8
    }

    /// Chains, region-wide: lines in topology order, chains in fragment order, and each node on its
    /// chain (a continuous line's by chain number, a non-continuous line's by flat part number).
    static func layout(
        display: DisplayInput.Region, topology: PackTopology
    ) throws -> (slots: [ChainSlot], lines: [RailPackLine]) {
        let network = display.network
        let displayByID = Dictionary(display.lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let topologyIDs = Set(topology.lines.map(\.id))
        for line in display.lines where !topologyIDs.contains(line.id) { throw Failure.lineNotInTopology(line.id) }
        var slots: [ChainSlot] = []
        var lines: [RailPackLine] = []
        for line in topology.lines {
            let first = slots.count
            if let info = displayByID[line.id] {
                var byNumber: [Int: Int] = [:]
                // Slot of each flat part number of a non-continuous line.
                var flatParts: [Int] = []
                for fragment in info.fragments {
                    let input = network.lines[fragment.inputIndex]
                    if fragment.continuous {
                        byNumber[fragment.chainNumber] = slots.count
                        let joined = input.intervals
                        let closed = (joined.first?.first).flatMap { start in
                            (joined.last?.last).map { $0 == start }
                        } ?? false
                        slots.append(ChainSlot(
                            inputIndex: fragment.inputIndex, part: nil, tier: info.tierQuarterZoom,
                            span: fragment.partSpans.first ?? nil, closed: closed && input.vertexCount >= 4, nodes: []))
                    } else {
                        for part in input.intervals.indices {
                            flatParts.append(slots.count)
                            slots.append(ChainSlot(
                                inputIndex: fragment.inputIndex, part: part, tier: info.tierQuarterZoom,
                                span: fragment.partSpans.indices.contains(part) ? fragment.partSpans[part] : nil,
                                closed: false, nodes: []))
                        }
                    }
                }
                for ordinal in 0..<line.nodeCount {
                    let id = line.firstNode + ordinal
                    guard topology.nodes.indices.contains(id), let metres = topology.nodes[id].metres else { continue }
                    // A non-continuous line's node chain is its flat part number.
                    let number = topology.nodes[id].chain
                    let found = flatParts.isEmpty ? byNumber[number] : (flatParts.indices.contains(number) ? flatParts[number] : nil)
                    guard let chain = found else { continue }
                    slots[chain].nodes.append((id, metres))
                }
            }
            guard slots.count - first <= Int(UInt16.max) else { throw Failure.tooManyChains(line.id) }
            lines.append(RailPackLine(
                firstChain: UInt32(first), chainCount: UInt16(slots.count - first),
                firstNode: UInt32(line.firstNode), nodeCount: UInt16(line.nodeCount)))
        }
        return (slots, lines)
    }

    /// Station metres per stroke: the vertices the thinning must keep.
    static func keepMeasures(
        slots: [ChainSlot], network: NetworkStrokeBake.Network
    ) -> [NetworkStrokeBake.PartKey: [Double]] {
        var keep: [NetworkStrokeBake.PartKey: [Double]] = [:]
        for slot in slots where !slot.nodes.isEmpty {
            keep[NetworkStrokeBake.PartKey(chainID: network.lines[slot.inputIndex].id, part: slot.part ?? 0), default: []]
                .append(contentsOf: slot.nodes.map(\.metres))
        }
        return keep
    }

    /// The tier window of a tenant's fallback ink: from the tenant's own tier up to the tier (exclusive)
    /// where its landlord's pieces take over, or never when the landlord is already drawing by the time
    /// the tenant becomes visible (the landlord's pieces are its ink then). `landlordTier` is the
    /// highest tier among the family's landlords, nil when none draws the family.
    static func fallbackRange(tenantTier: Int16, landlordTier: Int16?) -> (min: Int16, max: Int16) {
        guard let landlordTier else { return (tenantTier, RailPackFormat.tierNoUpperLimit) }
        if landlordTier <= tenantTier { return (RailPackFormat.tierNeverDrawn, RailPackFormat.tierNeverDrawn) }
        return (tenantTier, landlordTier)
    }

    public static func assemble(
        region: String, display: DisplayInput.Region, topology: PackTopology,
        ladder: RailPackLadder, datum: DisplayInput.Datum, inputsSHA256: [UInt8],
        progress: ((_ level: Int, _ of: Int) -> Void)? = nil
    ) throws -> RailPackSource {
        guard topology.region == region else {
            throw Failure.regionMismatch(topology: topology.region, requested: region)
        }
        let network = display.network
        let (slots, lines) = try layout(display: display, topology: topology)
        let keep = keepMeasures(slots: slots, network: network)
        let chainIndexOfInput = Dictionary(grouping: slots.indices, by: { slots[$0].inputIndex })

        var partSpansByInput: [Int: [DisplayInput.DaySpan?]] = [:]
        for info in display.lines { for fragment in info.fragments { partSpansByInput[fragment.inputIndex] = fragment.partSpans } }
        func partSpans(of input: Int) -> [DisplayInput.DaySpan?] { partSpansByInput[input] ?? [] }

        var groups: [RailPackGroup] = []
        var groupIndex: [GroupKey: UInt16] = [:]
        func group(_ key: GroupKey) -> UInt16 {
            if let index = groupIndex[key] { return index }
            let index = UInt16(groups.count)
            groups.append(RailPackGroup(
                colourLight: key.light, colourDark: key.dark, tierMin: key.tierMin, tierMax: key.tierMax,
                styleClass: key.style, category: 0))
            groupIndex[key] = index
            return index
        }
        var spans: [RailPackSpan] = []
        var spanIndex: [DisplayInput.DaySpan: UInt16] = [:]
        func span(_ value: DisplayInput.DaySpan?) -> UInt16 {
            guard let value else { return RailPackFormat.noSpan }
            if let index = spanIndex[value] { return index }
            let index = UInt16(spans.count)
            spans.append(RailPackSpan(fromDay: value.fromDay, toDay: value.toDay))
            spanIndex[value] = index
            return index
        }

        var levels: [RailPackLevelSource] = []
        for level in 0..<ladder.levelCount {
            progress?(level, ladder.levelCount)
            let mpp = ladder.mapPointsPerPoint(level: level)
            let frame = try frame(for: ladder, level: level, datumToken: datum.rawValue)
            let baked = NetworkStrokeBake.thinned(
                try NetworkStrokeBake.bake(network, level: frame), tolerance: RailStrokeTokens.packThinTolerance, keep: keep)
            let quantum = RailPackFormat.quantum(mapPointsPerPoint: mpp)
            let laneBucket = UInt8(LaneLOD.resolve(zoom: log2(StrokeProjection.worldSize / (256 * mpp)), previousBucket: nil).bucket)

            // Highest tier of any chain landlording a family group: where its tenants may stop falling
            // back. A group can have landlords of different tiers; the tenant's fallback ink stays until
            // the last of them draws, so that no stretch is left without ink in between.
            var landlordTier: [String: Int16] = [:]
            for (index, chain) in baked.chains.enumerated() {
                guard let slot = chainIndexOfInput[index]?.first else { continue }
                for run in chain.landlord {
                    guard let id = run.groupID else { continue }
                    landlordTier[id] = max(landlordTier[id] ?? .min, slots[slot].tier)
                }
            }

            var pieces: [RailPackPieceSource] = []
            var nodeSlots = [RailPackNodeSlot](repeating: .none, count: topology.nodes.count)
            var cutByInput: [Int: [PieceCutter.Piece]] = [:]
            for chainIndex in slots.indices {
                let slot = slots[chainIndex]
                let chain = baked.chains[slot.inputIndex]
                var cut: [PieceCutter.Piece]
                if let part = slot.part {
                    // One cut per fragment, shared by its parts.
                    if cutByInput[slot.inputIndex] == nil {
                        let dated = Set(partSpans(of: slot.inputIndex).enumerated().compactMap { $0.element == nil ? nil : $0.offset })
                        cutByInput[slot.inputIndex] = PieceCutter.cut(
                            chain, mapPointsPerPoint: mpp, dated: { dated.contains($0) })
                    }
                    cut = cutByInput[slot.inputIndex]!.filter { $0.part == part }
                } else {
                    cut = PieceCutter.cut(chain, mapPointsPerPoint: mpp, dated: { _ in slot.span != nil })
                }
                // A closed chain's last vertex is its first (the reader's wrap rule); snap the
                // few-quanta residue a lane offset can leave.
                if slot.closed, let start = cut.first?.line.points.first, let end = cut.last?.line.points.last,
                   hypot(start.x - end.x, start.y - end.y) <= 2 * quantum {
                    cut[cut.count - 1].line.points[cut[cut.count - 1].line.points.count - 1] = start
                }
                var ruler: PieceCutter.Polyline?
                if let part = slot.part {
                    if let run = chain.runs.first(where: {
                        $0.part == part && $0.measures.count == $0.vertices.count && $0.vertices.count >= 2
                    }) {
                        ruler = PieceCutter.Polyline(points: run.vertices, measures: run.measures)
                    }
                } else if chain.strokePoints.count >= 2 {
                    ruler = PieceCutter.Polyline(points: chain.strokePoints, measures: chain.strokeMeasures)
                }
                if !slot.nodes.isEmpty, let stroke = ruler {
                    let placed = PieceCutter.place(
                        nodes: slot.nodes.map { (id: $0.id, measure: $0.metres) }, stroke: stroke,
                        pieces: &cut, quantum: quantum)
                    for (id, found) in placed {
                        nodeSlots[id] = RailPackNodeSlot(
                            piece: UInt32(pieces.count + found.piece), vertex: UInt16(found.vertex))
                    }
                }
                let light = rgba(chain.colorHex), dark = rgba(chain.colorDarkHex)
                let spanID = span(slot.span)
                for piece in cut {
                    let key: GroupKey
                    switch piece.kind {
                    case .base:
                        key = GroupKey(
                            light: light, dark: dark, tierMin: slot.tier, tierMax: RailPackFormat.tierNoUpperLimit,
                            style: slot.span != nil ? RailPackFormat.StyleClass.historicalDashed.rawValue : 0)
                    case .withheld(let colour, let colourDark):
                        key = GroupKey(
                            light: rgba(colour), dark: rgba(colourDark), tierMin: slot.tier,
                            tierMax: RailPackFormat.tierNoUpperLimit,
                            style: RailPackFormat.StyleClass.withheldDashed.rawValue)
                    case .landlord(_, let colour, let colourDark):
                        key = GroupKey(
                            light: rgba(colour), dark: rgba(colourDark), tierMin: slot.tier,
                            tierMax: RailPackFormat.tierNoUpperLimit, style: 0)
                    case .fallback(let id, let colour, let colourDark):
                        let range = fallbackRange(tenantTier: slot.tier, landlordTier: landlordTier[id])
                        key = GroupKey(
                            light: rgba(colour), dark: rgba(colourDark), tierMin: range.min, tierMax: range.max, style: 0)
                    case .gap:
                        key = GroupKey(
                            light: light, dark: dark, tierMin: RailPackFormat.tierNeverDrawn,
                            tierMax: RailPackFormat.tierNeverDrawn, style: 0)
                    }
                    pieces.append(RailPackPieceSource(
                        chain: chainIndex, group: group(key), span: spanID, isLong: piece.isLong,
                        vertices: piece.line.points.map { RailPackPoint(x: $0.x, y: $0.y) }))
                }
            }
            levels.append(RailPackLevelSource(
                mapPointsPerPoint: mpp, laneBucket: laneBucket, pieces: pieces, nodes: nodeSlots))
        }
        progress?(ladder.levelCount, ladder.levelCount)
        return RailPackSource(
            datum: datum == .gcj02 ? .gcj02 : .wgs84, regionCode: region,
            displaySHA256: topology.displaySHA256, inputsSHA256: inputsSHA256,
            chainCount: slots.count, nodeCount: topology.nodes.count, lines: lines, groups: groups,
            spans: spans, levels: levels,
            closedChains: Set(slots.indices.filter { slots[$0].closed }))
    }
}
