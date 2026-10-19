import MapKit
import RailCore
import RailInspection
import SwiftUI

struct InspectorMap: UIViewRepresentable {
    let model: InspectorModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.lastFocus != model.focus, !model.focusRect.isNull {
            coordinator.lastFocus = model.focus
            map.setVisibleMapRect(model.focusRect,
                                  edgePadding: .init(top: 60, left: 50, bottom: 60, right: 50), animated: false)
        }
        if coordinator.lastZoom != model.zoomRevision, let zoom = model.zoomRequest {
            coordinator.lastZoom = model.zoomRevision
            let scale = MKMapSize.world.width / (256 * pow(2, zoom))
            let center = MKMapPoint(model.cameraCenterRequest?.native ?? map.centerCoordinate)
            let width = scale * Double(map.bounds.width), height = scale * Double(map.bounds.height)
            map.setVisibleMapRect(MKMapRect(x: center.x - width / 2, y: center.y - height / 2,
                                           width: width, height: height), animated: false)
        }
        let key = "\(model.lineID ?? "")-\(model.stationIndex)-\(model.mode)-\(model.opacity)-\(model.peek)-\(model.captureRequest?.uuidString ?? "")-\(model.analysisRequest?.uuidString ?? "")-\(model.referenceRevision)"
        if coordinator.lastKey != key {
            coordinator.lastKey = key
            coordinator.redraw(map)
        }
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        let model: InspectorModel
        var lastFocus: UUID?
        var lastKey = ""
        var rendering = false
        var publication = UUID()
        var lastCapture: UUID?
        var lastZoom: UUID?
        var lastAnalysis: UUID?
        init(_ model: InspectorModel) { self.model = model }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Extracted mode presents its own fixed snapshot. Its result
            // captions resize the hidden map; that is not a user camera move.
            if model.mode != .extracted, !model.analysisRect.isNull {
                let old = model.analysisRect, next = mapView.visibleMapRect
                let tolerance = mapScale(mapView)
                if abs(old.minX - next.minX) > tolerance || abs(old.minY - next.minY) > tolerance
                    || abs(old.width - next.width) > tolerance || abs(old.height - next.height) > tolerance {
                    model.invalidateAnalysis()
                }
            }
            redraw(mapView)
        }

        func redraw(_ map: MKMapView) {
            guard !rendering, map.bounds.width > 0 else { return }
            rendering = true
            defer { rendering = false }
            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations)
            let scale = mapScale(map)
            let zoom = log2(MKMapSize.world.width / (256 * scale))
            let mode = model.peek ? ComparisonMode.basemap : model.mode
            if mode == .decoded { add(model.decoded, kind: "decoded", map: map) }
            if mode == .display || mode == .compare { add(model.display, kind: "display", map: map) }
            let smoothed = InspectorStrokeGeometry.build(display: model.display,
                stations: (model.line?.displayStations ?? []).map(\.coordinate),
                mapPointsPerPoint: scale, zoom: zoom)
            let smoothCount = smoothed.filter { $0.count > 1 }.reduce(0) { $0 + $1.count }
            if mode == .smooth || mode == .compare { add(smoothed, kind: "smooth", map: map) }
            if mode != .basemap, let line = model.line,
               line.stations.indices.contains(model.stationIndex) {
                let station = line.stations[model.stationIndex]
                let annotation = MKPointAnnotation()
                annotation.coordinate = line.displayCoordinate(for: station).native
                annotation.title = station.name
                annotation.subtitle = "包内站点 · \(station.id)"
                map.addAnnotation(annotation)
            }
            let mpp = scale * MKMetersPerMapPointAtLatitude(map.centerCoordinate.latitude)
            if mode != .basemap { add(model.referencePaths, kind: "reference", map: map) }
            let camera = ["latitude": map.centerCoordinate.latitude,
                                  "longitude": map.centerCoordinate.longitude,
                                  "zoom256": zoom, "metresPerPoint": mpp,
                                  "heading": map.camera.heading, "pitch": map.camera.pitch,
                                  "mapPointsPerPoint": scale,
                                  "viewportWidthPoints": Double(map.bounds.width),
                                  "viewportHeightPoints": Double(map.bounds.height),
                                  "displayScale": Double(map.traitCollection.displayScale),
                                  "rectX": map.visibleMapRect.origin.x, "rectY": map.visibleMapRect.origin.y,
                                  "rectWidth": map.visibleMapRect.width, "rectHeight": map.visibleMapRect.height]
            let status = String(format: "z %.2f · %.2f m/pt · display %d parts · smooth %d vertices",
                                  zoom, mpp, model.display.count, smoothCount)
            let drift = InspectionDistances.sampledMaximum(smoothed, to: model.display, in: map.visibleMapRect)
            let referenceRect = InspectorModel.bounds(model.referencePaths.flatMap { $0 }).intersection(map.visibleMapRect)
            let referenceDistance = InspectionDistances.sampledMaximum(smoothed, to: model.referencePaths, in: referenceRect)
            let distanceNote = drift.map { String(format: " · 可视平滑→显示 %.1f m (%d点 / 步长≤%.1fm)", $0.maximumMetres, $0.sampleCount, $0.spacingUpperBoundMetres) } ?? ""
            let referenceNote = referenceDistance.map { String(format: " · 参考范围内 %.1f m (%d点)", $0.maximumMetres, $0.sampleCount) } ?? ""
            let revision = UUID(); publication = revision
            Task { @MainActor [weak self] in
                guard let self, self.publication == revision else { return }
                self.model.cameraRecord = camera
                self.model.status = self.model.mode == .extracted ? (self.model.analysisReport?.summary ?? "尚未抽离当前视点") : status + distanceNote + referenceNote
            }
            if let request = model.analysisRequest, request != lastAnalysis, let line = model.line {
                lastAnalysis = request
                model.analysisRect = map.visibleMapRect
                let options = MKMapSnapshotter.Options()
                options.mapRect = map.visibleMapRect
                let ratio = min(1, 1024 / max(map.bounds.width, map.bounds.height))
                options.size = CGSize(width: map.bounds.width * ratio, height: map.bounds.height * ratio)
                options.traitCollection = UITraitCollection(traitsFrom: [map.traitCollection, UITraitCollection(displayScale: 1)])
                if model.transitCartography {
                    // Keep the subway glyph contrast consistent in the
                    // analysis snapshot; the interactive map keeps its style.
                    options.traitCollection = UITraitCollection(traitsFrom: [
                        UITraitCollection(userInterfaceStyle: .light), UITraitCollection(displayScale: 1)])
                }
                options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
                options.pointOfInterestFilter = .excludingAll
                options.showsBuildings = false
                let stations = line.stations.map { AppleStationSeed(id: $0.id, name: $0.name, nameRoma: $0.nameRoma,
                    coordinate: line.displayCoordinate(for: $0)) }
                let selectedIndex = model.currentInput?.intervalIndex ?? max(0, model.stationIndex - 1)
                let evidenceMode: AppleMapRailEvidenceMode = model.transitCartography ? .transitCartography : .physicalRailGlyph
                model.analysisTask = Task { @MainActor in
                    defer { model.captureAdmission.finish(request) }
                    do {
                        let result = try await AppleMapAnalysisService.capture(options: options, constructed: smoothed,
                            stations: stations, lineID: line.id, intervalIndex: selectedIndex, evidenceMode: evidenceMode,
                            cartographicPalette: model.blueRailwayOnly ? .blueRailway : .blueAndCyan)
                        guard !Task.isCancelled, model.analysisGeneration == request else { return }
                        model.analysisReport = result
                        model.analysisBusy = false
                        model.analysisTask = nil
                        model.mode = .extracted
                        model.status = result.summary
                    } catch {
                        guard model.analysisGeneration == request else { return }
                        model.analysisBusy = false
                        model.analysisTask = nil
                        model.error = "Apple 底图抽离失败：\(error.localizedDescription)"
                    }
                }
            }
            if let request = model.captureRequest, request != lastCapture {
                lastCapture = request
                let display = model.display, reference = model.referencePaths
                let itemID = model.currentItem?.id
                do {
                    let record = try model.viewRecord(camera: camera)
                    var object = try JSONSerialization.jsonObject(with: record) as! [String: Any]
                    object["snapshotAppearance"] = "light"
                    object["snapshotDisplayScale"] = 1
                    if let drift { object["displayDistanceSample"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(drift)) }
                    if let referenceDistance { object["referenceDistanceSample"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(referenceDistance)) }
                    object["distanceScope"] = "One-sided sampled nearest polyline; visible selected line parts. Reference measurement clipped to reference bounds. Not Apple pixel residual."
                    let capturedRecord = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
                    let width = RailStyle.railWidth * RailStyle.scale(atZoom: zoom)
                    let options = MKMapSnapshotter.Options()
                    options.mapRect = map.visibleMapRect
                    options.size = map.bounds.size
                    // Keep exported railway evidence readable and comparable
                    // regardless of the interactive window's appearance.
                    options.traitCollection = UITraitCollection(traitsFrom: [
                        UITraitCollection(userInterfaceStyle: .light),
                        UITraitCollection(displayScale: 1)])
                    options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
                    options.pointOfInterestFilter = .excludingAll
                    options.showsBuildings = true
                    Task { @MainActor in
                        do {
                            let bundle = try await InspectionEvidence.capture(options: options, record: capturedRecord,
                                display: display, smooth: smoothed, reference: reference, width: width, itemID: itemID)
                            model.finishCapture(request, bundle: bundle)
                        } catch { model.finishCapture(request, error: error) }
                    }
                } catch { model.finishCapture(request, error: error) }
            }
        }

        func mapScale(_ map: MKMapView) -> Double {
            // Same local 8-point chord as MapProjection, independent of Retina backing pixels.
            let center = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
            let a = MKMapPoint(map.convert(CGPoint(x: center.x - 4, y: center.y), toCoordinateFrom: map))
            let b = MKMapPoint(map.convert(CGPoint(x: center.x + 4, y: center.y), toCoordinateFrom: map))
            let scale = hypot((b.x - a.x).remainder(dividingBy: MKMapSize.world.width), b.y - a.y) / 8
            return scale.isFinite && scale > 0 ? scale : max(map.visibleMapRect.width / Double(map.bounds.width), 1e-9)
        }

        func add(_ parts: [[Coordinate]], kind: String, map: MKMapView) {
            for part in parts where part.count > 1 {
                let coordinates = part.map(\.native)
                let overlay = MKPolyline(coordinates: coordinates, count: coordinates.count)
                overlay.title = kind
                map.addOverlay(overlay, level: .aboveLabels)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            let zoom = log2(MKMapSize.world.width / (256 * mapScale(mapView)))
            renderer.lineWidth = RailStyle.railWidth * RailStyle.scale(atZoom: zoom)
            renderer.strokeColor = polyline.title == "smooth" ? .systemPink :
                polyline.title == "display" ? .systemTeal : polyline.title == "reference" ? .systemOrange : .systemBlue
            renderer.alpha = CGFloat(model.opacity)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            if polyline.title == "decoded" { renderer.lineDashPattern = [4, 3] }
            return renderer
        }
    }
}
