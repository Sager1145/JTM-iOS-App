import Foundation
import RailCore
import Testing
@testable import RailBakeKit

/// Bake -> write -> open with the reader -> compare with the bake core, on the committed stroke
/// fixture (real hk and mo, a jp selection with follows, lanes, withheld spans and family windows)
/// and on small synthetic chains.
@Suite("PackAssembler")
struct PackAssemblerTests {

    static let levels = [8, 16, 24, 34]  // zoom 4, 8, 12, 17

    /// The fixture region, with a synthetic topology: one node per baked station vertex, placed at the
    /// station's measure on the bake at `referenceLevel`.
    static func fixtureRegion(
        _ name: String, directory: URL, referenceLevel k: Int
    ) throws -> (DisplayInput.Region, PackTopology) {
        let display = try DisplayInput.load(region: name, from: directory)
        let ladder = try PackBake.ladder(levels: [k])
        let baked = try NetworkStrokeBake.bake(
            display.network, level: try PackAssembler.frame(for: ladder, level: 0, datumToken: "wgs84"))
        var lines: [PackTopology.Line] = []
        var nodes: [PackTopology.Node] = []
        for info in display.lines {
            let first = nodes.count
            var flatPart = 0
            for fragment in info.fragments {
                if fragment.continuous {
                    for node in baked.chains[fragment.inputIndex].nodes {
                        nodes.append(PackTopology.Node(chain: fragment.chainNumber, metres: node.measure))
                    }
                    continue
                }
                // A non-continuous line: nodes at the start, middle and end of each part's ruler, the
                // part addressed by its flat number.
                for part in display.network.lines[fragment.inputIndex].intervals.indices {
                    if let run = baked.chains[fragment.inputIndex].runs.first(where: { $0.part == part }),
                       let total = run.measures.last, total > 0 {
                        for fraction in [0.0, 0.5, 1.0] {
                            nodes.append(PackTopology.Node(chain: flatPart, metres: total * fraction))
                        }
                    }
                    flatPart += 1
                }
            }
            lines.append(PackTopology.Line(id: info.id, firstNode: first, nodeCount: nodes.count - first))
        }
        let topology = PackTopology(
            region: name, displaySHA256: [UInt8](repeating: 0x11, count: 32), lines: lines, nodes: nodes)
        return (display, topology)
    }

    static func assemble(
        _ region: DisplayInput.Region, _ topology: PackTopology, levels: [Int], datum: DisplayInput.Datum = .wgs84
    ) throws -> RailPackSource {
        try PackAssembler.assemble(
            region: topology.region, display: region, topology: topology, ladder: PackBake.ladder(levels: levels),
            datum: datum, inputsSHA256: [UInt8](repeating: 0x22, count: 32))
    }

    static func reader(_ source: RailPackSource) throws -> RailPackReader {
        try RailPackReader(data: RailPackWriter.write(source))
    }

    static func pieces(of chain: Int, level: Int, reader: RailPackReader) throws -> [[RailPackPoint]] {
        try reader.pieceRange(level: level, chain: chain).map { piece in
            var points: [RailPackPoint] = []
            try reader.appendVertices(level: level, piece: piece, to: &points)
            return points
        }
    }

    /// Distance from each of `points` (in order along the polyline) to the polyline: a window of segments
    /// around the previous nearest one first, the whole polyline when that finds nothing within `slack`
    /// (a loop, or a point that backtracks).
    static func distances(_ points: [RailPackPoint], toPolyline line: [StrokePoint], slack: Double = 1e-3) -> [Double] {
        var result: [Double] = []
        var segment = 0
        for p in points {
            guard line.count >= 2 else { result.append(.infinity); continue }
            var nearest = Double.infinity, nearestSegment = segment
            func search(_ low: Int, _ high: Int) {
                for k in low...high {
                    let d = distance(p, from: line[k], to: line[k + 1])
                    if d < nearest { nearest = d; nearestSegment = k }
                }
            }
            search(max(segment - 200, 0), min(segment + 200, line.count - 2))
            if nearest > slack { search(0, line.count - 2) }
            segment = nearestSegment
            result.append(nearest)
        }
        return result
    }

    static func distance(_ p: RailPackPoint, toPolyline line: [StrokePoint]) -> Double {
        var nearest = Double.infinity
        for (s, e) in zip(line, line.dropFirst()) {
            let dx = e.x - s.x, dy = e.y - s.y
            let l2 = dx * dx + dy * dy
            let t = l2 > 0 ? min(max(((p.x - s.x) * dx + (p.y - s.y) * dy) / l2, 0), 1) : 0
            nearest = min(nearest, hypot(s.x + dx * t - p.x, s.y + dy * t - p.y))
        }
        return nearest
    }

    static func distance(_ p: RailPackPoint, from s: StrokePoint, to e: StrokePoint) -> Double {
        let dx = e.x - s.x, dy = e.y - s.y
        let l2 = dx * dx + dy * dy
        let t = l2 > 0 ? min(max(((p.x - s.x) * dx + (p.y - s.y) * dy) / l2, 0), 1) : 0
        return hypot(s.x + dx * t - p.x, s.y + dy * t - p.y)
    }

    @Test("a level's stroke frame is the app's frame at the same scale (ladder zoom + 1)")
    func frames() throws {
        let ladder = RailPackLadder.default
        for level in 0..<ladder.levelCount {
            let frame = try PackAssembler.frame(for: ladder, level: level, datumToken: "")
            let expected = NetworkStrokeBake.Level(appZoom: ladder.zooms[level] + 1)
            #expect(abs(frame.mapPointsPerPoint - ladder.mapPointsPerPoint(level: level)) < 1e-9 * frame.mapPointsPerPoint)
            #expect(frame.laneScale == expected.laneScale)
            #expect(abs(frame.scale - expected.scale) < 1e-9)
        }
    }

    /// The engine's bake at pack level `level` and the same bake after the pack's thinning stage.
    static func bakes(
        _ display: DisplayInput.Region, _ topology: PackTopology, reader: RailPackReader, level: Int
    ) throws -> (full: NetworkStrokeBake.Baked, thinned: NetworkStrokeBake.Baked) {
        let frame = try PackAssembler.frame(for: reader.ladder, level: level, datumToken: "wgs84")
        let full = try NetworkStrokeBake.bake(display.network, level: frame)
        let layout = try PackAssembler.layout(display: display, topology: topology)
        let thinned = NetworkStrokeBake.thinned(
            full, tolerance: RailStrokeTokens.packThinTolerance,
            keep: PackAssembler.keepMeasures(slots: layout.slots, network: display.network))
        return (full, thinned)
    }

    @Test("every line's geometry at every level equals the thinned bake within half a quantum and the full bake within four")
    func equalsBakeCore() throws {
        let directory = try RegionBakeTests.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var sawWithheld = false, sawFamily = false, sawLong = false, sawNode = false, sawMultiPiece = false
        for name in ["hk", "jp", "mo"] {
            let (display, topology) = try Self.fixtureRegion(name, directory: directory, referenceLevel: 26)
            let source = try Self.assemble(display, topology, levels: Self.levels)
            let reader = try Self.reader(source)
            try reader.validateContents()
            #expect(reader.header.levelCount == Self.levels.count)
            #expect(reader.header.lineCount == display.lines.count)
            for (level, k) in Self.levels.enumerated() {
                let (full, baked) = try Self.bakes(display, topology, reader: reader, level: level)
                let quantum = RailPackFormat.quantum(mapPointsPerPoint: reader.levels[level].mapPointsPerPoint)
                let half = quantum / 2 * (1 + 1e-6) + 1e-6
                for (lineIndex, info) in display.lines.enumerated() {
                    var chain = Int(try reader.line(lineIndex).firstChain)
                    for fragment in info.fragments {
                        let bakedChain = baked.chains[fragment.inputIndex]
                        let fullChain = full.chains[fragment.inputIndex]
                        let slots: [Int?] = fragment.continuous ? [nil] : display.network.lines[fragment.inputIndex].intervals.indices.map { Optional($0) }
                        for part in slots {
                            let pieces = try Self.pieces(of: chain, level: level, reader: reader)
                            chain += 1
                            let all = pieces.flatMap { $0 }
                            if pieces.count > 1 { sawMultiPiece = true }
                            // The pieces of one chain meet end to end.
                            for (a, b) in zip(pieces, pieces.dropFirst()) {
                                #expect(abs(a.last!.x - b.first!.x) < 1e-6 && abs(a.last!.y - b.first!.y) < 1e-6,
                                        "\(name) \(bakedChain.id) k\(k): pieces do not share a boundary vertex")
                            }
                            if fragment.continuous, bakedChain.strokePoints.count >= 2 {
                                // Every stroke vertex is in the pack chain, in order, within half a quantum.
                                var cursor = 0
                                for v in bakedChain.strokePoints {
                                    while cursor < all.count,
                                          abs(all[cursor].x - v.x) > half || abs(all[cursor].y - v.y) > half { cursor += 1 }
                                    #expect(cursor < all.count, "\(name) \(bakedChain.id) k\(k): stroke vertex missing")
                                    if cursor >= all.count { break }
                                }
                                // Every pack vertex lies on the stroke (inserted vertices are collinear).
                                let off = Self.distances(all, toPolyline: bakedChain.strokePoints).filter { $0 > quantum }
                                #expect(off.isEmpty, "\(name) \(bakedChain.id) k\(k): \(off.count) vertices off the stroke")
                                // The full bake's every vertex is within four quanta of the pack chain (thinning
                                // tolerance 3 quanta, rounding half a quantum, and the bound's own slack).
                                let fullPoints = fullChain.strokePoints.map { RailPackPoint(x: $0.x, y: $0.y) }
                                let packLine = all.map { StrokePoint(x: $0.x, y: $0.y) }
                                if packLine.count >= 2 {
                                    let far = Self.distances(fullPoints, toPolyline: packLine).filter { $0 > 4 * quantum }
                                    #expect(far.isEmpty, "\(name) \(bakedChain.id) k\(k): \(far.count) full-bake vertices more than 4 quanta from the pack")
                                }
                                // Ends agree.
                                let s = bakedChain.strokePoints
                                #expect(abs(all[0].x - s[0].x) <= half && abs(all[0].y - s[0].y) <= half)
                                #expect(abs(all.last!.x - s.last!.x) <= half && abs(all.last!.y - s.last!.y) <= half)
                            } else {
                                let runs = bakedChain.runs.filter { $0.part == (part ?? 0) }.flatMap(\.vertices)
                                var cursor = 0
                                for v in runs {
                                    var found = false
                                    var probe = max(cursor - 1, 0)
                                    while probe < all.count {
                                        if abs(all[probe].x - v.x) <= half && abs(all[probe].y - v.y) <= half { found = true; cursor = probe; break }
                                        probe += 1
                                    }
                                    if !found { found = all.contains { abs($0.x - v.x) <= half && abs($0.y - v.y) <= half } }
                                    #expect(found, "\(name) \(bakedChain.id) k\(k): run vertex missing")
                                }
                                if runs.count >= 2 {
                                    let off = Self.distances(all, toPolyline: runs).filter { $0 > quantum }
                                    #expect(off.isEmpty, "\(name) \(bakedChain.id) k\(k): \(off.count) vertices off the run")
                                    let fullRun = fullChain.runs.filter { $0.part == (part ?? 0) }.flatMap(\.vertices)
                                    let packLine = all.map { StrokePoint(x: $0.x, y: $0.y) }
                                    if packLine.count >= 2 {
                                        let far = Self.distances(fullRun.map { RailPackPoint(x: $0.x, y: $0.y) }, toPolyline: packLine)
                                            .filter { $0 > 4 * quantum }
                                        #expect(far.isEmpty, "\(name) \(bakedChain.id) k\(k): \(far.count) full-run vertices more than 4 quanta from the pack")
                                    }
                                }
                            }
                            for piece in try reader.pieceRange(level: level, chain: chain - 1) {
                                let row = try reader.piece(level: level, index: piece)
                                let group = try reader.group(Int(row.group))
                                if group.styleClass == RailPackFormat.StyleClass.withheldDashed.rawValue { sawWithheld = true }
                                if row.isLong { sawLong = true }
                            }
                        }
                    }
                }
                // A family stretch is in the pack when a piece draws in a colour that is not its own line's.
                for (lineIndex, info) in display.lines.enumerated() {
                    let line = try reader.line(lineIndex)
                    for chain in Int(line.firstChain)..<(Int(line.firstChain) + Int(line.chainCount)) {
                        let own = PackAssembler.rgba(baked.chains[info.fragments[0].inputIndex].colorHex)
                        for piece in try reader.pieceRange(level: level, chain: chain) {
                            let group = try reader.group(Int(try reader.piece(level: level, index: piece).group))
                            if group.colourLight != own, group.styleClass == 0,
                               group.tierMin != RailPackFormat.tierNeverDrawn { sawFamily = true }
                        }
                    }
                }
                for slot in 0..<topology.nodes.count where !(try reader.nodeSlot(level: level, node: slot).isNone) {
                    sawNode = true
                }
            }
        }
        #expect(sawWithheld && sawFamily && sawLong && sawNode && sawMultiPiece)
    }

    @Test("a node sits on the vertex the bake put its station on, on every kind of line")
    func nodesMatchTheBake() throws {
        let directory = try RegionBakeTests.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["hk", "jp"] {
            let (display, topology) = try Self.fixtureRegion(name, directory: directory, referenceLevel: 26)
            for k in [10, 26] {
                let reader = try Self.reader(try Self.assemble(display, topology, levels: [k]))
                try reader.validateContents()
                let (_, baked) = try Self.bakes(display, topology, reader: reader, level: 0)
                let quantum = RailPackFormat.quantum(mapPointsPerPoint: reader.levels[0].mapPointsPerPoint)
                let half = quantum / 2 * (1 + 1e-6) + 1e-6
                var checkedContinuous = 0, checkedParts = 0
                for (lineIndex, info) in display.lines.enumerated() {
                    let line = try reader.line(lineIndex)
                    var ordinal = 0
                    var flatPart = 0
                    for fragment in info.fragments {
                        let bakedChain = baked.chains[fragment.inputIndex]
                        if fragment.continuous {
                            for node in bakedChain.nodes {
                                let slot = try reader.nodeSlot(level: 0, node: Int(line.firstNode) + ordinal)
                                ordinal += 1
                                #expect(!slot.isNone)
                                var points: [RailPackPoint] = []
                                try reader.appendVertices(level: 0, piece: Int(slot.piece), to: &points)
                                let at = points[Int(slot.vertex)]
                                #expect(abs(at.x - node.point.x) <= half && abs(at.y - node.point.y) <= half)
                                checkedContinuous += 1
                            }
                            continue
                        }
                        for part in display.network.lines[fragment.inputIndex].intervals.indices {
                            defer { flatPart += 1 }
                            guard let run = bakedChain.runs.first(where: { $0.part == part }), let total = run.measures.last, total > 0
                            else { continue }
                            let stroke = PieceCutter.Polyline(points: run.vertices, measures: run.measures)
                            for fraction in [0.0, 0.5, 1.0] {
                                let metres = try #require(topology.nodes[Int(line.firstNode) + ordinal].metres)
                                let slot = try reader.nodeSlot(level: 0, node: Int(line.firstNode) + ordinal)
                                ordinal += 1
                                #expect(!slot.isNone, "\(name) \(bakedChain.id) part \(part): node without a slot")
                                if slot.isNone { continue }
                                // The node's piece belongs to this part's chain and the vertex is the part's
                                // position at that metre on its own ruler.
                                #expect(try reader.chain(level: 0, ofPiece: Int(slot.piece)) == Int(line.firstChain) + flatPart)
                                var points: [RailPackPoint] = []
                                try reader.appendVertices(level: 0, piece: Int(slot.piece), to: &points)
                                let at = points[Int(slot.vertex)]
                                let expected = PieceCutter.point(on: stroke, at: metres)
                                #expect(abs(at.x - expected.x) <= quantum && abs(at.y - expected.y) <= quantum,
                                        "\(name) \(bakedChain.id) part \(part) at \(fraction)")
                                checkedParts += 1
                            }
                        }
                    }
                }
                if name == "jp" { #expect(checkedContinuous > 20, "\(name) k\(k): \(checkedContinuous) continuous nodes") }
                if name == "hk" { #expect(checkedContinuous == 0 && checkedParts > 20, "\(name) k\(k): \(checkedParts) part nodes") }
            }
        }
    }

    @Test("a trip between two stations of a non-continuous line has a vertex range on the line itself")
    func tripOnANonContinuousLine() throws {
        let directory = try RegionBakeTests.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (display, topology) = try Self.fixtureRegion("hk", directory: directory, referenceLevel: 26)
        let levels = [10, 26]
        let reader = try Self.reader(try Self.assemble(display, topology, levels: levels))
        var trips = 0
        for level in levels.indices {
            let quantum = RailPackFormat.quantum(mapPointsPerPoint: reader.levels[level].mapPointsPerPoint)
            for lineIndex in 0..<reader.header.lineCount {
                let line = try reader.line(lineIndex)
                guard line.nodeCount >= 3 else { continue }
                // Nodes of one part come in threes (start, middle, end): the first part's start and end.
                let from = Int(line.firstNode), to = Int(line.firstNode) + 2
                let result = try reader.vertexRanges(level: level, fromNode: from, toNode: to)
                #expect(!result.reversed)
                let a = try reader.nodeSlot(level: level, node: from), b = try reader.nodeSlot(level: level, node: to)
                let first = try #require(result.ranges.first), last = try #require(result.ranges.last)
                #expect(first.piece == a.piece && first.first == Int(a.vertex))
                #expect(last.piece == b.piece && last.last == Int(b.vertex))
                // The range is contiguous along the part: consecutive pieces share their end vertex.
                var length = 0.0
                var previous: RailPackPoint?
                for range in result.ranges {
                    var points: [RailPackPoint] = []
                    try reader.appendVertices(level: level, piece: Int(range.piece), first: range.first, last: range.last, to: &points)
                    if let previous, let start = points.first {
                        #expect(abs(previous.x - start.x) <= quantum && abs(previous.y - start.y) <= quantum)
                    }
                    for (p, q) in zip(points, points.dropFirst()) { length += hypot(p.x - q.x, p.y - q.y) }
                    previous = points.last
                }
                #expect(length > 0, "a trip from the start to the end of a part draws something")
                // Reversed: the same ranges walked the other way.
                let back = try reader.vertexRanges(level: level, fromNode: to, toNode: from)
                #expect(back.reversed && back.ranges == result.ranges)
                trips += 1
            }
        }
        #expect(trips >= 2)
    }

    @Test("two bakes of one input are byte for byte equal")
    func deterministic() throws {
        let directory = try RegionBakeTests.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (display, topology) = try Self.fixtureRegion("jp", directory: directory, referenceLevel: 26)
        let a = try RailPackWriter.write(try Self.assemble(display, topology, levels: Self.levels))
        let b = try RailPackWriter.write(try Self.assemble(display, topology, levels: Self.levels))
        #expect(a == b)
        let again = try DisplayInput.load(region: "jp", from: directory)
        #expect(a == (try RailPackWriter.write(try Self.assemble(again, topology, levels: Self.levels))))
        let report = try PackReport(reader: RailPackReader(data: a))
        #expect(report.levels.count == Self.levels.count)
        #expect(report.fileBytes == a.count)
        #expect(report.totalVertices > 1000)
        #expect(try PackCompare.differences(RailPackReader(data: a), RailPackReader(data: b)).isEmpty)

        // Negative control: a compare that cannot see a moved vertex or a changed group proves nothing.
        var moved = try Self.assemble(display, topology, levels: Self.levels)
        let level = try #require(moved.levels.indices.last)
        let piece = try #require(moved.levels[level].pieces.indices.first { moved.levels[level].pieces[$0].vertices.count >= 2 })
        moved.levels[level].pieces[piece].vertices[0].x += 3 * RailPackFormat.quantum(mapPointsPerPoint: moved.levels[level].mapPointsPerPoint)
        let differences = try PackCompare.differences(RailPackReader(data: a), RailPackReader(data: RailPackWriter.write(moved)))
        #expect(differences.count == 1 && differences[0].contains("level \(level) piece \(piece)"), "\(differences)")
        var regrouped = try Self.assemble(display, topology, levels: Self.levels)
        regrouped.levels[0].pieces[0].group = regrouped.levels[0].pieces[0].group &+ 1
        #expect(try !PackCompare.differences(RailPackReader(data: a), RailPackReader(data: RailPackWriter.write(regrouped))).isEmpty)
    }

    @Test("at every level every line visible at its tier has ink, and the tenant fallback and its landlord hand over without a gap")
    func everyVisibleLineHasInk() throws {
        let directory = try RegionBakeTests.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var inked = 0
        for name in ["hk", "jp", "mo"] {
            let (display, topology) = try Self.fixtureRegion(name, directory: directory, referenceLevel: 26)
            let reader = try Self.reader(try Self.assemble(display, topology, levels: PackBake.defaultLevels))
            let lines = display.lines.map { (id: $0.id, tier: $0.tierQuarterZoom) }
            let missing = try PackInkCheck.missing(reader: reader, lines: lines)
            #expect(missing.isEmpty, "\(name): \(missing.prefix(5))")
            // The check has teeth: count the (level, line) pairs it examined.
            for level in 0..<reader.header.levelCount {
                inked += lines.filter { Double($0.tier) <= reader.ladder.appZoom(level: level) * 4 }.count
            }
        }
        #expect(inked > 500)
    }

    @Test("a tenant's fallback ink hands over to its landlords without a gap at any tier")
    func fallbackHandover() {
        let never = RailPackFormat.tierNeverDrawn, unlimited = RailPackFormat.tierNoUpperLimit
        // No landlord: the tenant draws from its own tier for ever.
        #expect(PackAssembler.fallbackRange(tenantTier: 20, landlordTier: nil) == (20, unlimited))
        // A landlord that appears later: fallback ink until it does.
        #expect(PackAssembler.fallbackRange(tenantTier: 20, landlordTier: 40) == (20, 40))
        // A landlord that is already drawing: the landlord's pieces are the ink.
        #expect(PackAssembler.fallbackRange(tenantTier: 40, landlordTier: 40) == (never, never))
        #expect(PackAssembler.fallbackRange(tenantTier: 60, landlordTier: 40) == (never, never))
        // For every tenant tier and every landlord tier set, at every tier from the tenant's own up,
        // either the fallback or some landlord draws. The landlord tier handed over is the highest
        // of the group's landlords, so no stretch is dark between the first and the last of them.
        for tenant in stride(from: Int16(0), through: 80, by: 4) {
            for landlords in [[Int16(40)], [24, 60], [60, 24], [8, 40, 72]] {
                let range = PackAssembler.fallbackRange(tenantTier: tenant, landlordTier: landlords.max())
                for tier in stride(from: tenant, through: 100, by: 4) {
                    let fallback = range.min != never && range.min <= tier && (range.max == unlimited || tier < range.max)
                    let landlord = landlords.contains { $0 <= tier }
                    #expect(fallback || landlord, "tenant \(tenant), landlords \(landlords), tier \(tier)")
                }
            }
        }
    }

    @Test("the ink check finds a line whose pieces stop drawing")
    func inkCheckFindsAGap() throws {
        let directory = try RegionBakeTests.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (display, topology) = try Self.fixtureRegion("jp", directory: directory, referenceLevel: 26)
        var source = try Self.assemble(display, topology, levels: [26])
        // Hide every group: nothing draws, so every visible line is reported.
        for index in source.groups.indices {
            source.groups[index].tierMin = RailPackFormat.tierNeverDrawn
            source.groups[index].tierMax = RailPackFormat.tierNeverDrawn
        }
        let reader = try Self.reader(source)
        let missing = try PackInkCheck.missing(reader: reader, lines: display.lines.map { (id: $0.id, tier: $0.tierQuarterZoom) })
        var expected = 0
        for offset in PackInkCheck.defaultOffsets {
            let visibility = reader.ladder.appZoom(level: 0) + offset
            expected += display.lines.filter { Double($0.tierQuarterZoom) <= visibility * 4 }.count
        }
        #expect(missing.count == expected)
        #expect(missing.count > 5)
    }

    @Test("a dated chain keeps every solid piece whole, with its span and a dashed-capable group")
    func datedChain() throws {
        let directory = try RegionBakeTests.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Self.fixtureRegion("jp", directory: directory, referenceLevel: 34)
        var display = fixture.0
        let topology = fixture.1
        let span = DisplayInput.DaySpan(fromDay: 100, toDay: 50_000)
        let target = try #require(display.lines.firstIndex { line in
            line.fragments.contains { $0.continuous && display.network.lines[$0.inputIndex].vertexCount > 300 }
        })
        for index in display.lines[target].fragments.indices where display.lines[target].fragments[index].continuous {
            display.lines[target].fragments[index].partSpans = display.lines[target].fragments[index].partSpans.map { _ in span }
        }
        let reader = try Self.reader(try Self.assemble(display, topology, levels: [34]))
        try reader.validateContents()
        let line = try reader.line(target)
        var datedPieces = 0
        for chain in Int(line.firstChain)..<(Int(line.firstChain) + Int(line.chainCount)) {
            for piece in try reader.pieceRange(level: 0, chain: chain) {
                let row = try reader.piece(level: 0, index: piece)
                #expect(row.span != RailPackFormat.noSpan)
                #expect(try reader.span(row.span) == RailPackSpan(fromDay: 100, toDay: 50_000))
                let group = try reader.group(Int(row.group))
                if group.styleClass == RailPackFormat.StyleClass.historicalDashed.rawValue {
                    #expect(row.isLong, "a dated solid piece is a long piece")
                    datedPieces += 1
                }
            }
        }
        #expect(datedPieces > 0)
    }

    @Test("a closed chain is flagged at every level and a wrapping span crosses the seam")
    func closedChain() throws {
        // A square loop of four intervals, closed on its first coordinate.
        let corners = [(139.700, 35.650), (139.720, 35.650), (139.720, 35.670), (139.700, 35.670), (139.700, 35.650)]
        let intervals = zip(corners, corners.dropFirst()).map { a, b in
            [Coordinate(lon: a.0, lat: a.1), Coordinate(lon: b.0, lat: b.1)]
        }
        let input = StrokeLineInput(
            id: "jp|loop#0", lineID: "loop", region: "jp", operatorName: nil, colorHex: "#ff0000",
            colorDarkHex: "#ff8888", lane: 0, continuous: true, totalMetres: 7_000, intervals: intervals)
        let network = NetworkStrokeBake.Network(lines: [input], anchors: ["jp|loop#0": [0, 1, 2, 3]])
        let info = DisplayInput.LineInfo(
            id: "loop", tierQuarterZoom: 36,
            fragments: [.init(inputIndex: 0, continuous: true, chainNumber: 0, partSpans: [nil])])
        let region = DisplayInput.Region(network: network, lines: [info])

        let ladder = try PackBake.ladder(levels: [10, 26])
        let reference = try NetworkStrokeBake.bake(
            network, level: try PackAssembler.frame(for: ladder, level: 1, datumToken: "wgs84"))
        let stroke = try #require(reference.chains.first)
        #expect(stroke.strokePoints.count >= 5)
        let total = try #require(stroke.strokeMeasures.last)
        // Four nodes: the start, two on the loop, one near the end.
        let topology = PackTopology(
            region: "jp", displaySHA256: [UInt8](repeating: 1, count: 32),
            lines: [.init(id: "loop", firstNode: 0, nodeCount: 4)],
            nodes: [0, 0.3, 0.7, 0.95].map { PackTopology.Node(chain: 0, metres: total * $0) })
        let source = try PackAssembler.assemble(
            region: "jp", display: region, topology: topology, ladder: ladder, datum: .wgs84,
            inputsSHA256: [UInt8](repeating: 2, count: 32))
        #expect(source.closedChains == [0])
        let reader = try Self.reader(source)
        try reader.validateContents()
        for level in 0..<2 {
            #expect(try reader.isClosed(level: level, chain: 0))
            let all = try Self.pieces(of: 0, level: level, reader: reader).flatMap { $0 }
            #expect(all.first == all.last, "a closed chain's last vertex is its first")
            // Forward trip across the seam: from the late node to the early node.
            let wrap = try reader.vertexRanges(level: level, fromNode: 3, toNode: 1, wraps: true)
            #expect(!wrap.reversed)
            let first = try #require(wrap.ranges.first), last = try #require(wrap.ranges.last)
            let slot3 = try reader.nodeSlot(level: level, node: 3), slot1 = try reader.nodeSlot(level: level, node: 1)
            #expect(first.piece == slot3.piece && first.first == Int(slot3.vertex))
            #expect(last.piece == slot1.piece && last.last == Int(slot1.vertex))
            // The seam vertex ends the first part and starts the second.
            let tail = try Self.pieces(of: 0, level: level, reader: reader)
            let endPiece = tail[tail.count - 1], startPiece = tail[0]
            #expect(endPiece.last == startPiece.first)
        }
    }

    @Test("a display line the topology does not know, or a topology of another region, is refused")
    func refusals() throws {
        let directory = try RegionBakeTests.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (display, topology) = try Self.fixtureRegion("hk", directory: directory, referenceLevel: 26)
        var missing = topology
        missing.lines.removeLast()
        #expect(throws: PackAssembler.Failure.self) { try Self.assemble(display, missing, levels: [26]) }
        var other = topology
        other.region = "mo"
        #expect(throws: PackAssembler.Failure.regionMismatch(topology: "mo", requested: "hk")) {
            try PackAssembler.assemble(
                region: "hk", display: display, topology: other, ladder: PackBake.ladder(levels: [26]),
                datum: .wgs84, inputsSHA256: [UInt8](repeating: 0, count: 32))
        }
    }
}
