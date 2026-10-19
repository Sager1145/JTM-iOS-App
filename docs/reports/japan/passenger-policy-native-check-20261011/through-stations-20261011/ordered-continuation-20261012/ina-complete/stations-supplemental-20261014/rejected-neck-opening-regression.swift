
#if os(macOS)
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
    print("SHIKU_REGIONS", result.map { ($0.midpoint, $0.axis, $0.reason) })
    #expect(result.contains { hypot($0.midpoint.x - 558, $0.midpoint.y - 397) < 15 })
    #expect(result.allSatisfy { hypot($0.axis[1].x - $0.axis[0].x, $0.axis[1].y - $0.axis[0].y) * 0.24079648697591033 < 80 })
    #expect(result.allSatisfy { $0.railMidpoint == nil && $0.status == "unresolved" })
}
#endif
