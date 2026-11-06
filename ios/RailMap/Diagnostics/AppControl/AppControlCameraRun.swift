#if DEBUG
import MapKit
import QuartzCore
import RailPresentation
import UIKit

/// One `camera` command: moves the map through `RailMapController` and reports
/// what the run cost. Nothing here draws or builds; it only reads the map's own
/// render-status label, `MapRenderProbe` and `RenderStats`, and counts frames.
@MainActor
struct AppControlCameraRun {
    let controller: RailMapController
    let renderStats: () -> RailMapView.RenderStats?

    /// The map has to be quiet this long (same camera, same rebuild count) to end a run.
    private static let quietMilliseconds = 400
    private static let settleLimitMilliseconds = 8_000

    func run(_ action: AppControlCameraAction) async throws -> AppControlJSON {
        guard let mapView = controller.mapView, mapView.bounds.width > 0 else {
            throw AppControlError.unavailable("map not mounted")
        }
        let start = Self.cameraState(mapView)
        var steps = 1
        switch action {
        case .set, .fit: break
        case .pan(_, _, let count, _): steps = count
        case .zoom(let from, _, let count, _):
            steps = count
            if let from {
                // The ramp's own starting point is not part of the measured run.
                controller.setCameraForUITest(center: mapView.centerCoordinate, zoom: from, animated: false)
                _ = await settle(mapView)
            }
        }
        let origin = Self.cameraState(mapView)

        let before = Self.counters(statusText: AppControlHost.renderStatusText())
        let footprintBefore = DevPerfSampler.footprintMB()
        let waitsBefore = (MapRenderProbe.geometryWaits, MapRenderProbe.maxGeometryWaitMilliseconds)
        let meter = RunMeter(statusText: { AppControlHost.renderStatusText() })
        meter.start()
        let started = ContinuousClock.now

        switch action {
        case .set(let lat, let lon, let zoom, let animated):
            controller.setCameraForUITest(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                zoom: zoom ?? origin.zoom, animated: animated)
        case .fit(let target):
            switch target {
            case .network: controller.fitToNetwork()
            case .selection: controller.fitToSelection()
            }
        case .pan(let dLat, let dLon, let count, let stepMs):
            for index in 1...count {
                let fraction = Double(index) / Double(count)
                let latitude = min(max(origin.lat + dLat * fraction, -85), 85)
                var longitude = origin.lon + dLon * fraction
                longitude = (longitude + 540).truncatingRemainder(dividingBy: 360) - 180
                controller.setCameraForUITest(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    zoom: origin.zoom, animated: false)
                try await pace(stepMs)
            }
        case .zoom(_, let to, let count, let stepMs):
            for index in 1...count {
                let zoom = origin.zoom + (to - origin.zoom) * Double(index) / Double(count)
                controller.setCameraForUITest(center: origin.center, zoom: zoom, animated: false)
                try await pace(stepMs)
            }
        }
        let movedMs = AppControlHost.ms(since: started)
        let settleMs = await settle(mapView)
        meter.stop()

        let end = Self.cameraState(mapView)
        let after = Self.counters(statusText: AppControlHost.renderStatusText())
        let footprintAfter = DevPerfSampler.footprintMB()
        let stats = renderStats()
        func round(_ value: Double, _ places: Double = 10) -> AppControlJSON {
            .number((value * places).rounded() / places)
        }
        let builds = meter.buildMilliseconds.sorted()
        func percentile(_ fraction: Double) -> AppControlJSON {
            guard !builds.isEmpty else { return .null }
            return .number(builds[min(builds.count - 1, Int((Double(builds.count - 1) * fraction).rounded(.up)))])
        }
        return [
            "action": .string(action.name),
            "steps": .number(Double(steps)),
            "camera": [
                "from": start.json, "to": end.json,
            ],
            "durationMs": .number(movedMs),
            "settleMs": .number(settleMs),
            "frames": .number(Double(meter.frames)),
            "maxGapMs": round(meter.maximumGapMilliseconds),
            "hitches": .number(Double(meter.hitches)),
            "rebuilds": .number(Double(after.rebuilds - before.rebuilds)),
            "gestureBuilds": .number(Double(after.gestureBuilds - before.gestureBuilds)),
            "buildMs": [
                "samples": .number(Double(builds.count)), "p50": percentile(0.5), "p95": percentile(0.95),
                "max": builds.last.map { .number($0) } ?? .null,
            ],
            "overlays": stats.map { .number(Double($0.overlays)) } ?? .null,
            "vertices": stats.map { .number(Double($0.vertices)) } ?? .null,
            "geometryWait": [
                "count": .number(Double(MapRenderProbe.geometryWaits - waitsBefore.0)),
                "maxMs": .number(Double(MapRenderProbe.maxGeometryWaitMilliseconds)),
                "maxMsBefore": .number(Double(waitsBefore.1)),
            ],
            "footprintMB": [
                "before": round(footprintBefore), "after": round(footprintAfter),
                "delta": round(footprintAfter - footprintBefore),
            ],
        ]
    }

    private func pace(_ stepMs: Int) async throws {
        if stepMs > 0 { try await Task.sleep(for: .milliseconds(stepMs)) } else { await Task.yield() }
    }

    /// Waits until the camera and the rebuild count stop changing. Returns the wait in ms.
    private func settle(_ mapView: MKMapView) async -> Double {
        let started = ContinuousClock.now
        var last = Self.signature(mapView)
        var quietSince = ContinuousClock.now
        while AppControlHost.ms(since: quietSince) < Double(Self.quietMilliseconds),
              AppControlHost.ms(since: started) < Double(Self.settleLimitMilliseconds) {
            try? await Task.sleep(for: .milliseconds(50))
            let current = Self.signature(mapView)
            if current != last { last = current; quietSince = .now }
        }
        return AppControlHost.ms(since: started)
    }

    private static func signature(_ mapView: MKMapView) -> String {
        let counts = counters(statusText: AppControlHost.renderStatusText())
        let camera = cameraState(mapView)
        return "\(counts.rebuilds)|\(camera.lat)|\(camera.lon)|\(camera.zoom)"
    }

    struct CameraState {
        var lat: Double
        var lon: Double
        var zoom: Double
        var center: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
        var json: AppControlJSON {
            ["lat": .number((lat * 1e6).rounded() / 1e6), "lon": .number((lon * 1e6).rounded() / 1e6),
             "zoom": .number((zoom * 100).rounded() / 100)]
        }
    }

    private static func cameraState(_ mapView: MKMapView) -> CameraState {
        CameraState(
            lat: mapView.centerCoordinate.latitude, lon: mapView.centerCoordinate.longitude,
            zoom: MapProjection.zoomLevel(of: mapView))
    }

    /// `rebuilds`, `gestureBuilds` and `buildMs` from the map's render-status label.
    struct Counters { var rebuilds = 0; var gestureBuilds = 0; var buildMs = 0 }

    static func counters(statusText: String?) -> Counters {
        guard let statusText else { return Counters() }
        var result = Counters()
        for field in statusText.split(separator: ";") {
            guard let colon = field.firstIndex(of: ":") else { continue }
            let value = Int(field[field.index(after: colon)...]) ?? 0
            switch field[..<colon] {
            case "rebuilds": result.rebuilds = value
            case "gestureBuilds": result.gestureBuilds = value
            case "buildMs": result.buildMs = value
            default: break
            }
        }
        return result
    }
}

/// Display-link frame counter for one run, plus a sampler of the map's build time.
@MainActor
private final class RunMeter: NSObject {
    private let statusText: () -> String?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var ticks = 0
    private var lastRebuilds: Int?
    private(set) var frames = 0
    private(set) var maximumGapMilliseconds = 0.0
    private(set) var hitches = 0
    /// `buildMs` read each time the rebuild count moved between two samples.
    private(set) var buildMilliseconds: [Double] = []

    init(statusText: @escaping () -> String?) { self.statusText = statusText }

    func start() {
        guard link == nil else { return }
        lastRebuilds = AppControlCameraRun.counters(statusText: statusText()).rebuilds
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        sample()
    }

    @objc private func tick(_ link: CADisplayLink) {
        if let lastTimestamp {
            let gap = (link.timestamp - lastTimestamp) * 1000
            maximumGapMilliseconds = max(maximumGapMilliseconds, gap)
            let expected = max(link.targetTimestamp - link.timestamp, 1.0 / 120) * 1000
            if gap > expected * 1.5 + 1 { hitches += 1 }
        }
        lastTimestamp = link.timestamp
        frames += 1
        ticks += 1
        if ticks % 3 == 0 { sample() }
    }

    private func sample() {
        let counters = AppControlCameraRun.counters(statusText: statusText())
        defer { lastRebuilds = counters.rebuilds }
        if let lastRebuilds, counters.rebuilds != lastRebuilds { buildMilliseconds.append(Double(counters.buildMs)) }
    }
}
#endif
