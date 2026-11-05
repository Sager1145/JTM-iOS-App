import MapKit
import RailCore
import SwiftUI
import UIKit

/// What the add-trip map draws. Value-typed so SwiftUI only touches MapKit
/// when something the reader can see actually changed.
struct TripMapContent: Equatable {
    struct Piece: Equatable {
        var coordinates: [CLLocationCoordinate2D]
        var colorHex: String?
        var isConnector: Bool

        static func == (lhs: Piece, rhs: Piece) -> Bool {
            lhs.colorHex == rhs.colorHex && lhs.isConnector == rhs.isConnector
                && lhs.coordinates.count == rhs.coordinates.count
                && zip(lhs.coordinates, rhs.coordinates).allSatisfy {
                    $0.latitude == $1.latitude && $0.longitude == $1.longitude
                }
        }
    }

    struct Route: Equatable, Identifiable {
        var id: String
        var pieces: [Piece]
        var isSelected: Bool
    }

    enum Role: Equatable {
        case origin, via(Int), destination
    }

    struct Mark: Equatable, Identifiable {
        var id: String
        var role: Role
        var station: CatalogStation
        var coordinate: CLLocationCoordinate2D

        static func == (lhs: Mark, rhs: Mark) -> Bool {
            lhs.id == rhs.id && lhs.role == rhs.role && lhs.station == rhs.station
                && lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
        }
    }

    var routes: [Route] = []
    var marks: [Mark] = []
    /// Bumped when the camera should frame the trip again.
    var fitRevision = 0
}

/// A small MapKit surface for choosing a trip: catalog stations become
/// tappable dots once the reader zooms in, and candidate routes are drawn
/// with the chosen one on top. Not the main map engine — it owns no network
/// layers, playback or ride state.
struct TripMapView: UIViewRepresentable {
    let regionCode: String
    let stations: [CatalogStation]
    let content: TripMapContent
    let reduceMotion: Bool
    var onStation: (CatalogStation) -> Void
    var onRoute: (String) -> Void
    var onBackground: () -> Void
    var onZoomChange: (Bool) -> Void

    /// Stations are drawn only below this latitude span, where a dot is a
    /// target a finger can actually hit.
    static let stationSpanLimit: CLLocationDegrees = 0.3
    static let stationLimit = 350

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = configuration
        mapView.showsCompass = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.delegate = context.coordinator
        mapView.register(StationDotView.self,
                         forAnnotationViewWithReuseIdentifier: StationDotView.reuseID)
        mapView.register(MarkView.self, forAnnotationViewWithReuseIdentifier: MarkView.reuseID)
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        // A double-tap is MapKit's zoom. Waiting for it to fail keeps a zoom
        // near a grey line from also choosing that route.
        let doubleTap = UITapGestureRecognizer()
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = context.coordinator
        mapView.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
        mapView.addGestureRecognizer(tap)
        mapView.accessibilityIdentifier = "newTripMap"
        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.setStations(stations, regionCode: regionCode, on: mapView)
        coordinator.apply(content, on: mapView, reduceMotion: reduceMotion)
    }

    /// The editor closed: let MapKit drop its tiles, overlays and dots now
    /// rather than whenever the hosting view is finally released.
    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        coordinator.release(mapView)
    }

    // MARK: - coordinator

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TripMapView?
        weak var mapView: MKMapView?
        private var regionCode = ""
        private var stationCount = -1
        private var grid: [Cell: [Int]] = [:]
        private var displayStations: [(station: CatalogStation, coordinate: CLLocationCoordinate2D)] = []
        private var shownDots: [StationKey: StationDotAnnotation] = [:]
        private var markAnnotations: [String: MarkAnnotation] = [:]
        private var content = TripMapContent()
        private var appliedFit = -1
        private var zoomedIn: Bool?
        private var framedRegion = false

        private struct Cell: Hashable { var x: Int; var y: Int }
        private static let cellSize = 0.05

        private static func cell(_ coordinate: CLLocationCoordinate2D) -> Cell {
            Cell(x: Int((coordinate.longitude / cellSize).rounded(.down)),
                 y: Int((coordinate.latitude / cellSize).rounded(.down)))
        }

        func release(_ mapView: MKMapView) {
            mapView.delegate = nil
            mapView.gestureRecognizers?.forEach { mapView.removeGestureRecognizer($0) }
            mapView.removeAnnotations(mapView.annotations)
            mapView.removeOverlays(mapView.overlays)
            grid = [:]
            displayStations = []
            shownDots = [:]
            markAnnotations = [:]
            content = TripMapContent()
            parent = nil
            self.mapView = nil
        }

        func setStations(_ stations: [CatalogStation], regionCode: String, on mapView: MKMapView) {
            guard regionCode != self.regionCode || stations.count != stationCount else { return }
            self.regionCode = regionCode
            stationCount = stations.count
            displayStations = stations.map { station in
                let display = AppleMapDatum.display(
                    Coordinate(lon: station.longitude, lat: station.latitude), country: regionCode)
                return (station, display.clLocation)
            }
            grid = [:]
            for (index, entry) in displayStations.enumerated() {
                grid[Self.cell(entry.coordinate), default: []].append(index)
            }
            mapView.removeAnnotations(Array(shownDots.values))
            shownDots = [:]
            framedRegion = false
            frameRegionIfNeeded(on: mapView)
            refreshDots(on: mapView)
        }

        /// First camera: the region's whole network, before any trip exists.
        private func frameRegionIfNeeded(on mapView: MKMapView) {
            guard !framedRegion, content.marks.isEmpty, !displayStations.isEmpty,
                  mapView.bounds.width > 1 else { return }
            framedRegion = true
            // Trim outliers (remote islands) so the mainland fills the frame.
            let lats = displayStations.map(\.coordinate.latitude).sorted()
            let lons = displayStations.map(\.coordinate.longitude).sorted()
            func quantile(_ values: [Double], _ q: Double) -> Double {
                values[min(values.count - 1, max(0, Int(Double(values.count - 1) * q)))]
            }
            let south = quantile(lats, 0.02), north = quantile(lats, 0.98)
            let west = quantile(lons, 0.02), east = quantile(lons, 0.98)
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2),
                span: MKCoordinateSpan(latitudeDelta: max(0.05, (north - south) * 1.1),
                                       longitudeDelta: max(0.05, (east - west) * 1.1)))
            mapView.setRegion(region, animated: false)
        }

        func apply(_ next: TripMapContent, on mapView: MKMapView, reduceMotion: Bool) {
            let previous = content
            content = next
            if previous.routes != next.routes { applyRoutes(next.routes, on: mapView) }
            if previous.marks != next.marks { applyMarks(next.marks, on: mapView) }
            if next.fitRevision != appliedFit {
                appliedFit = next.fitRevision
                fit(on: mapView, animated: RailMotion.cameraAnimated(reduceMotion: reduceMotion))
            }
            frameRegionIfNeeded(on: mapView)
        }

        private func applyRoutes(_ routes: [TripMapContent.Route], on mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays.filter { $0 is RoutePolyline })
            // Alternatives under the chosen route, the chosen route on a white casing.
            var overlays: [RoutePolyline] = []
            for route in routes where !route.isSelected {
                for piece in route.pieces {
                    overlays.append(RoutePolyline(piece, routeID: route.id, style: .alternative))
                }
            }
            for route in routes where route.isSelected {
                for piece in route.pieces where !piece.isConnector {
                    overlays.append(RoutePolyline(piece, routeID: route.id, style: .casing))
                }
                for piece in route.pieces {
                    overlays.append(RoutePolyline(piece, routeID: route.id, style: .selected))
                }
            }
            mapView.addOverlays(overlays, level: .aboveRoads)
        }

        private func applyMarks(_ marks: [TripMapContent.Mark], on mapView: MKMapView) {
            let wanted = Dictionary(marks.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            for (id, annotation) in markAnnotations where wanted[id] != annotation.mark {
                mapView.removeAnnotation(annotation)
                markAnnotations[id] = nil
            }
            for mark in marks where markAnnotations[mark.id] == nil {
                let annotation = MarkAnnotation(mark: mark)
                markAnnotations[mark.id] = annotation
                mapView.addAnnotation(annotation)
            }
            refreshDots(on: mapView)
        }

        private func fit(on mapView: MKMapView, animated: Bool) {
            var rect = MKMapRect.null
            for route in content.routes {
                for piece in route.pieces {
                    for coordinate in piece.coordinates {
                        let point = MKMapPoint(coordinate)
                        rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
                    }
                }
            }
            for mark in content.marks {
                let point = MKMapPoint(mark.coordinate)
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
            }
            guard !rect.isNull else { return }
            if rect.size.width < 1, rect.size.height < 1 {
                // One station: settle close enough that its neighbours are tappable.
                let region = MKCoordinateRegion(
                    center: rect.origin.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
                mapView.setRegion(region, animated: animated)
                return
            }
            let padding = UIEdgeInsets(top: 56, left: 36, bottom: 44, right: 36)
            mapView.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
        }

        // MARK: stations

        private func refreshDots(on mapView: MKMapView) {
            let region = mapView.region
            let isZoomedIn = region.span.latitudeDelta <= TripMapView.stationSpanLimit
            if zoomedIn != isZoomedIn {
                zoomedIn = isZoomedIn
                // Deferred: this can run inside `updateUIView`, where SwiftUI
                // state must not change.
                Task { @MainActor [weak self] in self?.parent?.onZoomChange(isZoomedIn) }
            }
            var wanted: [StationKey: CatalogStation] = [:]
            var coordinates: [StationKey: CLLocationCoordinate2D] = [:]
            if isZoomedIn {
                let marked = Set(content.marks.map(\.station.key))
                let south = region.center.latitude - region.span.latitudeDelta * 0.6
                let north = region.center.latitude + region.span.latitudeDelta * 0.6
                let west = region.center.longitude - region.span.longitudeDelta * 0.6
                let east = region.center.longitude + region.span.longitudeDelta * 0.6
                let low = Self.cell(CLLocationCoordinate2D(latitude: south, longitude: west))
                let high = Self.cell(CLLocationCoordinate2D(latitude: north, longitude: east))
                scan: for x in low.x...high.x {
                    for y in low.y...high.y {
                        for index in grid[Cell(x: x, y: y)] ?? [] {
                            let entry = displayStations[index]
                            let c = entry.coordinate
                            guard c.latitude >= south, c.latitude <= north,
                                  c.longitude >= west, c.longitude <= east,
                                  !marked.contains(entry.station.key) else { continue }
                            wanted[entry.station.key] = entry.station
                            coordinates[entry.station.key] = c
                            if wanted.count >= TripMapView.stationLimit { break scan }
                        }
                    }
                }
            }
            let stale = shownDots.filter { wanted[$0.key] == nil }
            mapView.removeAnnotations(Array(stale.values))
            for key in stale.keys { shownDots[key] = nil }
            var added: [StationDotAnnotation] = []
            for (key, station) in wanted where shownDots[key] == nil {
                let annotation = StationDotAnnotation(station: station, coordinate: coordinates[key]!)
                shownDots[key] = annotation
                added.append(annotation)
            }
            mapView.addAnnotations(added)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            refreshDots(on: mapView)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            frameRegionIfNeeded(on: mapView)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let dot = annotation as? StationDotAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: StationDotView.reuseID, for: dot)
                view.accessibilityLabel = dot.station.name
                view.accessibilityIdentifier = "newTripMapStation-\(dot.station.key.sourceCode)"
                return view
            }
            if let mark = annotation as? MarkAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MarkView.reuseID, for: mark) as? MarkView
                view?.configure(mark.mark)
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            mapView.deselectAnnotation(annotation, animated: false)
            if let dot = annotation as? StationDotAnnotation {
                parent?.onStation(dot.station)
            } else if let mark = annotation as? MarkAnnotation {
                parent?.onStation(mark.mark.station)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? RoutePolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            let lineColor = polyline.colorHex.flatMap(UIColor.init(railHex:)) ?? .systemBlue
            switch polyline.style {
            case .alternative:
                renderer.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.55)
                renderer.lineWidth = 5
            case .casing:
                renderer.strokeColor = .systemBackground
                renderer.lineWidth = 10
            case .selected:
                renderer.strokeColor = lineColor
                renderer.lineWidth = 6
            }
            if polyline.isConnector { renderer.lineDashPattern = [2, 7] }
            return renderer
        }

        // MARK: route taps

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView, recognizer.state == .ended else { return }
            let point = recognizer.location(in: mapView)
            var hit = mapView.hitTest(point, with: nil)
            while let view = hit {
                if view is MKAnnotationView { return }
                hit = view.superview
            }
            var best: (id: String, distance: CGFloat)?
            for route in content.routes where !route.isSelected {
                for piece in route.pieces {
                    let distance = Self.distance(from: point, to: piece.coordinates, in: mapView)
                    if distance < (best?.distance ?? 26) { best = (route.id, distance) }
                }
            }
            if let best {
                parent?.onRoute(best.id)
            } else {
                parent?.onBackground()
            }
        }

        private static func distance(
            from point: CGPoint, to coordinates: [CLLocationCoordinate2D], in mapView: MKMapView
        ) -> CGFloat {
            let points = coordinates.map { mapView.convert($0, toPointTo: mapView) }
            guard var previous = points.first else { return .infinity }
            var best = hypot(point.x - previous.x, point.y - previous.y)
            for next in points.dropFirst() {
                let dx = next.x - previous.x, dy = next.y - previous.y
                let lengthSquared = dx * dx + dy * dy
                var t: CGFloat = 0
                if lengthSquared > 0 {
                    t = max(0, min(1, ((point.x - previous.x) * dx + (point.y - previous.y) * dy) / lengthSquared))
                }
                let x = previous.x + t * dx, y = previous.y + t * dy
                best = min(best, hypot(point.x - x, point.y - y))
                previous = next
            }
            return best
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

// MARK: - overlays and annotations

private final class RoutePolyline: MKPolyline {
    enum Style { case alternative, casing, selected }
    private(set) var routeID = ""
    private(set) var style = Style.alternative
    private(set) var colorHex: String?
    private(set) var isConnector = false

    convenience init(_ piece: TripMapContent.Piece, routeID: String, style: Style) {
        self.init(coordinates: piece.coordinates, count: piece.coordinates.count)
        self.routeID = routeID
        self.style = style
        self.colorHex = piece.colorHex
        self.isConnector = piece.isConnector
    }
}

private final class StationDotAnnotation: NSObject, MKAnnotation {
    let station: CatalogStation
    let coordinate: CLLocationCoordinate2D
    var title: String? { station.name }

    init(station: CatalogStation, coordinate: CLLocationCoordinate2D) {
        self.station = station
        self.coordinate = coordinate
    }
}

private final class MarkAnnotation: NSObject, MKAnnotation {
    let mark: TripMapContent.Mark
    var coordinate: CLLocationCoordinate2D { mark.coordinate }
    var title: String? { mark.station.name }

    init(mark: TripMapContent.Mark) { self.mark = mark }
}

/// A station a finger can choose: a small ring with a 30pt hit target.
private final class StationDotView: MKAnnotationView {
    static let reuseID = "tripStationDot"
    private let ring = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        backgroundColor = .clear
        ring.frame = CGRect(x: 9, y: 9, width: 12, height: 12)
        ring.layer.cornerRadius = 6
        ring.layer.borderWidth = 2.5
        ring.isUserInteractionEnabled = false
        addSubview(ring)
        displayPriority = .defaultHigh
        collisionMode = .circle
        isAccessibilityElement = true
        accessibilityTraits = .button
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: StationDotView, _) in
            view.updateColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateColors() {
        ring.backgroundColor = .systemBackground
        ring.layer.borderColor = UIColor.label.withAlphaComponent(0.75).cgColor
    }
}

/// Origin, via and destination. Required priority so they never collide away.
private final class MarkView: MKMarkerAnnotationView {
    static let reuseID = "tripMark"

    func configure(_ mark: TripMapContent.Mark) {
        displayPriority = .required
        titleVisibility = .visible
        subtitleVisibility = .hidden
        animatesWhenAdded = true
        switch mark.role {
        case .origin:
            markerTintColor = .systemGreen
            glyphImage = UIImage(systemName: "circle.fill")
            glyphText = nil
        case .destination:
            markerTintColor = .systemRed
            glyphImage = UIImage(systemName: "flag.fill")
            glyphText = nil
        case .via(let index):
            markerTintColor = .systemIndigo
            glyphImage = nil
            glyphText = String(index + 1)
        }
        accessibilityLabel = mark.station.name
        accessibilityIdentifier = "newTripMapMark-\(mark.station.key.sourceCode)"
    }
}
