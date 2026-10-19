import Foundation
@preconcurrency import MapKit
import RailCore
import RailInspection
import UIKit
import Vision

struct AppleStationSeed {
    let id: String
    let name: String
    let nameRoma: String?
    let coordinate: Coordinate
}

struct AppleStationMatch {
    let seed: AppleStationSeed
    let seedPixel: CGPoint
    let matches: [(name: String, coordinate: Coordinate, pixel: CGPoint, distance: Double)]
    let note: String
}

struct AppleMapExtractionReport {
    let image: UIImage
    let pixelSize: CGSize
    let constructed: [[CGPoint]]
    let analysis: AppleMapRailAnalysis
    let coordinates: [[Coordinate]]
    let stations: [AppleStationMatch]
    let platformCandidates: [AppleMapPlatformCandidate]
    let platformCoordinates: [[Coordinate]]
    let platformMidpointCoordinates: [Coordinate]
    let platformRailCoordinates: [Coordinate?]
    let masks: [CGRect]
    let mapRect: MKMapRect
    let lineID: String
    let intervalIndex: Int
    let metresPerPixel: Double
    let cartographicPalette: AppleMapCartographicPalette

    var summary: String {
        let metrics: String
        if let median = analysis.medianOffsetMetres, let p95 = analysis.p95OffsetMetres,
           let maximum = analysis.maximumOffsetMetres {
            metrics = String(format: " · 偏移中位 %.1fm / P95 %.1fm / 最大 %.1fm", median, p95, maximum)
        } else { metrics = " · 未取得可靠偏移" }
        let prefix = analysis.status.contains("cartographic") ? "Apple 地铁示意线" : "Apple 像素"
        return String(format: "%@支持 %.0f%%", prefix, analysis.supportFraction * 100) + metrics + " · 站台形状 \(platformCandidates.count)（可定位 \(platformCandidates.filter { $0.railMidpoint != nil }.count)）"
    }

    func files() throws -> [String: Data] {
        var features: [[String: Any]] = coordinates.map { path in
            ["type": "Feature", "properties": ["source": "Apple Maps snapshot pixel candidate",
                "representation": analysis.status.contains("cartographic") ? "transit_cartography_not_survey" : "physical_rail_glyph_candidate", "lineID": lineID,
                "intervalIndex": intervalIndex], "geometry": ["type": "LineString", "coordinates": path.map { [$0.lon, $0.lat] }]]
        } + stations.flatMap { station in station.matches.map { match in
            ["type": "Feature", "properties": ["source": "Apple Maps publicTransport POI", "name": match.name,
                "matchedStationID": station.seed.id, "role": "station_poi_not_platform_centre"],
             "geometry": ["type": "Point", "coordinates": [match.coordinate.lon, match.coordinate.lat]]]
        } }
        let platformRecords: [[String: Any]] = platformCandidates.enumerated().map { index, candidate in
            var value: [String: Any] = ["representation": "platform_cartography_midpoint_candidate",
                "status": candidate.status, "reason": candidate.reason, "support": candidate.support,
                "ambiguity": candidate.ambiguity, "polygonPixels": candidate.polygon.map { [$0.x, $0.y] },
                "axisPixels": candidate.axis.map { [$0.x, $0.y] },
                "midpointPixel": [candidate.midpoint.x, candidate.midpoint.y],
                "midpointCoordinate": [platformMidpointCoordinates[index].lon, platformMidpointCoordinates[index].lat],
                "supportingRailPixels": candidate.supportingRail.map { [$0.x, $0.y] }]
            if let point = candidate.railMidpoint { value["railMidpointPixel"] = [point.x, point.y] }
            if let coordinate = platformRailCoordinates[index] { value["railMidpointCoordinate"] = [coordinate.lon, coordinate.lat] }
            return value
        }
        for (index, candidate) in platformCandidates.enumerated() {
            let properties: [String: Any] = ["source": "Apple Maps visible platform fill and rail glyph",
                "representation": "platform_cartography_midpoint_candidate", "status": candidate.status,
                "reason": candidate.reason, "ambiguity": candidate.ambiguity, "lineID": lineID,
                "intervalIndex": intervalIndex, "platformCandidateIndex": index,
                "role": "unassigned_cartographic_platform_frame_not_survey"]
            features.append(["type": "Feature", "properties": properties,
                "geometry": ["type": "Polygon", "coordinates": [platformCoordinates[index].map { [$0.lon, $0.lat] }]]])
            if let coordinate = platformRailCoordinates[index] {
                features.append(["type": "Feature", "properties": properties,
                    "geometry": ["type": "Point", "coordinates": [coordinate.lon, coordinate.lat]]])
            }
        }
        var record: [String: Any] = ["format": "jtm-apple-map-extraction-v1", "lineID": lineID,
            "cartographicPalette": cartographicPalette == .blueRailway ? "blue_railway_excluding_cyan" : "blue_and_cyan",
            "representation": analysis.status.contains("cartographic") ? "transit_cartography_not_survey" : "physical_rail_glyph_candidate",
            "intervalIndex": intervalIndex, "status": analysis.status, "reason": analysis.reason,
            "supportFraction": analysis.supportFraction, "metresPerPixel": metresPerPixel,
            "width": pixelSize.width, "height": pixelSize.height,
            "mapRect": ["x": mapRect.minX, "y": mapRect.minY, "width": mapRect.width, "height": mapRect.height],
            "textMasks": masks.map { [$0.minX, $0.minY, $0.width, $0.height] },
            "samples": analysis.samples.map { ["seed": [$0.seed.x, $0.seed.y], "pixel": [$0.point.x, $0.point.y],
                "supported": $0.supported, "contrast": $0.contrast, "ambiguity": $0.ambiguity, "offsetMetres": $0.offsetMetres] as [String: Any] },
            "platformCandidates": platformRecords,
            "stations": stations.map { station in ["stationID": station.seed.id, "name": station.seed.name,
                "constructedCoordinate": [station.seed.coordinate.lon, station.seed.coordinate.lat], "note": station.note,
                "appleMatches": station.matches.map { ["name": $0.name, "coordinate": [$0.coordinate.lon, $0.coordinate.lat], "distanceMetres": $0.distance] as [String: Any] }] as [String: Any] },
            "scope": "Selected visible smoothed centreline against independent snapshot glyph candidates; unsupported/ambiguous gaps excluded. Platform frames are cartographic, unassigned review evidence, not surveyed coordinates; unresolved shapes have no rail midpoint. POI is not a platform centre. No source geometry writes."]
        if let value = analysis.medianOffsetMetres { record["medianOffsetMetres"] = value }
        if let value = analysis.p95OffsetMetres { record["p95OffsetMetres"] = value }
        if let value = analysis.maximumOffsetMetres { record["maximumOffsetMetres"] = value }
        guard let imageData = image.pngData() else { throw EvidenceError.imageEncoding }
        return ["basemap.png": imageData,
            "analysis.json": try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]),
            "extracted.geojson": try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": features], options: [.prettyPrinted, .sortedKeys])]
    }
}

@MainActor enum AppleMapAnalysisService {
    static func capture(options: MKMapSnapshotter.Options, constructed: [[Coordinate]],
                        stations: [AppleStationSeed], lineID: String, intervalIndex: Int,
                        evidenceMode: AppleMapRailEvidenceMode = .physicalRailGlyph,
                        cartographicPalette: AppleMapCartographicPalette = .blueAndCyan,
                        analyzePlatforms: Bool = true) async throws -> AppleMapExtractionReport {
        let snapshot = try await MKMapSnapshotter(options: options).start()
        try Task.checkCancellation()
        guard let cgImage = snapshot.image.cgImage else { throw EvidenceError.imageEncoding }
        let width = cgImage.width, height = cgImage.height
        let imageScale = snapshot.image.scale
        let pixels = try rgba(cgImage)
        func point(_ coordinate: Coordinate) -> CGPoint {
            let p = snapshot.point(for: coordinate.native)
            return CGPoint(x: p.x * imageScale, y: p.y * imageScale)
        }
        // Snapshot.point supplies the projection of this image, including any
        // MapKit aspect fit. Do not infer pixels from an obscured map frame.
        let rect = options.mapRect
        let a = MKMapPoint(x: rect.minX, y: rect.minY)
        let b = MKMapPoint(x: rect.maxX, y: rect.minY)
        let c = MKMapPoint(x: rect.minX, y: rect.maxY)
        func projected(_ mapPoint: MKMapPoint) -> CGPoint {
            let p = snapshot.point(for: mapPoint.coordinate)
            return CGPoint(x: p.x * imageScale, y: p.y * imageScale)
        }
        let pa = projected(a), pb = projected(b), pc = projected(c)
        let dx = pb.x - pa.x, dy = pb.y - pa.y, ex = pc.x - pa.x, ey = pc.y - pa.y
        let determinant = dx * ey - dy * ex
        guard abs(determinant) > 1 else { throw EvidenceError.imageEncoding }
        func coordinate(_ p: CGPoint) -> Coordinate {
            let x = p.x - pa.x, y = p.y - pa.y
            let u = (x * ey - y * ex) / determinant, v = (dx * y - dy * x) / determinant
            let value = MKMapPoint(x: a.x + Double(u) * rect.width, y: a.y + Double(v) * rect.height).coordinate
            return Coordinate(lon: value.longitude, lat: value.latitude)
        }
        let centre = MKMapPoint(x: rect.midX, y: rect.midY)
        let mpp = rect.width / Double(hypot(dx, dy)) * MKMetersPerMapPointAtLatitude(centre.coordinate.latitude)
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        let seeds = clipped(constructed.map { $0.map(point) }, to: frame)
        let raster = AppleMapRaster(width: width, height: height, rgba: pixels)
        let task = Task.detached(priority: .userInitiated) {
            let masks = try textMasks(raster)
            let analysis = AppleMapRailExtractor.analyze(raster, seedPaths: seeds, metresPerPixel: mpp, masks: masks,
                evidenceMode: evidenceMode, cartographicPalette: cartographicPalette)
            try Task.checkCancellation()
            var platforms: [AppleMapPlatformCandidate] = []
            if analyzePlatforms {
                // Platform colour proposes search windows only. Local paired
                // dark glyph probes supply independent rail evidence, preserving
                // the same OCR masks and unsupported gaps as ordinary extraction.
                let frames = AppleMapRailExtractor.analyzePlatforms(raster, railPaths: [], metresPerPixel: mpp, masks: masks)
                let localRail = AppleMapRailExtractor.analyze(raster, seedPaths: frames.map(\.axis),
                    metresPerPixel: mpp, masks: masks, evidenceMode: .physicalRailGlyph)
                platforms = AppleMapRailExtractor.analyzePlatforms(raster,
                    railPaths: (evidenceMode == .physicalRailGlyph ? analysis.paths : []) + localRail.paths,
                    metresPerPixel: mpp, masks: masks)
            }
            try Task.checkCancellation()
            return (analysis, masks, platforms)
        }
        let (analysis, masks, platforms) = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        try Task.checkCancellation()
        var comparisons: [AppleStationMatch] = []
        // Search only named stations on the visible selected railway. A nearby
        // unrelated bus stop is not substituted for a failed station lookup.
        let visible = stations.filter { frame.contains(point($0.coordinate)) }.sorted {
            hypot(point($0.coordinate).x - frame.midX, point($0.coordinate).y - frame.midY)
                < hypot(point($1.coordinate).x - frame.midX, point($1.coordinate).y - frame.midY)
        }
        for seed in visible.prefix(3) {
            try Task.checkCancellation()
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = seed.name + "駅"
            request.region = MKCoordinateRegion(center: seed.coordinate.native, latitudinalMeters: 900, longitudinalMeters: 900)
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
            do {
                let response = try await MKLocalSearch(request: request).start()
                let matches = response.mapItems.compactMap { item -> (String, Coordinate, CGPoint, Double)? in
                    guard let name = item.name,
                          normalized(name) == normalized(seed.name) || seed.nameRoma.map({ normalized(name) == normalized($0) }) == true else { return nil }
                    let native = item.placemark.coordinate
                    let candidate = Coordinate(lon: native.longitude, lat: native.latitude)
                    let distance = Geometry.distanceMeters(seed.coordinate, candidate)
                    guard distance <= 300, frame.contains(point(candidate)) else { return nil }
                    return (name, candidate, point(candidate), distance)
                }
                comparisons.append(.init(seed: seed, seedPixel: point(seed.coordinate), matches: matches,
                    note: matches.isEmpty ? "Apple 未返回同名车站候选" : "Apple 车站 POI；不等于站台中心"))
            } catch {
                try Task.checkCancellation()
                comparisons.append(.init(seed: seed, seedPixel: point(seed.coordinate), matches: [], note: "Apple 车站搜索未完成：\(error.localizedDescription)"))
            }
        }
        return .init(image: snapshot.image, pixelSize: CGSize(width: width, height: height), constructed: seeds,
                     analysis: analysis, coordinates: analysis.paths.map { $0.map(coordinate) }, stations: comparisons,
                     platformCandidates: platforms, platformCoordinates: platforms.map { $0.polygon.map(coordinate) },
                     platformMidpointCoordinates: platforms.map { coordinate($0.midpoint) },
                     platformRailCoordinates: platforms.map { $0.railMidpoint.map(coordinate) },
                     masks: masks, mapRect: rect, lineID: lineID, intervalIndex: intervalIndex, metresPerPixel: mpp,
                     cartographicPalette: cartographicPalette)
    }

    nonisolated private static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "Station", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "駅", with: "").filter { $0.isLetter || $0.isNumber }.lowercased()
    }

    private static func rgba(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let success = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard success else { throw EvidenceError.imageEncoding }
        return pixels
    }

    nonisolated private static func textMasks(_ raster: AppleMapRaster) throws -> [CGRect] {
        guard let provider = CGDataProvider(data: Data(raster.rgba) as CFData),
              let image = CGImage(width: raster.width, height: raster.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: raster.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw EvidenceError.imageEncoding }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).map { observation in
            let box = observation.boundingBox
            return CGRect(x: box.minX * Double(raster.width), y: (1 - box.maxY) * Double(raster.height),
                          width: box.width * Double(raster.width), height: box.height * Double(raster.height)).insetBy(dx: -2, dy: -2)
        }
    }

    private static func clipped(_ paths: [[CGPoint]], to rect: CGRect) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        for path in paths {
            var run: [CGPoint] = []
            for (a, b) in zip(path, path.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y
                var low = 0.0, high = 1.0, accepted = true
                for (p, q) in [(-dx, a.x - rect.minX), (dx, rect.maxX - a.x), (-dy, a.y - rect.minY), (dy, rect.maxY - a.y)] {
                    if abs(p) < 1e-9 { if q < 0 { accepted = false }; continue }
                    let value = q / p
                    if p < 0 { low = max(low, value) } else { high = min(high, value) }
                    if low > high { accepted = false; break }
                }
                if accepted {
                    let start = CGPoint(x: a.x + low * dx, y: a.y + low * dy)
                    let end = CGPoint(x: a.x + high * dx, y: a.y + high * dy)
                    if let last = run.last, hypot(last.x - start.x, last.y - start.y) > 1 {
                        if run.count > 1 { result.append(run) }; run = []
                    }
                    if run.isEmpty { run.append(start) }; run.append(end)
                } else { if run.count > 1 { result.append(run) }; run = [] }
            }
            if run.count > 1 { result.append(run) }
        }
        return result
    }
}
