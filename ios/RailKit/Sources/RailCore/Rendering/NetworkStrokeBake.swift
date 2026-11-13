import Foundation

/// Bake one whole region's network at one level: the entry a host tool calls.
///
/// "Whole network resident" is the point. In the app, joints and follows depend on which
/// neighbouring lines happen to be loaded; here every chain of the region is in the
/// `allLines` the engine sees, so a chain's joints, follows and family fallbacks no longer depend
/// on load order. Everything per chain runs through the same `StrokeBake` functions the app
/// calls (`StrokeBakeEqualityTests` pins the bake against `StrokeBake.prepare`).
///
/// The output is plain value geometry in map points: for each chain, the finished runs with the
/// attributes the piece cutter groups by (colour tokens, lane, source part, family window,
/// withheld), and the vertices stations sit on. It is not cut into tiles or quantised here.
public enum NetworkStrokeBake {

    /// The scale one level is drawn at (see `StrokeBake.Frame`).
    public typealias Level = StrokeBake.Frame

    /// A region's builder output: its chains, and the chain vertex index each station sits on.
    public struct Network: Sendable {
        public var lines: [StrokeLineInput]
        /// Keyed by `StrokeLineInput.id`.
        public var anchors: [String: [Int]]

        public init(lines: [StrokeLineInput], anchors: [String: [Int]]) {
            self.lines = lines
            self.anchors = anchors
        }
    }

    /// One finished polyline.
    public struct Run: Sendable, Equatable {
        /// For a non-continuous line, the index of the interval (in `StrokeLineInput.intervals`)
        /// the run was drawn from; 0 for a continuous chain.
        public var part: Int
        /// Metre range on the chain's stroke ruler (`Chain.strokeMeasures`) this run was cut from.
        /// Zero for a non-continuous line, which has no whole stroke.
        public var from: Double
        public var to: Double
        public var vertices: [StrokePoint]
        /// For a non-continuous line, the metre measure of every vertex on its part's own ruler
        /// (0 at the part's first vertex, then the topology ruler's step: 111,320 m per degree,
        /// longitude scaled by the cosine of the mean latitude). Empty for a continuous chain,
        /// whose measures are `Chain.strokeMeasures`.
        public var measures: [Double]

        public init(part: Int, from: Double = 0, to: Double = 0, vertices: [StrokePoint], measures: [Double] = []) {
            self.part = part
            self.from = from
            self.to = to
            self.vertices = vertices
            self.measures = measures
        }
    }

    /// A run that draws under a colour of its own: a withheld dash, or a family window.
    public struct TokenRun: Sendable, Equatable {
        /// The family group for a family run; nil for a withheld run.
        public var groupID: String?
        public var colorHex: String
        public var colorDarkHex: String
        /// Metre window on the chain's stroke ruler (`Chain.strokeMeasures`).
        public var from: Double
        public var to: Double
        public var vertices: [StrokePoint]
    }

    /// A vertex of the baked stroke a station sits on.
    public struct Node: Sendable, Equatable {
        /// The chain vertex index the station was requested at.
        public var anchor: Int
        public var point: StrokePoint
        /// The station's measure on the chain's stroke ruler (`Chain.strokeMeasures`).
        public var measure: Double
    }

    public struct Chain: Sendable, Equatable {
        /// Stable across bakes: `lineKey#chain` for a continuous chain, `lineKey@lane` otherwise.
        public var id: String
        public var lineID: String
        public var region: String
        public var continuous: Bool
        public var lane: Double
        public var colorHex: String
        public var colorDarkHex: String
        /// The chain's own ink, in part order.
        public var runs: [Run]
        /// Withheld spans, to draw dashed.
        public var withheld: [TokenRun]
        /// Stretches this chain draws in a landlord family's colour.
        public var landlord: [TokenRun]
        /// This chain's own geometry inside its tenant windows, the fallback ink.
        public var tenantFallback: [TokenRun]
        /// Station vertices, ascending by anchor.
        public var nodes: [Node]
        /// The whole built stroke in map points and its metre measure per vertex (empty for a
        /// non-continuous line). Every run, withheld span and family window above is a slice of
        /// this stroke, cut at its `from`/`to`; pieces that meet share their boundary vertex exactly.
        public var strokePoints: [StrokePoint]
        public var strokeMeasures: [Double]
    }

    public struct Baked: Sendable, Equatable {
        public var level: Level
        /// In input order, so equal input gives byte-equal output.
        public var chains: [Chain]
    }

    /// The cumulative metres along a non-continuous part's finished run: the topology ruler's step
    /// (`StrokeBake.joinedChainCoordinates`) over the run's own vertices, 0 at the first.
    static func partRuler(_ run: [Coordinate]) -> [Double] {
        var measures = [Double](repeating: 0, count: run.count)
        if run.count > 1 {
            for index in 1..<run.count {
                let a = run[index - 1], b = run[index]
                let lat = ((a.lat + b.lat) / 2) * Double.pi / 180
                measures[index] = measures[index - 1]
                    + hypot((b.lon - a.lon) * 111_320 * cos(lat), (b.lat - a.lat) * 111_320)
            }
        }
        return measures
    }

    public static func bake(_ network: Network, level: Level) throws -> Baked {
        let byID = Dictionary(network.lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let joined = JoinedChainCache()
        let pixels = ChainPixelCache(joinedChains: joined)
        let projection = ChainPixelCache.Projection(
            frameKey: level.key, datumToken: level.datumToken,
            mapPointsPerScreenPoint: level.mapPointsPerPoint, lodScale: level.laneScale)
        pixels.begin(projection)
        let reader = ChainPixelReader(cache: pixels, projection: projection)
        let junctions = JunctionCandidateIndex(byID, chains: joined)

        // Strokes first: a family owner built while preparing a tenant is recorded here too, and
        // reused, never rebuilt, when its own turn comes.
        var strokes: [String: StrokeBake.Build] = [:]
        for line in network.lines where line.continuous {
            try Task.checkCancellation()
            if strokes[line.id] != nil { continue }
            strokes[line.id] = try StrokeBake.strokeBuild(
                for: line, anchors: network.anchors[line.id] ?? [], canonical: { byID[$0] },
                chains: reader, mapPointsPerPoint: level.mapPointsPerPoint, scale: level.scale,
                laneScale: level.laneScale, junctionCandidates: junctions)
        }
        func points(_ coordinates: [Coordinate]) -> [StrokePoint] {
            coordinates.map(StrokeProjection.point)
        }
        var chains: [Chain] = []
        chains.reserveCapacity(network.lines.count)
        for line in network.lines {
            try Task.checkCancellation()
            let stroke = strokes[line.id]
            var runs: [Run] = []
            if line.continuous {
                let finished = try StrokeBake.finishedRuns(
                    stroke?.runs ?? line.intervals, line: line, frame: level)
                let ranges = stroke?.runRanges ?? []
                precondition(ranges.isEmpty || ranges.count == finished.count, "run ranges follow the runs")
                for (index, run) in finished.enumerated() {
                    runs.append(Run(
                        part: 0, from: ranges.isEmpty ? 0 : ranges[index].from,
                        to: ranges.isEmpty ? 0 : ranges[index].to, vertices: points(run)))
                }
            } else {
                for (index, interval) in line.intervals.enumerated() {
                    for run in try StrokeBake.finishedRuns([interval], line: line, frame: level) {
                        runs.append(Run(part: index, vertices: points(run), measures: partRuler(run)))
                    }
                }
            }
            var withheld: [TokenRun] = []
            var landlord: [TokenRun] = []
            var fallback: [TokenRun] = []
            var nodes: [Node] = []
            var strokePoints: [StrokePoint] = []
            var strokeMeasures: [Double] = []
            if let stroke {
                strokePoints = stroke.stroke.points.map {
                    StrokeProjection.point(StrokeBake.coordinate(of: $0, mapPointsPerPoint: level.mapPointsPerPoint))
                }
                strokeMeasures = stroke.stroke.measures
                for run in stroke.withheldRuns {
                    withheld.append(TokenRun(
                        groupID: nil, colorHex: run.colorHex, colorDarkHex: run.colorDarkHex,
                        from: run.from, to: run.to, vertices: points(run.coordinates)))
                }
                let built = try StrokeBake.familyGeometry(
                    for: line, stroke: stroke, strokes: &strokes, cachedStrokes: [:], allLines: byID,
                    anchors: network.anchors, chains: reader, frame: level, junctionCandidates: junctions)
                for key in built.families.keys.sorted() {
                    let family = built.families[key]!
                    for (index, chunk) in family.coordinateChunks.enumerated() {
                        landlord.append(TokenRun(
                            groupID: key, colorHex: family.colorHex, colorDarkHex: family.colorDarkHex,
                            from: family.chunkWindows[index].from, to: family.chunkWindows[index].to,
                            vertices: points(chunk)))
                    }
                }
                for item in built.fallbacks {
                    for (index, chunk) in item.family.coordinateChunks.enumerated() {
                        fallback.append(TokenRun(
                            groupID: item.window.groupID, colorHex: item.family.colorHex,
                            colorDarkHex: item.family.colorDarkHex,
                            from: item.family.chunkWindows[index].from, to: item.family.chunkWindows[index].to,
                            vertices: points(chunk)))
                    }
                }
                // The slot an anchor index was requested in (the last, as `strokeBuild` keeps).
                var slotOf: [Int: Int] = [:]
                for (slot, index) in (network.anchors[line.id] ?? []).enumerated()
                where slot < stroke.stroke.anchors.count && slot < stroke.stroke.anchorMeasures.count {
                    slotOf[index] = slot
                }
                nodes = stroke.anchors.keys.sorted().map {
                    Node(anchor: $0, point: StrokeProjection.point(stroke.anchors[$0]!),
                         measure: slotOf[$0].map { stroke.stroke.anchorMeasures[$0] } ?? 0)
                }
            }
            chains.append(Chain(
                id: line.id, lineID: line.lineID, region: line.region, continuous: line.continuous,
                lane: line.lane, colorHex: line.colorHex, colorDarkHex: line.colorDarkHex,
                runs: runs, withheld: withheld, landlord: landlord, tenantFallback: fallback, nodes: nodes,
                strokePoints: strokePoints, strokeMeasures: strokeMeasures))
        }
        return Baked(level: level, chains: chains)
    }
}
