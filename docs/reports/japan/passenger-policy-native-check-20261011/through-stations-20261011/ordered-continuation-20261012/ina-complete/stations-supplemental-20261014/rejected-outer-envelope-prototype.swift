import Foundation

/// Cartographic review evidence, never a surveyed station coordinate.
public struct AppleMapPlatformCandidate: Sendable {
    /// Oriented fitted frame around visible fill, not a surveyed platform boundary.
    public let polygon: [CGPoint]
    public let axis: [CGPoint]
    public let midpoint: CGPoint
    public let railMidpoint: CGPoint?
    public let supportingRail: [CGPoint]
    /// 1 means the midpoint has local rail segment support; 0 means none.
    public let support: Double
    public let ambiguity: Double
    public let status: String
    public let reason: String
}

extension AppleMapRailExtractor {
    /// Opt-in frame analysis. Paths must be independently supported rail glyphs.
    public static func analyzePlatforms(_ raster: AppleMapRaster, railPaths: [[CGPoint]],
                                       metresPerPixel: Double, masks: [CGRect] = []) -> [AppleMapPlatformCandidate] {
        guard raster.width > 1, raster.height > 1, raster.width <= 4096, raster.height <= 4096,
              raster.rgba.count == raster.width * raster.height * 4,
              metresPerPixel.isFinite, metresPerPixel > 0 else { return [] }
        let width = raster.width, height = raster.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        func masked(_ point: CGPoint) -> Bool {
            masks.contains { rect in
                let x0 = min(rect.origin.x, rect.origin.x + rect.size.width)
                let x1 = max(rect.origin.x, rect.origin.x + rect.size.width)
                let y0 = min(rect.origin.y, rect.origin.y + rect.size.height)
                let y1 = max(rect.origin.y, rect.origin.y + rect.size.height)
                return point.x >= x0 && point.x < x1 && point.y >= y0 && point.y < y1
            }
        }
        for y in 0..<height {
            if Task.isCancelled { return [] }
            for x in 0..<width {
                let index = (y * width + x) * 4
                let r = Double(raster.rgba[index]), g = Double(raster.rgba[index + 1]), b = Double(raster.rgba[index + 2])
                // Pale periwinkle platform fill, excluding gray roads and the
                // darker, less blue-selective building palette. Water is also
                // excluded below by width, aspect and independent rail support.
                if raster.rgba[index + 3] >= 250, r >= 75, b - g >= 28,
                   b - r >= 45, b - g > 1.5 * (g - r),
                   !masked(CGPoint(x: Double(x), y: Double(y))) { pixels[y * width + x] = 1 }
            }
        }
        var candidates: [AppleMapPlatformCandidate] = []
        for start in pixels.indices where pixels[start] == 1 {
            if Task.isCancelled { return [] }
            var queue = [start], cursor = 0
            pixels[start] = 0
            var touchesMask = false, touchesEdge = false
            while cursor < queue.count {
                let index = queue[cursor]; cursor += 1
                let x = index % width, y = index / width
                if x == 0 || y == 0 || x == width - 1 || y == height - 1 { touchesEdge = true }
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    if masked(CGPoint(x: Double(nx), y: Double(ny))) { touchesMask = true }
                    let next = ny * width + nx
                    if pixels[next] == 1 { pixels[next] = 0; queue.append(next) }
                }
            }
            guard queue.count >= 30, !touchesEdge else { continue }
            // Measure the outer envelope, so text holes inside a fill do not
            // create artificial caps. A constriction can separate roof/stair
            // shapes, but is not by itself proof of a passenger boundary.
            let allPoints = queue.map { CGPoint(x: Double($0 % width), y: Double($0 / width)) }
            let cx = allPoints.reduce(0) { $0 + $1.x } / Double(allPoints.count)
            let cy = allPoints.reduce(0) { $0 + $1.y } / Double(allPoints.count)
            let cxx = allPoints.reduce(0) { $0 + pow($1.x - cx, 2) }
            let cyy = allPoints.reduce(0) { $0 + pow($1.y - cy, 2) }
            let cxy = allPoints.reduce(0) { $0 + ($1.x - cx) * ($1.y - cy) }
            let direction = 0.5 * atan2(2 * cxy, cxx - cyy)
            let ux = cos(direction), uy = sin(direction)
            func bin(_ p: CGPoint) -> Int { Int(((p.x - cx) * ux + (p.y - cy) * uy).rounded()) }
            var envelopes: [Int: (Double, Double)] = [:]
            for p in allPoints {
                let k = bin(p), n = -(p.x - cx) * uy + (p.y - cy) * ux
                let old = envelopes[k] ?? (n, n)
                envelopes[k] = (min(old.0, n), max(old.1, n))
            }
            func median(_ values: [Double]) -> Double {
                let sorted = values.sorted()
                return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
            }
            let widths = envelopes.mapValues { $0.1 - $0.0 + 1 }
            let keys = widths.keys.sorted()
            var narrowBins: [Int] = []
            if let first = keys.first, let last = keys.last {
                for k in keys where k - first >= 25 && last - k >= 25 {
                    let local = median((k - 2...k + 2).compactMap { widths[$0] })
                    let before = median((k - 25...k - 13).compactMap { widths[$0] })
                    let after = median((k + 13...k + 25).compactMap { widths[$0] })
                    if before > 0, after > 0, local < 0.82 * min(before, after) { narrowBins.append(k) }
                }
            }
            var runs: [[Int]] = []
            for k in narrowBins {
                if let previous = runs.last?.last, k == previous + 1 { runs[runs.count - 1].append(k) }
                else { runs.append([k]) }
            }
            let cuts = runs.filter { $0.count >= 3 && $0.count <= 12 }.map { $0[$0.count / 2] }
            let constricted = !cuts.isEmpty
            let groups = Dictionary(grouping: allPoints) { p in cuts.filter { bin(p) > $0 }.count }
            for group in groups.keys.sorted() {
                let points = groups[group]!
                guard points.count >= 30 else { continue }
                let centre = CGPoint(x: points.reduce(0) { $0 + $1.x } / Double(points.count),
                                     y: points.reduce(0) { $0 + $1.y } / Double(points.count))
                var xx = 0.0, yy = 0.0, xy = 0.0
                for p in points {
                    let x = p.x - centre.x, y = p.y - centre.y
                    xx += x * x; yy += y * y; xy += x * y
                }
                let angle = 0.5 * atan2(2 * xy, xx - yy)
                let tangent = CGPoint(x: cos(angle), y: sin(angle))
                let normal = CGPoint(x: -tangent.y, y: tangent.x)
                func projected(_ p: CGPoint, _ direction: CGPoint) -> Double {
                    (p.x - centre.x) * direction.x + (p.y - centre.y) * direction.y
                }
                let longitudinal = points.map { projected($0, tangent) }.sorted()
                let transverse = points.map { projected($0, normal) }.sorted()
                // Trim only edge antialiasing/specks; never join separate components
                // across text, missing fill, or an unsupported railway segment.
                func extent(_ values: [Double]) -> (Double, Double) {
                    (values[Int(Double(values.count - 1) * 0.02)], values[Int(Double(values.count - 1) * 0.98)])
                }
                let (low, high) = extent(longitudinal), (left, right) = extent(transverse)
                let length = (high - low + 1) * metresPerPixel
                let breadth = (right - left + 1) * metresPerPixel
                guard length >= 15, length <= 250, breadth >= 2, breadth <= 30,
                      length / breadth >= 2.5 else { continue }
                func point(_ along: Double, _ across: Double) -> CGPoint {
                    CGPoint(x: centre.x + tangent.x * along + normal.x * across,
                            y: centre.y + tangent.y * along + normal.y * across)
                }
                let middleAcross = (left + right) / 2
                let midpoint = point((low + high) / 2, middleAcross)
                let axis = [point(low, middleAcross), point(high, middleAcross)]
                let polygon = [point(low, left), point(high, left), point(high, right), point(low, right), point(low, left)]
                var matches: [(point: CGPoint, path: [CGPoint], distance: Double)] = []
                for path in railPaths {
                    var nearest: (CGPoint, Double)?
                    for (a, b) in zip(path, path.dropFirst()) {
                        let dx = b.x - a.x, dy = b.y - a.y, distance = hypot(dx, dy)
                        guard distance.isFinite, distance > 0.01,
                              abs((dx * tangent.x + dy * tangent.y) / distance) >= cos(25 * .pi / 180) else { continue }
                        let fraction = ((midpoint.x - a.x) * dx + (midpoint.y - a.y) * dy) / (distance * distance)
                        // No endpoint extension into unsupported gaps.
                        guard fraction >= 0, fraction <= 1 else { continue }
                        let p = CGPoint(x: a.x + fraction * dx, y: a.y + fraction * dy)
                        guard !masked(p) else { continue }
                        let offset = hypot(p.x - midpoint.x, p.y - midpoint.y) * metresPerPixel
                        if offset <= 8, nearest == nil || offset < nearest!.1 { nearest = (p, offset) }
                    }
                    if let nearest { matches.append((nearest.0, path, nearest.1)) }
                }
                matches.sort { $0.distance < $1.distance }
                let selected = matches.first
                let ambiguous = selected.map { selected in matches.dropFirst().contains {
                    hypot($0.point.x - selected.point.x, $0.point.y - selected.point.y) * metresPerPixel > 2
                } } ?? false
                let resolved = selected != nil && !touchesMask && !ambiguous && !constricted
                candidates.append(.init(polygon: polygon, axis: axis, midpoint: midpoint,
                    railMidpoint: resolved ? selected?.point : nil,
                    supportingRail: selected?.path ?? [], support: selected == nil ? 0 : 1,
                    ambiguity: ambiguous ? 1 : 0,
                    status: resolved ? "platform_cartography_midpoint_candidate" : "unresolved",
                    reason: constricted ? "constricted_fill_extent_requires_owner_review" : touchesMask ? "text_mask_intersects_platform_extent" : ambiguous ? "competing_parallel_rail_bands" :
                        selected == nil ? "no_supported_parallel_rail_at_midpoint" : "visible_platform_extent_and_independent_rail_glyph"))
            }
        }
        // Parallel passenger groups cannot be assigned by nearest POI, source
        // station position, or old chainage. Two sides sharing the same band
        // are retained separately; distinct nearby bands remain unresolved.
        let conflicting = Set(candidates.indices.filter { i in
            guard let a = candidates[i].railMidpoint else { return false }
            return candidates.indices.contains { j in
                guard i != j, let b = candidates[j].railMidpoint else { return false }
                let ta = candidates[i].axis[1], sa = candidates[i].axis[0]
                let tb = candidates[j].axis[1], sb = candidates[j].axis[0]
                let ax = ta.x - sa.x, ay = ta.y - sa.y, bx = tb.x - sb.x, by = tb.y - sb.y
                let parallel = abs((ax * bx + ay * by) / (hypot(ax, ay) * hypot(bx, by))) >= cos(25 * .pi / 180)
                let distance = hypot(a.x - b.x, a.y - b.y) * metresPerPixel
                let across = abs((b.x - a.x) * -ay + (b.y - a.y) * ax) / hypot(ax, ay) * metresPerPixel
                let along = abs((b.x - a.x) * ax + (b.y - a.y) * ay) / hypot(ax, ay) * metresPerPixel
                return parallel && across > 2 && distance < 35 && along < 20
            }
        })
        return candidates.enumerated().map { i, c in
            guard conflicting.contains(i) else { return c }
            return .init(polygon: c.polygon, axis: c.axis, midpoint: c.midpoint,
                railMidpoint: nil, supportingRail: c.supportingRail, support: c.support,
                ambiguity: 1, status: "unresolved", reason: "competing_parallel_platform_groups")
        }
    }
}
