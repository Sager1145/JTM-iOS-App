import Foundation
@preconcurrency import MapKit
import RailCore
import RailInspection
import UIKit
import UniformTypeIdentifiers

struct ReferenceTrack {
    var paths: [[Coordinate]]
    var label: String
    var lineID: String?
    var intervalIndex: Int?

    static func read(_ data: Data) throws -> ReferenceTrack {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EvidenceError.invalidReference
        }
        let features: [[String: Any]]
        if root["type"] as? String == "FeatureCollection" {
            features = root["features"] as? [[String: Any]] ?? []
        } else if root["type"] as? String == "Feature" { features = [root] }
        else { features = [["geometry": root]] }
        var paths: [[Coordinate]] = []
        var labels: [String] = []
        var lineIDs: Set<String> = [], intervals: Set<Int> = []
        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any] else { continue }
            let properties = feature["properties"] as? [String: Any] ?? [:]
            if let label = properties["source"] as? String { labels.append(label) }
            if let id = properties["lineID"] as? String { lineIDs.insert(id) }
            if let index = properties["intervalIndex"] as? Int { intervals.insert(index) }
            let rows: [[[Double]]]
            switch geometry["type"] as? String {
            case "LineString": rows = [(geometry["coordinates"] as? [[Double]]) ?? []]
            case "MultiLineString": rows = (geometry["coordinates"] as? [[[Double]]]) ?? []
            default: continue
            }
            for row in rows {
                guard row.count >= 2, row.allSatisfy({ $0.count >= 2 && $0[0].isFinite && $0[1].isFinite && abs($0[0]) <= 180 && abs($0[1]) <= 90 }) else {
                    throw EvidenceError.invalidReference
                }
                paths.append(row.map { Coordinate(lon: $0[0], lat: $0[1]) })
            }
        }
        guard !paths.isEmpty, lineIDs.count <= 1, intervals.count <= 1 else { throw EvidenceError.invalidReference }
        return .init(paths: paths, label: labels.first ?? "导入的 WGS84 轨道参考（身份需人工核对）",
                     lineID: lineIDs.first, intervalIndex: intervals.first)
    }
}

enum EvidenceError: LocalizedError {
    case invalidReference, noMap, imageEncoding, unexpectedSnapshotScale
    var errorDescription: String? {
        switch self {
        case .invalidReference: "需要单一线路/区间的 WGS84 GeoJSON LineString 或 MultiLineString。"
        case .noMap: "地图尚未准备好。"
        case .imageEncoding: "无法编码证据图像。"
        case .unexpectedSnapshotScale: "原生快照像素尺寸与请求的 1× 视口不符；证据未写入。"
        }
    }
}

struct EvidenceBundle {
    var files: [String: Data]
    var name: String
    var itemID: String?
}

@MainActor enum InspectionEvidence {
    static func capture(options: MKMapSnapshotter.Options, record: Data, display: [[Coordinate]], smooth: [[Coordinate]],
                        reference: [[Coordinate]], width: CGFloat, itemID: String?,
                        outputModes: [DiagnosticCaptureSettings.OutputMode]? = nil,
                        expectedPixelSize: CGSize? = nil) async throws -> EvidenceBundle {
        // Interactive captures keep every stage, including an imported reference.
        // A batch request names only the PNGs it needs before any image encoding.
        let requestedModes = outputModes ?? DiagnosticCaptureSettings.OutputMode.allCases
        var metadata = (try JSONSerialization.jsonObject(with: record)) as? [String: Any] ?? [:]
        func rows(_ paths: [[Coordinate]]) -> [[[Double]]] { paths.map { $0.map { [$0.lon, $0.lat] } } }
        metadata["renderedDisplay"] = rows(display)
        metadata["renderedSmooth"] = rows(smooth)
        metadata["referenceCoordinates"] = rows(reference)
        metadata["evidenceOpacity"] = 1
        metadata["evidenceLineWidthPoints"] = width
        metadata["mapRect"] = ["x": options.mapRect.origin.x, "y": options.mapRect.origin.y,
                               "width": options.mapRect.size.width, "height": options.mapRect.size.height]
        let snapshot = try await MKMapSnapshotter(options: options).start()
        if let expectedPixelSize {
            guard let pixels = snapshot.image.cgImage,
                  CGFloat(pixels.width) == expectedPixelSize.width,
                  CGFloat(pixels.height) == expectedPixelSize.height else {
                throw EvidenceError.unexpectedSnapshotScale
            }
        }
        // Record returned native projection witnesses as well as the requested
        // camera. Overlay coordinates always use this same snapshot mapping.
        let rect = options.mapRect
        if !rect.isNull, rect.width > 0, rect.height > 0 {
            let center = MKMapPoint(x: rect.midX, y: rect.midY)
            let west = MKMapPoint(x: rect.midX - rect.width / 4, y: rect.midY)
            let east = MKMapPoint(x: rect.midX + rect.width / 4, y: rect.midY)
            let north = MKMapPoint(x: rect.midX, y: rect.midY - rect.height / 4)
            let south = MKMapPoint(x: rect.midX, y: rect.midY + rect.height / 4)
            let cp = snapshot.point(for: center.coordinate)
            let wp = snapshot.point(for: west.coordinate), ep = snapshot.point(for: east.coordinate)
            let np = snapshot.point(for: north.coordinate), sp = snapshot.point(for: south.coordinate)
            let xScale = (rect.width / 2) / Double(ep.x - wp.x)
            let yScale = (rect.height / 2) / Double(sp.y - np.y)
            if xScale.isFinite, yScale.isFinite, xScale > 0, yScale > 0 {
                metadata["snapshotProjection"] = [
                    "scope": "Measured from MKMapSnapshotter returned point mapping; flat north-up camera.",
                    "widthPoints": Double(snapshot.image.size.width), "heightPoints": Double(snapshot.image.size.height),
                    "displayScale": Double(snapshot.image.scale),
                    "centerXPoints": Double(cp.x), "centerYPoints": Double(cp.y),
                    "mapPointsPerPointX": xScale, "mapPointsPerPointY": yScale,
                    "zoom256X": log2(MKMapSize.world.width / (256 * xScale)),
                    "zoom256Y": log2(MKMapSize.world.width / (256 * yScale))]
            }
        }
        let evidenceRecord = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        func overlay(_ paths: [[Coordinate]], color: UIColor) throws -> Data {
            let format = UIGraphicsImageRendererFormat()
            format.scale = snapshot.image.scale
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: snapshot.image.size, format: format).image { context in
                snapshot.image.draw(at: .zero)
                let cg = context.cgContext
                cg.setLineWidth(width); cg.setLineCap(.round); cg.setLineJoin(.round)
                cg.setStrokeColor(color.cgColor)
                for path in paths where path.count > 1 {
                    cg.beginPath()
                    for (i, coordinate) in path.enumerated() {
                        let point = snapshot.point(for: coordinate.native)
                        if i == 0 { cg.move(to: point) } else { cg.addLine(to: point) }
                    }
                    cg.strokePath()
                }
            }
            guard let data = image.pngData() else { throw EvidenceError.imageEncoding }
            return data
        }
        var files = ["view.json": evidenceRecord]
        if requestedModes.contains(.basemap) {
            guard let baseline = snapshot.image.pngData() else { throw EvidenceError.imageEncoding }
            files["basemap.png"] = baseline
        }
        if requestedModes.contains(.display) { files["display.png"] = try overlay(display, color: .systemTeal) }
        if requestedModes.contains(.smooth) { files["smooth.png"] = try overlay(smooth, color: .systemPink) }
        if outputModes == nil && !reference.isEmpty { files["reference.png"] = try overlay(reference, color: .systemOrange) }
        files["README.txt"] = Data("同一次 MKMapSnapshotter 底图上绘制三个阶段；相同 mapRect、尺寸、样式。图片是独立快照，不是屏幕截图；证据叠加为不透明，界面透明度仅记录为上下文。仅中心线，未包含主程序多线、共享走廊、连接、折叠。橙色参考是外部轨道证据，不是 Apple 像素测量。审查状态以 view.json 为准。\n".utf8)
        return .init(files: files, name: "jp-rail-evidence-\(Int(Date().timeIntervalSince1970))", itemID: itemID)
    }
}

/// Sampled, one-sided nearest-polyline distance; never a basemap residual.
struct InspectionDistances {
    struct Sample: Codable {
        var maximumMetres: Double
        var sampleCount: Int
        var candidateCount: Int
        var spacingUpperBoundMetres: Double
        var includedParts: [Int]
        var capReducedSampling: Bool
    }
    static func sampledMaximum(_ paths: [[Coordinate]], to reference: [[Coordinate]],
                               in rect: MKMapRect, limit: Int = 1000) -> Sample? {
        let targets = reference.flatMap { path -> [(MKMapPoint, MKMapPoint)] in
            let points = path.map { MKMapPoint($0.native) }
            return zip(points, points.dropFirst()).map { ($0.0, $0.1) }
        }
        guard !targets.isEmpty else { return nil }
        // Densify chords as well as curves: endpoints alone miss a chord cutting a bend.
        var points: [(point: MKMapPoint, part: Int)] = []
        var maxBaseSpacing = 0.0
        for (partIndex, path) in paths.enumerated() {
            for (a, b) in zip(path, path.dropFirst()) {
                let pa = MKMapPoint(a.native), pb = MKMapPoint(b.native)
                let bounds = MKMapRect(x: min(pa.x, pb.x), y: min(pa.y, pb.y),
                    width: max(1, abs(pb.x - pa.x)), height: max(1, abs(pb.y - pa.y)))
                guard rect.intersects(bounds) else { continue }
                let count = min(200, max(1, Int(ceil(Geometry.distanceMeters(a, b) / 10))))
                maxBaseSpacing = max(maxBaseSpacing, Geometry.distanceMeters(a, b) / Double(count))
                for i in 0...count {
                    let t = Double(i) / Double(count)
                    let p = MKMapPoint(x: pa.x + (pb.x - pa.x) * t, y: pa.y + (pb.y - pa.y) * t)
                    if rect.contains(p) { points.append((p, partIndex)) }
                }
            }
        }
        guard !points.isEmpty else { return nil }
        let step = max(1, Int(ceil(Double(points.count) / Double(limit))))
        var result = 0.0
        var parts: Set<Int> = [], sampled = 0
        for index in stride(from: 0, to: points.count, by: step) {
            let p = points[index].point
            parts.insert(points[index].part); sampled += 1
            var nearest = Double.infinity
            for (a, b) in targets {
                let dx = b.x - a.x, dy = b.y - a.y, length2 = dx * dx + dy * dy
                let t = length2 > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2)) : 0
                nearest = min(nearest, hypot(p.x - a.x - t * dx, p.y - a.y - t * dy))
            }
            result = max(result, nearest * MKMetersPerMapPointAtLatitude(p.coordinate.latitude))
        }
        return Sample(maximumMetres: result, sampleCount: sampled, candidateCount: points.count,
                      spacingUpperBoundMetres: maxBaseSpacing * Double(step), includedParts: parts.sorted(),
                      capReducedSampling: step > 1)
    }
}
