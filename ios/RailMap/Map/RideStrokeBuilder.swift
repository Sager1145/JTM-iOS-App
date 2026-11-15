import CoreLocation
import Foundation
import MapKit
import RailCore
import RailPresentation

/// Ride polylines built off the main actor (trip-loading plan, unit U5).
///
/// Slicing, lane-offsetting and Douglas-Peucker simplification of every ride
/// segment is one pure function,
/// ``polylineCoordinates(for:frame:)``, which works on value inputs only, so a
/// worker can run it. The coordinator captures a ``Request`` per missing
/// segment on the main actor (cheap: array references, no geometry work), the
/// worker answers with polylines, and the main actor only stores and installs
/// them.
///
/// This is the only path: there is no main-actor slicing. The coordinator
/// applies results on main and drops them when their request generation is
/// stale.
///
/// Work is shared between rides on the same track: a request that slices a
/// built chain carries a ``Request/shareKey(frame:)`` of (chain, from, to,
/// frame), and every ride with the same key reuses one simplified point list
/// (each ride still gets its own `MKPolyline`).
nonisolated enum RideStrokeBuilder {

    /// The projection a polyline is drawn for: one zoom frame.
    struct Frame: Sendable, Equatable {
        var key: String
        var mapPointsPerScreenPoint: Double
        var scale: CGFloat
    }

    /// The built continuous stroke a segment is sliced from, copied by value.
    struct StrokeSource: Sendable {
        var chainID: String
        var points: [ContinuousStroke.Point]
        var measures: [Double]
        /// The stroke's own pixel size, from the build it came out of.
        var mapPointsPerScreenPoint: Double
        var from: Double
        var to: Double
    }

    /// One ride segment's inputs, all values.
    struct Request: Sendable {
        /// The trip-line cache key, which names the rail line and its stroke
        /// generation when the segment is sliced from a built chain.
        var key: RideLineCacheKey
        /// The segment's own coordinates (what the fallback draws from).
        var coordinates: [Coordinate]
        /// Latitude of the segment's bounding-rect centre, for the metre epsilon.
        var latitude: Double
        /// Set when the segment resolves into a chain built this frame.
        var stroke: StrokeSource?

        /// Rides with the same key slice the same chain span in the same
        /// frame and so draw the same points. `nil` for a fallback segment:
        /// those are the ride's own geometry.
        func shareKey(frame: Frame) -> String? {
            guard let stroke else { return nil }
            return "\(stroke.chainID)|\(stroke.from)|\(stroke.to)|\(frame.key)"
        }
    }

    /// A built polyline. `MKPolyline` is created off the main actor and then
    /// owned by exactly one consumer, which is why the box is `@unchecked`.
    struct Built: @unchecked Sendable {
        var key: RideLineCacheKey
        var polyline: MKPolyline
    }

    // MARK: - the arithmetic

    /// The points one segment is drawn with, or `nil` when it draws nothing.
    ///
    /// Exactly the miss path of the original `ridePolylines`: slice the built
    /// chain, else lane-offset the segment's own coordinates; then
    /// Douglas-Peucker. The offset/sliced stroke is "built ink" (already
    /// decimated, epsilon 0); the raw fallback owes its metre tolerance.
    static func polylineCoordinates(
        for request: Request, frame: Frame
    ) -> [CLLocationCoordinate2D]? {
        resolve(request, frame: frame)?.points
    }

    /// ``polylineCoordinates(for:frame:)`` plus whether the points came from
    /// the built chain. Only those are a function of the share key alone; a
    /// slice that came back empty falls back to the ride's own coordinates.
    fileprivate static func resolve(
        _ request: Request, frame: Frame
    ) -> (points: [CLLocationCoordinate2D], fromChain: Bool)? {
        let built = builtInk(of: request, frame: frame)
        let stroke = (built ?? request.coordinates.map(\.clLocation)).map {
            Coordinate(lon: $0.longitude, lat: $0.latitude)
        }
        guard stroke.count >= 2 else { return nil }
        let epsilon = built == nil
            ? MKMetersPerMapPointAtLatitude(request.latitude)
                * frame.mapPointsPerScreenPoint * RailStyle.simplifyTolerance
            : 0
        let kept = Geometry.douglasPeuckerIndices(stroke, epsilonMeters: epsilon)
        let points = kept.map { stroke[$0].clLocation }
        guard points.count >= 2 else { return nil }
        return (points, built != nil && request.stroke != nil)
    }

    private static func builtInk(of request: Request, frame: Frame) -> [CLLocationCoordinate2D]? {
        if let source = request.stroke {
            let sliced = ContinuousStroke.slice(
                points: source.points, measures: source.measures,
                from: source.from, to: source.to)
            guard sliced.count >= 2 else { return nil }
            return sliced.map {
                MKMapPoint(
                    x: $0.x * source.mapPointsPerScreenPoint,
                    y: $0.y * source.mapPointsPerScreenPoint
                ).coordinate
            }
        }
        guard request.coordinates.count >= 2 else { return nil }
        return parallelLaneCoordinates(
            request.coordinates.map(\.clLocation), lane: 0,
            mapPointsPerScreenPoint: frame.mapPointsPerScreenPoint, scale: frame.scale)
    }

    // MARK: - the memo

    /// Simplified point lists by share key, valid for one frame. Thread-safe.
    final class Memo: @unchecked Sendable {
        private let lock = NSLock()
        private var frameKey = ""
        private var entries: [String: [CLLocationCoordinate2D]] = [:]
        private static let capacity = 20_000

        func points(for shareKey: String, frame: Frame) -> [CLLocationCoordinate2D]? {
            lock.lock()
            defer { lock.unlock() }
            return frameKey == frame.key ? entries[shareKey] : nil
        }

        func store(_ points: [CLLocationCoordinate2D], for shareKey: String, frame: Frame) {
            lock.lock()
            defer { lock.unlock() }
            if frameKey != frame.key {
                frameKey = frame.key
                entries.removeAll(keepingCapacity: true)
            }
            if entries.count >= Self.capacity { entries.removeAll(keepingCapacity: true) }
            entries[shareKey] = points
        }

        /// Forget everything: a chain's stroke was replaced or the lines changed.
        func removeAll() {
            lock.lock()
            defer { lock.unlock() }
            frameKey = ""
            entries.removeAll(keepingCapacity: true)
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return entries.count
        }
    }

    // MARK: - the worker entry point

    struct Output: Sendable {
        var built: [Built]
        /// Requests answered from the memo or from another request in the batch.
        var shared: Int
        /// Keys of the requests that draw nothing (fewer than two points).
        /// The coordinator remembers them for the frame so it does not ask
        /// for them again.
        var empty: [RideLineCacheKey]
    }

    /// Builds every request. Pure apart from the memo; call from a worker.
    /// Cancellation returns what was built so far.
    ///
    /// A large batch is split by share key across a few child tasks
    /// (``RideBuildPartition``): requests that share a key stay together, so
    /// the sharing counts match one thread's, and the answers are merged back
    /// into request order. One thread took 3.26 s for a warm launch's trips.
    /// The children inherit the caller's cancellation and nothing blocks a
    /// thread while they run.
    static func build(_ requests: [Request], frame: Frame, memo: Memo) async -> Output {
        let interval = RailSignpost.map.begin("map.rideStrokes.build")
        defer { RailSignpost.map.end("map.rideStrokes.build", interval) }
        let maxParts = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1))
        let parts = RideBuildPartition.partition(
            shareKeys: requests.map { $0.shareKey(frame: frame) }, maxParts: maxParts)
        guard parts.count > 1 else {
            return merge([buildPart(Array(requests.indices), requests, frame: frame, memo: memo, cancelled: { Task.isCancelled })])
        }
        let results = await withTaskGroup(of: (Int, Part).self) { group in
            for (position, indices) in parts.enumerated() {
                group.addTask {
                    (position, buildPart(
                        indices, requests, frame: frame, memo: memo, cancelled: { Task.isCancelled }))
                }
            }
            var all = Array(repeating: Part(), count: parts.count)
            for await (position, part) in group { all[position] = part }
            return all
        }
        return merge(results)
    }

    private struct Part: Sendable {
        var built: [(index: Int, value: Built)] = []
        var shared = 0
        var empty: [(index: Int, key: RideLineCacheKey)] = []
    }

    private static func buildPart(
        _ indices: [Int], _ requests: [Request], frame: Frame, memo: Memo, cancelled: () -> Bool
    ) -> Part {
        var part = Part()
        part.built.reserveCapacity(indices.count)
        for index in indices {
            if cancelled() { break }
            let request = requests[index]
            let shareKey = request.shareKey(frame: frame)
            let points: [CLLocationCoordinate2D]
            if let shareKey, let known = memo.points(for: shareKey, frame: frame) {
                points = known
                part.shared += 1
            } else if let fresh = resolve(request, frame: frame) {
                points = fresh.points
                if let shareKey, fresh.fromChain {
                    memo.store(fresh.points, for: shareKey, frame: frame)
                }
            } else {
                part.empty.append((index, request.key))
                continue
            }
            part.built.append((index, Built(
                key: request.key, polyline: MKPolyline(coordinates: points, count: points.count))))
        }
        return part
    }

    /// The parts' answers in original request order.
    private static func merge(_ parts: [Part]) -> Output {
        Output(
            built: parts.flatMap(\.built).sorted { $0.index < $1.index }.map(\.value),
            shared: parts.reduce(0) { $0 + $1.shared },
            empty: parts.flatMap(\.empty).sorted { $0.index < $1.index }.map(\.key))
    }
}
