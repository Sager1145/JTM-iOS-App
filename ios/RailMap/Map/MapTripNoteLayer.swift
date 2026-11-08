import MapKit
import RailCore

/// Trip notes on the map: one "!" per note of the selected trip, or — with no
/// trip selected — one count badge per trip that has notes. A trip without
/// notes draws nothing at all.
///
/// Called on every `updateUIView`, which a sheet drag makes every frame, so
/// ``render(_:rides:selectedTrainID:routesDrawn:playbackActive:dateScope:language:text:reconciler:on:)``
/// returns before any geometry work unless one of its inputs moved. The ride
/// array is compared by buffer identity (the coordinator replaces it only when
/// the deck changed), never element by element.
@MainActor
final class MapTripNoteLayer {
    /// The words the marks carry, resolved by the coordinator's localization.
    struct Text {
        /// VoiceOver label of a note's "!".
        var marker: (TripNote) -> String = { $0.category.isEmpty ? $0.text : $0.category }
        /// Place summary of a note on its ride ("At A", "A → B").
        var place: (TripNote, RiddenRouteStore.DrawnRide) -> String = { _, _ in "" }
        /// VoiceOver label of a trip's badge.
        var count: (Int) -> String = { "\($0)" }
    }

    private struct Key: Equatable {
        var snapshot: TripNoteMapSnapshot
        var selectedTrainID: String?
        var routesDrawn: Bool
        var playbackActive: Bool
        var dateScope: MapDateScope.Scope
        var language: String?
    }

    private var lastKey: Key?
    private var lastRides: [RiddenRouteStore.DrawnRide] = []
    /// Badge points per ride, valid while the ride's geometry digest holds.
    private var badgeCache: [String: (digest: Int, coordinate: Coordinate?)] = [:]
    private(set) var annotations: [MKAnnotation] = []

    func render(
        _ snapshot: TripNoteMapSnapshot, rides: [RiddenRouteStore.DrawnRide], selectedTrainID: String?,
        routesDrawn: Bool, playbackActive: Bool, dateScope: MapDateScope.Scope, language: String?,
        text: () -> Text, reconciler: MapAnnotationReconciler, on mapView: MKMapView
    ) {
        let key = Key(snapshot: snapshot, selectedTrainID: selectedTrainID, routesDrawn: routesDrawn,
                      playbackActive: playbackActive, dateScope: dateScope, language: language)
        let ridesChanged = !ArrayGeneration.same(rides, lastRides)
        guard ridesChanged || key != lastKey else { return }
        lastKey = key
        lastRides = rides
        let desired = Self.annotations(
            snapshot, rides: rides, selectedTrainID: selectedTrainID, routesDrawn: routesDrawn,
            playbackActive: playbackActive,
            isInScope: { MapDateScope.inScope($0.daySpan, dateScope) },
            badgeCoordinate: badgeCoordinate(of:), text: text())
        annotations = reconciler.reconcile(desired, replacing: annotations, on: mapView)
    }

    private func badgeCoordinate(of ride: RiddenRouteStore.DrawnRide) -> Coordinate? {
        if let cached = badgeCache[ride.id], cached.digest == ride.geometryDigest { return cached.coordinate }
        let coordinate = TripNoteGeometry.badgeCoordinate(of: ride)
        badgeCache[ride.id] = (ride.geometryDigest, coordinate)
        return coordinate
    }

    /// The annotations the map should show. Pure, for tests.
    static func annotations(
        _ snapshot: TripNoteMapSnapshot, rides: [RiddenRouteStore.DrawnRide], selectedTrainID: String?,
        routesDrawn: Bool, playbackActive: Bool,
        isInScope: (RiddenRouteStore.DrawnRide) -> Bool = { _ in true },
        badgeCoordinate: (RiddenRouteStore.DrawnRide) -> Coordinate? = TripNoteGeometry.badgeCoordinate(of:),
        text: Text = Text()
    ) -> [MKAnnotation] {
        guard routesDrawn, !playbackActive else { return [] }
        if let selectedTrainID {
            // Any selection hides every badge; only the selected trip's own
            // notes are drawn, and only once the snapshot is about it.
            guard snapshot.selectedTrainID == selectedTrainID, !snapshot.selectedNotes.isEmpty,
                  let ride = rides.first(where: { $0.id == selectedTrainID }) else { return [] }
            let notes = Dictionary(snapshot.selectedNotes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return TripNoteGeometry.place(snapshot.selectedNotes, on: ride).compactMap { placed in
                guard let note = notes[placed.noteID] else { return nil }
                return TripNoteAnnotation(
                    trainID: selectedTrainID, noteID: placed.noteID, coordinate: placed.coordinate.clLocation,
                    isStation: placed.isStation, stackPosition: placed.stackPosition,
                    accessibilityText: text.marker(note), placeSummary: text.place(note, ride))
            }
        }
        guard !snapshot.noteCounts.isEmpty else { return [] }
        var seen = Set<String>()
        return rides.compactMap { ride -> MKAnnotation? in
            guard let count = snapshot.noteCounts[ride.id], count > 0, seen.insert(ride.id).inserted,
                  ride.visible, isInScope(ride), let point = badgeCoordinate(ride) else { return nil }
            return TripNoteBadgeAnnotation(rideID: ride.id, count: count, coordinate: point.clLocation,
                                           accessibilityText: text.count(count))
        }
    }
}
