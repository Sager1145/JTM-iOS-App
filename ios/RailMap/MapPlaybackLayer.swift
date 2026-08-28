import MapKit
import RailCore
import UIKit

/// The chase, on the map: the trail a playing journey leaves, the beads of the
/// stations it has passed, the head that moves between them, and the camera
/// that follows it.
///
/// ## Why this is not part of the map coordinator
///
/// It was, and the shape of the cost was legible in the field list: eleven of
/// the coordinator's stored properties existed only while something was
/// playing, and every one of them was named `playbackSomething` because there
/// was nothing else to scope them by. Reading the coordinator meant carrying
/// the whole of the chase's state through the network rebuild, the label
/// layout, the tap resolution and the styling, none of which touch it.
///
/// The boundary is narrow, which is what made it worth drawing:
///
///   * ``MapOverlayStyles`` — shared with the coordinator, because a stroke is
///     a stroke whether the network drew it or a chase did, and one registry is
///     what lets `rendererFor` answer for both.
///   * ``RailMapController`` — for the padding the resident sheet imposes, so
///     the train is centred in the part of the map the reader can see.
///   * ``PlaybackController`` — one property, written back so the transport
///     knows how large a frame it is being drawn into.
///
/// Everything else it needs arrives as an argument. It never rebuilds the
/// network and never asks anything to; the coordinator keeps that decision,
/// because *whether a rebuild may run* is about the rebuild, not about the
/// trail — see ``render(_:on:)``'s return value.
@MainActor
final class MapPlaybackLayer {

    private let overlayStyles: MapOverlayStyles

    /// The framing insets and the camera moves that bracket a run.
    weak var controller: RailMapController?

    /// Written back to, never read: the transport sizes its own export frames
    /// from the view it is actually being drawn into.
    weak var playback: PlaybackController?

    init(overlayStyles: MapOverlayStyles) {
        self.overlayStyles = overlayStyles
    }

    /// The frame currently on the map, and `nil` when nothing is playing.
    ///
    /// The coordinator reads this to decide whether a rebuild may run: a
    /// national LOD rebuild in the middle of a chase interrupts a camera that
    /// is moving every display-link frame, so it waits for the trail to come
    /// down. It is also what ``repaint(on:)`` re-mounts from after a rebuild
    /// has taken every overlay off the map.
    private(set) var lastSnapshot: PlaybackMapSnapshot?

    private var doneOverlays: [MKOverlay] = []
    private var trailOverlays: [MKOverlay] = []
    private var partialOverlay: MKOverlay?
    private var stationAnnotations: [PlaybackAnnotation] = []
    private var headAnnotation: PlaybackAnnotation?
    private var trainID: String?
    private var renderedDoneCount = 0
    private var completedStepCount = 0
    private var lastDistance = -Double.infinity
    private var steps: [TrailStep] = []

    /// Draw one frame of the chase, or tear it down when the snapshot is `nil`.
    ///
    /// Returns whether the trail came DOWN, which is the moment a rebuild that
    /// was waiting on the chase may finally run. The layer does not run it: the
    /// caller owns the rebuild and its own deferral flag, and handing that
    /// decision across the boundary is what keeps this type free of it.
    @discardableResult
    func render(_ snapshot: PlaybackMapSnapshot?, on mapView: MKMapView) -> Bool {
        lastSnapshot = snapshot
        guard let snapshot else {
            clear(on: mapView)
            return true
        }
        paint(snapshot, on: mapView, applyCamera: snapshot.autoFocus)
        return false
    }

    /// Re-mount the current frame after a rebuild removed every overlay.
    ///
    /// Without the camera: the rebuild happened because the map moved, and
    /// moving it again from a frame the clock has already passed would fight
    /// the reader for it.
    func repaint(on mapView: MKMapView) {
        guard let lastSnapshot else { return }
        paint(lastSnapshot, on: mapView, applyCamera: false)
    }

    /// Take the whole trail off the map and forget every object in it.
    ///
    /// Two callers: ``render(_:on:)`` when the run ends, and the coordinator's
    /// network rebuild, which is about to remove every overlay MapKit holds and
    /// must not leave this layer believing its own are still mounted.
    ///
    /// ``lastSnapshot`` survives, deliberately — that is what lets
    /// ``repaint(on:)`` put a chase back after a rebuild rather than dropping
    /// the trail every time the map crosses an LOD threshold.
    func clear(on mapView: MKMapView) {
        let overlays = doneOverlays + trailOverlays + [partialOverlay].compactMap { $0 }
        if !overlays.isEmpty { mapView.removeOverlays(overlays) }
        overlayStyles.forget(overlays)
        let annotations: [MKAnnotation] = stationAnnotations
            + [headAnnotation].compactMap { $0 }
        if !annotations.isEmpty { mapView.removeAnnotations(annotations) }
        doneOverlays = []
        renderedDoneCount = 0
        resetCurrent(on: mapView, removeMountedObjects: false)
    }

    private func paint(
        _ snapshot: PlaybackMapSnapshot, on mapView: MKMapView, applyCamera: Bool
    ) {
        let color = UIColor(railHex: snapshot.path.color) ?? .systemBlue
        syncDone(snapshot.done, fallbackColor: color, on: mapView)

        // A new train (or a backwards seek/restart) is the only time the
        // current trail and its station objects are replaced. Ordinary
        // display-link frames retain every completed segment and mutate the
        // handful of objects that actually moved.
        if trainID != snapshot.path.trainID || snapshot.frame.distance < lastDistance {
            resetCurrent(on: mapView)
            prepareCurrent(snapshot, color: color, on: mapView)
        }
        appendCompletedSteps(through: snapshot.frame.distance, color: color, on: mapView)
        updatePartial(snapshot, color: color, on: mapView)

        // The head and the camera in ONE transaction, with implicit actions
        // off, because they are two halves of one statement: the train is
        // HERE, and the map is looking at it from THERE. The chase's whole
        // claim is that those two agree — the camera centre is the head plus
        // an offset that has already decayed to nothing — so the reader
        // should see a dot that does not move at all while the country slides
        // under it.
        //
        // They are written through different machinery and that is the risk.
        // The camera is `setVisibleMapRect`; the head is a KVO write on an
        // `MKAnnotation`, which MapKit answers by moving a `UIView` on its own
        // schedule. Split across two commits — or with one of them picking up
        // an implicit `CALayer` action from whatever transaction happens to be
        // open — the dot lands one frame behind the map it is supposed to be
        // fixed in, every frame, which reads as a dot that will not sit still.
        //
        // Insurance, and MEASURED AS SUCH — do not read it as the fix for the
        // wander described on ``applyCamera``. A run was recorded on the
        // simulator with this in and with it out, and the head's screen
        // position tracked frame by frame against a static-frame noise floor
        // of 0.00 px. With it out: 13–18 px median wander. With it in: 3–20 px
        // across four runs of the SAME binary. The spread between identical
        // builds is as large as the difference between the two, so this buys
        // nothing that can be demonstrated; it is kept because it costs a
        // begin/commit pair and closes a real hole (a frame that fires while
        // some other transaction is open), not because it was shown to help.
        //
        // The wander itself is still unexplained. See ``applyCamera``.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateAnnotations(snapshot, color: color, on: mapView)
        if applyCamera, let camera = snapshot.frame.camera {
            self.applyCamera(camera, on: mapView)
        }
        CATransaction.commit()

        lastDistance = snapshot.frame.distance
        playback?.mapRendererViewSize = mapView.bounds.size
    }

    /// One frame of the chase, on the map.
    ///
    /// ## Two things this used to get wrong
    ///
    /// **The zoom was read in the wrong units.** `CameraFrame.zoom` is a
    /// MapLibre zoom — `Playback.metersPerPixelAtZoom0` is 78271.517, the 512
    /// px tile grid, and the module says so: "a MapKit shell converting
    /// `Path.zoom` to an altitude or a span has to start from this number". The
    /// span was built with `360 × (width / 256) / 2^zoom`, which is
    /// ``MapProjection``'s 256-point convention — the one `zoomLevel(of:)` and
    /// `metresPerPixel(zoom:latitude:)` speak — with no
    /// `RailStyle.zoom(fromMapLibre:)` between them. So every frame of every
    /// chase was drawn a full level further out than the camera law asked for,
    /// and it disagreed with ``frame(coordinates:maxZoom:animated:on:)``, which
    /// converts: the ease landed on the start at one scale and the first tick
    /// of the clock yanked the map out to double it.
    /// `RailStyle.mapLibreZoomOffset`'s own note names this exact shape of bug.
    ///
    /// **The centre was the wrong centre.** `setRegion` has no padding to give,
    /// so the train was centred on the raw view — behind the resident sheet on
    /// a phone — while the moves that bracket the run went through
    /// `RailMapController.fit`, which keeps its subject clear of the panel.
    /// That is a jump of half the sheet's height at the intro/chase hand-off,
    /// and a train riding the panel's top edge for the rest of the journey.
    ///
    /// ## Why a map RECT and not a region
    ///
    /// `MKCoordinateRegion` cannot express the padding, and it cannot express
    /// the projection either: a degree of longitude is `cos φ` of a degree of
    /// latitude, and the old span ignored that, asking for a box 22 % too tall
    /// at Japan's latitude which MapKit then widened to fit. `MKMapRect` is
    /// Mercator, where the scale is the same in both directions locally, so
    /// `MKMapPointsPerMeterAtLatitude` converts a ground extent to a rect with
    /// no aspect fudge — and `setVisibleMapRect(_:edgePadding:)` is the one
    /// call that takes the same insets `fit` uses.
    ///
    /// ## What this still does NOT fix: the head wanders
    ///
    /// Measured rather than argued. A run was recorded and the head's centroid
    /// tracked per frame; on a still frame the same measurement reads 0.00 px,
    /// so what follows is real motion and not the detector.
    ///
    /// The ANCHOR is right and is stable across runs — the dot sits at
    /// (≈590, 712) device px on a 1206 × 2622 screen, which is the middle of
    /// the strip the resident sheet leaves, every time. That is this method's
    /// job and it does it. But the dot does not HOLD that point: it sits still
    /// for several frames and then jumps 20–30 px, over and over, for a median
    /// wander of 4–20 px and a p90 of 25–45 px. It is a dot 30 pt across
    /// moving by up to a third of itself, which is what a reader means by
    /// 圓點一直跳動.
    ///
    /// Two things were tried and are recorded here so they are not tried
    /// again. Wrapping the marker and the camera in one `CATransaction` with
    /// implicit actions off: no measurable change (see `paint`). Removing
    /// MapKit's fit by spanning the whole view and offsetting the rect's
    /// centre to place the train at the anchor, so `edgePadding:` is not
    /// needed: clearly WORSE — the anchor moved 70 px down, which also says
    /// `setVisibleMapRect(_:edgePadding:)` does not simply centre the rect in
    /// the padded box, and the wander rose to a 16–22 px median.
    ///
    /// The `step p50 = 0.00 px` in most sample windows is the shape of the
    /// remaining clue: the dot is not vibrating, it is HOLDING and then
    /// catching up. That is a dropped or coalesced frame, not arithmetic —
    /// and it was measured on a simulator, which software-renders, so how much
    /// of it survives on a device is the next thing to find out.
    private func applyCamera(_ camera: Playback.CameraFrame, on mapView: MKMapView) {
        let insets = controller?.playbackFramingInsets ?? .zero
        let width = Double(max(mapView.bounds.width - insets.left - insets.right, 1))
        let height = Double(max(mapView.bounds.height - insets.top - insets.bottom, 1))
        let latitude = camera.center.lat
        let metresPerPoint = MapProjection.metresPerPixel(
            zoom: RailStyle.zoom(fromMapLibre: camera.zoom), latitude: latitude)
        let mapPointsPerMetre = MKMapPointsPerMeterAtLatitude(latitude)
        let spanX = width * metresPerPoint * mapPointsPerMetre
        let spanY = height * metresPerPoint * mapPointsPerMetre
        guard spanX.isFinite, spanY.isFinite, spanX > 0, spanY > 0 else { return }
        let centre = MKMapPoint(camera.center.clLocation)
        mapView.setVisibleMapRect(
            MKMapRect(
                x: centre.x - spanX / 2, y: centre.y - spanY / 2,
                width: spanX, height: spanY),
            edgePadding: insets,
            animated: false)
    }

    /// Mount only newly finished journeys. `done` is an append-only prefix
    /// while a queue plays, so repainting it at 60 Hz is pure object churn. A
    /// shorter array means playback was restarted.
    private func syncDone(
        _ done: [PlaybackMapSnapshot.DoneTrail], fallbackColor: UIColor, on mapView: MKMapView
    ) {
        if done.count < renderedDoneCount {
            if !doneOverlays.isEmpty {
                mapView.removeOverlays(doneOverlays)
                overlayStyles.forget(doneOverlays)
            }
            doneOverlays = []
            renderedDoneCount = 0
        }
        var additions: [MKOverlay] = []
        for index in renderedDoneCount..<done.count {
            let trail = done[index]
            guard trail.coords.count >= 2 else { continue }
            let strideBy = max(1, trail.coords.count / 64)
            var sampled = Swift.stride(
                from: 0, to: trail.coords.count, by: strideBy
            ).map { trail.coords[$0] }
            if sampled.last != trail.coords.last, let last = trail.coords.last {
                sampled.append(last)
            }
            guard sampled.count >= 2 else { continue }
            let line = MKPolyline(
                coordinates: sampled.map(\.clLocation), count: sampled.count)
            let styleKey = "playback-done|\(index)"
            line.title = styleKey
            overlayStyles[styleKey] = .init(
                color: UIColor(railHex: trail.colorHex) ?? fallbackColor,
                widthToken: Self.trailWidth, alpha: 1)
            additions.append(line)
        }
        renderedDoneCount = done.count
        doneOverlays += additions
        if !additions.isEmpty { mapView.addOverlays(additions, level: .aboveLabels) }
    }

    private func prepareCurrent(
        _ snapshot: PlaybackMapSnapshot, color: UIColor, on mapView: MKMapView
    ) {
        trainID = snapshot.path.trainID
        lastDistance = -Double.infinity
        completedStepCount = 0
        steps = snapshot.path.runs.enumerated().flatMap { element -> [TrailStep] in
            let (runIndex, run) = element
            guard run.coords.count >= 2, run.cum.count == run.coords.count else { return [] }
            let strideBy = max(1, run.coords.count / 64)
            var indices = Array(Swift.stride(from: 0, to: run.coords.count, by: strideBy))
            if indices.last != run.coords.count - 1 { indices.append(run.coords.count - 1) }
            let denominator = Double(max(indices.count - 1, 1))
            return indices.indices.dropFirst().map { position in
                let from = indices[position - 1]
                let to = indices[position]
                return TrailStep(
                    runIndex: runIndex,
                    start: run.coords[from], end: run.coords[to],
                    startDistance: run.offset + run.cum[from],
                    endDistance: run.offset + run.cum[to],
                    fraction: Double(position) / denominator)
            }
        }

        stationAnnotations = snapshot.path.stations.enumerated().map {
            PlaybackAnnotation(
                coordinate: $0.element.coord.clLocation,
                // Already named: `Playback.compile` puts every station through
                // `I18N.stationName` with its own stop code as it builds the
                // path, which is where the web app bakes it too. Re-running the
                // lookup here would ask the table about a name it has already
                // answered for — and, with no code to say which region, ask
                // Japan's table about a Taiwanese station.
                title: $0.element.name,
                color: color, kind: .station, active: false, pulse: 0)
        }
        if !stationAnnotations.isEmpty {
            mapView.addAnnotations(stationAnnotations)
        }
    }

    private func appendCompletedSteps(
        through distance: Double, color: UIColor, on mapView: MKMapView
    ) {
        var additions: [MKOverlay] = []
        while completedStepCount < steps.count {
            let index = completedStepCount
            let step = steps[index]
            guard step.endDistance <= distance else { break }
            let points = [step.start.clLocation, step.end.clLocation]
            let line = MKPolyline(coordinates: points, count: points.count)
            let styleKey = "playback|\(trainID ?? "")|\(index)"
            line.title = styleKey
            overlayStyles[styleKey] = .init(
                color: color, widthToken: Self.trailWidth,
                alpha: 0.18 + 0.82 * step.fraction)
            additions.append(line)
            completedStepCount += 1
        }
        trailOverlays += additions
        if !additions.isEmpty { mapView.addOverlays(additions, level: .aboveLabels) }
    }

    /// The only overlay replaced on an ordinary frame: the short unfinished
    /// line from the last fixed sample to the moving head.
    private func updatePartial(
        _ snapshot: PlaybackMapSnapshot, color: UIColor, on mapView: MKMapView
    ) {
        let previous = partialOverlay
        partialOverlay = nil
        defer {
            // Removed AFTER the replacement is mounted, never before. The old
            // order left the map without a leading stroke for the width of one
            // overlay transaction on every frame of every run, which is a
            // stroke that flickers at 60 Hz for no reason — the two calls are
            // the same runloop turn, so ordering them this way costs nothing
            // and closes the gap.
            if let previous {
                mapView.removeOverlay(previous)
                // Only the renderer, not the style: the replacement carries the
                // same key and has already written its own entry by the time
                // this runs.
                if let key = previous.title ?? nil {
                    overlayStyles.forgetRenderer(forKey: key)
                    if partialOverlay == nil {
                        overlayStyles.forgetStyle(forKey: key)
                    }
                }
            }
        }
        guard let head = snapshot.frame.head else { return }
        let currentRun = snapshot.frame.runProgress.index
        guard let step = steps.first(where: {
            $0.runIndex == currentRun
                && $0.startDistance <= snapshot.frame.distance
                && $0.endDistance > snapshot.frame.distance
        }), step.start != head else { return }
        let points = [step.start.clLocation, head.clLocation]
        let line = MKPolyline(coordinates: points, count: points.count)
        let styleKey = "playback-partial|\(trainID ?? "")"
        line.title = styleKey
        overlayStyles[styleKey] = .init(
            color: color, widthToken: Self.trailWidth,
            alpha: 0.18 + 0.82 * step.fraction)
        partialOverlay = line
        mapView.addOverlay(line, level: .aboveLabels)
    }

    private func updateAnnotations(
        _ snapshot: PlaybackMapSnapshot, color: UIColor, on mapView: MKMapView
    ) {
        for (index, annotation) in stationAnnotations.enumerated() {
            let active = index <= snapshot.frame.stations.index
            let pulse = index == snapshot.frame.stations.index
                ? snapshot.frame.stations.pulse : 0
            guard annotation.active != active || annotation.pulse != pulse else { continue }
            annotation.active = active
            annotation.pulse = pulse
            (mapView.view(for: annotation) as? PlaybackAnnotationView)?
                .configure(annotation, scale: annotationScale(on: mapView))
        }
        if let head = snapshot.frame.head {
            if let annotation = headAnnotation {
                annotation.coordinate = head.clLocation
            } else {
                let annotation = PlaybackAnnotation(
                    coordinate: head.clLocation, title: nil, color: color,
                    kind: .head, active: true, pulse: 0)
                headAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
        } else if let annotation = headAnnotation {
            mapView.removeAnnotation(annotation)
            headAnnotation = nil
        }
    }

    private func resetCurrent(on mapView: MKMapView, removeMountedObjects: Bool = true) {
        let overlays = trailOverlays + [partialOverlay].compactMap { $0 }
        let annotations: [MKAnnotation] = stationAnnotations
            + [headAnnotation].compactMap { $0 }
        if removeMountedObjects {
            if !overlays.isEmpty { mapView.removeOverlays(overlays) }
            if !annotations.isEmpty { mapView.removeAnnotations(annotations) }
        }
        overlayStyles.forget(overlays)
        trailOverlays = []
        partialOverlay = nil
        stationAnnotations = []
        headAnnotation = nil
        trainID = nil
        completedStepCount = 0
        lastDistance = -Double.infinity
        steps = []
    }

    private func annotationScale(on mapView: MKMapView) -> CGFloat {
        guard mapView.bounds.width > 1 else { return 1 }
        return MapProjection.quantised(
            RailStyle.scale(atZoom: MapProjection.zoomLevel(of: mapView)), on: mapView)
    }

    private static var trailWidth: CGFloat {
        RailStyle.railWidth * RailStyle.riddenWidthScale
            + RailStyle.playbackTrailEdge * 2
    }

    private struct TrailStep {
        let runIndex: Int
        let start: Coordinate
        let end: Coordinate
        let startDistance: Double
        let endDistance: Double
        let fraction: Double
    }

    /// `fitTrainsBounds` while the transport owns the camera.
    ///
    /// `maxZoom` is a floor on how far in the move may go, expressed as a
    /// MapLibre zoom because that is what `Playback.Tuning` carries. Without it
    /// a single short journey opens at street level, where the overview shows
    /// nothing an overview is for.
    func frame(
        coordinates: [Coordinate], maxZoom: Double, animated: Bool, on mapView: MKMapView
    ) {
        guard var region = MapProjection.region(covering: [coordinates]) else { return }
        // The smallest span this zoom is allowed to produce, across the view's
        // own width — one MapLibre tile pixel is this app's zoom minus the
        // ported offset, and `metresPerPixel` already speaks that language.
        let metres = MapProjection.metresPerPixel(
            zoom: RailStyle.zoom(fromMapLibre: maxZoom),
            latitude: region.center.latitude) * Double(mapView.bounds.width)
        let minimumDelta = metres / 111_320
        region.span.latitudeDelta = max(region.span.latitudeDelta, minimumDelta)
        region.span.longitudeDelta = max(region.span.longitudeDelta, minimumDelta)
        controller?.fit(region, animated: animated)
    }
}
