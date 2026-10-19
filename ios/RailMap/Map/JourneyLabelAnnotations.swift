import MapKit
import RailCore
import SwiftUI

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
    let stationID: String?
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
        selected: Bool, stationID: String? = nil
    ) {
        self.coordinate = coordinate
        self.text = text
        self.rawName = rawName
        self.stationCode = stationCode
        self.stationID = stationID
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
