import MapKit
import RailCore
import SwiftUI

// =========================================================================
//  RailMapAnnotations.swift — what MapKit draws at a point, and the views
//  that draw it.
//
//  Ten classes lifted out of `RailMapView.Surface.Coordinator`, which was
//  3,311 lines and is now 2,582. They are moved and not otherwise rewritten:
//  every body below is what it was nested four types deep, dedented by one
//  level, with the single reference that reached back into the coordinator
//  (`uiColor(hex:)`) pointed at `UIColor(railHex:)` instead — which is where
//  that parser lives now for everyone.
//
//  The split is along a real seam rather than a line count. The coordinator
//  decides WHAT the map shows — it reads the stores, rebuilds overlays,
//  answers the delegate, owns the camera. These decide how one point LOOKS
//  once that decision is made, and they know nothing about how it was
//  reached: an `MKAnnotation` here carries the fields its view reads, and
//  the view reads them. Neither half calls the coordinator.
//
//  ## The one thing that changed
//
//  They were `private` members of `Coordinator`, so they were visible to the
//  whole of that 2,500-line class and to nothing else. At file scope they are
//  module-internal, which is wider — Swift has no access level for "this
//  file and one other". Nothing else in the target declares any of these
//  names, and nothing outside this file and `RailMapView.swift` names them.
//  `verify.sh` checks that second half on every run, so a third user has to be
//  added deliberately rather than by accident.
// =========================================================================

final class PlaybackAnnotation: NSObject, MKAnnotation {
    enum Kind { case station, head }
    dynamic var coordinate: CLLocationCoordinate2D
    let title: String?
    let color: UIColor
    let kind: Kind
    var active: Bool
    var pulse: Double
    init(
        coordinate: CLLocationCoordinate2D, title: String?, color: UIColor,
        kind: Kind, active: Bool, pulse: Double
    ) {
        self.coordinate = coordinate
        self.title = title
        self.color = color
        self.kind = kind
        self.active = active
        self.pulse = pulse
    }
}

final class PlaybackAnnotationView: MKAnnotationView {
    func configure(_ annotation: PlaybackAnnotation, scale: CGFloat) {
        self.annotation = annotation
        // Playback beads are multiples of an ordinary station's
        // radius and therefore share the map's one weight ramp.
        let swell = RailStyle.playbackStationScale
            + (RailStyle.playbackStationCurrentScale
                - RailStyle.playbackStationScale) * CGFloat(annotation.pulse)
        let multiple: CGFloat = annotation.kind == .head
            ? RailStyle.playbackHeadScale
            : annotation.pulse > 0
                ? swell
                : annotation.active
                    ? RailStyle.playbackStationDoneScale
                    : RailStyle.playbackStationScale
        let size = max(2, RailStyle.stationRadius * multiple * 2 * scale)
        // `bounds`, not `frame`, and it is the whole of why the beads used to
        // shiver.
        //
        // MapKit places an annotation view by its CENTRE — the projected point
        // plus `centerOffset` — and UIKit's `frame.size` setter keeps the
        // ORIGIN, so every resize moved the centre by half the change and left
        // it there until MapKit's next layout pass pulled it back. That is a
        // per-frame wobble rather than a one-off: this method is called for
        // every frame of a station's 0.45 s arrival pulse, where the bead
        // swells from 11.4 pt to 17.4 pt and decays — a 3 pt hop on arrival
        // and a fraction of a point every frame after it — and again from
        // `restyle` while the chase's zoom eases.
        //
        // `bounds.size` keeps the centre, which is the anchor MapKit is
        // actually driving. The three sibling views here reach the same place
        // by writing `centerOffset` immediately after their own `frame.size`
        // (assigning it re-runs MapKit's placement); this one had no offset to
        // write, so it never got the correction.
        bounds.size = CGSize(width: size, height: size)
        layer.cornerRadius = size / 2
        layer.borderWidth = RailStyle.stationRing * 2 * scale
        layer.borderColor = UIColor.white.cgColor
        backgroundColor = annotation.active
            ? annotation.color : annotation.color.withAlphaComponent(0.25)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = annotation.kind == .head ? 0.28 : 0
        layer.shadowRadius = 4
        canShowCallout = annotation.kind == .station
        // A label on a view VoiceOver cannot reach is a label nobody hears:
        // `MKAnnotationView` is not an accessibility element by default, so
        // the station names baked into the played path were announced by
        // nothing at all.
        isAccessibilityElement = annotation.title?.isEmpty == false
        accessibilityLabel = annotation.title
    }
}

final class StationAnnotation: NSObject, MKAnnotation {
    let station: RailNetworkStore.DrawnStation
    dynamic var coordinate: CLLocationCoordinate2D
    /// The callout header, in the reader's language.
    ///
    /// `RailNetworkStore` builds the popup model off the main actor
    /// with no `StationDisplay.Naming` attached, so `popup.name` is
    /// the package's own spelling; `buildStationPopupModel` in the
    /// web app puts it through `I18N.stationName`. Applied here
    /// instead, which also means a language change is picked up by
    /// the next rebuild rather than needing the package decoded
    /// again.
    let displayName: String
    /// `nameReadingsList` — one line per enabled reading. Empty is
    /// a real answer (every toggle off), and different from the
    /// standalone case the `nameRoma` fallback covers.
    let readings: [String]?
    /// Whether this dot prints its name.
    ///
    /// `DrawnStation.showsLabel` is the election result — which of
    /// the platforms at one complex won the right to print the
    /// place's name — and this is that AND the reader's
    /// `networkStationNames` switch. Both have to be true, and the
    /// zoom floor in `relayout` still applies under them: a switch
    /// can take a name away, never make it appear earlier.
    var showsName: Bool
    /// 1 for an open platform. A closed overlay station uses the same dot
    /// at a lower alpha — never the cross-day diamond.
    let markerAlpha: CGFloat
    var title: String? { displayName }
    var subtitle: String? {
        if let first = readings?.first { return first }
        guard readings == nil, !station.popup.nameRoma.isEmpty else { return nil }
        return station.popup.nameRoma
    }
    init(
        station: RailNetworkStore.DrawnStation,
        displayName: String, showsName: Bool, readings: [String]?,
        markerAlpha: CGFloat = 1,
        displayCoordinate: CLLocationCoordinate2D? = nil
    ) {
        self.station = station
        self.displayName = displayName
        self.showsName = showsName
        self.readings = readings
        self.markerAlpha = markerAlpha
        coordinate = displayCoordinate ?? station.coordinate.clLocation
    }
}

/// One dot a ride puts on a station it called at — a
/// ``StationDisplay/MarkerFeature`` with its record's colours, in the
/// form MapKit wants.
///
/// Every size on it is a FULL-SCALE token; the view multiplies by the
/// one shared factor when it draws.
final class RideStationAnnotation: NSObject, MKAnnotation {
    /// The route-coloured core of an intermediate stop, folded into the dot it
    /// sits in — its own record exists, but not its own annotation.
    struct Core {
        let radius: CGFloat
        let focusScale: CGFloat
        let color: UIColor
    }

    let rideID: String
    /// Circle pixels participate in the route overlay stack; this annotation
    /// still owns the station's touch target and accessibility identity.
    let drawsInOverlay: Bool
    dynamic var coordinate: CLLocationCoordinate2D
    /// Empty on every record that lost the label election, which is
    /// what lets one station reached by twenty rides print its name
    /// once.
    let name: String
    /// The package's own spelling of the place, whatever the
    /// election did to `name`.
    ///
    /// Carried because `name` cannot do this job: most dots lost
    /// the election and are empty, and a tap on one still has to
    /// find the station it stands on. See
    /// ``Coordinator/rideStationCard(name:code:at:)``.
    let rawName: String
    /// `n02_station_code` off the ride's own stop — the station
    /// GROUP, which is the identity `DrawnStation.stationCode`
    /// carries on the network's side of the same station.
    let stationCode: String?
    /// The region whose network a tap on this dot should resolve against —
    /// the ride's own region, so a stop cannot resolve to another country's
    /// platform. See ``Coordinator/rideStationCard(name:code:region:at:)``.
    let region: Region?
    let role: String
    let radius: CGFloat
    let lineWidth: CGFloat
    /// The ordinary call/pass-through marker in the same reader settings.
    /// Endpoints ease back to these tokens as the map becomes regional.
    let ordinaryRadius: CGFloat
    let ordinaryLineWidth: CGFloat
    let focusScale: CGFloat
    let fill: UIColor
    let stroke: UIColor
    let alpha: CGFloat
    let focusBoost: CGFloat
    let selected: Bool
    var core: Core?

    var title: String? { name.isEmpty ? nil : name }

    /// The label tier this role's name is drawn in — the three floors
    /// of `railmap-style.js` §7b, ported into `RailCore`. A role with
    /// no tier is never named.
    var labelTier: StationDisplay.RideLabelTier? {
        StationDisplay.rideLabelTier(role: role)
    }

    private var isEndpoint: Bool { role == "terminal" || role == "xday" }

    /// The endpoint's relative prominence at this map scale. The selected ride
    /// reaches the configured full radius; every other ride stops at a quiet
    /// 4/3 of an ordinary station, and both become ordinary beads in a wide
    /// view. Non-endpoint calls retain their existing selection behavior.
    func drawnRadiusToken(atZoom zoom: Double) -> CGFloat {
        guard isEndpoint else {
            return selected ? radius + focusBoost * focusScale : radius
        }
        let progress = RailStyle.endpointEmphasisProgress(atZoom: zoom)
        let fullRadius = selected
            ? radius
            : ordinaryRadius * RailStyle.riddenEmphasisRatio
        let structuralRadius = ordinaryRadius + (fullRadius - ordinaryRadius) * progress
        let selectionBoost = selected ? focusBoost * focusScale * progress : 0
        return structuralRadius + selectionBoost
    }

    /// The keyline follows the same emphasis ramp as its shape. This matters
    /// most for a cross-day diamond, whose close-view rim is intentionally
    /// heavier but would overwhelm an ordinary-size mark after zooming out.
    func drawnLineWidthToken(atZoom zoom: Double) -> CGFloat {
        guard isEndpoint else { return lineWidth }
        let progress = RailStyle.endpointEmphasisProgress(atZoom: zoom)
        let structural = ordinaryLineWidth + (lineWidth - ordinaryLineWidth) * progress
        return selected && role == "terminal"
            ? structural * (1 + progress)
            : structural
    }

    init(
        rideID: String, drawsInOverlay: Bool,
        coordinate: CLLocationCoordinate2D, name: String,
        rawName: String, stationCode: String?, region: Region?, role: String,
        radius: CGFloat, lineWidth: CGFloat,
        ordinaryRadius: CGFloat, ordinaryLineWidth: CGFloat,
        focusScale: CGFloat,
        fill: UIColor, stroke: UIColor, alpha: CGFloat,
        focusBoost: CGFloat, selected: Bool
    ) {
        self.rideID = rideID
        self.drawsInOverlay = drawsInOverlay
        self.coordinate = coordinate
        self.name = name
        self.rawName = rawName
        self.stationCode = stationCode
        self.region = region
        self.role = role
        self.radius = radius
        self.lineWidth = lineWidth
        self.ordinaryRadius = ordinaryRadius
        self.ordinaryLineWidth = ordinaryLineWidth
        self.focusScale = focusScale
        self.fill = fill
        self.stroke = stroke
        self.alpha = alpha
        self.focusBoost = focusBoost
        self.selected = selected
    }
}

/// One journey's circles, mounted immediately above its own route strokes.
/// Names remain annotations above the entire overlay stack.
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
    private struct Circle {
        let point: MKMapPoint
        let radius: CGFloat
        let lineWidth: CGFloat
        let fill: CGColor
        let stroke: CGColor
        let alpha: CGFloat
        let coreRadius: CGFloat?
        let coreColor: CGColor?
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
    private var circles: [Circle] = []
    private let circleLock = NSLock()
    private var scale: CGFloat = .nan
    private var zoom: Double = .nan
    private var initialDuration: TimeInterval = 0
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

    /// Reuse the overlay per ride, assign its new station list, then call this.
    /// Calling before the first scale sets the new renderer's arrival timing.
    func updateStations(duration: TimeInterval = 0) {
        guard scale.isFinite, zoom.isFinite else {
            initialDuration = duration
            return
        }
        guard let overlay = overlay as? RideStationOverlay else { return }
        let duration = max(0, duration)
        let now = CACurrentMediaTime()
        sampleFades(at: now)
        var occurrences: [String: Int] = [:]
        var desiredKeys: Set<String> = []
        var order: [String] = []
        for station in overlay.stations {
            let base = "\(station.coordinate.latitude)|\(station.coordinate.longitude)|\(station.role)|\(station.rawName)"
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
                    alpha: duration > 0 ? 0 : station.alpha,
                    fade: duration > 0 ? Fade(from: 0, to: station.alpha,
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
        publishCircles()
        updateClock()
    }

    private func sampleFades(at now: TimeInterval) {
        for key in markerOrder {
            guard var marker = markers[key], let fade = marker.fade else { continue }
            let fraction = min(1, max(0, (now - fade.startedAt) / fade.duration))
            marker.alpha = fade.from + (fade.to - fade.from)
                * RailMotion.mapHighlightProgress(fraction)
            if fraction >= 1 {
                if marker.retiring {
                    markers.removeValue(forKey: key)
                    continue
                }
                marker.fade = nil
            }
            markers[key] = marker
        }
        markerOrder.removeAll { markers[$0] == nil }
    }

    private func advance(at now: TimeInterval) {
        sampleFades(at: now)
        publishCircles()
        updateClock()
    }

    private func updateClock() {
        if markers.values.contains(where: { $0.fade != nil }) {
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
        let updated = markerOrder.compactMap { key -> Circle? in
            guard let marker = markers[key] else { return nil }
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
        circles = updated
        circleLock.unlock()
        setNeedsDisplay()
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

/// The NAME a marker won, as its own annotation.
///
/// Split from the dot on purpose. MapLibre never collides circles and
/// collides only symbols, so every dot draws and the names contend for
/// space among themselves; MapKit collides whole annotation VIEWS, so a
/// label riding inside its dot's view would make the dot lose its place
/// to another dot's name — a record of a journey erased by a caption.
///
/// Separated, the mapping is exact: dots are `.required`, and the
/// labels are admitted by `MapLabelCollisionGrid` in
/// `rideLabelTiersInPlacementOrder`, which is the same "a boarding
/// station claims its space before an intermediate stop, which claims
/// it before one merely rolled through" the style's layer order expresses.
final class RideLabelAnnotation: NSObject, MKAnnotation {
    enum Side { case leading, trailing }
    dynamic var coordinate: CLLocationCoordinate2D
    let text: String
    /// The same two keys the dot carries. A caption is a separate
    /// annotation from the dot it names — see below — so a tap that
    /// lands on the NAME must be able to answer with the same card
    /// as a tap on the mark, without going back to the dot for it.
    let rawName: String
    let stationCode: String?
    /// See ``RideStationAnnotation/region``.
    let region: Region?
    let tier: StationDisplay.RideLabelTier
    /// Where the dot ends, so the text can sit beside it rather than
    /// on it. A token, like every other size here.
    let dotRadiusToken: CGFloat
    let selected: Bool
    var side: Side = .trailing
    var title: String? { text }
    init(
        coordinate: CLLocationCoordinate2D, text: String,
        rawName: String, stationCode: String?, region: Region?,
        tier: StationDisplay.RideLabelTier, dotRadiusToken: CGFloat,
        selected: Bool
    ) {
        self.coordinate = coordinate
        self.text = text
        self.rawName = rawName
        self.stationCode = stationCode
        self.region = region
        self.tier = tier
        self.dotRadiusToken = dotRadiusToken
        self.selected = selected
    }
}

/// A ride's origin / destination name card.
final class EndpointLabelAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var spec: MapEndpointLabels.Spec
    var title: String? { spec.mainLine }
    init(spec: MapEndpointLabels.Spec) {
        self.spec = spec
        coordinate = spec.coordinate.clLocation
    }
}

/// One edited stop, keyed by the editor's occurrence id rather than its place.
final class DraftStopAnnotation: NSObject, MKAnnotation {
    let occurrenceID: UUID
    dynamic var coordinate: CLLocationCoordinate2D
    let index: Int
    let name: String
    let stopType: String
    let timeText: String
    let stopTypeLabel: String
    let timeLabel: String
    let stackPosition: Int

    init(
        occurrenceID: UUID, coordinate: CLLocationCoordinate2D, index: Int,
        name: String, stopType: String, timeText: String,
        stopTypeLabel: String, timeLabel: String, stackPosition: Int = 0
    ) {
        self.occurrenceID = occurrenceID
        self.coordinate = coordinate
        self.index = index
        self.name = name
        self.stopType = stopType
        self.timeText = timeText
        self.stopTypeLabel = stopTypeLabel
        self.timeLabel = timeLabel
        self.stackPosition = stackPosition
    }
}

/// Always shows the 1-based index, name, stop type, and time. No callout.
final class DraftStopAnnotationView: MKAnnotationView {
    private let bubble = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bubble.numberOfLines = 4
        bubble.font = .preferredFont(forTextStyle: .caption1)
        bubble.textAlignment = .center
        bubble.textColor = .label
        addSubview(bubble)
        canShowCallout = false
        collisionMode = .none
        backgroundColor = .systemBackground
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ item: DraftStopAnnotation) {
        annotation = item
        bubble.text = "\(item.index)\n\(item.name)\n\(item.stopTypeLabel)\n\(item.timeLabel)"
        let fitted = bubble.sizeThatFits(CGSize(width: 160, height: 220))
        let size = CGSize(width: min(180, ceil(fitted.width) + 16), height: ceil(fitted.height) + 10)
        bounds.size = size
        bubble.frame = bounds.insetBy(dx: 8, dy: 5)
        centerOffset = CGPoint(x: 0, y: -size.height / 2 - CGFloat(item.stackPosition) * (size.height + 4))
        isAccessibilityElement = true
        accessibilityLabel = bubble.text
    }
}

/// Preserve MapKit annotation identity when its complete presentation is
/// unchanged. Buckets support coincident ride markers without merging them.
@MainActor
final class MapAnnotationReconciler {
    private struct Arrival {
        let duration: TimeInterval
        let startedAt: TimeInterval
    }

    private struct Departure {
        let annotation: MKAnnotation
        let token: UUID
        let interactionEnabled: Bool
    }

    private var arrivals: [ObjectIdentifier: Arrival] = [:]
    private var departures: [ObjectIdentifier: Departure] = [:]

    func reconcile(_ desired: [MKAnnotation], replacing old: [MKAnnotation],
                          on mapView: MKMapView,
                          duration: TimeInterval? = nil) -> [MKAnnotation] {
        let duration = max(0, duration ?? 0)
        var available = Dictionary(grouping: old, by: Self.key)
        var exiting = Dictionary(grouping: departures.values, by: { Self.key($0.annotation) })
        var added: [MKAnnotation] = []
        let installed = desired.map { candidate -> MKAnnotation in
            let id = Self.key(candidate)
            if let index = available[id]?.firstIndex(where: { Self.sameContent($0, candidate) }),
               let retained = available[id]?.remove(at: index) {
                updateNameVisibility(of: retained, from: candidate, on: mapView, duration: duration)
                return retained
            }
            // A zoom reversal may ask for a label whose departure has not
            // finished. Reuse that annotation and continue from its visible
            // opacity instead of mounting a second copy at zero.
            if let index = exiting[id]?.firstIndex(where: {
                Self.sameContent($0.annotation, candidate)
            }), let departure = exiting[id]?.remove(at: index) {
                let retained = departure.annotation
                departures.removeValue(forKey: ObjectIdentifier(retained))
                updateNameVisibility(of: retained, from: candidate, on: mapView, duration: duration)
                if let view = mapView.view(for: retained) {
                    view.isUserInteractionEnabled = departure.interactionEnabled
                    fade(view, to: Self.targetAlpha(retained), duration: duration)
                }
                return retained
            }
            if duration > 0, !(candidate is DraftStopAnnotation) {
                arrivals[ObjectIdentifier(candidate)] = Arrival(
                    duration: duration, startedAt: ProcessInfo.processInfo.systemUptime)
            }
            added.append(candidate)
            return candidate
        }
        for removed in available.values.flatMap({ $0 }) {
            retire(removed, on: mapView, duration: duration)
        }
        if !added.isEmpty { mapView.addAnnotations(added) }
        return installed
    }

    /// Call after configuring a dequeued view, before returning it to MapKit.
    /// This also clears opacity left behind by a previous reuse occupant.
    func prepare(_ view: MKAnnotationView) {
        guard let annotation = view.annotation else { return }
        let id = ObjectIdentifier(annotation)
        view.layer.removeAnimation(forKey: "opacity")
        // Departing views can be recycled before their fade completion.
        // Endpoint cards are the one intentionally noninteractive kind.
        view.isUserInteractionEnabled = !(annotation is EndpointLabelAnnotation)
        if departures[id] != nil {
            view.isUserInteractionEnabled = false
            view.alpha = 0
        } else if let arrival = arrivals[id],
           ProcessInfo.processInfo.systemUptime - arrival.startedAt < arrival.duration {
            view.alpha = 0
        } else {
            arrivals.removeValue(forKey: id)
            view.alpha = Self.targetAlpha(annotation)
        }
    }

    /// MapKit has now mounted these views; starting earlier loses the fade.
    func didAdd(_ views: [MKAnnotationView]) {
        for view in views {
            guard let annotation = view.annotation,
                  let arrival = arrivals.removeValue(forKey: ObjectIdentifier(annotation)) else { continue }
            let remaining = arrival.duration
                - (ProcessInfo.processInfo.systemUptime - arrival.startedAt)
            fade(view, to: Self.targetAlpha(annotation), duration: max(0, remaining))
        }
    }

    /// Full map teardown also removes annotations temporarily kept for an exit.
    func removeRetiring(on mapView: MKMapView) {
        let retiring = Array(departures.values)
        departures.removeAll()
        arrivals.removeAll()
        for departure in retiring {
            if let view = mapView.view(for: departure.annotation) {
                view.layer.removeAnimation(forKey: "opacity")
                view.isUserInteractionEnabled = departure.interactionEnabled
            }
        }
        mapView.removeAnnotations(retiring.map(\.annotation))
    }

    private func retire(_ annotation: MKAnnotation, on mapView: MKMapView,
                        duration: TimeInterval) {
        let id = ObjectIdentifier(annotation)
        arrivals.removeValue(forKey: id)
        guard duration > 0, !(annotation is DraftStopAnnotation),
              let view = mapView.view(for: annotation) else {
            mapView.removeAnnotation(annotation)
            return
        }
        let departure = Departure(annotation: annotation, token: UUID(),
                                  interactionEnabled: view.isUserInteractionEnabled)
        departures[id] = departure
        // A disappearing caption must not intercept a tap on the new one.
        view.isUserInteractionEnabled = false
        fade(view, to: 0, duration: duration) { [weak self, weak mapView, weak view] in
            guard let self, self.departures[id]?.token == departure.token else { return }
            self.departures.removeValue(forKey: id)
            if let view, view.annotation.map({ ObjectIdentifier($0) }) == id {
                view.isUserInteractionEnabled = departure.interactionEnabled
            }
            mapView?.removeAnnotation(annotation)
        }
    }

    private func fade(_ view: MKAnnotationView, to alpha: CGFloat,
                      duration: TimeInterval, completion: (() -> Void)? = nil) {
        guard duration > 0 else {
            view.layer.removeAnimation(forKey: "opacity")
            view.alpha = alpha
            completion?()
            return
        }
        UIView.animate(withDuration: duration, delay: 0,
                       options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) {
            view.alpha = alpha
        } completion: { _ in
            completion?()
        }
    }

    private func updateNameVisibility(of retained: MKAnnotation, from candidate: MKAnnotation,
                                      on mapView: MKMapView, duration: TimeInterval) {
        guard let retained = retained as? StationAnnotation,
              let candidate = candidate as? StationAnnotation,
              retained.showsName != candidate.showsName else { return }
        retained.showsName = candidate.showsName
        (mapView.view(for: retained) as? StationAnnotationView)?
            .applyNameVisibility(candidate.showsName, duration: duration)
    }

    private static func targetAlpha(_ annotation: MKAnnotation) -> CGFloat {
        switch annotation {
        case let station as StationAnnotation: return station.markerAlpha
        case let station as RideStationAnnotation: return station.alpha
        default: return 1
        }
    }

    private static func key(_ annotation: MKAnnotation) -> String {
        switch annotation {
        case let item as StationAnnotation:
            return "network|\(item.station.region.rawValue)|\(item.station.lineID)|\(item.station.id)"
        case let item as RideStationAnnotation:
            return "ride|\(item.coordinate.latitude)|\(item.coordinate.longitude)|\(item.role)|\(item.rawName)"
        case let item as RideLabelAnnotation:
            return "label|\(item.coordinate.latitude)|\(item.coordinate.longitude)|\(item.rawName)"
        case let item as EndpointLabelAnnotation:
            return "endpoint|\(item.spec.key)"
        case let item as DraftStopAnnotation:
            return "draft|\(item.occurrenceID)"
        default:
            return "\(ObjectIdentifier(annotation))"
        }
    }

    private static func sameContent(_ lhs: MKAnnotation, _ rhs: MKAnnotation) -> Bool {
        guard lhs.coordinate.latitude == rhs.coordinate.latitude,
              lhs.coordinate.longitude == rhs.coordinate.longitude else { return false }
        switch (lhs, rhs) {
        case let (a as StationAnnotation, b as StationAnnotation):
            return a.station.contentID == b.station.contentID && a.displayName == b.displayName
                && a.readings == b.readings
                && a.markerAlpha == b.markerAlpha
        case let (a as RideLabelAnnotation, b as RideLabelAnnotation):
            return a.text == b.text && a.rawName == b.rawName && a.stationCode == b.stationCode
                && a.tier == b.tier && a.dotRadiusToken == b.dotRadiusToken && a.selected == b.selected
                && a.side == b.side
        case let (a as RideStationAnnotation, b as RideStationAnnotation):
            return a.rideID == b.rideID && a.drawsInOverlay == b.drawsInOverlay
                && a.name == b.name && a.rawName == b.rawName && a.stationCode == b.stationCode
                && a.role == b.role && a.radius == b.radius && a.lineWidth == b.lineWidth
                && a.ordinaryRadius == b.ordinaryRadius && a.ordinaryLineWidth == b.ordinaryLineWidth
                && a.focusScale == b.focusScale && a.fill == b.fill && a.stroke == b.stroke
                && a.alpha == b.alpha && a.focusBoost == b.focusBoost && a.selected == b.selected
                && a.core?.radius == b.core?.radius && a.core?.focusScale == b.core?.focusScale
                && a.core?.color == b.core?.color
        case let (a as EndpointLabelAnnotation, b as EndpointLabelAnnotation):
            // Placement changes as the camera moves; the coordinator updates
            // offset and direction in place after reconciliation.
            return a.spec.trainID == b.spec.trainID && a.spec.name == b.spec.name
                && a.spec.rawName == b.spec.rawName && a.spec.badge == b.spec.badge
                && a.spec.time == b.spec.time && a.spec.readings == b.spec.readings
                && a.spec.width == b.spec.width && a.spec.height == b.spec.height
        case let (a as DraftStopAnnotation, b as DraftStopAnnotation):
            return a.name == b.name && a.stopType == b.stopType && a.timeText == b.timeText
                && a.index == b.index && a.stopTypeLabel == b.stopTypeLabel
                && a.timeLabel == b.timeLabel && a.stackPosition == b.stackPosition
        default:
            return false
        }
    }
}

final class StationAnnotationView: MKAnnotationView {
    private let dot = UIView()
    private let nameLabel = HaloLabel()
    private var station: RailNetworkStore.DrawnStation?
    /// The name election AND the reader's switch, resolved by
    /// `StationAnnotation`. Views are recycled, so this has to be
    /// stored rather than read back off the annotation in
    /// `relayout` — a rescale runs without a fresh `configure`.
    private var showsName = false
    private var fadingNameOut = false
    private var nameTransition: UUID?
    /// The zoom the name is currently sized for. Text does not ride
    /// the railway's scale ramp, but it does ride its own shallower
    /// one, so a rescale has to re-measure it.
    private var zoom: Double = 0
    /// The factor the dot below is currently drawn at. Held so a
    /// rescale is a resize rather than a rebuild.
    private var scale: CGFloat = 1

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        addSubview(dot)
        addSubview(nameLabel)
        // A name is drawn in the map's own label ink with the map's
        // own surface haloed around it — never on a filled plate.
        // See `MapLabelStyle`.
        nameLabel.numberOfLines = 1
        collisionMode = .rectangle
        // No callout. A station's popup is a card in a sheet now —
        // see `StationCardView`, and `mapView(_:didSelect:)` for
        // how a tap gets there. A bubble anchored to the bead had
        // to be small enough not to cover the map it was pointing
        // at, which put a dozen railways' badges in a 280-point
        // box that could not scroll and could not grow with the
        // reader's type size.
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ item: StationAnnotation, scale: CGFloat, zoom: Double) {
        station = item.station
        showsName = item.showsName
        fadingNameOut = false
        nameTransition = nil
        nameLabel.layer.removeAnimation(forKey: "opacity")
        nameLabel.alpha = item.showsName ? 1 : 0
        alpha = item.markerAlpha
        self.scale = scale
        self.zoom = zoom
        let station = item.station
        // Network platforms are stopping stations. Journey pass-throughs
        // render their hollow markers above these network dots.
        let color = UIColor(railHex: station.colorHex) ?? .systemGray
        dot.backgroundColor = color
        dot.layer.borderColor = UIColor.white.cgColor
        // A deliberate deviation, and the only one on this label:
        // `rn-stations-label` draws the package's own spelling,
        // because `railmap.js` is a standalone library with no
        // `I18N` under it. Here the name a station's CALLOUT gives
        // and the name printed beside its bead would then be two
        // different words in Taiwan, Hong Kong, Macao and Korea —
        // whose readings tables exist precisely to name the place
        // in the reader's language. Japan is unaffected: its table
        // annotates rather than replaces, so this is the identity.
        nameLabel.text = item.displayName
        // An interchange is counted in RAILWAYS, which is exactly
        // what the popup's rows already are: `buildPopupModel`
        // dedupes them on displayed operator + name, so several
        // services of one railway leave a station reading as one.
        displayPriority = MapLabelStyle.stationDisplayPriority(
            interchange: station.popup.lines.count > 1,
            isTerminal: station.isTerminal,
            named: item.showsName)
        accessibilityLabel = item.displayName
        relayout()
    }

    /// Name election changes fade only the caption; the station bead keeps
    /// its identity, callout state, and opacity throughout the level change.
    func applyNameVisibility(_ visible: Bool, duration: TimeInterval) {
        guard showsName != visible else { return }
        showsName = visible
        let token = UUID()
        nameTransition = token
        fadingNameOut = !visible && duration > 0
        if let station {
            displayPriority = MapLabelStyle.stationDisplayPriority(
                interchange: station.popup.lines.count > 1,
                isTerminal: station.isTerminal, named: visible)
        }
        relayout()
        guard duration > 0 else {
            nameLabel.layer.removeAnimation(forKey: "opacity")
            nameLabel.alpha = visible ? 1 : 0
            return
        }
        UIView.animate(withDuration: duration, delay: 0,
                       options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) {
            self.nameLabel.alpha = visible ? 1 : 0
        } completion: { [weak self] _ in
            guard let self, self.nameTransition == token else { return }
            self.fadingNameOut = false
            self.nameTransition = nil
            self.relayout()
        }
    }

    func applyScale(_ scale: CGFloat, zoom: Double) {
        guard scale != self.scale || zoom != self.zoom else { return }
        self.scale = scale
        self.zoom = zoom
        relayout()
    }

    /// The dot is one token times the one shared factor, and its route-colour
    /// ring is another — an EIGHTH of the dot, so a ring that kept its
    /// absolute width while the dot shrank cannot swallow the light core it
    /// is there to preserve. A terminal used to be drawn 8 pt against
    /// an ordinary 6 pt; neither number was a token, and the web app
    /// draws every network platform at the same radius.
    private func relayout() {
        guard station != nil else { return }
        let dark = traitCollection.userInterfaceStyle == .dark
        let diameter = max(1, RailStyle.stationDiameter * scale)
        dot.frame = CGRect(
            x: 0, y: 12 - diameter / 2, width: diameter, height: diameter)
        dot.layer.cornerRadius = diameter / 2
        dot.layer.borderWidth = RailStyle.stationRing * scale

        // The coordinator has already applied the importance-specific zoom
        // floor and collision pass; a second floor would hide distant hubs.
        let names = showsName || fadingNameOut
        var width = diameter
        // Nothing below is worth doing for a name that is not drawn
        // and was not drawn a moment ago — and that is the state
        // every bead is in at the zooms where there are hundreds of
        // them. Setting the font alone invalidates a `UILabel`'s
        // intrinsic size, and `sizeThatFits` measures type; over
        // 557 beads that is most of a rescale, spent on a label
        // whose `isHidden` never changed.
        if names || !nameLabel.isHidden {
            let size = MapLabelStyle.stationLabelSize(atZoom: zoom)
            nameLabel.isHidden = !names
            nameLabel.font = MapLabelStyle.font(ofSize: size)
            nameLabel.textColor = MapLabelStyle.ink(dark: dark)
            nameLabel.haloColor = MapLabelStyle.halo(dark: dark)

            let labelSize = names
                ? nameLabel.sizeThatFits(CGSize(width: 180, height: 24)) : .zero
            // `text-radial-offset` is in ems, so the gap grows with
            // the text rather than holding a pixel count while the
            // label around it changes size. The halo needs room of
            // its own on both sides or it is clipped by the label's
            // bounds.
            let gap = size * MapLabelStyle.radialOffsetEm
            let inset = MapLabelStyle.haloWidth
            nameLabel.frame = CGRect(
                x: diameter + gap - inset, y: 1,
                width: labelSize.width + inset * 2, height: 22)
            if names { width = nameLabel.frame.maxX }
        }
        frame.size = CGSize(width: width, height: 24)
        centerOffset = CGPoint(x: width / 2 - diameter / 2, y: 0)
    }

    /// The bead is one of the two things on this map a reader taps, and it is
    /// drawn at six points — a three-point radius, where HIG's iOS control
    /// size is 44×44 and its floor is 28×28. The touch is therefore answered
    /// over ``RailStyle/minimumTouchTarget`` centred on the dot, while the dot
    /// itself keeps its six.
    ///
    /// ## Why this is not `frame`
    ///
    /// Because these bounds are load-bearing three times over: `collisionMode
    /// = .rectangle` measures them, the name label is laid out inside them,
    /// and `centerOffset` is derived from them. Growing the frame to buy a hit
    /// target would move every caption on the map and evict the neighbours of
    /// every bead that kept one — paying for a station that can be tapped with
    /// a station that can no longer be read. `point(inside:)` changes none of
    /// those: it is asked only once a touch is already being routed.
    ///
    /// The existing bounds stay hittable on top of the disc, because the NAME
    /// is part of the same annotation and a reader who taps the word means the
    /// station.
    ///
    /// ## Where two beads are closer together than the target is wide
    ///
    /// Their discs overlap, and UIKit answers such a touch with the topmost
    /// view — which is the same one the eye picks, because it is the one drawn
    /// over the other. That is a worse answer than "the nearest", and a much
    /// better one than the miss a three-point radius produces today.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if bounds.contains(point) { return true }
        let reach = max(RailStyle.minimumTouchTarget, dot.bounds.width) / 2
        // A disc rather than the square it is inscribed in. The corners of a
        // 44-point box are 31 points from the dot, and at that distance a
        // neighbouring bead is usually the one meant.
        return hypot(point.x - dot.frame.midX, point.y - dot.frame.midY) <= reach
    }

}

/// A solid circle for a stop, or a hollow circle for a pass-through.
final class RideStationAnnotationView: MKAnnotationView {
    private let dot = UIView()
    private let core = UIView()
    private var item: RideStationAnnotation?
    private var scale: CGFloat = 1
    private var zoom: Double = 0

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        addSubview(dot)
        dot.addSubview(core)
        core.isUserInteractionEnabled = false
        // Labels use their own collision grid. A visible label must never
        // evict the station dot that anchors it.
        collisionMode = .none
        displayPriority = .required
        // No callout, for the reason the network's beads have none
        // (`StationAnnotationView`): a station's answer is the card
        // in a sheet now — see `mapView(_:didSelect:)`. The bubble
        // could only ever say the name this dot had WON in the
        // label election, so at every station that lost it — which
        // is most of them — a tap opened an empty bubble or did
        // nothing at all.
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ item: RideStationAnnotation, scale: CGFloat, zoom: Double) {
        self.item = item
        self.scale = scale
        self.zoom = zoom
        applyStacking()
        dot.backgroundColor = item.fill
        dot.layer.borderColor = item.stroke.cgColor
        core.backgroundColor = item.core?.color
        core.isHidden = item.core == nil
        dot.isHidden = item.drawsInOverlay
        alpha = item.alpha
        // The dot's own name, not the one it won: a dot that lost
        // the label election draws no caption but is still a
        // station and still opens that station's card, so leaving
        // it unlabelled would put an unnamed button under a
        // VoiceOver reader's finger (§10.2).
        accessibilityLabel = item.rawName.isEmpty ? nil : item.rawName
        relayout()
    }

    func applyScale(_ scale: CGFloat, zoom: Double) {
        guard scale != self.scale || zoom != self.zoom else { return }
        self.scale = scale
        self.zoom = zoom
        relayout()
    }

    func applyStacking() {
        guard let item else { return }
        zPriority = item.selected ? .max : .defaultSelected
        // MapKit assigns its own layer order when mounting and moving views.
        // Restore the selected journey above coincident station dots afterward.
        layer.zPosition = item.selected ? (item.role == "terminal" ? 1_001 : 1_000) : 100
    }

    private func relayout() {
        guard let item else { return }
        let diameter = max(1, item.drawnRadiusToken(atZoom: zoom) * 2 * scale)
        frame.size = CGSize(width: diameter, height: diameter)
        dot.transform = .identity
        dot.frame = CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter))
        dot.layer.cornerRadius = diameter / 2
        dot.layer.borderWidth = item.drawnLineWidthToken(atZoom: zoom) * scale
        centerOffset = .zero
        guard let coreSpec = item.core else { return }
        // The core takes the focus boost in the same proportion the
        // dot does, so the white ring between them survives selection.
        let coreToken = item.selected
            ? coreSpec.radius + item.focusBoost * coreSpec.focusScale
            : coreSpec.radius
        let coreDiameter = max(0.5, min(coreToken * 2 * scale, diameter))
        core.frame = CGRect(
            x: (diameter - coreDiameter) / 2, y: (diameter - coreDiameter) / 2,
            width: coreDiameter, height: coreDiameter)
        core.layer.cornerRadius = coreDiameter / 2
    }

    /// ``StationAnnotationView/point(inside:with:)``'s rule, for the dots on a
    /// ride. The visible circle stays small while its touch target remains
    /// large enough to select without changing its layout.
    ///
    /// A stop that is also under the ride's own stroke is still answered by
    /// the stroke: `handleMapTap` claims that touch before
    /// `mapView(_:didSelect:)` is asked, and one tap gets one answer. What
    /// this reaches is the stop tapped just OFF the line — at a corner, or
    /// where the finger covers the dot and lands beside it.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let reach = max(RailStyle.minimumTouchTarget, bounds.width) / 2
        return hypot(point.x - bounds.midX, point.y - bounds.midY) <= reach
    }
}

/// A marker's elected name, on its own annotation so MapKit's
/// collision pass decides between NAMES rather than between a name and
/// somebody else's dot.
final class RideLabelAnnotationView: MKAnnotationView {
    private let text = HaloLabel()
    private var item: RideLabelAnnotation?
    private var scale: CGFloat = 1
    private var zoom: Double = 0

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        addSubview(text)
        text.numberOfLines = 1
        collisionMode = .rectangle
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ item: RideLabelAnnotation, scale: CGFloat, zoom: Double) {
        self.item = item
        self.scale = scale
        self.zoom = zoom
        text.text = item.text
        accessibilityLabel = item.text
        // `.required`, and it has to be — measured, not chosen.
        //
        // The tier ranking `rideLabelTiersInPlacementOrder` gives
        // is deliberately NOT read here. It was, as a
        // `defaultHigh + tier` display priority, and the next
        // paragraph is why that had to go.
        //
        // An annotation view does not only collide with other
        // annotation views: it competes with the BASEMAP's own
        // labels, and Apple's are dense over a city. At
        // `defaultHigh + tier` (910 of a possible 1000) every one
        // of 85 captions over Osaka was evicted and the map drew a
        // ride with no names on it at all; the two endpoint cards
        // survived only because they were already `.required`.
        // Nothing between 750 and 1000 changed that.
        //
        // Thinning now happens before annotations are added, in the
        // screen-space `MapLabelCollisionGrid`. That pass can respect
        // ride tier order without asking accepted names to compete
        // with unrelated basemap text a second time.
        displayPriority = .required
        applyStacking()
        relayout()
    }

    func applyScale(_ scale: CGFloat, zoom: Double) {
        guard scale != self.scale || zoom != self.zoom else { return }
        self.scale = scale
        self.zoom = zoom
        relayout()
    }

    func applyStacking() {
        // Names stay above circle annotations as well as route overlays,
        // including while a selected journey's enlarged dots are present.
        guard item != nil else { return }
        zPriority = .max
        layer.zPosition = 2_000
    }

    /// Text is not a mark: it rides the tier's own shallow ramp — the
    /// base size at the tier's floor, two points more by z16 — and
    /// never thins with the railway scale. Only its DISTANCE from the
    /// dot follows the scale, because that dot did thin.
    private func relayout() {
        guard let item else { return }
        let dark = traitCollection.userInterfaceStyle == .dark
        let points = CGFloat(
            item.tier.textSize(atZoom: RailStyle.mapLibreZoom(from: zoom)))
        text.font = MapLabelStyle.font(ofSize: points)
        text.textColor = MapLabelStyle.ink(dark: dark)
        text.haloColor = MapLabelStyle.halo(dark: dark)
        let inset = MapLabelStyle.haloWidth
        let size = text.sizeThatFits(CGSize(width: 190, height: 24))
        let height = max(size.height, 16)
        let width = size.width + inset * 2
        text.frame = CGRect(x: 0, y: 0, width: width, height: height)
        frame.size = CGSize(width: width, height: height)
        let distance = item.dotRadiusToken * scale
            + points * MapLabelStyle.radialOffsetEm + width / 2
        centerOffset = CGPoint(
            x: item.side == .trailing ? distance : -distance,
            y: 0)
    }
}

/// The origin / destination card, whose placement is decided in
/// `MapEndpointLabels` and applied here as a centre offset.
final class EndpointLabelView: MKAnnotationView {
    /// One label per piece rather than one attributed string.
    ///
    /// ``HaloLabel`` strokes the surface around the glyphs by
    /// drawing the text twice, and the stroke pass works by
    /// swapping `textColor` — which an attributed string carrying
    /// its own `.foregroundColor` ignores, so the halo would come
    /// out in the ink's colour. Four labels of one colour each
    /// keeps that contract and costs a little arithmetic.
    private let badge = HaloLabel()
    private let name = HaloLabel()
    private let time = HaloLabel()
    private var readings: [HaloLabel] = []

    /// The web app's own per-line estimates, reused as the drawn
    /// line heights so the card occupies exactly the box
    /// `layoutEndpointLabels` placed for it.
    private static let mainLineHeight: CGFloat = 18
    private static let readingLineHeight: CGFloat = 15
    private static let verticalPadding: CGFloat = 6
    private static let pieceGap: CGFloat = 4

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        for label in [badge, name, time] {
            label.numberOfLines = 1
            label.textAlignment = .center
            // The web app draws this one as a filled card
            // (`.station-label`), because HTML text over a raster
            // map has no other way to stay legible. Here it is
            // haloed like every other name on the map instead: a
            // filled plate in dark mode is a black chip punched
            // through the map, and this is the one label big enough
            // for that to be the first thing a reader sees.
            label.backgroundColor = .clear
            addSubview(label)
        }
        badge.font = MapEndpointLabels.badgeFont
        name.font = MapEndpointLabels.font
        time.font = MapEndpointLabels.timeFont
        // The web app's cards are `pointer-events: none` so they never
        // block route picking; the same here.
        isUserInteractionEnabled = false
        collisionMode = .rectangle
        displayPriority = .required
    }

    required init?(coder: NSCoder) { nil }

    func applyStacking() {
        zPriority = .max
        layer.zPosition = 2_001
    }

    func configure(_ item: EndpointLabelAnnotation) {
        applyStacking()
        // Read here, not in `init`: an annotation view is reused
        // across a light/dark flip, and a colour resolved once at
        // construction is a colour from whichever theme happened to
        // be in force the first time this view was made.
        let dark = traitCollection.userInterfaceStyle == .dark
        let ink = MapLabelStyle.ink(dark: dark)
        let muted = MapLabelStyle.mutedInk(dark: dark)
        let halo = MapLabelStyle.halo(dark: dark)
        let spec = item.spec

        badge.text = spec.badge
        name.text = spec.name
        time.text = spec.time
        badge.textColor = ink
        name.textColor = ink
        // The time and the readings QUALIFY the name rather than
        // being it, and with no plate under them the only thing
        // that can say so is weight, size and a second rank of ink.
        time.textColor = muted
        for label in [badge, name, time] { label.haloColor = halo }

        // One label per reading, built to fit: a station can carry
        // kana, romaji and a Chinese reading at once, and the box
        // `buildEndpointLabelSpec` measured already allowed for all
        // three.
        while readings.count < spec.readings.count {
            let label = HaloLabel()
            label.numberOfLines = 1
            label.textAlignment = .center
            label.backgroundColor = .clear
            label.font = MapEndpointLabels.readingFont
            addSubview(label)
            readings.append(label)
        }
        for (index, label) in readings.enumerated() {
            label.isHidden = index >= spec.readings.count
            label.haloColor = halo
            label.textColor = muted
            label.text = index < spec.readings.count ? spec.readings[index] : nil
        }

        accessibilityLabel = spec.mainLine
        layout(spec)
        centerOffset = MapEndpointLabels.centreOffset(for: spec)
    }

    /// Badge and name on one centred row; the time on its own row
    /// under it, and the readings under that — each on its own
    /// line, never bracket-appended, which is the one display rule
    /// `stationNameReadings` exists to spell.
    ///
    /// The time used to ride the name's row, as it does in the web
    /// app. It came down for two reasons: the name is what the card
    /// is FOR and a suffix on its row competes with it, and a row
    /// that grows sideways gets pushed sideways to stay on screen,
    /// which on a phone moves the card off the dot it belongs to.
    private func layout(_ spec: MapEndpointLabels.Spec) {
        let inset = MapLabelStyle.haloWidth
        let bound = CGSize(width: MapEndpointLabels.maxWidth, height: 24)
        var row: [(label: UILabel, width: CGFloat)] = []
        for label in [badge, name] where !(label.text ?? "").isEmpty {
            row.append((label, label.sizeThatFits(bound).width + inset * 2))
        }
        for label in [badge, name, time] {
            label.isHidden = (label.text ?? "").isEmpty
        }
        let rowWidth = row.reduce(CGFloat(0)) { $0 + $1.width }
            + Self.pieceGap * CGFloat(max(row.count - 1, 0))
        let timeWidth = time.isHidden
            ? 0 : time.sizeThatFits(bound).width + inset * 2
        var readingWidths: [CGFloat] = []
        for label in readings where !label.isHidden {
            readingWidths.append(label.sizeThatFits(bound).width + inset * 2)
        }
        let width = max(rowWidth, max(timeWidth, readingWidths.max() ?? 0))
        // The sublines are the time and the readings, in that
        // order; both are drawn at `readingLineHeight`, which is
        // the height `MapEndpointLabels.spec` measured them at.
        let height = Self.verticalPadding + Self.mainLineHeight
            + Self.readingLineHeight
            * CGFloat(readingWidths.count + (time.isHidden ? 0 : 1))
        frame.size = CGSize(width: max(width, 1), height: max(height, 1))

        var x = (width - rowWidth) / 2
        for piece in row {
            piece.label.frame = CGRect(
                x: x, y: Self.verticalPadding / 2,
                width: piece.width, height: Self.mainLineHeight)
            x += piece.width + Self.pieceGap
        }
        var y = Self.verticalPadding / 2 + Self.mainLineHeight
        if !time.isHidden {
            time.frame = CGRect(
                x: (width - timeWidth) / 2, y: y,
                width: timeWidth, height: Self.readingLineHeight)
            y += Self.readingLineHeight
        }
        var index = 0
        for label in readings where !label.isHidden {
            let pieceWidth = readingWidths[index]
            label.frame = CGRect(
                x: (width - pieceWidth) / 2, y: y,
                width: pieceWidth, height: Self.readingLineHeight)
            y += Self.readingLineHeight
            index += 1
        }
    }
}
