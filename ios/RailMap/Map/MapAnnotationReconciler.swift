import MapKit
import RailCore
import RailPresentation
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

    /// The fades started by one reconcile. Their annotations leave MapKit in a
    /// single `removeAnnotations` call once the last fade has finished.
    private final class RetireBatch {
        var pending = 0
        var survivors: [MKAnnotation] = []
    }

    private var arrivals: [ObjectIdentifier: Arrival] = [:]
    private var departures: [ObjectIdentifier: Departure] = [:]

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
        /// Counted in DEBUG builds only; always 0 in Release.
        fileprivate(set) var coordinateChangedCount = 0
    }

    /// Computes annotation identity reuse without touching MapKit or transition state.
    /// Matching is `AnnotationDiff` (RailKit): identity key alone for annotations
    /// that move and restyle in place; a coordinate or style difference on any
    /// other kind still replaces it.
    func plan(_ desired: [MKAnnotation], replacing old: [MKAnnotation]) -> Plan {
        let diff = AnnotationDiff.make(
            old: old.map(Self.item), new: desired.map(Self.item),
            sameStyle: { Self.samePresentation($0, $1) })
        var keptOld: [Int: MKAnnotation] = [:]
        var movedCount = 0
        for kept in diff.kept {
            keptOld[kept.newIndex] = old[kept.oldIndex]
            if kept.moved { movedCount += 1 }
        }
        var exiting = Dictionary(grouping: departures.values, by: { Self.key($0.annotation) })
        var addedCount = 0
        var retainedCount = diff.kept.count
        let retainedOldCount = diff.kept.count
        let resolutions = desired.enumerated().map { index, candidate -> Plan.Resolution in
            if let retained = keptOld[index] {
                return .retained(retained, candidate: candidate)
            }
            // A zoom reversal may ask for a label whose departure has not
            // finished. Reuse that annotation and continue from its visible
            // opacity instead of mounting a second copy at zero.
            let id = Self.key(candidate)
            if let slot = exiting[id]?.firstIndex(where: { Self.resumable($0.annotation, as: candidate) }),
               let departure = exiting[id]?.remove(at: slot) {
                retainedCount += 1
                return .resumed(
                    departure.annotation, candidate: candidate,
                    interactionEnabled: departure.interactionEnabled)
            }
            addedCount += 1
            return .added(candidate)
        }
        let removals = diff.removed.map { old[$0] }
        var plan = Plan(
            resolutions: resolutions, removals: removals,
            addedCount: addedCount, removedCount: removals.count,
            retainedCount: retainedCount, retainedOldCount: retainedOldCount)
#if DEBUG
        plan.coordinateChangedCount = movedCount
#endif
        return plan
    }

    func apply(_ plan: Plan, on mapView: MKMapView,
               duration requestedDuration: TimeInterval? = nil) -> [MKAnnotation] {
        let duration = max(0, requestedDuration ?? 0)
        var added: [MKAnnotation] = []
        let installed = plan.resolutions.map { resolution -> MKAnnotation in
            switch resolution {
            case .retained(let retained, let candidate):
                updateInPlace(retained, from: candidate, on: mapView, duration: duration)
                return retained
            case .resumed(let retained, let candidate, let interactionEnabled):
                departures.removeValue(forKey: ObjectIdentifier(retained))
                updateInPlace(retained, from: candidate, on: mapView, duration: duration)
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
        let batch = RetireBatch()
        for removed in plan.removals {
            if !retire(removed, on: mapView, duration: duration, batch: batch) {
                immediateRemovals.append(removed)
            }
        }
        if !immediateRemovals.isEmpty { mapView.removeAnnotations(immediateRemovals) }
        if !added.isEmpty { mapView.addAnnotations(added) }
        return installed
    }

    func reconcile(_ desired: [MKAnnotation], replacing old: [MKAnnotation],
                   on mapView: MKMapView,
                   duration: TimeInterval? = nil) -> [MKAnnotation] {
        apply(plan(desired, replacing: old), on: mapView, duration: duration)
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
                        duration: TimeInterval, batch: RetireBatch) -> Bool {
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
        batch.pending += 1
        fade(view, to: 0, duration: duration) { [weak self, weak mapView, weak view] in
            batch.pending -= 1
            if let self, self.departures[id]?.token == departure.token {
                self.departures.removeValue(forKey: id)
                if let view, view.annotation.map({ ObjectIdentifier($0) }) == id {
                    view.isUserInteractionEnabled = departure.interactionEnabled
                }
                batch.survivors.append(annotation)
            }
            if batch.pending == 0, !batch.survivors.isEmpty {
                mapView?.removeAnnotations(batch.survivors)
                batch.survivors.removeAll()
            }
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

    /// Brings a kept annotation to the wanted state without remounting it: a
    /// new coordinate moves it (`dynamic`, so MapKit repositions the view),
    /// changed style fields are copied across and pushed to the existing view.
    /// The view is looked up only when something visible changed.
    private func updateInPlace(_ retained: MKAnnotation, from candidate: MKAnnotation,
                               on mapView: MKMapView, duration: TimeInterval) {
        if !Self.sameCoordinate(retained, candidate) {
            switch retained {
            case let station as StationAnnotation: station.coordinate = candidate.coordinate
            case let label as RideLabelAnnotation: label.coordinate = candidate.coordinate
            case let dot as RideStationAnnotation: dot.coordinate = candidate.coordinate
            default: break
            }
        }
        switch (retained, candidate) {
        case let (old as StationAnnotation, new as StationAnnotation):
            if !Self.samePresentation(old, new) {
                let alphaChanged = old.markerAlpha != new.markerAlpha
                old.station = new.station
                old.displayName = new.displayName
                old.readings = new.readings
                old.markerAlpha = new.markerAlpha
                if let view = mapView.view(for: old) as? StationAnnotationView {
                    view.refresh()
                    if alphaChanged { fade(view, to: new.markerAlpha, duration: duration) }
                }
            }
            if old.showsName != new.showsName {
                old.showsName = new.showsName
                (mapView.view(for: old) as? StationAnnotationView)?
                    .applyNameVisibility(new.showsName, duration: duration)
            }
        case let (old as RideLabelAnnotation, new as RideLabelAnnotation):
            if !Self.samePresentation(old, new) {
                old.text = new.text
                old.rawName = new.rawName
                old.stationCode = new.stationCode
                old.tier = new.tier
                old.dotRadiusToken = new.dotRadiusToken
                old.selected = new.selected
                old.side = new.side
                (mapView.view(for: old) as? RideLabelAnnotationView)?.refresh()
            }
        default:
            break
        }
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
            return "ride|\(item.rideID)|\(item.role)|\(item.rawName)|\(item.stationCode ?? "")"
        case let item as RideLabelAnnotation:
            return "label|\(item.rawName)|\(item.stationCode ?? "")|\(item.stationID ?? "")|\(item.region?.rawValue ?? "")"
        case let item as EndpointLabelAnnotation:
            return "endpoint|\(item.spec.key)"
        case let item as DraftStopAnnotation:
            return "draft|\(item.occurrenceID)"
        case let item as TripNoteAnnotation:
            return "tripnote|\(item.trainID)|\(item.noteID)"
        case let item as TripNoteBadgeAnnotation:
            return "tripbadge|\(item.rideID)"
        default:
            return "\(ObjectIdentifier(annotation))"
        }
    }

    private static func item(_ annotation: MKAnnotation) -> AnnotationDiff.Item<MKAnnotation> {
        AnnotationDiff.Item(
            key: key(annotation),
            latitude: annotation.coordinate.latitude, longitude: annotation.coordinate.longitude,
            canMove: movesInPlace(annotation), canRestyle: restylesInPlace(annotation),
            style: annotation)
    }

    /// Kinds whose coordinate is not part of their identity: the level, not
    /// the place, decides where they are drawn.
    private static func movesInPlace(_ annotation: MKAnnotation) -> Bool {
        annotation is StationAnnotation || annotation is RideLabelAnnotation
            || annotation is RideStationAnnotation
    }

    /// Kinds that copy changed style fields onto the kept annotation and
    /// refresh its view. Everything else is replaced when its style changes.
    private static func restylesInPlace(_ annotation: MKAnnotation) -> Bool {
        annotation is StationAnnotation || annotation is RideLabelAnnotation
    }

    private static func resumable(_ departing: MKAnnotation, as candidate: MKAnnotation) -> Bool {
        (restylesInPlace(departing) && restylesInPlace(candidate)) || sameContent(departing, candidate)
    }

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
        case let (a as TripNoteAnnotation, b as TripNoteAnnotation):
            // `sameContent` adds the coordinate, so a moved note is replaced.
            return a.isStation == b.isStation && a.stackPosition == b.stackPosition
                && a.accessibilityText == b.accessibilityText && a.placeSummary == b.placeSummary
        case let (a as TripNoteBadgeAnnotation, b as TripNoteBadgeAnnotation):
            return a.count == b.count && a.accessibilityText == b.accessibilityText
        default:
            return false
        }
    }
}
