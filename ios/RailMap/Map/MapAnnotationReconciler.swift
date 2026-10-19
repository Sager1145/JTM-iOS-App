import MapKit
import RailCore
import SwiftUI

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

#if DEBUG
    struct Plan {
        fileprivate enum Resolution {
            case retained(MKAnnotation, candidate: MKAnnotation)
            case resumed(MKAnnotation, candidate: MKAnnotation, interactionEnabled: Bool)
            case added(MKAnnotation)
        }

        fileprivate let resolutions: [Resolution]
        fileprivate let removals: [MKAnnotation]
        let addedCount: Int
        let removedCount: Int
        let retainedCount: Int
        let retainedOldCount: Int
        let coordinateChangedCount: Int
    }

    /// Computes annotation identity reuse without touching MapKit or transition state.
    func plan(_ desired: [MKAnnotation], replacing old: [MKAnnotation]) -> Plan {
        var available = Dictionary(grouping: old, by: Self.key)
        let oldByCoordinateIdentity = Dictionary(grouping: old, by: Self.keyIgnoringCoordinate)
        var exiting = Dictionary(grouping: departures.values, by: { Self.key($0.annotation) })
        var addedCount = 0
        var retainedCount = 0
        var retainedOldCount = 0
        var coordinateChangedCount = 0
        let resolutions = desired.map { candidate -> Plan.Resolution in
            let id = Self.key(candidate)
            if let index = available[id]?.firstIndex(where: { Self.sameContent($0, candidate) }),
               let retained = available[id]?.remove(at: index) {
                retainedCount += 1
                retainedOldCount += 1
                return .retained(retained, candidate: candidate)
            }
            if oldByCoordinateIdentity[Self.keyIgnoringCoordinate(candidate)]?.contains(where: {
                !Self.sameCoordinate($0, candidate) && Self.samePresentation($0, candidate)
            }) == true {
                coordinateChangedCount += 1
            }
            // A zoom reversal may ask for a label whose departure has not
            // finished. Reuse that annotation and continue from its visible
            // opacity instead of mounting a second copy at zero.
            if let index = exiting[id]?.firstIndex(where: {
                Self.sameContent($0.annotation, candidate)
            }), let departure = exiting[id]?.remove(at: index) {
                retainedCount += 1
                return .resumed(
                    departure.annotation, candidate: candidate,
                    interactionEnabled: departure.interactionEnabled)
            }
            addedCount += 1
            return .added(candidate)
        }
        let removals = available.values.flatMap { $0 }
        return Plan(
            resolutions: resolutions, removals: removals,
            addedCount: addedCount, removedCount: removals.count,
            retainedCount: retainedCount, retainedOldCount: retainedOldCount,
            coordinateChangedCount: coordinateChangedCount)
    }

    func apply(_ plan: Plan, on mapView: MKMapView,
               duration requestedDuration: TimeInterval? = nil) -> [MKAnnotation] {
        let duration = max(0, requestedDuration ?? 0)
        var added: [MKAnnotation] = []
        let installed = plan.resolutions.map { resolution -> MKAnnotation in
            switch resolution {
            case .retained(let retained, let candidate):
                updateNameVisibility(of: retained, from: candidate, on: mapView, duration: duration)
                return retained
            case .resumed(let retained, let candidate, let interactionEnabled):
                departures.removeValue(forKey: ObjectIdentifier(retained))
                updateNameVisibility(of: retained, from: candidate, on: mapView, duration: duration)
                if let view = mapView.view(for: retained) {
                    view.isUserInteractionEnabled = interactionEnabled
                    fade(view, to: Self.targetAlpha(retained), duration: duration)
                }
                return retained
            case .added(let candidate):
                if duration > 0, !(candidate is DraftStopAnnotation) {
                    arrivals[ObjectIdentifier(candidate)] = Arrival(
                        duration: duration, startedAt: ProcessInfo.processInfo.systemUptime)
                }
                added.append(candidate)
                return candidate
            }
        }
        // One MapKit update for every annotation that is not riding out a fade.
        var immediateRemovals: [MKAnnotation] = []
        for removed in plan.removals {
            if !retire(removed, on: mapView, duration: duration) {
                immediateRemovals.append(removed)
            }
        }
        if !immediateRemovals.isEmpty { mapView.removeAnnotations(immediateRemovals) }
        if !added.isEmpty { mapView.addAnnotations(added) }
        return installed
    }
#endif

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
        // One MapKit update for every annotation that is not riding out a fade.
        var immediateRemovals: [MKAnnotation] = []
        for removed in available.values.flatMap({ $0 }) {
            if !retire(removed, on: mapView, duration: duration) {
                immediateRemovals.append(removed)
            }
        }
        if !immediateRemovals.isEmpty { mapView.removeAnnotations(immediateRemovals) }
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

    /// Starts an exit fade when the view can animate out.
    /// Returns false when the caller should remove the annotation in this reconcile.
    private func retire(_ annotation: MKAnnotation, on mapView: MKMapView,
                        duration: TimeInterval) -> Bool {
        let id = ObjectIdentifier(annotation)
        arrivals.removeValue(forKey: id)
        guard duration > 0, !(annotation is DraftStopAnnotation),
              let view = mapView.view(for: annotation) else {
            return false
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
        return true
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

#if DEBUG
    private static func keyIgnoringCoordinate(_ annotation: MKAnnotation) -> String {
        switch annotation {
        case let item as RideStationAnnotation:
            return "ride|\(item.role)|\(item.rawName)"
        case let item as RideLabelAnnotation:
            return "label|\(item.rawName)"
        default:
            return key(annotation)
        }
    }
#endif

    private static func sameContent(_ lhs: MKAnnotation, _ rhs: MKAnnotation) -> Bool {
        sameCoordinate(lhs, rhs) && samePresentation(lhs, rhs)
    }

    private static func sameCoordinate(_ lhs: MKAnnotation, _ rhs: MKAnnotation) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    private static func samePresentation(_ lhs: MKAnnotation, _ rhs: MKAnnotation) -> Bool {
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
