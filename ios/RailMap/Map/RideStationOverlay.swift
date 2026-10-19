import MapKit
import RailCore
import SwiftUI

final class RideStationOverlay: NSObject, MKOverlay {
    let rideID: String
    var stations: [RideStationAnnotation]
    var transitionDuration: TimeInterval = 0
    var title: String? { "ride-stations|\(rideID)" }
    var coordinate: CLLocationCoordinate2D { stations.first?.coordinate ?? CLLocationCoordinate2D() }
    // Circle sizes are screen points, so a geographic extent cannot describe
    // their footprint at every zoom. The renderer culls against each tile.
    var boundingMapRect: MKMapRect { .world }

    init(rideID: String, stations: [RideStationAnnotation]) {
        self.rideID = rideID
        self.stations = stations
    }
}

final class RideStationOverlayRenderer: MKOverlayRenderer {
    private struct Circle: Equatable {
        let point: MKMapPoint
        let radius: CGFloat
        let lineWidth: CGFloat
        let fill: CGColor
        let stroke: CGColor
        var alpha: CGFloat
        let coreRadius: CGFloat?
        let coreColor: CGColor?

        static func == (lhs: Circle, rhs: Circle) -> Bool {
            lhs.point.x == rhs.point.x && lhs.point.y == rhs.point.y
                && lhs.radius == rhs.radius && lhs.lineWidth == rhs.lineWidth
                && lhs.fill == rhs.fill && lhs.stroke == rhs.stroke
                && lhs.alpha == rhs.alpha && lhs.coreRadius == rhs.coreRadius
                && lhs.coreColor == rhs.coreColor
        }
    }

    private struct Fade {
        let from: CGFloat
        let to: CGFloat
        let startedAt: TimeInterval
        let duration: TimeInterval
    }

    private struct Marker {
        var station: RideStationAnnotation
        var alpha: CGFloat
        var fade: Fade?
        var retiring: Bool
    }

    /// CADisplayLink retains its target; this bridge keeps the renderer weak.
    private final class FrameTarget: NSObject {
        weak var renderer: RideStationOverlayRenderer?
        @objc func tick(_ link: CADisplayLink) { renderer?.advance(at: link.timestamp) }
    }

    // Marker and clock state are updated by the coordinator on the main thread.
    // MapKit tile drawing reads only the locked immutable circle snapshot.
    private var markers: [String: Marker] = [:]
    private var markerOrder: [String] = []
    private var activeFadeKeys: Set<String> = []
    private var circles: [Circle] = []
    private var circleIndexByKey: [String: Int] = [:]
    // Keep former painted positions too: an outgoing dot's tile must still
    // receive an empty redraw after its fade ends. The renderer's lifetime
    // bounds this history to the single shared station canvas.
    private var paintCoverage = MKMapRect.null
    private var paintRadius: CGFloat = 0
    private let circleLock = NSLock()
    private var scale: CGFloat = .nan
    private var zoom: Double = .nan
    private var initialDuration: TimeInterval = 0
    private var hasPublishedStations = false
    private var batchArrival: Fade?
    private var displayLink: CADisplayLink?
    private let frameTarget = FrameTarget()

    deinit { displayLink?.invalidate() }

    func applyScale(_ scale: CGFloat, zoom: Double) {
        guard self.scale != scale || self.zoom != zoom else { return }
        self.scale = scale
        self.zoom = zoom
        if markerOrder.isEmpty {
            updateStations(duration: initialDuration)
        } else {
            // Resize current and departing dots without restarting opacity.
            publishCircles()
        }
    }

    /// Reuse the shared overlay, assign its new station list, then call this.
    /// Calling before the first scale sets the new renderer's arrival timing.
    func updateStations(duration: TimeInterval = 0) {
        guard scale.isFinite, zoom.isFinite else {
            initialDuration = duration
            return
        }
        guard let overlay = overlay as? RideStationOverlay else { return }
        let duration = max(0, duration)
        let now = CACurrentMediaTime()
        _ = sampleFades(at: now)
        if duration == 0 {
            batchArrival = nil
            alpha = 1
        }
        if batchArrival != nil, duration > 0 {
            var occurrences: [String: Int] = [:]
            let unchanged = overlay.stations.count == markers.count && overlay.stations.allSatisfy { station in
                let base = "\(station.rideID)|\(station.coordinate.latitude)|\(station.coordinate.longitude)|\(station.role)|\(station.rawName)"
                let occurrence = occurrences[base, default: 0]
                occurrences[base] = occurrence + 1
                guard let marker = markers["\(base)|\(occurrence)"] else { return false }
                return !marker.retiring && (marker.fade?.to ?? marker.alpha) == station.alpha
            }
            if !unchanged {
                // Preserve the visible opacity when membership changes during
                // batch arrival, then let individual dots retarget their fades.
                let batchAlpha = alpha
                for key in markerOrder {
                    guard var marker = markers[key] else { continue }
                    marker.alpha *= batchAlpha
                    marker.fade = nil
                    markers[key] = marker
                }
                batchArrival = nil
                alpha = 1
            }
        }
        let fadesWholeBatch = !hasPublishedStations && !overlay.stations.isEmpty && duration > 0
        if fadesWholeBatch {
            // A new journey's dots arrive together. Fade the already painted
            // texture in the compositor instead of rasterising every dot on
            // every display-link tick for the shared station canvas.
            batchArrival = Fade(from: 0, to: 1, startedAt: now, duration: duration)
            alpha = 0
        }
        if !overlay.stations.isEmpty { hasPublishedStations = true }
        var occurrences: [String: Int] = [:]
        var desiredKeys: Set<String> = []
        var order: [String] = []
        for station in overlay.stations {
            let base = "\(station.rideID)|\(station.coordinate.latitude)|\(station.coordinate.longitude)|\(station.role)|\(station.rawName)"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            let key = "\(base)|\(occurrence)"
            desiredKeys.insert(key)
            order.append(key)
            if var marker = markers[key] {
                let previousTarget = marker.fade?.to ?? marker.alpha
                marker.station = station
                if marker.retiring || previousTarget != station.alpha {
                    marker.fade = duration > 0 ? Fade(
                        from: marker.alpha, to: station.alpha, startedAt: now, duration: duration) : nil
                    if duration == 0 { marker.alpha = station.alpha }
                }
                marker.retiring = false
                markers[key] = marker
            } else {
                markers[key] = Marker(station: station,
                    alpha: duration > 0 && !fadesWholeBatch ? 0 : station.alpha,
                    fade: duration > 0 && !fadesWholeBatch ? Fade(from: 0, to: station.alpha,
                                             startedAt: now, duration: duration) : nil,
                    retiring: false)
            }
        }
        for key in markerOrder where !desiredKeys.contains(key) {
            guard var marker = markers[key] else { continue }
            guard duration > 0 else {
                markers.removeValue(forKey: key)
                continue
            }
            if !marker.retiring {
                marker.retiring = true
                marker.fade = Fade(from: marker.alpha, to: 0,
                                   startedAt: now, duration: duration)
                markers[key] = marker
            }
            order.append(key)
        }
        markerOrder = order
        activeFadeKeys = Set(markers.compactMap { key, marker in
            marker.fade == nil ? nil : key
        })
        publishCircles()
        updateClock()
    }

    private func sampleFades(at now: TimeInterval) -> (changed: Set<String>, removed: Bool) {
        if let fade = batchArrival {
            let fraction = min(1, max(0, (now - fade.startedAt) / fade.duration))
            alpha = fade.from + (fade.to - fade.from) * RailMotion.mapHighlightProgress(fraction)
            if fraction >= 1 { batchArrival = nil }
        }
        var changed: Set<String> = []
        var finished: Set<String> = []
        var removed = false
        for key in activeFadeKeys {
            guard var marker = markers[key], let fade = marker.fade else { continue }
            let fraction = min(1, max(0, (now - fade.startedAt) / fade.duration))
            marker.alpha = fade.from + (fade.to - fade.from)
                * RailMotion.mapHighlightProgress(fraction)
            changed.insert(key)
            if fraction >= 1 {
                finished.insert(key)
                if marker.retiring {
                    markers.removeValue(forKey: key)
                    removed = true
                    continue
                }
                marker.fade = nil
            }
            markers[key] = marker
        }
        activeFadeKeys.subtract(finished)
        if removed { markerOrder.removeAll { markers[$0] == nil } }
        return (changed, removed)
    }

    private func advance(at now: TimeInterval) {
        let changes = sampleFades(at: now)
        if changes.removed {
            publishCircles()
        } else if !changes.changed.isEmpty {
            updateFadingCircles(for: changes.changed)
        }
        updateClock()
    }

    private func updateClock() {
        if batchArrival != nil || !activeFadeKeys.isEmpty {
            guard displayLink == nil else { return }
            frameTarget.renderer = self
            let link = CADisplayLink(target: frameTarget, selector: #selector(FrameTarget.tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func publishCircles() {
        var updatedIndices: [String: Int] = [:]
        let updated = markerOrder.compactMap { key -> Circle? in
            guard let marker = markers[key] else { return nil }
            updatedIndices[key] = updatedIndices.count
            let station = marker.station
            return Circle(point: MKMapPoint(station.coordinate),
                          radius: max(0.5, station.drawnRadiusToken(atZoom: zoom) * scale),
                          lineWidth: station.drawnLineWidthToken(atZoom: zoom) * scale,
                          fill: station.fill.cgColor, stroke: station.stroke.cgColor,
                          alpha: marker.alpha,
                          coreRadius: station.core.map { max(0.25, $0.radius * scale) },
                          coreColor: station.core?.color.cgColor)
        }
        circleLock.lock()
        guard circles != updated else {
            circleIndexByKey = updatedIndices
            circleLock.unlock()
            return
        }
        let previous = circles
        circles = updated
        circleIndexByKey = updatedIndices
        for circle in updated {
            paintCoverage = paintCoverage.union(MKMapRect(
                x: circle.point.x, y: circle.point.y, width: 0, height: 0))
            paintRadius = max(paintRadius, circle.radius)
        }
        circleLock.unlock()
        invalidateChangedCircles(previous: previous, updated: updated)
    }

    private func updateFadingCircles(for keys: Set<String>) {
        guard zoom.isFinite else {
            publishCircles()
            return
        }
        let mapPointsPerScreenPoint = MKMapSize.world.width / (256 * pow(2, zoom))
        var updates: [(index: Int, alpha: CGFloat)] = []
        for key in keys {
            guard let marker = markers[key], let index = circleIndexByKey[key],
                  circles.indices.contains(index) else {
                publishCircles()
                return
            }
            updates.append((index, marker.alpha))
        }
        var changed: [Circle] = []
        circleLock.lock()
        for update in updates {
            guard circles[update.index].alpha != update.alpha else { continue }
            circles[update.index].alpha = update.alpha
            changed.append(circles[update.index])
        }
        circleLock.unlock()
        guard !changed.isEmpty else { return }
        if changed.count > 64 {
            var union = MKMapRect.null
            var maxRadius: CGFloat = 0
            for circle in changed {
                union = union.union(MKMapRect(
                    x: circle.point.x, y: circle.point.y, width: 0, height: 0))
                maxRadius = max(maxRadius, circle.radius)
            }
            let padding = Double(maxRadius) * mapPointsPerScreenPoint * 2
            setNeedsDisplay(union.insetBy(dx: -padding, dy: -padding))
            return
        }
        for circle in changed {
            let padding = Double(circle.radius) * mapPointsPerScreenPoint * 2
            let rect = MKMapRect(
                x: circle.point.x, y: circle.point.y, width: 0, height: 0)
            setNeedsDisplay(rect.insetBy(dx: -padding, dy: -padding))
        }
    }

    // A fade only ever moves a handful of dots, so invalidating the whole
    // country canvas on every display-link tick wastes most of the redraw.
    // Diff against the last published circles and invalidate just the map
    // rect that covers what changed, padded by the largest affected radius.
    private func invalidateChangedCircles(previous: [Circle], updated: [Circle]) {
        guard zoom.isFinite, previous.count == updated.count else {
            setNeedsDisplay()
            return
        }
        let mapPointsPerScreenPoint = MKMapSize.world.width / (256 * pow(2, zoom))
        var changed: [(old: Circle, new: Circle)] = []
        for (old, new) in zip(previous, updated) where old != new {
            changed.append((old, new))
            if changed.count > 512 {
                setNeedsDisplay()
                return
            }
        }
        guard !changed.isEmpty else { return }
        // Invalidating each dot's own padded rect keeps Core Graphics redraws
        // small when only a handful of dots are mid-fade. Once enough dots
        // change in a single tick, a union covers the same area for less
        // display-link overhead than many small invalidations.
        if changed.count > 64 {
            var union = MKMapRect.null
            var maxRadius: CGFloat = 0
            for (old, new) in changed {
                union = union.union(MKMapRect(x: old.point.x, y: old.point.y, width: 0, height: 0))
                union = union.union(MKMapRect(x: new.point.x, y: new.point.y, width: 0, height: 0))
                maxRadius = max(maxRadius, old.radius, new.radius)
            }
            let padding = Double(maxRadius) * mapPointsPerScreenPoint * 2
            setNeedsDisplay(union.insetBy(dx: -padding, dy: -padding))
            return
        }
        for (old, new) in changed {
            let radius = max(old.radius, new.radius)
            let padding = Double(radius) * mapPointsPerScreenPoint * 2
            var rect = MKMapRect(x: old.point.x, y: old.point.y, width: 0, height: 0)
                .union(MKMapRect(x: new.point.x, y: new.point.y, width: 0, height: 0))
            rect = rect.insetBy(dx: -padding, dy: -padding)
            setNeedsDisplay(rect)
        }
    }

    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        guard zoomScale > 0 else { return false }
        circleLock.lock()
        let coverage = paintCoverage
        let radius = paintRadius
        circleLock.unlock()
        guard !coverage.isNull else { return false }
        let padding = Double(radius) / zoomScale
        // A world-sized MKOverlay keeps screen-sized dots valid at every
        // zoom, but accepting every tile generates transparent textures for
        // every journey across the world. Only tiles that may contain paint
        // (including departing paint) need raster resources.
        return coverage.insetBy(dx: -padding, dy: -padding).intersects(mapRect)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard zoomScale > 0 else { return }
        circleLock.lock()
        let circles = circles
        circleLock.unlock()
        for circle in circles {
            let radius = circle.radius / zoomScale
            let extent = MKMapRect(x: circle.point.x - Double(radius),
                                   y: circle.point.y - Double(radius),
                                   width: Double(radius * 2), height: Double(radius * 2))
            guard extent.intersects(mapRect) else { continue }
            let centre = point(for: circle.point)
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                              width: radius * 2, height: radius * 2)
            context.saveGState()
            // Match annotation alpha: apply opacity to the complete circle,
            // rather than blending the fill and keyline against each other.
            context.setAlpha(circle.alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setFillColor(circle.fill)
            context.fillEllipse(in: rect)
            let width = min(radius, circle.lineWidth / zoomScale)
            if width > 0 {
                context.setStrokeColor(circle.stroke)
                context.setLineWidth(width)
                // UIView borders are inset inside the dot's bounds.
                context.strokeEllipse(in: rect.insetBy(dx: width / 2, dy: width / 2))
            }
            if let coreRadius = circle.coreRadius, let color = circle.coreColor {
                let core = min(radius, coreRadius / zoomScale)
                context.setFillColor(color)
                context.fillEllipse(in: CGRect(x: centre.x - core, y: centre.y - core,
                                               width: core * 2, height: core * 2))
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }
}
