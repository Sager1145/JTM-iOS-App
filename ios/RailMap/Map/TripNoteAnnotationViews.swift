import MapKit
import UIKit

/// The amber "!" disc both trip-note marks draw: a white bold "!" on amber,
/// ringed in white on a light map and near-black on a dark one so it reads
/// over route ink and basemap alike.
private final class TripNoteDisc: UIView {
    static let diameter: CGFloat = 26
    private let glyph = UILabel()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        layer.cornerRadius = Self.diameter / 2
        layer.borderWidth = 2
        glyph.text = "!"
        glyph.textAlignment = .center
        // Fixed size: the disc is a map symbol, not text that reflows.
        glyph.font = .systemFont(ofSize: 17, weight: .heavy)
        glyph.frame = bounds
        addSubview(glyph)
        isUserInteractionEnabled = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 1.5
        layer.shadowOffset = CGSize(width: 0, height: 0.5)
    }

    required init?(coder: NSCoder) { nil }

    static func amber(dark: Bool) -> UIColor {
        dark ? UIColor(red: 1.00, green: 0.66, blue: 0.10, alpha: 1)
             : UIColor(red: 0.93, green: 0.56, blue: 0.00, alpha: 1)
    }

    /// Colours are resolved here, from the view's current traits, never in
    /// `init`: a reused view may move between appearances.
    func apply(dark: Bool) {
        backgroundColor = Self.amber(dark: dark)
        glyph.textColor = .white
        layer.borderColor = (dark ? UIColor(white: 0.08, alpha: 1) : UIColor.white).cgColor
    }
}

/// One note of the selected trip. A station note sits beside its station's
/// bead (above and to the right, stacked upwards when several share the
/// stop); an interval note is centred on its point of the line.
final class TripNoteMarkerView: MKAnnotationView {
    /// The touch target: at least 44 pt whatever the disc's size.
    static let hitSize: CGFloat = 44
    /// How far a station note's target stays from the bead's centre, in
    /// points on both axes: clear of a selected stop bead's radius.
    static let beadClearance: CGFloat = 8
    private let disc = TripNoteDisc()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.hitSize, height: Self.hitSize)
        disc.center = CGPoint(x: Self.hitSize / 2, y: Self.hitSize / 2)
        addSubview(disc)
        canShowCallout = false
        collisionMode = .circle
        displayPriority = .required
        isAccessibilityElement = true
        accessibilityIdentifier = "tripNoteMarker"
        accessibilityTraits = .button
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TripNoteMarkerView, _) in
            view.disc.apply(dark: view.traitCollection.userInterfaceStyle == .dark)
        }
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ item: TripNoteAnnotation) {
        annotation = item
        disc.apply(dark: traitCollection.userInterfaceStyle == .dark)
        accessibilityLabel = item.accessibilityText
        accessibilityValue = item.placeSummary
        // Above the trip's own station names, which stack at 2 000.
        zPriority = .max
        layer.zPosition = 2_100
        let middle = Self.hitSize / 2
        if item.isStation {
            // The disc sits up and to the right of the bead; the 44 pt target
            // is pushed further that way so its lower-left corner stops
            // `inset` short of the bead and a tap on the bead still selects
            // the station.
            let step = TripNoteDisc.diameter + 2
            let disc = CGPoint(x: 18, y: -18 - CGFloat(item.stackPosition) * step)
            let inset = Self.beadClearance
            let shift = max(0, middle + inset - disc.x)
            centerOffset = CGPoint(x: disc.x + shift, y: disc.y - shift)
            self.disc.center = CGPoint(x: middle - shift, y: middle + shift)
        } else {
            centerOffset = .zero
            disc.center = CGPoint(x: middle, y: middle)
        }
    }
}

/// One trip's notes on the overview map: the same disc, with the count in a
/// small pill at its top-right.
final class TripNoteBadgeView: MKAnnotationView {
    private let disc = TripNoteDisc()
    private let pill = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: TripNoteMarkerView.hitSize, height: TripNoteMarkerView.hitSize)
        disc.center = CGPoint(x: bounds.midX, y: bounds.midY)
        addSubview(disc)
        pill.textAlignment = .center
        pill.font = .systemFont(ofSize: 11, weight: .bold)
        pill.layer.masksToBounds = true
        pill.layer.borderWidth = 1.5
        addSubview(pill)
        canShowCallout = false
        collisionMode = .circle
        // Below the endpoint cards (`.required`), above ordinary basemap text.
        displayPriority = .defaultHigh
        isAccessibilityElement = true
        accessibilityIdentifier = "tripNoteBadge"
        accessibilityTraits = .button
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TripNoteBadgeView, _) in
            view.applyColors()
        }
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ item: TripNoteBadgeAnnotation) {
        annotation = item
        pill.text = item.count > 99 ? "99+" : "\(item.count)"
        let fitted = pill.sizeThatFits(CGSize(width: 60, height: 16))
        let height: CGFloat = 16
        let width = max(height, ceil(fitted.width) + 8)
        pill.frame = CGRect(x: disc.frame.maxX - width / 2 - 2, y: disc.frame.minY - height / 2 + 2,
                            width: width, height: height)
        pill.layer.cornerRadius = height / 2
        applyColors()
        accessibilityLabel = item.accessibilityText
        centerOffset = .zero
    }

    private func applyColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        disc.apply(dark: dark)
        pill.backgroundColor = dark ? UIColor(white: 0.95, alpha: 1) : UIColor(white: 0.12, alpha: 1)
        pill.textColor = dark ? UIColor(white: 0.08, alpha: 1) : .white
        pill.layer.borderColor = (dark ? UIColor(white: 0.08, alpha: 1) : UIColor.white).cgColor
    }
}
