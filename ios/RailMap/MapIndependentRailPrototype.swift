import MapKit
import RailCore
import RailPresentation
import UIKit

#if DEBUG
/// Opt-in camera/composition experiment. It is deliberately not a production
/// backend: native annotations provide an independent displayed-position probe,
/// while a fixed route, own beads/labels and a moving head paint above the veil.
/// No private MapKit views or extra MKMapView participate in the experiment.
@MainActor
final class MapIndependentRailPrototype: UIView {
    nonisolated final class Reference: MKPointAnnotation {
        let id: Int
        init(id: Int, coordinate: CLLocationCoordinate2D) {
            self.id = id
            super.init()
            self.coordinate = coordinate
        }
    }

    /// Opt-in control for the native reference's path preparation. The default
    /// reference remains MKMultiPolylineRenderer with its own path preparation.
    nonisolated final class ExactPathReferenceRenderer: MKOverlayPathRenderer {
        override func createPath() {
            guard let lines = overlay as? MKMultiPolyline else { return }
            let exact = CGMutablePath()
            for line in lines.polylines where line.pointCount > 0 {
                let points = line.points()
                exact.move(to: point(for: points[0]))
                for index in 1..<line.pointCount {
                    exact.addLine(to: point(for: points[index]))
                }
            }
            path = exact
        }
    }

    @MainActor private final class ClockTarget: NSObject {
        weak var owner: MapIndependentRailPrototype?
        @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
    }

    @MainActor private final class Trial {
        var motionErrors: [Double] = []
        var settledErrors: [Double] = []
        var phaseErrors: [Int: [Double]] = [:]
        var nativeModelErrors: [Double] = []
        var fitResidualErrors: [Double] = []
        var fittedFrames = 0
        var motionFitSamples = 0
        var pairedCosts: [Double] = []
        var missingReferenceSamples = 0
        var offscreenReferenceSamples = 0
        var drawnFrames = 0
        var frames = 0
        var errors: [Double] = []
        var projectionCosts: [Double] = []
        var paintCosts: [Double] = []
        var maxFrameGap = 0.0
        var referenceFrames = 0
    }
    private static let trial = Trial()

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_PROTOTYPE"] == "1"
    }

    static var usesExactReferencePath: Bool {
        ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_EXACT_REFERENCE_PATH"] == "1"
    }

    private static var rasterStyle: String {
        ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_RASTER_STYLE"] ?? "default"
    }

    static var referenceStrokeWidth: CGFloat {
        switch rasterStyle {
        case "narrow": 1
        case "matched": 5
        default: 9
        }
    }

    private var ownStrokeAlpha: CGFloat {
        Self.rasterStyle == "narrow" || Self.rasterStyle == "matched" ? 0.45 : 1
    }

    private weak var mapView: MKMapView?
    private let veil = UIView()
    private let status = UILabel()
    private let target = ClockTarget()
    private var link: CADisplayLink?
    private var references: [Reference] = []
    private var calibrationReferences: [Reference] = []
    private var nativeBaseline: MKMultiPolyline?
    static let nativeBaselineTitle = "independent-rail-native-baseline"
    private var mapPoints: [MKMapPoint] = []
    private var planeCenterX = 0.0
    private var projectionMisses = 0
    private let usesNativeProjection = ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_PROJECTION"] == "native"
    private let correctedNativeAnchors = ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_CORRECTED_ANCHORS"] == "1"
    private let anchorDiagnostics = ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_ANCHOR_DIAGNOSTICS"] == "1"
    private var anchorDiagnosticRows: [String] = []
    private var frameQMinusModel: [Double] = []
    private var framePresentationMinusQ: [Double] = []
    private var frameCorrectedHoldoutErrors: [Double] = []
    private var referenceAnchors: [UIView] = []
    private var previousReferencePoints: [Int: CGPoint] = [:]
    private var coordinates: [CLLocationCoordinate2D] = []
    private var scene = MapProjectedRailScene()
    private var sceneProjectionCost = 0.0
    private var sceneFrameID = 0
    private var drawnFrameID = 0
    private var labels: [(point: CGPoint, text: String)] = []
    private var projectedRoute: [RideTapResolver.Point] = []
    private var previousTick: CFTimeInterval?
    private var beganAt: CFTimeInterval?
    private var phase = -1
    private var wrapBreaks = 0
    private var selectedReference = -1
    private let tracing = ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_TRACE"] == "1"
    private let traceDelay = Double(ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_TRACE_DELAY"] ?? "0") ?? 0
    private let phaseDuration = max(2, Double(ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_PHASE_DURATION"] ?? "2") ?? 2)
    private let rasterReference = ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_RASTER_REFERENCE"] == "1"
    private let synchronousPaint = ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_SYNCHRONOUS_PAINT"] == "1"
    private let visibleRegionPaint = ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_VISIBLE_REGION_PAINT"] == "1"
    private var visibleRegionPaints = 0
    private let vertexCount: Int
    private var referencePathDiagnostics: String?

    init(on mapView: MKMapView) {
        self.mapView = mapView
        vertexCount = max(
            65,
            min(
                100_000,
                Int(ProcessInfo.processInfo.environment["RAILMAP_INDEPENDENT_RAIL_VERTICES"] ?? "5000") ?? 5000))
        super.init(frame: mapView.bounds)
        isOpaque = false
        isUserInteractionEnabled = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        veil.frame = mapView.bounds
        veil.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        veil.backgroundColor = .black.withAlphaComponent(0.1)
        veil.isUserInteractionEnabled = false
        mapView.addSubview(veil)
        mapView.addSubview(self)
        status.frame = CGRect(x: 1, y: 1, width: 1, height: 1)
        status.textColor = .clear
        status.isAccessibilityElement = true
        status.accessibilityIdentifier = "railIndependentPrototypeStatus"
        addSubview(status)
        installScene(center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.77))
        target.owner = self
        let link = CADisplayLink(target: target, selector: #selector(ClockTarget.tick(_:)))
        link.preferredFrameRateRange = .init(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let transparentReferenceImage: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 6, height: 6), format: format).image { _ in }
    }()

    static func referenceView(_ annotation: Reference, on mapView: MKMapView) -> MKAnnotationView {
        let identifier = "independent-rail-native-reference"
        let view =
            mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        view.annotation = annotation
        view.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
        view.backgroundColor = annotation.id >= 100 ? .clear : .green
        view.image = annotation.id >= 100 ? transparentReferenceImage : nil
        view.alpha = 1
        view.isHidden = false
        view.isUserInteractionEnabled = false
        view.layer.cornerRadius = 3
        view.displayPriority = .required
        view.collisionMode = .circle
        view.centerOffset = .zero
        view.isAccessibilityElement = false
        return view
    }

    func tearDown() {
        link?.invalidate()
        link = nil
        if let mapView {
            mapView.removeAnnotations(references + calibrationReferences)
            if let nativeBaseline { mapView.removeOverlay(nativeBaseline) }
        }
        nativeBaseline = nil
        referencePathDiagnostics = nil
        references = []
        calibrationReferences = []
        referenceAnchors.forEach { $0.removeFromSuperview() }
        referenceAnchors = []
        veil.removeFromSuperview()
        removeFromSuperview()
    }

    func selectReference(_ id: Int) {
        selectedReference = id
        publish()
    }

    func select(at point: CGPoint) {
        guard let mapView else { return }
        if let reference = references.min(by: {
            let a = mapView.convert($0.coordinate, toPointTo: mapView)
            let b = mapView.convert($1.coordinate, toPointTo: mapView)
            return hypot(a.x - point.x, a.y - point.y) < hypot(b.x - point.x, b.y - point.y)
        }) {
            let center = mapView.convert(reference.coordinate, toPointTo: mapView)
            if hypot(center.x - point.x, center.y - point.y) <= 22 {
                selectReference(reference.id)
                return
            }
        }
        let hits = RideTapResolver.hits(
            at: .init(x: point.x, y: point.y),
            among: [.init(id: "prototype", strokes: [projectedRoute])])
        selectedReference = hits.isEmpty ? -1 : 99
        publish()
    }

    private func installScene(center: CLLocationCoordinate2D) {
        guard let mapView else { return }
        mapView.removeAnnotations(references + calibrationReferences)
        if let nativeBaseline { mapView.removeOverlay(nativeBaseline) }
        nativeBaseline = nil
        referencePathDiagnostics = nil
        referenceAnchors.forEach { $0.removeFromSuperview() }
        previousReferencePoints = [:]
        referenceAnchors = (0..<5).map { _ in
            let anchor = UIView(frame: CGRect(x: 0, y: 0, width: 6, height: 6))
            anchor.isUserInteractionEnabled = false
            addSubview(anchor)
            return anchor
        }
        coordinates = (0..<vertexCount).map { index in
            let t = Double(index) / Double(vertexCount - 1)
            let wgs84 = Coordinate(
                lon: center.longitude + (t - 0.5) * 0.045,
                lat: center.latitude + sin(t * .pi * 2) * 0.012)
            let displayed = AppleMapDatum.display(wgs84, country: "jp")
            return CLLocationCoordinate2D(
                latitude: displayed.lat,
                longitude: ((displayed.lon + 180).truncatingRemainder(dividingBy: 360) + 360)
                    .truncatingRemainder(dividingBy: 360) - 180)
        }
        references = (0..<5).map { id in
            Reference(id: id, coordinate: coordinates[id * (vertexCount - 1) / 4])
        }
        if rasterReference {
            // The native raster receives the same fixed fixture coordinates.
            // Splitting at the seam prevents a world-spanning debug chord.
            var chunks: [[CLLocationCoordinate2D]] = [[]]
            for coordinate in coordinates {
                if let previous = chunks.last?.last,
                    abs(previous.longitude - coordinate.longitude) > 180 { chunks.append([]) }
                chunks[chunks.count - 1].append(coordinate)
            }
            let lines = chunks.filter { $0.count >= 2 }.map { MKPolyline(coordinates: $0, count: $0.count) }
            let baseline = MKMultiPolyline(lines)
            baseline.title = Self.nativeBaselineTitle
            nativeBaseline = baseline
            mapView.addOverlay(baseline, level: .aboveLabels)
        }
        planeCenterX = MKMapPoint(center).x
        mapPoints = coordinates.map { MKMapPoint($0) }
        let gridOffsets: [Double] = [-1, 0, 1]
        let calibrationGrid = gridOffsets.flatMap { y -> [(Double, Double)] in
            gridOffsets.map { x in (x, y) }
        }
        calibrationReferences = calibrationGrid.enumerated().map { index, location in
            let longitude = center.longitude + location.0 * 0.009
            return Reference(id: index + 100, coordinate: CLLocationCoordinate2D(
                latitude: center.latitude + location.1 * 0.007,
                longitude: ((longitude + 180).truncatingRemainder(dividingBy: 360) + 360)
                    .truncatingRemainder(dividingBy: 360) - 180))
        }
        for reference in references {
            referenceAnchors[reference.id].center = mapView.convert(reference.coordinate, toPointTo: self)
        }
        mapView.addAnnotations(references + calibrationReferences)
    }

    private func tick(_ displayLink: CADisplayLink) {
        guard let mapView, window != nil, bounds.width > 1 else { return }
        if let previousTick { Self.trial.maxFrameGap = max(Self.trial.maxFrameGap, (displayLink.timestamp - previousTick) * 1000) }
        previousTick = displayLink.timestamp
        if beganAt == nil { beganAt = displayLink.timestamp }
        let elapsed = displayLink.timestamp - (beganAt ?? displayLink.timestamp)
        if tracing, elapsed >= traceDelay { advanceTrace(elapsed: elapsed - traceDelay, on: mapView) }
        updateScene(on: mapView, elapsed: elapsed)
    }

    /// Opt-in timing control. The display link still advances the playback
    /// fixture; a public camera callback can replace its scene before commit.
    func visibleRegionChanged(on mapView: MKMapView) {
        guard visibleRegionPaint, window != nil, bounds.width > 1 else { return }
        visibleRegionPaints += 1
        updateScene(on: mapView, elapsed: CACurrentMediaTime() - (beganAt ?? CACurrentMediaTime()))
    }

    private func updateScene(on mapView: MKMapView, elapsed: CFTimeInterval) {
        if let nativeBaseline, !mapView.overlays.contains(where: { ($0 as AnyObject) === nativeBaseline }) {
            mapView.addOverlay(nativeBaseline, level: .aboveLabels)
        }
        mapView.bringSubviewToFront(veil)
        mapView.bringSubviewToFront(self)
        if synchronousPaint {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }
        let started = CACurrentMediaTime()
        frameQMinusModel = []
        framePresentationMinusQ = []
        frameCorrectedHoldoutErrors = []
        let fitted = usesNativeProjection ? displayedProjection(on: mapView) : nil
        if usesNativeProjection && fitted == nil { projectionMisses += 1 }
        if fitted != nil { Self.trial.fittedFrames += 1 }
        let points = zip(coordinates, mapPoints).map { coordinate, mapPoint in
            fitted?.project(localPlanePoint(mapPoint)) ?? mapView.convert(coordinate, toPointTo: self)
        }
        let path = CGMutablePath()
        var last: CGPoint?
        var discontinuities = 0
        for point in points {
            guard point.x.isFinite, point.y.isFinite else {
                last = nil
                continue
            }
            if let last, hypot(point.x - last.x, point.y - last.y) < max(bounds.width, bounds.height) * 2 {
                path.addLine(to: point)
            } else {
                if let last, bounds.insetBy(dx: -30, dy: -30).contains(last)
                    || bounds.insetBy(dx: -30, dy: -30).contains(point) {
                    discontinuities += 1
                }
                path.move(to: point)
            }
            last = point
        }
        wrapBreaks += discontinuities
        projectedRoute = points.map { .init(x: $0.x, y: $0.y) }
        let red = UIColor.red.cgColor
        let white = CGColor(gray: 1, alpha: 1)
        var next = MapProjectedRailScene(strokes: [.init(path: path, color: red, width: 5, alpha: ownStrokeAlpha)])
        labels = []
        var inspectedReference = false
        for reference in references {
            let modelPoint = mapView.convert(reference.coordinate, toPointTo: self)
            let point = fitted?.project(localPlanePoint(MKMapPoint(reference.coordinate))) ?? modelPoint
            let anchor = referenceAnchors[reference.id]
            anchor.center = point
            next.beads.append(
                .init(
                    center: point, radius: 7, fill: red, rim: white, rimWidth: 2, alpha: 1,
                    diamond: reference.id == 4))
            labels.append((point, "Station \(reference.id + 1)"))
            guard let native = mapView.view(for: reference), native.window != nil,
                let presentation = native.layer.presentation(),
                let mapPresentation = layer.presentation(),
                let railPresentation = anchor.layer.presentation()
            else { Self.trial.missingReferenceSamples += 1; continue }
            // The app-owned anchor and painted bead receive the same point in
            // the same transaction. Compare displayed presentation positions,
            // not a future model-camera point against the current native frame.
            let referencePoint = presentation.convert(
                CGPoint(x: native.bounds.midX, y: native.bounds.midY), to: mapPresentation)
            guard bounds.insetBy(dx: -30, dy: -30).contains(referencePoint) else {
                Self.trial.offscreenReferenceSamples += 1
                continue
            }
            let railPoint = railPresentation.convert(
                CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: mapPresentation)
            let error = Double(hypot(referencePoint.x - railPoint.x, referencePoint.y - railPoint.y))
                * Double(traitCollection.displayScale)
            Self.trial.errors.append(error)
            if fitted != nil {
                Self.trial.fitResidualErrors.append(Double(hypot(referencePoint.x - point.x, referencePoint.y - point.y))
                    * Double(traitCollection.displayScale))
                if anchorDiagnostics,
                    let corrected = correctedAnchorPoint(reference, native: native, presentation: presentation,
                        displayedSurface: mapPresentation, on: mapView) {
                    frameCorrectedHoldoutErrors.append(Double(hypot(corrected.x - point.x, corrected.y - point.y))
                        * Double(traitCollection.displayScale))
                }
            }
            Self.trial.phaseErrors[phase, default: []].append(error)
            Self.trial.nativeModelErrors.append(Double(hypot(referencePoint.x - modelPoint.x, referencePoint.y - modelPoint.y))
                * Double(traitCollection.displayScale))
            if let previous = previousReferencePoints[reference.id],
                hypot(referencePoint.x - previous.x, referencePoint.y - previous.y) > 0.25 {
                Self.trial.motionErrors.append(error)
                if fitted != nil { Self.trial.motionFitSamples += 1 }
            } else {
                Self.trial.settledErrors.append(error)
            }
            previousReferencePoints[reference.id] = referencePoint
            inspectedReference = true
        }
        if inspectedReference { Self.trial.referenceFrames += 1 }
        let headIndex = Int((sin(elapsed * 0.8) + 1) / 2 * Double(points.count - 1))
        next.beads.append(
            .init(
                center: points[headIndex], radius: 10,
                fill: CGColor(red: 0.1, green: 0.55, blue: 1, alpha: 1), rim: white, rimWidth: 2, alpha: 1))
        scene = next
        sceneProjectionCost = (CACurrentMediaTime() - started) * 1000
        Self.trial.projectionCosts.append(sceneProjectionCost)
        sceneFrameID = Self.trial.frames
        if anchorDiagnostics {
            func p95(_ values: [Double]) -> Double {
                let sorted = values.sorted()
                return sorted.isEmpty ? -1 : sorted[Int(Double(sorted.count - 1) * 0.95)]
            }
            anchorDiagnosticRows.append(String(
                format: "%.6f,%.6f,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%d,%.4f,%.4f",
                started, elapsed, sceneFrameID, phase, fitted == nil ? 0 : 1, frameQMinusModel.count,
                p95(frameQMinusModel), frameQMinusModel.max() ?? -1,
                p95(framePresentationMinusQ), framePresentationMinusQ.max() ?? -1,
                frameCorrectedHoldoutErrors.count, p95(frameCorrectedHoldoutErrors),
                frameCorrectedHoldoutErrors.max() ?? -1))
        }
        Self.trial.frames += 1
        setNeedsDisplay()
        if synchronousPaint {
            layer.displayIfNeeded()
            CATransaction.commit()
        }
        if Self.trial.frames.isMultiple(of: 15) { publish() }
    }

    private func localPlanePoint(_ point: MKMapPoint) -> CGPoint {
        let world = MKMapSize.world.width
        var x = point.x - planeCenterX
        if x > world / 2 { x -= world }
        if x < -world / 2 { x += world }
        return CGPoint(x: x, y: point.y)
    }

    private func displayedProjection(on mapView: MKMapView) -> MapRailHomography? {
        guard let displayedSurface = layer.presentation() else { return nil }
        let samples = calibrationReferences.compactMap { reference -> MapRailHomography.Sample? in
            guard let native = mapView.view(for: reference), native.window != nil,
                !native.isHidden, native.alpha == 1,
                let presentation = native.layer.presentation(), presentation.opacity > 0.99 else { return nil }
            let raw = presentation.convert(
                CGPoint(x: native.bounds.midX, y: native.bounds.midY), to: displayedSurface)
            let corrected = correctedNativeAnchors || anchorDiagnostics
                ? correctedAnchorPoint(reference, native: native, presentation: presentation,
                    displayedSurface: displayedSurface, on: mapView) : nil
            guard !correctedNativeAnchors || corrected != nil else { return nil }
            let point = correctedNativeAnchors ? corrected! : raw
            guard point.x.isFinite, point.y.isFinite else { return nil }
            return .init(source: localPlanePoint(MKMapPoint(reference.coordinate)), displayed: point)
        }
        // Coordinates stay fixed for this scene epoch. Mounted offscreen
        // references may contribute; required priority does not guarantee
        // their lifetime. Independent green holdouts never select the fit.
        guard samples.count >= 4 else { return nil }
        return MapRailHomography.fit(samples)
    }

    /// Opt-in spatial correction A_P(A_M^-1(q)). Public conversion can observe
    /// a different camera epoch from annotation presentation; the raster probe
    /// must establish whether this correction actually follows the native rail.
    private func correctedAnchorPoint(
        _ reference: Reference, native: MKAnnotationView, presentation: CALayer,
        displayedSurface: CALayer, on mapView: MKMapView
    ) -> CGPoint? {
        let q = mapView.convert(reference.coordinate, toPointTo: self)
        let center = CGPoint(x: native.bounds.midX, y: native.bounds.midY)
        let model = native.layer.convert(center, to: layer)
        let raw = presentation.convert(center, to: displayedSurface)
        let local = native.layer.convert(q, from: layer)
        let corrected = presentation.convert(local, to: displayedSurface)
        guard q.x.isFinite, q.y.isFinite, model.x.isFinite, model.y.isFinite,
            raw.x.isFinite, raw.y.isFinite, corrected.x.isFinite, corrected.y.isFinite else { return nil }
        if anchorDiagnostics {
            let scale = Double(traitCollection.displayScale)
            frameQMinusModel.append(Double(hypot(q.x - model.x, q.y - model.y)) * scale)
            framePresentationMinusQ.append(Double(hypot(raw.x - q.x, raw.y - q.y)) * scale)
        }
        return corrected
    }

    private func advanceTrace(elapsed: Double, on mapView: MKMapView) {
        let next = min(6, Int(elapsed / phaseDuration))
        guard next != phase else { return }
        phase = next
        let camera = MKMapCamera()
        camera.centerCoordinate = CLLocationCoordinate2D(latitude: 35.68, longitude: 139.77)
        camera.centerCoordinateDistance = 7000
        switch next {
        case 0: break
        case 1:
            camera.heading = 70
            camera.centerCoordinateDistance = 4500
        case 2:
            camera.pitch = 45
            camera.heading = 140
            camera.centerCoordinate.latitude += 0.006
        case 3:
            camera.pitch = 20
            camera.heading = 230
            camera.centerCoordinateDistance = 11_000
        case 4:
            camera.centerCoordinate = CLLocationCoordinate2D(latitude: 35.68, longitude: 179.995)
            installScene(center: camera.centerCoordinate)
        case 5:
            camera.centerCoordinate = CLLocationCoordinate2D(latitude: 35.68, longitude: -179.995)
            camera.heading = 60
            camera.pitch = 35
        default:
            publish()
            return
        }
        mapView.setCamera(camera, animated: next != 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insets = window?.safeAreaInsets ?? .zero
        status.frame.origin = CGPoint(
            x: max(safeAreaInsets.left, insets.left) + 12,
            y: max(safeAreaInsets.top, insets.top) + 12)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let started = CACurrentMediaTime()
        scene.draw(in: context)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black,
            .strokeColor: UIColor.white, .strokeWidth: -3,
        ]
        for label in labels {
            (label.text as NSString).draw(
                at: CGPoint(x: label.point.x + 10, y: label.point.y - 16),
                withAttributes: attributes)
        }
        if rasterReference {
            // This code is actually rasterized with the rail. Reading it from
            // a screenshot identifies the displayed scene; requestDisplay or
            // the accessibility label alone cannot establish a committed frame.
            let x = safeAreaInsets.left + 16, y = safeAreaInsets.top + 28
            context.setFillColor(UIColor.magenta.cgColor)
            context.fill(CGRect(x: x - 5, y: y, width: 4, height: 4))
            for bit in 0..<16 {
                context.setFillColor(((sceneFrameID >> bit) & 1) == 1 ? UIColor.white.cgColor : UIColor.black.cgColor)
                context.fill(CGRect(x: x + CGFloat(bit) * 4, y: y, width: 4, height: 4))
            }
        }
        let paintCost = (CACurrentMediaTime() - started) * 1000
        Self.trial.paintCosts.append(paintCost)
        Self.trial.pairedCosts.append(sceneProjectionCost + paintCost)
        Self.trial.drawnFrames += 1
        drawnFrameID = sceneFrameID
    }

    private func publish() {
        func percentile(_ values: [Double], _ p: Double) -> Double {
            guard !values.isEmpty else { return -1 }
            let sorted = values.sorted()
            return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
        }
        status.text =
            "frames:\(Self.trial.frames);referenceFrames:\(Self.trial.referenceFrames);samples:\(Self.trial.errors.count);phase:\(phase)"
            + ";sceneFrameID:\(sceneFrameID);drawnFrameID:\(drawnFrameID);drawnFrames:\(Self.trial.drawnFrames);missingRefs:\(Self.trial.missingReferenceSamples);offscreenRefs:\(Self.trial.offscreenReferenceSamples);fittedFrames:\(Self.trial.fittedFrames);motionFitSamples:\(Self.trial.motionFitSamples);projection:\(usesNativeProjection ? "native" : "convert");projectionMisses:\(projectionMisses);motionSamples:\(Self.trial.motionErrors.count);vertices:\(coordinates.count);wrapBreaks:\(wrapBreaks);selectedReference:\(selectedReference)"
            + String(
                format: ";errorP50Px:%.3f;errorP95Px:%.3f;errorMaxPx:%.3f",
                percentile(Self.trial.errors, 0.5), percentile(Self.trial.errors, 0.95), Self.trial.errors.max() ?? -1)
            + String(format: ";motionErrorP95Px:%.3f;settledErrorP95Px:%.3f;nativeModelP95Px:%.3f",
                percentile(Self.trial.motionErrors, 0.95), percentile(Self.trial.settledErrors, 0.95), percentile(Self.trial.nativeModelErrors, 0.95))
            + String(format: ";holdoutFitP95Px:%.3f;pairedP95Ms:%.3f",
                percentile(Self.trial.fitResidualErrors, 0.95), percentile(Self.trial.pairedCosts, 0.95))
            + (0...6).map { String(format: ";phase%dP95Px:%.3f", $0, percentile(Self.trial.phaseErrors[$0] ?? [], 0.95)) }.joined()
            + String(
                format: ";projectionP95Ms:%.3f;paintP95Ms:%.3f;maxFrameGapMs:%.3f",
                percentile(Self.trial.projectionCosts, 0.95), percentile(Self.trial.paintCosts, 0.95), Self.trial.maxFrameGap)
            + String(
                format: ";viewportWidth:%.1f;viewportHeight:%.1f;veilAlpha:%.3f",
                bounds.width, bounds.height, veil.backgroundColor?.cgColor.alpha ?? -1)
        if rasterReference, Self.usesExactReferencePath || Self.rasterStyle != "default" {
            inspectReferencePathIfNeeded()
            status.text = (status.text ?? "")
                + ";referencePath:\(Self.usesExactReferencePath ? "exact" : "default");rasterStyle:\(Self.rasterStyle)"
                + ";paintCommit:\(synchronousPaint ? "synchronous" : "deferred")"
                + ";visibleRegionPaints:\(visibleRegionPaints)"
                + String(format: ";projectionP50Ms:%.3f;paintP50Ms:%.3f;pairedP50Ms:%.3f",
                    percentile(Self.trial.projectionCosts, 0.5), percentile(Self.trial.paintCosts, 0.5),
                    percentile(Self.trial.pairedCosts, 0.5))
                + (referencePathDiagnostics ?? ";referencePathVertices:-1;sourcePathDeviationMapPoints:-1")
        }
        if let camera = mapView?.camera {
            status.text = (status.text ?? "") + String(
                format: ";cameraLat:%.7f;cameraLon:%.7f;cameraDistance:%.2f;cameraHeading:%.3f;cameraPitch:%.3f",
                camera.centerCoordinate.latitude, camera.centerCoordinate.longitude,
                camera.centerCoordinateDistance, camera.heading, camera.pitch)
        }
        if anchorDiagnostics {
            status.text = (status.text ?? "") + ";anchorCorrection:\(correctedNativeAnchors ? "corrected" : "raw")"
            let header = "timestamp,elapsed,scene,phase,fitted,anchors,qMinusModelP95Px,qMinusModelMaxPx,pMinusQP95Px,pMinusQMaxPx,holdouts,correctedHoldoutP95Px,correctedHoldoutMaxPx\n"
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("independent-rail-anchor-diagnostics.csv")
            // Only the opt-in raster experiment exports diagnostics, after the
            // tested heading/pitch transitions. Frozen defaults do no file IO.
            if rasterReference, phase == 3 {
                do { try (header + anchorDiagnosticRows.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8) }
                catch { status.text = (status.text ?? "") + ";anchorDiagnosticsWriteFailed:1" }
            }
        }
    }

    /// Public path introspection is diagnostic only. It compares corresponding
    /// path endpoints when counts match; a changed count is reported explicitly
    /// rather than treated as zero source deviation or a screen-error pass.
    private func inspectReferencePathIfNeeded() {
        guard referencePathDiagnostics == nil, let mapView, let nativeBaseline,
            let renderer = mapView.renderer(for: nativeBaseline) as? MKOverlayPathRenderer,
            let path = renderer.path else { return }
        var endpoints: [CGPoint] = []
        var curves = 0
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                endpoints.append(element.pointee.points[0])
            case .addQuadCurveToPoint:
                curves += 1
                endpoints.append(element.pointee.points[1])
            case .addCurveToPoint:
                curves += 1
                endpoints.append(element.pointee.points[2])
            case .closeSubpath: break
            @unknown default: break
            }
        }
        let source = nativeBaseline.polylines.flatMap { line in
            Array(UnsafeBufferPointer(start: line.points(), count: line.pointCount))
        }
        var deviation = -1.0
        if source.count == endpoints.count, curves == 0 {
            deviation = zip(source, endpoints).map { original, endpoint in
                let recovered = renderer.mapPoint(for: endpoint)
                return hypot(original.x - recovered.x, original.y - recovered.y)
            }.max() ?? 0
        }
        referencePathDiagnostics = ";referencePathVertices:\(endpoints.count);referencePathCurves:\(curves);referenceSourceVertices:\(source.count)"
            + String(format: ";sourcePathDeviationMapPoints:%.9f", deviation)
    }
}
#endif
