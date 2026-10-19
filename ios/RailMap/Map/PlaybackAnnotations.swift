import MapKit
import RailCore
import SwiftUI

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
