import MapKit
import RailCore
import SwiftUI

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

        // The coordinator has already applied collision placement in
        // importance order; a zoom floor here would hide names with room.
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
