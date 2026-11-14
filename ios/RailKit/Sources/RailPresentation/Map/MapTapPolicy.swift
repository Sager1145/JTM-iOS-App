import Foundation

/// What is under the finger when the map is tapped, as the map layer measured it.
public struct MapTapHits: Equatable, Sendable {
    /// A mounted annotation view (draft pin, note, badge, station bead, trip dot) is under the finger.
    public var annotationViewUnderFinger: Bool
    /// The finger is on a station dot of the trip that is already selected.
    public var selectedTripStationDot: Bool
    /// Trips within ``MapTapPolicy/tripReach``; a dot of an unselected trip counts as that trip.
    public var tripIDsInReach: [String]
    /// A station annotation is within ``MapTapPolicy/stationReach``.
    public var stationAnnotationInReach: Bool
    /// Network lines within ``MapTapPolicy/networkLineReach``.
    public var networkLineIDsInReach: [String]
    /// A trip card is open. It does not change an answer: several trips show the chooser either way.
    public var tripCardOpen: Bool
    /// 1 for a single tap, 2 for the second tap of a double tap.
    public var tapCount: Int

    public init(
        annotationViewUnderFinger: Bool = false, selectedTripStationDot: Bool = false,
        tripIDsInReach: [String] = [], stationAnnotationInReach: Bool = false,
        networkLineIDsInReach: [String] = [], tripCardOpen: Bool = false, tapCount: Int = 1
    ) {
        self.annotationViewUnderFinger = annotationViewUnderFinger
        self.selectedTripStationDot = selectedTripStationDot
        self.tripIDsInReach = tripIDsInReach
        self.stationAnnotationInReach = stationAnnotationInReach
        self.networkLineIDsInReach = networkLineIDsInReach
        self.tripCardOpen = tripCardOpen
        self.tapCount = tapCount
    }
}

/// How the map answers a tap.
public enum MapTapAnswer: Equatable, Sendable {
    /// The annotation view under the finger handles it.
    case annotation
    /// A station dot of the selected trip: open the station card.
    case stationCard
    case pickTrip(String)
    case tripChooser([String])
    /// A station annotation: open the station card.
    case station
    case lineCard(String)
    case lineChooser([String])
    /// Empty map: clear the selection, but only after the double-tap window has passed.
    case clearWhenSettled
    case ignore

    /// Answers that act at once, without waiting for the double-tap window.
    public var answersImmediately: Bool {
        switch self {
        case .clearWhenSettled, .ignore: false
        default: true
        }
    }
}

/// The map's tap rules, kept pure so every edge is testable and the real tap
/// and the test-control `tapMap` command share one answer.
public enum MapTapPolicy {
    /// View points around the finger within which a trip line or trip dot counts.
    public static let tripReach: Double = 18
    /// View points within which a station annotation counts.
    public static let stationReach: Double = 33
    /// View points within which a network line counts.
    public static let networkLineReach: Double = 12

    /// The second tap of a double tap is never answered as a tap.
    public static func receives(tapCount: Int) -> Bool { tapCount <= 1 }

    /// Priority: annotation view, selected trip's station dot, trips, station
    /// annotation, network lines, empty.
    public static func answer(_ hits: MapTapHits) -> MapTapAnswer {
        guard receives(tapCount: hits.tapCount) else { return .ignore }
        if hits.annotationViewUnderFinger { return .annotation }
        if hits.selectedTripStationDot { return .stationCard }
        let trips = unique(hits.tripIDsInReach)
        if trips.count == 1 { return .pickTrip(trips[0]) }
        if trips.count > 1 { return .tripChooser(trips) }
        if hits.stationAnnotationInReach { return .station }
        let lines = unique(hits.networkLineIDsInReach)
        if lines.count == 1 { return .lineCard(lines[0]) }
        if lines.count > 1 { return .lineChooser(lines) }
        return .clearWhenSettled
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
