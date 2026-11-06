import Foundation

/// Tightly packed, straight-alpha RGBA8 pixels in image coordinates (origin top left).
/// Capture a basemap without inspector overlays; seed paths only bound the search.
public struct AppleMapRaster: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width; self.height = height; self.rgba = rgba
    }
}

public struct AppleMapRailSample: Sendable {
    public let seed: CGPoint
    public let point: CGPoint
    public let supported: Bool
    public let contrast: Double
    /// Rival image reward / selected image reward. Values near one are unresolved.
    public let ambiguity: Double
    public let offsetMetres: Double
}

public struct AppleMapRailAnalysis: Sendable {
    public let samples: [AppleMapRailSample]
    /// Only persistent, unambiguous image-supported runs; never bridges gaps.
    public let paths: [[CGPoint]]
    public let supportFraction: Double
    public let medianOffsetMetres: Double?
    public let p95OffsetMetres: Double?
    public let maximumOffsetMetres: Double?
    public let status: String
    public let reason: String
}

public enum AppleMapRailEvidenceMode: Sendable, Equatable {
    /// Paired dark railway strokes used by the original extractor.
    case physicalRailGlyph
    /// Apple's thin blue labelled transit line. This is cartographic corridor
    /// evidence and must not be reported as surveyed physical rail.
    case transitCartography
}

public enum AppleMapCartographicPalette: Sendable, Equatable {
    case blueAndCyan
    /// Opt in only after identifying a blue railway in the raw basemap.
    /// Cyan roadside lines are excluded; this does not establish railway identity.
    case blueRailway
}

/// Independent raster evidence for the rendered railway glyph, not physical
/// track counts, railway identity, surveyed alignment, or platform midpoints.
/// The default physical mode requires narrow dark valley pairs with a brighter
/// interior and exterior; a nearby broad road/building edge is never a fallback.
/// The opt-in transit-cartography mode instead requires a thin, persistent blue
/// local colour peak and reports it as cartographic rather than surveyed rail.
/// Labels, crossings and low-detail map styles can leave explicit unsupported
/// gaps. Light and dark standard basemaps use relative contrast rather than a
/// fixed palette.
public enum AppleMapRailExtractor {
    public static func analyze(_ raster: AppleMapRaster, seedPaths: [[CGPoint]],
                        metresPerPixel: Double, masks: [CGRect] = [],
                        evidenceMode: AppleMapRailEvidenceMode = .physicalRailGlyph,
                        cartographicPalette: AppleMapCartographicPalette = .blueAndCyan) -> AppleMapRailAnalysis {
        func empty(_ status: String, _ reason: String) -> AppleMapRailAnalysis {
            .init(samples: [], paths: [], supportFraction: 0,
                  medianOffsetMetres: nil, p95OffsetMetres: nil,
                  maximumOffsetMetres: nil, status: status, reason: reason)
        }
        guard raster.width >= 2, raster.height >= 2,
              raster.width <= 4096, raster.height <= 4096,
              raster.rgba.count == raster.width * raster.height * 4,
              metresPerPixel.isFinite, metresPerPixel > 0 else {
            return empty("invalid", "invalid_raster_or_scale")
        }
        // OCR masks invalidate every bilinear contributor; masked text does
        // not become a painted black hole with invented railway contrast.
        var masked = [UInt8]()
        if !masks.isEmpty {
            masked = [UInt8](repeating: 0, count: raster.width * raster.height)
            for rectangle in masks {
                let minX = min(rectangle.origin.x, rectangle.origin.x + rectangle.size.width)
                let maxX = max(rectangle.origin.x, rectangle.origin.x + rectangle.size.width)
                let minY = min(rectangle.origin.y, rectangle.origin.y + rectangle.size.height)
                let maxY = max(rectangle.origin.y, rectangle.origin.y + rectangle.size.height)
                guard minX.isFinite, minY.isFinite,
                      maxX.isFinite, maxY.isFinite else { continue }
                let left = Int(max(0, min(Double(raster.width), floor(minX))))
                let right = Int(max(0, min(Double(raster.width), ceil(maxX))))
                let top = Int(max(0, min(Double(raster.height), floor(minY))))
                let bottom = Int(max(0, min(Double(raster.height), ceil(maxY))))
                guard left < right, top < bottom else { continue }
                for y in top..<bottom {
                    for x in left..<right { masked[y * raster.width + x] = 1 }
                }
            }
        }
        // Bounds keep both memory and work finite even at extreme camera zoom.
        let searchMetres = evidenceMode == .transitCartography ? 80.0 : 40.0
        let radius = Int(min(128, ceil(searchMetres / metresPerPixel)))
        let clippedSearch = searchMetres / metresPerPixel > 128
        let count = radius * 2 + 1
        var allSamples: [AppleMapRailSample] = []
        var runs: [[CGPoint]] = []
        var remaining = 4096
        for path in seedPaths {
            if Task.isCancelled { return empty("cancelled", "analysis_cancelled") }
            let seeds = resample(path, maximum: remaining)
            remaining -= seeds.count
            guard seeds.count >= 2 else { continue }
            var rows: [[Candidate]] = []
            rows.reserveCapacity(seeds.count)
            for seed in seeds {
                if Task.isCancelled { return empty("cancelled", "analysis_cancelled") }
                // Reuse transverse profiles for every pair spacing. Four
                // longitudinal probes suppress single text strokes and specks.
                let padding = 12
                let profileRadius = radius + padding
                var profiles = [[Pixel?]]()
                for along in [-3.0, -1.0, 1.0, 3.0] {
                    profiles.append((-profileRadius...profileRadius).map { offset in
                        pixel(raster, masked: masked, at: move(seed.point, seed.tangent, along,
                                              seed.normal, Double(offset)))
                    })
                }
                func value(_ offset: Double, _ longitudinal: Int) -> Pixel? {
                    let index = offset + Double(profileRadius)
                    let low = Int(floor(index)), fraction = index - floor(index)
                    guard low >= 0, low + 1 < profiles[longitudinal].count,
                          let a = profiles[longitudinal][low],
                          let b = profiles[longitudinal][low + 1] else { return nil }
                    return .init(r: a.r * (1 - fraction) + b.r * fraction,
                                 g: a.g * (1 - fraction) + b.g * fraction,
                                 b: a.b * (1 - fraction) + b.b * fraction,
                                 luma: a.luma * (1 - fraction) + b.luma * fraction,
                                 chroma: a.chroma * (1 - fraction) + b.chroma * fraction)
                }
                var row = [Candidate](repeating: .missing, count: count)
                for index in 0..<count {
                    let offset = Double(index - radius)
                    switch evidenceMode {
                    case .physicalRailGlyph:
                        for spacing in 2...20 {
                            let half = Double(spacing) / 2
                            var contrasts: [Double] = []
                            var imbalance = 0.0
                            for longitudinal in 0..<4 {
                                guard let left = value(offset - half, longitudinal),
                                      let right = value(offset + half, longitudinal),
                                      let outerLeft = value(offset - half - 2, longitudinal),
                                      let outerRight = value(offset + half + 2, longitudinal),
                                      let middle = value(offset, longitudinal),
                                      max(left.luma, right.luma) < 170,
                                      max(left.chroma, right.chroma) < 65 else { break }
                                contrasts.append(min(outerLeft.luma - left.luma,
                                                     outerRight.luma - right.luma,
                                                     middle.luma - max(left.luma, right.luma)))
                                imbalance += abs(left.luma - right.luma)
                            }
                            guard contrasts.count == 4,
                                  contrasts.filter({ $0 >= 4 }).count >= 3 else { continue }
                            let contrast = contrasts.reduce(0, +) / 4
                            let score = contrast - 0.05 * imbalance / 4
                            if contrast >= 4, score > row[index].score {
                                row[index] = .init(score: score, contrast: contrast,
                                                   spacing: Double(spacing))
                            }
                        }
                    case .transitCartography:
                        // Apple's subway glyph is a narrow blue/cyan local
                        // colour peak on both light and dark map styles. RGB is
                        // retained because luma/chroma alone cannot separate it
                        // from gray roads, building borders or water.
                        var prominences: [Double] = []
                        var strengths: [Double] = []
                        for longitudinal in 0..<4 {
                            guard let middle = value(offset, longitudinal),
                                  let left = value(offset - 2.5, longitudinal),
                                  let right = value(offset + 2.5, longitudinal) else { break }
                            let strength = min(middle.b - middle.r, middle.g - middle.r)
                            let leftStrength = max(0, min(left.b - left.r, left.g - left.r))
                            let rightStrength = max(0, min(right.b - right.r, right.g - right.r))
                            guard middle.b > middle.r + 8,
                                  middle.g > middle.r + 4,
                                  strength >= 10,
                                  cartographicPalette != .blueRailway || middle.b - middle.g >= 40 else { break }
                            prominences.append(min(strength - leftStrength,
                                                   strength - rightStrength))
                            strengths.append(strength)
                        }
                        guard prominences.count == 4,
                              prominences.filter({ $0 >= 4 }).count >= 3 else { continue }
                        let contrast = prominences.reduce(0, +) / 4
                        let score = contrast + 0.05 * strengths.reduce(0, +) / 4
                        if contrast >= 4, score > row[index].score {
                            row[index] = .init(score: score, contrast: contrast, spacing: 4)
                        }
                    }
                }
                rows.append(row)
            }
            // Viterbi continuity chooses among pixel candidates. Unsupported
            // states carry zero reward and remain unsupported in the output.
            var costs = rows[0].map { max(0, $0.score) }
            var back = [[Int]](repeating: [Int](repeating: 0, count: count), count: rows.count)
            for i in 1..<rows.count {
                if Task.isCancelled { return empty("cancelled", "analysis_cancelled") }
                var next = [Double](repeating: -.infinity, count: count)
                for j in 0..<count {
                    // Four-pixel sampling: a twelve-pixel lateral step already
                    // accommodates strong curvature without quadratic search.
                    for k in max(0, j - 12)...min(count - 1, j + 12) {
                        let spacingPenalty = rows[i][j].score > 0 && rows[i - 1][k].score > 0
                            ? 0.08 * abs(rows[i][j].spacing - rows[i - 1][k].spacing) : 0
                        let score = costs[k] - 0.22 * Double(abs(j - k)) - spacingPenalty
                        if score > next[j] { next[j] = score; back[i][j] = k }
                    }
                    next[j] += max(0, rows[i][j].score)
                }
                costs = next
            }
            var chosen = [Int](repeating: 0, count: rows.count)
            chosen[rows.count - 1] = costs.indices.max(by: { costs[$0] < costs[$1] }) ?? radius
            for i in stride(from: rows.count - 1, through: 1, by: -1) {
                chosen[i - 1] = back[i][chosen[i]]
            }
            var provisional: [AppleMapRailSample] = []
            for i in seeds.indices {
                let selected = rows[i][chosen[i]]
                let rivalDistance = max(5, selected.spacing * 0.65)
                let rival = rows[i].indices.filter { Double(abs($0 - chosen[i])) > rivalDistance }
                    .map { rows[i][$0].score }.max() ?? 0
                let ambiguity = selected.score > 0 ? max(0, rival) / selected.score : 1
                let offset = Double(chosen[i] - radius)
                provisional.append(.init(seed: seeds[i].point,
                    point: move(seeds[i].point, seeds[i].tangent, 0, seeds[i].normal, offset),
                    supported: selected.score >= 4 && ambiguity < 0.85,
                    contrast: selected.contrast, ambiguity: ambiguity,
                    offsetMetres: offset * metresPerPixel))
            }
            var run: [CGPoint] = []
            for i in provisional.indices {
                let sample = provisional[i]
                // Three consecutive probes (8px extent) are the minimum
                // persistence evidence. A lone valid endpoint is not a trace.
                let lo = max(0, i - 2), hi = min(provisional.count - 1, i + 2)
                let persistent = (lo...hi).contains { start in
                    start + 2 <= hi && (start...(start + 2)).allSatisfy { provisional[$0].supported }
                        && start <= i && i <= start + 2
                }
                let supported = sample.supported && persistent
                allSamples.append(.init(seed: sample.seed, point: sample.point,
                    supported: supported, contrast: sample.contrast,
                    ambiguity: sample.ambiguity, offsetMetres: sample.offsetMetres))
                if supported { run.append(sample.point) }
                else { if run.count >= 2 { runs.append(run) }; run = [] }
            }
            if run.count >= 2 { runs.append(run) }
            if remaining <= 0 { break }
        }
        guard !allSamples.isEmpty else {
            return evidenceMode == .transitCartography
                ? empty("no_cartographic_candidate", "no_visible_cartographic_corridor_samples")
                : empty("no_candidate", "no_visible_corridor_samples")
        }
        let offsets = allSamples.filter(\.supported).map { abs($0.offsetMetres) }.sorted()
        func percentile(_ fraction: Double) -> Double? {
            guard !offsets.isEmpty else { return nil }
            return offsets[Int((Double(offsets.count - 1) * fraction).rounded())]
        }
        let fraction = Double(offsets.count) / Double(allSamples.count)
        let reason: String
        if evidenceMode == .transitCartography {
            reason = remaining <= 0 ? "transit_cartography_sample_budget_reached"
                : clippedSearch ? "transit_cartography_search_radius_clipped"
                : offsets.isEmpty ? "persistent_unambiguous_transit_cartography_not_resolved"
                : fraction < 0.8 ? "partial_transit_cartography_support"
                : "rendered_transit_cartography_candidates"
        } else {
            reason = remaining <= 0 ? "sample_budget_reached"
                : clippedSearch ? "search_radius_clipped"
                : offsets.isEmpty ? "persistent_unambiguous_rail_glyph_not_resolved"
                : fraction < 0.8 ? "partial_image_support" : "rendered_rail_glyph_candidates"
        }
        let status = offsets.isEmpty
            ? (evidenceMode == .transitCartography ? "no_cartographic_candidate" : "no_candidate")
            : (evidenceMode == .transitCartography ? "cartographic_candidate" : "candidate")
        return .init(samples: allSamples, paths: runs, supportFraction: fraction,
                     medianOffsetMetres: percentile(0.5), p95OffsetMetres: percentile(0.95),
                     maximumOffsetMetres: offsets.last,
                     status: status, reason: reason)
    }

    private struct Candidate {
        let score: Double
        let contrast: Double
        let spacing: Double
        static let missing = Candidate(score: 0, contrast: 0, spacing: 0)
    }

    private struct Pixel {
        let r: Double
        let g: Double
        let b: Double
        let luma: Double
        let chroma: Double
    }
    private struct Seed { let point: CGPoint; let tangent: CGPoint; let normal: CGPoint }

    private static func move(_ p: CGPoint, _ t: CGPoint, _ along: Double,
                             _ n: CGPoint, _ across: Double) -> CGPoint {
        CGPoint(x: p.x + t.x * along + n.x * across,
                y: p.y + t.y * along + n.y * across)
    }

    private static func pixel(_ raster: AppleMapRaster, masked: [UInt8], at p: CGPoint) -> Pixel? {
        guard p.x >= 0, p.y >= 0, p.x < Double(raster.width - 1),
              p.y < Double(raster.height - 1) else { return nil }
        let x = Int(floor(p.x)), y = Int(floor(p.y))
        let fx = p.x - Double(x), fy = p.y - Double(y)
        var r = 0.0, g = 0.0, b = 0.0
        for (dx, dy, weight) in [(0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)),
                                 (0, 1, (1 - fx) * fy), (1, 1, fx * fy)] {
            let pixelIndex = (y + dy) * raster.width + x + dx
            guard masked.isEmpty || masked[pixelIndex] == 0 else { return nil }
            let index = pixelIndex * 4
            guard raster.rgba[index + 3] >= 250 else { return nil }
            r += Double(raster.rgba[index]) * weight
            g += Double(raster.rgba[index + 1]) * weight
            b += Double(raster.rgba[index + 2]) * weight
        }
        return .init(r: r, g: g, b: b,
                     luma: r * 0.2126 + g * 0.7152 + b * 0.0722,
                     chroma: max(r, g, b) - min(r, g, b))
    }

    private static func resample(_ path: [CGPoint], maximum: Int) -> [Seed] {
        guard maximum >= 2, path.count >= 2,
              path.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
        var points = [path[0]], measures = [0.0]
        for p in path.dropFirst() {
            let previous = points[points.count - 1]
            let length = hypot(p.x - previous.x, p.y - previous.y)
            if length > 0.0001 { points.append(p); measures.append(measures.last! + length) }
        }
        guard let total = measures.last, total >= 4 else { return [] }
        func at(_ measure: Double) -> CGPoint {
            var low = 0, high = measures.count - 1
            while low + 1 < high {
                let mid = (low + high) / 2
                if measures[mid] <= measure { low = mid } else { high = mid }
            }
            let f = (measure - measures[low]) / (measures[high] - measures[low])
            return CGPoint(x: points[low].x + (points[high].x - points[low].x) * f,
                           y: points[low].y + (points[high].y - points[low].y) * f)
        }
        var result: [Seed] = []
        var measure = 0.0
        while measure <= total && result.count < maximum {
            let p = at(measure), before = at(max(0, measure - 12)), after = at(min(total, measure + 12))
            let length = hypot(after.x - before.x, after.y - before.y)
            if length > 0.0001 {
                let tangent = CGPoint(x: (after.x - before.x) / length, y: (after.y - before.y) / length)
                result.append(.init(point: p, tangent: tangent,
                                    normal: CGPoint(x: -tangent.y, y: tangent.x)))
            }
            measure += 4
        }
        return result
    }
}
