import Foundation

/// The pack's thinning stage (docs/maintenance/2026-11-13-rail-pack-size-design.md, section 4.2).
///
/// The stroke engine never simplifies a continuous chain at the level's scale, so a baked level
/// carries the whole survey (tens of vertices per point of drawn line at low zoom) and a spline
/// sample every degree or two at high zoom. `thinned` runs the engine's own Douglas-Peucker
/// (`ContinuousStroke.simplifySpan`, the one implementation) over every stroke at the level's
/// scale, so a stored vertex is at most `tolerance` points from the engine's stroke.
///
/// Forced vertices, never dropped: the two ends of every stroke or run, every measure in `keep`
/// (station nodes), and every `from` and `to` of a run, withheld, landlord or tenant-fallback
/// window. A forced measure with no vertex gets one, interpolated on the full stroke, so node and
/// attribute boundaries sit exactly where the engine's stroke puts them.
///
/// A coincidence pass keeps lines that lie on each other coincident: where another stroke keeps a
/// vertex in a one-quantum cell, a stroke that has none in that cell keeps its first vertex there
/// (and is simplified again between its kept vertices, so the tolerance holds everywhere).
///
/// Only the whole stroke of a continuous chain (and the runs of a non-continuous line) is thinned.
/// The per-run `vertices` of a continuous chain stay as the engine built them: the pack cutter
/// reads the stroke and the metre windows, never those arrays.
public extension NetworkStrokeBake {

    /// Which stroke a `keep` list belongs to: the chain, and for a non-continuous line its part
    /// (the interval index of `Run.part`); part 0 for a continuous chain.
    struct PartKey: Hashable, Sendable {
        public var chainID: String
        public var part: Int
        public init(chainID: String, part: Int) {
            self.chainID = chainID
            self.part = part
        }
    }

    /// - Parameters:
    ///   - tolerance: points of the level (`RailStrokeTokens.packThinTolerance`).
    ///   - keep: extra measures that must stay vertices, on the stroke's ruler (`Chain.strokeMeasures`
    ///     for a continuous chain, `Run.measures` for a part of a non-continuous line).
    static func thinned(_ baked: Baked, tolerance: Double, keep: [PartKey: [Double]] = [:]) -> Baked {
        let mpp = baked.level.mapPointsPerPoint
        let scale = 1 / mpp
        let toleranceSquared = tolerance * tolerance
        let cell = mpp * RailStrokeTokens.simplifyTolerance

        // One unit per stroke: a continuous chain's whole stroke, or one run of a non-continuous line.
        struct Unit {
            var chain: Int
            var run: Int?
            var points: [StrokePoint]
            var measures: [Double]
            var kept: [Bool]
        }

        /// Douglas-Peucker between every pair of consecutive kept vertices of `kept`.
        func simplify(_ points: [StrokePoint], _ kept: inout [Bool]) {
            let scaled = points.map { ContinuousStroke.Point(x: $0.x * scale, y: $0.y * scale) }
            var spanStart = 0
            for index in 1..<kept.count where kept[index] {
                ContinuousStroke.simplifySpan(scaled, spanStart, index, toleranceSquared, &kept)
                spanStart = index
            }
        }

        func thin(_ points: [StrokePoint], _ measures: [Double], forced: [Double], chain: Int, run: Int?) -> Unit {
            let (all, allMeasures, flags) = augmented(points, measures, forced: forced)
            var kept = flags
            kept[0] = true
            kept[kept.count - 1] = true
            simplify(all, &kept)
            return Unit(chain: chain, run: run, points: all, measures: allMeasures, kept: kept)
        }

        var units: [Unit] = []
        for (chainIndex, chain) in baked.chains.enumerated() {
            if chain.continuous {
                guard chain.strokePoints.count >= 2, chain.strokePoints.count == chain.strokeMeasures.count else { continue }
                var forced = keep[PartKey(chainID: chain.id, part: 0)] ?? []
                for run in chain.runs { forced.append(run.from); forced.append(run.to) }
                for run in chain.withheld + chain.landlord + chain.tenantFallback {
                    forced.append(run.from)
                    forced.append(run.to)
                }
                units.append(thin(chain.strokePoints, chain.strokeMeasures, forced: forced, chain: chainIndex, run: nil))
            } else {
                for (runIndex, run) in chain.runs.enumerated() where run.vertices.count >= 2 {
                    let measures = run.measures.count == run.vertices.count ? run.measures : cumulative(run.vertices)
                    units.append(thin(
                        run.vertices, measures, forced: keep[PartKey(chainID: chain.id, part: run.part)] ?? [],
                        chain: chainIndex, run: runIndex))
                }
            }
        }

        // Coincidence: the cell of every kept vertex and which stroke holds it (-2: several).
        func key(_ p: StrokePoint) -> UInt64 {
            let x = UInt64(max(0, min((p.x / cell).rounded(), 4_294_967_295)))
            let y = UInt64(max(0, min((p.y / cell).rounded(), 4_294_967_295)))
            return x << 32 | y
        }
        var owner: [UInt64: Int32] = [:]
        for (index, unit) in units.enumerated() {
            for (i, p) in unit.points.enumerated() where unit.kept[i] {
                let k = key(p)
                if let existing = owner[k] {
                    if existing != Int32(index) { owner[k] = -2 }
                } else {
                    owner[k] = Int32(index)
                }
            }
        }
        for index in units.indices {
            var own = Set<UInt64>()
            for (i, p) in units[index].points.enumerated() where units[index].kept[i] { own.insert(key(p)) }
            var promoted = false
            for i in units[index].points.indices where !units[index].kept[i] {
                let k = key(units[index].points[i])
                guard !own.contains(k), let other = owner[k], other != Int32(index) else { continue }
                units[index].kept[i] = true
                own.insert(k)
                promoted = true
            }
            // A promoted vertex splits a span, so the chords on both sides change: simplify again
            // between the kept vertices (promoted ones now forced) to hold the tolerance everywhere.
            if promoted { simplify(units[index].points, &units[index].kept) }
        }

        var chains = baked.chains
        for unit in units {
            var points: [StrokePoint] = [], measures: [Double] = []
            for i in unit.points.indices where unit.kept[i] {
                points.append(unit.points[i])
                measures.append(unit.measures[i])
            }
            if let run = unit.run {
                chains[unit.chain].runs[run].vertices = points
                chains[unit.chain].runs[run].measures = measures
            } else {
                chains[unit.chain].strokePoints = points
                chains[unit.chain].strokeMeasures = measures
            }
        }
        return Baked(level: baked.level, chains: chains)
    }

    private static func cumulative(_ points: [StrokePoint]) -> [Double] {
        var measures = [Double](repeating: 0, count: points.count)
        for i in points.indices.dropFirst() {
            measures[i] = measures[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return measures
    }

    /// The stroke with a vertex at every forced measure (interpolated where none exists) and a flag
    /// on the forced vertices. Measures outside the stroke are ignored.
    private static func augmented(
        _ points: [StrokePoint], _ measures: [Double], forced: [Double]
    ) -> (points: [StrokePoint], measures: [Double], flags: [Bool]) {
        let low = measures[0], high = measures[measures.count - 1]
        let wanted = Set(forced.filter { $0.isFinite && $0 > low && $0 < high }).sorted()
        var outPoints: [StrokePoint] = [], outMeasures: [Double] = [], flags: [Bool] = []
        var next = 0
        for index in points.indices {
            // Forced measures strictly inside the segment that ends at this vertex.
            while index > 0, next < wanted.count, wanted[next] < measures[index] {
                let m = wanted[next]
                next += 1
                guard m > measures[index - 1] else {
                    if m == measures[index - 1] { flags[flags.count - 1] = true }
                    continue
                }
                let t = (m - measures[index - 1]) / (measures[index] - measures[index - 1])
                let p = points[index - 1], q = points[index]
                outPoints.append(StrokePoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t))
                outMeasures.append(m)
                flags.append(true)
            }
            var isForced = index == 0 || index == points.count - 1
            if next < wanted.count, wanted[next] == measures[index] {
                isForced = true
                next += 1
            }
            outPoints.append(points[index])
            outMeasures.append(measures[index])
            flags.append(isForced)
        }
        return (outPoints, outMeasures, flags)
    }
}
