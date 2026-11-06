import Foundation
import Testing
@testable import RailInspection
#if os(macOS)
import CoreGraphics
import ImageIO
#endif

private func glyphRaster(bands: [ClosedRange<Int>]) -> AppleMapRaster {
    let width = 200, height = 200
    var rgba = [UInt8](repeating: 100, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            rgba[i + 3] = 255
            if bands.contains(where: { $0.contains(y) }) {
                rgba[i] = 20; rgba[i + 1] = 20; rgba[i + 2] = 20
            }
        }
    }
    return .init(width: width, height: height, rgba: rgba)
}

private func transitRaster(background: (UInt8, UInt8, UInt8),
                           routes: [(offset: Int, thickness: Int)] = [(8, 1)],
                           broadWater: ClosedRange<Int>? = nil,
                           grayFeatures: Bool = false) -> AppleMapRaster {
    let width = 200, height = 200
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    func curve(_ x: Int) -> Int {
        92 + Int((8 * sin(Double(x - 20) / 160 * .pi)).rounded())
    }
    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            var colour = background
            if let broadWater, broadWater.contains(y) { colour = (38, 126, 184) }
            if grayFeatures && (y == 74 || y == 75 || x == 48 || x == 49 ||
                                ((120...165).contains(x) && (130...165).contains(y) &&
                                 (x == 120 || x == 165 || y == 130 || y == 165))) {
                colour = (92, 96, 100)
            }
            for route in routes {
                if abs(y - curve(x) - route.offset) <= route.thickness {
                    colour = background.0 < 80 ? (45, 132, 236) : (42, 139, 224)
                }
            }
            rgba[index] = colour.0
            rgba[index + 1] = colour.1
            rgba[index + 2] = colour.2
            rgba[index + 3] = 255
        }
    }
    return .init(width: width, height: height, rgba: rgba)
}

private let curvedTransitSeed = [[
    CGPoint(x: 20, y: 92), CGPoint(x: 100, y: 100), CGPoint(x: 180, y: 92)
]]

@Test func appleRailPixelsDetermineOffsetAndBroadRoadHasNoFallback() throws {
    let seeds = [[CGPoint(x: 20, y: 112), CGPoint(x: 180, y: 112)]]
    let pair = AppleMapRailExtractor.analyze(glyphRaster(bands: [116...116, 124...124]),
                                             seedPaths: seeds, metresPerPixel: 1)
    #expect(pair.status == "candidate")
    #expect(pair.supportFraction > 0.9)
    #expect(abs(try #require(pair.medianOffsetMetres) - 8) < 0.1)
    #expect(pair.paths.flatMap { $0 }.allSatisfy { abs($0.y - 120) < 0.1 })
    let masked = AppleMapRailExtractor.analyze(glyphRaster(bands: [116...116, 124...124]),
        seedPaths: seeds, metresPerPixel: 1,
        masks: [CGRect(x: 0, y: 110, width: 200, height: 30)])
    #expect(masked.paths.isEmpty)
    #expect(masked.supportFraction == 0)
    let road = AppleMapRailExtractor.analyze(glyphRaster(bands: [110...135]),
                                             seedPaths: seeds, metresPerPixel: 1)
    #expect(road.paths.isEmpty)
    #expect(road.supportFraction == 0)
    #expect(road.medianOffsetMetres == nil)
}

@Test func appleRailEqualParallelGlyphRivalsStayUnresolved() {
    let result = AppleMapRailExtractor.analyze(
        glyphRaster(bands: [90...90, 98...98, 118...118, 126...126]),
        seedPaths: [[CGPoint(x: 20, y: 108), CGPoint(x: 180, y: 108)]], metresPerPixel: 1)
    #expect(result.samples.contains { $0.ambiguity >= 0.85 })
    #expect(result.paths.isEmpty)
    #expect(result.supportFraction == 0)
}

@Test func appleTransitCartographyRecoversShiftedThinBlueCurveInLightAndDarkMaps() throws {
    for background in [(238, 238, 235), (31, 34, 38)] as [(UInt8, UInt8, UInt8)] {
        let result = AppleMapRailExtractor.analyze(transitRaster(background: background),
            seedPaths: curvedTransitSeed, metresPerPixel: 1,
            evidenceMode: .transitCartography)
        #expect(result.status == "cartographic_candidate")
        #expect(result.reason == "rendered_transit_cartography_candidates")
        #expect(result.supportFraction > 0.8)
        #expect(abs(try #require(result.medianOffsetMetres) - 8) < 1.5)
        #expect(!result.paths.isEmpty)
        #expect(result.samples.filter(\.supported).allSatisfy {
            $0.contrast >= 4 && $0.ambiguity < 0.85
        })
    }
}

@Test func appleTransitCartographyRejectsGrayStructureBroadWaterAndParallelRoutes() {
    let nonTransit = AppleMapRailExtractor.analyze(
        transitRaster(background: (238, 238, 235), routes: [], broadWater: 82...118,
                      grayFeatures: true),
        seedPaths: curvedTransitSeed, metresPerPixel: 1,
        evidenceMode: .transitCartography)
    #expect(nonTransit.status == "no_cartographic_candidate")
    #expect(nonTransit.paths.isEmpty)
    #expect(nonTransit.supportFraction == 0)

    let rivals = AppleMapRailExtractor.analyze(
        transitRaster(background: (238, 238, 235),
                      routes: [(offset: -8, thickness: 1), (offset: 8, thickness: 1)]),
        seedPaths: curvedTransitSeed, metresPerPixel: 1,
        evidenceMode: .transitCartography)
    #expect(rivals.samples.contains { $0.ambiguity >= 0.85 })
    #expect(rivals.paths.isEmpty)
    #expect(rivals.supportFraction == 0)
}

@Test func appleTransitCartographyMaskCreatesUnsupportedGapWithoutBridging() {
    let result = AppleMapRailExtractor.analyze(
        transitRaster(background: (238, 238, 235)), seedPaths: curvedTransitSeed,
        metresPerPixel: 1, masks: [CGRect(x: 82, y: 88, width: 36, height: 28)],
        evidenceMode: .transitCartography)
    #expect(result.status == "cartographic_candidate")
    #expect(result.samples.contains { !$0.supported })
    #expect(result.paths.count >= 2)
    #expect(result.paths.allSatisfy { path in
        guard let first = path.first, let last = path.last else { return false }
        return max(first.x, last.x) < 82 || min(first.x, last.x) > 118
    })
}

#if os(macOS)
@Test func appleRailExistingShiohamaPixelsProvidePartialGlyphEvidence() throws {
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { repository.deleteLastPathComponent() }
    let url = repository.appendingPathComponent(
        "docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/keiyo/west-long-review/main-shiohama-detail-basemap.png")
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    // Existing screenshot only: crop the unobscured railway rectangle away
    // from app chrome. Map labels remain and must become unsupported gaps.
    let cropped = try #require(image.cropping(to: CGRect(x: 610, y: 260, width: 360, height: 490)))
    var rgba = [UInt8](repeating: 0, count: cropped.width * cropped.height * 4)
    try rgba.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(data: buffer.baseAddress,
            width: cropped.width, height: cropped.height, bitsPerComponent: 8,
            bytesPerRow: cropped.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
    }
    let result = AppleMapRailExtractor.analyze(
        .init(width: cropped.width, height: cropped.height, rgba: rgba),
        seedPaths: [[CGPoint(x: 70, y: 470), CGPoint(x: 240, y: 40)]], metresPerPixel: 1)
    #expect(result.status == "candidate")
    #expect(result.supportFraction > 0.1)
    #expect(!result.paths.isEmpty)
    #expect(result.samples.contains { !$0.supported })
    #expect(result.samples.filter(\.supported).allSatisfy { $0.contrast >= 4 && $0.ambiguity < 0.85 })
}
#endif

private func platformRaster(second: Bool = false, water: Bool = false) -> AppleMapRaster {
    let width = 200, height = 200
    var rgba = [UInt8](repeating: 230, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            rgba[i + 3] = 255
            if (40...120).contains(x) && (100...105).contains(y) ||
                second && (40...120).contains(x) && (120...125).contains(y) ||
                water && (0...199).contains(x) && (150...195).contains(y) {
                rgba[i] = 104; rgba[i + 1] = 128; rgba[i + 2] = 178
            }
        }
    }
    return .init(width: width, height: height, rgba: rgba)
}

@Test func applePlatformMidpointUsesVisibleExtentAndSupportedRailRatherThanStationSeed() throws {
    let result = AppleMapRailExtractor.analyzePlatforms(platformRaster(water: true),
        railPaths: [[CGPoint(x: 20, y: 96), CGPoint(x: 150, y: 96)]], metresPerPixel: 1)
    let candidate = try #require(result.first { $0.status == "platform_cartography_midpoint_candidate" })
    #expect(abs(candidate.midpoint.x - 80) < 1)
    #expect(abs(try #require(candidate.railMidpoint).y - 96) < 1)
    #expect(result.count == 1)
}

@Test func applePlatformMissingRailMasksAndParallelGroupsStayUnresolved() {
    let rail = [[CGPoint(x: 20, y: 96), CGPoint(x: 150, y: 96)]]
    let unsupported = AppleMapRailExtractor.analyzePlatforms(platformRaster(), railPaths: [], metresPerPixel: 1)
    #expect(unsupported.count == 1)
    #expect(unsupported.allSatisfy { $0.railMidpoint == nil && $0.status == "unresolved" })
    let masked = AppleMapRailExtractor.analyzePlatforms(platformRaster(), railPaths: rail,
        metresPerPixel: 1, masks: [CGRect(x: 70, y: 90, width: 20, height: 20)])
    #expect(masked.count == 2)
    #expect(masked.allSatisfy { $0.status == "unresolved" && $0.railMidpoint == nil })
    let rivals = AppleMapRailExtractor.analyzePlatforms(platformRaster(second: true),
        railPaths: rail + [[CGPoint(x: 20, y: 116), CGPoint(x: 150, y: 116)]], metresPerPixel: 1)
    #expect(rivals.count == 2)
    #expect(rivals.allSatisfy { $0.status == "unresolved" && $0.ambiguity == 1 })
}

#if os(macOS)
@Test func applePlatformFrozenManyoFramesRetainVisiblePlatformsWithoutOldStationChainage() throws {
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { repository.deleteLastPathComponent() }
    let folder = repository.appendingPathComponent("docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012")
    for (name, expected) in [
        ("manyo-koshinokata-interval6-first-extraction-before", CGPoint(x: 236, y: 219)),
        ("manyo-east-interval5-view0-extraction-before", CGPoint(x: 428, y: 307)),
        ("manyo-koshinokata-interval6-last-extraction-before", CGPoint(x: 464, y: 307)),
        ("manyo-rokudoji-shin-interval0-view0-extraction-before", CGPoint(x: 577, y: 288))
    ] {
        let url = folder.appendingPathComponent(name + "/apple-map-extraction/basemap.png")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        // No supplied rail paths: visible platform shapes must remain unresolved.
        let candidates = AppleMapRailExtractor.analyzePlatforms(
            .init(width: image.width, height: image.height, rgba: rgba), railPaths: [], metresPerPixel: 0.477)
        #expect(candidates.contains { hypot($0.midpoint.x - expected.x, $0.midpoint.y - expected.y) < 12 })
        #expect(candidates.allSatisfy { $0.railMidpoint == nil && $0.status == "unresolved" })
    }
}
#endif

#if os(macOS)
@Test func appleToyamaBlueRailwayExcludesIndependentCyanRoadsideLine() throws {
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { repository.deleteLastPathComponent() }
    let base = repository.appendingPathComponent("docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/toyama-port-complete")
    let capture = base.appendingPathComponent("native/primary/captures/003316/000002")
    let source = try #require(CGImageSourceCreateWithURL(capture.appendingPathComponent("basemap.png") as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try rgba.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    let view = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: capture.appendingPathComponent("view.json"))) as? [String: Any])
    let rect = try #require(view["mapRect"] as? [String: Double])
    let paths = try #require(view["renderedSmooth"] as? [[[Double]]])
    let seeds = paths.map { path in path.map { coordinate in
        let x = (coordinate[0] + 180) / 360 * 268435456
        let y = (1 - asinh(tan(coordinate[1] * .pi / 180)) / .pi) / 2 * 268435456
        return CGPoint(x: (x - rect["x"]!) / rect["width"]! * Double(image.width),
                       y: (y - rect["y"]!) / rect["height"]! * Double(image.height))
    } }
    let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: base.appendingPathComponent("pixel-analysis-baseline/04-02.json"))) as? [String: Any])
    let masks = try #require(saved["textMasks"] as? [[Double]]).map {
        CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3])
    }
    let result = AppleMapRailExtractor.analyze(.init(width: image.width, height: image.height, rgba: rgba),
        seedPaths: seeds, metresPerPixel: 0.9544483010977206, masks: masks,
        evidenceMode: .transitCartography, cartographicPalette: .blueRailway)
    #expect(result.supportFraction > 0.6)
    #expect(try #require(result.medianOffsetMetres) < 4)
    // The independently visible cyan line runs around x455 here; the own railway is around x490.
    let middle = result.samples.filter { $0.supported && (480...550).contains($0.point.y) }
    #expect(!middle.isEmpty)
    #expect(middle.allSatisfy { $0.point.x > 475 })
}

@Test func applePlatformShikuNarrowConnectionsDoNotInventOneLongPassengerFrame() throws {
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { repository.deleteLastPathComponent() }
    let url = repository.appendingPathComponent("docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/ina-complete/stations-supplemental-20261014/09-shiku-extraction-z19/basemap.png")
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try rgba.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    let result = AppleMapRailExtractor.analyzePlatforms(.init(width: image.width, height: image.height, rgba: rgba),
        railPaths: [], metresPerPixel: 0.24079648697591033)
    #expect(result.contains { hypot($0.midpoint.x - 558, $0.midpoint.y - 397) < 15 })
    #expect(result.allSatisfy { hypot($0.axis[1].x - $0.axis[0].x, $0.axis[1].y - $0.axis[0].y) * 0.24079648697591033 < 80 })
    #expect(result.allSatisfy { $0.railMidpoint == nil && $0.status == "unresolved" })
    let locallySupported = AppleMapRailExtractor.analyzePlatforms(.init(width: image.width, height: image.height, rgba: rgba),
        railPaths: [[CGPoint(x: 500, y: 220), CGPoint(x: 650, y: 650)]], metresPerPixel: 0.24079648697591033)
    #expect(locallySupported.contains { $0.support == 1 })
    #expect(locallySupported.allSatisfy { $0.railMidpoint == nil && $0.status == "unresolved" })
}
#endif
