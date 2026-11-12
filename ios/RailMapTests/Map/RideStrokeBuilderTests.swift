import CoreLocation
import Foundation
import MapKit
import RailCore
import RailPresentation
import Testing

@testable import RailMap

/// U5: the off-main stroke builder draws exactly what the main-actor path
/// drew. The reference below is an independent transcription of the original
/// `ridePolylines` miss path (slice a built chain or lane-offset the segment's
/// own coordinates, then Douglas-Peucker); the builder must equal it vertex for
/// vertex.
///
/// Geometry is synthetic, seeded per sample-trip shape: 287 rides (the oracle's
/// distinct sample-trip count) of 2 to 14 segments, a mix of segments sliced
/// from 60 built chains (several rides on the same span) and fallback segments,
/// plus the degenerate cases (too few points, a slice that comes back empty).
/// The oracle fixture stores no coordinates, so real solved polylines are
/// compared by the app-control run, not here.
@MainActor
struct RideStrokeBuilderTests {

    private struct Generator {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() * Double(range.count)) % range.count
        }
    }

    private static let frame = RideStrokeBuilder.Frame(
        key: "9|2.0|0|1.0|era", mapPointsPerScreenPoint: 305.748, scale: 2.0)

    private static func walk(_ generator: inout Generator, count: Int) -> [Coordinate] {
        var lon = 130 + generator.next() * 14
        var lat = 31 + generator.next() * 13
        return (0..<count).map { _ in
            lon += (generator.next() - 0.45) * 0.02
            lat += (generator.next() - 0.45) * 0.02
            return Coordinate(lon: lon, lat: lat)
        }
    }

    /// A built stroke the way `parallelLaneCoordinates` builds one.
    private static func chain(
        _ id: String, _ generator: inout Generator, frame: RideStrokeBuilder.Frame
    ) -> (id: String, stroke: ContinuousStroke.Stroke) {
        let coordinates = walk(&generator, count: generator.int(40...120))
        let pixels = coordinates.map { coordinate -> ContinuousStroke.Point in
            let point = MKMapPoint(coordinate.clLocation)
            return .init(x: point.x / frame.mapPointsPerScreenPoint,
                         y: point.y / frame.mapPointsPerScreenPoint)
        }
        var measures = [Double](repeating: 0, count: coordinates.count)
        for index in 1..<coordinates.count {
            measures[index] = measures[index - 1]
                + Geometry.distanceMeters(coordinates[index - 1], coordinates[index])
        }
        let total = measures.last ?? 0
        let scale = frame.scale
        let stroke = ContinuousStroke.buildStroke(pixels, options: .init(
            measures: measures, rows: [.init(from: 0, to: total, lane: 0)], totalMetres: total,
            laneGapPx: Double(RailStyle.parallelLaneCentreDistance * scale),
            minRampPx: RailStyle.strokeMinRamp,
            cornerRadiusPx: Double(RailStyle.strokeCornerRadius * scale),
            minCornerRadiusPx: Double(RailStyle.minimumCornerRadius(atScale: scale)),
            anchors: [0, pixels.count - 1], enforceMinimumCornerRadius: true,
            curveCentreline: true,
            hardCornerMaxDeviationPx: Double(RailStyle.hardCornerMaxDeviation(atScale: scale)),
            railWidthPx: Double(RailStyle.railWidth * scale)))
        return (id, stroke)
    }

    private static func requests(frame: RideStrokeBuilder.Frame) -> [RideStrokeBuilder.Request] {
        var generator = Generator(state: 0x5EED_2026_1111)
        let chains = (0..<60).map { chain("chain-\($0)", &generator, frame: frame) }
        var requests: [RideStrokeBuilder.Request] = []
        for ride in 0..<287 {
            for part in 0..<generator.int(2...14) {
                let key = RideLineCacheKey(
                    rideID: "ride-\(ride)", geometryDigest: ride, segmentIndex: part,
                    partIndex: 0, stroke: .init(lineID: "chain", generation: 1, from: 0, to: 1))
                let coordinates = walk(&generator, count: generator.int(0...80))
                let latitude = coordinates.first?.lat ?? 35
                let kind = generator.int(0...9)
                if kind < 6 {
                    // Sliced from a built chain; chains are shared by span.
                    let chain = chains[generator.int(0...59)]
                    let last = chain.stroke.measures.last ?? 0
                    let span = generator.int(0...3)
                    let from = last * Double(span) * 0.1
                    let to = kind == 0 ? from : last * (Double(span) * 0.1 + 0.4)
                    requests.append(.init(
                        key: key, coordinates: coordinates, latitude: latitude,
                        stroke: .init(
                            chainID: chain.id, points: chain.stroke.points,
                            measures: chain.stroke.measures,
                            mapPointsPerScreenPoint: frame.mapPointsPerScreenPoint,
                            from: from, to: to)))
                } else {
                    requests.append(.init(
                        key: key, coordinates: coordinates, latitude: latitude, stroke: nil))
                }
            }
        }
        return requests
    }

    /// The original miss path, transcribed.
    private static func reference(
        _ request: RideStrokeBuilder.Request, frame: RideStrokeBuilder.Frame
    ) -> [CLLocationCoordinate2D]? {
        func built() -> [CLLocationCoordinate2D]? {
            if let source = request.stroke {
                let sliced = ContinuousStroke.slice(
                    points: source.points, measures: source.measures,
                    from: source.from, to: source.to)
                guard sliced.count >= 2 else { return nil }
                return sliced.map {
                    MKMapPoint(x: $0.x * source.mapPointsPerScreenPoint,
                               y: $0.y * source.mapPointsPerScreenPoint).coordinate
                }
            }
            guard request.coordinates.count >= 2 else { return nil }
            return parallelLaneCoordinates(
                request.coordinates.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                lane: 0, mapPointsPerScreenPoint: frame.mapPointsPerScreenPoint, scale: frame.scale)
        }
        let ink = built()
        let raw = request.coordinates.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let stroke = (ink ?? raw).map { Coordinate(lon: $0.longitude, lat: $0.latitude) }
        guard stroke.count >= 2 else { return nil }
        let epsilon = ink == nil
            ? MKMetersPerMapPointAtLatitude(request.latitude) * frame.mapPointsPerScreenPoint
                * RailStyle.simplifyTolerance
            : 0
        let kept = Geometry.douglasPeuckerIndices(stroke, epsilonMeters: epsilon)
        let points = kept.map { CLLocationCoordinate2D(latitude: stroke[$0].lat, longitude: stroke[$0].lon) }
        return points.count >= 2 ? points : nil
    }

    private static func points(of polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var buffer = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&buffer, range: NSRange(location: 0, length: polyline.pointCount))
        return buffer
    }

    private static func identical(_ a: [CLLocationCoordinate2D], _ b: [CLLocationCoordinate2D]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.latitude.bitPattern == $1.latitude.bitPattern
                && $0.longitude.bitPattern == $1.longitude.bitPattern
        }
    }

    @Test("the builder draws the same vertices as the main-actor path for every segment")
    func builderEqualsMainActorPath() {
        let frame = Self.frame
        let requests = Self.requests(frame: frame)
        let output = RideStrokeBuilder.build(requests, frame: frame, memo: .init())
        let byKey = Dictionary(output.built.map { ($0.key, $0.polyline) }, uniquingKeysWith: { first, _ in first })

        var drawn = 0
        var empty = 0
        for request in requests {
            // The original path handed its points to `MKPolyline`, which keeps
            // projected map points; compare what each polyline holds.
            let expected = Self.reference(request, frame: frame).map {
                Self.points(of: MKPolyline(coordinates: $0, count: $0.count))
            }
            let actual = byKey[request.key].map(Self.points(of:))
            switch (expected, actual) {
            case (nil, nil): empty += 1
            case let (expected?, actual?):
                drawn += 1
                #expect(Self.identical(expected, actual), "polyline differs for \(request.key)")
            default:
                Issue.record("drawn/not drawn disagree for \(request.key)")
            }
        }
        #expect(drawn > 1_000, "the fixture must exercise real polylines (\(drawn))")
        #expect(empty > 0, "the fixture must include segments that draw nothing")
        #expect(output.shared > 0, "rides on the same chain span share one simplification")
        print("RideStrokeBuilderTests: \(requests.count) segments, \(drawn) drawn, \(empty) empty, \(output.shared) shared")
    }

    @Test("a second build is answered from the memo with the same vertices")
    func memoisedBuildIsIdentical() {
        let frame = Self.frame
        let requests = Self.requests(frame: frame).filter { $0.stroke != nil }
        let memo = RideStrokeBuilder.Memo()
        let first = RideStrokeBuilder.build(requests, frame: frame, memo: memo)
        let second = RideStrokeBuilder.build(requests, frame: frame, memo: memo)
        // Every request whose slice succeeded hits the memo; one whose slice
        // came back empty draws its own coordinates and is never shared.
        #expect(second.shared >= first.shared + 1)
        #expect(second.shared <= second.built.count)
        #expect(first.built.map(\.key) == second.built.map(\.key))
        for (a, b) in zip(first.built, second.built) {
            #expect(Self.identical(Self.points(of: a.polyline), Self.points(of: b.polyline)))
            #expect(a.polyline !== b.polyline, "each ride keeps its own MKPolyline")
        }
        // A different frame never reuses another frame's points.
        let other = RideStrokeBuilder.Frame(
            key: "10|2.0|0|1.0|era", mapPointsPerScreenPoint: frame.mapPointsPerScreenPoint / 2,
            scale: frame.scale)
        #expect(memo.points(for: requests[0].shareKey(frame: frame) ?? "", frame: other) == nil)
    }

    @Test("the builder runs off the main actor and finishes a full redraw's worth quickly")
    func buildsOnAWorker() async {
        let frame = Self.frame
        let requests = Self.requests(frame: frame)
        let clock = ContinuousClock()
        let started = clock.now
        let onMain = await Task.detached(priority: .userInitiated) { () -> (Bool, Int) in
            let output = RideStrokeBuilder.build(requests, frame: frame, memo: .init())
            return (pthread_main_np() != 0, output.built.count)
        }.value
        let elapsed = clock.now - started
        #expect(onMain.0 == false, "the build ran on the main thread")
        #expect(onMain.1 > 1_000)
        print("RideStrokeBuilderTests: worker build of \(requests.count) segments took \(elapsed)")
    }

    @Test("the default mode is today's main-actor path")
    func defaultModeIsMainActor() {
        #expect(RideStrokeBuilder.Mode.current == .mainActor)
    }

    private static func plainKey(_ ride: String) -> RideLineCacheKey {
        RideLineCacheKey(rideID: ride, geometryDigest: 0, segmentIndex: 0, partIndex: 0, stroke: nil)
    }

    @Test("a segment that draws nothing is reported as empty, not dropped silently")
    func degenerateSegmentsAreReportedEmpty() {
        let frame = Self.frame
        let lone = RideStrokeBuilder.Request(
            key: Self.plainKey("lone"), coordinates: [Coordinate(lon: 139.7, lat: 35.7)], latitude: 35.7, stroke: nil)
        let none = RideStrokeBuilder.Request(
            key: Self.plainKey("none"), coordinates: [], latitude: 35.7, stroke: nil)
        let fine = RideStrokeBuilder.Request(
            key: Self.plainKey("fine"),
            coordinates: [Coordinate(lon: 139.7, lat: 35.7), Coordinate(lon: 139.8, lat: 35.8)],
            latitude: 35.7, stroke: nil)
        let output = RideStrokeBuilder.build([lone, none, fine], frame: frame, memo: .init())
        #expect(output.built.map(\.key) == [Self.plainKey("fine")])
        #expect(Set(output.empty) == [Self.plainKey("lone"), Self.plainKey("none")])
    }

    @Test("clearing the memo forgets shared points")
    func memoRemoveAll() {
        let frame = Self.frame
        let requests = Self.requests(frame: frame).filter { $0.stroke != nil }
        let memo = RideStrokeBuilder.Memo()
        _ = RideStrokeBuilder.build(requests, frame: frame, memo: memo)
        #expect(memo.count > 0)
        memo.removeAll()
        #expect(memo.count == 0)
        #expect(memo.points(for: requests[0].shareKey(frame: frame) ?? "", frame: frame) == nil)
    }
}
