import Foundation
import Testing
@testable import RailCore

/// The moved stroke engine against goldens captured from the code before it moved
/// (`Fixtures/README.md`). Every drawn chunk, family and fallback run, anchor and stroke
/// fingerprint of the fixture network, at five levels, plain and dated.
@Suite("StrokeBakeEquality")
struct StrokeBakeEqualityTests {

    struct Golden {
        var entries: [String: (count: Int, offset: Int)]
        var values: [Double]

        static func load() throws -> Golden {
            struct Index: Decodable {
                struct Item: Decodable { var k: String; var n: Int; var o: Int }
                var entries: [Item]
            }
            func inflate(_ name: String) throws -> Data {
                let packed = try Data(contentsOf: StrokeBakeFixtures.directory.appending(path: name))
                return try (packed as NSData).decompressed(using: .zlib) as Data
            }
            let index = try JSONDecoder().decode(
                Index.self, from: inflate("stroke-golden-index.json.deflate"))
            let raw = try inflate("stroke-golden.f64.deflate")
            let values = raw.withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
            var entries: [String: (count: Int, offset: Int)] = [:]
            for item in index.entries { entries[item.k] = (item.n, item.o) }
            return Golden(entries: entries, values: values)
        }

        func slice(_ key: String) -> [Double]? {
            guard let entry = entries[key] else { return nil }
            return Array(values[entry.offset..<(entry.offset + entry.count)])
        }
    }

    /// Records what the current engine produces under the same keys the capture used.
    struct Recorder {
        var recorded: [String: [Double]] = [:]
        mutating func record(_ key: String, _ numbers: [Double]) {
            #expect(recorded[key] == nil, "duplicate key \(key)")
            recorded[key] = numbers
        }
    }

    static func mapPoints(_ coordinates: [Coordinate]) -> [Double] {
        coordinates.flatMap { c -> [Double] in
            let p = StrokeProjection.point(c)
            return [p.x, p.y]
        }
    }

    static func checksum(_ v: [Double]) -> [Double] {
        var s = 0.0, w = 0.0, q = 0.0
        for (i, x) in v.enumerated() {
            s += x
            w += x * Double(i % 97 + 1)
            q += x * x * 1e-6
        }
        return [Double(v.count), s, w, q]
    }

    static func recordGeometry(_ prefix: String, _ g: StrokeBake.Prepared, into r: inout Recorder) {
        for id in g.strokes.keys.sorted() {
            let s = g.strokes[id]!
            let p = "\(prefix)|stroke|\(id)"
            r.record("\(p)|runs", checksum(mapPoints(s.runs.flatMap { $0 })) + [Double(s.runs.count)])
            r.record("\(p)|anchors", s.anchors.keys.sorted().flatMap {
                [Double($0)] + mapPoints([s.anchors[$0]!])
            })
            r.record("\(p)|points", checksum(s.stroke.points.flatMap { [$0.x, $0.y] }))
            r.record("\(p)|measures", checksum(s.stroke.measures))
            r.record("\(p)|sourceMeasures", checksum(s.sourceMeasures))
            for (i, w) in s.withheldRuns.enumerated() {
                r.record("\(p)|withheld|\(i)|\(w.colorHex)|\(w.colorDarkHex)", mapPoints(w.coordinates))
            }
            for (i, w) in s.emittedFamilyWindows.enumerated() {
                r.record("\(p)|emitted|\(i)|\(w.groupID)", [w.from, w.to])
            }
        }
        for id in g.lines.keys.sorted() {
            let l = g.lines[id]!
            let p = "\(prefix)|line|\(id)"
            for (i, c) in l.coordinateChunks.enumerated() { r.record("\(p)|chunk|\(i)", mapPoints(c)) }
            for (i, c) in l.historicalCoordinateChunks.enumerated() { r.record("\(p)|hist|\(i)", mapPoints(c)) }
            for key in l.familyCoordinateChunks.keys.sorted() {
                let f = l.familyCoordinateChunks[key]!
                for (i, c) in f.coordinateChunks.enumerated() {
                    r.record("\(p)|family|\(key)|\(f.colorHex)|\(f.colorDarkHex)|\(i)",
                             mapPoints(c) + [f.chunkWindows[i].from, f.chunkWindows[i].to])
                }
            }
            for (n, fb) in l.familyFallbacks.enumerated() {
                for (i, c) in fb.family.coordinateChunks.enumerated() {
                    r.record("\(p)|fallback|\(n)|\(fb.window.groupID)|\(fb.window.from)|\(fb.window.to)|\(i)",
                             mapPoints(c) + [fb.family.chunkWindows[i].from, fb.family.chunkWindows[i].to])
                }
            }
            r.record("\(p)|reserve", [Double(l.fallbackSplitReserve)])
        }
    }

    static let zooms: [Double] = [5, 8, 10.5, 13, 17]
    static let datedZooms: [Double] = [8, 13]

    static func isFingerprint(_ key: String) -> Bool {
        ["|runs", "|points", "|measures", "|sourceMeasures"].contains { key.hasSuffix($0) }
    }

    static func produce() throws -> Recorder {
        let fixture = try StrokeBakeFixtures.load()
        let network = StrokeBakeFixtures.network(fixture)
        let byID = Dictionary(network.lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var recorder = Recorder()
        for zoom in zooms {
            for name in ["plain", "dated"] {
                if name == "dated" && !datedZooms.contains(zoom) { continue }
                let joined = JoinedChainCache()
                let pixels = ChainPixelCache(joinedChains: joined)
                let frame = StrokeBake.Frame(appZoom: zoom)
                let prepared = try StrokeBake.prepare(
                    lines: network.lines, strokes: network.lines.filter(\.continuous),
                    allLines: byID, anchors: network.anchors, cachedStrokes: [:],
                    joinedChains: joined, chainPixels: pixels, frame: frame,
                    partStyle: name == "plain" ? { _, _ in .solid } : StrokeBakeFixtures.datedStyle)
                recordGeometry("\(name)|z\(zoom)", prepared, into: &recorder)
                if name == "plain", let probe = network.lines.first(where: { !$0.continuous }) {
                    for lane in [0.0, 1.0, -2.5] {
                        let out = StrokeBake.parallelLaneCoordinates(
                            probe.intervals[0], lane: lane,
                            mapPointsPerPoint: frame.mapPointsPerPoint, scale: frame.scale)
                        recorder.record("parallel|z\(zoom)|\(probe.id)|\(lane)", mapPoints(out))
                    }
                }
            }
        }
        return recorder
    }

    @Test("every golden key is produced, with the same length and values")
    func matchesGolden() throws {
        let golden = try Golden.load()
        let produced = try Self.produce()
        #expect(Set(produced.recorded.keys) == Set(golden.entries.keys))
        // Map points are up to 2.7e8, so doubles resolve about 3e-8, and the new projection differs
        // from MapKit's by up to 1.8e-7 (MapKit's rounding is not reproducible bit for bit; see
        // `StrokeProjectionParityTests`). The stroke builder amplifies input noise at some
        // vertices: measured on the hk tram lane line at z17, moving every input by 1e-8 map
        // point moved one output vertex by 0.15. So an output vertex is held to 1e-4 map point
        // (a five-thousandth of a pixel at the highest level) except for a handful of such
        // sensitive vertices, which are held to 0.1 map point (0.05 px at the highest level),
        // with the vertex counts of every run required to be identical.
        let pointTolerance = 1e-4
        let sensitiveTolerance = 0.1
        let sensitiveAllowance = 8
        var worst = 0.0
        var worstKey = ""
        var checked = 0
        var sensitive: [String] = []
        for (key, expected) in golden.entries.sorted(by: { $0.key < $1.key }) {
            guard let actual = produced.recorded[key] else { continue }
            #expect(actual.count == expected.count, "length of \(key)")
            guard actual.count == expected.count, let want = golden.slice(key) else { continue }
            checked += 1
            // Fingerprints are sums of large numbers, so they are compared relatively.
            let fingerprint = Self.isFingerprint(key)
            let difference = zip(actual, want).map { abs($0 - $1) / (fingerprint ? max(abs($1), 1) : 1) }.max() ?? 0
            if difference > worst { worst = difference; worstKey = key }
            if fingerprint {
                #expect(difference <= 1e-9, "\(key) differs by \(difference)")
            } else if difference > pointTolerance {
                sensitive.append(key)
                #expect(difference <= sensitiveTolerance, "\(key) differs by \(difference)")
            }
        }
        #expect(checked == golden.entries.count)
        #expect(sensitive.count <= sensitiveAllowance, "\(sensitive.count) entries beyond 1e-4: \(sensitive)")
        print("StrokeBakeEquality: \(checked) entries, \(sensitive.count) beyond 1e-4, worst difference \(worst) at \(worstKey)")
    }

    @Test("the fixture exercises every engine branch the golden claims to cover")
    func fixtureCoverage() throws {
        let network = StrokeBakeFixtures.network(try StrokeBakeFixtures.load())
        #expect(network.lines.contains { $0.continuous })
        #expect(network.lines.contains { !$0.continuous && $0.lane != 0 })
        #expect(network.lines.contains { !$0.follows.isEmpty })
        #expect(network.lines.contains { !$0.withheld.isEmpty })
        #expect(network.lines.contains { $0.familyWindows.contains(where: \.isLandlord) })
        #expect(network.lines.contains { $0.familyWindows.contains { !$0.isLandlord } })
        #expect(network.lines.contains { !$0.joinPrevious })
        #expect(Set(network.lines.map(\.region)) == ["jp", "hk", "mo"])
        let golden = try Golden.load()
        #expect(golden.entries.keys.contains { $0.contains("|hist|") })
        #expect(golden.entries.keys.contains { $0.contains("|family|") })
        #expect(golden.entries.keys.contains { $0.contains("|fallback|") })
        #expect(golden.entries.keys.contains { $0.contains("|withheld|") })
    }
}
