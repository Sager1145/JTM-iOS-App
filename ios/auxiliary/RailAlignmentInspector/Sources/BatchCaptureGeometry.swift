import CryptoKit
import Foundation
import MapKit
import RailCore
import RailInspection

/// Full-line rendering is computed before clipping; viewport boundaries are
/// never introduced as smoothing anchors.
struct BatchCaptureGeometry {
    static let zoom = 17.0
    static let size = CGSize(width: 1024, height: 768)
    static let mapPointsPerPoint = MKMapSize.world.width / (256 * pow(2, zoom))
    // Bump when DisplayParts / ContinuousStroke integration changes.
    static let revision = InspectorStrokeGeometry.revision + ";specified-capture-v3;projection-witness-v1"

    static func mapPointsPerPoint(settings: DiagnosticCaptureSettings) -> Double {
        MKMapSize.world.width / (256 * pow(2, settings.zoom))
    }
    static func size(settings: DiagnosticCaptureSettings) -> CGSize {
        CGSize(width: CGFloat(settings.width), height: CGFloat(settings.height))
    }

    struct RenderedLine {
        let lineID: String
        let display: [[Coordinate]]
        let smooth: [[Coordinate]]
        let decodedDisplay: [[Coordinate]]
    }
    struct Clipped {
        var paths: [[Coordinate]] = []
        var originalPartIndices: [Int] = []
    }
    struct DistanceReport: Codable {
        struct PointSample: Codable {
            var longitude: Double
            var latitude: Double
            var originalPartIndex: Int
            var nearestMetres: Double
        }
        var scope = "One-sided smooth→display nearest-polyline distance, within this viewport. Not Apple pixel residual or an alignment verdict."
        var requestedSpacingMetres = 10.0
        var candidateCount: Int
        var sampleCount: Int
        var cap = 1000
        var capReducedSampling: Bool
        var spacingUpperBoundMetres: Double
        var maximumMetres: Double
        var samples: [PointSample]
    }

    static var styleContract: String {
        styleContract(settings: .init())
    }

    static func styleContract(settings: DiagnosticCaptureSettings) -> String {
        let weight = RailStyle.scale(atZoom: settings.zoom)
        let standard = "\(revision);\(InspectorStrokeGeometry.joinContract);w=\(RailStyle.railWidth);lane=\(RailStyle.parallelLaneCentreDistance);r=\(RailStyle.strokeCornerRadius);rmin=\(RailStyle.minimumCornerRadius(atScale: weight));ramp=\(RailStyle.strokeMinRamp);weight=\(weight);zoom=\(settings.zoom);scale=\(mapPointsPerPoint(settings: settings));viewport=\(settings.width)x\(settings.height);backing=1;flat;\(settings.appearance.rawValue);outputs=\(settings.outputModes.map(\.rawValue).joined(separator: ","));coverage=mercator-min-axis-0.4-max350-v1;poi-excluded;buildings"
        // Retain existing standard receipt identities; only imagery adds a token.
        return settings.basemapStyle == .standard ? standard : standard + ";basemap=imagery"
    }

    static func render(line: CompactPackage.Line, display: [[Coordinate]], settings: DiagnosticCaptureSettings = .init()) -> RenderedLine {
        let smooth = InspectorStrokeGeometry.build(display: display, stations: line.displayStations.map(\.coordinate),
            mapPointsPerPoint: mapPointsPerPoint(settings: settings), zoom: settings.zoom)
        return .init(lineID: line.id, display: display, smooth: smooth, decodedDisplay: CompactPackage.decodeDisplayIntervals(line))
    }

    static func rect(center: Coordinate, settings: DiagnosticCaptureSettings = .init()) -> MKMapRect {
        let p = MKMapPoint(center.native)
        let width = Double(settings.width) * mapPointsPerPoint(settings: settings)
        let height = Double(settings.height) * mapPointsPerPoint(settings: settings)
        return .init(x: p.x - width / 2, y: p.y - height / 2, width: width, height: height)
    }

    static func clip(_ paths: [[Coordinate]], to rect: MKMapRect) -> Clipped {
        var result = Clipped()
        for (partIndex, path) in paths.enumerated() {
            var current: [Coordinate] = []
            func flush() {
                if current.count > 1 {
                    result.paths.append(current)
                    result.originalPartIndices.append(partIndex)
                }
                current = []
            }
            for (a, b) in zip(path, path.dropFirst()) {
                guard let (start, end) = clippedSegment(MKMapPoint(a.native), MKMapPoint(b.native), rect: rect) else {
                    flush(); continue
                }
                let sc = start.coordinate, ec = end.coordinate
                let first = Coordinate(lon: sc.longitude, lat: sc.latitude)
                let last = Coordinate(lon: ec.longitude, lat: ec.latitude)
                if current.last != first { flush(); current = [first] }
                if current.last != last { current.append(last) }
            }
            flush()
        }
        return result
    }

    /// Two passes bound retained samples even for a malformed long chord.
    /// Measurements target the complete display line, not its clipped chords.
    static func distances(smooth: Clipped, display: [[Coordinate]], cap: Int = 1000) -> DistanceReport? {
        let allTargets = display.flatMap { path in
            zip(path, path.dropFirst()).map { (MKMapPoint($0.0.native), MKMapPoint($0.1.native)) }
        }
        guard !allTargets.isEmpty else { return nil }
        // Exact conservative pruning: the center's nearest target plus half
        // the source bounds' diagonal is an upper bound for every sample's
        // nearest distance. A target outside the expanded source bounds cannot
        // win. This avoids rescanning a national trunk for every local sample.
        let sourcePoints = smooth.paths.flatMap { $0.map { MKMapPoint($0.native) } }
        guard let first = sourcePoints.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in sourcePoints {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let center = MKMapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let centerNearest = allTargets.reduce(Double.infinity) { min($0, nearestDistance(center, to: $1)) }
        let margin = centerNearest + hypot(maxX - minX, maxY - minY) / 2 + 1
        let targets = allTargets.filter { target in
            let (a, b) = target
            return max(a.x, b.x) >= minX - margin && min(a.x, b.x) <= maxX + margin
                && max(a.y, b.y) >= minY - margin && min(a.y, b.y) <= maxY + margin
        }
        var candidateCount = 0
        var maxSpacing = 0.0
        for path in smooth.paths {
            for (a, b) in zip(path, path.dropFirst()) {
                let length = Geometry.distanceMeters(a, b)
                let count = max(1, Int(ceil(length / 10)))
                candidateCount += count + 1
                maxSpacing = max(maxSpacing, length / Double(count))
            }
        }
        guard candidateCount > 0 else { return nil }
        let strideSize = max(1, Int(ceil(Double(candidateCount) / Double(max(1, cap)))))
        var ordinal = 0
        var samples: [DistanceReport.PointSample] = []
        samples.reserveCapacity(min(candidateCount, cap))
        var maximum = 0.0
        for (pathIndex, path) in smooth.paths.enumerated() {
            for (a, b) in zip(path, path.dropFirst()) {
                let pa = MKMapPoint(a.native), pb = MKMapPoint(b.native)
                let count = max(1, Int(ceil(Geometry.distanceMeters(a, b) / 10)))
                // Jump directly to selected candidates instead of iterating discarded samples.
                let offset = (strideSize - ordinal % strideSize) % strideSize
                if offset <= count {
                    for i in stride(from: offset, through: count, by: strideSize) {
                        let t = Double(i) / Double(count)
                        let p = MKMapPoint(x: pa.x + (pb.x - pa.x) * t, y: pa.y + (pb.y - pa.y) * t)
                        var nearest = Double.infinity
                        for (start, end) in targets {
                            nearest = min(nearest, nearestDistance(p, to: (start, end)))
                        }
                        let distance = nearest * MKMetersPerMapPointAtLatitude(p.coordinate.latitude)
                        maximum = max(maximum, distance)
                        samples.append(.init(longitude: p.coordinate.longitude, latitude: p.coordinate.latitude,
                            originalPartIndex: smooth.originalPartIndices[pathIndex], nearestMetres: distance))
                    }
                }
                ordinal += count + 1
            }
        }
        return .init(candidateCount: candidateCount, sampleCount: samples.count, cap: cap,
                     capReducedSampling: strideSize > 1, spacingUpperBoundMetres: maxSpacing * Double(strideSize),
                     maximumMetres: maximum, samples: samples)
    }

    static func dependency(line: CompactPackage.Line, display: [[Coordinate]], settings: DiagnosticCaptureSettings = .init()) -> String {
        var digest = SHA256()
        digest.update(data: Data(styleContract(settings: settings).utf8))
        digest.update(data: Data(line.id.utf8))
        for station in line.displayStations {
            digest.update(data: Data(station.id.utf8))
            append(station.coordinate, to: &digest)
        }
        append(display, to: &digest)
        // The independent DisplayParts→decoded-display metric depends on
        // neighboring raw intervals even when final DisplayParts is unchanged.
        append(CompactPackage.decodeDisplayIntervals(line), to: &digest)
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func referenceDependency(_ reference: ReferenceTrack?) -> String {
        guard let reference else { return "Apple-only" }
        var digest = SHA256()
        digest.update(data: Data("\(reference.lineID ?? "");\(reference.intervalIndex.map(String.init) ?? "");\(reference.label)".utf8))
        append(reference.paths, to: &digest)
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func append(_ paths: [[Coordinate]], to digest: inout SHA256) {
        for part in paths {
            var count = UInt64(part.count).bigEndian
            digest.update(data: withUnsafeBytes(of: &count) { Data($0) })
            for point in part { append(point, to: &digest) }
        }
    }
    private static func append(_ point: Coordinate, to digest: inout SHA256) {
        var lon = point.lon.bitPattern.bigEndian, lat = point.lat.bitPattern.bigEndian
        digest.update(data: withUnsafeBytes(of: &lon) { Data($0) })
        digest.update(data: withUnsafeBytes(of: &lat) { Data($0) })
    }
    private static func nearestDistance(_ p: MKMapPoint, to target: (MKMapPoint, MKMapPoint)) -> Double {
        let (start, end) = target
        let dx = end.x - start.x, dy = end.y - start.y
        let length2 = dx * dx + dy * dy
        let ratio = length2 > 0 ? min(1, max(0, ((p.x - start.x) * dx + (p.y - start.y) * dy) / length2)) : 0
        return hypot(p.x - start.x - ratio * dx, p.y - start.y - ratio * dy)
    }
    private static func clippedSegment(_ a: MKMapPoint, _ b: MKMapPoint, rect: MKMapRect) -> (MKMapPoint, MKMapPoint)? {
        let dx = b.x - a.x, dy = b.y - a.y
        var low = 0.0, high = 1.0
        for (p, q) in [(-dx, a.x - rect.minX), (dx, rect.maxX - a.x), (-dy, a.y - rect.minY), (dy, rect.maxY - a.y)] {
            if p == 0 { if q < 0 { return nil }; continue }
            let ratio = q / p
            if p < 0 { low = max(low, ratio) } else { high = min(high, ratio) }
            if low > high { return nil }
        }
        return (.init(x: a.x + low * dx, y: a.y + low * dy), .init(x: a.x + high * dx, y: a.y + high * dy))
    }
}
