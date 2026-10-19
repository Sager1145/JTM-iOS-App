import MapKit
import RailCore
import SwiftUI

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
    /// Registry station id when the ride stop has one. Nil keeps the code-then-name card.
    let stationID: String?
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
        stationID: String? = nil,
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
        self.stationID = stationID
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
