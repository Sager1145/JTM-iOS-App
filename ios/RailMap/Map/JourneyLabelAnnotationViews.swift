import MapKit
import RailCore
import SwiftUI

final class RideLabelAnnotationView: MKAnnotationView {
    private let text = HaloLabel()
    private var item: RideLabelAnnotation?
    private var scale: CGFloat = 1
    private var zoom: Double = 0

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        addSubview(text)
        text.numberOfLines = 1
        collisionMode = .rectangle
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ item: RideLabelAnnotation, scale: CGFloat, zoom: Double) {
        self.item = item
        self.scale = scale
        self.zoom = zoom
        text.text = item.text
        accessibilityLabel = item.text
        // `.required`, and it has to be — measured, not chosen.
        //
        // The tier ranking `rideLabelTiersInPlacementOrder` gives
        // is deliberately NOT read here. It was, as a
        // `defaultHigh + tier` display priority, and the next
        // paragraph is why that had to go.
        //
        // An annotation view does not only collide with other
        // annotation views: it competes with the BASEMAP's own
        // labels, and Apple's are dense over a city. At
        // `defaultHigh + tier` (910 of a possible 1000) every one
        // of 85 captions over Osaka was evicted and the map drew a
        // ride with no names on it at all; the two endpoint cards
        // survived only because they were already `.required`.
        // Nothing between 750 and 1000 changed that.
        //
        // Thinning now happens before annotations are added, in the
        // screen-space `MapLabelCollisionGrid`. That pass can respect
        // ride tier order without asking accepted names to compete
        // with unrelated basemap text a second time.
        displayPriority = .required
        applyStacking()
        relayout()
    }

    func applyScale(_ scale: CGFloat, zoom: Double) {
        guard scale != self.scale || zoom != self.zoom else { return }
        self.scale = scale
        self.zoom = zoom
        relayout()
    }

    func applyStacking() {
        // Names stay above circle annotations as well as route overlays,
        // including while a selected journey's enlarged dots are present.
        guard item != nil else { return }
        zPriority = .max
        layer.zPosition = 2_000
    }

    /// Text is not a mark: it rides the tier's own shallow ramp — the
    /// base size at the tier's floor, two points more by z16 — and
    /// never thins with the railway scale. Only its DISTANCE from the
    /// dot follows the scale, because that dot did thin.
    private func relayout() {
        guard let item else { return }
        let dark = traitCollection.userInterfaceStyle == .dark
        let points = CGFloat(
            item.tier.textSize(atZoom: RailStyle.mapLibreZoom(from: zoom)))
        text.font = MapLabelStyle.font(ofSize: points)
        text.textColor = MapLabelStyle.ink(dark: dark)
        text.haloColor = MapLabelStyle.halo(dark: dark)
        let inset = MapLabelStyle.haloWidth
        let size = text.sizeThatFits(CGSize(width: 190, height: 24))
        let height = max(size.height, 16)
        let width = size.width + inset * 2
        text.frame = CGRect(x: 0, y: 0, width: width, height: height)
        frame.size = CGSize(width: width, height: height)
        let distance = item.dotRadiusToken * scale
            + points * MapLabelStyle.radialOffsetEm + width / 2
        centerOffset = CGPoint(
            x: item.side == .trailing ? distance : -distance,
            y: 0)
    }
}

/// The origin / destination card, whose placement is decided in
/// `MapEndpointLabels` and applied here as a centre offset.
final class EndpointLabelView: MKAnnotationView {
    /// One label per piece rather than one attributed string.
    ///
    /// ``HaloLabel`` strokes the surface around the glyphs by
    /// drawing the text twice, and the stroke pass works by
    /// swapping `textColor` — which an attributed string carrying
    /// its own `.foregroundColor` ignores, so the halo would come
    /// out in the ink's colour. Four labels of one colour each
    /// keeps that contract and costs a little arithmetic.
    private let badge = HaloLabel()
    private let name = HaloLabel()
    private let time = HaloLabel()
    private var readings: [HaloLabel] = []

    /// The web app's own per-line estimates, reused as the drawn
    /// line heights so the card occupies exactly the box
    /// `layoutEndpointLabels` placed for it.
    private static let mainLineHeight: CGFloat = 18
    private static let readingLineHeight: CGFloat = 15
    private static let verticalPadding: CGFloat = 6
    private static let pieceGap: CGFloat = 4

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        for label in [badge, name, time] {
            label.numberOfLines = 1
            label.textAlignment = .center
            // The web app draws this one as a filled card
            // (`.station-label`), because HTML text over a raster
            // map has no other way to stay legible. Here it is
            // haloed like every other name on the map instead: a
            // filled plate in dark mode is a black chip punched
            // through the map, and this is the one label big enough
            // for that to be the first thing a reader sees.
            label.backgroundColor = .clear
            addSubview(label)
        }
        badge.font = MapEndpointLabels.badgeFont
        name.font = MapEndpointLabels.font
        time.font = MapEndpointLabels.timeFont
        // The web app's cards are `pointer-events: none` so they never
        // block route picking; the same here.
        isUserInteractionEnabled = false
        collisionMode = .rectangle
        displayPriority = .required
    }

    required init?(coder: NSCoder) { nil }

    func applyStacking() {
        zPriority = .max
        layer.zPosition = 2_001
    }

    func configure(_ item: EndpointLabelAnnotation) {
        applyStacking()
        // Read here, not in `init`: an annotation view is reused
        // across a light/dark flip, and a colour resolved once at
        // construction is a colour from whichever theme happened to
        // be in force the first time this view was made.
        let dark = traitCollection.userInterfaceStyle == .dark
        let ink = MapLabelStyle.ink(dark: dark)
        let muted = MapLabelStyle.mutedInk(dark: dark)
        let halo = MapLabelStyle.halo(dark: dark)
        let spec = item.spec

        badge.text = spec.badge
        name.text = spec.name
        time.text = spec.time
        badge.textColor = ink
        name.textColor = ink
        // The time and the readings QUALIFY the name rather than
        // being it, and with no plate under them the only thing
        // that can say so is weight, size and a second rank of ink.
        time.textColor = muted
        for label in [badge, name, time] { label.haloColor = halo }

        // One label per reading, built to fit: a station can carry
        // kana, romaji and a Chinese reading at once, and the box
        // `buildEndpointLabelSpec` measured already allowed for all
        // three.
        while readings.count < spec.readings.count {
            let label = HaloLabel()
            label.numberOfLines = 1
            label.textAlignment = .center
            label.backgroundColor = .clear
            label.font = MapEndpointLabels.readingFont
            addSubview(label)
            readings.append(label)
        }
        for (index, label) in readings.enumerated() {
            label.isHidden = index >= spec.readings.count
            label.haloColor = halo
            label.textColor = muted
            label.text = index < spec.readings.count ? spec.readings[index] : nil
        }

        accessibilityLabel = spec.mainLine
        layout(spec)
        centerOffset = MapEndpointLabels.centreOffset(for: spec)
    }

    /// Badge and name on one centred row; the time on its own row
    /// under it, and the readings under that — each on its own
    /// line, never bracket-appended, which is the one display rule
    /// `stationNameReadings` exists to spell.
    ///
    /// The time used to ride the name's row, as it does in the web
    /// app. It came down for two reasons: the name is what the card
    /// is FOR and a suffix on its row competes with it, and a row
    /// that grows sideways gets pushed sideways to stay on screen,
    /// which on a phone moves the card off the dot it belongs to.
    private func layout(_ spec: MapEndpointLabels.Spec) {
        let inset = MapLabelStyle.haloWidth
        let bound = CGSize(width: MapEndpointLabels.maxWidth, height: 24)
        var row: [(label: UILabel, width: CGFloat)] = []
        for label in [badge, name] where !(label.text ?? "").isEmpty {
            row.append((label, label.sizeThatFits(bound).width + inset * 2))
        }
        for label in [badge, name, time] {
            label.isHidden = (label.text ?? "").isEmpty
        }
        let rowWidth = row.reduce(CGFloat(0)) { $0 + $1.width }
            + Self.pieceGap * CGFloat(max(row.count - 1, 0))
        let timeWidth = time.isHidden
            ? 0 : time.sizeThatFits(bound).width + inset * 2
        var readingWidths: [CGFloat] = []
        for label in readings where !label.isHidden {
            readingWidths.append(label.sizeThatFits(bound).width + inset * 2)
        }
        let width = max(rowWidth, max(timeWidth, readingWidths.max() ?? 0))
        // The sublines are the time and the readings, in that
        // order; both are drawn at `readingLineHeight`, which is
        // the height `MapEndpointLabels.spec` measured them at.
        let height = Self.verticalPadding + Self.mainLineHeight
            + Self.readingLineHeight
            * CGFloat(readingWidths.count + (time.isHidden ? 0 : 1))
        frame.size = CGSize(width: max(width, 1), height: max(height, 1))

        var x = (width - rowWidth) / 2
        for piece in row {
            piece.label.frame = CGRect(
                x: x, y: Self.verticalPadding / 2,
                width: piece.width, height: Self.mainLineHeight)
            x += piece.width + Self.pieceGap
        }
        var y = Self.verticalPadding / 2 + Self.mainLineHeight
        if !time.isHidden {
            time.frame = CGRect(
                x: (width - timeWidth) / 2, y: y,
                width: timeWidth, height: Self.readingLineHeight)
            y += Self.readingLineHeight
        }
        var index = 0
        for label in readings where !label.isHidden {
            let pieceWidth = readingWidths[index]
            label.frame = CGRect(
                x: (width - pieceWidth) / 2, y: y,
                width: pieceWidth, height: Self.readingLineHeight)
            y += Self.readingLineHeight
            index += 1
        }
    }
}

final class DraftStopAnnotationView: MKAnnotationView {
    private let bubble = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bubble.numberOfLines = 4
        bubble.font = AppTypographyPolicy.preferredFont(forTextStyle: .caption1)
        bubble.textAlignment = .center
        bubble.textColor = .label
        addSubview(bubble)
        canShowCallout = false
        collisionMode = .none
        backgroundColor = .systemBackground
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory,
           let item = annotation as? DraftStopAnnotation {
            configure(item)
        }
    }

    func configure(_ item: DraftStopAnnotation) {
        annotation = item
        bubble.font = AppTypographyPolicy.preferredFont(forTextStyle: .caption1)
        bubble.text = "\(item.index)\n\(item.name)\n\(item.stopTypeLabel)\n\(item.timeLabel)"
        let fitted = bubble.sizeThatFits(CGSize(width: 160, height: 220))
        let size = CGSize(width: min(180, ceil(fitted.width) + 16), height: ceil(fitted.height) + 10)
        bounds.size = size
        bubble.frame = bounds.insetBy(dx: 8, dy: 5)
        centerOffset = CGPoint(x: 0, y: -size.height / 2 - CGFloat(item.stackPosition) * (size.height + 4))
        isAccessibilityElement = true
        accessibilityLabel = bubble.text
    }
}
