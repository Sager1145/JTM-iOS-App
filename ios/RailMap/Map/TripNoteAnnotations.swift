import MapKit
import RailCore

/// What the map needs to know about trip notes, as a cheap value: counts for
/// every trip, the notes themselves only for the selected one.
struct TripNoteMapSnapshot: Equatable {
    var selectedTrainID: String?
    var selectedNotes: [TripNote] = []
    /// The selected trip's own stops, from the itinerary rather than its
    /// drawn ride: a place pick offers them even before the route is drawn,
    /// and whatever scope the list is in.
    var selectedStops: [Stop] = []
    /// The selected trip's region code, for naming those stops.
    var selectedRegion: String?
    /// Trip id → number of notes, for trips with at least one.
    var noteCounts: [String: Int] = [:]

    init(selectedTrainID: String? = nil, selectedNotes: [TripNote] = [], selectedStops: [Stop] = [],
         selectedRegion: String? = nil, noteCounts: [String: Int] = [:]) {
        self.selectedTrainID = selectedTrainID
        self.selectedNotes = selectedNotes
        self.selectedStops = selectedStops
        self.selectedRegion = selectedRegion
        self.noteCounts = noteCounts
    }

    init(trains: [Train], selectedTrainID: String?) {
        var counts: [String: Int] = [:]
        var selected: Train?
        for train in trains {
            if train.id == selectedTrainID, selected == nil { selected = train }
            guard let notes = train.tripNotes, !notes.isEmpty else { continue }
            counts[train.id] = notes.count
        }
        self.init(selectedTrainID: selectedTrainID, selectedNotes: selected?.tripNotes ?? [],
                  selectedStops: selected?.stops ?? [], selectedRegion: selected?.region, noteCounts: counts)
    }
}

/// What the trip-note pick's centre pin is over, as the overlay draws it.
struct TripNotePickFeedback: Equatable {
    /// The anchor Confirm would save; nil while the pin is off the line.
    var anchor: TripNoteAnchor?
    /// "At A" / "A → B", localized; nil while off the line.
    var summary: String?
    /// The pin's tip, in the map view's coordinates.
    var pinPoint: CGPoint
    /// Distance from the map's bottom edge to the bottom bar.
    var barBottom: CGFloat
    /// Top safe-area inset of the map, for the banner.
    var topInset: CGFloat
}

/// One note's "!" on the selected trip.
final class TripNoteAnnotation: NSObject, MKAnnotation {
    let trainID: String
    let noteID: String
    dynamic var coordinate: CLLocationCoordinate2D
    /// At a stop (drawn beside its bead) rather than along an interval.
    let isStation: Bool
    /// Order among notes at the same stop.
    let stackPosition: Int
    /// Localized "Note: …" for VoiceOver.
    let accessibilityText: String
    /// Localized place summary ("At A", "A → B", …), the marker's value.
    let placeSummary: String
    var title: String? { accessibilityText }

    init(trainID: String, noteID: String, coordinate: CLLocationCoordinate2D, isStation: Bool,
         stackPosition: Int, accessibilityText: String, placeSummary: String) {
        self.trainID = trainID
        self.noteID = noteID
        self.coordinate = coordinate
        self.isStation = isStation
        self.stackPosition = stackPosition
        self.accessibilityText = accessibilityText
        self.placeSummary = placeSummary
    }
}

/// One trip's note count on the overview map. Tapping it selects the trip.
final class TripNoteBadgeAnnotation: NSObject, MKAnnotation {
    let rideID: String
    let count: Int
    dynamic var coordinate: CLLocationCoordinate2D
    /// Localized "Notes: n" for VoiceOver.
    let accessibilityText: String
    var title: String? { accessibilityText }

    init(rideID: String, count: Int, coordinate: CLLocationCoordinate2D, accessibilityText: String) {
        self.rideID = rideID
        self.count = count
        self.coordinate = coordinate
        self.accessibilityText = accessibilityText
    }
}
